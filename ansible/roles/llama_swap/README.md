# llama-swap Role

Installs the newest stable `llama-swap` release from upstream GitHub and runs
it as a systemd service in LLM LXCs.

The role exposes an OpenAI-compatible endpoint on the LXC and starts local
`llama-server`, `whisper-server`, or optional audio.cpp backends on dynamic
localhost ports.

Every run resolves the latest stable release via the GitHub releases API
(`llama_swap_release_api_url`), selects the Linux amd64 asset matching
`llama_swap_asset_pattern`, and verifies the archive download against the
release asset's published sha256 digest. New upstream releases are picked up
automatically on the next run; when the latest tag, published digest, and local
artifacts are unchanged, the role neither redownloads nor reinstalls.

Important parameters:

- `llama_swap_release_api_url`
- `llama_swap_asset_pattern`
- `llama_swap_environment`
- `llama_swap_listen`
- `llama_swap_start_port`
- `llama_swap_global_ttl`
- `llama_swap_models_dir`
- `llama_swap_default_context_size`
- `llama_swap_default_gpu_layers`
- `llama_swap_default_extra_args`
- `llama_swap_whisper_models_dir`
- `llama_swap_whisper_default_extra_args`

On first run only, the role scans `llama_swap_models_dir` for `*.gguf` files and
`llama_swap_whisper_models_dir` for Whisper `*.bin` files, then creates
`{{ llama_swap_config_path }}` with one backend per model. LLM model IDs are
based on each GGUF path relative to `llama_swap_models_dir`; STT model IDs are
prefixed with `whisper/`.

After the config file exists, the role does not modify it. Delete the file and
rerun the playbook to regenerate the bootstrap config, or edit it manually for
custom per-model settings.

The bootstrap config uses the Strix Halo flags from the ROCm toolbox guidance:

- `--no-mmap`
- `-ngl 999`
- `-fa 1`

## Kubernetes models and routing

The Kubernetes deployment is independent of this role. Its
[llama-swap catalog](../../../kubernetes/apps/apps/ai/llama-swap/config.yaml)
owns model files, placement, preloading, and runtime arguments;
[LiteLLM](../../../kubernetes/apps/apps/ai/litellm/configmap.yaml) owns client
aliases and fallback routes. Rerunning `llm_lxc.yml` changes neither catalog.

- The default local Qwen workhorse is Huihui Qwen3.8 27B Abliterated
  UD-Q4_K_XL. The Kubernetes service preloads it on `steadfast` using Gufo,
  with BF16 vision, DFlash2, and two 262,144-token sessions. `local/chat`,
  `local/coder`, `local/analysis`, and `local/document-analysis` use this
  backend or its task-specific profiles.
- The standard Unsloth Qwen3.8 27B Gufo backend remains available on demand.
  Check the catalog for exact model IDs and pinned artifacts instead of using
  the LXC's filename-derived model IDs.
- `cloud/stt` routes to OpenAI transcription first and falls back to
  `local/stt-fast` (Whisper large-v3-turbo). `local/stt-large` remains an explicit
  local option. These local routes use Kubernetes backends on `steadfast`, not
  the LXC's `whisper-server`.
