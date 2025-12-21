# AGENTS.md

## Project Overview
Home Lab Infrastructure as Code (IaC) repository implementing a GitOps workflow.
- **Ansible**: Configuration management for Raspberry Pi edge devices, Proxmox hosts, and Ubuntu VMs.
- **Packer**: Automated VM template generation (Ubuntu 24.04).
- **Terraform**: Infrastructure provisioning (K3s nodes on Proxmox) and dynamic inventory generation.

## Key Paths
- **Ansible**: `ansible/`
  - Inventories:
    - `inventories/baremetal.yml` (Manually managed Physical hosts)
    - `inventories/k3s-nodes.yml` (Terraform-generated - **DO NOT EDIT**)
    - `inventories/all-vms.yml` (VM Group definitions)
  - Playbooks: `playbooks/rpi.yml`, `playbooks/proxmox.yml`, `playbooks/ubuntu_vms.yml`, `playbooks/k3s_essentials.yml`
  - Roles: `roles/common`, `roles/vm_disk_expand`, `roles/k3s`, `roles/metallb`
- **Packer**: `packer/ubuntu-24.04-base/`
- **Terraform**: `terraform/k3s_nodes/`

## Development Guidelines

### Ansible
- **Working Directory**: Run all commands from `ansible/`.
- **Configuration**: `ANSIBLE_CONFIG=ansible/ansible.cfg` is set automatically if running from dir.
- **Dependencies**: `ansible`, `ansible-lint`, `yamllint`.
- **Verification Commands**:
  - **Syntax Check**: `ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --syntax-check`
  - **Dry Run (RPi)**: `ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --check`
  - **Dry Run (VMs)**: `ansible-playbook -i inventories/all-vms.yml -i inventories/k3s-nodes.yml playbooks/ubuntu_vms.yml --check`
  - **Lint**: `ansible-lint playbooks/*.yml`
- **Style**:
  - Keep defaults in `roles/`.
  - Use `group_vars` for environment specifics (`all.yml`, `rpi.yml`, `proxmox.yml`).
  - **Security**: SSH keys are currently committed in `group_vars/all.yml` (per user instruction).
  - **Task Names**: Descriptive and capitalized.

### Packer
- **Working Directory**: `packer/ubuntu-24.04-base/`.
- **Commands**:
  - `packer init .`
  - `packer validate .`
  - `packer build .`
- **Formatting**: `packer fmt -recursive .`
- **Secrets**: Use `variables.auto.pkrvars.hcl` for local secrets (git-ignored).

### Terraform
- **Working Directory**: `terraform/k3s_nodes/`.
- **Commands**:
  - `terraform init`
  - `terraform fmt`
  - `terraform plan`
  - `terraform apply`
- **Integration**: `terraform apply` automatically updates `ansible/inventories/k3s-nodes.yml`.

## Quality Assurance
- **Pre-commit**: **MANDATORY**. Run `pre-commit run --all-files` before submitting.
  - Includes: `trailing-whitespace`, `end-of-file-fixer`, `yamllint`, `ansible-lint`, `packer-fmt`, `terraform-fmt`.
- **Formatting**:
  - **Newlines**: All files MUST end with a single newline character (`\n`).
  - YAML: 2 spaces indent, no tabs, ~120 char line limit.
  - HCL: Standard Terraform/Packer formatting.
  - Shell: POSIX-sh compliant, `set -euo pipefail`.

## General Rules
- **Idempotency**: All scripts and playbooks must be idempotent.
- **Naming**: Descriptive, lowercase with hyphens/underscores (e.g., `k3s-node-01`).
- **Error Handling**: Fail fast. Surface errors immediately.
- **Generated Files**: **NEVER** manually modify `ansible/inventories/k3s-nodes.yml` or `terraform.tfstate`.

## Environment
- **Platform**: Linux
- **Tools**: Ansible Core, Packer >=1.10, Terraform >=1.0
