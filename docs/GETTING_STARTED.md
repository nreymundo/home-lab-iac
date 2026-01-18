# Getting Started

This guide walks you through setting up the development environment and deploying the infrastructure.

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Packer | 1.9+ | Build VM templates |
| Terraform | 1.5+ | Provision VMs |
| Ansible | 2.15+ | Configure VMs and deploy K3s |
| kubectl | 1.28+ | Kubernetes CLI |
| flux | 2.0+ | GitOps CLI |
| pre-commit | 3.0+ | Git hooks |

### Install on Ubuntu/Debian

```bash
# Packer
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install packer

# Terraform
sudo apt-get install terraform

# Ansible
pip install ansible ansible-lint

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/

# Flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# pre-commit
pip install pre-commit
```

### Required Accounts & Access

1. **Proxmox VE** - API token with VM management permissions
2. **Bitwarden Secrets Manager** - Access token for secrets retrieval
3. **GitHub** - Repository access for Flux GitOps

---

## Environment Setup

### 1. Clone the Repository

```bash
git clone https://github.com/<user>/home-lab-iac.git
cd home-lab-iac
```

### 2. Install Pre-commit Hooks

```bash
pre-commit install
```

### 3. Configure Environment Variables

Create a `.env` file (gitignored) or export directly:

```bash
# Proxmox API (Terraform & Packer)
export PM_API_URL="https://proxmox.lan:8006/api2/json"
export PM_API_TOKEN_ID="terraform@pve!terraform"
export PM_API_TOKEN_SECRET="<your-secret>"

# Packer-specific
export PKR_VAR_proxmox_api_url="$PM_API_URL"
export PKR_VAR_proxmox_api_token_id="packer@pve!packer"
export PKR_VAR_proxmox_api_token_secret="<packer-secret>"

# Bitwarden Secrets Manager
export BWS_ACCESS_TOKEN="<your-bws-token>"
```

### 4. Verify Tool Installation

```bash
packer version
terraform version
ansible --version
kubectl version --client
flux version --client
```

---

## First Deployment Walkthrough

### Step 1: Build VM Templates (Packer)

```bash
cd packer/ubuntu-24.04-base

# Validate the configuration
packer validate .

# Build templates on all Proxmox nodes
./build.sh
```

This creates VM templates on each Proxmox node for fast local cloning.

### Step 2: Provision K3s Nodes (Terraform)

```bash
cd terraform/k3s_nodes

# Initialize providers
terraform init

# Preview changes
terraform plan

# Create VMs (generates Ansible inventory)
terraform apply
```

### Step 3: Configure VMs and Deploy K3s (Ansible)

```bash
cd ansible

# Verify connectivity
ansible all -m ping

# Dry-run to preview changes
ansible-playbook playbooks/k3s_cluster.yml --check

# Deploy K3s cluster
ansible-playbook playbooks/k3s_cluster.yml
```

### Step 4: Verify Kubernetes Cluster

```bash
# Get kubeconfig (created by Ansible)
export KUBECONFIG=~/.kube/config

# Check nodes
kubectl get nodes

# Check Flux status
flux get all -A
```

---

## Day-to-Day Operations

### Adding a New K3s Node

1. Edit `terraform/k3s_nodes/terraform.tfvars`:
   ```hcl
   nodes = [
     {},  # existing nodes
     {},  # new node
   ]
   ```
2. Run `terraform apply`
3. Run `ansible-playbook playbooks/k3s_cluster.yml`

### Deploying a New Application

1. Create directory: `kubernetes/apps/apps/<category>/<app-name>/`
2. Create `helmrelease.yaml` and `kustomization.yaml`
3. Add to parent kustomization
4. Commit and push - Flux handles the rest

### Checking Cluster Health

```bash
# All Flux resources
flux get all -A

# HelmReleases status
flux get helmreleases -A

# Events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

---

## Next Steps

- [ARCHITECTURE.md](ARCHITECTURE.md) - Understand the system design
- [SECRETS_MANAGEMENT.md](SECRETS_MANAGEMENT.md) - Set up secrets
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
