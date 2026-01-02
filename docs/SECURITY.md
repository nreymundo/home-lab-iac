# Security Model

## Disclaimer
This is a homelab on a private LAN. Security is "good enough" not "perfect." If you're deploying this in production... don't.

## Threat Model

### What I'm Protecting Against ✅
- **Drive-by attacks:** Bots scanning the internet for open ports (since I don't forward ports, this is low risk).
- **Accidental exposure:** Making an internal service public by mistake.
- **Credential theft:** Storing API keys in plain text in Git.
- **Convenience hacks:** Using "admin/admin" everywhere.

### What I'm NOT Protecting Against ❌
- **Sophisticated nation-state actors:** If the NSA wants my Plex history, they can have it.
- **Physical access:** If you can touch the server, I have bigger issues.
- **Zero-day exploits:** I rely on updates, but I'm not auditing kernel code.
- **Insider threats:** It's me. I'm the insider and most likely also the bigger threat.

## Security Layers

### Layer 1: Network Security
**LAN Isolation**
- All services are LAN-only by default.
- **Traefik Middleware:** `lan-allowlist` explicitly blocks non-private IPs.
- **No Port Forwarding:** I do not forward ports 80/443 from my router to the cluster. Access is via VPN (Wireguard) if I'm away.

**VLAN Segmentation**
- **Main (VLAN 1):** Trusted devices.
- **Internal/K3s (VLAN 10):** Isolated cluster traffic.
- **Firewall Rules:** (Planned) Restrict VLAN 10 from accessing VLAN 1 except for specific ports (DNS).

### Layer 2: Authentication (SSO)
**Authentik** is the gatekeeper.
- **Protocol:** OIDC / OAuth2.
- **Forward Auth:** Traefik checks with Authentik before letting a request through.
- **MFA:** Enforce 2FA for admin panels.

### Layer 3: Secrets Management
**Bitwarden Secrets Manager**
I use Bitwarden for both Terraform provisioning and Kubernetes workloads.

**Provisioning (Terraform):**
- **SSH Public Keys:** Retrieved from Bitwarden Secrets Manager during VM provisioning
- **Workflow:** Terraform provider fetches keys at `apply` time and injects them into cloud-init

**Runtime (Kubernetes):**
- **Operator:** Bitwarden Operator injects secrets into pods
- **Workflow:**
    1. **Bitwarden UI:** I create a secret (e.g., `CLOUDFLARE_API_TOKEN`)
    2. **Git:** I commit a `BitwardenSecret` CRD that references the ID (UUID), not the value
    3. **Cluster:** The operator fetches the value and creates a native Kubernetes `Secret`
    4. **App:** Mounts the secret as an env var or file

**Rule:** No actual secrets (passwords, keys, tokens) in Git. Only UUIDs and Public Keys.

### Layer 4: Infrastructure Security
**SSH Access**
- **Keys Only:** Password authentication is disabled.
- **Root Login:** Disabled (except on Proxmox console).
- **Provisioning:** SSH public keys retrieved from Bitwarden Secrets Manager during VM creation (Terraform)
- **Runtime:** Public keys are stored in Ansible vars for ongoing access (this is safe).

**Patch Management**
- **RPi/VMs:** `unattended-upgrades` is enabled for security patches.
- **Proxmox:** Manual updates (too risky to auto-update the hypervisor).
- **Images:** I try to use specific tags (e.g., `v1.2.3`) instead of `latest` to avoid supply chain surprises, but I'm not perfect at this.

## Sensitive Data Handling

### What IS in Git (Intentionally)
- **SSH Public Keys:** `ssh-ed25519 AAA...` (Safe)
- **Internal IPs:** `192.168.x.x` (Useless outside my LAN)

### What is NEVER in Git
- **Passwords:** DB passwords, admin passwords.
- **API Tokens:** Cloudflare, Proxmox, Discord, etc.
- **SSH Private Keys:** Never, ever.
- **Kubeconfig:** Generated on the fly, never committed.
- **Bitwarden IDs:** `b4d3-....` (I could commit them but I don't)
- **Domain Name:** We're using variable substitution for TLD and only commit subdomains.

## Incident Response Plan

**If I suspect a breach:**
1.  **Disconnect:** Pull the ethernet cable / shut down the router interface.
2.  **Rotate:**
    - Rotate Bitwarden Access Token (kills operator access).
    - Rotate Cloudflare Tokens.
    - Rotate SSH keys.
3.  **Wipe:**
    - The beauty of IaC: I can reinstall the OS and re-run Ansible/Terraform/Flux in < 1 hour.
    - If in doubt, nuke it from orbit.

## Security Checklist (Mental Model)
Before deploying a new app, I ask:
1.  Is it exposed to the internet? (Answer should be NO).
2.  Does it have a login? (If NO, put it behind Authentik).
3.  Does it need secrets? (Put them in Bitwarden, not YAML).
4.  Is the image trusted? (Official images only).
