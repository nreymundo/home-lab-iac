# Kubernetes - AI Assistant Instructions

This document provides instructions for AI agents working with the Kubernetes/Flux GitOps component of the home-lab-iac repository.

## Directory Structure

```
kubernetes/
├── clusters/
│   └── production/               # Production cluster configuration
│       ├── flux-system/          # Flux bootstrap files (DO NOT EDIT)
│       │   └── gotk-sync.yaml    # GitRepository + root Kustomization
│       ├── ks/                   # Kustomization definitions (ordered)
│       │   ├── 00-infrastructure.yaml
│       │   ├── 10-metallb-install.yaml
│       │   ├── ...
│       │   └── 90-apps.yaml
│       └── kustomization.yaml    # Includes flux-system and ks/
├── infrastructure/               # Cluster infrastructure components
│   ├── sources/                  # HelmRepository definitions
│   ├── config/                   # Cluster-wide configuration
│   ├── networking/               # MetalLB, Traefik, external-dns
│   ├── security/                 # Cert-manager, Authentik, Crowdsec
│   ├── storage/                  # Longhorn, NFS shares
│   ├── database/                 # CloudNative-PG
│   └── observability/            # Prometheus, Loki, Alloy
├── apps/                         # Application deployments
│   ├── apps/                     # HelmRelease definitions
│   │   ├── automation/
│   │   ├── media/
│   │   ├── storage/
│   │   └── external-proxy/
│   └── production/
│       └── apps.yaml             # Kustomization for apps
├── components/                   # Reusable Kustomize components
│   ├── bjw-s-defaults/           # Common HelmRelease fields
│   └── nfs-mount/
│       └── media/
│           ├── ro/               # Read-only NFS media mount
│           └── rw/               # Read-write NFS media mount
└── renovate/                     # Renovate configuration
```

## Kustomize Components

Reusable components in `kubernetes/components/` reduce duplication across HelmReleases.

### Available Components

| Component | Path | Purpose |
|-----------|------|---------|
| bjw-s-defaults | `components/bjw-s-defaults` | Adds `interval`, `version`, `sourceRef` for bjw-s app-template |
| traefik-base | `components/ingress/traefik-base` | Sets `enabled: true`, `className: traefik` for `ingress.main` |
| auth-guard | `components/ingress/auth-guard` | Injects Authentik middleware for `ingress.main` |
| backup-policy | `components/storage/backup-policy` | Longhorn daily/weekly backup labels for `persistence.data` and CNPG clusters |
| NFS Media (RW) | `components/nfs-mount/media/rw` | NFS media mount at `/mnt/media` (read-write) + securityContext |
| NFS Media (RO) | `components/nfs-mount/media/ro` | NFS media mount at `/mnt/media` (read-only) + securityContext |
| NFS Backup | `components/nfs-mount/backup` | NFS backup mount at `/backup` |
| arr-custom-scripts | `components/arr-custom-scripts` | Custom scripts volume for *arr applications |

### Usage

Reference components in app's `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
components:
  - ../../../../components/bjw-s-defaults
  - ../../../../components/ingress/traefik-base
  - ../../../../components/storage/backup-policy
  # - ../../../../components/nfs-mount/media/rw  # If NFS media needed
resources:
  - helmrelease.yaml
```

### When to Use

- **bjw-s-defaults**: Always use for apps using bjw-s `app-template` chart. Omit `interval`, `version`, and `sourceRef` from HelmRelease.
- **ingress/traefik-base**: Apps with ingress. Sets `enabled: true` and `className: traefik`.
- **ingress/auth-guard**: Apps requiring Authentik authentication.
- **storage/backup-policy**: Apps with `persistence.data` or CNPG clusters needing Longhorn backups.
- **nfs-mount/media/rw**: Apps that need read-write access to NFS media share.
- **nfs-mount/media/ro**: Apps that only need read access to NFS media share.

NFS components include `defaultPodOptions.securityContext` (runAsUser: 99, runAsGroup: 100, fsGroup: 100) for proper NFS permissions.

## Flux GitOps Model

### Sync Flow
1. Flux watches the GitHub repo (`master` branch)
2. Root Kustomization at `kubernetes/clusters/production/`
3. Kustomizations in `ks/` are applied in numeric order
4. Each Kustomization points to infrastructure or apps directories

### Kustomization Ordering
Files in `ks/` are numbered for dependency ordering:

| Range | Category | Purpose |
|-------|----------|---------|
| 00-09 | Infrastructure base | Sources, config |
| 10-19 | Networking | MetalLB, Traefik |
| 20-29 | Networking config | External-DNS |
| 30-39 | Replication | Kube-replicator |
| 40-49 | Security | Authentik, Crowdsec |
| 50-59 | Certificates | Cert-manager |
| 60-69 | Storage | Longhorn, CNPG, NFS |
| 70-79 | Observability | Prometheus, Loki, Alloy |
| 90-99 | Applications | User apps |

## Key Patterns

### HelmRelease with app-template
Most apps use the bjw-s `app-template` chart:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
  namespace: myapp-namespace
spec:
  interval: 15m
  chart:
    spec:
      chart: app-template
      # renovate: datasource=helm depName=app-template registryUrl=https://bjw-s-labs.github.io/helm-charts/
      version: 4.6.2
      sourceRef:
        kind: HelmRepository
        name: bjw-s
        namespace: flux-system
  values:
    controllers:
      myapp:
        containers:
          app:
            image:
              repository: image/name
              tag: 1.0.0
    service:
      app:
        controller: myapp
        ports:
          http:
            port: 8080
    ingress:
      app:
        enabled: true
        className: traefik
        hosts:
          - host: myapp.lan.${CLUSTER_DOMAIN}
    persistence:
      data:
        enabled: true
        type: persistentVolumeClaim
        storageClass: longhorn-r2
        size: 1Gi
 ```

### Renovate Support

Renovate relies on explicit `# renovate:` comments to track Helm chart versions and image tags.

**Image tags**: add a comment immediately above the `repository`/`tag` block for every image (not just custom registries):

```yaml
# renovate: datasource=docker depName=<image-name> registryUrl=<registry-url>
repository: <registry>/<image-name>
tag: <version>
```

**HelmRelease chart versions**: add a comment immediately above the `version` field:

```yaml
chart:
  spec:
    chart: <chart-name>
    # renovate: datasource=helm depName=<chart-name> registryUrl=<chart-repo-url>
    version: <version>
```

**App-template**: the shared chart version is tracked in
`kubernetes/components/bjw-s-defaults/kustomization.yaml` with the same `# renovate:` pattern.

**Common registries:**
- `docker.gitea.com` → `registryUrl=https://docker.gitea.com`
- `docker.n8n.io` → `registryUrl=https://docker.n8n.io`
- `ghcr.io` → `registryUrl=https://ghcr.io`

### Ingress Conventions
- **Ingress class**: `traefik`
- **Domain pattern**: `<app>.lan.${CLUSTER_DOMAIN}` for internal apps
- **Annotations**:
  - Auth: `traefik.ingress.kubernetes.io/router.middlewares: traefik-gatekeeper-auth-chain@kubernetescrd`
  - DNS: `external-dns.alpha.kubernetes.io/hostname: <fqdn>`

### Homepage Integration
Add `gethomepage.dev/*` annotations to ingress for [Homepage](https://gethomepage.dev) dashboard discovery:

```yaml
# Required annotations
gethomepage.dev/enabled: "true"
gethomepage.dev/name: <App Name>
gethomepage.dev/description: <Short description>
gethomepage.dev/group: <Category>           # Media, Security & Monitoring, Networking, Storage
gethomepage.dev/icon: <app>.png             # From dashboard-icons

# Optional: For widget integration (if app supports it)
gethomepage.dev/widget.type: "<app-type>"
gethomepage.dev/widget.url: "http://<service>.<namespace>.svc.cluster.local:<port>"
gethomepage.dev/widget.key: '{{"{{"}}HOMEPAGE_VAR_<APP>_KEY{{"}}"}}'
```

**Current groups in use:** `Media`, `Security & Monitoring`, `Networking`, `Storage`

### Storage Classes
- `longhorn-r2` - Longhorn with 2 replicas (default for apps)
- `longhorn-r1` - Longhorn with 1 replica (for less critical data)
- NFS via built-in app-template type: `nfs` (see `components/nfs-mount/`)

### Longhorn Backup Labels
Add to PVC labels for automatic backups:
```yaml
labels:
  recurring-job.longhorn.io/backup-daily: enabled
  recurring-job.longhorn.io/backup-weekly: enabled
```

### Postgres Database Backups
For apps using PostgreSQL, create a `db-backup.yaml` alongside the `kustomization.yaml` to backup the database to NFS:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: <app-name>-db-backup
  namespace: <namespace>
spec:
  schedule: "0 2 * * *"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: postgres:17-alpine
              command: ["/bin/sh", "-c"]
              args:
                - |
                  set -eo pipefail
                  BACKUP_DIR="/backup/kubernetes/apps/$APP_NAME"
                  # Use .dump extension and custom format (-Fc)
                  BACKUP_FILE="$BACKUP_DIR/$APP_NAME-$(date +%Y%m%d-%H%M%S).dump"
                  mkdir -p "$BACKUP_DIR"
                  echo "Starting backup for $APP_NAME..."
                  # $APP_NAME will be evaluated by the shell at runtime
                  pg_dump -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -Fc -f "$BACKUP_FILE"
                  echo "Backup created: $BACKUP_FILE"
                  find "$BACKUP_DIR" -name "*.dump" -mtime +14 -delete
                  echo "Cleaned up *.dump backups older than 14 days"
              env:
                - name: APP_NAME
                  value: "<app-name>"
                - name: PGHOST
                  value: "<service-dns>" # e.g., app-pg-rw.namespace.svc.cluster.local
                - name: PGUSER
                  valueFrom:
                    secretKeyRef:
                      name: "<app>-db-secrets"
                      key: username
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: "<app>-db-secrets"
                      key: password
                - name: PGDATABASE
                  value: "<db-name>"
              volumeMounts:
                - name: backup
                  mountPath: /backup
          volumes:
            - name: backup
              nfs:
                server: "${UNRAID_IP}"
                path: /mnt/user/backup
```

**Note on Variables**: Use `$APP_NAME` (no braces) in `args` script so Flux ignores it and lets the shell evaluate it. Use `${UNRAID_IP}` (with braces) so Flux substitutes it.

## How to Add a New App

1. **Create namespace** (if new) in `infrastructure/config/namespaces.yaml`

2. **Create app directory**:
   ```bash
   mkdir -p kubernetes/apps/apps/<category>/<app-name>
   ```

 3. **Create HelmRelease** (`helmrelease.yaml`):
    ```yaml
    apiVersion: helm.toolkit.fluxcd.io/v2
    kind: HelmRelease
    metadata:
      name: <app-name>
      namespace: <namespace>
    spec:
      # ... see pattern above
    ```

 4. **Add Renovate datasource comment** above every image tag (see [Renovate Support](#renovate-support)):

    ```yaml
    # renovate: datasource=docker depName=<image-name> registryUrl=<registry-url>
    repository: <registry>/<image-name>
    tag: <version>
    ```

 5. **Create kustomization.yaml** (with components):
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   components:
     - ../../../../components/bjw-s-defaults
     # Add nfs-mount/media/rw or /ro if app needs NFS media access
   resources:
     - helmrelease.yaml
     # Add db-backup.yaml if using Postgres (see Postgres Database Backups pattern)
     - db-backup.yaml
    ```

 6. **Add to parent kustomization** (`kubernetes/apps/apps/<category>/kustomization.yaml`):
    ```yaml
    resources:
      - <app-name>
    ```

 7. **Commit and push** - Flux will automatically reconcile

## How to Add Infrastructure

1. **Add HelmRepository** (if new chart source) in `infrastructure/sources/`:
   ```yaml
   apiVersion: source.toolkit.fluxcd.io/v1
   kind: HelmRepository
   metadata:
     name: <repo-name>
     namespace: flux-system
   spec:
     interval: 1h
     url: https://charts.example.com
   ```

2. **Create component directory** in appropriate category (`networking/`, `security/`, etc.)

3. **Create HelmRelease + kustomization.yaml**

   Add a `# renovate:` comment above each Helm chart `version` field:

   ```yaml
   chart:
     spec:
       chart: <chart-name>
       # renovate: datasource=helm depName=<chart-name> registryUrl=<chart-repo-url>
       version: <version>
   ```

4. **Add Kustomization** in `clusters/production/ks/` with appropriate number prefix

## Validation

### Dry-run Apply
```bash
kubectl apply --dry-run=client -f kubernetes/apps/apps/media/myapp/
```

### Flux Reconciliation
```bash
# Force immediate reconciliation
flux reconcile kustomization flux-system --with-source

# Check Kustomization status
flux get kustomizations

# Check HelmRelease status
flux get helmreleases -A
```

### Pre-commit
```bash
# YAML validation
pre-commit run yamllint --all-files
pre-commit run check-yaml --all-files
```

## Common Tasks

| Task | Command |
|------|---------|
| Check all resources | `flux get all -A` |
| Force sync | `flux reconcile kustomization flux-system --with-source` |
| Suspend app | `flux suspend helmrelease <name> -n <namespace>` |
| Resume app | `flux resume helmrelease <name> -n <namespace>` |
| View logs | `flux logs --kind=HelmRelease --name=<name>` |
| Check events | `kubectl get events -n <namespace> --sort-by='.lastTimestamp'` |

## Renovate Integration

Renovate is configured to:
- Track HelmRelease chart versions via `# renovate:` comments
- Track app image tags via `# renovate:` comments
- Auto-update minor/patch versions on Sundays
- Group updates (observability, networking)
- Require manual review for major versions and 0.x.x apps

Config file: `/renovate.json`

## Important Notes

1. **Never edit `flux-system/`**: These are Flux bootstrap files

2. **Variable substitution**: Use `${CLUSTER_DOMAIN}`.

3. **Dependency ordering**: Use `dependsOn` in Kustomizations for explicit dependencies

4. **Secrets**: Use SOPS for secrets management, kube-replicator for cross-namespace replication

5. **AI Agent Guidance**: Never run `flux reconcile` commands unless explicitly asked. Flux auto-reconciles on Git push. Manual reconciliation can interfere with deployments.
