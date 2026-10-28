from copy import deepcopy


SUPPORTED_OPENAI_PARAMS = [
    "stream",
    "tools",
    "tool_choice",
    "parallel_tool_calls",
    "reasoning_effort",
    "verbosity",
    "extra_headers",
]

REASONING_LEVELS = ["none", "low", "medium", "high", "xhigh", "max"]

CHATGPT_CODEX_MODELS = {
    "gpt-5.5": {
        "display_name": "GPT-5.5",
        "description": "Frontier model for complex coding, research, and real-world work.",
        "context_window": 272000,
        "max_context_window": 272000,
        "max_output_tokens": 128000,
        "effective_context_window_percent": 95,
        "default_reasoning_level": "medium",
        "default_reasoning_summary": "none",
        "default_verbosity": "low",
        "input_modalities": ["text", "image"],
        "web_search_tool_type": "text_and_image",
        "supports_image_detail_original": True,
        "supported_in_api": True,
        "visibility": "list",
        "priority": 7,
        "service_tiers": [
            {"id": "priority", "name": "Fast", "description": "1.5x speed, increased usage"}
        ],
        "additional_speed_tiers": ["fast"],
        "truncation_policy": {"mode": "tokens", "limit": 10000},
        "supported_reasoning_efforts": ["low", "medium", "high", "xhigh"],
        "input_cost_per_token": 0.000005,
        "output_cost_per_token": 0.00003,
    },
    "gpt-5.4-mini": {
        "display_name": "GPT-5.4-Mini",
        "description": "Small, fast, and cost-efficient model for simpler coding tasks.",
        "context_window": 272000,
        "max_context_window": 272000,
        "max_output_tokens": 128000,
        "effective_context_window_percent": 95,
        "default_reasoning_level": "medium",
        "default_reasoning_summary": "none",
        "default_verbosity": "medium",
        "input_modalities": ["text", "image"],
        "web_search_tool_type": "text_and_image",
        "supports_image_detail_original": True,
        "supported_in_api": True,
        "visibility": "list",
        "priority": 23,
        "service_tiers": [],
        "additional_speed_tiers": [],
        "truncation_policy": {"mode": "tokens", "limit": 10000},
        "supported_reasoning_efforts": ["low", "medium", "high", "xhigh"],
        "input_cost_per_token": 0.00000075,
        "output_cost_per_token": 0.0000045,
    },
    "codex-auto-review": {
        "display_name": "Codex Auto Review",
        "description": "Automatic approval review model for Codex.",
        "context_window": 272000,
        "max_context_window": 1000000,
        "max_output_tokens": 128000,
        "effective_context_window_percent": 95,
        "default_reasoning_level": "medium",
        "default_reasoning_summary": "none",
        "default_verbosity": "low",
        "input_modalities": ["text", "image"],
        "web_search_tool_type": "text_and_image",
        "supported_in_api": True,
        "visibility": "hide",
        "priority": 43,
        "service_tiers": [],
        "additional_speed_tiers": [],
        "truncation_policy": {"mode": "tokens", "limit": 10000},
        "supported_reasoning_efforts": ["none", "low", "medium", "high", "xhigh"],
        "input_cost_per_token": 0.0,
        "output_cost_per_token": 0.0,
    },
}

PUBLIC_MODEL_PREFIX = "openai/"
BACKEND_MODEL_PREFIX = "chatgpt/"


def get_chatgpt_codex_slug(model):
    if not isinstance(model, str):
        return None
    if model in CHATGPT_CODEX_MODELS:
        return model
    for prefix in (PUBLIC_MODEL_PREFIX, BACKEND_MODEL_PREFIX):
        if model.startswith(prefix):
            slug = model[len(prefix) :]
            return slug if slug in CHATGPT_CODEX_MODELS else None
    return None


def get_chatgpt_codex_model(model):
    slug = get_chatgpt_codex_slug(model)
    if slug is None:
        return None
    return deepcopy(CHATGPT_CODEX_MODELS[slug])


def is_public_chatgpt_codex_model(model):
    info = get_chatgpt_codex_model(model)
    return bool(
        info
        and info.get("supported_in_api") is True
        and info.get("visibility") != "hide"
    )


def _reasoning_support_flags(info):
    supported_efforts = set(info.get("supported_reasoning_efforts", REASONING_LEVELS))
    flags = {
        f"supports_{level}_reasoning_effort": level in supported_efforts
        for level in REASONING_LEVELS
    }
    flags["supports_minimal_reasoning_effort"] = "minimal" in supported_efforts
    flags["supports_none_reasoning_effort"] = "none" in supported_efforts
    return flags


def _base_metadata(slug, info):
    supports_vision = "image" in info["input_modalities"]
    metadata = {
        "codex_model_slug": slug,
        "display_name": info["display_name"],
        "description": info["description"],
        "litellm_provider": "chatgpt",
        "mode": "responses",
        "context_window": info["context_window"],
        "max_input_tokens": info["context_window"],
        "max_context_window": info["max_context_window"],
        "max_output_tokens": info["max_output_tokens"],
        "max_tokens": info["max_output_tokens"],
        "effective_context_window_percent": info["effective_context_window_percent"],
        "supports_reasoning": True,
        "supported_reasoning_levels": [
            level
            for level in REASONING_LEVELS
            if level in info.get("supported_reasoning_efforts", REASONING_LEVELS)
        ],
        "default_reasoning_level": info["default_reasoning_level"],
        "supports_reasoning_summaries": True,
        "default_reasoning_summary": info["default_reasoning_summary"],
        "supports_verbosity": True,
        "support_verbosity": True,
        "default_verbosity": info["default_verbosity"],
        "input_modalities": list(info["input_modalities"]),
        "supports_vision": supports_vision,
        "supports_image_input": supports_vision,
        "supports_image_detail_original": info.get(
            "supports_image_detail_original", False
        ),
        "supports_web_search": True,
        "web_search_tool_type": info["web_search_tool_type"],
        "supports_function_calling": True,
        "supports_parallel_function_calling": True,
        "supports_parallel_tool_calls": True,
        "supported_openai_params": list(SUPPORTED_OPENAI_PARAMS),
        "supported_in_api": info["supported_in_api"],
        "visibility": info["visibility"],
        "priority": info["priority"],
        "service_tiers": deepcopy(info["service_tiers"]),
        "additional_speed_tiers": list(info["additional_speed_tiers"]),
        "truncation_policy": deepcopy(info["truncation_policy"]),
        "input_cost_per_token": info["input_cost_per_token"],
        "output_cost_per_token": info["output_cost_per_token"],
    }
    for key in (
        "cache_read_input_token_cost",
        "cache_creation_input_token_cost",
        "input_cost_per_token_above_272k_tokens",
        "cache_read_input_token_cost_above_272k_tokens",
        "cache_creation_input_token_cost_above_272k_tokens",
        "output_cost_per_token_above_272k_tokens",
    ):
        if key in info:
            metadata[key] = info[key]
    metadata.update(_reasoning_support_flags(info))
    return metadata


def model_metadata_for(model):
    slug = get_chatgpt_codex_slug(model)
    if slug is None:
        return None
    return _base_metadata(slug, CHATGPT_CODEX_MODELS[slug])


def litellm_model_cost_for(model):
    metadata = model_metadata_for(model)
    if metadata is None:
        return None
    return deepcopy(metadata)


def public_model_name_for(model):
    slug = get_chatgpt_codex_slug(model)
    if slug is None:
        return None
    return f"{PUBLIC_MODEL_PREFIX}{slug}"


def backend_model_name_for(model):
    slug = get_chatgpt_codex_slug(model)
    if slug is None:
        return None
    return f"{BACKEND_MODEL_PREFIX}{slug}"


def iter_model_cost_entries():
    for slug in CHATGPT_CODEX_MODELS:
        info = litellm_model_cost_for(slug)
        yield slug, deepcopy(info)
        yield f"{BACKEND_MODEL_PREFIX}{slug}", deepcopy(info)
        yield f"{PUBLIC_MODEL_PREFIX}{slug}", deepcopy(info)
