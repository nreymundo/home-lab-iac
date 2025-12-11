# Packer Build: Ubuntu 24.04 Base Image

This directory contains the Packer configuration to build a standardized **Ubuntu 24.04 LTS** virtual machine template on Proxmox VE. This template is used by Terraform to provision K3s worker nodes.

## 📋 Features

- **Base OS**: Ubuntu 24.04 LTS.
- **Cloud-Init**: Enabled for dynamic configuration (SSH keys, users, network) at provisioning time.
- **QEMU Guest Agent**: Installed and enabled for Proxmox integration.
- **Setup Script**: Runs `scripts/setup.sh` to perform initial updates and package installations.

## ⚙️ Configuration

The build is defined in `ubuntu-24.04-base/ubuntu-24.04.pkr.hcl`.

### Required Variables

Create a file named `variables.auto.pkrvars.hcl` in the `ubuntu-24.04-base` directory with the following content (adjust values to your environment):

```hcl
proxmox_api_url          = "https://192.168.1.100:8006/api2/json"
proxmox_api_token_id     = "user@pam!packer"
proxmox_api_token_secret = "your-secret-token"

# ISO Configuration (Must exist on Proxmox storage)
iso_name                 = "ubuntu-24.04.3-live-server-amd64.iso"
iso_storage_pool         = "local" # or 'unraid', 'nas', etc.
```

**Note:** The build configuration supports deploying the template to multiple Proxmox nodes (`pve1`, `pve2`) simultaneously if configured in the `build` sources.

## 🌐 Multi-Node Support

The template builds in parallel on multiple Proxmox nodes (currently `pve1` and `pve2`). Common hardware and boot configuration is centralized in the `locals` block, making it easy to add additional nodes.

## 🔨 Usage

1.  **Navigate to the directory**:
    ```bash
    cd packer/ubuntu-24.04-base
    ```

2.  **Configure variables** (first-time setup):
    ```bash
    cp variables.auto.pkrvars.hcl.example variables.auto.pkrvars.hcl
    # Edit variables.auto.pkrvars.hcl with your Proxmox API credentials
    ```

3.  **Initialize Packer** (download plugins):
    ```bash
    packer init .
    ```

4.  **Validate the template**:
    ```bash
    packer validate .
    ```

5.  **Build the Image**:
    ```bash
    packer build .
    ```

## 📝 Output

Upon successful completion, you will have a VM template (e.g., ID `9000` or `9001`) on your Proxmox node(s) named `ubuntu-24.04-base`.

## 🌐 Adding Proxmox Nodes

To deploy the template to additional Proxmox nodes:

1. Open `ubuntu-24.04.pkr.hcl`
2. Copy an existing `source "proxmox-iso"` block
3. Update three values:
   - `node = "pve3"` (your new node name)
   - `vm_id = local.vm_base_id + 2` (increment: pve1=+0, pve2=+1, pve3=+2, etc.)
   - `template_description = "... for pve3 ..."`
4. Add the new source to `build.sources`:
   ```hcl
   sources = [
     "source.proxmox-iso.ubuntu-base-pve1",
     "source.proxmox-iso.ubuntu-base-pve2",
     "source.proxmox-iso.ubuntu-base-pve3",  # Add this
   ]
   ```
5. Run `packer fmt .` and `packer validate .`

*Note:* The template is deployed to each node individually because shared storage is not yet available in this setup.

## 🔧 Development Workflow

Before committing Packer changes:

```bash
# Format HCL files
packer fmt -recursive .

# Validate configuration
packer validate .

# Run all pre-commit hooks
pre-commit run --all-files
```

**Note**: The pre-commit hooks will automatically run `packer fmt` on modified `.pkr.hcl` files.
