# Terraform Agent Notes

Read [the repository-wide rules](../AGENTS.md) first. This file covers Terraform-specific editing rules.

## What This Subtree Owns
- `terraform/modules/` holds reusable infrastructure building blocks.
- Concrete deployment roots live under `terraform/instances/` and `terraform/cloud/`.
- Keep backend and provider credentials outside the repository. Preserve existing SSH public-key lookups through `hashicorp/external` and the 1Password helper in `terraform/scripts/`.

## Source Of Truth Boundaries
- Terraform roots, including cloud roots, own the Ansible inventory files they generate. Find the output path in the root's `ansible_inventory.tf`.
- Treat the S3 backend settings and state key in each root's `providers.tf` as part of that root's contract.
- For the K3s fleet, preserve the `local.k3s.nodes` topology instead of reintroducing count-based node definitions.

## Local Anti-Patterns
- Do not hand-edit Terraform-generated Ansible inventory.
- Do not move credentials into `tfvars` or plaintext files, or bypass the public-key helper in a root or module that uses it.
- Do not put per-instance overrides in reusable modules; the deployment root owns them.
- Do not change root-module outputs or inventory shape without checking downstream Ansible impact.

## Validation
```bash
ROOT=terraform/instances/vm/k3s_nodes
terraform -chdir="$ROOT" init -backend=false
terraform -chdir="$ROOT" fmt -check
terraform -chdir="$ROOT" validate
```

- Set `ROOT` to the modified deployment root, including cloud roots. Use a fresh working directory for initialization with the backend disabled.
- Run `plan` separately with approval and the configured backend and provider credentials. Evaluating the SSH public-key data source also requires `op`, `jq`, `OP_SERVICE_ACCOUNT_TOKEN`, and `IAC_1PASSWORD_VAULT_ID`.
- After an approved change regenerates inventory, inspect the diff for hostnames, addresses, users, labels, and topology used by Ansible.
- Regenerate module reference tables using the [terraform-docs workflow](../.github/workflows/terraform-docs.yml), not by hand.
