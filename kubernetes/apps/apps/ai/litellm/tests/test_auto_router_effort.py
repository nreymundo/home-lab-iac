"""Exercise the deployed LiteLLM version with the repo config and mocked HTTP.

Run with LiteLLM installed, from any directory: python test_auto_router_effort.py.
All provider HTTP is intercepted; no credentials or live inference are needed.
"""

import copy
import json
from pathlib import Path
import unittest
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from cache_bypass import CacheBypassHandler
from litellm.proxy._types import UserAPIKeyAuth
import litellm
from unittest.mock import AsyncMock, patch

import httpx
import yaml
from litellm import Router
from litellm.router_strategy.complexity_router.jev_classifier import JevSystemOneResponse

CONFIG = yaml.safe_load(
    yaml.safe_load((Path(__file__).resolve().parents[1] / "configmap.yaml").read_text())["data"]["config.yaml"]
)
DEPLOYMENTS = {entry["model_name"]: entry for entry in CONFIG["model_list"]}
AUTOS = ("cloud/codex-auto", "cloud/glm-auto")
CARRIERS = (
    {"reasoning_effort": "xhigh"},
    {"reasoning": {"effort": "xhigh", "summary": "auto"}},
    {"reasoning_effort": "xhigh", "reasoning": {"effort": "xhigh", "summary": "auto"}},
)
IMAGE = [{"role": "user", "content": [
    {"type": "text", "text": "Describe this image."},
    {"type": "image_url", "image_url": {"url": "data:image/png;base64,"
     "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="}},
]}]


def verdict(tier):
    return JevSystemOneResponse(answers={"tier": {
        "type": "choice", "choice": tier, "confidence": 1.0,
        "probabilities": {name: float(name == tier) for name in ("SIMPLE", "MEDIUM", "COMPLEX", "REASONING")},
    }})


def effort(body):
    return (body.get("reasoning") or {}).get("effort") or body.get("reasoning_effort")


class AutoRouterEffortTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.sent = []
        self.fail_models = set()
        names = set(AUTOS)
        for auto in AUTOS:
            names.update(entry["model_name"] for entry in self.tiers(auto).values())
        names.update(("chatgpt/gpt-6.1-sol", "zai-coding/glm-5.3", "zai-coding/glm-5.3-flash",
                      "openrouter/~typesafe/jev-latest"))
        models = [copy.deepcopy(DEPLOYMENTS[name]) for name in sorted(names)]
        for entry in models:
            params = entry["litellm_params"]
            if entry["model_name"] not in AUTOS:
                params.pop("litellm_credential_name", None)
                params["api_key"] = "test-only"
                params["api_base"] = "https://provider.invalid/v1"
                # Exercise native Responses routing without subscription auth or live SSE.
                params["model"] = params["model"].replace("chatgpt/", "openai/")
        self.router = Router(
            model_list=models, num_retries=0, allowed_fails=100,
            model_group_alias=CONFIG["router_settings"]["model_group_alias"],
            fallbacks=CONFIG["router_settings"]["fallbacks"],
        )
        self.hook = CacheBypassHandler()
        self.patches = []
        self.original_callbacks = litellm.callbacks[:]
        litellm.callbacks = [self.hook]
        self.addCleanup(setattr, litellm, "callbacks", self.original_callbacks)
        self.evaluators = {}
        self.patches = [patch.object(httpx.AsyncClient, "send", side_effect=self.transport)]
        for auto in AUTOS:
            strategy = self.router.complexity_routers[auto][0].strategy
            # Disable timeout breaker to keep independent cases within a test independent.
            strategy._classifier_circuit_breaker = None
            evaluator = AsyncMock(return_value=verdict("SIMPLE"))
            self.evaluators[auto] = evaluator
            self.patches.append(patch.object(strategy._jev_client, "evaluate", evaluator))
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)

    @staticmethod
    def tiers(auto):
        return DEPLOYMENTS[auto]["litellm_params"]["complexity_router_config"]["tiers"]

    async def transport(self, request, **kwargs):
        body = json.loads(request.content)
        self.sent.append(body)
        if body["model"] in self.fail_models:
            return httpx.Response(503, request=request, json={"error": {
                "message": "synthetic provider outage", "type": "server_error"}})
        chat = request.url.path.endswith("/chat/completions")
        if chat:
            result = {"id": "chatcmpl-test", "object": "chat.completion", "created": 1,
                      "model": body["model"], "choices": [{"index": 0, "message": {
                          "role": "assistant", "content": "OK"}, "finish_reason": "stop"}],
                      "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}
        else:
            result = {"id": "resp_test", "object": "response", "created_at": 1,
                      "status": "completed", "model": body["model"], "output": [{
                          "id": "msg_test", "type": "message", "role": "assistant", "status": "completed",
                          "content": [{"type": "output_text", "text": "OK", "annotations": []}]}],
                      "parallel_tool_calls": True, "tool_choice": "auto", "tools": [],
                      "reasoning": body.get("reasoning"),
                      "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}}
        if body.get("stream"):
            if chat:
                events = [{"id": "chatcmpl-test", "object": "chat.completion.chunk", "created": 1,
                           "model": body["model"], "choices": [{"index": 0, "delta": {"content": "OK"},
                                                                "finish_reason": None}]},
                          {"id": "chatcmpl-test", "object": "chat.completion.chunk", "created": 1,
                           "model": body["model"], "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}]
            else:
                events = [{"type": "response.created", "response": {**result, "status": "in_progress", "output": []}},
                          {"type": "response.completed", "response": result}]
            data = "".join("data: " + json.dumps(event) + "\n\n" for event in events)
            if chat:
                data += "data: [DONE]\n\n"
            return httpx.Response(200, request=request, text=data, headers={"content-type": "text/event-stream"})
        return httpx.Response(200, request=request, json=result)

    async def call(self, model, surface="responses", carrier=None, messages=None, **kwargs):
        request = {"model": model, **copy.deepcopy(carrier or {}), **kwargs}
        messages = copy.deepcopy(messages or [{"role": "user", "content": "Explain a Python list."}])
        await self.hook.async_pre_call_hook(UserAPIKeyAuth(), None, request, "acompletion" if surface == "chat" else "aresponses")
        if surface == "chat":
            response = await self.router.acompletion(messages=messages, **request)
        else:
            items = []
            for message in messages:
                if message["role"] == "tool":
                    items.append({"type": "function_call_output", "call_id": message["tool_call_id"],
                                  "output": message["content"]})
                    continue
                for tool in message.get("tool_calls", []):
                    items.append({"type": "function_call", "call_id": tool["id"], **tool["function"]})
                content = message.get("content")
                if content is None:
                    continue
                if isinstance(content, list):
                    content = [{"type": "input_image", "image_url": part["image_url"]["url"]}
                               if part["type"] == "image_url" else {"type": "input_text", "text": part["text"]}
                               for part in content]
                items.append({"role": message["role"], "content": content})
            response = await self.router.aresponses(input=items, **request)
        if request.get("stream"):
            chunks = [chunk async for chunk in response]
            self.assertTrue(chunks)
        return self.sent[-1]

    async def test_every_tier_overrides_client_effort(self):
        for auto in AUTOS:
            for tier, entry in self.tiers(auto).items():
                self.evaluators[auto].return_value = verdict(tier)
                for surface in ("chat", "responses"):
                    for carrier in CARRIERS:
                        with self.subTest(auto=auto, tier=tier, surface=surface, carrier=carrier):
                            body = await self.call(auto, surface, carrier)
                            self.assertEqual(effort(body), entry["litellm_params"]["reasoning_effort"])
                            self.assertEqual(body["model"], DEPLOYMENTS[entry["model_name"]]["litellm_params"]["model"].split("/", 1)[1])

    async def test_classifier_failure_enforces_default_effort(self):
        for auto in AUTOS:
            self.evaluators[auto].side_effect = TimeoutError("synthetic classifier timeout")
            for surface in ("chat", "responses"):
                for carrier in CARRIERS:
                    with self.subTest(auto=auto, surface=surface, carrier=carrier):
                        body = await self.call(auto, surface, carrier)
                        self.assertEqual(effort(body), "high")
                        self.assertEqual(body["model"], "gpt-6-astra" if "codex" in auto else "glm-5.3")

    async def test_provider_fallback_retains_selected_effort(self):
        for auto in AUTOS:
            for tier, entry in self.tiers(auto).items():
                self.evaluators[auto].return_value = verdict(tier)
                primary = DEPLOYMENTS[entry["model_name"]]["litellm_params"]["model"].split("/", 1)[1]
                self.fail_models = {primary}
                for surface in ("chat", "responses"):
                    for carrier in CARRIERS:
                        with self.subTest(auto=auto, tier=tier, surface=surface, carrier=carrier):
                            body = await self.call(auto, surface, carrier)
                            self.assertNotEqual(body["model"], primary)
                            self.assertEqual(effort(body), entry["litellm_params"]["reasoning_effort"])
                self.fail_models.clear()

    async def test_glm_image_paths_enforce_router_effort(self):
        auto = "cloud/glm-auto"
        for failure in (False, True):
            self.evaluators[auto].return_value = verdict("REASONING")
            self.evaluators[auto].side_effect = TimeoutError("synthetic timeout") if failure else None
            for surface in ("chat", "responses"):
                for carrier in CARRIERS:
                    with self.subTest(failure=failure, surface=surface, carrier=carrier):
                        body = await self.call(auto, surface, carrier, messages=IMAGE)
                        self.assertEqual(body["model"], "glm-5.3-flash")
                        self.assertEqual(effort(body), "low" if failure else "high")

    async def test_streaming_enforces_selected_effort(self):
        for auto in AUTOS:
            for surface in ("chat", "responses"):
                for carrier in CARRIERS:
                    with self.subTest(auto=auto, surface=surface, carrier=carrier):
                        body = await self.call(auto, surface, carrier, stream=True)
                        self.assertEqual(effort(body), "low")

    async def test_direct_model_keeps_client_effort(self):
        for model in ("chatgpt/gpt-6.1-sol", "cloud/codex-luna-low"):
            for surface in ("chat", "responses"):
                for carrier in CARRIERS[:2]:
                    with self.subTest(model=model, surface=surface, carrier=carrier):
                        body = await self.call(model, surface, carrier)
                        self.assertEqual(effort(body), "xhigh")
        for evaluator in self.evaluators.values():
            evaluator.assert_not_awaited()

    async def test_continuations_retain_effort_new_user_turn_reclassifies(self):
        for auto in AUTOS:
            for surface in ("chat", "responses"):
                metadata = {"session_id": auto + surface}
                messages = [{"role": "user", "content": "Check the project files."}]
                evaluator = self.evaluators[auto]
                evaluator.return_value = verdict("SIMPLE")
                await self.call(auto, surface, CARRIERS[2], messages=messages, metadata=metadata)
                count = evaluator.await_count
                messages += [{"role": "assistant", "content": None, "tool_calls": [{
                    "id": "call_1", "type": "function", "function": {"name": "read_file", "arguments": "{}"}}]},
                    {"role": "tool", "tool_call_id": "call_1", "content": "Read successfully."}]
                body = await self.call(auto, surface, CARRIERS[2], messages=messages, metadata=metadata)
                self.assertEqual(evaluator.await_count, count)
                self.assertEqual(effort(body), "low")
                evaluator.return_value = verdict("COMPLEX")
                messages += [{"role": "assistant", "content": "Done."}, {"role": "user", "content": "Now redesign it."}]
                body = await self.call(auto, surface, CARRIERS[2], messages=messages, metadata=metadata)
                self.assertEqual(evaluator.await_count, count + 1)
                self.assertEqual(effort(body), "high")

    async def test_alternate_effort_carriers_are_removed_at_ingress(self):
        for auto in AUTOS:
            data = {
                "model": auto,
                "reasoning_effort": "xhigh",
                "thinking": {"type": "enabled", "budget_tokens": 32000},
                "reasoning": {"effort": "xhigh", "summary": "auto"},
                "output_config": {"effort": "max", "format": {"type": "text"}},
                "extra_body": {"reasoning_effort": "xhigh", "thinking": {"type": "enabled"},
                               "reasoning": {"effort": "xhigh", "summary": "auto"},
                               "output_config": {"effort": "max", "format": {"type": "text"}}},
            }
            await self.hook.async_pre_call_hook(UserAPIKeyAuth(), None, data, "aresponses")
            for bucket in (data, data["extra_body"]):
                self.assertNotIn("reasoning_effort", bucket)
                self.assertNotIn("thinking", bucket)
                self.assertEqual(bucket["reasoning"], {"summary": "auto"})
                self.assertEqual(bucket["output_config"], {"format": {"type": "text"}})
        direct = {"model": "chatgpt/gpt-6.1-sol", "reasoning": {"effort": "xhigh", "summary": "auto"}}
        before = copy.deepcopy(direct)
        await self.hook.async_pre_call_hook(UserAPIKeyAuth(), None, direct, "aresponses")
        self.assertEqual(direct, before)

    async def test_streaming_provider_fallback_retains_effort(self):
        for auto in AUTOS:
            entry = self.tiers(auto)["SIMPLE"]
            primary = DEPLOYMENTS[entry["model_name"]]["litellm_params"]["model"].split("/", 1)[1]
            self.fail_models = {primary}
            for surface in ("chat", "responses"):
                with self.subTest(auto=auto, surface=surface):
                    body = await self.call(auto, surface, CARRIERS[2], stream=True)
                    self.assertNotEqual(body["model"], primary)
                    self.assertEqual(effort(body), "low")
            self.fail_models.clear()

    async def test_direct_glm_models_keep_supported_client_effort(self):
        for model in ("zai-coding/glm-5.3", "cloud/glm-flash-low"):
            for surface in ("chat", "responses"):
                for carrier in ({"reasoning_effort": "max"}, {"reasoning": {"effort": "max"}}):
                    with self.subTest(model=model, surface=surface, carrier=carrier):
                        body = await self.call(model, surface, carrier)
                        self.assertEqual(effort(body), "max")

    async def test_existing_key_cache_and_parameter_controls_are_preserved(self):
        model = "chatgpt/gpt-6.1-sol"
        data = {"model": model, "temperature": 0.2, "top_p": 0.8, "reasoning_effort": "xhigh"}
        auth = UserAPIKeyAuth(metadata={"bypass_redis_cache": True,
                                      "drop_request_params": ["temperature"],
                                      "drop_request_params_by_model": {model: ["top_p"]}})
        await self.hook.async_pre_call_hook(auth, None, data, "acompletion")
        self.assertEqual(data["cache"], {"no-cache": True, "no-store": True})
        self.assertNotIn("temperature", data)
        self.assertNotIn("top_p", data)
        self.assertEqual(data["reasoning_effort"], "xhigh")

    async def test_glm_image_provider_failure_preserves_effort(self):
        auto = "cloud/glm-auto"
        self.fail_models = {"glm-5.3-flash"}
        for failure in (False, True):
            self.evaluators[auto].return_value = verdict("REASONING")
            self.evaluators[auto].side_effect = TimeoutError("synthetic timeout") if failure else None
            for surface in ("chat", "responses"):
                with self.subTest(failure=failure, surface=surface):
                    body = await self.call(auto, surface, CARRIERS[2], messages=IMAGE)
                    self.assertEqual(body["model"], "gpt-6.1-sol")
                    self.assertEqual(effort(body), "low" if failure else "high")

    async def test_chatgpt_adapter_enforces_effort_and_preserves_summary(self):
        from litellm.llms.chatgpt.authenticator import Authenticator

        self.enterContext(patch.object(Authenticator, "get_access_token", return_value="test-only"))
        self.enterContext(patch.object(Authenticator, "get_account_id", return_value="test-account"))
        self.enterContext(patch.object(Authenticator, "get_api_base", return_value="https://provider.invalid/v1"))

        names = {"cloud/codex-auto", "openrouter/~typesafe/jev-latest"}
        names.update(entry["model_name"] for entry in self.tiers("cloud/codex-auto").values())
        models = [copy.deepcopy(DEPLOYMENTS[name]) for name in sorted(names)]
        for entry in models:
            if entry["model_name"] == "openrouter/~typesafe/jev-latest":
                entry["litellm_params"].pop("litellm_credential_name", None)
                entry["litellm_params"]["api_key"] = "test-only"
        self.router = Router(model_list=models, num_retries=0)
        strategy = self.router.complexity_routers["cloud/codex-auto"][0].strategy
        evaluator = AsyncMock(return_value=verdict("SIMPLE"))
        # Mock subscription authentication only; run the actual ChatGPT adapter,
        # SSE parser, and native chat/Responses routing against synthetic HTTP.
        with patch.object(strategy._jev_client, "evaluate", evaluator):
            for tier, expected in (("SIMPLE", "low"), ("REASONING", "high")):
                evaluator.return_value = verdict(tier)
                for surface in ("chat", "responses"):
                    for stream in (False, True):
                        with self.subTest(tier=tier, surface=surface, stream=stream):
                            body = await self.call("cloud/codex-auto", surface, CARRIERS[2], stream=stream)
                            self.assertEqual(effort(body), expected)
                            self.assertEqual(body["reasoning"].get("summary"), "auto")

    async def test_responses_summary_is_preserved(self):
        body = await self.call("cloud/codex-auto", carrier=CARRIERS[1])
        self.assertEqual(body["reasoning"].get("summary"), "auto")
        self.assertEqual(effort(body), "low")


if __name__ == "__main__":
    unittest.main(verbosity=2)
