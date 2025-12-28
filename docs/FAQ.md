# Frequently Asked Questions

## General

### Why not just use Docker Compose?
I was using Docker Compose on multiple VMs. It was working great but I put everything together over time with no plan... so maintainance ended up being a pain. Also, I wanted to try kubernetes in my own home lab.

### Why Proxmox + VMs instead of bare metal K3s?
- **Snapshots:** I can snapshot a VM before breaking it.
- **Migration:** I can move VMs between nodes (even with local storage, if using offline migration).
- **Isolation:** I can run other things alongside K3s if I want.
- **Terraform:** I can destroy and recreate the entire cluster infrastructure with one command.

## Technical

### Why Traefik? Why not Nginx?
Traefik feels more "cloud native" with its dynamic configuration and CRDs. Also, the Middleware system makes adding Authelia/Authentik/Lan-whitelists super easy.

### I broke the cluster. How do I start over?
See [**Disaster Recovery**](DISASTER_RECOVERY.md). The short version:
`terraform destroy && terraform apply`.

### Can I access this from the internet?
**NO.** Not by default. The Ingresses use a LAN Allowlist middleware. If you want external access, you need to explicitly remove that middleware or set up a VPN (I use Wireguard).
