# Kubernetes

Desired state for the K3s cluster, applied by Flux GitOps. A manifest is only
active if a Flux Kustomization or a `kustomization.yaml` chain includes it.

- Reconciliation entrypoints: `clusters/production/` (Flux root and the
  ordered `ks/` layer).
- Cluster services live in `infrastructure/`, workloads in `apps/apps/`, and
  shared Kustomize components in `components/`.
- Secrets are committed as SOPS/AGE-encrypted `*.sops.yaml`.

Editing rules and validation commands: [AGENTS.md](AGENTS.md).
Rebuild and restore runbook: [../docs/kubernetes-bootstrap.md](../docs/kubernetes-bootstrap.md).
