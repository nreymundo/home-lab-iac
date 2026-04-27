# Terraform Agent Notes

Read the repo root `AGENTS.md` first for repo-wide policy. This file only covers Terraform-local editing rules.

## What This Subtree Owns
- `terraform/modules/` holds reusable infrastructure building blocks.
- Concrete root modules live under both `terraform/instances/` and `terraform/cloud/`; those roots are allowed to produce downstream artifacts such as Ansible inventory or cloud-specific infrastructure state.
- Secrets belong in Bitwarden-backed flows, not inline Terraform values or plaintext files.

## Source Of Truth Boundaries
- Treat instance roots as the source of truth for generated inventory under `ansible/inventories/`.
- Treat Terraform Cloud workspace settings in each root module's `providers.tf` as part of the root-module contract.
- For the K3s node fleet, prefer the current `local.k3s.nodes`-driven topology instead of reintroducing older count-based patterns.

## Local Anti-Patterns
- Do not hand-edit Terraform-generated Ansible inventory.
- Do not move secrets into `tfvars`, plaintext files, or ad hoc environment handling when the existing module already uses Bitwarden.
- Do not treat module internals as a safe place for per-instance overrides when the root module already owns that concern.
- Do not change root-module outputs or inventory shape without checking downstream Ansible impact.

## Validation
```bash
terraform -chdir=terraform/instances/k3s_nodes fmt
terraform -chdir=terraform/instances/k3s_nodes validate
terraform -chdir=terraform/instances/k3s_nodes plan
terraform -chdir=terraform/instances/openclaw fmt
terraform -chdir=terraform/instances/openclaw validate
terraform -chdir=terraform/instances/openclaw plan
```

- Treat those commands as representative root-module examples, not an exhaustive list of every Terraform root in the repo.
- After changing Terraform that feeds Ansible, inspect the generated inventory diff and any host labels, users, or topology assumptions consumed downstream.
