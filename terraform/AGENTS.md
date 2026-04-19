# TERRAFORM KNOWLEDGE BASE

## OVERVIEW
`terraform/` is split between reusable modules in `modules/` and concrete instance roots in `instances/`.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Shared VM module | `modules/proxmox_vms/` | Reusable Proxmox VM provisioning logic |
| K3s instance root | `instances/k3s_nodes/` | K3s VM definitions, providers, and Ansible inventory generation |
| OpenClaw instance root | `instances/openclaw/` | Single-VM instance root using the shared module |

## CONVENTIONS
- `instances/k3s_nodes/vm_definition.tf` is the scaling/config surface for K3s nodes.
- Secrets come from Bitwarden, not inline Terraform values.
- Instance roots write generated inventories into `ansible/inventories/`; those artifacts are part of the intended workflow.
- Terraform Cloud workspace metadata lives in each instance root's `providers.tf` and is part of the root-module contract.

## ANTI-PATTERNS
- Do not hand-edit the generated Ansible inventory.
- Do not reintroduce `node_count`-driven logic when `length(local.k3s.nodes)` is the current source of truth.
- Do not move secrets into tfvars or plaintext files when the module already uses Bitwarden.

## COMMANDS
```bash
terraform -chdir=terraform/instances/k3s_nodes fmt
terraform -chdir=terraform/instances/k3s_nodes validate
terraform -chdir=terraform/instances/k3s_nodes plan
terraform -chdir=terraform/instances/openclaw fmt
terraform -chdir=terraform/instances/openclaw validate
terraform -chdir=terraform/instances/openclaw plan
```

## NOTES
- Changes here often require checking the downstream Ansible impact, especially inventory shape, host labels, and users.
