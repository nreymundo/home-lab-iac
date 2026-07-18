# Kubernetes Workload Apps Agent Notes

Read the repo root `AGENTS.md`, `kubernetes/AGENTS.md`, and `kubernetes/apps/AGENTS.md` first. This file only covers deployable workload rules.

## What This Subtree Owns
- `kubernetes/apps/apps/` owns deployable workloads and their workload-local resources.
- The common workload shape is `helmrelease.yaml` + `kustomization.yaml` plus optional secrets and extra resources such as DB clusters, backup jobs, or sidecar HelmReleases.

## Source Of Truth Boundaries
- Workload-local resources that directly travel with an app stay here.
- Manually declared PVC catalogs stay in `kubernetes/apps/storage/`, while controller-managed storage such as `CNPG Cluster.spec.storage` remains workload-local unless a nearer child file documents an exception.
- Shared defaults and shared ingress behavior often come from `kubernetes/components/`, so local app edits may have shared-component dependencies.

## Local Anti-Patterns
- Do not invent a new app scaffold when the existing category already shows a stable pattern.
- Do not put manually declared PVC definitions here when the persistence belongs in `kubernetes/apps/storage/`.
- Do not overlook sibling resources or Kustomize behavior such as `cnpg-cluster.yaml`, backup jobs, extra HelmReleases, app variants, components, patches, generators, and namespace transforms.
- Do not assume `external-proxy/` follows the normal HelmRelease-heavy pattern; it is intentionally higher-variance and more direct-YAML-oriented.

## Validation
```bash
kubectl kustomize --load-restrictor=LoadRestrictionsNone kubernetes/apps/apps/<category>/<app> >/dev/null
flux get helmreleases -A
```

- `flux get helmreleases -A` applies only to Helm-managed workloads; validate direct-YAML workloads such as `external-proxy` through the `apps-manifests` Kustomization and their rendered resources.
- Check `kubernetes/apps/production` whenever adding or removing apps, and check storage wiring whenever manually declared PVCs are part of the change.
