"""Keep Headroom 0.41 accounting independent of provider authentication."""

import inspect

import litellm
from headroom.pricing import litellm_pricing
from headroom.pricing.litellm_model_resolution import pricing_lookup_candidates

_cost_per_token = litellm.cost_per_token
_signature = inspect.signature(_cost_per_token)


def _priced_model(model):
    for candidate in pricing_lookup_candidates(model):
        info = litellm.model_cost.get(candidate, {})
        if info.get("input_cost_per_token") is not None and info.get("litellm_provider"):
            return candidate, info["litellm_provider"]
    raise ValueError("No catalogue pricing available")


def _resolve_model(model):
    try:
        return _priced_model(model)[0]
    except ValueError:
        return model


def _metadata_cost_per_token(*args, **kwargs):
    call = _signature.bind(*args, **kwargs)
    model, provider = _priced_model(call.arguments["model"])
    call.arguments.update(model=model, custom_llm_provider=provider)
    return _cost_per_token(*call.args, **call.kwargs)


litellm_pricing.resolve_litellm_model = _resolve_model
litellm.cost_per_token = _metadata_cost_per_token
