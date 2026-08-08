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

The K3s playbook (`ansible/playbooks/k3s_cluster.yml`) enables the embedded
registry by default (`k3s_embedded_registry_enabled: true`) and renders
`/etc/rancher/k3s/registries.yaml` on each node. Direct upstream fallback is also
on by default, so no extra vars are required:

```bash
ansible-playbook ansible/playbooks/k3s_cluster.yml
```

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

## Flux Bring-Up Order

The numbered files in `kubernetes/clusters/production/ks` define the production
reconciliation entrypoints. The important logical order is:

1. `cluster-identity`
2. `infrastructure`
3. networking, security, and automation controllers (MetalLB, Traefik,
   external-dns, cloudflared, kube-replicator, reloader, Authentik, CrowdSec,
   cert-manager)
4. `longhorn-install`
5. `longhorn-config`
6. `cnpg-install`
7. observability (kube-prometheus-stack, metrics-server, Loki, Alloy, Tempo,
   OpenTelemetry Collector)
8. node feature discovery and device plugins
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

For registry validation (embedded peer sharing + direct upstream):

```bash
# Embedded registry flag present on each node's K3s unit
ssh k3s-node-01 'systemctl cat k3s | grep -- --embedded-registry'
# A pull resolves through peer cache or direct upstream
ssh k3s-node-01 'sudo k3s crictl pull ghcr.io/oras-project/oras:v1.2.3'
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
