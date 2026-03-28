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
├── terraform/    # Proxmox VM provisioning; currently centered on k3s_nodes
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
| VM provisioning | `terraform/k3s_nodes/` | Also generates Ansible inventory |
| Host / K3s config | `ansible/playbooks/`, `ansible/roles/` | `k3s_cluster.yml` is the main cluster playbook |
| VM template builds | `packer/*/` | Run template-local `build.sh` after validation |

## CONVENTIONS
- GitOps-first. If a Kubernetes change can live in git, make it in git and let Flux reconcile.
- Root Kubernetes flow is `kubernetes/clusters/production/kustomization.yaml` → `flux-system/` + `ks/`.
- App layout is stable: `kubernetes/apps/apps/<category>/<app>/`.
- Standard app components recur: `bjw-s-defaults`, `ingress/traefik-base`, and `storage/backup-policy`.
- Internal hostnames follow `*.lan.${CLUSTER_DOMAIN}`.
- Infrastructure secrets use Bitwarden; Kubernetes secrets are committed only as `*.sops.yaml`.
- Terraform is upstream of Ansible here: `terraform/k3s_nodes` writes `ansible/inventories/k3s-nodes.yml`.

## ANTI-PATTERNS (THIS PROJECT)
- Never patch, apply, edit, scale, or restart Kubernetes resources directly when the repo can express the change.
- Never treat `kubernetes/clusters/production/flux-system/gotk-*.yaml` as normal edit targets.
- Never commit plaintext secrets, private keys, or unencrypted Kubernetes Secret manifests.
- Never broaden a narrowly requested fix beyond the files needed for that exact change.
- Do not use docs or generated manifests as evidence that a subtree needs its own AGENTS file.

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
terraform -chdir=terraform/k3s_nodes validate
terraform -chdir=terraform/k3s_nodes plan

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
