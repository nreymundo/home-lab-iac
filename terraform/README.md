# Terraform: K3s Node Provisioning

This Terraform configuration provisions generic K3s node VMs on Proxmox using the `telmate/proxmox` provider. It clones the Packer-built `ubuntu-24.04-base` template and generates an Ansible inventory alongside the rest of the repo.

## Automation Features

- **Cloning**: Creates VMs from the `ubuntu-24.04-base` template.
- **Load balancing**: Distributes VMs across the provided Proxmox nodes list (e.g., `pve1`, `pve2`).
- **Dynamic inventory**: Writes `ansible/inventories/k3s-nodes.yml` with hostnames, IPs, and `ansible_user: ubuntu` for the created VMs.

## Configuration

### Prerequisites
- A Packer-built template named `ubuntu-24.04-base` available on the target Proxmox nodes.

### Variables

Create a `terraform.tfvars` (or `*.auto.tfvars`) file in `terraform/k3s_nodes/`:

```hcl
proxmox_api_url = "https://192.168.1.100:8006/api2/json"

# Credentials (recommend using environment variables or a secure secret manager)
# export PM_API_TOKEN_ID="user@pam!terraform"
# export PM_API_TOKEN_SECRET="your-token"

ssh_public_keys = [
  "ssh-ed25519 AAAAC3Nz..."
]

node_count    = 3
node_ip_start = "192.168.10.50"
# Optional overrides
# node_vmid_start = 180
# ip_prefix_len   = 24
# gateway_ip      = "192.168.10.1"
```

See `variables.tf` for all available options and defaults. Defaults target the 192.168.10.0/24 subnet; adjust `ip_prefix_len` and related values if your network differs.

## Usage

1. **Navigate to the directory**:
   ```bash
   cd terraform/k3s_nodes
   ```
2. **Initialize Terraform**:
   ```bash
   terraform init
   ```
3. **Plan the deployment**:
   ```bash
   terraform plan
   ```
4. **Apply changes**:
   ```bash
   terraform apply
   ```

## Generated Inventory

After `terraform apply`, check `ansible/inventories/k3s-nodes.yml`. It will look like:

```yaml
all:
  children:
    k3s_nodes:
      hosts:
        k3s-node-01:
          ansible_host: 192.168.10.50
          ansible_user: ubuntu
        k3s-node-02:
          ansible_host: 192.168.10.51
          ansible_user: ubuntu
```
