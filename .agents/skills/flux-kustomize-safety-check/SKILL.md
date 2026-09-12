---
name: flux-kustomize-safety-check
description: >-
  Validate and safely change this repository's Kubernetes desired state when
  manifests are not deploying or a Flux/Kustomize inclusion problem is
  suspected. Use for HelmRelease, Ingress, PVC, or CronJob edits; Kustomize
  render and schema checks; Flux spec.path, ordering, dependsOn, source-catalog,
  prune, and parent-kustomization questions; or when committed manifests do not
  appear in the cluster. Do NOT use for new-app onboarding, observability
  incidents, or cluster/PVC/database restore workflows; those belong to
  k8s-app-onboarding, kubernetes-observability-debugging, and
  cluster-bootstrap-restore respectively.
---

# Flux & Kustomize Safety Check

This skill checks the complete GitOps path from a hand-authored manifest to the
Flux `Kustomization` that reconciles it. File presence is not desired state in
this repository: a resource must be rendered by its local Kustomization parents
and reached by a Flux `spec.path` target.

## When to use

- A Kubernetes manifest is committed but is not deploying or is missing from a
  rendered inventory.
- Editing an existing `HelmRelease`, `Ingress`, `PVC`, or `CronJob`.
- Changing a Kustomize resource/component, a parent `kustomization.yaml`, or a
  Flux Kustomization ordering/inclusion entry.
- Checking whether a service is included by Flux, whether its chart source is
  available, or whether a prune/PVC change is safe.
- Validating a narrow Kubernetes desired-state change before any live action.

## Do not use

- Do not use this as the primary workflow for onboarding a new application;
  use `k8s-app-onboarding`.
- Do not use it to diagnose centralized Grafana, Loki, Tempo, Alloy, OTel, or
  Prometheus incidents; use `kubernetes-observability-debugging`.
- Do not use it for a fresh-cluster bootstrap, PVC restore, or CNPG restore;
  use `cluster-bootstrap-restore` and its authoritative runbook.
- Do not turn a desired-state check into an imperative live repair.

## Source-of-truth and ownership pass

1. Read the repository `AGENTS.md`, then walk from every changed path toward the
   repository root and read each applicable nearest `AGENTS.md`. For Kubernetes
   work this normally includes `kubernetes/AGENTS.md` and, when relevant,
   `apps/`, `apps/storage/`, `infrastructure/`, `components/`, or
   `clusters/production/` guidance. Record which file owns the edit before
   changing it.
2. Treat hand-authored manifests and Kustomizations as source of truth. Never
   hand-edit generated Flux bootstrap output such as
   `kubernetes/clusters/production/flux-system/gotk-components.yaml` or
   `gotk-sync.yaml`; redirect routine changes to the owning manifest or
   `clusters/production/ks/` entry.
3. If a shared Kustomize component changes, search all consumers before editing
   and render representative consumers. Relative component paths are part of
   the contract, so a component change is not local merely because one file was
   changed.

## Trace the complete inclusion chain

Start with the changed object and document the chain, rather than assuming its
directory is active:

1. Find the nearest Kustomize `kustomization.yaml`. Follow every `resources:`
   and `components:` entry upward through its parent Kustomizations until the
   workload, storage domain, infrastructure aggregate, or cluster aggregate is
   reached. Check both sides of the app/storage split: workload manifests live
   under `kubernetes/apps/apps/`, while manually declared PVC catalogs live
   under `kubernetes/apps/storage/`.
2. For infrastructure changes, check the service's `install/` and `config/`
   Kustomizations and the shared catalog under
   `kubernetes/infrastructure/sources/`. A `HelmRelease` must resolve its
   `spec.chart.spec.sourceRef` to the catalog's `HelmRepository` or
   `OCIRepository`; do not duplicate a repository definition inside a service
   directory when the catalog already owns it.
3. Trace the parent production aggregators. Typical roots include
   `kubernetes/apps/production`, `kubernetes/apps/storage/production`,
   `kubernetes/infrastructure`, and the production cluster ordering layer, but
   follow the actual parent chain rather than assuming every path exists.
4. Inspect `kubernetes/clusters/production/ks/kustomization.yaml` and every
   relevant numbered `ks/*.yaml`. For each Flux `Kustomization`, record its
   `metadata.name`, `spec.path`, `spec.prune`, and `spec.dependsOn`. Numbered
   filenames communicate intended human ordering; `spec.dependsOn` is the
   authoritative reconciliation dependency graph. A wrong `spec.path`, missing
   `ks/kustomization.yaml` entry, or failed dependency means a valid leaf
   manifest still will not become active.

## Resource-specific safety checks

- **HelmRelease:** verify namespace, chart name/version, the complete
  `sourceRef` (kind, name, and namespace), values files/config references,
  referenced Secrets/ConfigMaps, and that all those inputs are rendered by the
  same or an intentionally earlier Flux path.
- **Ingress:** verify the backend Service and port, hostname expression, TLS
  and middleware references, namespace ownership, and inclusion of the parent
  Kustomization. Copy the complete matching sibling expression for
  parameterized hostnames; do not infer variable placement from a rendered
  hostname.
- **PVC:** identify whether the claim is manually cataloged under
  `apps/storage/` or controller-managed by a workload such as CNPG. Check the
  exact claim name used by consumers, storage class, access mode, size, and
  backup/retention contract. Treat a removed storage entry as destructive even
  when the workload file is unchanged.
- **CronJob:** verify schedule, namespace, service account, image, command,
  Secret/ConfigMap references, and inclusion in the rendered parent. Ensure a
  cleanup or rename is intentional rather than a prune side effect.

## Prune, PVC, and generated-boundary risks

Both `apps-storage` and `apps-manifests` use `prune: true`. Removing a resource
or a parent `resources:` entry can therefore delete its live object. Before
removing or renaming anything, identify the Flux owner, rendered object name,
and whether a PVC or dependent workload will be orphaned, recreated, or pointed
at empty storage. Read the closer storage `AGENTS.md`; `ssa: IfNotPresent` is a
create-only migration contract, not a default for new PVCs.

If a requested change appears to require editing `flux-system/` generated
output, stop and locate the hand-maintained `ks/` or source manifest that owns
the behavior. Do not hide a source, ordering, or path fix in generated
bootstrap content.

## Read-only validation sequence

Render the changed leaf first, then every relevant parent Kustomization discovered
in the inclusion trace. Use the load restrictor when a component or referenced
file is outside the Kustomization root:

```bash
kubectl kustomize --load-restrictor=LoadRestrictionsNone <changed-leaf-path> >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone <parent-path> >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone <parent-path> \
  | kubectl apply --dry-run=client -f -
```

Repeat for the actual workload/storage/infrastructure and production ordering
parents found above; do not substitute a single narrow render for a parent
inclusion check. Then run the repository-wide rendered validation and the
file-scoped hooks:

```bash
scripts/kubeconform.sh
pre-commit run --files <changed-file> [<additional-changed-file>...]
```

`kubectl apply --dry-run=client` is the apply-shaped check; plain `kubectl
apply`, `kubectl delete`, and imperative patches are not validation. Hooks may
encrypt or stage SOPS files, so inspect the resulting diff when they touch
encrypted manifests.

For an existing deployment that is not appearing, read live status without
mutating it when access is available:

```bash
flux get kustomizations
flux get helmreleases -A
```

Use those results to distinguish an unrendered object, wrong `spec.path`, failed
dependency, unavailable chart source, schema failure, and a pruned object. Do
not claim a Git-only fix is confirmed when live access is unavailable.

## Explicit live-action boundary

`flux reconcile kustomization flux-system --with-source` is an intentional live
mutation, not a validation command. Never run it automatically as part of this
skill. It may be offered only after the user explicitly approves that exact live
reconciliation and its expected rollout; otherwise leave it out and report the
read-only results.

## Expected report

Return the nearest `AGENTS.md` owner, the leaf-to-parent Kustomize/component
chain, the Flux `spec.path` and `dependsOn` chain, source-catalog references,
prune/PVC risks, rendered paths checked, and any validation failures. Clearly
separate read-only checks from the explicitly approved live reconciliation.

## References

- `AGENTS.md`, `kubernetes/AGENTS.md`
- `kubernetes/apps/AGENTS.md`, `kubernetes/infrastructure/AGENTS.md`,
  `kubernetes/components/AGENTS.md`, and the closest child `AGENTS.md`
- `kubernetes/clusters/production/AGENTS.md`
- `k8s-app-onboarding`, `kubernetes-observability-debugging`, and
  `cluster-bootstrap-restore` for their owned workflows
- `CONTRIBUTING.md` Kubernetes validation section
