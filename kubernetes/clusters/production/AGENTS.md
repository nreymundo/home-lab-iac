# Production Cluster Agent Notes

Read the repo root `AGENTS.md` and `kubernetes/AGENTS.md` first. This file only covers the production cluster ordering and bootstrap layer.

## What This Subtree Owns
- `kubernetes/clusters/production/` owns the top-level cluster aggregation, Flux bootstrap wiring, and ordered reconciliation entrypoints.
- `ks/` is the hand-maintained ordering layer.
- `flux-system/` is generated bootstrap output and is not the routine edit surface.

## Source Of Truth Boundaries
- `ks/kustomization.yaml` controls inclusion, while Flux `spec.dependsOn` defines reconciliation dependencies. Numbered `ks/*.yaml` files communicate human-facing ordering intent.
- Install/config pairs often appear as adjacent numbers; preserve that convention unless the dependency model itself is changing.
- Service-specific implementation details should stay in `kubernetes/infrastructure/` or `kubernetes/apps/`; this subtree should mostly wire ordering and inclusion.

## Local Anti-Patterns
- Never hand-edit `flux-system/gotk-components.yaml` or `flux-system/gotk-sync.yaml` during routine changes.
- Do not reorder `ks/kustomization.yaml` casually; inclusion changes affect the rendered inventory. Model reconciliation dependencies with `spec.dependsOn`.
- Do not solve local service problems by stuffing service-specific config into the cluster ordering layer.

## Validation
```bash
kubectl kustomize kubernetes/clusters/production/ks >/dev/null
flux get kustomizations
```

- Most routine edits here should answer one of three questions: are you changing ordering, changing inclusion, or intentionally re-bootstrapping Flux?
- Treat `flux reconcile kustomization flux-system --with-source` as an intentional live reconciliation of committed state, not local validation.
