# Terraform Agent Notes

Read the repo root `AGENTS.md` first for repo-wide policy. This file only covers Terraform-local editing rules.

## What This Subtree Owns
- `terraform/modules/` holds reusable infrastructure building blocks.
- Concrete root modules live under both `terraform/instances/` and `terraform/cloud/`; those roots can produce downstream artifacts such as Ansible inventory or cloud-specific infrastructure state.
- Secrets belong in 1Password CLI-backed helper flows (the `hashicorp/external` data source and `terraform/scripts/` helpers), not inline Terraform values or plaintext files.

## Source Of Truth Boundaries
- Treat Terraform roots, including cloud roots, as the source of truth for generated inventory under `ansible/inventories/`.
- Treat Terraform Cloud workspace settings in each root module's `providers.tf` as part of the root-module contract.
- For the K3s node fleet, prefer the current `local.k3s.nodes`-driven topology instead of reintroducing older count-based patterns.

## Local Anti-Patterns
- Do not hand-edit Terraform-generated Ansible inventory.
- Do not move secrets into `tfvars`, plaintext files, or ad hoc environment handling when the existing module already uses the 1Password-backed helper.
- Do not treat module internals as a safe place for per-instance overrides when the root module already owns that concern.
- Do not change root-module outputs or inventory shape without checking downstream Ansible impact.

## Validation
```bash
ROOT=terraform/instances/vm/k3s_nodes
terraform -chdir="$ROOT" init
terraform -chdir="$ROOT" fmt -check
terraform -chdir="$ROOT" validate
terraform -chdir="$ROOT" plan
```

- Set `ROOT` to each modified root module, including cloud roots. `plan` requires the configured backend and provider credentials.
- The 1Password-backed external data source needs an authenticated `op` CLI and `jq` on PATH for anything that reads data sources; scope or constrain lookups with `OP_SSH_KEYS_VAULT_ID` and `OP_ACCOUNT` when needed.
- After changing Terraform that feeds Ansible, inspect the generated inventory diff and any host labels, users, or topology assumptions consumed downstream.
