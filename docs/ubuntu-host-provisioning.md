# Unified Ubuntu host provisioning — implementation checkpoint

## Status

Paused at the user's request on 2026-10-08. Branch:
`feat/ubuntu-host-provisioning`. This is an **unfinished draft**, not a completed
provisioning workflow. No target machines were provisioned or changed.

The reusable baseline passed its review gate. Hardware and power roles are
present, but their review gate has not run. The power role has known blocking
execution defects listed below. **`ansible/playbooks/ubuntu.yml` does not exist
yet**, and neither new role is wired into an existing provisioning playbook.

## Goal and agreed design

Provide one thin Ubuntu provisioning playbook for manually installed Ubuntu
Server 24.04/26.04 systems: bare metal, Proxmox VMs, and headless laptops.
Ubuntu 26.04 is the intended installation for the incoming physical machines.
Inventory expresses intent; discovered hardware determines capabilities.

| Owner | Agreed responsibility |
| --- | --- |
| `common` | Accounts, validated passwordless sudo, baseline/extra packages, identity, time, updates, logs, trim and Ubuntu boot parameters |
| `ssh_hardening` | Authorized keys, effective SSH policy and restart |
| `host_hardware` | CPU firmware/microcode, independently discovered Intel/AMD GPUs, hardware packages, diagnostics and guest integration |
| `host_power` | One CPU policy owner, optional governor/EPP/boost/platform profile, powertop and explicit numeric caps |
| `headless_laptop` | Lid/sleep behavior, charging threshold and ASUS fan controls |
| `cockpit` | Optional per-host web console, default disabled |
| Existing optional roles | UFW, fail2ban, Homebrew, Docker, Node.js, swap and explicit-layout VM disk expansion |

The intended Ubuntu fleet defaults are:

- Unattended security and regular updates enabled; automatic reboots disabled.
- Distribution upgrades during provisioning disabled unless requested.
- Key-only SSH and no direct root SSH login; designated administrator gets
  passwordless sudo. Existing shared-role consumers retain their explicit policy.
- Baseline, hardware and extra packages compose explicitly instead of replacing
  one another through inventory precedence.
- Empty boot-parameter additions/removals, unset numeric caps, and opt-in
  powertop auto-tuning.
- Cockpit disabled; firewall/fail2ban and disk expansion explicitly selected.
- No automatic provisioning reboot; report the pending requirement.

These are **planned fleet defaults**, not all active defaults today. Existing
`all_vms` and G14 automatic-reboot overrides still need consolidation. Generic
system setup stays separate from K3s installation and cluster membership.

## Implemented

### Reviewed baseline

Initial commit: `54d4c081` — `feat(ansible): add reusable Ubuntu host baseline`.

- Optional managed administrator (`common_manage_user`, default false), groups
  and shell; preserve existing account passwords.
- Optional passwordless sudo (`common_passwordless_sudo`, default false), using
  a role-owned file validated with `visudo`; disabling removes that file.
- Refresh APT metadata even when distribution upgrades are disabled.
- Configurable unattended-upgrade origins, blacklist and periodic intervals;
  disabling updates writes the periodic configuration as well as managing the
  service.
- Optional `common_apt_daily_timer_schedule` and
  `common_apt_daily_upgrade_timer_schedule`, both empty by default. Their
  `90-ansible-common-schedule.conf` drop-ins preserve administrator `override.conf`
  files and are removed when unset. Vendor randomized delay is not overridden.
- Ubuntu GRUB parameter additions/removals via a managed drop-in, preserving
  unrelated arguments. Protected keys are rejected; later additions replace
  earlier values for the same key. Clearing the lists removes the managed file.
- `update-grub` notification and a `/run` reboot-pending marker retained until
  reboot; ordinary package reboot requirements also contribute to the fact.
- Debian SSH drop-in and early Include, syntax validation, actual `sshd -T`
  policy checks, normalized OpenSSH aliases, and idempotent hushlogin creation.
- `base`, `packages` and `boot` tag isolation with reachable preflight tasks.

The baseline review found and corrected shell-option leakage from the GRUB
fragment, SSH alias comparison failures, an invalid copy argument, protected-key
bypasses, empty-list lifecycle gaps, broad tag inheritance and ownership of APT
overrides. Regression coverage exercises the relevant behavior.

**Existing-host effect:** previously dormant `common_kernel_params_add` in
`inventories/host_vars/k3s-node-01.yml` now has an Ubuntu implementation. A later
common-role run can activate its IOMMU/i915 flags and require a reboot. That
inventory's old “placeholder” comment still needs updating during integration.

### Hardware role — implemented, review pending

See [`host_hardware` API](../ansible/roles/host_hardware/README.md).

- Physical/guest selection, CPU vendor microcode, firmware and diagnostics.
- Independent PCI display-device discovery for Intel/AMD, including GPUs visible
  inside VMs; no GPU assumption based on CPU vendor.
- Ubuntu release-specific package maps, additive package composition and
  universe/multiverse sources.
- KVM QEMU guest agent, optional render/video group membership and opt-in
  headless GPU diagnostics.
- Five offline tests covering fake PCI discovery, release maps, no-GPU guests,
  explicit profile disabling and tag selection.

No hypervisor passthrough/VFIO configuration or ROCm stack is introduced.

### Power role — initial scaffold with known defects

See [`host_power` intended API](../ansible/roles/host_power/README.md).

The role has `none`, `sysfs` and `power-profiles-daemon` backend inputs, optional
powertop, persistent unit templates, a Python helper and nine fixture tests.
Numeric limits are unset by default. This implementation is **not ready to run**:

| Known issue | Required next change |
| --- | --- |
| RAPL discovery uses invented `constraint_N/name` directories | Use the real flat ABI: `constraint_N_name`, `constraint_N_power_limit_uw`, `constraint_N_time_window_us`, and matching bounds. Correct the fixtures first. |
| Powercap traversal follows arbitrary directory/symlink children | Restrict traversal to powercap zones/control types; avoid escaping through `device`/`subsystem`; test cycles and class symlinks. |
| Helper destination parent is not created | Ensure `/usr/local/libexec` exists before copying the executable. |
| PPD branch ignores requested RAPL limits | Validate and apply caps with the selected backend, or explicitly reject unsupported combinations; never silently ignore requests. |
| An unchanged active oneshot does not reconverge runtime drift | Invoke/report the helper on normal runs with accurate changed state, retaining boot persistence. |
| Competing-service failures are suppressed | Filter present services and surface real stop/disable failures; verify a single policy owner. |
| PPD-to-none transition does not fully relinquish managed PPD policy | Track the previously managed backend and stop its enforcement without touching never-managed services. |
| EPP choices and platform-profile choice discovery need correction | Validate advertised preferences before writes; use `platform_profile_choices`. |

Also validate unit rendering with Ansible's Jinja whitespace settings, unit
ordering, backend transitions, quantized readback and all requested controls
before mutation. Clearing sysfs policy cannot promise immediate restoration of
firmware defaults; document when a reboot is required.

**Important test limitation:** the current RAPL tests pass against the same
incorrect directory layout as the helper. Their green result does not establish
compatibility with Linux powercap. The correction was identified but no edits
to implement it were made before this checkpoint.

### Offline CI

The existing Ansible CI job now also installs/checks OpenSSH validation tools and
runs `python -m unittest discover -s ansible/tests -v`. Fixture behavior and
requirements are documented in [`ansible/tests/README.md`](../ansible/tests/README.md).

## Not implemented yet

1. **Finish and review hardware/power** using the defects above as the first
   work item. The stage-two review gate is still pending.
2. **Unified entrypoint and inventory:** add `playbooks/ubuntu.yml`, the
   hand-maintained Ubuntu aggregate and fleet group variables. Reuse generated
   VM groups without editing Terraform-owned inventories. Convert existing
   VM/laptop entrypoints into compatibility wrappers preserving their targets.
3. **Consolidate current settings:** resolve `all_vms`/G14 reboot overrides,
   preserve explicitly enabled tools, provide optional Node.js orchestration,
   and avoid package-list replacement. `node_os` in VM inventory is a login
   username, not a reliable OS identifier; use gathered distribution facts.
4. **Laptop extraction:** move generic graphics, boot and CPU policy ownership
   into shared roles; retain charging/lid/ASUS behavior. The current ASUS fan
   helper repeatedly writes platform profile, so separate that from PPD's
   policy ownership. Update G14 variables to the new API.
5. **Cockpit:** implement default-off package/socket lifecycle and selected
   extensions, including managed firewall access. Use per-host consoles: the
   old multi-host switcher is deprecated. Avoid implicitly installing
   NetworkManager integration on Netplan/networkd systems. Native browser login
   uses a local password; SSH key authentication and passwordless sudo are
   separate settings. Document SSH-based Cockpit Client access where relevant.
6. **Optional role composition:** wire UFW/fail2ban, Homebrew/Docker/Node.js/swap
   and explicit-layout disk expansion into the same entrypoint.
7. **Final integration evidence:** inventory target/precedence checks, full tag
   routing, optional-feature transitions, compatibility wrappers, final review,
   and updated usage examples once the entrypoint exists.

No future hostname/IP or numeric wattage setting has been invented. `pve3`
remains an active Proxmox inventory member until it is actually migrated.

## Local verification at this checkpoint

Checks used an isolated environment matching CI's Python major/minor and pinned
Ansible tools: Python 3.12.15, ansible-core 2.21.3, ansible-lint 26.8.0. Earlier
baseline checks also passed on the controller's Python 3.14/Ansible 2.21.4.

| Check | Result |
| --- | --- |
| Offline unittest discovery | 27 passed: 13 baseline, 5 hardware, 9 power; RAPL fixture limitation above applies |
| Full Ansible role/playbook lint | Passed, 277 files processed, zero failures/warnings |
| All 18 existing playbook syntax checks | Passed |
| Temporary playbook including both new roles, syntax only | Passed |
| Applicable pre-commit checks | Passed on all checkpoint files; commit hooks also run when committing |
| Whitespace/diff checks | Passed |

The combined test run emits a harmless Ansible plugin-loader “already configured”
warning because multiple test modules initialize it. No test was skipped.

Repeat from the repository root with the documented dependencies installed:

```sh
python -m unittest discover -s ansible/tests -v
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-lint --project-dir ansible ansible/playbooks/ ansible/roles/
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/ubuntu_vms.yml --syntax-check
git diff --check
```

`--check` against actual inventory is a live operation and was **not** run.
No provisioning, real SSH reconnect, service transitions, GPU acceleration,
power enforcement or reboot-persistence claim has been validated on targets.

## Physical rollout and later cluster work

Before first provisioning, establish actual host identities, installation state,
the Intel mini-PC's CPU/GPU SKU, per-host power policy/limits and management
access. The G14 was unreachable during planning. Validate on a disposable VM,
then one physical host: first run, unchanged rerun, fresh SSH plus `sudo -n true`,
reboot persistence, optional-feature enable/disable, GPU diagnostics, actual
powercap readback, and laptop lid/charging/fan behavior.

Repurposing `pve3` first requires relocating its current K3s/dev/OmniRoute VMs,
LLM/Garage/Photon containers and host-mounted data. Garage is both cluster backup
storage and the Terraform S3 backend; its relocation is unresolved.

K3s prerequisites, swap disabling for cluster members, manual
`/var/lib/longhorn` mount/filesystem verification, limited joins, workload/GPU
placement and VM retirement belong to the later cluster migration. The proposed
rolling replacement keeps the existing cluster and can temporarily use four
servers while replacing one of three. None of that migration is implemented
here; Terraform and Kubernetes desired state are unchanged.

## References

- [Linux powercap ABI](https://docs.kernel.org/power/powercap/powercap.html)
- [Ubuntu package catalogue](https://packages.ubuntu.com/)
- [Mesa Rusticl device enablement](https://docs.mesa3d.org/rusticl.html)
- [Cockpit multi-host deprecation](https://cockpit-project.org/blog/cockpit-322.html)
- [Ansible local rules](../ansible/AGENTS.md)

The next session should start with this document and the role READMEs. The
untracked orchestration progress file is not required to resume the work.
