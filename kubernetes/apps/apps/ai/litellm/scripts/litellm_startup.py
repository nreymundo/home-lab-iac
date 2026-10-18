import os
import sys
from functools import wraps

import litellm
from litellm.constants import INTERNAL_CALL_ORIGIN_METADATA_KEY
from litellm.llms.chatgpt.responses.transformation import ChatGPTResponsesAPIConfig
from litellm.llms.openai.chat.gpt_5_transformation import OpenAIGPT5Config
from litellm.proxy.auth.route_checks import RouteChecks
from litellm.router import Router
from litellm.types.utils import AUTOROUTER_CLASSIFIER_CALL_ORIGIN

import chatgpt_codex_catalog
import chatgpt_responses_streaming_patch
import openrouter_rerank
import vllm_model_discovery
import zai_coding_catalog


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


def _summary_default_disabled(summary_default):
    return summary_default.lower() in {"", "0", "false", "none", "off", "disabled"}


def _apply_chatgpt_reasoning_summary_default(request, model=None):
    metadata = chatgpt_codex_catalog.model_metadata_for(model)
    if metadata is not None:
        summary_default = str(metadata.get("default_reasoning_summary", "none")).strip()
    else:
        summary_default = os.getenv("CHATGPT_REASONING_SUMMARY_DEFAULT", "detailed").strip()
    if _summary_default_disabled(summary_default):
        return

    reasoning = request.get("reasoning")
    if hasattr(reasoning, "model_dump"):
        reasoning = reasoning.model_dump(exclude_none=True)
    elif isinstance(reasoning, dict):
        reasoning = dict(reasoning)
    else:
        return

    effort = reasoning.get("effort")
    if not effort or effort == "none" or reasoning.get("summary"):
        return

    reasoning["summary"] = summary_default
    request["reasoning"] = reasoning


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
        return original_transform(
            self,
            model=model,
            input=input,
            response_api_optional_request_params=response_api_optional_request_params,
            litellm_params=litellm_params,
            headers=headers,
        )

    transform_responses_api_request._chatgpt_responses_string_input_patch = True
    ChatGPTResponsesAPIConfig.transform_responses_api_request = (
        transform_responses_api_request
    )


def patch_chatgpt_responses_request_transform():
    if getattr(
        ChatGPTResponsesAPIConfig.transform_responses_api_request,
        "_chatgpt_responses_request_patch",
        False,
    ):
        return

    original_transform = ChatGPTResponsesAPIConfig.transform_responses_api_request

    def transform_responses_api_request(
        self,
        model,
        input,
        response_api_optional_request_params,
        litellm_params,
        headers,
    ):
        request = original_transform(
            self,
            model=model,
            input=input,
            response_api_optional_request_params=response_api_optional_request_params,
            litellm_params=litellm_params,
            headers=headers,
        )
        _move_system_input_items_to_instructions(request)
        _apply_chatgpt_reasoning_summary_default(request, model)
        return request

    transform_responses_api_request._chatgpt_responses_request_patch = True
    ChatGPTResponsesAPIConfig.transform_responses_api_request = (
        transform_responses_api_request
    )


def patch_local_decision_classifier_fallbacks():
    """Allow native local-to-cloud failover despite rc.4's classifier override."""
    original = Router.async_function_with_fallbacks
    if getattr(original, "_local_decision_classifier_fallbacks_patch", False):
        return

    @wraps(original)
    async def async_function_with_fallbacks(self, *args, **kwargs):
        metadata = kwargs.get("metadata") or kwargs.get("litellm_metadata") or {}
        if (
            kwargs.get("model") == "local/decisions"
            and metadata.get(INTERNAL_CALL_ORIGIN_METADATA_KEY)
            == AUTOROUTER_CLASSIFIER_CALL_ORIGIN
        ):
            kwargs["disable_fallbacks"] = False
            # The classifier's outer deadline covers both attempts. Use the
            # configured per-deployment timeouts so local cannot spend it all.
            kwargs.pop("timeout", None)
        return await original(self, *args, **kwargs)

    async_function_with_fallbacks._local_decision_classifier_fallbacks_patch = True
    Router.async_function_with_fallbacks = async_function_with_fallbacks


def patch_router_response_retries():
    if getattr(
        Router.async_function_with_retries,
        "_num_retries_default_patch",
        False,
    ):
        return

    original_async_function_with_retries = Router.async_function_with_retries

    async def async_function_with_retries(self, *args, **kwargs):
        if kwargs.get("num_retries") is None:
            kwargs["num_retries"] = getattr(self, "num_retries", None) or 0
        return await original_async_function_with_retries(self, *args, **kwargs)

    async_function_with_retries._num_retries_default_patch = True
    Router.async_function_with_retries = async_function_with_retries


def patch_responses_iterator_cache_callback():
    from litellm.caching.caching_handler import LLMCachingHandler
    from litellm.responses.streaming_iterator import BaseResponsesAPIStreamingIterator
    from litellm.types.llms.openai import ResponsesAPIResponse

    if getattr(
        LLMCachingHandler.async_set_cache,
        "_responses_iterator_cache_patch",
        False,
    ):
        return

    original_async_set_cache = LLMCachingHandler.async_set_cache

    async def async_set_cache(self, result, original_function, kwargs, args=None):
        # Responses iterators persist their completed response when the stream
        # finishes. The generic callback only sees the non-serializable iterator.
        if isinstance(result, BaseResponsesAPIStreamingIterator) or (
            isinstance(result, ResponsesAPIResponse)
            and result.status != "completed"
        ):
            return
        return await original_async_set_cache(
            self,
            result=result,
            original_function=original_function,
            kwargs=kwargs,
            args=args,
        )

    async_set_cache._responses_iterator_cache_patch = True
    LLMCachingHandler.async_set_cache = async_set_cache


def _catalog_metadata_for_deployment(deployment):
    if not isinstance(deployment, dict):
        return None

    metadata = chatgpt_codex_catalog.model_metadata_for(deployment.get("model_name"))
    if metadata is not None:
        return metadata

    litellm_params = deployment.get("litellm_params") or {}
    if isinstance(litellm_params, dict):
        return chatgpt_codex_catalog.model_metadata_for(litellm_params.get("model"))

    return None


def _apply_catalog_metadata_to_deployment(deployment):
    metadata = _catalog_metadata_for_deployment(deployment)
    if metadata is not None:
        model_info = deployment.setdefault("model_info", {})
        model_info.update(metadata)
    return deployment


def patch_chatgpt_codex_model_catalog():
    updated_model_cost = False
    for model_name, catalog_info in chatgpt_codex_catalog.iter_model_cost_entries():
        existing_info = dict(litellm.model_cost.get(model_name, {}) or {})
        existing_info.update(catalog_info)
        if litellm.model_cost.get(model_name) != existing_info:
            updated_model_cost = True
        litellm.model_cost[model_name] = existing_info

    provider_models = litellm.models_by_provider.setdefault("chatgpt", [])
    for slug in chatgpt_codex_catalog.CHATGPT_CODEX_MODELS:
        if slug not in provider_models:
            if hasattr(provider_models, "add"):
                provider_models.add(slug)
            else:
                provider_models.append(slug)

    if updated_model_cost:
        from litellm.utils import _invalidate_model_cost_lowercase_map

        _invalidate_model_cost_lowercase_map()


def patch_chatgpt_codex_reasoning_validator():
    if getattr(
        OpenAIGPT5Config._supports_reasoning_effort_level,
        "_chatgpt_codex_reasoning_patch",
        False,
    ):
        return

    original_supports = OpenAIGPT5Config._supports_reasoning_effort_level

    def supports_reasoning_effort_level(cls, model, level):
        metadata = chatgpt_codex_catalog.model_metadata_for(model)
        if metadata is not None:
            return level in metadata.get("supported_reasoning_levels", [])
        return original_supports(model, level)

    supports_reasoning_effort_level._chatgpt_codex_reasoning_patch = True
    OpenAIGPT5Config._supports_reasoning_effort_level = classmethod(
        supports_reasoning_effort_level
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


def patch_model_list_metadata():
    import litellm.proxy.utils as proxy_utils

    if getattr(
        proxy_utils.create_model_info_response,
        "_chatgpt_codex_model_list_metadata_patch",
        False,
    ):
        return

    original_create_model_info_response = proxy_utils.create_model_info_response

    def create_model_info_response(
        model_id,
        provider,
        include_metadata=False,
        fallback_type=None,
        llm_router=None,
        get_model_info=litellm.get_model_info,
    ):
        response = original_create_model_info_response(
            model_id=model_id,
            provider=provider,
            include_metadata=include_metadata,
            fallback_type=fallback_type,
            llm_router=llm_router,
            get_model_info=get_model_info,
        )
        metadata = chatgpt_codex_catalog.model_metadata_for(model_id)
        if metadata is None:
            return response

        response["owned_by"] = "chatgpt"
        if include_metadata:
            response_metadata = response.setdefault("metadata", {})
            response_metadata.update(metadata)
        return response

    create_model_info_response._chatgpt_codex_model_list_metadata_patch = True
    proxy_utils.create_model_info_response = create_model_info_response


def patch_proxy_model_info_endpoints():
    proxy_server = sys.modules.get("litellm.proxy.proxy_server")
    if proxy_server is None:
        return

    if not getattr(
        proxy_server._get_proxy_model_info,
        "_chatgpt_codex_proxy_model_info_patch",
        False,
    ):
        original_get_proxy_model_info = proxy_server._get_proxy_model_info

        def get_proxy_model_info(model):
            _apply_catalog_metadata_to_deployment(model)
            deployment = original_get_proxy_model_info(model)
            return _apply_catalog_metadata_to_deployment(deployment)

        get_proxy_model_info._chatgpt_codex_proxy_model_info_patch = True
        proxy_server._get_proxy_model_info = get_proxy_model_info

    if not getattr(
        proxy_server._enrich_model_info_with_litellm_data,
        "_chatgpt_codex_enrich_model_info_patch",
        False,
    ):
        original_enrich_model_info = proxy_server._enrich_model_info_with_litellm_data

        def enrich_model_info_with_litellm_data(model, debug=False, llm_router=None):
            _apply_catalog_metadata_to_deployment(model)
            deployment = original_enrich_model_info(
                model=model,
                debug=debug,
                llm_router=llm_router,
            )
            return _apply_catalog_metadata_to_deployment(deployment)

        enrich_model_info_with_litellm_data._chatgpt_codex_enrich_model_info_patch = True
        proxy_server._enrich_model_info_with_litellm_data = enrich_model_info_with_litellm_data

    if getattr(
        proxy_server._get_model_group_info,
        "_chatgpt_codex_model_group_info_patch",
        False,
    ):
        return

    original_get_model_group_info = proxy_server._get_model_group_info

    def get_model_group_info(llm_router, all_models_str, model_group):
        model_groups = original_get_model_group_info(
            llm_router=llm_router,
            all_models_str=all_models_str,
            model_group=model_group,
        )
        normalized_groups = []
        for model_group_info in model_groups:
            if hasattr(model_group_info, "model_dump"):
                group = model_group_info.model_dump(exclude_none=True)
            else:
                group = dict(model_group_info)

            metadata = chatgpt_codex_catalog.model_metadata_for(
                group.get("model_group")
            )
            if metadata is not None:
                group.update(metadata)
                group["providers"] = ["chatgpt"]
            normalized_groups.append(group)
        return normalized_groups

    get_model_group_info._chatgpt_codex_model_group_info_patch = True
    proxy_server._get_model_group_info = get_model_group_info


def patch_public_model_cost_map_endpoint():
    proxy_server = sys.modules.get("litellm.proxy.proxy_server")
    if proxy_server is None:
        return

    public_path = "/public/litellm_model_cost_map"
    proxy_server.app.router.routes[:] = [
        route
        for route in proxy_server.app.router.routes
        if getattr(route, "path", None) != public_path
    ]

    @proxy_server.app.get(public_path, include_in_schema=False)
    async def public_litellm_model_cost_map():
        patch_chatgpt_codex_model_catalog()
        zai_coding_catalog.worker_startup_hook()
        return litellm.model_cost


def patch_file_authoritative_router_settings():
    proxy_server = sys.modules.get("litellm.proxy.proxy_server")
    if proxy_server is None:
        return

    proxy_config_cls = getattr(proxy_server, "ProxyConfig", None)
    if proxy_config_cls is None:
        return

    current = getattr(proxy_config_cls, "_add_router_settings_from_db_config", None)
    if current is None or getattr(current, "_file_authoritative_patch", False):
        return

    async def add_router_settings_from_config(self, config_data, llm_router, prisma_client):
        if llm_router is None:
            return

        router_settings = config_data.get("router_settings") or {}
        if isinstance(router_settings, dict) and router_settings:
            llm_router.update_settings(**router_settings)

    add_router_settings_from_config._file_authoritative_patch = True
    proxy_config_cls._add_router_settings_from_db_config = add_router_settings_from_config


def worker_startup_hook():
    # Keep virtual-key discovery and the narrow upstream string-input backport
    # active. CacheBypassHandler is registered separately in config.yaml.
    patch_virtual_key_model_discovery_routes()
    patch_chatgpt_responses_string_input()
    openrouter_rerank.worker_startup_hook()
    patch_local_decision_classifier_fallbacks()

    # Retained implementations and mounts allow selective restoration by
    # uncommenting calls below. Review compatibility before re-enabling.
    # patch_chatgpt_codex_model_catalog()
    # zai_coding_catalog.worker_startup_hook()
    # patch_chatgpt_codex_reasoning_validator()
    # patch_chatgpt_responses_request_transform()
    # patch_model_list_metadata()
    # patch_proxy_model_info_endpoints()
    # patch_public_model_cost_map_endpoint()
    # Incompatible with v1.105.1: upstream no longer passes config_data.
    # patch_file_authoritative_router_settings()
    # patch_router_response_retries()
    # patch_responses_iterator_cache_callback()
    # vllm_model_discovery.worker_startup_hook()
    # chatgpt_responses_streaming_patch.worker_startup_hook()
