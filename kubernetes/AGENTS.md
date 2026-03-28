# KUBERNETES KNOWLEDGE BASE

## OVERVIEW
Everything under `kubernetes/` is desired cluster state reconciled by Flux.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Production bootstrap | `clusters/production/` | Top-level entry for this cluster |
| Shared infra services | `infrastructure/` | Sources + service install/config trees |
| Workload apps | `apps/` | Production overlay plus app and storage trees |
| Reusable components | `components/` | Shared Kustomize components referenced by apps |

## CONVENTIONS
- Edit hand-authored manifests, not generated Flux bootstrap output.
- Kustomize boundaries matter: parent `kustomization.yaml` files are the authoritative inclusion points.
- Shared provider/chart sources live in `infrastructure/sources/`, not ad hoc beside every service.
- App manifests commonly rely on `app-template` through `bjw-s-defaults`.
- `*.sops.yaml` is the normal form for committed Kubernetes secrets.

## ANTI-PATTERNS
- Do not validate by applying live changes when `kubectl --dry-run=client`, `flux get`, or `flux reconcile` will answer the question.
- Do not scatter new Helm/OCI source definitions outside `infrastructure/sources/` without a strong reason.

## COMMANDS
```bash
kubectl apply --dry-run=client -f <path>
flux get all -A
flux get helmreleases -A
flux reconcile kustomization flux-system --with-source
```

## NOTES
- Read the closer child AGENTS before editing `clusters/production`, `infrastructure`, `apps`, or `components`; each subtree has materially different rules.
