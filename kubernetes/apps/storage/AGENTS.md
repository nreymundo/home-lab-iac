# Kubernetes App Storage Agent Notes

Read the repo root `AGENTS.md`, `kubernetes/AGENTS.md`, and `kubernetes/apps/AGENTS.md` first. This file only covers workload-persistence rules.

## What This Subtree Owns
- `kubernetes/apps/storage/` owns workload PVC catalogs and storage overlays.
- PVCs are grouped by workload domain rather than copied into every app directory.

## Source Of Truth Boundaries
- File naming should stay explicit and workload-tied, typically `<app>-pvc.yaml`.
- Persistence ownership stays here even when the consuming workload manifest lives under `kubernetes/apps/apps/`.
- `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` is a special create-only or migration-oriented contract, not a normal default for new PVCs.

## Local Anti-Patterns
- Do not create opaque PVC names that hide the consuming workload.
- Do not scatter storage manifests across app folders when an existing PVC domain already owns them.
- Do not assume Flux will reconcile field changes on a PVC that already uses `ssa: IfNotPresent`.
- Do not add `ssa: IfNotPresent` to new PVCs unless you intentionally want create-only behavior for an existing-data or migration scenario.

## Validation
```bash
kubectl apply --dry-run=client -f kubernetes/apps/storage
```

- When changing app persistence, inspect both this subtree and the workload subtree; they are intentionally split.
- When changing a PVC that already has `ssa: IfNotPresent`, call out any required manual live step explicitly instead of presenting the Git change as self-sufficient.
