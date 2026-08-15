# Contributing

Guidelines for contributing to the home-lab-iac repository.

## Development Workflow

### 1. Set Up Environment

```bash
# Clone the repository
git clone https://github.com/nreymundo/home-lab-iac.git
cd home-lab-iac

# Check required host tools
scripts/bootstrap-host-tools.sh --check

# Install pre-commit hooks
pre-commit install
```

### 2. Make Changes

1. Create a new branch: `git checkout -b feature/my-change`
2. Make your changes
3. Run applicable pre-commit hooks: `pre-commit run --files <changed-file> [<changed-file>...]`
4. Test locally when possible

Some hooks format files or encrypt and stage `*.sops.yaml` files. Review `git diff` after running them.

### 3. Commit and Push

```bash
git add <changed-paths>
git commit -m "feat: descriptive commit message"
git push origin feature/my-change
```

### 4. Pull Request Review

- Review requests are automatically handled through `CODEOWNERS`.
- All PRs request review from `@nreymundo` by default.
- If a PR is opened from a bot or machine account, this ensures the main account is still pulled in for review.
- Pull request titles should follow the same conventional format as commit subjects.

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
| `kubeconform` | Validate rendered Kubernetes manifests |
| `trivy-fs` | Scan repository files for vulnerabilities and secrets |
| `checkov` | Scan Terraform and Kubernetes IaC policy checks |
| `sops-auto-encrypt` | Auto-encrypt `*.sops.yaml` files when needed |
| `forbid-commit-attribution` | Enforce commit subject policy and block forbidden attribution trailers |

### Running Hooks

```bash
# Run all hooks on all files. Some hooks can format, encrypt, and stage files.
pre-commit run --all-files

# Run specific hook
pre-commit run ansible-lint --all-files
pre-commit run terraform-fmt --all-files
pre-commit run kubeconform --all-files
pre-commit run trivy-fs --all-files --hook-stage manual
pre-commit run checkov --all-files

# Update hooks to latest versions
pre-commit autoupdate
```

`trivy-fs` is a manual local hook because it is slower and needs baseline tuning. Checkov runs for Kubernetes, Terraform, and `.checkov.yaml` changes; CI runs both as hard-failing jobs.

The `forbid-commit-attribution` hook runs during `git commit` as a `commit-msg` hook rather than through the normal file-based pre-commit scan.

---

## Code Style

### YAML

- Use 2-space indentation
- Use `---` for multi-document YAML; follow the existing local style for single-document manifests and Kustomizations
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
- The common workload shape is an `app-template` `helmrelease.yaml` plus `kustomization.yaml`, with optional secrets and workload-local resources. `external-proxy/` is an intentional exception that uses direct Service, Endpoints, and Ingress YAML; other apps may also have variants or extra resources.
- Homepage cards are declared under `config.services` in `kubernetes/apps/apps/utils/homepage/helmrelease.yaml`; do not add Homepage discovery annotations to individual workloads.
- Reuse the shared Helm/OCI source catalog in `kubernetes/infrastructure/sources/` instead of duplicating source definitions in app directories.
- Deployable workloads live under `kubernetes/apps/apps/`; manually declared PVCs live under `kubernetes/apps/storage/`, while controller-managed storage remains with its workload. Include app changes in `kubernetes/apps/production/kustomization.yaml` and storage changes in `kubernetes/apps/storage/production/kustomization.yaml`.

---

## Directory Conventions

| Directory | Purpose | Notes |
|-----------|---------|-------|
| `packer/<template-name>/` | VM template definitions | One folder per template |
| `packer/scripts/` | Shared Packer helpers | Used by one or more template roots |
| `terraform/modules/` | Reusable Terraform modules | Shared Proxmox and cloud building blocks |
| `terraform/instances/vm/<instance>/` | Terraform VM instance roots | Concrete VM deployments using shared modules |
| `terraform/instances/lxc/<instance>/` | Terraform LXC instance roots | Concrete container deployments using shared modules |
| `terraform/cloud/<provider>/.../` | Terraform cloud infrastructure roots | Concrete cloud deployments using shared modules |
| `ansible/roles/<role>/` | Reusable Ansible roles | Standard role structure |
| `kubernetes/apps/apps/<category>/<app>/` | Application deployments | HelmRelease + kustomization, with exceptions such as `external-proxy/` |
| `kubernetes/apps/storage/` | Application persistence | Manually declared PVC catalogs, split from workload manifests |
| `kubernetes/apps/production/` | Production workload inclusion | Aggregates active application directories |
| `kubernetes/components/` | Shared Kustomize components | Reusable defaults, ingress, storage, and config fragments |
| `kubernetes/infrastructure/<category>/` | Cluster infrastructure | Core services |
| `kubernetes/clusters/production/ks/` | Production reconciliation ordering | Numbered Flux Kustomizations; `90-storage.yaml` precedes `91-apps.yaml` |
| `scripts/` | Repository helper scripts | Bootstrap and validation entrypoints |

---

## Testing Changes

### Packer

```bash
TEMPLATE=packer/<changed-template>
packer init "$TEMPLATE"
packer fmt -check -recursive "$TEMPLATE"
packer validate "$TEMPLATE"
```

Set `TEMPLATE` to each modified Packer template root and repeat the commands. If a template has a `build.sh` wrapper that prepares generated inputs, use that workflow as part of the build rather than bypassing it.

### Terraform

```bash
ROOT=terraform/instances/vm/k3s_nodes
terraform -chdir="$ROOT" init
terraform -chdir="$ROOT" fmt -check
terraform -chdir="$ROOT" validate
terraform -chdir="$ROOT" plan
```

Set `ROOT` to each modified Terraform root. `plan` requires the configured backend and provider credentials.

### Ansible

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-lint ansible/playbooks/ ansible/roles/
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/<playbook>.yml --syntax-check
# With reachable target hosts:
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/playbooks/<playbook>.yml --check
```

### Kubernetes

#### Safe local validation

```bash
# Render a Kustomize path, then dry-run its rendered resources. The load
# restrictor is required for this repository's shared component references.
kubectl kustomize --load-restrictor=LoadRestrictionsNone <path> | kubectl apply --dry-run=client -f -

# Validate all rendered Kustomizations
scripts/kubeconform.sh

# Read-only inspection of current Flux state
flux get all -A
flux get helmreleases -A
```

#### Intentional live reconciliation

The following command changes live cluster state; it is not local validation and should only be run when a live reconciliation is explicitly intended and approved:

```bash
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

- Package rules define automerge eligibility and minimum release age; see `renovate.json` for the current policy
- Major updates require manual review
- Updates are grouped by category (observability, networking)

See `renovate.json` for configuration details.
