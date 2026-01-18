# Architecture Overview

This document provides a high-level overview of the home lab infrastructure architecture.

## Infrastructure Pipeline

The infrastructure is built in layers, each depending on the previous:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           INFRASTRUCTURE FLOW                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────┐      ┌───────────┐      ┌─────────┐      ┌──────────────┐    │
│   │ PACKER  │─────▶│ TERRAFORM │─────▶│ ANSIBLE │─────▶│  KUBERNETES  │    │
│   └─────────┘      └───────────┘      └─────────┘      └──────────────┘    │
│        │                 │                 │                   │            │
│   Build VM         Create VMs        Configure &          GitOps           │
│   templates        from templates    deploy K3s           via Flux         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Layer Details

| Layer | Purpose | Artifacts |
|-------|---------|-----------|
| **Packer** | Creates base VM templates with OS, packages, and cloud-init | VM templates on each Proxmox node |
| **Terraform** | Clones templates to create K3s node VMs | VMs + Ansible inventory file |
| **Ansible** | Configures VMs and bootstraps K3s cluster | Running K3s cluster |
| **Kubernetes** | Deploys applications via Flux GitOps | Running workloads |

---

## Network Architecture

### VLAN Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                        NETWORK TOPOLOGY                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   VLAN 1 (Default)           VLAN 10 (K3s)                      │
│   ├── Proxmox hosts          ├── K3s nodes                      │
│   ├── Management             ├── 192.168.10.0/24                │
│   └── Other services         └── Gateway: 192.168.10.1          │
│                                                                  │
│   K3s Node IPs: 192.168.10.50+                                  │
│   MetalLB Pool: 192.168.10.200-192.168.10.250                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### DNS & Ingress

- **External DNS**: Managed via external-dns to Cloudflare
- **Internal DNS**: Pi-hole for local resolution
- **Ingress Controller**: Traefik with automatic TLS via cert-manager

---

## Kubernetes Cluster Architecture

### Cluster Components

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         K3S CLUSTER                                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                        INFRASTRUCTURE                                │ │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │ │
│  │   │ MetalLB  │  │ Traefik  │  │Cert-Mgr  │  │  External-DNS    │   │ │
│  │   └──────────┘  └──────────┘  └──────────┘  └──────────────────┘   │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                         SECURITY                                     │ │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │ │
│  │   │Authentik │  │ Crowdsec │  │ Bitwarden│  │  Kube-Replicator │   │ │
│  │   └──────────┘  └──────────┘  └──────────┘  └──────────────────┘   │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                          STORAGE                                     │ │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐                          │ │
│  │   │ Longhorn │  │   CNPG   │  │   NFS    │                          │ │
│  │   │ (block)  │  │(Postgres)│  │ (media)  │                          │ │
│  │   └──────────┘  └──────────┘  └──────────┘                          │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                       OBSERVABILITY                                  │ │
│  │   ┌──────────────────────┐  ┌──────────┐  ┌──────────┐             │ │
│  │   │ Prometheus + Grafana │  │   Loki   │  │  Alloy   │             │ │
│  │   └──────────────────────┘  └──────────┘  └──────────┘             │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### Node Distribution

Nodes are distributed across Proxmox hosts for high availability:

| Node | Proxmox Host | Role | Zone Label |
|------|--------------|------|------------|
| k3s-node-01 | pve1 | General | `topology.kubernetes.io/zone=pve1` |
| k3s-node-02 | pve2 | General | `topology.kubernetes.io/zone=pve2` |
| k3s-node-03 | pve1 | Storage | `topology.kubernetes.io/zone=pve1` |

### Storage Strategy

| Storage Class | Backend | Replicas | Use Case |
|--------------|---------|----------|----------|
| `longhorn-r2` | Longhorn | 2 | Critical application data |
| `longhorn-r1` | Longhorn | 1 | Non-critical, ephemeral data |
| NFS PVCs | External NAS | N/A | Large media files |

---

## GitOps Workflow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           GITOPS FLOW                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────────┐ │
│   │  GitHub  │◀───│ Renovate │    │   Flux   │───▶│  K3s Cluster     │ │
│   │   Repo   │    │   Bot    │    │          │    │                  │ │
│   └────┬─────┘    └──────────┘    └────▲─────┘    └──────────────────┘ │
│        │                               │                                │
│        │         ┌─────────────────────┘                                │
│        │         │ Watches master branch                                │
│        ▼         │                                                      │
│   kubernetes/clusters/production/                                       │
│   ├── flux-system/           ◀── Bootstrap (DO NOT EDIT)              │
│   └── ks/                    ◀── Kustomization definitions             │
│       ├── 00-infrastructure.yaml                                       │
│       ├── 10-metallb-install.yaml                                      │
│       ├── ...                                                          │
│       └── 90-apps.yaml                                                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Secrets Management

All components use **Bitwarden Secrets Manager** for sensitive data:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      SECRETS FLOW                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Bitwarden Secrets Manager                                             │
│           │                                                              │
│           ├──▶ Packer (SSH keys during build)                           │
│           │                                                              │
│           ├──▶ Terraform (SSH keys for cloud-init)                      │
│           │                                                              │
│           └──▶ Kubernetes (Bitwarden Secrets Operator)                  │
│                     │                                                    │
│                     └──▶ kube-replicator (cross-namespace secrets)      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

See [SECRETS_MANAGEMENT.md](SECRETS_MANAGEMENT.md) for detailed setup instructions.
