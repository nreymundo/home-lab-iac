from functools import wraps

from litellm.llms.chatgpt.responses.transformation import ChatGPTResponsesAPIConfig
from litellm.proxy.auth.route_checks import RouteChecks

import openrouter_rerank
import secrets_guardrail


_SYSTEM_INSTRUCTION_ROLES = {"system", "developer"}


def _content_to_instruction_text(content):
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        text_parts = []
        for item in content:
            if isinstance(item, str):
                text_parts.append(item)
            elif isinstance(item, dict) and isinstance(item.get("text"), str):
                text_parts.append(item["text"])
        return "\n".join(part for part in text_parts if part)
    if isinstance(content, dict) and isinstance(content.get("text"), str):
        return content["text"]
    return str(content)


def _merge_instructions(existing_instructions, extracted_instructions):
    extracted_instructions = [item for item in extracted_instructions if item]
    if not extracted_instructions:
        return existing_instructions

    parts = []
    if existing_instructions:
        parts.append(str(existing_instructions))
    parts.extend(extracted_instructions)
    return "\n\n".join(parts)


def _move_system_input_items_to_instructions(request):
    input_items = request.get("input")
    if not isinstance(input_items, list):
        return

    sanitized_input = []
    extracted_instructions = []
    for item in input_items:
        if (
            isinstance(item, dict)
            and item.get("type", "message") == "message"
            and item.get("role") in _SYSTEM_INSTRUCTION_ROLES
        ):
            extracted_instructions.append(
                _content_to_instruction_text(item.get("content"))
            )
            continue
        sanitized_input.append(item)

    if len(sanitized_input) == len(input_items):
        return

    request["input"] = sanitized_input
    request["instructions"] = _merge_instructions(
        request.get("instructions"), extracted_instructions
    )


def patch_chatgpt_responses_string_input():
    """Backport non-empty string normalization from upstream PR #38191."""
    original_transform = ChatGPTResponsesAPIConfig.transform_responses_api_request
    if getattr(original_transform, "_chatgpt_responses_string_input_patch", False):
        return

    @wraps(original_transform)
    def transform_responses_api_request(
        self,
        model,
        input,
        response_api_optional_request_params,
        litellm_params,
        headers,
    ):
        if isinstance(input, str) and input != "":
            input = [
                {"role": "user", "content": [{"type": "input_text", "text": input}]}
            ]
        request = original_transform(
            self,
            model=model,
            input=input,
            response_api_optional_request_params=response_api_optional_request_params,
            litellm_params=litellm_params,
            headers=headers,
        )
        _move_system_input_items_to_instructions(request)
        return request

    transform_responses_api_request._chatgpt_responses_string_input_patch = True
    ChatGPTResponsesAPIConfig.transform_responses_api_request = (
        transform_responses_api_request
    )


_MODEL_DISCOVERY_ROUTES = [
    "/v1/models",
    "/models",
    "/v1/models/{model_id}",
    "/models/{model_id}",
    "/model/info",
    "/v1/model/info",
    "/model_group/info",
]


def _is_model_discovery_route(route):
    return RouteChecks.check_route_access(
        route=route,
        allowed_routes=_MODEL_DISCOVERY_ROUTES,
    )


def patch_virtual_key_model_discovery_routes():
    if getattr(
        RouteChecks.is_virtual_key_allowed_to_call_route,
        "_chatgpt_codex_model_discovery_patch",
        False,
    ):
        return

    original_is_allowed = RouteChecks.is_virtual_key_allowed_to_call_route

    def is_virtual_key_allowed_to_call_route(route, valid_token, *args, **kwargs):
        if _is_model_discovery_route(route):
            return True
        return original_is_allowed(route, valid_token, *args, **kwargs)

    is_virtual_key_allowed_to_call_route._chatgpt_codex_model_discovery_patch = True
    RouteChecks.is_virtual_key_allowed_to_call_route = staticmethod(
        is_virtual_key_allowed_to_call_route
    )


def worker_startup_hook():
    # Keep virtual-key discovery and the narrow upstream string-input backport
    # active. CacheBypassHandler is registered separately in config.yaml.
    patch_virtual_key_model_discovery_routes()
    patch_chatgpt_responses_string_input()
    openrouter_rerank.worker_startup_hook()
    secrets_guardrail.install_proxy_response_hooks()
