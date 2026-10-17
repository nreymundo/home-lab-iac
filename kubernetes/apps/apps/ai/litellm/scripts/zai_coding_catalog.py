from copy import deepcopy

import litellm
from litellm.llms.zai.chat.transformation import ZAIChatConfig


ZAI_CODING_MODELS = {
    "glm-5.3": {
        "context_window": 1000000,
        "max_output_tokens": 128000,
        "input_cost_per_token": 0.0000014,
        "cache_read_input_token_cost": 0.00000026,
        "output_cost_per_token": 0.0000044,
        "reasoning_options": [{"type": "effort", "values": ["low", "high", "max"]}],
        "default_reasoning_effort": "max",
        "source": "https://openrouter.ai/z-ai/glm-5.3/api",
    },
    "glm-5.3-flash": {
        "context_window": 1048576,
        "max_output_tokens": 131072,
        "input_cost_per_token": 0.000000075,
        "cache_read_input_token_cost": 0.000000015,
        "output_cost_per_token": 0.00000025,
        "reasoning_options": [{"type": "effort", "values": ["low", "high", "max"]}],
        "default_reasoning_effort": "max",
        "supports_vision": True,
        "source": "https://openrouter.ai/z-ai/glm-5.3-flash/api",
    },
    "glm-5.2": {
        "context_window": 1000000,
        "max_output_tokens": 131072,
        "input_cost_per_token": 0.0000014,
        "cache_read_input_token_cost": 0.00000026,
        "output_cost_per_token": 0.0000044,
        "reasoning_options": [{"type": "effort", "values": ["high", "max"]}],
        "default_reasoning_effort": "high",
        "source": "https://openrouter.ai/z-ai/glm-5.2/api",
    },
    "glm-5.1": {
        "context_window": 200000,
        "max_output_tokens": 128000,
        "input_cost_per_token": 0.0000014,
        "cache_read_input_token_cost": 0.00000026,
        "output_cost_per_token": 0.0000044,
    },
    "glm-5-turbo": {
        "context_window": 200000,
        "max_output_tokens": 128000,
        "input_cost_per_token": 0.0000012,
        "cache_read_input_token_cost": 0.00000024,
        "output_cost_per_token": 0.000004,
    },
    "glm-4.7": {
        "context_window": 200000,
        "max_output_tokens": 128000,
        "input_cost_per_token": 0.0000006,
        "cache_read_input_token_cost": 0.00000011,
        "output_cost_per_token": 0.0000022,
    },
}


def _metadata_for(slug):
    info = ZAI_CODING_MODELS[slug]
    supports_vision = info.get("supports_vision", False)
    metadata = {
        "litellm_provider": "zai",
        "mode": "chat",
        "context_window": info["context_window"],
        "max_input_tokens": info["context_window"],
        "max_output_tokens": info["max_output_tokens"],
        "max_tokens": info["max_output_tokens"],
        "supports_function_calling": True,
        "supports_tool_choice": True,
        # Z.AI uses native `thinking`; do not advertise OpenAI-style
        # `reasoning_effort` as a supported request parameter below.
        "supports_reasoning": True,
        "reasoning_options": deepcopy(
            info.get("reasoning_options", [{"type": "toggle"}])
        ),
        "source": info.get("source", "https://docs.z.ai/guides/overview/pricing"),
    }
    for key in (
        "input_cost_per_token",
        "cache_read_input_token_cost",
        "output_cost_per_token",
    ):
        if key in info:
            metadata[key] = info[key]
    if "default_reasoning_effort" in info:
        metadata["default_reasoning_effort"] = info["default_reasoning_effort"]
    if supports_vision:
        metadata.update(
            {
                "input_modalities": ["text", "image"],
                "supports_image_input": True,
                "supports_vision": True,
            }
        )
    return metadata


def iter_model_cost_entries():
    for slug in ZAI_CODING_MODELS:
        metadata = _metadata_for(slug)
        yield f"zai/{slug}", deepcopy(metadata)
        yield f"zai-coding/{slug}", deepcopy(metadata)


def _zai_coding_slug(model):
    if not isinstance(model, str):
        return None
    for prefix in ("zai/", "zai-coding/"):
        if model.startswith(prefix):
            model = model[len(prefix) :]
            break
    return model if model in ZAI_CODING_MODELS else None


def patch_zai_coding_supported_params():
    if getattr(
        ZAIChatConfig.get_supported_openai_params,
        "_zai_coding_supported_params_patch",
        False,
    ):
        return

    original_get_supported_openai_params = ZAIChatConfig.get_supported_openai_params

    def get_supported_openai_params(self, model):
        supported_params = list(original_get_supported_openai_params(self, model))
        # Z.AI GLM models support native `thinking`, and GLM-5.2/5.3/5.3-Flash
        # also accept OpenAI-style `reasoning_effort` values.
        # OpenAI-compatible clients may also send max_completion_tokens;
        # Z.AI accepts it, but LiteLLM's ZAI provider does not list it by default.
        slug = _zai_coding_slug(model)
        if slug is not None:
            params = ["thinking", "max_completion_tokens", "extra_body"]
            if slug in {"glm-5.2", "glm-5.3", "glm-5.3-flash"}:
                params.append("reasoning_effort")
            for param in params:
                if param not in supported_params:
                    supported_params.append(param)
        return supported_params

    get_supported_openai_params._zai_coding_supported_params_patch = True
    ZAIChatConfig.get_supported_openai_params = get_supported_openai_params

    if getattr(
        ZAIChatConfig.map_openai_params,
        "_zai_coding_map_params_patch",
        False,
    ):
        return

    original_map_openai_params = ZAIChatConfig.map_openai_params

    def map_openai_params(self, non_default_params, optional_params, model, drop_params):
        optional_params = original_map_openai_params(
            self,
            non_default_params=non_default_params,
            optional_params=optional_params,
            model=model,
            drop_params=drop_params,
        )
        if _zai_coding_slug(model) is not None and "thinking" in optional_params:
            extra_body = dict(optional_params.get("extra_body") or {})
            extra_body["thinking"] = optional_params.pop("thinking")
            optional_params["extra_body"] = extra_body
        return optional_params

    map_openai_params._zai_coding_map_params_patch = True
    ZAIChatConfig.map_openai_params = map_openai_params


def patch_zai_coding_model_catalog():
    updated_model_cost = False
    for model_name, catalog_info in iter_model_cost_entries():
        existing_info = dict(litellm.model_cost.get(model_name, {}) or {})
        existing_info.update(catalog_info)
        if litellm.model_cost.get(model_name) != existing_info:
            updated_model_cost = True
        litellm.model_cost[model_name] = existing_info

    provider_models = litellm.models_by_provider.setdefault("zai", [])
    for slug in ZAI_CODING_MODELS:
        if slug not in provider_models:
            if hasattr(provider_models, "add"):
                provider_models.add(slug)
            else:
                provider_models.append(slug)

    if updated_model_cost:
        from litellm.utils import _invalidate_model_cost_lowercase_map

        _invalidate_model_cost_lowercase_map()


def worker_startup_hook():
    patch_zai_coding_model_catalog()
    patch_zai_coding_supported_params()
