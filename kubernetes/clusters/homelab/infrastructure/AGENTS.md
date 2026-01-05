# AGENTS.md

**Generated:** 2026-01-05 21:13:08
**Commit:** 9c644bd

## OVERVIEW

Core infrastructure applications organized by category.
**Key Pattern:** Install (Helm) + Config (CRDs) split, each with README.md.

## WHERE TO LOOK

 | Category | Location | Components |
 |----------|----------|------------|
 | **Networking** | `networking/traefik/`, `networking/metallb/` |
 | **Storage** | `storage/longhorn/` |
 | **Security** | `security/authentik/` |
 | **DNS** | `dns/external-dns/`, `dns/cert-manager/` |
 | **Observability** | `observability/*` |

## STRUCTURE (Per Component)

```
infrastructure/<category>/<component>/
├── README.md
├── install/                  # Helm phase
│   ├── namespace.yaml
│   ├── helmrelease.yaml
│   └── kustomization.yaml
└── config/                   # CRD phase
    ├── ingress.yaml
    ├── middleware.yaml
    └── kustomization.yaml
```

## CONVENTIONS

### Install vs Config Split
- **`/install`**: Namespace + HelmRelease (Foundation)
- **`/config`**: Custom Resources (Ingress, Middleware, Certificate, etc.)
- Config `kustomization.yaml` uses Flux `substituteFrom` for secrets

### Component Categories
- `networking/`: Traefik, MetalLB
- `storage/`: Longhorn
- `security/`: Authentik
- `dns/`: ExternalDNS, Cert-manager
- `observability/`: Prometheus, Grafana, Loki, Alloy

### Documentation
- Every component has `README.md` with:
  - Architecture overview (Mermaid diagrams)
  - Installation steps
  - Troubleshooting guide

### Monitoring
- Each component includes monitoring manifests:
  - `*-podmonitor.yaml` or `*-servicemonitor.yaml`
  - Auto-discovered by Prometheus operator

### Secret Management
- Config Kustomizations use `substituteFrom` for Bitwarden secrets
- `.sample.yaml` files show expected structure

## ANTI-PATTERNS

1. **DO NOT** skip install phase—Helm charts must be deployed first.
2. **DO NOT** break `dependsOn` chain in Flux Kustomizations.
3. **DO NOT** skip README.md for new components—documentation is mandatory.
4. **DO NOT** hardcode secrets—use Bitwarden substitution.

## ADDING NEW COMPONENTS

 1. Add HelmRepo to `infrastructure/sources/`
 2. Create `infrastructure/<category>/<name>/install/`:
     - `namespace.yaml`, `helmrelease.yaml`, `kustomization.yaml`
 3. Create `infrastructure/<category>/<name>/config/`:
     - CRD manifests, `kustomization.yaml` with `substituteFrom`
 4. Create Flux Kustomizations in `flux-system/`:
     - `<name>-install-kustomization.yaml` → `/install`
     - `<name>-config-kustomization.yaml` → `/config`, `dependsOn: <name>-install`
 5. Write `README.md` with architecture and troubleshooting

## VERIFICATION

```bash
# Watch HelmRelease
flux get helmreleases --all-namespaces

# Watch Kustomization
flux get kustomizations --all-namespaces

# Check component health
kubectl -n <namespace> get pods
```

## NOTES

- All infrastructure apps are managed by Flux—never use `kubectl apply`.
- Config phase depends on install phase (enforced by Flux `dependsOn`).
