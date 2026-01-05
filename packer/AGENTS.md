# AGENTS.md

**Generated:** 2026-01-05 21:13:08
**Commit:** 9c644bd

## OVERVIEW

Packer builds "Golden Images" for VM templates (Ubuntu 24.04, Fedora 43).
**Key Pattern:** Secret injection via Bitwarden CLI at build time.

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| **Build Ubuntu template** | `ubuntu-24.04-base/build.sh` | Entry point |
| **Build Fedora template** | `fedora-43-server/build.sh` | Entry point |
| **Cloud-init templates** | `ubuntu-24.04-base/http/*.template` | User-data generation |
| **Kickstart templates** | `fedora-43-server/http/*.template` | Autoinstall config |
| **Secret fetching** | `scripts/fetch-ssh-keys.sh` | Bitwarden integration |
| **Template generation** | `scripts/generate-autoinstall.sh` | cloud-init + kickstart |

## STRUCTURE

```
packer/
├── scripts/
│   ├── fetch-ssh-keys.sh          # Bitwarden CLI wrapper
│   └── generate-autoinstall.sh     # Template engine
├── ubuntu-24.04-base/
│   ├── ubuntu-24.04.pkr.hcl       # Packer config
│   ├── build.sh                    # Build orchestration
│   └── http/                       # cloud-init templates
└── fedora-43-server/
    ├── fedora-43-server.pkr.hcl    # Packer config
    ├── build.sh                    # Build orchestration
    └── http/                       # kickstart templates
```

## CONVENTIONS

### Secret Injection
- Uses `fetch-ssh-keys.sh` (Bitwarden CLI: `bws`) at build time
- Retrieves public keys from Bitwarden Secrets Manager
- **NEVER** commit keys to repository

### VM ID Scheme
- **Ubuntu 24.04**: IDs 9000-9019
- **Fedora 43**: IDs 9020-9039
- Documented in `packer/README.md`

### Template Generation
- `generate-autoinstall.sh` handles both cloud-init and kickstart formats
- Detects template type from filename
- Replaces `{{SSH_PUBLIC_KEYS}}` placeholder

## ANTI-PATTERNS

1. **NEVER** commit SSH keys or secrets to repository.
2. **DO NOT** hardcode keys in templates—use `fetch-ssh-keys.sh`.
3. **DO NOT** skip `packer validate` before building.

## VERIFICATION

```bash
# Validate
packer validate .

# Format
packer fmt -check

# Build (from distro directory)
cd packer/ubuntu-24.04-base
./build.sh
```

## NOTES

- Pre-commit hook enforces `packer fmt`.
- Requires `BW_ACCESS_TOKEN` environment variable for Bitwarden CLI.
