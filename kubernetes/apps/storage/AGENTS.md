# APP STORAGE KNOWLEDGE BASE

## OVERVIEW
`kubernetes/apps/storage/` holds workload storage state, mostly PVC catalogs grouped by workload domain, plus storage-scoped overlays like `production/`.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| PVC groups | `pvcs/` | Domain folders like `media/`, `ai/`, `security/`, `utils/` |
| Storage overlay | `production/kustomization.yaml` | Inclusion point for storage resources |
| Per-domain grouping | `pvcs/<domain>/kustomization.yaml` | Parent include for each PVC set |

## CONVENTIONS
- PVC manifests are grouped by workload domain rather than colocated with every app.
- File naming is explicit and workload-specific: `<app>-pvc.yaml`.
- Shared multi-instance apps may have multiple PVCs in the same domain folder, e.g. Discord Presence main/alternate.

## ANTI-PATTERNS
- Do not create opaque PVC names; keep them tied to the consuming workload.
- Do not scatter storage manifests across app folders when an existing PVC domain already owns them.

## COMMANDS
```bash
kubectl apply --dry-run=client -f kubernetes/apps/storage
```

## NOTES
- When changing app persistence, inspect both this subtree and the app deployment subtree; they are intentionally split.
