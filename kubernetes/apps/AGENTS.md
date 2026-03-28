# APPS KNOWLEDGE BASE

## OVERVIEW
`kubernetes/apps/` is the workload layer: production overlays, deployable apps, and storage/PVC definitions that support those apps.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Production workload overlay | `production/kustomization.yaml` | Aggregates app deployments |
| Deployable applications | `apps/` | HelmRelease-driven services |
| PVCs and storage overlays | `storage/` | Mostly PVC catalogs and storage-scoped kustomizations |

## CONVENTIONS
- Workload membership is controlled by the production kustomizations, not by file presence alone.
- App deploy logic and app storage are intentionally split across `apps/` and `storage/`.
- Most app-level secrets are SOPS files colocated with the app or related storage object.

## ANTI-PATTERNS
- Do not add an app directory without wiring it into the relevant parent `kustomization.yaml`.
- Do not put PVC catalogs beside the workload manifests when an existing storage subtree already owns them.

## NOTES
- Use the nearer child AGENTS in `apps/apps/` or `apps/storage/` for the actual local editing rules.
