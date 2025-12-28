# Getting Started - Zero to Cluster

## Who This Guide Is For
- You have basic Linux knowledge (CLI, SSH, etc.)
- You're okay with things breaking (it's a homelab!)
- You want a GitOps-managed K3s cluster on Proxmox

## Prerequisites Checklist

### Hardware
- [ ] At least one **Proxmox VE** host (I use 2 nodes + qdevice - Soon to be 3 nodes)
- [ ] Network access to all hosts (LAN)

### Software - Local Machine
- [ ] Linux or WSL2 (Windows Subsystem for Linux)
- [ ] **Python 3.x** + `pip`
- [ ] **Packer** >= 1.10
- [ ] **Terraform** >= 1.0
- [ ] **Git**
- [ ] **SSH client**
- [ ] **kubectl**
- [ ] **Flux CLI**

### Accounts & Services
- [ ] **Cloudflare account** (for DNS + SSL challenges)
- [ ] **Bitwarden account** (for secrets management)
- [ ] **GitHub account** (for Flux GitOps source)

### Network Requirements
- [ ] Static IPs or DHCP reservations for Proxmox hosts
- [ ] VLAN capable switch/router (optional but recommended for VLAN 10)
- [ ] SSH access to all hosts (keys preferred)

---

## Phase 1: Environment Setup

### 1.1 Clone Repository
```bash
git clone https://github.com/nreymundo/home-lab-iac.git
cd home-lab-iac
```

### 1.2 Install Dependencies
Install the required Python tools for Ansible and linting.
```bash
pip install ansible ansible-lint yamllint
```

### 1.3 Configure Pre-commit Hooks
This ensures you don't commit broken YAML or secrets.
```bash
pre-commit install
```

### 1.4 Generate SSH Keys (if needed)
If you don't have an SSH key, generate one. This will be used to access the VMs.
```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```
*Note: You'll need to update `ansible/inventories/group_vars/all.yml` with your public key later.*

---

## Phase 2: Proxmox Preparation

### 2.1 Upload Ubuntu ISO
1. Download [Ubuntu Server 24.04 LTS ISO](https://ubuntu.com/download/server).
2. Upload it to your Proxmox storage (usually `local` -> ISO Images).

### 2.2 Create API Token
Packer and Terraform need API access.
1. Proxmox GUI -> Datacenter -> Permissions -> API Tokens.
2. Create a token for your user (e.g., `packer@pam!packer`).
3. **SAVE THE SECRET**. You won't see it again.
4. Give the user/token `Administrator` privileges (or fine-grained permissions if you prefer).

### 2.3 Configure Network (VLAN 10)
Ensure your Proxmox bridge (`vmbr0`) is VLAN-aware, or set up a dedicated bridge for the VM network. This setup assumes VMs live on VLAN 10 (`192.168.10.0/24`).

---

## Phase 3: Build Base Template (Packer)

This creates a "Golden Image" Ubuntu template that Terraform will clone.

### 3.1 Configure Packer Variables
Create a secrets file (this is git-ignored):
```bash
cd packer/ubuntu-24.04-base
cp variables.auto.pkrvars.hcl.example variables.auto.pkrvars.hcl
nano variables.auto.pkrvars.hcl
```
Fill in your Proxmox URL, username, token, and ISO location.

### 3.2 Run Packer Build
```bash
packer init .
packer validate .
packer build .
```
*This will take 5-10 minutes. It boots a VM, installs Ubuntu via autoinstall, configures cloud-init, and converts it to a template.*

### 3.3 Verify Template
Check Proxmox GUI. You should see a template (e.g., ID 9000) named `ubuntu-24.04-base`.

---

## Phase 4: Provision VMs (Terraform)

Now we spawn the K3s nodes from that template.

### 4.1 Set Environment Variables
Export your credentials (or use a `terraform.tfvars` file, but env vars are safer for temporary sessions).
```bash
export PM_API_URL="https://192.168.1.10:8006/api2/json"
export PM_API_TOKEN_ID="packer@pam!packer"
export PM_API_TOKEN_SECRET="your-secret-token"
```

### 4.2 Plan and Apply
```bash
cd ../../terraform/k3s_nodes
terraform init
terraform plan
terraform apply
```
*Type `yes` when prompted.*

### 4.3 Verify VMs
- Terraform should finish successfully.
- VMs should be running in Proxmox.
- Terraform automatically updates `ansible/inventories/k3s-nodes.yml` with the new IPs.

---

## Phase 5: Configure Hosts (Ansible)

Time to configure the OS on all hosts (Physical + Virtual).

### 5.1 Update Inventory Files
Edit `ansible/inventories/baremetal.yml` to match your physical hosts (RPi, Proxmox IPs).

### 5.2 Test Connectivity
```bash
cd ../../ansible
ansible -i inventories/baremetal.yml -i inventories/k3s-nodes.yml all -m ping
```

### 5.3 Run Playbooks
Run them in order.

**Configure Proxmox Hosts:**
```bash
ansible-playbook -i inventories/baremetal.yml playbooks/proxmox.yml
```

**Configure Raspberry Pi:**
```bash
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml
```

**Configure Ubuntu VMs (K3s Nodes):**
```bash
ansible-playbook -i inventories/all-vms.yml -i inventories/k3s-nodes.yml playbooks/ubuntu_vms.yml
```
*This prepares the VMs, expands disks, installs dependencies.*

---

## Phase 6: Bootstrap Kubernetes (K3s)

### 6.1 Install K3s on Nodes
This role installs K3s binary and configures the cluster.
```bash
ansible-playbook -i inventories/all-vms.yml -i inventories/k3s-nodes.yml playbooks/k3s_cluster.yml
```
*(Note: Ensure you have a playbook that targets the k3s role. If not, you might need to run the role specifically or use the `site.yml` if available. Currently using `playbooks/ubuntu_vms.yml` usually preps, you need to ensure the K3s install happens. Check `ansible/playbooks/` for a K3s specific playbook or create one).*

### 6.2 Get Kubeconfig
Grab the config from the master node:
```bash
scp ubuntu@<MASTER_NODE_IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Edit config to replace 127.0.0.1 with the MASTER_NODE_IP
```

### 6.3 Verify Cluster
```bash
kubectl get nodes
```
*Should see your nodes as `Ready`.*

---

## Phase 7: Setup GitOps (Flux)

Now we hand over control to Flux.

### 7.1 Install Flux CLI
See [Flux Installation](https://fluxcd.io/flux/installation/).

### 7.2 Bootstrap Flux
This installs Flux in the cluster and connects it to your Git repo.
```bash
flux bootstrap github \
  --owner=<YOUR_GITHUB_USER> \
  --repository=home-lab-iac \
  --branch=master \
  --path=./kubernetes/clusters/homelab \
  --personal
```

### 7.3 Configure Secrets
Flux will start failing because it needs secrets (Bitwarden token, Cloudflare token).
Follow the guides in `kubernetes/clusters/homelab/secrets/README.md` to manually create the initial bootstrap secrets.

### 7.4 Wait for Reconciliation
Flux will sync every ~10 minutes. You can force it:
```bash
flux reconcile source git flux-system
flux reconcile kustomization flux-system
```

---

## Phase 8: Verification & First App

### 8.1 Check All Pods Running
```bash
kubectl get pods -A
```
*Eventually, everything in the `infrastructure` folder should be running.*

### 8.2 Access Traefik Dashboard
If you set up the IngressRoute, you should be able to reach `traefik.lan.<YOUR_DOMAIN>`.

### 8.3 Deploy Test App
Try deploying the sample stateless app to verify Ingress and DNS.
```bash
kubectl apply -f kubernetes/samples/stateless_web_app.yaml
```

### 8.4 Verify DNS and SSL
Check if `whoami.lan.<YOUR_DOMAIN>` resolves and has a valid Let's Encrypt certificate.

---

## What's Next?
- Add monitoring dashboards (Grafana)
- Configure Authentik for SSO
- Deploy your first real application
- Set up backups (see [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md))

## Common First-Time Issues
- **VMs won't start:** Check Proxmox logs, often CPU type or memory issues.
- **Can't access cluster:** Check firewall rules, ensure `~/.kube/config` server IP is correct.
- **Flux not syncing:** Check `kubectl get kustomizations -n flux-system` for errors.
- **Certificates not issuing:** Check cert-manager logs and Cloudflare token permissions.
