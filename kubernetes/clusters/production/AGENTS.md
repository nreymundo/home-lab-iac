# PRODUCTION CLUSTER KNOWLEDGE BASE

## OVERVIEW
`clusters/production/` defines Flux bootstrap wiring and the ordered cluster bring-up manifests for the production cluster.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Overall cluster entry | `kustomization.yaml` | Includes `flux-system` then `ks` |
| Ordered cluster resources | `ks/kustomization.yaml` | Numbered sequence is intentional |
| Generated Flux bootstrap | `flux-system/` | Bootstrap output, not routine edit surface |

## CONVENTIONS
- `kustomization.yaml` at this level is the top-level aggregator for the cluster subtree.
- `ks/` is hand-maintained and authoritative for cluster resource ordering.
- Number prefixes in `ks/*.yaml` communicate dependency order; keep the order meaningful.
- Install and config pairs often come as adjacent numbers: e.g. `20-*-install`, `21-*-config`.

## ANTI-PATTERNS
- Never hand-edit `flux-system/gotk-components.yaml` or `flux-system/gotk-sync.yaml`.
- Do not reorder `ks/kustomization.yaml` casually; bootstrapping dependencies depend on the sequence.
- Do not put service-specific detail here when the real source belongs in `kubernetes/infrastructure/` or `kubernetes/apps/`.

## COMMANDS
```bash
kubectl apply --dry-run=client -f kubernetes/clusters/production/ks
flux get kustomizations
flux reconcile kustomization flux-system --with-source
```

## NOTES
- Contributor-relevant files are almost always `ks/*.yaml` and `ks/kustomization.yaml`.
- Treat `flux-system/` as generated bootstrap state unless you are intentionally re-bootstrapping Flux.
