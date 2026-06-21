# Kubernetes Bootstrap Runbook

This runbook covers rebuilding the Kubernetes and Flux-managed cluster state from
this repository. It intentionally focuses on `kubernetes/` desired state. VM/node
creation, Terraform, and general host provisioning are out of scope except where
K3s registry mirror settings affect Kubernetes bootstrap.

## Source Of Truth

- Flux root: `kubernetes/clusters/production`
- Flux bootstrap manifests: `kubernetes/clusters/production/flux-system`
- Ordered reconciliation layer: `kubernetes/clusters/production/ks`
- Shared infrastructure manifests: `kubernetes/infrastructure`
- Workload manifests: `kubernetes/apps/apps`
- PVC catalog: `kubernetes/apps/storage`
- Shared components: `kubernetes/components`

Do not hand-edit generated Flux files under
`kubernetes/clusters/production/flux-system` during a normal rebuild. The
hand-maintained ordering layer is `kubernetes/clusters/production/ks`.

## Initial Registry Bootstrap

K3s normally forces configured registries through Harbor with
`k3s_disable_default_registry_endpoint: true`. That is the desired steady state,
but it will break first bootstrap if Harbor and its proxy-cache projects do not
exist yet.

For a fresh cluster, first bring K3s up with direct upstream fallback enabled:

```bash
CLUSTER_DOMAIN=<domain> ansible-playbook ansible/playbooks/k3s_cluster.yml \
  -e k3s_disable_default_registry_endpoint=false
```

Then bootstrap Flux and let the production root reconcile.

Wait for Harbor install and config to exist:

```bash
flux get kustomizations
flux get helmrelease harbor -n flux-system
kubectl get pods -n harbor
```

Harbor SSO will not work until Authentik is up and the Harbor OIDC application
has been configured. During early bootstrap, use the Harbor admin credentials
from `harbor-secrets` for validation and bootstrap jobs instead of relying on
SSO.

Harbor proxy-cache projects are created by `harbor-bootstrap`, which is a
CronJob. On first bootstrap, run it once manually instead of waiting for the next
scheduled run:

```bash
kubectl -n harbor create job --from=cronjob/harbor-bootstrap harbor-bootstrap-manual
kubectl -n harbor logs job/harbor-bootstrap-manual
```

Verify the proxy-cache projects exist before disabling upstream fallback again:

- `dockerhub`
- `ghcr`
- `lscr`
- `quay`
- `gitea`

After Harbor is working, re-run the K3s playbook normally so nodes return to the
secure steady state where mirrored registries cannot bypass Harbor:

```bash
CLUSTER_DOMAIN=<domain> ansible-playbook ansible/playbooks/k3s_cluster.yml
```

Validate that each node's K3s service includes
`--disable-default-registry-endpoint` and that a test image pulls through Harbor.

## Flux Bring-Up Order

The numbered files in `kubernetes/clusters/production/ks` define the production
reconciliation entrypoints. The important logical order is:

1. `cluster-identity`
2. `infrastructure`
3. networking, security, and automation controllers
4. `longhorn-install`
5. `longhorn-config`
6. `cnpg-install`
7. `harbor-install`
8. `harbor-config`
9. `apps-storage`
10. `apps-manifests`

Use `dependsOn` inside each Flux `Kustomization` as the authoritative dependency
graph. Numeric filename order communicates intent, but some entries depend on
later-numbered services.

Useful commands:

```bash
flux get kustomizations
flux get helmreleases -A
flux reconcile kustomization flux-system --with-source
```

## Required Secrets

At minimum, a rebuild needs these secret paths or live secrets available at the
right time:

- `sops-age` in `flux-system`, required for SOPS decryption.
- `kubernetes/clusters/production/identity/cluster-identity.sops.yaml`, used for
  `${CLUSTER_DOMAIN}` and other substitutions.
- Longhorn S3 backup credentials:
  `kubernetes/infrastructure/storage/longhorn/config/longhorn-backup-secret.sops.yaml`
- CNPG S3 backup credentials:
  `kubernetes/infrastructure/database/cloudnative-pg/install/cnpg-backup-s3.sops.yaml`
- App-specific SOPS secrets beside each app or infrastructure service.

## PVC Restore Options

Longhorn is the repo-backed PVC backup mechanism. There are no VolSync restore
manifests in this repository.

Longhorn backup target:

- `s3://longhorn@garage/`
- configured in `kubernetes/infrastructure/storage/longhorn/install/helmrelease.yaml`
- credentials from `longhorn-backup-secret`

Backups are label-driven by recurring jobs in
`kubernetes/infrastructure/storage/longhorn/config/recurring-backup-jobs.yaml`:

- daily: `backup-daily`, `0 3 * * *`, retain `14`
- weekly: `backup-weekly`, `0 4 * * 0`, retain `4`

### Option A: Restore Before Apps Start

Use this for a full rebuild.

1. Reconcile Longhorn install/config.
2. Verify the Garage S3 backup target and credentials work.
3. Restore Longhorn backups as volumes before workloads mount empty claims.
4. Create or bind PV/PVCs with the original namespace and claim names.
5. Reconcile `apps-storage`.
6. Reconcile `apps-manifests`.

### Option B: Restore To A Temporary PVC And Copy

Use this for partial or file-level recovery.

1. Restore the Longhorn backup to a temporary PVC/name.
2. Stop or suspend the consuming workload if needed.
3. Mount both the restored PVC and target PVC into a one-shot copy pod.
4. Copy the required data.
5. Restart the workload and validate the application.

### Option C: Replace A Damaged PVC

Use this when the existing claim is unusable.

1. Stop or suspend the consuming workload.
2. Restore the backup to a new Longhorn volume.
3. Recreate or rebind the PVC intentionally.
4. Resume the workload and validate.

Longhorn StorageClasses in this repo use `Retain`, so avoid deleting PVs unless
you explicitly intend to preserve or discard the underlying volume.

### Full Reconstruction And `IfNotPresent`

For full cluster reconstruction from scratch, remove
`kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` from restored or new PVC
manifests before reconciling them.

Those annotations were used for previous PVC migration and create-only cases.
They are not needed when rebuilding a fresh cluster from Git plus backups.
Keeping them can hide future PVC spec drift because Flux will avoid updating
existing claims. The source-of-truth note in `kubernetes/apps/storage/AGENTS.md`
also treats `IfNotPresent` as a special migration contract, not a normal default
for new PVCs.

## CNPG Restore Options

CloudNativePG database backups use native `barmanObjectStore` configuration in
each `Cluster`. Current database clusters include:

- `authentik-pg` in `authentik`
- `n8n-pg` in `automation`
- `nextcloud-pg` in `nextcloud`
- `paperless-pg` in `paperless`
- `immich-pg` in `immich`
- `litellm-pg` in `ai`

Each cluster backs up to `s3://cloudnative-pg/<app>` with a `serverName` like
`<cluster>-v1` and retention `14d`.

CNPG restore is not an in-place operation. Prefer creating a new restored
Cluster, validating it, then cutting the application over or replacing the old
cluster intentionally through GitOps.

Example recovery shape matching this repository:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <app>-pg-restore
  namespace: <namespace>
spec:
  instances: 1
  bootstrap:
    recovery:
      source: origin
      database: <database>
      owner: <owner>
      secret:
        name: <db-secret>
      # Optional PITR target:
      # recoveryTarget:
      #   targetTime: "2026-06-21T12:00:00Z"
  externalClusters:
    - name: origin
      barmanObjectStore:
        destinationPath: s3://cloudnative-pg/<app>
        endpointURL: https://s3.${CLUSTER_DOMAIN}
        serverName: <original-serverName>
        s3Credentials:
          accessKeyId:
            name: cnpg-backup-s3
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: cnpg-backup-s3
            key: SECRET_ACCESS_KEY
        wal:
          maxParallel: 8
```

For point-in-time recovery, use timezone-explicit targets. Common options are
`targetTime`, `targetLSN`, `targetName`, `targetXID`, `targetImmediate`,
`backupID`, `exclusive`, and `targetTLI`.

If the restored cluster will also create new backups, give it a new backup
`serverName`, such as `<cluster>-v2`. Do not write new WALs into the same archive
prefix as the source cluster.

For Immich, preserve its custom image and extension configuration when creating a
restore cluster because the app uses VectorChord-related PostgreSQL extensions.

## Validation Checklist

```bash
kubectl get nodes
flux get kustomizations
flux get helmreleases -A
kubectl get storageclass
kubectl get volumes -n longhorn-system
kubectl get clusters -A
kubectl get scheduledbackup -A
kubectl get pods -A
```

For registry validation after Harbor is ready:

```bash
kubectl -n harbor get pods
kubectl -n harbor logs job/harbor-bootstrap-manual
ssh k3s-node-01 'sudo k3s crictl pull ghcr.io/oras-project/oras:v1.2.3'
```

## Troubleshooting

- Image pulls fail before Harbor exists: re-run K3s with
  `-e k3s_disable_default_registry_endpoint=false` until Harbor is bootstrapped.
- Harbor exists but proxy-cache projects are missing: run `harbor-bootstrap`
  manually from the CronJob.
- Harbor proxy-cache gives manifest or blob errors for a large multi-arch image:
  prewarm or repair Harbor by copying the exact platform manifest into
  `harbor-harbor-registry.harbor.svc.cluster.local:5000/ghcr/<repo>:<tag>`.
- CNPG restore cannot find backups: verify the target namespace has
  `cnpg-backup-s3`, and confirm `destinationPath` plus `serverName` match the
  original cluster.
- Restored PVC does not behave as expected: check whether the manifest still has
  `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` and whether the live PVC spec
  matches Git.
