---
name: cluster-bootstrap-restore
description: >-
  Guide cluster rebuild and recovery operations against this repo's
  `docs/kubernetes-bootstrap.md` runbook: fresh cluster bootstrap, the Harbor
  registry catch-22, Longhorn PVC restore (options A/B/C), CloudNativePG
  database restore and PITR, and Flux bring-up order. Use when the user says
  "rebuild the cluster from git", "restore a PVC", "restore a CNPG database",
  "Harbor bootstrap", "image pulls failing because registry is not ready", or
  "first-time bootstrap". Always distinguish Git changes from live/manual steps.
  Do NOT use for routine workload changes or normal Flux reconciliation of
  committed state.
---

# Cluster Bootstrap & Restore

The authoritative runbook is `docs/kubernetes-bootstrap.md`. This skill wraps it
for interactive recovery. Always read the runbook section that matches the
scenario before emitting commands; do not paraphrase from memory.

## When to use

- Fresh cluster rebuild from Git + backups.
- Harbor not yet bootstrapped and image pulls are failing.
- Longhorn PVC restore (full rebuild, file-level copy, or replacing a damaged
  claim).
- CloudNativePG database restore or point-in-time recovery.
- Re-establishing Flux reconciliation order after a partial rebuild.

Do not use for routine workload changes (use `k8s-app-onboarding`) or for
normal `flux reconcile` of already-committed state.

## Critical rule

Mixing GitOps changes with live recovery steps silently causes data loss. Always
label a step as **Git change** vs **live/manual** and confirm before running any
live step.

## Source of truth

- Flux root: `kubernetes/clusters/production`
- Flux bootstrap output (generated, do not hand-edit):
  `kubernetes/clusters/production/flux-system`
- Hand-maintained ordering layer: `kubernetes/clusters/production/ks`
- Workload manifests: `kubernetes/apps/apps`
- PVC catalog: `kubernetes/apps/storage`
- Shared components: `kubernetes/components`
- Runbook: `docs/kubernetes-bootstrap.md`

## Scenario 1: Fresh cluster bootstrap (Harbor catch-22)

K3s forces registries through Harbor (`k3s_disable_default_registry_endpoint:
true`). That breaks first bootstrap until Harbor's proxy-cache projects exist.

```bash
# 1. First K3s bring-up WITH upstream fallback
CLUSTER_DOMAIN=<domain> ansible-playbook ansible/playbooks/k3s_cluster.yml \
  -e k3s_disable_default_registry_endpoint=false

# 2. Bootstrap Flux and let production root reconcile
flux reconcile kustomization flux-system --with-source

# 3. Wait for Harbor
flux get kustomizations
flux get helmrelease harbor -n flux-system
kubectl get pods -n harbor

# 4. Manually trigger the harbor-bootstrap CronJob once
kubectl -n harbor create job --from=cronjob/harbor-bootstrap harbor-bootstrap-manual
kubectl -n harbor logs job/harbor-bootstrap-manual

# 5. Verify proxy-cache projects exist: dockerhub, ghcr, lscr, quay, gitea

# 6. Re-run K3s normally to re-lock registry through Harbor
CLUSTER_DOMAIN=<domain> ansible-playbook ansible/playbooks/k3s_cluster.yml
```

During early bootstrap, Harbor SSO is not yet usable; use the `harbor-secrets`
admin credentials.

## Scenario 2: Flux bring-up order

The numbered files in `kubernetes/clusters/production/ks` communicate intent;
`spec.dependsOn` inside each Flux `Kustomization` is the authoritative
dependency graph. Logical order:

1. `cluster-identity` → 2. `infrastructure` → 3. networking/security/automation
→ 4. `longhorn-install` → 5. `longhorn-config` → 6. `cnpg-install` →
7. `harbor-install` → 8. `harbor-config` → 9. `apps-storage` → 10. `apps-manifests`.

```bash
flux get kustomizations
flux get helmreleases -A
flux reconcile kustomization flux-system --with-source   # intentional live step
```

## Scenario 3: PVC restore (Longhorn)

Longhorn backs up to `s3://longhorn@garage/` (configured in
`kubernetes/infrastructure/storage/longhorn/install/helmrelease.yaml`,
credentials in `longhorn-backup-secret`). Backup jobs in
`kubernetes/infrastructure/storage/longhorn/config/recurring-backup-jobs.yaml`
(`backup-daily` retain 14, `backup-weekly` retain 4).

- **Option A — full rebuild**: reconcile Longhorn → verify S3 target/creds →
  restore backups as volumes before workloads mount empty claims → bind PV/PVC
  with original namespace+claim names → reconcile `apps-storage` → reconcile
  `apps-manifests`.
- **Option B — file-level copy**: restore to a temporary PVC, stop the
  workload, mount both into a one-shot copy pod, copy data, restart.
- **Option C — replace damaged PVC**: stop workload, restore to a new Longhorn
  volume, recreate/rebind PVC intentionally, resume workload.

StorageClasses use `Retain`; do not delete PVs unless you intend to discard or
preserve the underlying volume.

### `ssa: IfNotPresent` is a migration contract

For a full reconstruction, **remove**
`kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` from restored/new PVC manifests
before reconciling. It is a create-only migration annotation, not a default;
keeping it hides PVC spec drift. (See `kubernetes/apps/storage/AGENTS.md`.)
If a live PVC already has it and you are only patching that PVC in place, call
out the required manual live step explicitly — do not present the Git change as
self-sufficient.

## Scenario 4: CNPG restore

CloudNativePG backs up via native `barmanObjectStore` in each `Cluster` to
`s3://cloudnative-pg/<app>` with `serverName` like `<cluster>-v1`, retention
`14d`. Current clusters: `authentik-pg` (lives under
`kubernetes/infrastructure/security/authentik/install/authentik-db.yaml`), and
the per-app ones under `kubernetes/apps/apps/**/cnpg-cluster.yaml`:
`airtrail-pg`, `dawarich-pg`, `immich-pg`, `litellm-pg`, `n8n-pg`,
`nextcloud-pg`, `paperless-pg`.

CNPG restore is **not in-place**. Create a new `Cluster` (e.g.
`<app>-pg-restore`) that bootstraps from `recovery.source` referencing an
`externalClusters` entry pointing at the original `barmanObjectStore`. For
point-in-time recovery use timezone-explicit `recoveryTarget.targetTime` (other
options: `targetLSN`, `targetName`, `targetXID`, `targetImmediate`, `backupID`,
`exclusive`, `targetTLI`).

If the restored cluster will write new backups, give it a new `serverName` such
as `<cluster>-v2`. Do not write new WALs into the source cluster's archive
prefix.

For **Immich**, preserve its custom image and VectorChord extension
configuration in the restore cluster.

Reference shape: `docs/kubernetes-bootstrap.md` "CNPG Restore Options".

## Required secrets checklist

- `sops-age` in `flux-system` (SOPS decryption).
- `kubernetes/clusters/production/identity/cluster-identity.sops.yaml`
  (`${CLUSTER_DOMAIN}` etc.).
- Longhorn S3:
  `kubernetes/infrastructure/storage/longhorn/config/longhorn-backup-secret.sops.yaml`
- CNPG S3:
  `kubernetes/infrastructure/database/cloudnative-pg/install/cnpg-backup-s3.sops.yaml`
- App/infrastructure-specific `*.sops.yaml` beside each consumer.

## Validation

```bash
kubectl get nodes
flux get kustomizations
flux get helmreleases -A
kubectl get storageclass
kubectl get volumes -n longhorn-system
kubectl get clusters -A
kubectl get scheduledbackup -A
kubectl get pods -A

# Registry after Harbor
kubectl -n harbor get pods
kubectl -n harbor logs job/harbor-bootstrap-manual
ssh k3s-node-01 'sudo k3s crictl pull ghcr.io/oras-project/oras:v1.2.3'
```

## Troubleshooting (high-signal cases)

- Image pulls fail before Harbor exists → re-run K3s with
  `k3s_disable_default_registry_endpoint=false` until Harbor is bootstrapped.
- Harbor exists but proxy-cache projects missing → run `harbor-bootstrap`
  CronJob manually.
- Large multi-arch image gives manifest/blob errors → prewarm or repair Harbor
  by copying the exact platform manifest into
  `harbor-harbor-registry.harbor.svc.cluster.local:5000/ghcr/<repo>:<tag>`.
- CNPG restore cannot find backups → verify target namespace has
  `cnpg-backup-s3`, and that `destinationPath` + `serverName` match the
  original cluster.
- Restored PVC misbehaves → check for leftover `ssa: IfNotPresent` and whether
  the live PVC spec matches Git.

## References

- `docs/kubernetes-bootstrap.md` (authoritative)
- `kubernetes/clusters/production/AGENTS.md`
- `kubernetes/apps/storage/AGENTS.md` (`IfNotPresent` contract)
- `kubernetes/infrastructure/AGENTS.md`
