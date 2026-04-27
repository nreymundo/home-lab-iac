# Production Cluster Agent Notes

Read the repo root `AGENTS.md` and `kubernetes/AGENTS.md` first. This file only covers the production cluster ordering and bootstrap layer.

## What This Subtree Owns
- `kubernetes/clusters/production/` owns the top-level cluster aggregation, Flux bootstrap wiring, and ordered reconciliation entrypoints.
- `ks/` is the hand-maintained ordering layer.
- `flux-system/` is generated bootstrap output and is not the routine edit surface.

## Source Of Truth Boundaries
- `ks/kustomization.yaml` and the numbered `ks/*.yaml` files communicate dependency order and are part of the production bring-up contract.
- Install/config pairs often appear as adjacent numbers; preserve that ordering intent unless the dependency model itself is changing.
- Service-specific implementation details should stay in `kubernetes/infrastructure/` or `kubernetes/apps/`; this subtree should mostly wire ordering and inclusion.

## Local Anti-Patterns
- Never hand-edit `flux-system/gotk-components.yaml` or `flux-system/gotk-sync.yaml` during routine changes.
- Do not reorder `ks/kustomization.yaml` casually; bootstrap and reconciliation dependencies rely on that sequence.
- Do not solve local service problems by stuffing service-specific config into the cluster ordering layer.

## Validation
```bash
kubectl apply --dry-run=client -f kubernetes/clusters/production/ks
flux get kustomizations
flux reconcile kustomization flux-system --with-source
```

- Most routine edits here should answer one of three questions: are you changing ordering, changing inclusion, or intentionally re-bootstrapping Flux?
