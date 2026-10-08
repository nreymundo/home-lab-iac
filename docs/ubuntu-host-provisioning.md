# Unified Ubuntu host provisioning

## Status

Implementation resumed on 2026-10-08 in `feat/ubuntu-host-provisioning` (PR #1407).
The unified entrypoint, inventory grouping, hardware/power corrections, laptop
extraction and optional Cockpit composition are implemented. This remains a
**implementation pending target validation**. No target machines have been provisioned,
rebooted or changed by this implementation session.

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
`headless_laptops` and the empty `ubuntu_baremetal` group. Load the inventory
**directory**, not the aggregate alone: generated files provide VM identities.
Terraform-owned inventory was not edited. `pve3` remains a Proxmox host; no
future machine hostname, IP address, GPU SKU or wattage was invented.

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
and `common_extra_packages` holds host additions. Hardware packages compose
separately, with `host_hardware_extra_packages` as their extension point.
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

# Provision one installed host after verifying its inventory and bootstrap access.
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/ubuntu.yml --limit g14-2022
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

Power defaults to `none`; all numeric caps are unset. Select either `sysfs` or
`power-profiles-daemon`. PPD rejects direct governor/EPP/boost/platform-profile
inputs but accepts independently validated RAPL caps. Powertop tuning is opt-in.

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

Offline regressions cover the real flat powercap layout, class aliases/cycles,
EPP choice rejection, PPD plus caps, read-only checks, drift, quantized readback,
policy ownership transitions, unit whitespace, Cockpit source cleanup, fleet
precedence, target wrappers and the original baseline tests.

Fresh local validation uses Python 3.14.7 and ansible-core 2.21.5. Full
role/playbook lint and all 19 playbook syntax checks pass. The earlier local
Unix-socket restriction is absent in this environment: all execution-based
fixtures run, including temporary-root lifecycle and SSH assertion tests.
All 47 tests pass locally, with no skips. The complete suite also checks Pi update origins through the resolved inventory
and rendered APT configuration. CI runs the suite using the versions pinned in
`.github/workflows/ci.yml`; consult the latest PR run for remote results.

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

- [Linux powercap ABI](https://docs.kernel.org/power/powercap/powercap.html)
- [Ubuntu package catalogue](https://packages.ubuntu.com/)
- [Mesa Rusticl](https://docs.mesa3d.org/rusticl.html)
- [Cockpit authentication](https://cockpit-project.org/guide/latest/authentication.html)
- [Cockpit multi-host deprecation](https://cockpit-project.org/blog/cockpit-322.html)
- [Ansible local rules](../ansible/AGENTS.md)
