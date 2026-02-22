# Terraform - AI Assistant Instructions

This document provides instructions for AI coding assistants (Claude, Gemini, etc.) working with the Terraform component.

## Directory Structure

```
terraform/
└── k3s_nodes/                    # K3s node VM provisioning module
    ├── main.tf                   # Resource definitions (VMs, inventory generation)
    ├── variables.tf              # Input variable definitions
    ├── terraform.tfvars          # Variable values (node configs)
    ├── providers.tf              # Provider configuration (Proxmox, Bitwarden)
    ├── data.tf                   # Data sources
    ├── templates/
    │   └── inventory.yaml.tpl    # Template for Ansible inventory generation
    ├── .terraform/               # Provider cache (gitignored)
    └── .terraform.lock.hcl       # Provider lock file
```

## Providers

| Provider | Purpose |
|----------|---------|
| `telmate/proxmox` | Create VMs on Proxmox VE cluster |
| `bitwarden/bitwarden-secrets` | Retrieve SSH keys from Bitwarden Secrets Manager |

## Key Files

| File | Purpose |
|------|---------|
| `main.tf` | Creates `proxmox_vm_qemu.k3s_nodes` resources and generates Ansible inventory |
| `variables.tf` | Defines all configurable variables with defaults and validation |
| `terraform.tfvars` | **Primary configuration file** - node list and overrides |
| `providers.tf` | Provider versions and authentication configuration |

## How to Add a New K3s Node

1. Edit `terraform.tfvars` and add an entry to the `nodes` list:
   ```hcl
   nodes = [
     {},  # node-01 uses all defaults
     {},  # node-02 uses all defaults
     {    # node-03 with custom specs
       vm_cores    = 12
       vm_memory_mb = 16384
       target_node  = "pve2"
       labels = {
         "homelab.lan/role" = "storage"
       }
     },
   ]
   ```

2. Run `terraform plan` to preview changes

3. Run `terraform apply` to create the VM

The number of nodes equals the length of the `nodes` list.

## Node Configuration Options

Each node in the `nodes` list can override:

| Field | Default | Description |
|-------|---------|-------------|
| `template_name` | `ubuntu-24.04-base` | Packer template to clone |
| `ci_user` | `ubuntu` | Cloud-init username |
| `ansible_user` | Same as `ci_user` | Ansible SSH user |
| `target_node` | Round-robin across `proxmox_nodes` | Proxmox node to deploy on |
| `vm_cores` | 8 | CPU cores |
| `vm_memory_mb` | 24576 | RAM in MB |
| `vm_balloon_mb` | 16384 | Minimum balloon memory in MB |
| `vm_disk_size_gb` | 32 | Primary disk size |
| `secondary_disk_size_gb` | 200 | Secondary disk size |
| `labels` | `{}` | Additional K3s node labels |

## K3s Node Labels

Default labels applied to all nodes:
- `homelab.lan/role` = `general`
- `homelab.lan/cpu-vendor` = `intel`
- `homelab.lan/runtime` = `vm`
- `homelab.lan/hypervisor` = `proxmox`
- `homelab.lan/gpu` = `none`
- `topology.kubernetes.io/zone` = Proxmox node name (for zone awareness)

Override or extend via `labels` map in node configuration.

## Ansible Integration

Terraform automatically generates the Ansible inventory at:
```
ansible/inventories/k3s-nodes.yml
```

This file is regenerated on every `terraform apply` and includes:
- Node hostnames and IPs
- Ansible user per node
- K3s node labels

## How to Run

**Always run from the `k3s_nodes/` directory**:

```bash
cd terraform/k3s_nodes

# Initialize providers (first time or after provider changes)
terraform init

# Preview changes
terraform plan

# Apply changes
terraform apply

# Destroy specific resources
terraform destroy -target="proxmox_vm_qemu.k3s_nodes[2]"
```

## Environment Variables

The following environment variables are typically set for Proxmox authentication:

```bash
export PM_API_URL="https://proxmox.lan:8006/api2/json"
export PM_API_TOKEN_ID="terraform@pve!terraform"
export PM_API_TOKEN_SECRET="<secret>"
```

Bitwarden authentication uses the `BWS_ACCESS_TOKEN` environment variable.

## Validation

### Pre-commit Hooks
```bash
# Run from repo root
pre-commit run terraform-fmt --all-files
```

### Manual Validation
```bash
cd terraform/k3s_nodes

# Format check
terraform fmt -check

# Validate configuration
terraform validate

# Format and write
terraform fmt
```

## Common Tasks

| Task | Command |
|------|---------|
| Add nodes | Edit `terraform.tfvars`, then `terraform apply` |
| Remove nodes | Remove from `nodes` list, then `terraform apply` |
| Preview changes | `terraform plan` |
| View current state | `terraform show` |
| Import existing VM | `terraform import proxmox_vm_qemu.k3s_nodes[0] pve1/qemu/200` |
| Refresh state | `terraform refresh` |

## Important Notes

1. **VM IDs**: Start at `node_vmid_start` (default 200) and increment.

2. **IP addresses**: Start at `node_ip_start` and increment for each node.

3. **Template dependency**: VMs clone from Packer-built templates. Ensure templates exist before running.
