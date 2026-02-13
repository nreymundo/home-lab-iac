# Packer - AI Assistant Instructions

This document provides instructions for AI coding assistants (Claude, Gemini, etc.) working with the Packer component.

## Directory Structure

```
packer/
├── scripts/                      # Shared scripts
│   └── generate-autoinstall.sh   # Generates user-data with Bitwarden SSH keys
├── ubuntu-24.04-base/            # Ubuntu 24.04 template
│   ├── ubuntu-24.04.pkr.hcl      # Main Packer configuration
│   ├── variables.pkr.hcl         # Variable definitions
│   ├── build.sh                  # Build wrapper script (USE THIS)
│   ├── http/                     # Autoinstall files served via HTTP
│   │   ├── user-data.template    # Template for cloud-init autoinstall
│   │   └── user-data             # Generated file (gitignored)
│   └── scripts/
│       └── setup.sh              # Post-install provisioning script
└── fedora-43-server/             # Fedora 43 template (same structure)
    ├── fedora-43.pkr.hcl
    ├── variables.pkr.hcl
    ├── build.sh
    ├── http/
    └── scripts/
```

## Key Concepts

### Build Wrapper Script
**Always use `./build.sh` instead of `packer build`**. The build script:
1. Runs `generate-autoinstall.sh` to inject SSH keys from Bitwarden
2. Generates the `http/user-data` file from the template
3. Invokes `packer build` with any additional arguments

### Multi-Node Templates
Each template creates identical images on multiple Proxmox nodes (pve1, pve2) for local cloning performance.

### VM ID Convention
| Distro | Base ID | pve1 | pve2 |
|--------|---------|------|------|
| Ubuntu 24.04 | 9000 | 9001 | 9002 |
| Fedora 43 | 9100 | 9101 | 9102 |

## Key Files

| File | Purpose |
|------|---------|
| `*.pkr.hcl` | Main Packer configuration with sources and build blocks |
| `variables.pkr.hcl` | Variable definitions with defaults |
| `build.sh` | **Entry point** - generates user-data and runs packer |
| `http/user-data.template` | Cloud-init autoinstall template |
| `scripts/setup.sh` | Post-install provisioning (packages, cleanup) |

## Template Structure

Each `.pkr.hcl` file contains:

1. **Plugin requirements**: Proxmox plugin version
2. **Locals**: Computed values (VM name, IDs, defaults)
3. **Sources**: One `proxmox-iso` source per Proxmox node
4. **Build block**: Provisioners applied to all sources

Example source pattern:
```hcl
source "proxmox-iso" "ubuntu-base-pve1" {
  node     = "pve1"
  vm_id    = local.pve1_vm_id
  vm_name  = local.vm_name
  # ... hardware config
}
```

## How to Add a New Template

1. **Copy an existing template folder**:
   ```bash
   cp -r packer/ubuntu-24.04-base packer/<distro>-<version>-base
   ```

2. **Update the main `.pkr.hcl`**:
   - Change `vm_name` in locals
   - Update `distro_base_id` for unique VM IDs
   - Modify `boot_command` for the distribution
   - Update `ssh_username` if different

3. **Update `variables.pkr.hcl`**:
   - Change default `iso_name` to the new ISO

4. **Update autoinstall files in `http/`**:
   - Ubuntu uses `user-data` (cloud-init autoinstall)
   - Fedora uses `ks.cfg` (Kickstart)

5. **Update `scripts/setup.sh`**:
   - Adjust package manager commands
   - Modify cleanup steps

6. **Test the build**:
   ```bash
   cd packer/<new-template>
   ./build.sh
   ```

## How to Build Templates

```bash
cd packer/ubuntu-24.04-base

# Build both pve1 and pve2 templates
./build.sh

# Build only pve1
./build.sh -only="proxmox-iso.ubuntu-base-pve1"

# Build with debug output
./build.sh -debug

# Dry run (validate only)
packer validate .
```

## Environment Variables

Required for Proxmox authentication:
```bash
export PKR_VAR_proxmox_api_url="https://proxmox.lan:8006/api2/json"
export PKR_VAR_proxmox_api_token_id="packer@pve!packer"
export PKR_VAR_proxmox_api_token_secret="<secret>"
```

Required for Bitwarden SSH key injection:
```bash
export BWS_ACCESS_TOKEN="<bitwarden-secrets-token>"
```

## Validation

### Pre-commit Hooks
```bash
# Run from repo root
pre-commit run packer-fmt --all-files
```

### Manual Validation
```bash
cd packer/ubuntu-24.04-base

# Format check
packer fmt -check .

# Validate configuration
packer validate .

# Format and write
packer fmt .
```

## Common Tasks

| Task | Command |
|------|---------|
| Build all templates | `./build.sh` |
| Build specific node | `./build.sh -only="proxmox-iso.<source-name>"` |
| Validate without building | `packer validate .` |
| Format HCL files | `packer fmt .` |
| Debug build issues | `./build.sh -debug` or `PACKER_LOG=1 ./build.sh` |

## Important Notes

1. **ISO files**: Must be pre-uploaded to Proxmox ISO storage (`local:iso/<filename>`)

2. **SSH keys**: Injected from Bitwarden Secrets Manager via `generate-autoinstall.sh`

3. **Cloud-init**: Templates are cloud-init ready for Terraform cloning

4. **Tags**: Templates are tagged with `packer` and node name for identification

5. **Cleanup**: `setup.sh` removes SSH host keys and cloud-init state for clean cloning
