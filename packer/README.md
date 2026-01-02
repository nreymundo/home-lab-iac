# Packer Templates

Packer builds the "Golden Image" for our VMs.

## Why use Packer?
- **Speed:** Cloning a template takes seconds. Installing Ubuntu from ISO takes minutes.
- **Consistency:** Every VM starts with the exact same packages and config.
- **Automation:** No manual clicking through the Ubuntu installer.

## 🏗️ The Build Process

1.  **Boot:** Starts a VM on Proxmox using the ISO (Ubuntu or Fedora).
2.  **Autoinstall:** Uses cloud-init (Ubuntu) or Kickstart (Fedora) to answer all installer questions.
3.  **Provision:** Runs `scripts/setup.sh` to install updates, K3s prerequisites, and the QEMU Guest Agent.
4.  **Template:** Shuts down the VM and converts it to a Proxmox Template.

## 🔐 Secret Management with Bitwarden

This setup uses **Bitwarden Secrets Manager** to inject SSH public keys at build time, avoiding hardcoded secrets in the repository.

### Prerequisites

#### 1. Install Bitwarden Secrets CLI

**Arch Linux:**
```bash
yay -S bws-bin
# OR
paru -S bws-bin
```

**Other Linux:**
```bash
cargo install bws
```

**macOS:**
```bash
brew install bitwarden/tap/bws
```

**Verify installation:**
```bash
bws --version
```

#### 2. Store SSH Keys in Bitwarden Secrets Manager

1. Log in to your Bitwarden Secrets Manager
2. Create a new project (or use existing)
3. Create **one secret** named `PACKER_SSH_KEYS`
4. Set the value to your SSH public keys, **one per line**:
   ```
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICuRNLs... desktop
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK7zi2/... laptop
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOKnc8+... dev-vm
   ```
5. Note your **Secret ID** (UUID format)

#### 3. Create Machine Account

1. In Bitwarden Secrets Manager, go to **Machine Accounts**
2. Create a new machine account (e.g., `packer-builder`)
3. Grant it access to the project containing your SSH keys
4. Copy the **Access Token**

#### 4. Export Secret ID

```bash
export BWS_SSH_KEYS_ID="uuid-for-ssh-keys-secret"

# Add to shell profile for persistence
echo 'export BWS_SSH_KEYS_ID="..."' >> ~/.bashrc  # or ~/.zshrc
```

#### 5. Set Access Token

```bash
export BW_ACCESS_TOKEN="your-bitwarden-access-token"

# Add to shell profile for persistence
echo 'export BW_ACCESS_TOKEN="..."' >> ~/.bashrc  # or ~/.zshrc
```

#### 6. Make Scripts Executable

```bash
chmod +x packer/scripts/*.sh
```

### How It Works

1. **Run build.sh** → Wrapper script starts to process
2. **Generate config** → `generate-autoinstall.sh` detects format (cloud-init vs kickstart)
3. **Fetch secrets** → `fetch-ssh-keys.sh` retrieves keys from Bitwarden using `bws` CLI
4. **Format keys** → Script formats keys for the target system (Ubuntu YAML or Fedora Kickstart)
5. **Inject keys** → Keys replace `{{SSH_KEYS}}` placeholder in template
6. **Packer starts** → Autoinstall config is ready, Packer builds the VM
7. **Packer connects** → Uses SSH keys to connect and run `scripts/setup.sh`
8. **Template created** → VM shuts down and becomes a template
9. **Terraform clones** → Clones template, injects **new** SSH keys via cloud-init
10. **SSH keys replaced** → Cloud-init overrides the build-time keys with runtime keys

**Important:** SSH keys are used in two stages:
- **Build-time:** Bitwarden keys for Packer to connect during template creation
- **Runtime:** Terraform cloud-injects admin keys when cloning VMs (overrides build-time keys)

## 📋 VM ID Scheme

Templates use a consistent ID scheme across all Proxmox nodes:

**Formula**: `<distro_base> + <node_number>`

| Distro | Base ID | pve1 | pve2 | pve3 |
|--------|---------|------|------|------|
| Ubuntu 24.04 | 9000 | 9001 | 9002 | 9003 |
| Fedora 43 Server | 9020 | 9021 | 9022 | 9023 |

**To add more nodes**: Edit the `.pkr.hcl` file's `locals` block and add the VM ID, then add a corresponding source block.

**Example** (adding pve3 to Fedora):
```hcl
locals {
  pve2_vm_id = 9022
  pve3_vm_id = 9023  # Add this
}

# Add this source block
source "proxmox-iso" "fedora-base-pve3" {
  node  = "pve3"
  vm_id = local.pve3_vm_id
  # ... rest of config same as pve2
}

# Update build sources
build {
  sources = [
    "source.proxmox-iso.fedora-base-pve2",
    "source.proxmox-iso.fedora-base-pve3"  # Add this
  ]
}
```

## 🚀 Usage

### 1. Configure Secrets

#### Proxmox API Credentials

Create `variables.auto.pkrvars.hcl` in each template directory (git-ignored):

```hcl
proxmox_api_url = "https://192.168.1.10:8006/api2/json"
proxmox_api_token_id = "packer@pam!packer"
proxmox_api_token_secret = "your-secret-token"
```

Or use environment variables:
```bash
export PKR_VAR_proxmox_api_url="https://192.168.1.10:8006/api2/json"
export PKR_VAR_proxmox_api_token_id="packer@pam!packer"
export PKR_VAR_proxmox_api_token_secret="your-secret-token"
```

#### Bitwarden Secrets

See **🔐 Secret Management with Bitwarden** section above.

### 2. Build Templates

**Ubuntu 24.04** (builds on pve1 and pve2):
```bash
cd packer/ubuntu-24.04-base
packer init .    # First time only
./build.sh       # Generates user-data and runs packer build
```

**Fedora 43 Server** (builds on pve2 only):
```bash
cd packer/fedora-43-server
packer init .    # First time only
./build.sh       # Generates ks.cfg and runs packer build
```

**Note**: Always use `./build.sh` instead of `packer build .` directly. The build script generates the autoinstall config with your SSH keys from Bitwarden before starting the Packer build.

### 3. Verify Templates

After successful build, check Proxmox:

```bash
# List templates on pve1
ssh root@pve1 "qm list | grep 900"

# List templates on pve2
ssh root@pve2 "qm list | grep 900"
```

You should see:
- pve1: VM 9001 (ubuntu-24.04-base)
- pve2: VM 9002 (ubuntu-24.04-base), VM 9022 (fedora-43-server)

## 🔧 Customization

### Changing SSH Keys

Edit the `PACKER_SSH_KEYS` secret in Bitwarden Secrets Manager. Changes will be applied on the next build.

### Changing the User

**Ubuntu**: Edit `http/user-data.template` and look for the `identity` section.
**Fedora**: Edit `http/ks.cfg.template` and look for the `user` directive.

### Installing More Packages

Packages are installed in the autoinstall phase (cloud-init for Ubuntu, Kickstart for Fedora). Edit the autoinstall config files instead of setup.sh:

**Ubuntu:** Edit `http/user-data.template`:
```yaml
  packages:
    - openssh-server
    - qemu-guest-agent
    - your-new-package-here
```

**Fedora:** Edit `http/ks.cfg.template`:
```
%packages
@core
@standard
openssh-server
qemu-guest-agent
your-new-package-here
%end
```

**Note:** Use `scripts/setup.sh` only for configuration tasks (K3s prerequisites, sysctl, template cleanup), not package installation. This avoids redundancy and keeps the build process efficient.

## ⚠️ Troubleshooting

### Build hangs at "Waiting for SSH to become available"
- **Cause:** The VM didn't get an IP address or the SSH service didn't start.
- **Debug:** Open the Proxmox Console for the temporary VM (usually ID > 100) and watch the boot process.
- **Fix:** Check `http/user-data` syntax. Check if your DHCP server is working.

### "Error uploading ISO"
- **Cause:** Proxmox storage issue or wrong path.
- **Fix:** Verify `iso_file` variable matches the actual path in Proxmox (e.g., `local:iso/ubuntu-24.04...`).

### "Authentication failed"
- **Cause:** API Token is wrong or lacks permissions.
- **Fix:** Ensure the token has `PVEVMAdmin`, `DatastoreAdmin`, and `Sys.Console` permissions.
