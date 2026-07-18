# Kubernetes Apps Agent Notes

Read the repo root `AGENTS.md` and `kubernetes/AGENTS.md` first. This file only covers workload-layer composition rules.

## What This Subtree Owns
- `kubernetes/apps/` owns workload overlays, deployable applications, and manually declared PVC manifests that support those workloads.
- The subtree is intentionally split between `apps/apps/` for workload manifests and `apps/storage/` for PVC and storage-state concerns.

## Source Of Truth Boundaries
- Workload membership is controlled by the relevant parent `kustomization.yaml`, not by file presence alone.
- App deploy logic and manually declared app PVCs are intentionally split across the two child subtrees; changing one often requires checking the other.
- Most app-level secrets should stay SOPS-encrypted and colocated with the app or storage object that consumes them.
- `kubernetes/apps/storage/` owns manually declared PVC catalogs, while controller-managed storage such as `CNPG Cluster.spec.storage` remains workload-local. `kubernetes/apps/apps/storage/` is just a workload category; do not confuse the two because they have different contracts.
- `ks/90-storage.yaml` reconciles `kubernetes/apps/storage/production` as `apps-storage`; `ks/91-apps.yaml` reconciles `kubernetes/apps/production` as `apps-manifests`, which depends on storage and Traefik configuration.
- Both Flux Kustomizations use `prune: true`; removing an inclusion can delete its rendered resources.

## Local Anti-Patterns
- Do not add an app directory without wiring it into the relevant parent `kustomization.yaml`.
- Do not put manually declared PVC catalogs beside workload manifests when `apps/storage/` already owns that persistence layer.
- Do not treat this file as the detailed editing guide; use `apps/apps/AGENTS.md` for workload-shape rules and `apps/storage/AGENTS.md` for persistence-specific rules.

## Validation
```bash
kubectl kustomize --load-restrictor=LoadRestrictionsNone kubernetes/apps/production >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone kubernetes/apps/storage/production >/dev/null
```

- For app changes that use manually declared PVCs, verify both the workload manifest path and the storage inclusion path before claiming the change is complete.
