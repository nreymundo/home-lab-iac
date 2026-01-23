# Security

Security practices and policies for the home-lab-iac repository.

## Secrets Management

All sensitive data is managed through **Bitwarden Secrets Manager**:

- **Never commit secrets** to the repository
- Use environment variables for local development
- Secrets are injected at runtime via Bitwarden integrations

See [docs/SECRETS_MANAGEMENT.md](docs/SECRETS_MANAGEMENT.md) for detailed setup.

### Secrets by Component

| Component | Method |
|-----------|--------|
| Packer | `bws` CLI via `generate-autoinstall.sh` |
| Terraform | `bitwarden-secrets` provider |
| Kubernetes | SOPS (encrypted secrets in Git) |

---

## Network Security

### Cluster Network

- K3s nodes are isolated on VLAN 10
- Internal services use `.lan.${CLUSTER_DOMAIN}` domain
- External access is routed through Traefik with TLS

### Ingress Security

- **TLS termination**: All external traffic uses HTTPS via cert-manager
- **Authentication**: Protected routes use Authentik middleware
- **Rate limiting**: Crowdsec integration for threat detection

### Firewall Considerations

Required ports between nodes:
- `6443/tcp` - Kubernetes API
- `10250/tcp` - Kubelet
- `2379-2380/tcp` - etcd (if HA)
- `8472/udp` - Flannel VXLAN

---

## Access Control

### Proxmox API Tokens

- Use separate API tokens for each tool (Packer, Terraform)
- Tokens should have minimal required permissions
- Rotate tokens periodically

### Kubernetes RBAC

- Flux operates with cluster-admin privileges
- Application workloads should use least-privilege ServiceAccounts
- Use NetworkPolicies to restrict pod-to-pod communication where appropriate

---

## Sensitive Files

The following files contain or generate sensitive data and are gitignored:

| File/Pattern | Purpose |
|--------------|---------|
| `*.tfstate*` | Terraform state (contains resource details) |
| `http/user-data` | Generated autoinstall with SSH keys |
| `.env` | Local environment variables |
| `*.pem`, `*.key` | Any private keys |

---

## Reporting Security Issues

If you discover a security vulnerability:

1. **Do not** open a public issue
2. Contact the repository owner directly
3. Provide details about the vulnerability
4. Allow reasonable time for a fix before disclosure

---

## Security Best Practices

### For Development

1. Keep tools updated (`packer`, `terraform`, `ansible`, etc.)
2. Run `pre-commit` hooks before committing
3. Review Renovate PRs for dependency updates
4. Use SSH keys with passphrases

### For Operations

1. Regularly update VM templates with security patches
2. Monitor Crowdsec alerts for threat activity
3. Review Authentik logs for authentication issues
4. Keep cluster components updated via Flux/Renovate

### For Secrets

1. Rotate Bitwarden access tokens periodically
2. Use separate machine accounts for different environments
3. Audit secret access via Bitwarden logs
4. Never store secrets in plain text or commit to Git
