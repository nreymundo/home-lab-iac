# Technology Stack

## Infrastructure & Provisioning
- **Hypervisor:** Proxmox VE
- **Provisioning (IaC):** Terraform (Proxmox Provider)
- **Image Building:** Packer (Ubuntu 24.04, Fedora)
- **Configuration Management:** Ansible
- **Operating Systems:** Ubuntu 24.04 (Server VMs & Raspberry Pi), Fedora (Workstation/Server)

## Kubernetes & GitOps
- **Kubernetes Distribution:** k3s
- **GitOps Engine:** Flux CD
- **Ingress Controller:** Traefik
- **Load Balancer:** MetalLB
- **Certificate Management:** Cert-manager

## Security & Identity
- **Identity & Access Management (IAM):** Authentik
- **Secrets Management:** Bitwarden (Secrets Manager Operator), `kube-replicator`
- **Intrusion Prevention:** Crowdsec
- **Secure Access:** Cloudflare Tunnels, VPN Gateway

## Storage
- **Distributed Storage:** Longhorn
- **Local Storage:** ZFS
- **Network Storage:** NFS (Upcoming integration)

## Observability
- **Monitoring:** Prometheus (via Kube-Prometheus-Stack)
- **Visualization:** Grafana
- **Logging:** Loki
- **Telemetry Collection:** Alloy
