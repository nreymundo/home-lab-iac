### Ansible – Home Lab Provisioning

Scaffolding to manage Home Lab infrastructure, including Raspberry Pi hosts (3/4/5/CM), Proxmox VE nodes, and Ubuntu VM guests.

Structure:
- `inventories/` contains host definitions:
    - `baremetal.yml`: Raspberry Pi and Proxmox hosts grouped for their respective playbooks.
    - `k3s-nodes.yml`: Terraform-generated K3s VM nodes (do not edit manually).
    - `all-vms.yml`: Groups VM targets (e.g., `k3s_nodes`) for shared settings.
    - `k3s-cluster.yml`: Aggregates `k3s_nodes` and `baremetal_k3s` for cluster-wide runs.
    - `group_vars/` contains group-specific overrides:
        - `all.yml`: Shared settings like SSH keys, timezone, and NTP servers.
        - `rpi.yml`: Defaults for Raspberry Pi (security hardening, common packages).
        - `proxmox.yml`: Overrides for Proxmox (disables auto-upgrades, allows root key login).
        - `all_vms.yml`: Defaults for Ubuntu VMs (enables rootfs expansion, sets user defaults).
    - `host_vars/`: Per-host overrides (e.g., `main-rpi4.yml` for netplan and extra packages).
- `playbooks/` contains site-specific playbooks:
    - `rpi.yml`: Targets the `rpi` group in `baremetal.yml`.
    - `proxmox.yml`: Targets the `proxmox` group in `baremetal.yml`.
    - `ubuntu_vms.yml`: Targets VM hosts (combine `all-vms.yml` with a host inventory such as `k3s-nodes.yml`).
- `roles/` contains shared roles:
    - `common`: System setup (users, SSH keys, timezone, NTP, upgrades, netplan) with feature flags.
    - `vm_disk_expand`: Expands root disks on LVM-backed Ubuntu VMs when enabled.

Usage (run from `ansible/`):
- **Raspberry Pi:** `ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml`
- **Proxmox:** `ansible-playbook -i inventories/baremetal.yml playbooks/proxmox.yml`
- **Ubuntu VMs (K3s nodes):** `ansible-playbook -i inventories/all-vms.yml -i inventories/k3s-nodes.yml playbooks/ubuntu_vms.yml`
  - `all-vms.yml` provides group settings; `k3s-nodes.yml` supplies the hosts. Include both inventories.
- Dry run mode: append `--check` to any command.

### Role Behavior

The `common` role behaves differently based on the target group:

| Feature | Raspberry Pi | Proxmox | Ubuntu VMs |
| :--- | :--- | :--- | :--- |
| **User** | `ansible_user` (default: `pi`) | `root` | `ansible_user` (default: `ubuntu`) |
| **SSH Root Login** | Disabled (`no`) | Keys Only (`prohibit-password`) | Disabled (`no`) |
| **Auto-Upgrades** | **Enabled** (unattended-upgrades) | **Disabled** (Manual control required) | **Enabled** (unattended-upgrades) |
| **Run `apt dist-upgrade`** | Yes (on playbook run) | No (Skipped) | Yes (on playbook run) |
| **Hushlogin** | Created | Skipped | Created |
| **Root FS expansion** | N/A | N/A | Enabled when `vm_disk_expand_rootfs_expand` is true |

Notes:
- `common_timezone` sets the system timezone via `timedatectl`.
- `common_ntp_servers` installs/enables systemd-timesyncd.
- `common_netplan_config` (optional) renders `/etc/netplan/01-main.yaml` when provided and triggers `netplan apply`.
- Hostname is set to match the inventory name (`inventory_hostname`) during provisioning.

### VM Disk Expansion

- The `vm_disk_expand` role grows the root partition and LVM logical volume using `growpart`, `pvresize`, and `lvextend -r`.
- Defaults (see `roles/vm_disk_expand/defaults/main.yml`):
  - `vm_disk_expand_rootfs_expand: false` (opt-in)
  - `vm_disk_expand_rootfs_device: /dev/sda`, `vm_disk_expand_rootfs_partition: 3`
  - `vm_disk_expand_rootfs_vg: ubuntu-vg`, `vm_disk_expand_rootfs_lv: ubuntu-lv`
- `inventories/group_vars/all_vms.yml` enables `vm_disk_expand_rootfs_expand: true` for VM targets so they auto-grow to fill the disk. Override the device/partition/VG/LV if your template differs.
