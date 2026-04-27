# Packer Agent Notes

Read the repo root `AGENTS.md` first for repo-wide policy. This file only covers Packer-local editing rules.

## What This Subtree Owns
- Each template directory is a self-contained build root with its own Packer config, variables, and helper entrypoints.
- `packer/scripts/` owns shared helper logic used by one or more templates.
- The output of this subtree is reusable VM templates that Terraform later clones.

## Source Of Truth Boundaries
- Hand-authored template definitions live in each template root; generated autoinstall or helper-produced inputs are workflow artifacts, not ad hoc edit targets.
- If a template-local `build.sh` prepares generated inputs first, treat that wrapper as part of the intended source-of-truth workflow rather than an optional convenience script.
- Secrets and SSH material belong in environment variables, Bitwarden-backed flows, or helper scripts, not inline Packer config.

## Local Anti-Patterns
- Do not hardcode secrets, tokens, or private keys into template files.
- Do not skip template-local wrapper scripts when they prepare generated inputs required for a correct build.
- Do not document or depend on a brittle list of current template names when the subtree is meant to support additional template roots over time.
- Do not change a base template casually without checking the downstream Terraform consumers that clone it.

## Validation
```bash
packer validate packer/ubuntu-24.04-base
packer validate packer/ubuntu-26.04-base
packer validate packer/fedora-43-server
```

- Treat those commands as representative examples of validating template roots; keep this file aligned when new template directories are added.
- After changing a base template used by Terraform, call out the downstream impact on cloned node builds and any image compatibility assumptions.
