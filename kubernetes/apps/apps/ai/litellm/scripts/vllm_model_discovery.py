import os

import litellm
from litellm.llms.vllm.common_utils import VLLMModelInfo
from litellm.utils import _add_path_to_api_base


def patch_vllm_model_discovery():
    def get_models(self, api_key=None, api_base=None):
        api_base = api_base or os.environ.get("VLLM_API_BASE") or os.environ.get(
            "LITELLM_CREDENTIAL_LLAMA_SWAP_API_BASE"
        )
        api_key = api_key or os.environ.get("VLLM_API_KEY") or os.environ.get(
            "LITELLM_CREDENTIAL_LLAMA_SWAP_API_KEY"
        )

        if api_base is None:
            raise ValueError("VLLM_API_BASE is not set")

        headers = {}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
            headers["x-api-key"] = api_key

        response = litellm.module_level_client.get(
            url=_add_path_to_api_base(api_base, "/v1/models"),
            headers=headers,
        )
        response.raise_for_status()

        return [model["id"] for model in response.json().get("data", [])]

    VLLMModelInfo.get_models = get_models
    litellm.models_by_provider.setdefault("hosted_vllm", [])


def worker_startup_hook():
    patch_vllm_model_discovery()
