import json
from typing import Literal

from litellm.integrations.custom_logger import CustomLogger
from litellm.proxy.proxy_server import DualCache, UserAPIKeyAuth

AUTO_ROUTES = {"cloud/codex-auto", "cloud/glm-auto"}
AUTO_EFFORT_MARKER = "_auto_router_manages_effort"


def remove_client_effort(data):
    for bucket in (data, data.get("extra_body")):
        if not isinstance(bucket, dict):
            continue
        bucket.pop("reasoning_effort", None)
        bucket.pop("thinking", None)
        for name in ("reasoning", "output_config"):
            value = bucket.get(name)
            if isinstance(value, dict):
                remaining = {key: item for key, item in value.items() if key != "effort"}
                if remaining:
                    bucket[name] = remaining
                else:
                    bucket.pop(name, None)


class CacheBypassHandler(CustomLogger):
    async def async_pre_call_hook(
        self,
        user_api_key_dict: UserAPIKeyAuth,
        cache: DualCache,
        data: dict,
        call_type: Literal[
            "completion",
            "acompletion",
            "responses",
            "aresponses",
            "text_completion",
            "embeddings",
            "image_generation",
            "moderation",
            "audio_transcription",
        ],
    ):
        # Auto routes own effort, including classifier failure and fallback paths.
        # Direct model requests retain the usual client-over-deployment precedence.
        managed_effort = data.get("model") in AUTO_ROUTES
        for name in ("metadata", "litellm_metadata"):
            if isinstance(data.get(name), dict):
                data[name].pop(AUTO_EFFORT_MARKER, None)
        if managed_effort:
            remove_client_effort(data)
            name = "litellm_metadata" if call_type in ("responses", "aresponses") else "metadata"
            if not isinstance(data.get(name), dict):
                data[name] = {}
            data[name][AUTO_EFFORT_MARKER] = True

        metadata = getattr(user_api_key_dict, "metadata", {}) or {}

        if isinstance(metadata, str):
            try:
                metadata = json.loads(metadata)
            except json.JSONDecodeError:
                metadata = {}

        if not isinstance(metadata, dict):
            metadata = {}

        if metadata.get("bypass_redis_cache") is True:
            cache_controls = data.setdefault("cache", {})
            cache_controls["no-cache"] = True
            cache_controls["no-store"] = True

        drop_request_params = metadata.get("drop_request_params")
        if isinstance(drop_request_params, list):
            for param in drop_request_params:
                if isinstance(param, str):
                    data.pop(param, None)

        drop_request_params_by_model = metadata.get("drop_request_params_by_model")
        model = data.get("model")
        if isinstance(drop_request_params_by_model, dict) and isinstance(model, str):
            model_drop_params = drop_request_params_by_model.get(model)
            if isinstance(model_drop_params, list):
                for param in model_drop_params:
                    if isinstance(param, str):
                        data.pop(param, None)

        return data

    async def async_pre_call_deployment_hook(self, kwargs, call_type):
        managed = any(
            isinstance(kwargs.get(name), dict) and kwargs[name].get(AUTO_EFFORT_MARKER) is True
            for name in ("metadata", "litellm_metadata")
        )
        # Responses treats a nested reasoning object as authoritative. Preserve
        # summary settings while applying the deployment/tier's resolved effort.
        if managed and kwargs.get("reasoning_effort") is not None and isinstance(kwargs.get("reasoning"), dict):
            kwargs["reasoning"] = {**kwargs["reasoning"], "effort": kwargs["reasoning_effort"]}
        return kwargs


proxy_handler_instance = CacheBypassHandler()
