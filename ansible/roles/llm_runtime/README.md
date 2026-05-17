# LLM Runtime Role

Installs the ROCm userspace and builds `llama.cpp` for Strix Halo Fedora LXCs.

The role mirrors the important parts of the
`kyuz0/amd-strix-halo-toolboxes` ROCm toolbox:

- ROCm repository and runtime/build packages;
- ROCm shell environment;
- `llama.cpp` clone, grammar patch, ROCm/HIP build, and install;
- `gguf-vram-estimator.py` helper;
- validation with `rocminfo` and `llama-cli`.

Important parameters:

- `llm_runtime_rocm_version`
- `llm_runtime_llama_repo`
- `llm_runtime_llama_ref`
- `llm_runtime_llama_update`
- `llm_runtime_llama_depth`
- `llm_runtime_llama_single_branch`
- `llm_runtime_amdgpu_targets`
- `llm_runtime_cmake_hip_flags`
- `llm_runtime_enable_rpc`
- `llm_runtime_enable_unified_memory`
- `llm_runtime_force_rebuild`
- `llm_runtime_extra_packages`
- `llm_runtime_vram_estimator_url`

The role writes `{{ llm_runtime_llama_marker_path }}` after a successful build.
Changing the ROCm version, llama.cpp ref, build flags, or patch settings causes
the next playbook run to rebuild. Source updates are opt-in with
`llm_runtime_llama_update` so normal runs do not reset the patched source tree.
