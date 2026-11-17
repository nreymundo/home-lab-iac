# Ubuntu host provisioning

Use `ubuntu.yml` for Ubuntu Server 24.04 or 26.04 on bare metal, headless laptops,
and VMs. Commands below run from `ansible/`.

## Inventory and run

The inventory directory loads hand-maintained host groups and host variables.
VM identities come from generated inventory; do not edit generated files.
Ubuntu hosts are grouped under `ubuntu_hosts`. K3s servers also belong to
`k3s_server`. Set host values in `inventories/host_vars/<host>.yml` and group
defaults in `inventories/group_vars/`. See the [K3s guide](k3s-provisioning.md)
for cluster operations.

`all_vms` includes the Terraform-managed `development` and `hermes` guests on
Unraid. Use their dedicated application playbooks for workstation tools or
Hermes services; `ubuntu.yml` provides the common host baseline.

```sh
ansible-inventory --graph ubuntu_hosts
ansible-playbook playbooks/ubuntu.yml --limit <host> --list-hosts
ansible-playbook playbooks/ubuntu.yml --limit <host> --syntax-check
ansible-playbook playbooks/ubuntu.yml --limit <host> --check
ansible-playbook playbooks/ubuntu.yml --limit <host>
```

`--check` connects to the host, gathers facts and may run read-only commands; it
is not an offline dry run. Offline tests use temporary fixtures. Hosts are not
rebooted automatically.

For bootstrap, set `common_user` to the intended administrator and provide
working sudo access. SSH key discovery uses the configured 1Password service
account.

Use `--limit all_vms` or `--limit headless_laptops` for those groups. Useful tags:

| Tags | Work |
| --- | --- |
| `base`, `packages`, `boot`, `ssh` | Common setup and SSH |
| `hardware`, `gpu` | Hardware and GPU packages/settings |
| `power`, `preflight` | Power policy |
| `laptop` | Laptop lid, charging and fan settings |
| `swap`, `disk`, `firewall`, `fail2ban`, `cockpit` | Optional host features |

Tags may rely on prerequisites from an earlier full run.

## Common settings

Put host-specific values in `inventories/host_vars/<host>.yml`. Common package
lists are in `inventories/group_vars/ubuntu_hosts.yml`; host package additions
use `common_extra_packages`, hardware additions use
`host_hardware_extra_packages`.

| Setting | Default/behavior |
| --- | --- |
| `common_run_upgrade` | `false` for Ubuntu hosts; skips provisioning-time upgrades, not unattended updates |
| `common_unattended_upgrades_auto_reboot` | `false` |
| `host_hardware_install_diagnostics` | Optional physical-host diagnostics |
| `host_power_backend` | `none`; choose `sysfs` or `power-profiles-daemon` to manage power |
| `host_power_powertop_auto_tune` | `false` |
| `cockpit_enabled` | `false` |
| `swapfile_enabled` | Ubuntu swap role is enable-only; `false` does not remove active swap |

See the [hardware](../ansible/roles/host_hardware/README.md),
[power](../ansible/roles/host_power/README.md), and
[Cockpit](../ansible/roles/cockpit/README.md) role guides for their options.

K3s enrollment disables active swap on a new server; existing servers are
inspected without changing swap. Keep host setup and cluster operations as
separate playbook runs. Package installation can start or restart services.

## Current bare-metal host policy

The settings below come from `inventories/host_vars/`. Hardware discovery does
not select a power policy; describe that policy explicitly per host.

| Host | Hardware and power policy |
| --- | --- |
| `daring` | Intel GPU tooling; sysfs `powersave` and `balance_performance`, boost enabled, 4.2 GHz ceiling on eligible CPU policies, and Powertop auto-tune. |
| `steadfast` | AMD GPU profile with GPU and Vulkan validation; kernel TTM settings preserve a 108 GiB allowance on 4 KiB pages. Sysfs `powersave`, `power` EPP, boost disabled, `low-power` platform profile, and Powertop auto-tune. |
| `valiant` | AMD ASUS headless laptop. The `host_power` backend is `none`; laptop policy ignores lid events, masks sleep targets, and caps charging at 60%. ASUS fan curves are managed through `asusd` rather than the legacy quiet fan policy service. |

On `valiant`, Homebrew supplies `asusctl`/`asusd`. The configured
`headless_laptop_asusd_fan_curve` applies to both CPU and GPU fans in the
`Quiet` profile, with a 30% floor and full speed at 90 C. The fan-curve task
does not switch profiles; the separate ASUS daemon setup selects `LowPower`
if available, otherwise `Quiet`. After a full host run has installed and
configured `asusd`, use:

```sh
ansible-playbook playbooks/ubuntu.yml --limit valiant --tags asus_fan_curve
```

Read back the curves with `asusctl fan-curve --mod-profile Quiet` on the host.
The playbook runs this read probe even in check mode, so check mode for this
host also requires an existing `asusctl`/`asusd` installation.

All three hosts are K3s members with swap provisioning disabled and a manual
Longhorn mount. See the [K3s guide](k3s-provisioning.md#current-server-fleet) for
cluster storage and device-plugin ownership.

## Validation

From the repository root:

```sh
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/ubuntu.yml --syntax-check
```
