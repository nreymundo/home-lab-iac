# Kubernetes Workload Apps Agent Notes

Read the repo root `AGENTS.md`, `kubernetes/AGENTS.md`, and `kubernetes/apps/AGENTS.md` first. This file only covers deployable workload rules.

## What This Subtree Owns
- `kubernetes/apps/apps/` owns deployable workloads and their workload-local resources.
- The common workload shape is `helmrelease.yaml` + `kustomization.yaml` plus optional secrets and extra resources such as DB clusters, backup jobs, or sidecar HelmReleases.

## Source Of Truth Boundaries
- Workload-local resources that directly travel with an app stay here.
- Manually declared PVC catalogs stay in `kubernetes/apps/storage/`, while controller-managed storage such as `CNPG Cluster.spec.storage` remains workload-local unless a nearer child file documents an exception.
- Shared defaults and shared ingress behavior often come from `kubernetes/components/`, so local app edits may have shared-component dependencies.
- Homepage cards belong directly in `utils/homepage/helmrelease.yaml` under `config.services`; do not use Homepage discovery labels or annotations. For every new card, search https://github.com/homarr-labs/dashboard-icons for an appropriate icon first.
- For Homepage catalog changes, compare the complete card-name set before and after the edit; do not rely on manual counts. Resolve every missing or unexpected card before committing.

## Local Anti-Patterns
- Do not invent a new app scaffold when the existing category already shows a stable pattern.
- When a user names a reference workload, read it before further planning or research.
- For shared app dependencies (Meilisearch, browsers, OIDC, PVC helpers), search sibling workloads and copy the established HelmRelease pattern before designing a new one.
- For native Authentik OIDC, the Authentik `<app>-sso-secret` is the source of the client credentials and must be replicated into the workload namespace. Consume that replica directly with `secretKeyRef`; do not duplicate OAuth client credentials in a workload-local SOPS Secret. A local Secret may retain only app-owned values such as a session-signing secret.
- Decide native OIDC versus Traefik forward-auth from the app's actual capability. A proxy-only app uses the established Gatekeeper middleware chain and does not automatically need an Authentik native provider, `<app>-sso-secret`, or client credentials; add those only when the app also performs its own OIDC flow.
- Do not escalate a local, rebuildable component failure into a PVC deletion, migration, or multi-phase recovery plan when an existing Git-managed app pattern already handles it.
- For a scoped repair, make the smallest source-of-truth change, run the direct validation, and deliver; avoid speculative hardening or unrelated redesign.
- Do not put manually declared PVC definitions here when the persistence belongs in `kubernetes/apps/storage/`.
- Do not overlook sibling resources or Kustomize behavior such as `cnpg-cluster.yaml`, backup jobs, extra HelmReleases, app variants, components, patches, generators, and namespace transforms.
- Do not assume `external-proxy/` follows the normal HelmRelease-heavy pattern; it is intentionally higher-variance and more direct-YAML-oriented.
- For either authentication mode, verify the owning app Kustomization and the production aggregator; file presence alone does not activate a workload or ingress.

## Validation
```bash
kubectl kustomize --load-restrictor=LoadRestrictionsNone kubernetes/apps/apps/<category>/<app> >/dev/null
flux get helmreleases -A
```

- `flux get helmreleases -A` applies only to Helm-managed workloads; validate direct-YAML workloads such as `external-proxy` through the `apps-manifests` Kustomization and their rendered resources.
- Check `kubernetes/apps/production` whenever adding or removing apps, and check storage wiring whenever manually declared PVCs are part of the change.
