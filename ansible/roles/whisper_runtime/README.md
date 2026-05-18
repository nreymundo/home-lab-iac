# Whisper Runtime Role

Builds and installs `whisper.cpp` for STT workloads in LLM LXCs.

The default build enables the Vulkan backend so STT can run alongside the ROCm
`llama.cpp` runtime without changing the known-good LLM build.

Important parameters:

- `whisper_runtime_repo`
- `whisper_runtime_ref`
- `whisper_runtime_update`
- `whisper_runtime_depth`
- `whisper_runtime_enable_vulkan`
- `whisper_runtime_build_examples`
- `whisper_runtime_packages`
- `whisper_runtime_force_rebuild`
- `whisper_runtime_extra_cmake_args`

`whisper_runtime_build_examples` controls whether the upstream examples are
built. Keep it enabled when using `whisper-server`, including through
`llama-swap`; when disabled, the role skips the `whisper-server --help`
validation.

Source updates are opt-in with `whisper_runtime_update`, matching the
`llm_runtime` role. To update from `master`, set `whisper_runtime_update: true`
for one playbook run, then set it back to `false`.
