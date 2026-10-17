"""Run in the deployed LiteLLM image with scripts/ on PYTHONPATH."""

import unittest

import litellm_startup
from litellm.llms.chatgpt.responses.transformation import ChatGPTResponsesAPIConfig
from litellm.llms.custom_httpx.llm_http_handler import BaseLLMHTTPHandler
from litellm.types.router import GenericLiteLLMParams


class ResponsesStringInputTests(unittest.TestCase):
    def transform(self, input_value, optional_params=None):
        return ChatGPTResponsesAPIConfig().transform_responses_api_request(
            model="chatgpt/gpt-6.1-sol",
            input=input_value,
            response_api_optional_request_params=optional_params or {},
            litellm_params=GenericLiteLLMParams(),
            headers={},
        )

    def test_nonempty_string_becomes_user_message(self):
        request = self.transform("hello")
        self.assertEqual(
            request["input"],
            [{"role": "user", "content": [{"type": "input_text", "text": "hello"}]}],
        )
        self.assertTrue(request["stream"])
        self.assertFalse(request["store"])

    def test_list_input_and_tool_result_survive(self):
        input_value = [
            {"role": "user", "content": [{"type": "input_text", "text": "hello"}]},
            {"type": "function_call_output", "call_id": "call_1", "output": "OK"},
        ]
        self.assertEqual(self.transform(input_value)["input"], input_value)

    def test_empty_string_stays_empty(self):
        self.assertEqual(self.transform("")["input"], "")

    def test_tools_and_tool_choice_survive(self):
        tools = [{"type": "function", "name": "echo", "parameters": {}}]
        request = self.transform("call echo", {"tools": tools, "tool_choice": "required"})
        self.assertEqual(request["tools"], tools)
        self.assertEqual(request["tool_choice"], "required")

    def test_startup_is_idempotent_and_other_request_patches_stay_disabled(self):
        transform = ChatGPTResponsesAPIConfig.transform_responses_api_request
        litellm_startup.worker_startup_hook()
        self.assertIs(ChatGPTResponsesAPIConfig.transform_responses_api_request, transform)
        self.assertTrue(getattr(transform, "_chatgpt_responses_string_input_patch", False))
        self.assertFalse(getattr(transform, "_chatgpt_responses_request_patch", False))
        self.assertFalse(
            getattr(BaseLLMHTTPHandler.async_response_api_handler, "_chatgpt_streaming_patch", False)
        )


if __name__ == "__main__":
    unittest.main()
