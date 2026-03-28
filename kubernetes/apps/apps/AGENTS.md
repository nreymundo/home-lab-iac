# APPLICATION DEPLOYMENTS KNOWLEDGE BASE

## OVERVIEW
`kubernetes/apps/apps/` contains deployable workloads, mostly category-grouped folders plus a few standalone app roots such as `immich/`, `nextcloud/`, and `paperless/`.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Standard app deployment | `<category>/<app>/helmrelease.yaml` | Main workload definition |
| App composition | `<category>/<app>/kustomization.yaml` | Pulls in components and local resources |
| DB-backed apps | `*/cnpg-cluster.yaml` | Per-app CloudNativePG clusters |
| Special high-variance subtree | `external-proxy/` | Many small service YAMLs under one umbrella |

## CONVENTIONS
- Common shape: `helmrelease.yaml` + `kustomization.yaml` + optional `*.sops.yaml` and extra resources.
- Standard components often include `../../../components/bjw-s-defaults` and `.../ingress/traefik-base`.
- Hostnames and ingress rules usually follow `*.lan.${CLUSTER_DOMAIN}`.
- Some apps bundle related satellites in the same folder, e.g. Paperless variants or Discord Presence main/alternate trees.

## ANTI-PATTERNS
- Do not invent a different app scaffold when the existing category already shows a stable pattern.
- Do not put PVC definitions here when the persistent storage belongs in `kubernetes/apps/storage/`.
- Do not overlook sibling resources like `cnpg-cluster.yaml`, backup jobs, or extra HelmReleases in multi-part apps.

## COMMANDS
```bash
kubectl apply --dry-run=client -f kubernetes/apps/apps/<category>/<app>
flux get helmreleases -A
```

## NOTES
- `external-proxy/` is intentionally different: many direct service YAMLs, minimal HelmRelease pattern.
- Check parent production kustomizations whenever adding or removing apps.
