# PROJECT KNOWLEDGE BASE

**Generated:** 2026-03-28
**Commit:** cad43be
**Branch:** master

## OVERVIEW
Home-lab IaC repo with a staged provisioning pipeline: Packer builds VM templates, Terraform creates K3s node VMs, Ansible configures them, and Kubernetes/Flux reconciles cluster state.

## STRUCTURE
```text
home-lab-iac/
├── kubernetes/   # GitOps state: Flux, cluster bootstrap, infra, apps
├── terraform/    # Proxmox VM provisioning via shared modules and instance roots
├── ansible/      # Host and cluster configuration playbooks and roles
├── packer/       # Proxmox template builds with Bitwarden-backed SSH injection
├── docs/         # Human guidance; useful context, not runtime state
└── scripts/      # Pre-commit and secret-safety helpers
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Cluster bootstrap order | `kubernetes/clusters/production/ks/` | Numbered Kustomizations define install/config order |
| Flux bootstrap state | `kubernetes/clusters/production/flux-system/` | Generated; not normal edit targets |
| Shared infra sources | `kubernetes/infrastructure/sources/` | HelmRepository/other source definitions |
| Cluster infra services | `kubernetes/infrastructure/` | Repeated `install/` and `config/` split |
| App deployments | `kubernetes/apps/apps/` | Mostly app-template HelmReleases + kustomizations |
| App PVCs and storage overlays | `kubernetes/apps/storage/` | PVC catalogs and storage-scoped overlays |
| VM provisioning | `terraform/instances/k3s_nodes/`, `terraform/instances/openclaw/` | Instance roots; also generate Ansible inventory |
| Host / K3s config | `ansible/playbooks/`, `ansible/roles/` | `k3s_cluster.yml` is the main cluster playbook |
| VM template builds | `packer/*/` | Run template-local `build.sh` after validation |

## CONVENTIONS
- GitOps-first. If a Kubernetes change can live in git, make it in git and let Flux reconcile.
- Root Kubernetes flow is `kubernetes/clusters/production/kustomization.yaml` → `flux-system/` + `ks/`.
- App layout is stable: `kubernetes/apps/apps/<category>/<app>/`.
- Standard app components recur: `bjw-s-defaults`, `ingress/traefik-base`, and `storage/backup-policy`.
- Internal hostnames follow `*.lan.${CLUSTER_DOMAIN}`.
- Infrastructure secrets use Bitwarden; Kubernetes secrets are committed only as `*.sops.yaml`.
- Terraform is upstream of Ansible here: `terraform/instances/k3s_nodes` writes `ansible/inventories/k3s-nodes.yml` and `terraform/instances/openclaw` writes `ansible/inventories/openclaw.yml`.

## ANTI-PATTERNS (THIS PROJECT)
- Never patch, apply, edit, scale, or restart Kubernetes resources directly when the repo can express the change.
- Never treat `kubernetes/clusters/production/flux-system/gotk-*.yaml` as normal edit targets.
- Never commit plaintext secrets, private keys, or unencrypted Kubernetes Secret manifests.
- Do not attribute commits to any person or tool unless explicitly instructed to do so.
- Do not add anything to commit messages beyond the requested change summary unless explicitly instructed to do so.
- Never broaden a narrowly requested fix beyond the files needed for that exact change.
- Do not use docs or generated manifests as evidence that a subtree needs its own AGENTS file.

## DEBUGGING / INCIDENT VALIDATION
- Do not assume a root cause from config review, static reasoning, or pattern matching alone when live evidence is available.
- Before claiming a fix, identify the actual root cause using the most direct evidence available in the current environment: real logs, live cluster state, runtime behavior, failing requests, rendered config, or other production-facing signals.
- If live validation is possible from the current environment, do it before proposing or applying a fix. Do not stop at a plausible theory.
- If live validation is not possible, say so explicitly, state that the diagnosis is provisional, and do not present the fix as confirmed.
- After applying a fix for a runtime issue, validate the live result against the original failure mode whenever access permits. Do not declare success based only on linting, dry-run validation, or code inspection.

## UNIQUE STYLES
- Repo guidance is intentionally operational: commands, boundaries, and “where to edit” matter more than prose style.
- Validation is centralized through pre-commit plus domain-specific CLI checks, not a large traditional CI test suite.
- `CLAUDE.md` currently mirrors root guidance; treat `AGENTS.md` as the canonical source when extending hierarchy.

## COMMANDS
```bash
pre-commit install
pre-commit run --all-files

# Kubernetes / Flux
kubectl apply --dry-run=client -f <path>
flux get all -A
flux reconcile kustomization flux-system --with-source

# Terraform
terraform -chdir=terraform/instances/k3s_nodes validate
terraform -chdir=terraform/instances/k3s_nodes plan
terraform -chdir=terraform/instances/openclaw validate
terraform -chdir=terraform/instances/openclaw plan

# Ansible
ansible-lint ansible/playbooks/ ansible/roles/
ansible-playbook ansible/playbooks/k3s_cluster.yml --check

# Packer
packer validate packer/ubuntu-24.04-base
packer validate packer/fedora-43-server
```

## NOTES
- Highest-signal generated noise: `kubernetes/clusters/production/flux-system/gotk-components.yaml` and `gotk-sync.yaml`.
- `docs/` is useful for orientation, but AGENTS placement should follow maintained runtime boundaries first.
- Start with the domain AGENTS nearest the change; parent files give shared rules, child files give edit targets and local gotchas.
