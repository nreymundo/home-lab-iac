# Unified Ubuntu host provisioning

## Status

Implementation resumed on 2026-10-08 in `feat/ubuntu-host-provisioning` (PR #1407).
The unified entrypoint, inventory grouping, hardware/power corrections, laptop
extraction and optional Cockpit composition are implemented. This remains a
**implementation pending validation**. The first full run against `daring`
completed 101 tasks, with 31 changed and one failure: CPU frequency ceiling
readback immediately after a `4200000` kHz write returned `4900000` kHz, although
a later read returned `4200000` kHz. This happened before powertop auto-tuning
ran. The helper now retries exact readback for up to 20 × 50 ms; the
user-selected power-only rerun result has not been reported. Final policy
convergence, service recovery and reboot persistence remain unvalidated.

The earlier checkpoint is preserved in commit `b7e06c87`. Its incorrect nested
RAPL fixtures and missing entrypoint are superseded by the implementation below.

## Scope and ownership

One thin playbook configures manually installed Ubuntu Server 24.04 (`noble`)
or 26.04 (`resolute`) systems: bare metal, Proxmox VMs and headless laptops.
Ubuntu 26.04 is intended for the incoming physical machines. Inventory expresses
intent; gathered distribution facts and independently detected PCI GPUs determine
capabilities. `node_os` in generated VM inventory is a login username, not an OS
identifier.

| Owner | Responsibility |
| --- | --- |
| `common` | Administrator, validated passwordless sudo, baseline/group/host packages, identity, time, updates, logs, trim and Ubuntu boot parameters |
| `ssh_hardening` | Authorized keys, effective key-only SSH policy and restart |
| `host_hardware` | CPU microcode, firmware, Intel/AMD PCI GPU discovery, release-specific packages, diagnostics and KVM guest agent |
| `host_power` | One CPU policy backend, optional governor/EPP/boost/platform profile, explicit named powercap limits and optional powertop |
| `headless_laptop` | Lid/sleep behavior, charging threshold and ASUS fan curves |
| `cockpit` | Default-off per-host console, selected extensions, socket/package and firewall-rule lifecycle |
| Existing optional roles | UFW, fail2ban, Homebrew, Docker, Node.js, swap and explicitly configured VM disk expansion |

Generic host configuration remains separate from K3s installation, cluster
membership, hypervisor passthrough, ROCm and data migration.

## Inventory and defaults

`ansible/inventories/ubuntu.yml` is a hand-maintained aggregate of `all_vms`,
`headless_laptops` and `ubuntu_baremetal`. `daring` (`ubuntu@192.168.10.30`)
is defined in hand-maintained `baremetal.yml` and belongs only to
`ubuntu_baremetal`; it is not a K3s inventory member. Load the inventory
**directory**, not the aggregate alone: generated files provide VM identities.
Terraform-owned inventory was not edited. `pve3` remains a Proxmox host.

Fleet defaults in `group_vars/ubuntu_hosts.yml` enable unattended security and
regular updates, disable provisioning dist-upgrades and automatic reboots,
manage the designated administrator with validated NOPASSWD sudo, and require
key-only SSH without direct root login. Group/host overrides remain possible.
Existing VM and G14 automatic-reboot settings are now false.

The shared role defaults allow only Ubuntu security and stable-release updates.
Proxmox explicitly overrides the origins with Debian base, `-security` and
`-updates` repositories; unattended upgrades remain disabled there. Proxmox/vendor
repositories are not added to that automatic policy. The `rpi` group explicitly
retains its previous Debian, Debian-Security, Raspbian and Raspberry Pi Foundation
origins. A Pi installed with Ubuntu instead needs a host override selecting the
Ubuntu origins; origin policy follows the installed OS, not the hardware model.

Package composition is explicit: `common_packages` provides the baseline,
`common_group_packages` holds additive group requirements (e.g. VM `nfs-common`),
and `common_extra_packages` holds host additions. Ubuntu hosts additionally
compose `common_ubuntu_packages`; the `ubuntu_hosts` group builds it from
`ubuntu_utility_packages` and `ubuntu_security_packages` (empty by default). This
does not replace baseline, group, or host packages and does not affect other
Debian-family hosts. `auditd` is not installed by default. These additions only
install packages: they do not define service, firewall, or network policy, and
install toggles do not disable services that were already present. In
particular, `iperf3` is selected as a CLI utility, not as an intended server.
Automatic host reboots remain disabled. Check service state on rollout rather than assuming that
installing a package has no runtime side effects.
Hardware packages compose separately, with `host_hardware_extra_packages` as
their extension point; `daring` adds `intel-gpu-tools` and `ffmpeg` there.
GPU/boot/CPU policy settings have moved out of the laptop role. G14 retains its
power-saver PPD profile, charge threshold, fan percentage and selected tools.
Its ASUS helper only reads the platform profile; it never changes PPD's policy.
Disabling the fan policy stops/removes its timer and helper; firmware fan state
may need a profile change or reboot to return to defaults.

## Running

From the repository root, with the pinned Ansible dependencies and collections
installed (versions in `.github/workflows/ci.yml`):

```sh
# Read-only inventory and target inspection; no remote connection.
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-inventory --graph ubuntu_hosts
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/ubuntu.yml --list-hosts
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/ubuntu.yml --limit daring --list-hosts

# Provision only after checking bootstrap access and the manual rollout gates below.
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/ubuntu.yml --limit daring
```

The command above is a real provisioning operation. `--check` also connects to
hosts, gathers facts and runs selected read-only discovery commands; it is not
an offline test or a substitute for first-run validation. Existing SSH key
discovery still requires the configured 1Password service account. For bootstrap
using a different login, set the intended `common_user` explicitly and supply
working privilege escalation (`--ask-become-pass` when needed).

Use `ubuntu.yml` with a group limit to provision VMs or headless laptops:

```sh
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/ubuntu.yml --limit all_vms
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/ubuntu.yml --limit headless_laptops
```

Application-specific playbooks remain separate. Use the directory inventory so
fleet defaults are loaded.

| Tags | Scope |
| --- | --- |
| `base`, `packages`, `boot`, `ssh` | Common baseline, package installation, kernel arguments/reboot reporting, SSH policy |
| `hardware`, `gpu` | CPU/guest setup; GPU packages, group access and optional diagnostics |
| `power`, `preflight` | Power lifecycle; power input validation |
| `laptop` | Lid, sleep, charge threshold and ASUS fan policy |
| `homebrew`, `docker`, `nodejs`, `swap`, `disk` | Explicitly selected optional tools/storage behavior |
| `firewall`, `fail2ban`, `cockpit` | Explicit firewall/service configuration and console lifecycle |

Narrow tags assume prerequisites were provisioned already. For example, GPU
user membership needs an existing account, and `--tags cockpit` with firewall
sources needs UFW already installed. Distribution validation always runs.

## Hardware and power

See the [hardware API](../ansible/roles/host_hardware/README.md) and
[power API](../ansible/roles/host_power/README.md) for all variables.
Hardware repositories are prepared using Ubuntu's APT source library before
hardware packages. Existing mirrors and signing settings are retained;
source files are written only when components are missing.
Requested GPU validation fails when no stable render device exists;
package installation alone does not establish working acceleration.

Physical diagnostics are optional through `host_hardware_install_diagnostics`
and are restricted to hosts detected as physical. Defaults include `powertop`,
storage/USB/system inspection tools, and kernel tools selected automatically
from installed APT package facts. The role selects `linux-tools-<running-kernel-ABI>`
plus a tracking meta only for recognized installed image metas (`linux-image-generic`,
`linux-image-generic-hwe-24.04`, or `linux-image-generic-hwe-26.04`). A missing
recognized meta does not trigger GA/HWE inference from a `-generic` kernel
suffix; only the exact ABI package is selected. Set
`host_hardware_linux_tools_packages` to an explicit list to replace auto-selection,
or `[]` to disable kernel tools. GPU and other `host_hardware_extra_packages`
remain a separate additive package path.

Read-only inspection of `daring` reported Ubuntu 26.04.1 (`resolute`), kernel
`7.0.0-38-generic`, and installed `linux-generic` / `linux-image-generic`
version `7.0.0-38.38`, with the exact `linux-tools-7.0.0-38-generic` package
and binaries already installed. The `linux-tools-generic` candidate matched;
`apt -s` showed it adds only the tracking meta. The same package-candidate
inspection found no `dnsutils` candidate for resolute and found
`bind9-dnsutils` version `1:9.20.24-1ubuntu0.3`; the Ubuntu package list now
uses that available name. Candidates were available for the other newly
proposed baseline, security, physical-diagnostics and `daring` extra packages.
These were read-only checks: no packages were installed and no reboot occurred.
The corrected selection expression was then evaluated against live kernel and
installed-package data. Its two tools packages were
`linux-tools-7.0.0-38-generic` and `linux-tools-generic`. A dependency-solver
simulation of the resolved 55-package baseline/hardware list succeeded:
295 new packages, zero upgrades, and one removal. The removal is `chrony`,
because the existing `common` role installs the conflicting `systemd-timesyncd`;
review that time-service transition before provisioning. No time-service policy
was changed by the kernel-tools correction. `turbostat --version` succeeded
with version `2026.02.14`; hardware measurements were not run. All live package
checks used the existing APT cache without updating it or installing packages.

Power defaults to `none`; all numeric caps are unset. Select either `sysfs` or
`power-profiles-daemon`. PPD rejects direct governor/EPP/boost/platform-profile
inputs and the CPU frequency cap, but accepts independently validated RAPL
caps. Powertop tuning is opt-in.
For `daring`, inventory selects the `sysfs` backend, `powersave` governor,
`balance_performance` EPP, CPU boost, and a 4,200,000 kHz maximum-frequency
threshold; `host_power_powertop_auto_tune` is enabled and no RAPL limit is configured.
This frequency threshold only caps eligible policies whose reported maximum is
higher. It does not identify P-cores by itself, and the E-core policy is intended
to remain untouched.

The helper uses the Linux flat `constraint_N_*` ABI. Discovery follows powercap
zones/control types and deduplicates class symlinks; it does not recurse through
`device`, `subsystem` or arbitrary directories. Named constraints, advertised
bounds and available CPU preferences are checked before control writes. Duplicate
constraints fail explicitly. Reports contain requested/effective values and
whether a write was needed; powercap hardware can quantize numeric values.
Quantized values differing from the request can cause another write on a rerun.

The role creates the helper directory, enables boot persistence, and reconverges
runtime drift on normal Ansible runs even when files are unchanged. It stops only
present competing services and surfaces real service failures. A previous managed
PPD backend is stopped/disabled when relinquished; `none` does not stop a
never-managed PPD installation. Removing sysfs controls or changing backends does
not promise immediate restoration of firmware defaults: schedule a reboot when
needed. No provisioning task reboots automatically. Helpers do not provide
transactional rollback for a hardware write that fails part-way through.

## Optional features

Homebrew/Docker honor their existing `*_install_enabled` variables. Node.js uses
`nodejs_runtime_install_enabled` (enabled for G14 and the development VM).
These installation toggles opt out of management; they do not uninstall tools.
`swapfile_enabled` retains the existing role's enable-only semantics; disabling
it does not remove active swap. Cluster swap policy remains later migration work.

UFW/fail2ban are selected via their `*_install_enabled` variables. Keep installation
management enabled and set `ufw_enabled`/`fail2ban_enabled` false to stop enforcement.
Existing explicitly selected VM firewall settings are preserved.

Disk expansion remains opt-in through `disk_expand_rootfs_expand` and the
explicit device/partition/VG/LV layout in `all_vms`. It consumes the VG's free
space for root. Do not enable it for a bare-metal disk layout with reserved
Longhorn capacity. A non-NOCHANGE `growpart` failure now aborts correctly.

This `daring` baseline does not enroll the host in K3s or change swap removal,
modules/sysctl, iSCSI, multipath, storage, or firewall policy. Those remain
separate workflows. Installing `nftables` or other packages does not itself
configure their runtime policy.

Cockpit defaults off. Example host overrides:

```yaml
cockpit_enabled: true
cockpit_extensions: [cockpit-storaged]
# Optional; requires ufw_install_enabled: true and ufw_enabled: true.
cockpit_ufw_sources: [192.168.10.0/24]
```

The role installs `cockpit-ws`, `cockpit-bridge` and `cockpit-system` without
recommended packages; it does not implicitly install NetworkManager integration
on Netplan/networkd machines. Explicitly selecting `cockpit-networkmanager` changes
that choice. Removed extensions and previously managed firewall sources are
removed on subsequent runs. Disabling a previously managed console stops its
socket/service, removes its managed packages/rules and clears its state file.
A never-managed Cockpit installation is left alone when the feature is off.

Use the individual host's HTTPS port 9090. Native web login needs a local account
password; SSH keys and NOPASSWD sudo do not create one. Account management leaves
existing passwords unchanged. Cockpit Client can connect over SSH using the
host's `cockpit-bridge`; the old web multi-host switcher is deprecated. See the
[Cockpit role README](../ansible/roles/cockpit/README.md).

## Validation evidence and rollout gate

Offline regressions cover Ubuntu inventory/package composition, optional
physical hardware diagnostics, the real flat powercap layout, class aliases/cycles,
EPP choice rejection, PPD plus caps, read-only checks, drift, quantized readback,
policy ownership transitions, unit whitespace, Cockpit source cleanup, fleet
precedence, target wrappers and the original baseline tests.

Current local validation: 99 tests run, 94 passed and five APT repository tests
skipped because system `python3-apt` is unavailable. Full role/playbook lint and
Ubuntu playbook syntax validation pass. The changed-file pre-commit checks pass.
Target inventory inspection confirmed `--limit daring` selects only that host,
outside the K3s groups. The power-only rerun and final runtime/reboot validation
remain outstanding.

Before rollout, establish actual host identities, installation state, the Intel
mini-PC CPU/GPU SKU, per-host policy/limits and management access. Validate on a
disposable VM, then one physical host: first run, unchanged rerun, fresh SSH plus
`sudo -n true`, reboot persistence, feature enable/disable, GPU diagnostics, actual
powercap readback and laptop lid/charging/fan behavior. No live provisioning,
fresh SSH, GPU acceleration, power enforcement or reboot-persistence result is
claimed here.

## Later cluster work

Repurposing `pve3` requires relocating its K3s/dev/OmniRoute VMs,
LLM/Garage/Photon containers and host-mounted data. Garage also stores cluster
backups and the Terraform S3 backend; its relocation is unresolved.

K3s prerequisites, cluster swap policy, manual `/var/lib/longhorn` filesystem
verification, limited joins, workload/GPU placement and VM retirement belong to
that later migration. The proposed rolling replacement retains the cluster and
can temporarily use four servers while replacing one of three. Terraform and
Kubernetes desired state are unchanged.

## References

- [Linux CPUFreq policy interface](https://docs.kernel.org/admin-guide/pm/cpufreq.html)
- [Linux powercap ABI](https://docs.kernel.org/power/powercap/powercap.html)
- [Ubuntu package catalogue](https://packages.ubuntu.com/)
- [Mesa Rusticl](https://docs.mesa3d.org/rusticl.html)
- [Cockpit authentication](https://cockpit-project.org/guide/latest/authentication.html)
- [Cockpit multi-host deprecation](https://cockpit-project.org/blog/cockpit-322.html)
- [Ansible local rules](../ansible/AGENTS.md)
