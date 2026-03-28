# INFRASTRUCTURE KNOWLEDGE BASE

## OVERVIEW
`kubernetes/infrastructure/` holds shared cluster services: sources, namespaces/config, and domain services such as networking, security, storage, observability, automation, GPU, and database operators.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Shared chart/source defs | `sources/` | Centralized HelmRepository / source catalog |
| Shared namespaces/config | `config/` | Global infrastructure wiring |
| Networking services | `networking/` | Traefik, external-dns, cloudflared, MetalLB |
| Security services | `security/` | Authentik, CrowdSec, cert-manager, kube-replicator |
| Storage services | `storage/` | Longhorn and related config |
| Observability stack | `observability/` | Prometheus, Loki, Alloy, metrics-server |
| Automation services | `automation/` | Renovate and related scheduled automation |
| Database operators | `database/` | CloudNativePG and related secrets/backups |
| GPU services | `gpu/` | Intel device plugins and GPU operator pieces |
| Node discovery | `node-feature-discovery/` | Hardware labeling and discovery rules |

## CONVENTIONS
- Common pattern: `install/` for deploy-time objects, `config/` for runtime policies and overlays.
- Source definitions belong in `sources/`; service directories reference them.
- Secrets next to services are usually SOPS-encrypted and service-scoped.
- Service roots often expose one install Kustomization plus one config Kustomization.

## ANTI-PATTERNS
- Do not create duplicate source definitions inside service folders when `sources/` is the shared catalog.
- Do not mix long-lived runtime config into `install/` when an existing `config/` split is already in use.
- Do not treat generated or vendor-like chart content as if it belongs in this repo; keep repo state to manifests and values.

## COMMANDS
```bash
kubectl apply --dry-run=client -f kubernetes/infrastructure
flux get helmreleases -A
pre-commit run --all-files
```

## NOTES
- Security and storage subtrees carry the most local nuance because they mix install objects, policies, ingress, and secrets.
- If a change affects ordering, the corresponding `clusters/production/ks/*.yaml` entry is often the other place to inspect.
