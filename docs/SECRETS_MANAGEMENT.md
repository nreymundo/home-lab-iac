# Secrets Management

This document explains how secrets are managed across all components using Bitwarden Secrets Manager.

## Overview

All sensitive data is stored in **Bitwarden Secrets Manager** and retrieved at runtime by each component:

| Component | Secrets Used | Retrieval Method |
|-----------|-------------|------------------|
| Packer | SSH public keys | `bws` CLI in `generate-autoinstall.sh` |
| Terraform | SSH public keys | `bitwarden-secrets` provider |
| Kubernetes | App secrets | Bitwarden Secrets Operator |

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

## Kubernetes: Bitwarden Secrets Operator

The cluster uses the **Bitwarden Secrets Operator** to sync secrets from Bitwarden to Kubernetes.

### Installation

The operator is deployed via Flux in `infrastructure/security/bitwarden-secrets-operator/`.

### Creating a BitwardenSecret

```yaml
apiVersion: k8s.bitwarden.com/v1
kind: BitwardenSecret
metadata:
  name: my-app-secrets
  namespace: my-app
spec:
  organizationId: "<org-id>"
  secretName: my-app-secrets  # Name of the K8s Secret to create
  map:
    - secretKeyName: database-password
      bwSecretId: "<bitwarden-secret-uuid>"
    - secretKeyName: api-key
      bwSecretId: "<bitwarden-secret-uuid>"
```

### Using Secrets in Applications

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

### 1. Add to Bitwarden

1. Go to Secrets Manager → relevant project
2. Create new secret with key-value pair
3. Copy the secret UUID

### 2. Reference in Component

**For Kubernetes apps:**
```yaml
# In BitwardenSecret spec.map
- secretKeyName: new-secret-key
  bwSecretId: "<uuid-from-bitwarden>"
```

**For Terraform:**
```hcl
data "bitwarden-secrets_secret" "new_secret" {
  id = "<uuid-from-bitwarden>"
}
```

---

## Security Best Practices

1. **Rotate access tokens** periodically
2. **Use separate machine accounts** for different environments (dev/prod)
3. **Limit project access** - each machine account should only access needed projects
4. **Never commit secrets** - use environment variables or secret managers
5. **Audit access** regularly via Bitwarden's access logs
