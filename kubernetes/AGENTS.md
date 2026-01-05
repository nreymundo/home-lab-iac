# AGENTS.md

**Generated:** 2026-01-05 21:13:08
**Commit:** 9c644bd

## OVERVIEW

Flux GitOps definitions for K3s cluster state.
**Key Pattern:** Install (Helm) vs Config (CRDs) split with dependency chain.

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| **New infrastructure app** | `clusters/homelab/infrastructure/<cat>/<name>/` | Create install/config dirs |
| **Flux configuration** | `clusters/homelab/flux-system/` | GitOps sync root |
| **Helm repository sources** | `clusters/homelab/infrastructure/sources/` | Centralized HelmRepos |
| **Secret definitions** | `clusters/homelab/secrets/` | Bitwarden integration |
| **App templates** | `samples/` | Helm release scaffolding |

## STRUCTURE

```
kubernetes/
├── clusters/homelab/
│   ├── flux-system/           # Flux GitOps config
│   ├── infrastructure/        # Core infrastructure apps
│   ├── apps/                 # User applications
│   └── secrets/              # Secret definitions (.sample.yaml)
└── samples/                  # Helm release templates
```

## CONVENTIONS

### Install vs Config Split
Every infrastructure component has two subdirectories:
- **`/install`**: HelmRelease + namespace (Foundation)
- **`/config`**: Custom Resources (Ingress, Middleware, Certificate, etc.)

### Kustomization Dependency Chain
In `flux-system/`, each component has two Kustomizations:
- `<name>-install-kustomization.yaml` → Points to `/install` dir
- `<name>-config-kustomization.yaml` → Points to `/config` dir, `dependsOn: <name>-install`

### Secret Management
- Uses Bitwarden Secrets Manager with Flux `substituteFrom`
- `.sample.yaml` files in `secrets/` show expected structure

### Component Organization
- Category subdirs: `security/`, `observability/`, `networking/`
- Component naming: kebab-case (e.g., `traefik`, `metallb`)
- Each component has README.md with Mermaid diagrams

## ANTI-PATTERNS

1. **NEVER** use `kubectl apply` for resources in this directory—push to Git.
2. **DO NOT** edit Flux-generated files (`gotk-components.yaml`, `gotk-sync.yaml`).
3. **DO NOT** break the install → config dependency chain.
4. **DO NOT** commit actual secrets—use Bitwarden IDs or placeholders.

## VERIFICATION

```bash
# Dry run apply
kubectl apply -f <file> --dry-run=client

# Watch Flux logs
flux logs -f

# Check Kustomization status
flux get kustomizations --all-namespaces
```

## NOTES

- Flux syncs from `main` branch to `clusters/homelab/` directory.
- Documentation required for each component (README.md).
