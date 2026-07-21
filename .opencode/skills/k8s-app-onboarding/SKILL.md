---
name: k8s-app-onboarding
description: >-
  Scaffold a new Kubernetes workload in this repo the way the rest of the fleet
  is wired: bjw-s `app-template` HelmRelease, Kustomize components, SOPS
  secrets, optional CNPG cluster, optional Authentik SSO, optional PVC, parent
  `kustomization.yaml` inclusion, and Renovate image-tag annotation. Use when the
  user says "add/deploy/onboard a new app", "create a HelmRelease for X",
  "deploy container Y to the cluster", or wants to bring up a new service end to
  end. Do NOT use for infrastructure services under
  `kubernetes/infrastructure/`, for the `external-proxy/` direct-YAML shape, or
  for changes confined to a single existing app.
---

# Kubernetes App Onboarding

This repo's workloads follow a single dominant shape. This skill enforces it so
new apps reconcile cleanly through Flux and stay consistent with the fleet.

## When to use

- New deployable workload under `kubernetes/apps/apps/<category>/<app>/`.
- Adding a sidecar HelmRelease, CNPG cluster, or backup job to an existing app.
- Onboarding SSO wiring for an app via Authentik.

Do not use for `kubernetes/infrastructure/` services or `external-proxy/`; those
have different contracts (see `kubernetes/infrastructure/AGENTS.md` and
`kubernetes/apps/apps/AGENTS.md`).

## Inputs to confirm before writing

Ask only what is not obvious from the request:

- app name (lowercase, DNS-safe)
- category: an existing dir under `kubernetes/apps/apps/` (e.g. `ai`, `media`,
  `utils`, `storage`, `automation`, `development`)
- image `repository` and `tag`, plus the registry that should be forced through
  Harbor (docker.io, ghcr.io, lscr.io, quay.io, gitea)
- port + health/readiness path
- persistence needs: none / existing shared PVC / new manually declared PVC /
  controller-managed (CNPG, Longhorn via spec)
- SSO-protected? (Authentik OIDC via `<app>-oidc-secrets.sops.yaml` locally +
  `<app>-sso-secret.sops.yaml` under `kubernetes/infrastructure/security/authentik/install/`
  + optional `middleware-<app>.yaml` under `.../authentik/config/`)
- DB-backed? (per-app CNPG `Cluster` in `cnpg-cluster.yaml`)
- DNS name (default `<app>.lan.${CLUSTER_DOMAIN}`)

## Reference shape

Clone the closest sibling by complexity. Two good references:

- Minimal HTTP app with OIDC + CNPG + manually declared PVC:
  `kubernetes/apps/apps/utils/airtrail/`
- Configmap-mounted patches, sidecar Valkey, initContainer install:
  `kubernetes/apps/apps/ai/litellm/`

### Standard files

```
kubernetes/apps/apps/<category>/<app>/
  helmrelease.yaml        # apiVersion helm.toolkit.fluxcd.io/v2, chart: app-template
  kustomization.yaml      # components: bjw-s-defaults + ingress/traefik-base
  <app>-secrets.sops.yaml # SOPS-encrypted, never plaintext
  cnpg-cluster.yaml       # only if DB-backed (controller-managed storage stays here)
```

### Required bits in every HelmRelease

- `# renovate: datasource=docker depName=<image> registryUrl=<registry>` comment
  directly above `repository:` (required by `renovate.json` custom regex
  managers; without it the tag will not be tracked).
- `ingress.main.annotations`:
  - `external-dns.alpha.kubernetes.io/hostname: <app>.lan.${CLUSTER_DOMAIN}`
  - `gethomepage.dev/enabled: "true"` plus name/description/group/icon
- `persistence.<name>` referencing the PVC `claimName` when a manually declared
  PVC is used.
- Probes (liveness/readiness/startup) — match the sibling's shape.

### `kustomization.yaml` template

The minimal template:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
components:
  - ../../../../components/bjw-s-defaults
  - ../../../../components/ingress/traefik-base
resources:
  - helmrelease.yaml
```

Add to `resources:` based on what the app actually uses. Every SOPS file the
HelmRelease consumes via `secretKeyRef` / `envFrom` must be listed here, and
so must every sidecar manifest. Cross-check against a real sibling's
`kustomization.yaml` — typical conditional entries:

- `- <app>-secrets.sops.yaml` — always, when the HelmRelease reads app secrets.
- `- <app>-oidc-secrets.sops.yaml` — when SSO-protected (Authentik OIDC).
- `- <app>-db-secrets.sops.yaml` — when DB-backed (consumed by CNPG or app).
- `- <app>-credentials.sops.yaml` — when the app needs provider API keys.
- `- cnpg-cluster.yaml` — **when DB-backed**; every DB-backed app in the repo
  includes this (omitting it leaves the `Cluster` unrendered and the app
  deploys without its database).
- `- backup-job.yaml` — when a per-app backup `CronJob` is wanted.

Add `storage/backup-policy` to `components:` only when Longhorn backup labels
are wanted and the workload owns its own PVC semantics.

## Storage split (do not get this wrong)

- Controller-managed storage (e.g. CNPG `Cluster.spec.storage`): stays in the
  app dir, e.g. `cnpg-cluster.yaml`.
- Manually declared PVC for the app: goes in
  `kubernetes/apps/storage/pvcs/<domain>/<app>-pvc.yaml`, named `<app>-pvc.yaml`,
  wired into that domain's parent `kustomization.yaml`. The HelmRelease
  references it by `claimName`.
- Do NOT add `ssa: IfNotPresent` to a new PVC. That annotation is a create-only
  migration contract, not a default (see
  `kubernetes/apps/storage/AGENTS.md`).

## Authentik SSO wiring (when SSO-protected)

1. Local app creds: `<app>-oidc-secrets.sops.yaml` in the app dir with
   `OAUTH_CLIENT_ID` / `OAUTH_CLIENT_SECRET` (or whatever env keys the app
   expects), referenced via `secretKeyRef` in the HelmRelease.
2. Authentik side:
   - `<app>-sso-secret.sops.yaml` under
     `kubernetes/infrastructure/security/authentik/install/` — **required**;
     the OAuth client secret injected into the Authentik HelmRelease.
   - An `<app>-sso` entry in
     `kubernetes/infrastructure/security/authentik/install/blueprint-bootstrap-cm.yaml`
     declaring the Authentik `application` + `oauth2provider` (and any groups
     or property mappings). **Required** — without this entry the issuer has
     no application or provider and
     `https://sso.${CLUSTER_DOMAIN}/application/o/<app>/...` returns nothing.
     Mirror an existing sibling entry (e.g. `airtrail-sso`, `dawarich-sso`).
   - Optional: `middleware-<app>.yaml` under `.../authentik/config/` when a
     Traefik forward-auth middleware is wanted.
   Add each new file to its respective parent `kustomization.yaml`.
3. Endpoints use `https://sso.${CLUSTER_DOMAIN}/application/o/<app>/...`.

## Flux inclusion (easy to forget)

- **The authoritative aggregator is `kubernetes/apps/production/kustomization.yaml`,
  which lists each app directory directly** (one `resources:` entry per app,
  e.g. `- ../apps/utils/airtrail`). Add the new app dir there.
- A category-level `kubernetes/apps/apps/<category>/kustomization.yaml` exists
  only for a few categories (`external-proxy`, `immich`, `nextcloud`,
  `paperless`); most categories have none. If the target category does have
  one, wire it there too — but never assume file presence alone makes the app
  active.
- `kubernetes/apps/production/kustomization.yaml` reconciles via
  `ks/91-apps.yaml` (`apps-manifests`, `prune: true`).
- Storage-side changes reconcile via `ks/90-storage.yaml` (`apps-storage`,
  `prune: true`).
- A new `ks/*.yaml` entry is NOT needed for a normal app — only infrastructure
  services require ordering changes. See `kubernetes/clusters/production/AGENTS.md`.

## Validation (run before claiming done)

```bash
# Render the app and its storage domain
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/apps/apps/<category>/<app> >/dev/null
# Only when a category-level kustomization.yaml exists (most categories don't —
# see "Flux inclusion" above):
[ -f kubernetes/apps/apps/<category>/kustomization.yaml ] && \
  kubectl kustomize --load-restrictor=LoadRestrictionsNone \
    kubernetes/apps/apps/<category> >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/apps/production >/dev/null
[ -n "$PVC_DOMAIN" ] && kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/apps/storage/pvcs/"$PVC_DOMAIN" >/dev/null

# Repo-wide manifest validation + secret/pre-commit policy
scripts/kubeconform.sh
pre-commit run --files kubernetes/apps/apps/<category>/<app>/*
# Only when a manually declared PVC was added:
[ -f kubernetes/apps/storage/pvcs/<domain>/<app>-pvc.yaml ] && \
  pre-commit run --files kubernetes/apps/storage/pvcs/<domain>/<app>-pvc.yaml
```

`pre-commit` will auto-encrypt any new `*.sops.yaml` and stage it; review
`git diff --cached` afterward.

## Anti-patterns

- Adding an app directory without wiring the parent `kustomization.yaml` (file
  presence alone is not active state).
- Putting a manually declared PVC inside the app dir instead of
  `kubernetes/apps/storage/pvcs/<domain>/`.
- Plaintext `Secret` manifests (blocked by pre-commit and CI).
- Forgetting the `# renovate: datasource=...` comment, which silently leaves the
  image tag untracked.
- Adding a `ks/*.yaml` ordering entry for a normal app (not needed).
- Forgetting `external-dns` / Homepage annotations on ingress.

## References

- `CONTRIBUTING.md` Kubernetes section (components, naming, Homepage)
- `kubernetes/apps/apps/AGENTS.md`, `kubernetes/apps/AGENTS.md`,
  `kubernetes/apps/storage/AGENTS.md`, `kubernetes/components/AGENTS.md`
- `renovate.json` `customManagers` (renovate comment contract)
