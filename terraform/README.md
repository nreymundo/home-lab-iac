# Terraform – K3s Infrastructure Provisioning

Provisioning layer for the K3s Kubernetes cluster on Proxmox VE. This module handles the creation of virtual machines using the Packer-built templates and generates the necessary Ansible inventory.

## 🏗️ Architecture

- **Provider:** `telmate/proxmox` (Proxmox VE)
- **Source:** Clones from `ubuntu-24.04-base` template
- **Output:**
  - Virtual Machines on Proxmox
  - Dynamic Ansible Inventory (`ansible/inventories/k3s-nodes.yml`)

## 🚀 Quick Start

### Prerequisites
1. **Packer Template:** Ensure `ubuntu-24.04-base` has been built and is available on the Proxmox storage.
2. **Terraform:** v1.0+ installed.
3. **Proxmox Credentials:** API token ID and Secret.

### 1. Environment Configuration
Terraform requires credentials to communicate with Proxmox. Use environment variables to keep them secure:

```bash
export PM_API_URL="https://192.168.1.10:8006/api2/json"
export PM_API_TOKEN_ID="terraform@pam!terraform"
export PM_API_TOKEN_SECRET="your-secret-token"

# Optional: SSH Keys for VM access (if not using defaults)
export TF_VAR_ssh_public_keys='["ssh-ed25519 AAAAC3..."]'
```

### 2. Initialize and Apply

```bash
cd terraform/k3s_nodes

# Initialize Terraform (download providers)
terraform init

# Review execution plan
terraform plan

# Apply changes to infrastructure
terraform apply
```

## ⚙️ Configuration Variables

Key variables defined in `variables.tf`. You can override these via `TF_VAR_` environment variables or a `terraform.tfvars` file.

| Variable | Description | Default |
|----------|-------------|---------|
| `node_count` | Number of K3s nodes to provision | `2` |
| `pm_node` | Proxmox node to deploy VMs on | `pve1` |
| `template_name` | Name of the Packer template | `ubuntu-24.04-base` |
| `vm_memory` | RAM per VM (MB) | `4096` |
| `vm_cores` | CPU cores per VM | `2` |
| `ip_prefix_len` | Network CIDR prefix | `24` |
| `node_ip_start` | Starting IP octet | `50` (e.g., 192.168.10.50) |

## 🔗 Integration with Ansible

This Terraform module includes a `local_file` resource that automatically generates an Ansible inventory file.

**Generated File:** `ansible/inventories/k3s-nodes.yml`

**Example Output:**
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

This integration allows for a seamless workflow:
1. `terraform apply` -> Creates VMs + Updates Inventory
2. `ansible-playbook` -> Configures the new VMs immediately

## 🛠️ State Management

Terraform state is currently stored **locally** (`terraform.tfstate`).
- **Backup:** Ensure this file is backed up if working in a team or across multiple machines.
- **Locking:** No remote locking is configured. Avoid concurrent runs.
