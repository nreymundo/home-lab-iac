"""Run in the deployed RC image with scripts/ on PYTHONPATH; no network."""

import json
import unittest
from unittest.mock import AsyncMock, patch

import httpx
import litellm
from litellm.cost_calculator import response_cost_calculator
from litellm.utils import ProviderConfigManager

from openrouter_rerank import OpenRouterRerankConfig, worker_startup_hook


MODEL = "openrouter/voyageai/rerank-2.5-lite"


def payload(cost=0.000123):
    usage = {"total_tokens": 100}
    if cost is not None:
        usage["cost"] = cost
    return {"results": [{"index": 1, "relevance_score": 0.99}], "usage": usage}


def recorded_cost(response, cache_hit=False):
    return response_cost_calculator(
        response_object=response,
        model=MODEL,
        custom_llm_provider="openrouter",
        call_type="arerank",
        optional_params={},
        cache_hit=cache_hit,
    )


class OpenRouterRerankTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        worker_startup_hook()

    def test_provider_cost_including_zero_and_cached_cost(self):
        for cost in (0.000123, 0):
            response = OpenRouterRerankConfig()._transform_response(payload(cost))
            self.assertEqual(response.meta["billed_units"]["total_tokens"], 100)
            self.assertEqual(recorded_cost(response), cost)
            self.assertEqual(recorded_cost(response, cache_hit=True), 0)

    def test_missing_provider_cost_uses_voyage_token_price(self):
        response = OpenRouterRerankConfig()._transform_response(payload(None))
        self.assertAlmostEqual(recorded_cost(response), 100 * 0.00000002)

    def test_explicit_token_rate_and_missing_price(self):
        config = OpenRouterRerankConfig()
        self.assertEqual(
            config.calculate_rerank_cost("example/model", billed_units={"total_tokens": 10},
                                         model_info={"input_cost_per_token": 0.001}),
            (0.01, 0),
        )
        with self.assertRaises(ValueError):
            config.calculate_rerank_cost("example/model", billed_units={"total_tokens": 10})

    def test_other_providers_unchanged_and_registration_idempotent(self):
        original = ProviderConfigManager.get_provider_rerank_config
        worker_startup_hook()
        self.assertIs(ProviderConfigManager.get_provider_rerank_config, original)
        for provider, cls in (("hosted_vllm", litellm.HostedVLLMRerankConfig),
                              ("voyage", litellm.VoyageRerankConfig),
                              ("cohere", litellm.CohereRerankConfig)):
            config = ProviderConfigManager.get_provider_rerank_config(
                model="test", provider=litellm.LlmProviders(provider), api_base=None, present_version_params=[]
            )
            self.assertIsInstance(config, cls)

    async def test_router_alias_sends_openrouter_rerank_and_preserves_cost(self):
        router = litellm.Router(
            model_list=[{"model_name": MODEL, "model_info": {"mode": "rerank"},
                         "litellm_params": {"model": MODEL, "custom_llm_provider": "openrouter",
                                            "api_key": "unit-test-placeholder"}}],
            model_group_alias={"remote/rerank": MODEL},
        )
        for model in (MODEL, "remote/rerank"):
            response = httpx.Response(200, json=payload(), request=httpx.Request("POST", "https://openrouter.ai/api/v1/rerank"))
            post = AsyncMock(return_value=response)
            with patch("litellm.llms.custom_httpx.http_handler.AsyncHTTPHandler.post", post):
                result = await router.arerank(model=model, query="France?", documents=["Berlin", "Paris"], top_n=1)
            call = post.call_args
            self.assertEqual(str(call.kwargs.get("url", call.args[0] if call.args else None)), str(response.request.url))
            body = call.kwargs.get("json") or call.kwargs.get("data") or call.kwargs.get("content")
            if isinstance(body, (str, bytes)):
                body = json.loads(body)
            self.assertEqual(body["model"], "voyageai/rerank-2.5-lite")
            self.assertEqual(body["top_n"], 1)
            self.assertNotIn("top_k", body)
            self.assertEqual(result.results[0]["index"], 1)
            self.assertEqual(recorded_cost(result), 0.000123)


if __name__ == "__main__":
    unittest.main()
