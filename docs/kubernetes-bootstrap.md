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

## Registry: Embedded Peer Sharing And Direct Upstream

Image pulls resolve in two layers:

1. **Embedded registry peer sharing** — every node runs the K3s embedded
   registry (`--embedded-registry`, from `k3s_embedded_registry_enabled` in
   `ansible/roles/k3s/defaults/main.yml`), which serves that node's locally
   cached images to peer nodes. Peer pulls run over inter-node TCP `5001`; see
   the firewall requirements in [SECURITY.md](../SECURITY.md).
2. **Direct upstream fallback** — when no peer has the image, K3s pulls directly
   from the upstream registry (for example `registry-1.docker.io`). The K3s role
   does not pass `--disable-default-registry-endpoint`, so this fallback is on by
   default with no extra configuration.

### Bring-Up

The K3s role enables the embedded
registry by default (`k3s_embedded_registry_enabled: true`) and renders
`/etc/rancher/k3s/registries.yaml` on each node. Direct upstream fallback is also
on by default, so no extra vars are required:

```bash
cd ansible
ansible-playbook playbooks/k3s_bootstrap.yml
```

Use `playbooks/k3s_cluster.yml --limit <new-server>` for an existing-cluster
join. Fresh bootstrap is explicit and rejects existing datastores. See
[K3s provisioning](k3s-provisioning.md) for host/storage preparation,
administrative access and rolling upgrades.

Mirror configuration is the wildcard `k3s_registry_mirrors: { "*": {} }` in
`ansible/roles/k3s/defaults/main.yml`, which lets the embedded registry intercept
all pulls without forcing specific endpoints or rewrites, and lets any miss fall
through to upstream. The K3s role no longer requires `CLUSTER_DOMAIN` for mirror
rendering. After the run, confirm the rendered `/etc/rancher/k3s/registries.yaml`
on a node shows only the wildcard mirror.

### Docker Hub Node Authentication Is Manual

Ansible intentionally renders no registry credentials — the K3s role prints a
reminder to configure them (see the comment block in
`ansible/roles/k3s/templates/registries.yaml.j2`). When direct upstream fallback
pulls from `docker.io`, per-node Docker Hub authentication avoids anonymous rate
limits. Configure it manually on each node after the K3s playbook runs, using
the standard K3s `configs.docker.io.auth` block in that node's
`/etc/rancher/k3s/registries.yaml`.

- Do not commit credentials to this repository, and do not store them in SOPS or
  any other Git-tracked file.
- The K3s role preserves any existing node-local `configs:` block in
  `/etc/rancher/k3s/registries.yaml` across runs, so the manual auth does not
  need to be reapplied after each Ansible run.

## Bootstrap Flux and sequence recovery

The generated [sync manifest](../kubernetes/clusters/production/flux-system/gotk-sync.yaml)
tracks `master` and points the root `flux-system` Kustomization at
`./kubernetes/clusters/production`. On a fresh cluster, bootstrap Flux with
authorized GitHub access using the repository, branch, and path from that
manifest. Applying the generated YAML alone does not provision the Git source
credential. `flux reconcile` is not a substitute for bootstrap.

For the GitHub repository in the sync manifest, run the following **live**
bootstrap from an authorized admin workstation with the new cluster selected
and GitHub credentials supplied outside Git. For a restore, first prepare
the recovery gates below on the tracked branch.

```bash
flux bootstrap github --owner=nreymundo --repository=home-lab-iac \
  --personal --token-auth --branch=master --path=kubernetes/clusters/production
```

**Recovery planning (Git):** Before allowing production reconciliation, stage
the recovery configuration. Gate `apps-storage` and `apps-manifests` with
`spec.suspend: true` while preparing restored volumes and database definitions;
do not remove entries from `ks/kustomization.yaml` as a pause mechanism. The
root prunes removed entries. Authentik's database belongs to `authentik-install`,
not the app layer; gate that install separately if restoring its database.

Read [the production inclusion list](../kubernetes/clusters/production/ks/kustomization.yaml)
and each entry's `spec.dependsOn`, `wait`, and `healthChecks`. This is a graph,
not a serial rollout ordered by filename. Key paths are:

| Reconciler | Direct dependencies |
| --- | --- |
| `infrastructure` (sources and namespaces) | `cluster-identity` |
| `longhorn-config` | `cluster-identity`, `longhorn-install` |
| `observability-kube-prometheus-stack-install` | `cluster-identity`, `longhorn-config` |
| `cnpg-install` | `cluster-identity`, `infrastructure`, Prometheus stack install |
| `metallb-config` | `cluster-identity`, `metallb-install`, Prometheus stack install |
| `traefik-install` | `cluster-identity`, `metallb-config` |
| `traefik-config` | `cluster-identity`, `traefik-install` |
| `authentik-install` | `cluster-identity`, Prometheus stack install |
| `authentik-config` | `cluster-identity`, `authentik-install`, `traefik-config` |
| `apps-storage` | `cluster-identity`, `longhorn-config` |
| `apps-manifests` | `cluster-identity`, `apps-storage`, `traefik-config` |

Before releasing consumers, verify CNPG CRDs/operator, replicated Secrets, and
any required DNS, Authentik, or GPU services separately: app Flux readiness
does not gate all these dependencies. NetBird is intentionally excluded.
On a fresh rebuild, Authentik also consumes the Camofox Secret replicated
from `utils`. If workloads are gated, arrange for that app-owned Secret to
be delivered before expecting Authentik to become ready; do not duplicate
the credential or wait on Authentik as a prerequisite for the entire app inventory.

Read-only status: `flux get sources git -A`, `flux get kustomizations -A`, and
`flux get helmreleases -A`. Running
`flux reconcile kustomization flux-system --with-source` deliberately applies
committed state to the live cluster; use it only as an intended rollout step.

## Required Secrets

At minimum, a rebuild needs these secret paths or live secrets available at the
right time:

- Live `flux-system` Git source Secret in namespace `flux-system`, provisioned
  by bootstrap, and `sops-age` in the same namespace, provisioned separately
  with the matching Age private key before decrypting Flux inventories.
- `kubernetes/clusters/production/identity/cluster-identity.sops.yaml`, used for
  `${CLUSTER_DOMAIN}` and other substitutions.
- Longhorn S3 backup credentials:
  `kubernetes/infrastructure/storage/longhorn/config/longhorn-backup-secret.sops.yaml`
- CNPG S3 backup credentials:
  `kubernetes/infrastructure/database/cloudnative-pg/install/cnpg-backup-s3.sops.yaml`
- App-specific SOPS secrets beside each app or infrastructure service.

Git does not contain backup contents. Verify the external Garage S3 endpoint,
DNS/TLS, buckets, and credentials before attempting recovery. The CNPG source
Secret is delivered by kube-replicator; verify `cnpg-backup-s3` in the database
namespace without printing its values.

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

Use for a full rebuild. Keep the storage and workload inventories gated as
described above so dynamic provisioning does not win the race.

1. **GitOps:** Bring up Longhorn install/config and verify the Garage backup
   target, credentials, and available restore points.
2. **Live/manual:** Restore volumes and prebind PV/PVCs to the original
   namespace and claim names. Match class, capacity, access mode, and restored
   volume handle to the intended claim; confirm it binds to the restored PV.
3. **GitOps:** Release `apps-storage` and verify claims remain correctly bound.
4. **GitOps:** Release `apps-manifests` only after storage and database recovery
   definitions are ready. Validate restored data before exposing traffic.

### Option B: Restore To A Temporary PVC And Copy

Use this for partial or file-level recovery.

1. **Live/manual:** Restore the Longhorn backup to a temporary PVC.
2. **GitOps:** Pause the consumer so it cannot write during recovery.
3. **Live/manual:** Mount both claims in a one-shot copy pod, copy the
   required data with its ownership and permissions, and remove the pod.
4. **GitOps:** Resume the consumer and validate the application.

### Option C: Replace A Damaged PVC

Use this when the existing claim is unusable.

1. **GitOps:** Pause the consumer; account for the claim's Flux owner before
   replacing the live PVC so it is not dynamically recreated mid-restore.
2. **Live/manual:** Restore the backup to a new Longhorn volume and prebind
   the intended claim to it.
3. **GitOps:** Resume inventory reconciliation and verify the claim binds to
   the restored volume before resuming the consumer. Validate the application.

`longhorn-r1` and `longhorn-r2` use `Retain`; the separate `local-path` class
uses `Delete` and is not recovered from Longhorn backups. `Retain` does not
prevent Flux from pruning an omitted claim.

External NFS content (for example, Immich and Jellyfin media mounts) is not
part of the app PVC catalog. Restore or reconnect those exports separately.

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

The production inclusion chains contain the following CNPG clusters.
All use native `barmanObjectStore`, `https://s3.${CLUSTER_DOMAIN}`, 21-day
retention, and a weekly Sunday midnight `ScheduledBackup`. The bucket is
`s3://cloudnative-pg/`; append the prefix below.

| Namespace | Cluster | Prefix | Current backup serverName |
| --- | --- | --- | --- |
| `ai` | `audiomuse-pg` | `audiomuse` | `audiomuse-pg-v1` |
| `ai` | `hindsight-pg` | `hindsight` | `hindsight-pg-v1` |
| `ai` | `litellm-pg` | `litellm` | `litellm-pg-v1` |
| `ai` | `open-webui-pg` | `open-webui` | `open-webui-pg-v1` |
| `authentik` | `authentik-pg` | `authentik` | `authentik-pg-v1` |
| `automation` | `n8n-pg` | `n8n` | `n8n-pg-v1` |
| `comms` | `mailflow-pg` | `mailflow` | `mailflow-pg-v2` |
| `immich` | `immich-pg` | `immich` | `immich-pg-v1` |
| `lifestyle` | `airtrail-pg` | `airtrail` | `airtrail-pg-v4` |
| `lifestyle` | `dawarich-pg` | `dawarich` | `dawarich-pg-v4` |
| `lifestyle` | `sparkyfitness-pg` | `sparkyfitness` | `sparkyfitness-pg-v4` |
| `media` | `bookorbit-pg` | `bookorbit` | `bookorbit-pg-v1` |
| `media` | `scrob-pg` | `scrob` | `scrob-pg-v1` |
| `nextcloud` | `nextcloud-pg` | `nextcloud` | `nextcloud-pg-v1` |
| `paperless` | `paperless-pg` | `paperless` | `paperless-pg-v1` |
| `reddit` | `apollo-pg` | `apollo` | `apollo-pg-v1` |

Mailflow and the three lifestyle clusters already declare recovery from older
archives. Do not replay those historical bootstrap settings blindly: confirm
which archive holds the desired backup and WALs. The table lists write archives,
not proof of successful backups. Authentik is defined in `authentik/install/authentik-db.yaml`
under `kubernetes/infrastructure/security/`; the other clusters live with their
apps (`apollo-pg` under `reddit/apollo-backend`).

Immich and n8n also include `db-backup.yaml` CronJobs. They run `pg_dump`
daily at 02:00, write custom-format dumps to NFS on `${UNRAID_IP}`, and
prune old dumps with `find -mtime +14`. These are separate logical backups,
not CNPG recovery sources or WAL archives. Check the NFS export and dump
availability separately if using them for recovery.

CNPG restore is not an in-place operation. Prefer creating a new restored
Cluster, validating it, then cutting the application over or replacing the old
cluster intentionally through GitOps.

Example recovery shape matching this repository:

Use this as a fragment, not a complete manifest. Copy required storage,
PostgreSQL image/version, extensions, resources, and database credentials from
the owning Cluster. Before cutover verify recovery and application queries,
then update consumers and the backup schedule to target the restored cluster.

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

If the restored cluster will write backups, give it a new, unused backup
`serverName`. Do not write WALs into the archive used as the recovery source.
Preserve Immich's VectorChord image and extension configuration, and Open
WebUI's pgvector support. Database recovery does not restore the apps' separate
file PVCs; choose compatible restore points where both stores matter.

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

For registry validation (embedded peer sharing + direct upstream):

```bash
# Embedded registry flag present on each node's K3s unit
ssh k3s-node-02 'systemctl cat k3s | grep -- --embedded-registry'
# A pull resolves through peer cache or direct upstream
ssh k3s-node-02 'sudo k3s crictl pull ghcr.io/oras-project/oras:v1.2.3'
```

## Troubleshooting

- Image pulls fail with no peer cache and no upstream: confirm the node's K3s
  unit includes `--embedded-registry` and that inter-node TCP `5001` is reachable
  so peers can share cached images. Direct upstream fallback is on by default; if
  a pull still fails, check upstream reachability and Docker Hub rate limits.
- `docker.io` pulls hit rate limits (HTTP 429): apply per-node Docker Hub auth
  manually in `/etc/rancher/k3s/registries.yaml`; Ansible does not manage it.
- CNPG restore cannot find backups: verify the target namespace has
  `cnpg-backup-s3`, and confirm `destinationPath` plus `serverName` match the
  original cluster.
- Restored PVC does not behave as expected: check whether the manifest still has
  `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` and whether the live PVC spec
  matches Git.
