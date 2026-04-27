# Kubernetes Apps Agent Notes

Read the repo root `AGENTS.md` and `kubernetes/AGENTS.md` first. This file only covers workload-layer composition rules.

## What This Subtree Owns
- `kubernetes/apps/` owns workload overlays, deployable applications, and storage manifests that support those workloads.
- The subtree is intentionally split between `apps/apps/` for workload manifests and `apps/storage/` for PVC and storage-state concerns.

## Source Of Truth Boundaries
- Workload membership is controlled by the relevant parent `kustomization.yaml`, not by file presence alone.
- App deploy logic and app persistence are intentionally split across the two child subtrees; changing one often requires checking the other.
- Most app-level secrets should stay SOPS-encrypted and colocated with the app or storage object that consumes them.
- `kubernetes/apps/storage/` owns PVC and persistence state, while `kubernetes/apps/apps/storage/` is just a workload category; do not confuse the two because they have different contracts.

## Local Anti-Patterns
- Do not add an app directory without wiring it into the relevant parent `kustomization.yaml`.
- Do not put PVC catalogs beside workload manifests when `apps/storage/` already owns that persistence layer.
- Do not treat this file as the detailed editing guide; use `apps/apps/AGENTS.md` for workload-shape rules and `apps/storage/AGENTS.md` for persistence-specific rules.

## Validation
- For workload-tree changes, dry-run the smallest affected subtree rather than the whole cluster.
- For app changes that depend on persistence, verify both the workload manifest path and the storage inclusion path before claiming the change is complete.
