# Packer Build: Ubuntu 24.04 Base Image

This directory contains the Packer configuration to build a standardized **Ubuntu 24.04 LTS** VM template on Proxmox VE.

## Prerequisites & Layout
- Tools: Packer (>=1.10) and the `hashicorp/proxmox` plugin (installed via `packer init`).
- Template: `ubuntu-24.04-base/ubuntu-24.04.pkr.hcl` with supporting vars in the same directory.
- Cloud-init seeds: `ubuntu-24.04-base/http/user-data` and `ubuntu-24.04-base/http/meta-data`.
- Provisioner: `ubuntu-24.04-base/scripts/setup.sh` runs inside the guest.

## Features
- Cloud-init enabled for SSH keys, users, and networking at provision time.
- QEMU guest agent installed and enabled for Proxmox integration.
- Setup script handles updates, essentials, and K3s prerequisites.

## Variables & Secrets
- You can create `ubuntu-24.04-base/variables.auto.pkrvars.hcl` and fill values or override the defaults.
- Required fields: `proxmox_api_url`, `proxmox_api_token_id`, `proxmox_api_token_secret`.
- Keep secrets out of git; you can also supply sensitive values via `PKR_VAR_` environment variables.

## Cloud-Init Seeds
- `http/user-data`: autoinstall seed with placeholder hostname, timezone, and authorized_keys. Replace these placeholders with your own values before building (use a copied variant if you prefer).
- `http/meta-data`: placeholder instance-id and hostname; update to match your naming.

## Quickstart
1) `cd packer/ubuntu-24.04-base`
2) Prepare vars: `cp variables.auto.pkrvars.hcl.example variables.auto.pkrvars.hcl` and replace placeholders (or set `PKR_VAR_` env vars).
3) Update cloud-init placeholders in `http/user-data` (and `http/meta-data` if needed).
4) `packer init .`
5) `packer fmt -recursive .` (optional) and `packer validate .`
6) `packer build .`

## Multi-Node Builds
- Sources for `pve1` and `pve2` are defined and run in parallel.
- To add a node: duplicate a `proxmox-iso` source, set `node`, `vm_id`, `template_description`, and add it to `build.sources`, then run fmt/validate.

## Output & Safety
- Resulting template name: `ubuntu-24.04-base`; IDs follow the `vm_id` values per node on the configured storage pool.
- Verify the ISO exists on the target storage before building, and avoid committing real tokens or SSH keys.
