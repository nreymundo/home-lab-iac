# Product Guidelines

## Core Principles

### 1. Unified IaC & GitOps First
- **Definition:** Every infrastructure component (VMs, network config, OS tuning) and application resource (deployments, ingresses, secrets) must be defined in code.
- **Implementation:** Use Terraform for provisioning, Ansible for configuration, and Flux CD for Kubernetes management.
- **Exceptions:** Manual intervention is permitted ONLY when the automation is prohibitively brittle or for initial bootstrapping of secrets (e.g., Bitwarden Service Account tokens).
- **Secret Management:** Manual bootstrapping of Bitwarden secrets is followed by automation using `kube-replicator` to distribute secrets across namespaces based on annotations.

### 2. Zero Trust & Private-First Networking
- **Exposure:** Minimize public-facing attack surfaces. Services should be reached via Cloudflare Tunnels or a VPN Gateway.
- **Authentication:** Authentik is the mandatory gateway for all external access.
- **Local Network Policy:** Bypassing authentication for clients within the local network (LAN) or established VPN sessions is acceptable for convenience, provided the internal perimeter is secured.

### 3. Production-Grade Sandbox
- **Standard:** Maintain high stability and adhere to industry best practices (monitoring, backups, structured logging) to simulate a real production environment.
- **Evolution:** The current environment serves as "production." A dedicated "staging" environment may be introduced in the future to test disruptive changes.

### 4. Observability Integration
- **Goal:** Strive for every service to export Prometheus metrics and have logs captured by the central logging system.
- **Tolerance:** While metrics are the standard, services that do not natively support them can be accepted as long as they are integrated into the central logging system.
- **Visibility:** Dashboards (Grafana) should provide immediate insight into the health of both the infrastructure and the hosted applications where possible.
