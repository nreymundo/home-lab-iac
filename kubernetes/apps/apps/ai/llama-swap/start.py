import base64
import os
from pathlib import Path

# Authentik injects Basic auth; llama-swap also accepts its password as a bearer key.
scheme, encoded = os.environ.pop("LLAMA_BASIC_AUTH").split(" ", 1)
if scheme.lower() != "basic":
    raise ValueError("Expected Authentik Basic authorization")
_, password = base64.b64decode(encoded, validate=True).decode().split(":", 1)
os.environ["LLAMA_SWAP_API_KEY"] = password
# kubeswap supports environment values but cannot mount backend ConfigMaps.
for model in ("higgs", "chatterbox"):
    config = Path(f"/etc/llama-swap/audio-{model}.json").read_bytes()
    os.environ[f"AUDIOCPP_{model.upper()}_CONFIG"] = base64.b64encode(config).decode()
os.execvp("llama-swap", ["llama-swap", "-config", "/etc/llama-swap/config.yaml", "-listen", "0.0.0.0:8080"])
