# Contributing

Guidelines for contributing to the home-lab-iac repository.

## Development Workflow

### 1. Set Up Environment

```bash
# Clone the repository
git clone https://github.com/<user>/home-lab-iac.git
cd home-lab-iac

# Install pre-commit hooks
pre-commit install

# Set up environment variables (see docs/GETTING_STARTED.md)
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

---

## Pre-commit Hooks

The repository uses pre-commit to enforce code quality:

| Hook | Purpose |
|------|---------|
| `trailing-whitespace` | Remove trailing whitespace |
| `end-of-file-fixer` | Ensure files end with newline |
| `check-yaml` | Validate YAML syntax |
| `yamllint` | Lint YAML files |
| `ansible-lint` | Lint Ansible playbooks and roles |
| `packer-fmt` | Format Packer HCL files |
| `terraform-fmt` | Format Terraform files |

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
- Follow naming convention: `<app-name>.lan.${CLUSTER_DOMAIN}`
- Add Longhorn backup labels where appropriate
- Include `kustomization.yaml` in app directories

---

## Directory Conventions

| Directory | Purpose | Notes |
|-----------|---------|-------|
| `packer/<distro>-<version>-base/` | VM template definitions | One folder per template |
| `terraform/k3s_nodes/` | K3s node provisioning | Main Terraform module |
| `ansible/roles/<role>/` | Reusable Ansible roles | Standard role structure |
| `kubernetes/apps/apps/<category>/<app>/` | Application deployments | HelmRelease + kustomization |
| `kubernetes/infrastructure/<category>/` | Cluster infrastructure | Core services |

---

## Testing Changes

### Packer

```bash
cd packer/<template>
packer validate .
./build.sh  # Full build
```

### Terraform

```bash
cd terraform/k3s_nodes
terraform validate
terraform plan
```

### Ansible

```bash
cd ansible
ansible-lint playbooks/ roles/
ansible-playbook playbooks/<playbook>.yml --check
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
docs: update getting started guide
chore(deps): update helm chart versions
```

---

## Renovate

The repository uses Renovate for dependency updates:

- Minor/patch updates are auto-merged on Sundays
- Major updates require manual review
- Updates are grouped by category (observability, networking)

See `renovate.json` for configuration details.
