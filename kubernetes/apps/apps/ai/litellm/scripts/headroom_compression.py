"""Session-aware Headroom compression after LiteLLM resolves a deployment."""

import copy
import hashlib
import json
import os
import time
from contextvars import ContextVar

import httpx

from litellm._logging import verbose_proxy_logger
from litellm.integrations.custom_logger import CustomLogger
from litellm.llms import get_guardrail_translation_mapping
from litellm.llms.custom_httpx.http_handler import AsyncHTTPHandler
from litellm.proxy.guardrails.guardrail_hooks.headroom.headroom import (
    HeadroomGuardrail,
    _flatten_messages_for_compression,
    _restore_content_shapes,
)
from litellm.types.utils import CallTypes

_CALLER = "_headroom_caller"
_CONTEXT = ContextVar("headroom_compression_context", default=None)
_SUPPORTED = {"completion", "acompletion", "responses", "aresponses", "anthropic_messages"}


def _digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()


def _metadata(data):
    params = data.get("litellm_params") or {}
    return [
        value for value in (
            data.get("metadata"), data.get("litellm_metadata"), params.get("metadata")
        ) if isinstance(value, dict)
    ]


class _SessionClient:
    def __init__(self, client):
        self.client = client

    async def post(self, **kwargs):
        context = _CONTEXT.get()
        body = {**kwargs["json"], "config": {
            "session_id": context["session_id"],
            "protect_recent": 0,
        }}
        if context.get("token_budget"):
            body["token_budget"] = context["token_budget"]
        return await self.client.post(**{**kwargs, "json": body})


def _protect_instructions(messages):
    protected = copy.deepcopy(messages)
    for message in protected:
        if message.get("role") in {"tool", "function"}:
            # Do not flatten away a client's explicit cache-control blocks.
            if not _cache_marked(message):
                message.update(_flatten_messages_for_compression([message])[0])
            continue
        content = message.get("content")
        if isinstance(content, str):
            # Headroom protects assistant text blocks, whereas plain assistant
            # strings can enter the compression path.
            message["content"] = [{"type": "text", "text": content}]
    return protected


def _cache_marked(value):
    if isinstance(value, dict):
        return "cache_control" in value or any(_cache_marked(item) for item in value.values())
    if isinstance(value, list):
        return any(_cache_marked(item) for item in value)
    return False


class _SessionGuardrail(HeadroomGuardrail):
    def __init__(self):
        super().__init__(
            api_base=os.getenv("HEADROOM_API_BASE", "http://127.0.0.1:8787"),
            guardrail_name="headroom-compression",
            event_hook="pre_call",
            default_on=True,
            unreachable_fallback="fail_open",
            timeout=5,
            ccr_retrieval=False,
        )
        # Keep localhost compression independent of the proxy's shared
        # provider/guardrail transport and its startup/session lifecycle.
        self.async_handler = _SessionClient(AsyncHTTPHandler(transport=httpx.AsyncHTTPTransport()))

    async def apply_guardrail(self, inputs, request_data, input_type, logging_obj=None):
        if input_type != "request" or self._should_bypass(request_data) or request_data.get("background"):
            return inputs
        messages = inputs.get("structured_messages")
        if not messages:
            return inputs
        metadata = _metadata(request_data)
        caller = next((m[_CALLER] for m in metadata if m.get(_CALLER)), None)
        if not caller:
            return inputs
        first_user = next((m for m in messages if m.get("role") == "user"), None)
        session = next((m["session_id"] for m in metadata if m.get("session_id")), None)
        if first_user is None and session is None:
            return inputs
        # Content-derived identity covers clients without a session id. Include
        # the authenticated caller, model, and initial instructions to isolate
        # identical conversations belonging to different callers/backends.
        model = request_data["model"]
        identity = [caller, model, request_data.get("api_base"), session, first_user,
                    [m for m in messages if m.get("role") in {"system", "developer"}]]
        info = request_data.get("model_info") or (request_data.get("litellm_params") or {}).get("model_info") or {}
        context = {"session_id": _digest(identity), "token_budget": info.get("max_input_tokens")}
        token = _CONTEXT.set(context)
        start = time.time()
        try:
            result = await self._call_compress(
                messages=_protect_instructions(messages),
                model=model,
            )
        finally:
            _CONTEXT.reset(token)
        end = time.time()
        self.add_standard_logging_guardrail_information_to_request_data(
            guardrail_json_response=result.stats if result.succeeded else {"error": "compression unavailable"},
            request_data=request_data,
            guardrail_status="success" if result.succeeded else "guardrail_failed_to_respond",
            guardrail_provider="headroom",
            start_time=start,
            end_time=end,
            duration=end - start,
        )
        if not result.succeeded:
            return inputs
        if any(old.get("role") != new.get("role") or old.get("tool_call_id") != new.get("tool_call_id")
               for old, new in zip(messages, result.messages)):
            verbose_proxy_logger.warning("Headroom changed message identities; forwarding original input")
            return inputs
        restored = _restore_content_shapes(messages, result.messages)
        # Preserve all non-tool rows byte-for-byte, including reasoning and
        # multimodal parts, and retain explicit client cache breakpoints.
        rewritten = [new if old.get("role") in {"tool", "function"} and not _cache_marked(old) else old
                     for old, new in zip(messages, restored)]
        from litellm.proxy.common_utils.callback_utils import add_guardrail_to_applied_guardrails_header

        add_guardrail_to_applied_guardrails_header(request_data=request_data, guardrail_name=self.guardrail_name)
        if rewritten == messages:
            return inputs
        return {**inputs, "structured_messages": rewritten}


class HeadroomCompression(CustomLogger):
    def __init__(self):
        super().__init__()
        self.guardrail = _SessionGuardrail()

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        caller = getattr(user_api_key_dict, "api_key", None) or getattr(user_api_key_dict, "user_id", None)
        name = "litellm_metadata" if call_type in {"responses", "aresponses"} else "metadata"
        if not isinstance(data.get(name), dict):
            data[name] = {}
        for metadata in _metadata(data):
            metadata.pop(_CALLER, None)
        if caller:
            data[name][_CALLER] = _digest(caller)
        return data

    async def async_pre_call_deployment_hook(self, kwargs, call_type):
        value = getattr(call_type, "value", call_type)
        model = kwargs.get("model")
        if value not in _SUPPORTED or not isinstance(model, str) or model.startswith("auto_router/"):
            return kwargs
        handler = get_guardrail_translation_mapping(CallTypes(value))()
        return await handler.process_input_messages(data=kwargs, guardrail_to_apply=self.guardrail)


handler = HeadroomCompression()
