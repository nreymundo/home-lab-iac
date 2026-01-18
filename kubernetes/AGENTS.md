# Kubernetes - AI Agent Instructions

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
└── renovate/                     # Renovate configuration
```

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
| 40-49 | Security | Bitwarden, Authentik, Crowdsec |
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

### Ingress Conventions
- **Ingress class**: `traefik`
- **Domain pattern**: `<app>.lan.${CLUSTER_DOMAIN}` for internal apps
- **Annotations**:
  - Auth: `traefik.ingress.kubernetes.io/router.middlewares: traefik-gatekeeper-auth-chain@kubernetescrd`
  - DNS: `external-dns.alpha.kubernetes.io/hostname: <fqdn>`

### Storage Classes
- `longhorn-r2` - Longhorn with 2 replicas (default for apps)
- `longhorn-r1` - Longhorn with 1 replica (for less critical data)
- NFS via PersistentVolumeClaim `nfs-media`, `nfs-downloads`

### Longhorn Backup Labels
Add to PVC labels for automatic backups:
```yaml
labels:
  recurring-job.longhorn.io/backup-daily: enabled
  recurring-job.longhorn.io/backup-weekly: enabled
```

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

4. **Create kustomization.yaml**:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - helmrelease.yaml
   ```

5. **Add to parent kustomization** (`kubernetes/apps/apps/<category>/kustomization.yaml`):
   ```yaml
   resources:
     - <app-name>
   ```

6. **Commit and push** - Flux will automatically reconcile

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
- Detect Flux HelmRelease versions
- Auto-update minor/patch versions on Sundays
- Group updates (observability, networking)
- Require manual review for major versions and 0.x.x apps

Config file: `/renovate.json`

## Important Notes

1. **Never edit `flux-system/`**: These are Flux bootstrap files

2. **Variable substitution**: Use `${CLUSTER_DOMAIN}`.

3. **Dependency ordering**: Use `dependsOn` in Kustomizations for explicit dependencies

4. **Secrets**: Use Bitwarden Secrets Operator or kube-replicator for secret management
