# Kubernetes

Flux reconciles K3s desired state from
[`clusters/production`](clusters/production/kustomization.yaml). That root
includes the generated `flux-system/` bootstrap and the hand-maintained
[`ks/` inventory](clusters/production/ks/kustomization.yaml). Follow each Flux
`spec.path` and then local `resources` and `components`; a file on disk is not
necessarily deployed. `spec.dependsOn`, not filename order, gates readiness.

| Layer | Where to trace changes |
| --- | --- |
| Shared sources and namespaces | [`infrastructure`](infrastructure/kustomization.yaml) |
| Infrastructure services | Individual `spec.path` targets under `infrastructure/`, often split into `install/` and `config/` |
| Workloads | [`apps/production`](apps/production/kustomization.yaml) includes app roots under `apps/apps/` |
| Standalone workload PVCs | [`apps/storage/production`](apps/storage/production/kustomization.yaml) includes per-domain catalogs; operator-managed claims stay with their controllers |
| Shared defaults and ingress | `components/`, included by consumers rather than reconciled separately |

Both app inventories use pruning; removing an inclusion can delete a workload
or a claim. NetBird manifests are retained but intentionally not reconciled.
Encrypted `*.sops.yaml` files are the Git source for Secrets; trace replicated
Secrets from their owner to the actual consumer namespace before editing.

Editing rules and validation commands: [AGENTS.md](AGENTS.md).
Rebuild and restore runbook: [../docs/kubernetes-bootstrap.md](../docs/kubernetes-bootstrap.md).
