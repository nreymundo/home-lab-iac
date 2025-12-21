# Packer Templates for Proxmox VE

This directory contains Packer configurations for building standardized virtual machine templates for Proxmox VE. The current focus is on **Ubuntu 24.04 LTS**.

## 🏗️ Architecture

The build process uses the `proxmox-iso` builder to:
1. Boot from an official Ubuntu Server ISO.
2. Automate installation via **Cloud-Init** (Autoinstall).
3. Provision the system using shell scripts.
4. Convert the VM into a Proxmox template.

## 🚀 Quick Start

### Prerequisites
- **Packer** (v1.10+)
- **Proxmox VE** (with API access)
- **Proxmox API Token** (ID and Secret)

### 1. Configure Credentials
Create a variable file `ubuntu-24.04-base/variables.auto.pkrvars.hcl` based on the example:

```hcl
proxmox_api_url = "https://192.168.1.10:8006/api2/json"
proxmox_api_token_id = "packer@pam!packer"
proxmox_api_token_secret = "your-secret-token"
```

> **⚠️ Security Note:** Never commit `variables.auto.pkrvars.hcl` to version control. It is git-ignored by default.

### 2. Customize Cloud-Init
Review and update the cloud-init user-data if necessary:
- `ubuntu-24.04-base/http/user-data`: Controls the autoinstall process, including default user, timezone, and SSH keys.

### 3. Build the Template
Navigate to the template directory and run the build:

```bash
cd ubuntu-24.04-base

# Initialize Packer plugins
packer init .

# Validate configuration
packer validate .

# Build the template
packer build .
```

## 📂 Directory Structure

```
packer/
├── ubuntu-24.04-base/
│   ├── http/
│   │   ├── meta-data          # Cloud-init meta-data
│   │   └── user-data          # Autoinstall configuration
│   ├── scripts/
│   │   └── setup.sh           # Provisioning script (updates, qemu-guest-agent)
│   ├── ubuntu-24.04.pkr.hcl   # Main Packer configuration
│   ├── variables.pkr.hcl      # Variable definitions
│   └── variables.auto.pkrvars.hcl.example # Example variables
└── README.md
```

## ⚙️ Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `proxmox_api_url` | URL of the Proxmox API | Required |
| `proxmox_api_token_id` | API Token ID | Required |
| `proxmox_api_token_secret` | API Token Secret | Required |
| `proxmox_node` | Target Proxmox Node | `pve1` |
| `iso_file` | Path to Ubuntu ISO on Proxmox storage | `local:iso/ubuntu-24.04-live-server-amd64.iso` |

## 🔧 Customization

### Adding Packages
Modify `ubuntu-24.04-base/scripts/setup.sh` to install additional software or perform system configuration during the build process.

### Changing VM Hardware
Adjust resource allocation (CPU, RAM, Disk) in `ubuntu-24.04-base/ubuntu-24.04.pkr.hcl` within the `source "proxmox-iso"` block.

## 🛠️ Troubleshooting

- **Build freezes at boot:** Check VNC output in Proxmox console. Often caused by incorrect boot commands or cloud-init syntax errors.
- **API Authentication Failed:** Verify token permissions. The user needs `VM.Allocate`, `VM.Config.Disk`, `VM.Config.CPU`, `VM.Config.Memory`, `Datastore.AllocateSpace`.
- **ISO Not Found:** Ensure the `iso_file` path matches exactly where the ISO is stored on your Proxmox node.
