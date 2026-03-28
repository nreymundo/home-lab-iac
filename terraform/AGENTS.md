# TERRAFORM KNOWLEDGE BASE

## OVERVIEW
`terraform/` currently centers on the `k3s_nodes` module that provisions Proxmox VMs and emits the Ansible inventory used downstream.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Main module logic | `k3s_nodes/main.tf` | Proxmox VM resources + local inventory file |
| Inputs and validations | `k3s_nodes/variables.tf` | Strong schema for node shape and sizing |
| Providers / workspace | `k3s_nodes/providers.tf` | Proxmox + Bitwarden Secrets providers |
| External data | `k3s_nodes/data.tf` | Bitwarden SSH key lookup |

## CONVENTIONS
- `nodes` is the real scaling/config surface; `node_count` is explicitly deprecated.
- Secrets come from Bitwarden, not inline Terraform values.
- This module writes `../../ansible/inventories/k3s-nodes.yml`; that generated artifact is part of the intended workflow.
- Terraform Cloud workspace metadata lives in `providers.tf` and is part of the module contract.

## ANTI-PATTERNS
- Do not hand-edit the generated Ansible inventory.
- Do not reintroduce `node_count`-driven logic when `length(var.nodes)` is the current source of truth.
- Do not move secrets into tfvars or plaintext files when the module already uses Bitwarden.

## COMMANDS
```bash
terraform -chdir=terraform/k3s_nodes fmt
terraform -chdir=terraform/k3s_nodes validate
terraform -chdir=terraform/k3s_nodes plan
```

## NOTES
- Changes here often require checking the downstream Ansible impact, especially inventory shape, host labels, and users.
