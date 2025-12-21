# Home Lab IaC

This is like my 4th attempt to trying to bring some order to the madness that is my home lab.

The main purpose is to slowly consolidate all the custom scripts and configurations I've put into my Proxmox nodes and also to bring down the number of VMs and LXCs I use by moving to Kubernetes.

## ⚠️ Notice

1. This repository is a massive work in progress and there's no guarantee I will ever finish it. I'll keep adding to it as I keep adding more stuff to my homelab. Or at least that's the idea.
2. The code is either written by me or written by AI and audited by me.
3. The READMEs and documentations are mostly written by AI as a way to keep track of everything and so I know WTF was going if I take a break and eventually come back to this.
4. Finally, the code isn't the best in all places. In some cases you'll see long very tailored shell commands or things that are, honeslty, flaky as fuck. _The joys of homelabing_.

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
