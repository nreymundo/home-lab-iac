# Home Lab IaC

Infrastructure as Code (IaC) repository for managing a comprehensive home lab setup with Kubernetes, Proxmox virtualization, and Raspberry Pi edge devices.

## Architecture Overview

This repository implements a GitOps-style home lab with three main components:

1. **Base Infrastructure** (Packer + Terraform): Provisions VM templates and K3s Kubernetes nodes
2. **Configuration Management** (Ansible): Configures bare-metal hosts and VMs
3. **Automation**: Pre-commit hooks and CI/CD for consistency

## Quick Start

```bash
# 1. Install dependencies
pip install ansible ansible-lint yamllint
npm install -g @commitlint/cli @commitlint/config-conventional
pre-commit install

# 2. Build VM template (Packer)
cd packer/ubuntu-24.04-base
cp variables.auto.pkrvars.hcl.example variables.auto.pkrvars.hcl
# Edit variables with your Proxmox credentials
packer init .
packer build .

# 3. Provision K3s nodes (Terraform)
cd ../../terraform/k3s_nodes
export PM_API_URL="https://your-proxmox:8006/api2/json"
export PM_API_TOKEN_ID="user@pam!terraform"
export PM_API_TOKEN_SECRET="your-token"
export TF_VAR_ssh_public_keys='["ssh-ed25519 AAAAC3Nz..."]'
terraform init && terraform apply

# 4. Configure all hosts (Ansible)
cd ../../ansible
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --check  # Dry run
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml            # Apply
ansible-playbook -i inventories/all-vms.yml -i inventories/k3s-nodes.yml playbooks/ubuntu_vms.yml
```

## Components

### 📁 Ansible (`ansible/`)
Configuration management for existing servers and VMs.

**Targets:**
- Raspberry Pi (4/5/CM) running Ubuntu Server
- Proxmox VE nodes (management)
- Ubuntu VM guests (K3s nodes, applications)

**Key Features:**
- **Security:** SSH hardening, user management, fail2ban
- **Networking:** Netplan configuration, static IPs, VLAN support
- **System:** Unattended upgrades, timezone sync, NTP
- **Storage:** LVM disk expansion for VMs
- **Monitoring:** QEMU guest agent setup

**Usage Examples:**
```bash
# Configure Raspberry Pi hosts
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml

# Configure Proxmox management nodes
ansible-playbook -i inventories/baremetal.yml playbooks/proxmox.yml

# Configure Ubuntu VMs (K3s nodes)
ansible-playbook -i inventories/all-vms.yml -i inventories/k3s-nodes.yml playbooks/ubuntu_vms.yml
```

### 🏗️ Packer (`packer/`)
Image builder for creating standardized VM templates.

**Current Templates:**
- Ubuntu 24.04 LTS Base with cloud-init
- Optimized for Proxmox VE with QEMU guest agent
- K3s prerequisites pre-installed

**Key Features:**
- Cloud-init ready for SSH keys and user provisioning
- Multi-node Proxmox cluster support
- Automated security updates and hardening
- Template validation and formatting checks

### 🌐 Terraform (`terraform/`)
Infrastructure provisioning for Kubernetes nodes.

**Capabilities:**
- VM cloning from Packer templates
- Load balancing across Proxmox nodes
- Dynamic IP assignment and DNS integration
- Automated Ansible inventory generation
- State management for reproducible deployments

**K3s Cluster Deployment:**
```bash
cd terraform/k3s_nodes
terraform plan  # Preview changes
terraform apply # Deploy cluster
```

## Repository Structure

```
home-lab-iac/
├── ansible/                    # Configuration management
│   ├── inventories/           # Host definitions and variables
│   ├── playbooks/             # Site-specific playbooks
│   └── roles/                 # Reusable Ansible roles
├── packer/                    # VM image templates
│   └── ubuntu-24.04-base/    # Ubuntu base template
├── terraform/                 # Infrastructure provisioning
│   └── k3s_nodes/            # K3s cluster configuration
├── .github/                   # CI/CD workflows
├── .pre-commit-config.yaml    # Pre-commit hooks
└── AGENTS.md                  # Development guidelines
```

## Development Workflow

### Pre-commit Checks
This repository uses pre-commit hooks to ensure code quality:

```bash
# Run all checks
pre-commit run --all-files

# Individual checks
ansible-lint playbooks/*.yml
yamllint .
packer validate packer/*/
terraform fmt -check terraform/
```

### Code Standards
- **YAML:** 2-space indentation, 120 char line limit
- **HCL:** Standard Terraform formatting
- **Shell:** POSIX-compliant, `set -euo pipefail`
- **Commits:** Conventional commit messages
- **Security:** No secrets in repo, use environment variables

### Testing
```bash
# Ansible dry-run
ansible-playbook --check --diff

# Terraform validation
terraform plan -detailed-exitcode

# Packer validation
packer validate -syntax-only
```

## Configuration Files

- **`.yamllint`**: YAML linting rules
- **`.pre-commit-config.yaml`**: Git hooks configuration
- **`ansible/ansible.cfg`**: Ansible settings and defaults
- **`AGENTS.md`**: Detailed development guidelines

## Security Considerations

- 🔒 SSH keys committed directly in Ansible inventory files
- 🛡️ Proxmox API tokens stored securely, never committed
- 🔐 Root login disabled on all hosts except Proxmox management
- 📝 Automated security updates on edge devices
- 🔍 Regular dependency updates and vulnerability scanning

## Support

Refer to individual component READMEs for detailed documentation:
- [Ansible Documentation](ansible/README.md)
- [Packer Documentation](packer/README.md)
- [Terraform Documentation](terraform/README.md)
