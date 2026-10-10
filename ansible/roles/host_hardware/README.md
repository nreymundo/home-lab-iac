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
| `host_hardware_physical` | derived from virtualization role | Override if virtualization facts do not describe the actual physical/guest intent. Controls physical CPU microcode and gates the physical diagnostic package set. |
| `host_hardware_enable_universe` | `true` | Enable missing universe/multiverse components in Ubuntu's existing sources using its APT source library. |
| `host_hardware_install_diagnostics` | `true` | Install PCI, VAAPI, OpenCL, Vulkan, sensor and optional physical-host diagnostic tools. The physical package set is installed only when `host_hardware_physical` is true. |
| `host_hardware_physical_diagnostic_packages` | `powertop`, `smartmontools`, `nvme-cli`, `hdparm`, `usbutils`, `dmidecode`, `lshw`, `msr-tools`, `fio`, `stress-ng`, `memtester` | Optional package list installed on physical hosts when diagnostics are enabled. Override to add or replace this set. |
| `host_hardware_linux_tools_packages` | `null` (automatic) | `null` selects `linux-tools-<running-kernel-ABI>` plus the tools tracking meta inferred only from installed `linux-image-generic`/supported HWE image metas. An explicit list replaces automatic selection; `[]` disables Linux tools packages. |
| `host_hardware_gpu_sysfs_root` | `/sys/bus/pci/devices` | Override for isolated discovery fixtures. |
| `host_hardware_render_root` | `/dev/dri` | DRM node root, primarily useful for fixtures. |

The role installs `linux-firmware` on both supported releases, maps Intel/AMD microcode from CPU facts only on physical hosts, and installs/enables `qemu-guest-agent` for KVM guests. Physical-host diagnostic packages are gated by both `host_hardware_physical` and `host_hardware_install_diagnostics`; their defaults include `powertop` and the package set above. Automatic Linux tools selection reads installed package facts only on that physical diagnostics lane. It always requests the exact running-kernel ABI package, then adds a tracking meta only when an installed image meta is recognized (`linux-image-generic`, `linux-image-generic-hwe-24.04`, or `linux-image-generic-hwe-26.04`). If there is no recognized meta, only the exact ABI package is selected; no GA/HWE assumption is made from the `-generic` kernel suffix. GPU diagnostics report PCI IDs, driver binding, and stable render paths. Requested validation fails if no stable render device exists. Optional VAAPI uses the stable `/dev/dri/by-path/pci-…-render` path; OpenCL/Vulkan checks are opt-in. A VM with no exposed GPU does not gain an inferred AMD profile from its CPU.

Package lists are the unique composition of the release baseline, physical CPU firmware, enabled diagnostics, detected/explicit GPU profile packages, and `host_hardware_extra_packages`. The role's helper uses `python3-apt` to enable missing components in the existing `ubuntu.sources` (or legacy `sources.list`), retaining mirrors, suites and signing settings. Files are saved only when components are missing; check mode reports changes without writing. Unlike noble's `add-apt-repository`, this supports deb822 on both releases. Third-party source files are left alone. Ubuntu maps use `mesa-va-drivers` on noble and `mesa-libgallium` on resolute for AMD VAAPI. No ROCm stack or vendor kernel is installed.

Tasks are independently reachable with `hardware`, `gpu`, and `packages` tags; narrow tags do not apply to unrelated dynamic include tasks. Users/groups are untouched unless `host_hardware_gpu_users` is set.
