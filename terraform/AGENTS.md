# AGENTS.md

**Generated:** 2026-01-05 21:13:08
**Commit:** 9c644bd

## OVERVIEW

Terraform provisions K3s VMs on Proxmox and generates Ansible inventory.
**Key Integration:** Writes `ansible/inventories/k3s-nodes.yml` via `local_file` resource.

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| **Provision K3s nodes** | `k3s_nodes/main.tf` | Entry point |
| **Add new nodes** | `k3s_nodes/vars.tf` | Update `nodes` list |
| **VM configuration** | `k3s_nodes/variables.tf` | CPU, RAM, disk, IP scheme |
| **Secret retrieval** | `k3s_nodes/data.tf` | Bitwarden Secrets Manager |
| **Inventory template** | `k3s_nodes/templates/inventory.yaml.tpl` | Ansible inventory generation |

## STRUCTURE

```
terraform/
└── k3s_nodes/
    ├── main.tf              # VM provisioning + inventory generation
    ├── variables.tf         # Input variables
    ├── data.tf              # Bitwarden secrets
    ├── outputs.tf           # VM IPs and metadata
    └── templates/
        └── inventory.yaml.tpl # Ansible inventory template
```

## CONVENTIONS

### Ansible Inventory Generation
- Uses `local_file` resource to write `ansible/inventories/k3s-nodes.yml`
- Must run `terraform apply` before Ansible playbook on K3s nodes

### VM ID Scheme
- Follows `packer/README.md` naming: Ubuntu 9000-9019, Fedora 9020-9039

### Bitwarden Integration
- Uses `bitwarden/bitwarden-secrets` provider (pinned to 0.5.4-pre)
- Retrieves SSH keys via secret ID (`BW_SSH_KEYS_ID`)

### Local State
- Uses `terraform.tfstate` (local, not remote)
- Back up state file—never delete

## ANTI-PATTERNS

1. **NEVER** delete `terraform.tfstate`—back it up instead.
2. **DO NOT** manually edit `ansible/inventories/k3s-nodes.yml`—use Terraform.
3. **DO NOT** use un-pinned provider versions—see `providers.tf`.

## VERIFICATION

```bash
# Format
terraform fmt -check

# Validate
terraform validate

# Plan (review before apply)
terraform plan

# Apply
terraform apply
```

## NOTES

- Pre-commit hook enforces `terraform fmt`.
- Requires Terraform >= 1.3 (see `providers.tf`).
