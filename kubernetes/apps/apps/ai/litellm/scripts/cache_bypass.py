import json
from typing import Literal

from litellm.integrations.custom_logger import CustomLogger
from litellm.proxy.proxy_server import DualCache, UserAPIKeyAuth


class CacheBypassHandler(CustomLogger):
    async def async_pre_call_hook(
        self,
        user_api_key_dict: UserAPIKeyAuth,
        cache: DualCache,
        data: dict,
        call_type: Literal[
            "completion",
            "text_completion",
            "embeddings",
            "image_generation",
            "moderation",
            "audio_transcription",
        ],
    ):
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


proxy_handler_instance = CacheBypassHandler()
