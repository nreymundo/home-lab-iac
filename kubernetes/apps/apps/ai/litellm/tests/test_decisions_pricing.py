"""Run in the deployed LiteLLM image; no provider network access required."""

import json
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

import httpx
import litellm
import yaml


CONFIG = yaml.safe_load(
    yaml.safe_load((Path(__file__).resolve().parents[1] / "configmap.yaml").read_text())["data"]["config.yaml"]
)
DECISION_MODEL = "openrouter/~typesafe/jev-latest"


class DecisionsPricingTests(unittest.IsolatedAsyncioTestCase):
    def test_native_openrouter_models_use_provider_pricing(self):
        for model in CONFIG["model_list"]:
            params = model["litellm_params"]
            if params.get("custom_llm_provider") == "openrouter":
                self.assertNotIn("input_cost_per_token", params, model["model_name"])
                self.assertNotIn("output_cost_per_token", params, model["model_name"])

    def test_decision_alias_targets_canonical_deployment(self):
        self.assertEqual(CONFIG["router_settings"]["model_group_alias"]["cloud/decision"], DECISION_MODEL)
        model = next(model for model in CONFIG["model_list"] if model["model_name"] == DECISION_MODEL)
        self.assertEqual(model["model_info"]["mode"], "decisions")
        self.assertEqual(model["litellm_params"]["litellm_credential_name"], "openrouter")
        router = litellm.Router(
            model_list=[{**model, "litellm_params": {"model": DECISION_MODEL, "api_key": "unit-test-placeholder"}}],
            model_group_alias={"cloud/decision": DECISION_MODEL},
        )
        self.assertEqual(router.get_model_from_alias("cloud/decision"), DECISION_MODEL)
        self.assertEqual(router.get_model_list(model_name="cloud/decision")[0]["model_info"]["mode"], "decisions")

    def test_chat_cost_uses_builtin_rates_without_zero_override(self):
        response = litellm.ModelResponse(
            model="openai/gpt-6-luna",
            usage={"prompt_tokens": 10, "completion_tokens": 1, "total_tokens": 11, "cost": 0.0000123},
        )
        cost = litellm.completion_cost(
            completion_response=response,
            model="openrouter/openai/gpt-6-luna",
            custom_llm_provider="openrouter",
        )
        self.assertAlmostEqual(cost, 10 * 0.0000001 + 0.0000005)

    async def test_decision_adapter_uses_openrouter_endpoint_and_reports_cost(self):
        payload = {
            "model": "typesafe/jev-1.14",
            "answers": {"refund": {"type": "noul", "noul": 0.98}},
            "usage": {"input_tokens": 100, "output_tokens": 0, "cost": 0.0000042},
        }
        response = httpx.Response(
            200,
            json=payload,
            request=httpx.Request("POST", "https://openrouter.ai/api/alpha/decisions"),
        )
        post = AsyncMock(return_value=response)
        with patch("litellm.llms.custom_httpx.http_handler.AsyncHTTPHandler.post", post):
            result = await litellm.asystemone(
                model=DECISION_MODEL,
                api_key="unit-test-placeholder",
                state="I was charged twice. Please refund the duplicate charge.",
                questions={"refund": {"type": "noul", "instructions": "Is a refund requested?"}},
            )
        call = post.call_args
        self.assertEqual(call.kwargs.get("url", call.args[0] if call.args else None), response.request.url)
        body = call.kwargs.get("json") or call.kwargs.get("data") or call.kwargs.get("content")
        if isinstance(body, (bytes, str)):
            body = json.loads(body)
        self.assertEqual(body["model"], "~typesafe/jev-latest")
        self.assertEqual(result.answers["refund"].noul, 0.98)
        self.assertAlmostEqual(result.usage.model_dump()["cost"], 0.0000042)


if __name__ == "__main__":
    unittest.main()
