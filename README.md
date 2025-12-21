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
pre-commit install

# 2. Build VM template (Packer)
cd packer/ubuntu-24.04-base
# [See packer/README.md for setup]
packer build .

# 3. Provision K3s nodes (Terraform)
cd ../../terraform/k3s_nodes
# [See terraform/README.md for credentials]
terraform init && terraform apply

# 4. Configure all hosts (Ansible)
cd ../../ansible
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml
```

## Components

### 📁 Ansible (`ansible/`)
Configuration management for existing servers and VMs. Handles system hardening, user management, networking, and software installation.

**[Read Ansible Documentation](ansible/README.md)**

### 🏗️ Packer (`packer/`)
Image builder for creating standardized VM templates (Ubuntu 24.04 LTS) optimized for Proxmox VE.

**[Read Packer Documentation](packer/README.md)**

### 🌐 Terraform (`terraform/`)
Infrastructure provisioning for Kubernetes nodes. Handles VM cloning, load balancing, and dynamic Ansible inventory generation.

**[Read Terraform Documentation](terraform/README.md)**

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

## Security Considerations

- 🔒 SSH keys committed directly in Ansible inventory files
- 🛡️ Proxmox API tokens stored securely (env vars), never committed
- 🔐 Root login disabled on all hosts except Proxmox management
- 📝 Automated security updates on edge devices
- 🔍 Regular dependency updates and vulnerability scanning
