# Terraform

Terraform provisions Proxmox VMs and LXC containers, Unraid VMs through
libvirt, and Hetzner Cloud resources. The Proxmox VM module defaults to cloning
the `ubuntu-24.04-base` template built by [Packer](../packer/AGENTS.md).

- [`modules/`](modules/) holds reusable building blocks. Deployments live in
  [`instances/`](instances/) and [`cloud/`](cloud/); run Terraform from the
  individual root, not from this directory.
- Each deployment root declares its S3 backend and state key in `providers.tf`.
  Check that file for the backend and provider inputs before initializing.
- Roots with `ansible_inventory.tf` write inventory under
  [`ansible/inventories/`](../ansible/inventories/). For example,
  [`k3s_nodes`](instances/vm/k3s_nodes/) derives `k3s-nodes.yml` from
  `local.k3s.nodes`, while [NetBird](cloud/hetzner/servers/netbird/) writes
  `public-vps.local.yml`. Update the owning root instead of editing generated
  inventory.
- Roots and modules that look up SSH public keys use the
  [1Password helper](scripts/fetch-ssh-public-keys.sh). Backend and provider
  credentials are supplied separately, not committed in Terraform files.

Editing rules and validation commands: [AGENTS.md](AGENTS.md).

The [terraform-docs workflow](../.github/workflows/terraform-docs.yml) generates
module reference tables from HCL. Do not edit the `BEGIN_TF_DOCS` blocks by hand.
