"""OpenRouter rerank compatibility for LiteLLM v1.106.0-rc.4."""

from functools import wraps

import litellm
from litellm.llms.hosted_vllm.rerank.transformation import HostedVLLMRerankConfig
from litellm.secret_managers.main import get_secret_str
from litellm.utils import ProviderConfigManager


class OpenRouterRerankConfig(HostedVLLMRerankConfig):
    def get_complete_url(self, api_base, model, optional_params=None):
        return super().get_complete_url(
            api_base or get_secret_str("OPENROUTER_API_BASE") or "https://openrouter.ai/api/v1",
            model,
            optional_params,
        )

    def validate_environment(self, headers, model, api_key=None, optional_params=None, litellm_params=None):
        api_key = api_key or get_secret_str("OPENROUTER_API_KEY")
        if not api_key:
            raise ValueError("OpenRouter API key is required for reranking")
        return {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json", **headers}

    def get_supported_cohere_rerank_params(self, model):
        return ["query", "documents", "top_n", "return_documents"]

    def _transform_response(self, response):
        result = super()._transform_response(response)
        cost = response.get("usage", {}).get("cost")
        if cost is not None:
            # Use LiteLLM's existing provider-cost hook for headers and spend logs.
            # An explicit zero is meaningful (for example, a free provider).
            result._hidden_params.setdefault("additional_headers", {})[
                "llm_provider-x-litellm-response-cost"
            ] = str(cost)
        return result

    def calculate_rerank_cost(self, model, custom_llm_provider=None, billed_units=None, model_info=None):
        model = model.removeprefix("openrouter/")
        info = model_info or {}
        if info.get("input_cost_per_token") is None and model.startswith("voyageai/"):
            # Reuse the shipped Voyage price book when OpenRouter omits usage.cost.
            info = litellm.get_model_info(model="voyage/" + model.removeprefix("voyageai/"))
        rate = info.get("input_cost_per_token")
        tokens = (billed_units or {}).get("total_tokens")
        if rate is None or tokens is None:
            raise ValueError(f"Missing OpenRouter rerank token pricing or usage for {model}")
        return rate * tokens, 0.0


def worker_startup_hook():
    original = ProviderConfigManager.get_provider_rerank_config
    if getattr(original, "_openrouter_rerank_patch", False):
        return

    @wraps(original)
    def get_provider_rerank_config(model, provider, api_base, present_version_params):
        if provider == litellm.LlmProviders.OPENROUTER:
            return OpenRouterRerankConfig()
        return original(
            model=model,
            provider=provider,
            api_base=api_base,
            present_version_params=present_version_params,
        )

    get_provider_rerank_config._openrouter_rerank_patch = True
    ProviderConfigManager.get_provider_rerank_config = staticmethod(get_provider_rerank_config)
