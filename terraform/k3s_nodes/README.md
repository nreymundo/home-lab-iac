# K3s Nodes Terraform Configuration

Provisions K3s node VMs on Proxmox using a base template created by Packer.

## Requirements

- **Packer template** (`ubuntu-24.04-base`) must exist in Proxmox
- **Bitwarden Secrets Manager** access with secrets configured
- **Proxmox API credentials**

## Authentication

### Proxmox
Set environment variables for Proxmox API access:
```bash
export PM_API_URL="https://<proxmox-host>:8006/api2/json"
export PM_API_TOKEN_ID="user@pam!token-id"
export PM_API_TOKEN_SECRET="your-token-secret"
```

### Bitwarden Secrets Manager
The Bitwarden provider retrieves SSH public keys from your Bitwarden vault:

Required environment variables:
- `BW_ORGANIZATION_ID` - Your Bitwarden organization ID
- `BW_ACCESS_TOKEN` - Bitwarden Secrets Manager access token
- `BW_SSH_KEYS_ID` - Secret ID for SSH public keys

Pass the secret ID into Terraform:
```bash
export TF_VAR_ssh_keys_secret_id="$BW_SSH_KEYS_ID"
```

## Secrets Configuration

### SSH Public Keys
1. Store your SSH public keys in Bitwarden Secrets Manager as a secret
2. Each key should be on a separate line in the secret value
3. Export `BW_SSH_KEYS_ID` and `TF_VAR_ssh_keys_secret_id` before running Terraform

## Variables

Configure VM parameters via `terraform.tfvars` or CLI:

```hcl
template_name          = "ubuntu-24.04-base"
node_count             = 2
node_ip_start          = "192.168.10.50"
proxmox_nodes          = ["pve1", "pve2"]
vm_cores               = 8
vm_memory_mb           = 8192
vm_disk_size_gb        = 32
secondary_disk_enabled = true
secondary_disk_size_gb = 200
```

See `variables.tf` for all available options.

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Output

- **Inventory file**: Automatically generates `ansible/inventories/k3s-nodes.yml`
- **VM IPs**: Displays allocated IPs after deployment
