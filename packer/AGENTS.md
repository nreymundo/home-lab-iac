# Packer Agent Notes

Read [the repository-wide rules](../AGENTS.md) first. This file covers Packer-specific editing rules.

## What This Subtree Owns
- Each template directory is a build root with its own Packer configuration, variables, and entry point. Discover roots by locating `*.pkr.hcl` files.
- [`scripts/`](scripts/) contains shared build, answer-file generation, and provisioning helpers. Check which roots call a helper before changing it.
- The build roots produce reusable Proxmox VM templates. Check Terraform clone consumers before changing template names, disk layouts, guest users, or cloud-init behavior.

## Source Of Truth Boundaries
- Edit the source answer files (`http/user-data.template` or `http/ks.cfg.template`), not the generated `http/user-data` or `http/ks.cfg` files.
- Use the template's `build.sh` for an approved build: it generates the answer file before running `packer build`.
- Answer-file generation reads public keys from 1Password `SSH Key` items tagged `packer`. It requires `op`, `jq`, `OP_SERVICE_ACCOUNT_TOKEN`, and `IAC_1PASSWORD_VAULT_ID`. Configure Proxmox credentials through the variables documented in the template's `variables.pkr.hcl`.

## Local Anti-Patterns
- Do not hardcode secrets, tokens, or private keys into template files.
- Do not skip template-local wrapper scripts when they prepare generated inputs required for a correct build.
- Do not document or depend on a brittle list of current template names when the subtree is meant to support additional template roots over time.
- Do not change a base template casually without checking the downstream Terraform consumers that clone it.

## Validation
```bash
TEMPLATE=packer/ubuntu-24.04-base
packer init "$TEMPLATE"
packer fmt -check -recursive "$TEMPLATE"
packer validate "$TEMPLATE"
```

- Set `TEMPLATE` to each affected root. Run `packer init` on a fresh plugin cache and supply the root's required variables for `packer validate`.
- To prepare an answer file without building, run `packer/scripts/generate-autoinstall.sh` from the repository root with the source and output paths under `$TEMPLATE`, using the same filenames as the build wrapper. Do not use `build.sh` as a validation command: it launches a live build.
- For changes to a template cloned by Terraform, trace the clone setting and check the resulting guest assumptions used by Ansible.
