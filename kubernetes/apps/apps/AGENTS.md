# Kubernetes Workload Apps Agent Notes

Read the repo root `AGENTS.md`, `kubernetes/AGENTS.md`, and `kubernetes/apps/AGENTS.md` first. This file only covers deployable workload rules.

## What This Subtree Owns
- `kubernetes/apps/apps/` owns deployable workloads and their workload-local resources.
- The common workload shape is `helmrelease.yaml` + `kustomization.yaml` plus optional secrets and extra resources such as DB clusters, backup jobs, or sidecar HelmReleases.

## Source Of Truth Boundaries
- Workload-local resources that directly travel with an app stay here.
- PVC catalogs and persistent storage ownership stay in `kubernetes/apps/storage/` unless a nearer child file explicitly documents an exception.
- Shared defaults and shared ingress behavior often come from `kubernetes/components/`, so local app edits may have shared-component dependencies.

## Local Anti-Patterns
- Do not invent a new app scaffold when the existing category already shows a stable pattern.
- Do not put PVC definitions here when the persistence belongs in `kubernetes/apps/storage/`.
- Do not overlook sibling resources such as `cnpg-cluster.yaml`, backup jobs, extra HelmReleases, or app variants in the same folder.
- Do not assume `external-proxy/` follows the normal HelmRelease-heavy pattern; it is intentionally higher-variance and more direct-YAML-oriented.

## Validation
```bash
kubectl apply --dry-run=client -f kubernetes/apps/apps/<category>/<app>
flux get helmreleases -A
```

- Check parent production kustomizations whenever adding or removing apps, and check storage wiring whenever persistence is part of the change.
