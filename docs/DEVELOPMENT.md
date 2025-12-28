# Development Guide

So you want to contribute? Or (more likely) I forgot how to set up my own laptop.

## 🛠️ Environment Setup

### 1. Install Dependencies
You need these tools to work on this repo.

- **Python 3:** For Ansible and pre-commit.
- **Packer:** For building images.
- **Terraform:** For infrastructure.
- **kubectl & helm:** For Kubernetes.
- **flux:** For GitOps.
- **age:** For secret encryption (optional/future).

### 2. Install Pre-commit Hooks
This is **mandatory**. It prevents me from committing broken YAML or errors.

```bash
pip install pre-commit
pre-commit install
```

Now, every time you run `git commit`, it will check:
- YAML syntax
- Trailing whitespace
- End of file fixers
- Ansible Lint
- Terraform Fmt

### 3. VS Code Recommendations
Extensions that make life easier:
- **HashiCorp Terraform**
- **Ansible**
- **Kubernetes**
- **YAML**
- **Prettier**

## 🧪 Testing Changes

### Ansible
Always run with `--check` first (Dry Run).

```bash
cd ansible
ansible-playbook -i inventories/baremetal.yml playbooks/rpi.yml --check
```

### Terraform
Always run `plan` before `apply`.

```bash
cd terraform/k3s_nodes
terraform plan
```

### Kubernetes
To validate manifests without applying them:
```bash
kubectl apply -f my-manifest.yaml --dry-run=client
```

## 📦 Adding a New Application

1.  **Create Manifests:**
    - Create a folder in `kubernetes/clusters/homelab/apps/<app-name>`.
    - Add `helmrelease.yaml` or standard k8s manifests.
2.  **Add to Kustomization:**
    - Edit `kubernetes/clusters/homelab/apps/kustomization.yaml` to include the new folder.
3.  **Commit:**
    - `git add .`
    - `git commit -m "Add <app-name>"`
    - `git push`
4.  **Sync:**
    - Watch Flux pick it up.

## 🔄 Updating Dependencies

- **Ansible Galaxy:** `ansible-galaxy install -r requirements.yml`
- **Helm Charts:** Update the `version` field in `HelmRelease` files.
- **K3s:** Update the version in Ansible vars.
