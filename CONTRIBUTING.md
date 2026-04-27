# Contributing

Guidelines for contributing to the home-lab-iac repository.

## Development Workflow

### 1. Set Up Environment

```bash
# Clone the repository
git clone https://github.com/<user>/home-lab-iac.git
cd home-lab-iac

# Check required host tools
scripts/bootstrap-host-tools.sh --check

# Install pre-commit hooks
pre-commit install
```

### 2. Make Changes

1. Create a new branch: `git checkout -b feature/my-change`
2. Make your changes
3. Run pre-commit hooks: `pre-commit run --all-files`
4. Test locally when possible

### 3. Commit and Push

```bash
git add .
git commit -m "feat: descriptive commit message"
git push origin feature/my-change
```

### 4. Pull Request Review

- Review requests are automatically handled through `CODEOWNERS`.
- All PRs request review from `@nreymundo` by default.
- If a PR is opened from a bot or machine account, this ensures the main account is still pulled in for review.

---

## Pre-commit Hooks

The repository uses pre-commit to enforce code quality:

| Hook | Purpose |
|------|---------|
| `trailing-whitespace` | Remove trailing whitespace |
| `end-of-file-fixer` | Ensure files end with newline |
| `mixed-line-ending` | Normalize mixed line endings |
| `check-added-large-files` | Block accidentally committed large files |
| `check-yaml` | Validate YAML syntax |
| `yamllint` | Lint YAML files |
| `ansible-lint` | Lint Ansible playbooks and roles |
| `packer-fmt` | Format Packer HCL files |
| `terraform-fmt` | Format Terraform files |
| `forbid-sensitive-files` | Block committing private key material |
| `prevent-plaintext-k8s-secrets` | Block unencrypted Kubernetes Secret manifests |
| `sops-auto-encrypt` | Auto-encrypt `*.sops.yaml` files when needed |
| `forbid-commit-attribution` | Enforce commit subject policy and block forbidden attribution trailers |

### Running Hooks

```bash
# Run all hooks on all files
pre-commit run --all-files

# Run specific hook
pre-commit run ansible-lint --all-files
pre-commit run terraform-fmt --all-files

# Update hooks to latest versions
pre-commit autoupdate
```

The `forbid-commit-attribution` hook runs during `git commit` as a `commit-msg` hook rather than through the normal file-based pre-commit scan.

---

## Code Style

### YAML

- Use 2-space indentation
- Use `---` at the start of files
- Prefer explicit `true`/`false` over `yes`/`no`
- Keep lines under 120 characters

### Terraform

- Run `terraform fmt` before committing
- Use descriptive variable names
- Add descriptions to all variables
- Group related resources

### Ansible

- Use FQCNs (e.g., `ansible.builtin.apt`)
- Name all tasks descriptively
- Use `become: true` only when needed
- Put defaults in `defaults/main.yml`

### Kubernetes

- Use `app-template` chart for applications
- Use standard Kustomize components (`bjw-s-defaults`, `common-env`, `ingress/traefik-base`, `storage/backup-policy`)
- Follow naming convention: `<app-name>.lan.${CLUSTER_DOMAIN}`
- Add Longhorn backup labels via `storage/backup-policy` component or manually
- Include `kustomization.yaml` in app directories
- Add Homepage annotations for dashboard integration

---

## Directory Conventions

| Directory | Purpose | Notes |
|-----------|---------|-------|
| `packer/<distro>-<version>-base/` | VM template definitions | One folder per template |
| `terraform/instances/<instance>/` | Terraform instance roots | Concrete deployments using shared modules |
| `ansible/roles/<role>/` | Reusable Ansible roles | Standard role structure |
| `kubernetes/apps/apps/<category>/<app>/` | Application deployments | HelmRelease + kustomization |
| `kubernetes/infrastructure/<category>/` | Cluster infrastructure | Core services |

---

## Testing Changes

### Packer

```bash
packer validate packer/ubuntu-24.04-base
packer validate packer/fedora-43-server
```

### Terraform

```bash
terraform -chdir=terraform/instances/k3s_nodes validate
terraform -chdir=terraform/instances/k3s_nodes plan
terraform -chdir=terraform/instances/openclaw validate
terraform -chdir=terraform/instances/openclaw plan
```

### Ansible

```bash
ansible-lint ansible/playbooks/ ansible/roles/
ansible-playbook ansible/playbooks/<playbook>.yml --check
```

### Kubernetes

```bash
# Dry-run apply
kubectl apply --dry-run=client -f <path>

# Wait for Flux reconciliation
flux reconcile kustomization flux-system --with-source
```

---

## Commit Messages

Use conventional commits format:

```
<type>(<scope>): <description>

[optional body]
```

Scope is optional, so `<type>: <description>` is also valid.
If present, scope should stay lowercase and can represent a single area like `ansible`, a composite area like `ansible+terraform`, or a path-like area like `apps/item`.

Commit message validation is enforced by the repository hook and CI. Git-generated subjects such as `Merge ...`, `Revert "..."`, `fixup! ...`, `squash! ...`, and `amend! ...` are allowed as exceptions.

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation
- `refactor` - Code refactoring
- `chore` - Maintenance tasks

**Examples:**
```
feat(kubernetes): add audiobookshelf deployment
fix(ansible): correct network interface detection
docs(project): update getting started guide
chore(deps): update helm chart versions
```

---

## Renovate

The repository uses Renovate for dependency updates:

- Minor/patch updates are auto-merged on Sundays
- Major updates require manual review
- Updates are grouped by category (observability, networking)

See `renovate.json` for configuration details.
