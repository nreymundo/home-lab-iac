# Terraform

Creates VMs and LXC containers on Proxmox, manages existing Unraid VMs through
libvirt, and provisions cloud infrastructure. Proxmox guests clone Packer-built templates.

- `modules/` holds the reusable Proxmox and cloud building blocks; concrete
  roots live under `instances/` (vm, lxc) and `cloud/`.
- The K3s node root (`instances/vm/k3s_nodes`) also renders the Ansible
  inventory for the cluster, keeping node topology in one place.
- Runtime secrets come from the secret-helper external data source,
  never from tfvars or plaintext files.
- `instances/vm/development` manages the migrated Unraid `development` domain
  through `qemu+sshcmd://unraid/system?proxy=native`, using the controller's SSH
  configuration. It uses guest hostname `development` and generates its existing
  Ansible inventory. The migrated disk and cloud-init seed remain under
  `/mnt/cache/domains/development`; this root references those files rather than
  creating replacement disks. Back them up independently of Proxmox guest jobs.

Editing rules and validation commands: [AGENTS.md](AGENTS.md).
