# Terraform Infrastructure

Terraform manages the lifecycle of the K3s virtual machines.

## 🏗️ Architecture

- **Provider:** `telmate/proxmox`
- **State:** Local (`terraform.tfstate`)
- **Resource:** `proxmox_vm_qemu`

It does two things:
1.  **Clones VMs:** Creates `k3s-node-01`, `k3s-node-02`... from the Packer template.
2.  **Generates Inventory:** Writes `ansible/inventories/k3s-nodes.yml` with the new IPs.

## 🚀 Usage

### 1. Set Credentials
Use environment variables to avoid committing secrets.
```bash
export PM_API_URL="https://192.168.1.10:8006/api2/json"
export PM_API_TOKEN_ID="terraform@pam!terraform"
export PM_API_TOKEN_SECRET="your-secret-token"
```

### 2. Apply
```bash
terraform init
terraform plan
terraform apply
```

## ⚙️ Scaling the Cluster

To add more nodes, just change the variable!

1.  Edit `variables.tf` (or override via `-var`):
    ```hcl
    variable "node_count" {
      default = 3  # Was 2
    }
    ```
2.  Run `terraform apply`.
3.  Terraform creates `k3s-node-03`.
4.  Run Ansible to configure the new node.

## 🧹 State Management

Since we use **local state**, the `terraform.tfstate` file is the database of your infrastructure.

- **Do NOT delete it.** If you do, Terraform forgets the VMs exist and will try to create duplicates (failing).
- **Backup it.** Ideally, use a remote backend (S3/Consul), but for homelab, just be careful.

### "I deleted the state file, help!"
You have to import the existing VMs back into the state.
```bash
terraform import proxmox_vm_qemu.k3s_nodes[0] <VMID_OF_NODE_01>
terraform import proxmox_vm_qemu.k3s_nodes[1] <VMID_OF_NODE_02>
```

## ⚠️ Known Issues

### "Error: VM already exists"
- **Cause:** Terraform crashed or state is out of sync.
- **Fix:** Manually delete the VM in Proxmox, or fix the state (remove the resource from state if it doesn't exist in Proxmox).

### "Timeout waiting for IP"
- **Cause:** QEMU Guest Agent isn't running in the VM.
- **Fix:** Ensure the Packer template has the agent installed and enabled (`systemctl enable --now qemu-guest-agent`).
