# host_hardware

Reusable Ubuntu 24.04 (`noble`) and 26.04 (`resolute`) CPU/GPU enablement. CPU vendor facts select physical microcode; PCI display devices independently select GPU userspace, including devices passed through to a guest. This role does not configure hypervisor VFIO.

## API

| Variable | Default | Purpose |
| --- | --- | --- |
| `host_hardware_gpu_profiles` | `['auto']` | Automatically select detected Intel/AMD PCI GPU profiles; `[]` disables GPU packages; explicit `['intel']`, `['amd']`, or both override discovery. |
| `host_hardware_extra_packages` | `[]` | Add packages to (never replace) the role package list. |
| `host_hardware_gpu_users` | `[]` | Users to append to `render` and `video`; caller may pass `common_user`. |
| `host_hardware_validate_gpu` | `false` | Opt-in headless validation. Packages alone never imply acceleration. |
| `host_hardware_validate_opencl` | `false` | Additionally run `clinfo`; AMD uses `RUSTICL_ENABLE=radeonsi`. |
| `host_hardware_validate_vulkan` | `false` | Additionally run `vulkaninfo --summary`. |
| `host_hardware_physical` | derived from virtualization role | Override if virtualization facts do not describe the actual physical/guest intent. Controls CPU microcode and powertop. |
| `host_hardware_enable_universe` | `true` | Enable missing universe/multiverse components in Ubuntu's existing sources using its native repository tool. |
| `host_hardware_install_diagnostics` | `true` | Install PCI, VAAPI, OpenCL, Vulkan and sensor diagnostic tools. |
| `host_hardware_gpu_sysfs_root` | `/sys/bus/pci/devices` | Override for isolated discovery fixtures. |
| `host_hardware_render_root` | `/dev/dri` | DRM node root, primarily useful for fixtures. |

The role installs `linux-firmware` on both supported releases, maps Intel/AMD microcode from CPU facts only on physical hosts, and installs/enables `qemu-guest-agent` for KVM guests. GPU diagnostics report PCI IDs, driver binding, and stable render paths. Requested validation fails if no stable render device exists. Optional VAAPI uses the stable `/dev/dri/by-path/pci-…-render` path; OpenCL/Vulkan checks are opt-in. A VM with no exposed GPU does not gain an inferred AMD profile from its CPU.

Package lists are the unique composition of the release baseline, physical CPU firmware, enabled diagnostics, detected/explicit GPU profile packages, and `host_hardware_extra_packages`. Ubuntu's `add-apt-repository` enables missing components in the existing `ubuntu.sources` (or legacy `sources.list`), retaining mirrors, suites and signing settings. Third-party source files are left alone. Ubuntu maps use `mesa-va-drivers` on noble and `mesa-libgallium` on resolute for AMD VAAPI. No ROCm stack or vendor kernel is installed.

Tasks are independently reachable with `hardware`, `gpu`, and `packages` tags; narrow tags do not apply to unrelated dynamic include tasks. Users/groups are untouched unless `host_hardware_gpu_users` is set.
