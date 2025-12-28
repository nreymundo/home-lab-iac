# Packer Templates

Packer builds the "Golden Image" for our VMs.

## Why use Packer?
- **Speed:** Cloning a template takes seconds. Installing Ubuntu from ISO takes minutes.
- **Consistency:** Every VM starts with the exact same packages and config.
- **Automation:** No manual clicking through the Ubuntu installer.

## 🏗️ The Build Process

1.  **Boot:** Starts a VM on Proxmox using the Ubuntu 24.04 ISO.
2.  **Autoinstall:** Uses the `http/user-data` file to answer all installer questions (language, disk layout, user creation).
3.  **Provision:** Runs `scripts/setup.sh` to install updates and the QEMU Guest Agent.
4.  **Template:** Shuts down the VM and converts it to a Proxmox Template.

## 🚀 Usage

### 1. Configure Secrets
Create `variables.auto.pkrvars.hcl` (git-ignored):
```hcl
proxmox_api_url = "https://192.168.1.10:8006/api2/json"
proxmox_api_token_id = "packer@pam!packer"
proxmox_api_token_secret = "your-secret-token"
```

### 2. Build
```bash
packer init .
packer validate .
packer build .
```

## 🔧 Customization

### Changing the User
Edit `http/user-data`. Look for the `users` section. You can change the default username (`ubuntu`) and the SSH key.

### Installing More Packages
Edit `scripts/setup.sh`. Add any `apt install` commands there.

**Example:**
```bash
# scripts/setup.sh
apt-get update
apt-get install -y qemu-guest-agent curl wget vim htop
```

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
