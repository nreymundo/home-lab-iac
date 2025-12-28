# AGENTS.md

**Instructions for AI Coding Assistants (Cursor, Copilot, etc.)**

If you are an AI agent reading this, these rules are **LAW**.

## Project Overview
This is a **Home Lab Infrastructure as Code (IaC)** repository implementing a **GitOps workflow**.
- **Platform:** Proxmox VE + Kubernetes (K3s).
- **Tools:** Ansible, Packer, Terraform, Flux.
- **Language:** YAML, HCL, Shell, Python.

## ⚠️ Documentation Maintenance (CRITICAL)

**When making changes, YOU MUST update the relevant documentation.**

- **New component?** → Create/Update `README.md` in that component's folder.
- **Changed architecture?** → Update `docs/ARCHITECTURE.md`.
- **New network/IP?** → Update `docs/NETWORKING.md`.
- **New security pattern?** → Update `docs/SECURITY.md`.
- **New workflow?** → Update `docs/GETTING_STARTED.md`.

**Before confirming a task is done, check:** "Does the documentation reflect what I just changed?"

## Directory Map

- `ansible/` - Host configuration. Run commands from here.
- `packer/` - VM Template building.
- `terraform/` - VM Provisioning.
- `kubernetes/` - Flux GitOps definitions.
    - `clusters/homelab/` - The actual cluster state.
    - `infrastructure/` - Core apps (Traefik, Storage, etc.).
    - `apps/` - User apps.
- `docs/` - Human documentation.

## Verification Commands

Always verify your work.

**Ansible:**
```bash
# Syntax check
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --syntax-check
# Lint
ansible-lint playbooks/*.yml
```

**Terraform:**
```bash
terraform fmt -check
terraform validate
```

**Packer:**
```bash
packer validate .
```

**Kubernetes:**
```bash
# Dry run apply
kubectl apply -f <file> --dry-run=client
```

## Forbidden Actions

1.  **NEVER** commit secrets (API keys, passwords). Use placeholders or Bitwarden references.
2.  **NEVER** modify `ansible/inventories/k3s-nodes.yml` manually (Terraform owns it).
3.  **NEVER** suggest `kubectl apply` for things in `kubernetes/` (Flux owns it). Suggest `git push` instead.
4.  **NEVER** delete `terraform.tfstate`.

## Style Guide

- **YAML:** 2 space indent.
- **Comments:** Explain *why*, not *what*.
- **Naming:** Kebab-case (`my-app-name`) preferred for K8s resources.
