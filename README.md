# Home Lab IaC

Infrastructure as Code (IaC) repository for managing my home lab setup.

## Components

### Ansible (`ansible/`)
Configuration management for existing servers.
- **Targets:** Raspberry Pi (Raspbian/Ubuntu) and Proxmox VE nodes.
- **Features:** System hardening, user management, networking (Netplan), and automated updates (where appropriate).

### Packer (`packer/`)
Image builder for creating standardized VM templates.
- **Current Images:** Ubuntu 24.04 Base.

### Terraform (`terraform/`)
Infrastructure provisioning for K3s Kubernetes nodes.
- **Targets:** Proxmox VE.
- **Features:** VM cloning, static IP assignment, and Ansible inventory generation.

## Usage
Refer to the `README.md` inside each directory for specific instructions.
