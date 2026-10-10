# Ubuntu host provisioning

Use this playbook for manually installed Ubuntu Server 24.04 or 26.04 hosts:
bare metal, Proxmox VMs and headless laptops. Commands below run from `ansible/`.

## Inventory and run

The inventory directory loads hand-maintained host groups and host variables.
VM identities come from generated inventory; do not edit generated files.
Ubuntu hosts are grouped under `ubuntu_hosts`. K3s servers also belong to
`k3s_server`. Set host values in `inventories/host_vars/<host>.yml` and group
defaults in `inventories/group_vars/`. See the [K3s guide](k3s-provisioning.md)
for cluster operations.

```sh
ANSIBLE_CONFIG=ansible.cfg ansible-inventory --graph ubuntu_hosts
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu.yml --limit <host> --list-hosts
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu.yml --limit <host> --syntax-check
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu.yml --limit <host> --check
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu.yml --limit <host>
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

## Validation

From the repository root:

```sh
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/ubuntu.yml --syntax-check
python -m unittest discover -s ansible/tests -v
```
