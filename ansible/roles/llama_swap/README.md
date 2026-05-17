# llama-swap Role

Installs `llama-swap` from the upstream release binary and runs it as a systemd
service in LLM LXCs.

The role exposes one public OpenAI-compatible endpoint with `llama-swap` and
lets it start `llama-server` backends on dynamic localhost ports.

Important parameters:

- `llama_swap_version`
- `llama_swap_archive_url`
- `llama_swap_archive_checksum`
- `llama_swap_environment`
- `llama_swap_listen`
- `llama_swap_start_port`
- `llama_swap_global_ttl`
- `llama_swap_models_dir`
- `llama_swap_default_context_size`
- `llama_swap_default_gpu_layers`
- `llama_swap_default_extra_args`

On first run only, the role scans `llama_swap_models_dir` for `*.gguf` files and
creates `{{ llama_swap_config_path }}` with one `llama-server` backend per model.
Model IDs are based on each GGUF path relative to `llama_swap_models_dir`.

After the config file exists, the role does not modify it. Delete the file and
rerun the playbook to regenerate the bootstrap config, or edit it manually for
custom per-model settings.

The bootstrap config uses the Strix Halo flags from the ROCm toolbox guidance:

- `--no-mmap`
- `-ngl 999`
- `-fa 1`
