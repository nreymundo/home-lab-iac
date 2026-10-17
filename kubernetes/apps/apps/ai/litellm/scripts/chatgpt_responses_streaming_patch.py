import json

import httpx
import litellm
from litellm._logging import verbose_logger
from litellm.exceptions import MidStreamFallbackError
from litellm.llms.chatgpt.responses.transformation import (
    ChatGPTResponsesAPIConfig,
    record_output_item_chunk,
    record_output_text_chunk,
)
from litellm.llms.custom_httpx.llm_http_handler import (
    BaseLLMHTTPHandler,
    get_async_httpx_client,
)
from litellm.llms.custom_httpx.http_handler import AsyncHTTPHandler
from litellm.responses.streaming_iterator import ResponsesAPIStreamingIterator
from litellm.types.llms.openai import ResponsesAPIStreamEvents
from litellm.types.utils import CallTypes
from litellm.llms.base_llm.responses.transformation import BaseResponsesAPIConfig


_original_async_response_api_handler = BaseLLMHTTPHandler.async_response_api_handler


class ChatGPTResponsesStreamingIterator(ResponsesAPIStreamingIterator):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._streamed_output_items = {}
        self._text_only_output_items = {}
        self._suppress_completed_response_logging = False

    def _handle_logging_completed_response(self):
        if self._suppress_completed_response_logging:
            return
        return super()._handle_logging_completed_response()

    async def __anext__(self):
        try:
            return await super().__anext__()
        except StopAsyncIteration:
            if self.completed_response is not None:
                raise
            error = litellm.APIError(
                status_code=502,
                message="ChatGPT Responses stream ended without a terminal event",
                model=self.model,
                llm_provider=self.custom_llm_provider or "chatgpt",
            )
            raise MidStreamFallbackError(
                message=str(error),
                model=self.model,
                llm_provider=self.custom_llm_provider or "chatgpt",
                original_exception=error,
                generated_content=self._generated_content,
                is_pre_first_chunk=not self._yielded_first_chunk,
            )

    def _process_chunk(self, chunk):
        if not chunk or chunk == "[DONE]":
            return super()._process_chunk(chunk)

        try:
            parsed_chunk = json.loads(chunk)
        except json.JSONDecodeError:
            return super()._process_chunk(chunk)

        if not isinstance(parsed_chunk, dict):
            return super()._process_chunk(chunk)

        event_type = parsed_chunk.get("type")
        if event_type == ResponsesAPIStreamEvents.OUTPUT_ITEM_DONE:
            record_output_item_chunk(
                parsed_chunk=parsed_chunk,
                output_items=self._streamed_output_items,
            )
        elif event_type == ResponsesAPIStreamEvents.OUTPUT_TEXT_DONE:
            record_output_text_chunk(
                parsed_chunk=parsed_chunk,
                output_items=self._streamed_output_items,
                text_only_items=self._text_only_output_items,
            )
        elif event_type in (
            ResponsesAPIStreamEvents.RESPONSE_COMPLETED,
            ResponsesAPIStreamEvents.RESPONSE_INCOMPLETE,
        ):
            response_payload = parsed_chunk.get("response")
            if isinstance(response_payload, dict) and not response_payload.get("output"):
                merged_items = {**self._text_only_output_items}
                merged_items.update(self._streamed_output_items)
                if merged_items:
                    parsed_chunk = dict(parsed_chunk)
                    parsed_chunk["response"] = dict(response_payload)
                    parsed_chunk["response"]["output"] = [
                        item for _, item in sorted(merged_items.items())
                    ]

        return super()._process_chunk(json.dumps(parsed_chunk))


async def _chatgpt_streaming_response_api_handler(
    self,
    model,
    input,
    responses_api_provider_config,
    response_api_optional_request_params,
    custom_llm_provider,
    litellm_params,
    logging_obj,
    extra_headers=None,
    extra_body=None,
    timeout=None,
    client=None,
    fake_stream=False,
    litellm_metadata=None,
    shared_session=None,
):
    if (
        custom_llm_provider != "chatgpt"
        or not isinstance(responses_api_provider_config, ChatGPTResponsesAPIConfig)
    ):
        return await _original_async_response_api_handler(
            self,
            model=model,
            input=input,
            responses_api_provider_config=responses_api_provider_config,
            response_api_optional_request_params=response_api_optional_request_params,
            custom_llm_provider=custom_llm_provider,
            litellm_params=litellm_params,
            logging_obj=logging_obj,
            extra_headers=extra_headers,
            extra_body=extra_body,
            timeout=timeout,
            client=client,
            fake_stream=fake_stream,
            litellm_metadata=litellm_metadata,
            shared_session=shared_session,
        )

    if client is None or not isinstance(client, AsyncHTTPHandler):
        async_httpx_client = get_async_httpx_client(
            llm_provider=litellm.LlmProviders(custom_llm_provider),
            params={"ssl_verify": litellm_params.get("ssl_verify", None)},
            shared_session=shared_session,
        )
    else:
        async_httpx_client = client

    headers = responses_api_provider_config.validate_environment(
        headers=response_api_optional_request_params.get("extra_headers", {}) or {},
        model=model,
        litellm_params=litellm_params,
    )
    headers.setdefault("Accept", "text/event-stream")
    if extra_headers:
        headers.update(extra_headers)

    api_base = responses_api_provider_config.get_complete_url(
        api_base=litellm_params.api_base,
        litellm_params=dict(litellm_params),
    )
    data = responses_api_provider_config.transform_responses_api_request(
        model=model,
        input=input,
        response_api_optional_request_params=response_api_optional_request_params,
        litellm_params=litellm_params,
        headers=headers,
    )
    data = BaseResponsesAPIConfig.normalize_responses_api_request_dict(data)
    return_stream = bool(response_api_optional_request_params.get("stream", False))
    if extra_body:
        data.update(extra_body)
    data["stream"] = True

    request_context = {"input": input}
    try:
        request_context.update(response_api_optional_request_params)
    except Exception:
        pass
    request_context["litellm_params"] = dict(litellm_params)

    logging_obj.pre_call(
        input=input,
        api_key="",
        additional_args={
            "complete_input_dict": data,
            "api_base": api_base,
            "headers": headers,
        },
    )

    try:
        req = async_httpx_client.client.build_request(
            "POST",
            api_base,
            headers=headers,
            json=data,
            timeout=timeout or float(response_api_optional_request_params.get("timeout", 0)),
        )
        response = await async_httpx_client.client.send(req, stream=True)
        response.raise_for_status()
    except Exception as exc:
        error_response = getattr(exc, "response", None)
        if error_response is not None:
            try:
                await error_response.aread()
            except Exception:
                pass
        raise self._handle_error(
            e=exc,
            provider_config=responses_api_provider_config,
        )

    verbose_logger.debug("Using local ChatGPT Responses streaming patch")
    iterator = ChatGPTResponsesStreamingIterator(
        response=response,
        model=model,
        logging_obj=logging_obj,
        responses_api_provider_config=responses_api_provider_config,
        litellm_metadata=litellm_metadata,
        custom_llm_provider=custom_llm_provider,
        request_data=request_context,
        call_type=CallTypes.responses.value,
    )
    if return_stream or fake_stream:
        return iterator

    iterator._suppress_completed_response_logging = True
    async for _ in iterator:
        pass
    completed_response = iterator._get_completed_response_object()
    if completed_response is None:
        raise ValueError("ChatGPT Responses stream ended without a completed response")
    return completed_response


def patch_chatgpt_responses_streaming():
    if getattr(BaseLLMHTTPHandler.async_response_api_handler, "_chatgpt_streaming_patch", False):
        return
    _chatgpt_streaming_response_api_handler._chatgpt_streaming_patch = True
    BaseLLMHTTPHandler.async_response_api_handler = _chatgpt_streaming_response_api_handler


def worker_startup_hook():
    patch_chatgpt_responses_streaming()
