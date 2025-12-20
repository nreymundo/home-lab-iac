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

Use environment variables instead of tfvars for sensitive and connection data:

```bash
# Proxmox provider (required)
export PM_API_URL="https://192.168.1.100:8006/api2/json"
export PM_API_TOKEN_ID="user@pam!terraform"
export PM_API_TOKEN_SECRET="your-token"

# Terraform inputs (TF_VAR_*)
export TF_VAR_ssh_public_keys='["ssh-ed25519 AAAAC3Nz..."]'
# Optional: explicitly set the module variable instead of PM_API_URL
# export TF_VAR_proxmox_api_url="https://192.168.1.100:8006/api2/json"
```

Other variables keep their defaults; see `variables.tf` for all options (e.g., `node_count`, `node_ip_start`, `vm_*` sizing, networking). Defaults target the 192.168.10.0/24 subnet; adjust `ip_prefix_len` and related values if your network differs.

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
