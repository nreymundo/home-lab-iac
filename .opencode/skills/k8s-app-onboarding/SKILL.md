---
name: k8s-app-onboarding
description: >-
  Onboard a new Kubernetes workload with this repo's app-template, Kustomize,
  SOPS, persistence, ingress, authentication, and Flux-inclusion contracts. Use
  when the user says "add/deploy/onboard a new app", "create a HelmRelease for
  X", "deploy container Y to the cluster", or asks to bring up a service end to
  end. Do NOT use for infrastructure services, the `external-proxy/`
  direct-YAML shape, a change confined to one existing app, or an Authentik-only
  provider/client change (use `authentik-oidc-app-change`).
---

# Kubernetes App Onboarding

This repo's workloads follow a dominant shape, with documented exceptions. Use
the closest working sibling and trace every inclusion boundary so a new app
reconciles cleanly through Flux without silently creating or deleting resources.

## When to use

- New deployable workload under `kubernetes/apps/apps/<category>/<app>/`.
- Adding a sidecar HelmRelease, CNPG cluster, or backup job to an existing app.
- Onboarding the workload side of native Authentik OIDC or Authentik
  forward-auth.

Do not use for `kubernetes/infrastructure/` services or `external-proxy/`; those
have different contracts (see `kubernetes/infrastructure/AGENTS.md` and
`kubernetes/apps/apps/AGENTS.md`).

## Inputs to confirm before writing

Ask only what is not obvious from the request:

- app name (lowercase, DNS-safe)
- category: an existing dir under `kubernetes/apps/apps/` (e.g. `ai`, `media`,
  `utils`, `storage`, `automation`, `development`)
- image `repository` and `tag`, plus the upstream registry it comes from
  (docker.io, ghcr.io, lscr.io, quay.io, gitea). Pulls resolve through the K3s
  embedded registry peer cache, then direct
  upstream. `docker.io` images may need per-node Docker Hub auth, which is a
  manual post-Ansible step (see `docs/kubernetes-bootstrap.md`).
- port + health/readiness path
- persistence needs: none / existing shared PVC / new manually declared PVC /
  controller-managed (CNPG, Longhorn via spec)
- authentication: none, native OIDC, Authentik forward-auth, or a documented
  runtime-reconciliation exception. Native Authentik OIDC uses the replicated
  `<app>-sso-secret` from `kubernetes/infrastructure/security/authentik/install/`;
  do not assume an app-local `<app>-oidc-secrets.sops.yaml`. That local filename
  is conditional and is only for app-owned or explicitly established transformed
  values, never a duplicate of `CLIENT_ID` / `CLIENT_SECRET`. A
  `middleware-<app>.yaml` under `.../authentik/config/` is for forward-auth only.
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
- Homepage cards are maintained centrally in
  `kubernetes/apps/apps/utils/homepage/helmrelease.yaml` under
  `config.services`; do not add mandatory `gethomepage.dev/*` discovery
  annotations to the app ingress. Follow the nearest
  `kubernetes/apps/apps/AGENTS.md` guidance, including complete card-set review
  and an appropriate dashboard icon.
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

Add to `resources:` based on what the app actually owns. Every workload-local
SOPS file the HelmRelease consumes via `secretKeyRef` / `envFrom` must be
listed here, as must every sidecar manifest. An Authentik SSO Secret is instead
listed under the Authentik install Kustomization and replicated to this
namespace. Cross-check against a real sibling's `kustomization.yaml` — typical
conditional entries:

- `- <app>-secrets.sops.yaml` — always, when the HelmRelease reads app secrets.
- Do not add a local `<app>-oidc-secrets.sops.yaml` for a native Authentik OIDC
  client; consume the replicated `<app>-sso-secret` instead. Add an app-local
  OIDC-named Secret only when the chosen sibling proves it is needed for
  app-owned or transformed values, and never copy the Authentik client keys.
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

## Authentication shapes

Choose one of these contracts explicitly. Do not combine them because a
workload happens to appear behind the same Traefik entrypoint.

### Native OIDC

Use this when the application performs its own OIDC login and has OIDC
environment/configuration. Start with a complete native-OIDC sibling and read
the nearest `kubernetes/infrastructure/security/authentik/AGENTS.md` and
`kubernetes/apps/apps/AGENTS.md`; do not infer the contract from one manifest.

1. The Authentik source Secret
   `<app>-sso-secret.sops.yaml` under
   `kubernetes/infrastructure/security/authentik/install/` is required. It is
   in namespace `authentik`, contains `CLIENT_ID` / `CLIENT_SECRET`, and sets
   `replicator.v1.mittwald.de/replicate-to: <workload namespace>`.
2. Include that source Secret in the Authentik install Kustomization and inject
   it into the Authentik HelmRelease as `<APP>_CLIENT_ID` and
   `<APP>_CLIENT_SECRET` for the blueprint provider.
3. Reference the replicated `<app>-sso-secret` directly from the workload with
   `secretKeyRef` (or a projected Secret for a runtime job), using its
   `CLIENT_ID` / `CLIENT_SECRET` keys. Do not create a workload-local copy of
   those credentials. A local Secret is limited to app-owned values.
4. Add the `<app>-sso` application/provider entry in
   `kubernetes/infrastructure/security/authentik/install/blueprint-bootstrap-cm.yaml`
   and all Authentik-side files to their parent Kustomization. Use the exact
   sibling callback and issuer expression; do not infer a URL from a rendered
   hostname.
5. For provider/application-only edits, use
   `authentik-oidc-app-change`; this skill owns the workload scaffold and its
   consumer wiring rather than duplicating that provider workflow.

### Authentik forward-auth

Use this when the application has no native OIDC flow and Traefik should gate
the route. Do not create an OIDC client Secret just to put the app behind
forward-auth. Copy a complete forward-auth sibling, add the app-specific
`middleware-<app>.yaml` under `kubernetes/infrastructure/security/authentik/config/`
only when one is needed, reference the middleware from the app ingress, and add
the file to `config/kustomization.yaml`. The middleware's Authentik outpost,
response headers, and namespace are part of the contract; do not replace this
with Homepage claim authorization or an invented local middleware shape.

### Runtime-reconciliation exception

This is an implementation exception, not a third authentication mechanism. Use
it only when the application exposes no declarative/idempotent config path and a
small workload-local Job/CronJob must reconcile state after the controller is
running. `kubernetes/apps/apps/nextcloud/oidc-reconcile-cronjob.yaml` is the
reference: it still consumes the replicated `nextcloud-sso-secret`, uses narrow
namespace RBAC, and is included by the app Kustomization. Document the reason,
retry/idempotency behavior, secret delivery, and exact owning resource; never
turn a runtime job into a substitute for the Git source of truth.

## Shared cluster contracts

- **Source catalog:** shared `HelmRepository` definitions are owned by
  `kubernetes/infrastructure/sources/` and referenced from `flux-system`. Search
  that catalog before adding a source; do not duplicate a repository in an app
  directory. App-template defaults come from the existing `bjw-s` source and
  `bjw-s-defaults` component.
- **NetworkPolicy:** there is no default app NetworkPolicy pattern in
  `kubernetes/apps/apps/`. Do not invent one in every new scaffold. Add a policy
  only for an explicit workload requirement, copying a close security/infrastructure
  sibling and including it in the correct Kustomization.
- **TLS:** standard app ingress uses the shared Traefik component and cluster
  behavior: HTTP redirects to `websecure`, TLS is enabled there, and Traefik's
  default TLSStore in
  `kubernetes/infrastructure/networking/traefik/config/tls-store.yaml` serves
  `wildcard-cluster-domain-tls`. Do not add per-app `tls` blocks or certificates
  unless the app has a documented certificate or hostname exception.
- **Backups:** no persistence means no app backup resource. For a CNPG-backed
  database, keep the `Cluster` local and follow the sibling's CNPG object-store
  backup/PITR configuration. For a Longhorn PVC, use the
  `storage/backup-policy` component only when the primary key is `persistence.data`;
  non-standard keys need explicit labels copied from a sibling. Add a per-app
  backup CronJob only when the app needs an export/filesystem backup that volume
  snapshots or CNPG do not provide. Do not add every backup mechanism by default.
- **Homepage:** the source of truth for cards is
  `kubernetes/apps/apps/utils/homepage/helmrelease.yaml` under
  `config.services`. Add or update the card there, compare the complete card-name
  set before and after, and do not add `gethomepage.dev/*` discovery annotations
  to new app ingresses.

## Exceptional app shapes

- `kubernetes/apps/apps/external-proxy/` is direct YAML, not the normal
  app-template HelmRelease shape; do not scaffold it here.
- Category-level roots such as `immich`, `nextcloud`, and `paperless` can own
  sidecars, CNPG resources, export/backup Jobs, or runtime reconciliation. App
  variants such as `discord-presence/main` and `alternate` also need their local
  parent wiring checked.
- Multi-controller apps (for example a main service plus a database/search/
  browser sidecar) need separate services, probes, persistence mounts, and
  resource entries copied from a matching sibling rather than the minimal
  single-container template.

## Inclusion and prune safety

`kubernetes/apps/production` is reconciled as `apps-manifests` with `prune: true`
and `kubernetes/apps/storage/production` as `apps-storage` with `prune: true`.
Removing an app or resource from a parent Kustomization can therefore delete
the rendered object; file presence alone is not active state. Before removing
or renaming anything, inspect the parent inclusion, both rendered paths when
storage is involved, and the expected removal in the diff. A normal new app
needs an entry in `kubernetes/apps/production/kustomization.yaml`; it does not
need a new `ks/*.yaml` ordering object.

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
# When Authentik install or config files changed:
[ -d kubernetes/infrastructure/security/authentik/install ] && \
  kubectl kustomize --load-restrictor=LoadRestrictionsNone \
    kubernetes/infrastructure/security/authentik/install >/dev/null
[ -d kubernetes/infrastructure/security/authentik/config ] && \
  kubectl kustomize --load-restrictor=LoadRestrictionsNone \
    kubernetes/infrastructure/security/authentik/config >/dev/null

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
- Plaintext `Secret` manifests (blocked by the local `prevent-plaintext-k8s-secrets`
  pre-commit hook; treat that hook as a safety net, not as proof that secret
  ownership and consumer wiring are correct).
- Forgetting the `# renovate: datasource=...` comment, which silently leaves the
  image tag untracked.
- Adding a `ks/*.yaml` ordering entry for a normal app (not needed).
- Forgetting the external-dns hostname, or trying to maintain Homepage cards
  with discovery annotations instead of editing its central `config.services`
  catalog.

## References

- `CONTRIBUTING.md` Kubernetes section (components, naming, Homepage)
- `kubernetes/apps/apps/AGENTS.md`, `kubernetes/apps/AGENTS.md`,
  `kubernetes/apps/storage/AGENTS.md`,
  `kubernetes/infrastructure/security/authentik/AGENTS.md`,
  `kubernetes/components/AGENTS.md`
- `renovate.json` `customManagers` (renovate comment contract)
