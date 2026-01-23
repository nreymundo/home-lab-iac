# Home Lab IaC - AI Agent Instructions

This document provides an overview of the home-lab-iac repository and pointers to component-specific instructions for AI agents.

## Repository Overview

This repository manages a home lab infrastructure using Infrastructure as Code (IaC) principles:

| Component | Purpose | Documentation |
|-----------|---------|---------------|
| **Packer** | Build VM templates for Proxmox | [packer/AGENTS.md](packer/AGENTS.md) |
| **Terraform** | Provision K3s node VMs on Proxmox | [terraform/AGENTS.md](terraform/AGENTS.md) |
| **Ansible** | Configure VMs and deploy K3s cluster | [ansible/AGENTS.md](ansible/AGENTS.md) |
| **Kubernetes** | GitOps-managed K3s cluster with Flux | [kubernetes/AGENTS.md](kubernetes/AGENTS.md) |

## Workflow Sequence

```
┌─────────┐     ┌───────────┐     ┌─────────┐     ┌────────────┐
│  Packer │────▶│ Terraform │────▶│ Ansible │────▶│ Kubernetes │
└─────────┘     └───────────┘     └─────────┘     └────────────┘
 Build VM        Create VMs       Configure &      GitOps apps
 templates       from templates   deploy K3s       via Flux
```

1. **Packer** creates base VM templates (Ubuntu, Fedora) on each Proxmox node
2. **Terraform** clones templates to create K3s node VMs, generates Ansible inventory
3. **Ansible** configures VMs and bootstraps the K3s cluster
4. **Kubernetes** (Flux) continuously reconciles cluster state from Git

## Quick Reference

### Packer Commands
```bash
cd packer/ubuntu-24.04-base
./build.sh                    # Build template (uses Bitwarden for SSH keys)
packer validate .             # Validate configuration
```

### Terraform Commands
```bash
cd terraform/k3s_nodes
terraform init                # Initialize providers
terraform plan                # Preview changes
terraform apply               # Apply changes
```

### Ansible Commands
```bash
cd ansible
ansible-playbook playbooks/k3s_cluster.yml --check   # Dry run
ansible-playbook playbooks/k3s_cluster.yml           # Full run
```

### Flux/Kubernetes Commands
```bash
flux get all -A                                       # Check all resources
flux reconcile kustomization flux-system --with-source  # Force sync
kubectl get helmreleases -A                           # List HelmReleases
```

## Pre-commit Hooks

The repository uses pre-commit for validation:

```bash
# Install hooks
pre-commit install

# Run all hooks
pre-commit run --all-files

# Run specific hook
pre-commit run ansible-lint --all-files
pre-commit run terraform-fmt --all-files
pre-commit run packer-fmt --all-files
pre-commit run yamllint --all-files
```

## Secrets Management

All components use **Bitwarden Secrets Manager** for sensitive data:

| Component | Usage |
|-----------|-------|
| Packer | SSH public keys injection during build |
| Terraform | SSH public keys for cloud-init |
| Kubernetes | SOPS for app secrets |

Environment variable: `BWS_ACCESS_TOKEN`

## Common Conventions

### Naming
- K3s nodes: `k3s-node-01`, `k3s-node-02`, ...
- VMs start at VMID 200
- Templates at VMID 9000+

### Node Labels
Prefix: `homelab.lan/`
- `role` - Node purpose (general, storage)
- `cpu-vendor` - CPU type (intel, amd)
- `runtime` - VM or baremetal
- `gpu` - GPU type or none

Zone awareness: `topology.kubernetes.io/zone` = Proxmox node name

### Network
- VLAN 10 for K3s nodes
- Gateway: 192.168.10.1
- Node IPs start at 192.168.10.50

### Domains
- Internal: `*.lan.${CLUSTER_DOMAIN}`
- External: `*.${CLUSTER_DOMAIN}`

## Directory Structure

```
home-lab-iac/
├── AGENTS.md                 # This file
├── README.md                 # Human-readable project overview
├── .pre-commit-config.yaml   # Pre-commit hook configuration
├── renovate.json             # Renovate bot configuration
├── ansible/                  # VM configuration & K3s deployment
├── terraform/                # VM provisioning on Proxmox
├── packer/                   # VM template building
├── kubernetes/               # Flux GitOps manifests
└── conductor/                # AI coding guidelines (legacy)
```

## Common Tasks

| Task | Component | See |
|------|-----------|-----|
| Add a new K3s node | Terraform | [terraform/AGENTS.md](terraform/AGENTS.md) |
| Deploy a new app | Kubernetes | [kubernetes/AGENTS.md](kubernetes/AGENTS.md) |
| Add Ansible role | Ansible | [ansible/AGENTS.md](ansible/AGENTS.md) |
| Create new VM template | Packer | [packer/AGENTS.md](packer/AGENTS.md) |
| Update node configuration | Ansible | [ansible/AGENTS.md](ansible/AGENTS.md) |
