# Terraform

Creates the VMs and LXC containers that run the lab on Proxmox, plus cloud
infrastructure, cloning from the Packer-built templates.

- `modules/` holds the reusable Proxmox and cloud building blocks; concrete
  roots live under `instances/` (vm, lxc) and `cloud/`.
- The K3s node root (`instances/vm/k3s_nodes`) also renders the Ansible
  inventory for the cluster, keeping node topology in one place.
- Runtime secrets come from the secret-helper external data source,
  never from tfvars or plaintext files.

Editing rules and validation commands: [AGENTS.md](AGENTS.md).
