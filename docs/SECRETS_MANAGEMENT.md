# Secrets Management

This document explains how secrets are managed across all components.

## Overview

Sensitive data is stored in either Bitwarden Secrets Manager (infrastructure) or encrypted in Git with SOPS (Kubernetes):

| Component | Secrets Used | Retrieval Method |
|-----------|-------------|------------------|
| Packer | SSH public keys | `bws` CLI in `generate-autoinstall.sh` |
| Terraform | SSH public keys | `bitwarden-secrets` provider |
| Kubernetes | App secrets | SOPS (AGE-encrypted) |

---

## Bitwarden Secrets Manager Setup

### 1. Create a Machine Account

1. Log into Bitwarden and navigate to **Secrets Manager**
2. Go to **Machine Accounts** → **New Machine Account**
3. Name it (e.g., `home-lab-iac`)
4. Generate an **Access Token** and save it securely

### 2. Configure Access Token

```bash
# Add to your shell profile or .env file
export BWS_ACCESS_TOKEN="<your-access-token>"
```

### 3. Create Projects and Secrets

Organize secrets into projects:

| Project | Purpose | Example Secrets |
|---------|---------|-----------------|
| `home-lab` | Infrastructure | SSH keys, API tokens |
| `kubernetes` | K8s app secrets | Database passwords, API keys |

---

## Packer: SSH Key Injection

Packer uses SSH keys during VM template creation.

### How It Works

1. `build.sh` runs `generate-autoinstall.sh`
2. Script retrieves SSH public keys from Bitwarden using `bws`
3. Keys are injected into `http/user-data` template
4. Packer builds the VM with authorized keys pre-configured

### Required Secrets

| Secret Name | Description |
|-------------|-------------|
| `ssh-public-key` | Public key for VM access |

### Usage

```bash
cd packer/ubuntu-24.04-base
./build.sh  # Automatically injects SSH keys
```

---

## Terraform: SSH Keys for Cloud-Init

Terraform retrieves SSH keys to inject into VMs via cloud-init.

### Provider Configuration

```hcl
terraform {
  required_providers {
    bitwarden-secrets = {
      source  = "bitwarden/bitwarden-secrets"
      version = "0.5.4-pre"
    }
  }
}

provider "bitwarden-secrets" {}
```

### Retrieving Secrets

```hcl
data "bitwarden-secrets_secret" "ssh_public_key" {
  id = "<secret-uuid>"
}

# Use in cloud-init
resource "proxmox_vm_qemu" "node" {
  # ...
  ciuser     = "ubuntu"
  sshkeys    = data.bitwarden-secrets_secret.ssh_public_key.value
}
```

---

## Kubernetes: SOPS

The cluster uses **SOPS** (Secrets OPerationS) to manage encrypted secrets in Git.

### How It Works

1. Secrets are stored as `.sops.yaml` files in repository
2. SOPS encrypts the `data` and `stringData` fields using AGE encryption
3. Flux applies the encrypted secrets to the cluster
4. The Flux SOPS controller decrypts secrets at runtime using the cluster AGE key

### Encryption Configuration

SOPS is configured via `.sops.yaml` at the repository root:

```yaml
creation_rules:
  - path_regex: .*\.sops\.ya?ml$
    encrypted_regex: '^(data|stringData)$'
    age: age189vx0wdx4q2hjdzqm3j5yxjjupfun5y3a7ajj40t3cl6lttmz9wsv36vck
```

### Creating an Encrypted Secret

1. **Create a secret manifest** with the `.sops.yaml` extension:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secrets
  namespace: my-app
type: Opaque
stringData:
  DATABASE_URL: "postgresql://user:password@db:5432/mydb"
  API_KEY: "super-secret-api-key"
```

2. **Encrypt with SOPS**:

```bash
sops --encrypt secret.yaml > secret.sops.yaml
```

3. **Commit the encrypted file** to Git (the plaintext remains in the untracked `secret.yaml`)

4. **Add to your application**:

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: app
          envFrom:
            - secretRef:
                name: my-app-secrets
```

### Adding SOPS Decryption to Flux

Ensure Flux SOPS integration is enabled in your cluster to automatically decrypt secrets at runtime.

### Cross-Namespace Replication

For secrets needed in multiple namespaces, use **kube-replicator** with annotations:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: shared-credentials
  namespace: flux-system
  annotations:
    replicator.v1.mittwald.de/replicate-to: "namespace-1,namespace-2"
```

---

## Cross-Namespace Secret Replication

Some secrets need to be available in multiple namespaces. Use **kube-replicator** for this:

### Annotate Source Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: shared-credentials
  namespace: flux-system
  annotations:
    replicator.v1.mittwald.de/replicate-to: "namespace-1,namespace-2"
```

### Or Replicate From Another Namespace

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: shared-credentials
  namespace: my-app
  annotations:
    replicator.v1.mittwald.de/replicate-from: flux-system/shared-credentials
```

---

## Adding New Secrets

### For Kubernetes Apps

1. Create a `*.sops.yaml` secret file in the appropriate directory
2. Encrypt it with `sops --encrypt`
3. The secret will be applied to the cluster by Flux and decrypted automatically

### For Terraform

1. Add to Bitwarden: Go to Secrets Manager → relevant project
2. Create new secret with key-value pair
3. Copy the secret UUID
4. Reference in your Terraform configuration:

```hcl
data "bitwarden-secrets_secret" "new_secret" {
  id = "<uuid-from-bitwarden>"
}
```

---

## Security Best Practices

1. **Rotate access tokens** periodically
1. **Use separate machine accounts** for different environments (dev/prod)
1. **Limit project access** - each machine account should only access needed projects
1. **Never commit secrets** - use environment variables or secret managers
1. **Keep AGE keys secure** - rotate encryption keys periodically (Kubernetes)
