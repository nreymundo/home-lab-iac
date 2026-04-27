# Kubernetes Infrastructure Agent Notes

Read the repo root `AGENTS.md` and `kubernetes/AGENTS.md` first. This file only covers shared infrastructure-service rules.

## What This Subtree Owns
- `kubernetes/infrastructure/` owns shared cluster services and the sources, install manifests, config overlays, and secrets they depend on.
- A common pattern is `install/` for deploy-time objects and `config/` for runtime policy or overlays.

## Source Of Truth Boundaries
- Shared HelmRepository and source definitions belong in `sources/`; service directories should reference that catalog rather than duplicating it.
- Service-scoped secrets belong beside the service and are usually committed as SOPS-encrypted manifests.
- Treat generated or vendor-like chart content as external input; this repo should keep manifests, values, and wiring, not vendored chart payloads.
- `kubernetes/infrastructure/kustomization.yaml` is not the full service aggregation layer; most service reconciliation is wired through `kubernetes/clusters/production/ks/*.yaml`, so ordering and inclusion changes often need edits there too.

## Local Anti-Patterns
- Do not duplicate shared source definitions inside service folders when `sources/` already owns them.
- Do not mix long-lived runtime config into `install/` when an existing `config/` split already communicates the boundary.
- Do not assume install-only changes are isolated; many infrastructure services also have config overlays, ingress, or policy objects nearby.
- Do not change service wiring or inclusion assumptions without checking whether the production cluster ordering layer also needs an update.

## Validation
```bash
kubectl apply --dry-run=client -f kubernetes/infrastructure
flux get helmreleases -A
pre-commit run --all-files
```

- Security and storage subtrees usually have the most local nuance because they mix install objects, policies, ingress, and secrets in the same service tree.
