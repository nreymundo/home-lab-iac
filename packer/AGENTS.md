# PACKER KNOWLEDGE BASE

## OVERVIEW
`packer/` builds Proxmox VM templates that Terraform later clones for K3s nodes and other hosts.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Ubuntu base template | `ubuntu-24.04-base/` | Current K3s node template default |
| Fedora template | `fedora-43-server/` | Separate template root |
| Main build config | `<template>/*.pkr.hcl` | Source blocks, build steps, variables |
| Helper scripts | `<template>/build.sh`, `scripts/` | Build wrapper and SSH/autoinstall generation |

## CONVENTIONS
- Validate inside the template directory before running the wrapper build script.
- Templates use Bitwarden-backed SSH key injection and generated autoinstall data.
- Template roots are self-contained: variables, main config, scripts, and build entrypoint live together.

## ANTI-PATTERNS
- Do not skip template-local `build.sh` when comments say it prepares generated inputs first.
- Do not hardcode secrets into Packer files; this repo expects environment variables and helper scripts.

## COMMANDS
```bash
packer validate packer/ubuntu-24.04-base
packer validate packer/fedora-43-server
```

## NOTES
- The default Terraform template name is `ubuntu-24.04-base`, so changes there have downstream impact on node provisioning.
