# Authentik Agent Notes

Read the repo root `AGENTS.md`, `kubernetes/AGENTS.md`, and
`kubernetes/infrastructure/AGENTS.md` first. This subtree owns Authentik
providers, applications, blueprints, and their source credentials.

## Authentication Mode

Choose native OIDC versus Traefik forward-auth before creating an Authentik
provider or secret:

- Native OIDC is for an app that performs its own redirect, code exchange,
  token validation, session handling, or app-specific role mapping. It uses the
  replicated `<app>-sso-secret` contract below.
- Traefik forward-auth is for an app protected at the ingress boundary by the
  shared Gatekeeper proxy/outpost. A proxy-only app does **not** need native
  provider credentials or an app-specific SSO Secret. Use the existing
  `traefik-gatekeeper-auth-chain@kubernetescrd` unless an exact sibling proves
  that a special middleware chain is required.
- Configure both only when two independent flows are explicitly required and
  test them separately; do not create native credentials to make a proxy route
  look complete.

## Native OIDC Client Contract

Before changing an Authentik OIDC application, read a complete native-OIDC
reference across both namespaces. `Karakeep` is the primary `utils` reference:

- source Secret: `install/karakeep-sso-secret.sops.yaml`
- Authentik HelmRelease environment: `install/helmrelease.yaml`
- provider, application, group, and policy: `install/blueprint-bootstrap-cm.yaml`
- workload consumer: `kubernetes/apps/apps/utils/karakeep/helmrelease.yaml`

The Authentik-side `<app>-sso-secret` is the single source of `CLIENT_ID` and
`CLIENT_SECRET`. It must:

1. live in namespace `authentik` and be included by `install/kustomization.yaml`;
2. set `replicator.v1.mittwald.de/replicate-to: <consumer namespace>`;
3. be injected into the Authentik HelmRelease as `<APP>_CLIENT_ID` and
   `<APP>_CLIENT_SECRET` for the blueprint; and
4. be consumed by the workload from the replica with `secretKeyRef`.

Do not create a second workload-local copy of these client credentials. A
workload-local Secret may contain only application-owned values such as a
session-signing secret.

## Blueprint And URL Rules

- Create the application access group, add `AK_BLUEPRINT_USERNAME`, and bind
  that group to the application policy. Homepage-style applications must not
  rely on Homepage claim authorization.
- Pair exactly one provider with the intended application through
  `provider: !KeyOf <provider-id>` and the matching application slug. Copy
  strict callback URIs, provider settings, and scope mappings from the closest
  working provider; register only the exact callback the app emits, never a
  wildcard or guessed home page.
- Start with the minimum `openid`, `email`, and `profile` mappings. Review a
  custom role claim separately: derive it only from explicit groups, use an
  allowlist and deterministic precedence, return no privileged role by
  default, and keep the application group policy as the admission control.
- Review any dangerous email-account-linking setting as a security exception.
  Require an explicit need, one trusted Authentik issuer, verified email
  behavior, collision/takeover analysis, and a documented temporary bootstrap
  window when applicable. Do not enable email linking merely because the
  `email` scope is present.
- Derive parameterized hostnames only from an exact sibling with the same role.
  The in-repo custom icon pattern is
  `https://assets.web.${CLUSTER_DOMAIN}/icons/<app>.svg`; do not synthesize a
  different DNS label layout from a rendered domain.

## Forward-auth chain and callback rules

- The generic chain is ordered `default-headers`, `crowdsec-bouncer`, then
  `authentik-auth`; its forward-auth address is the Gatekeeper outpost's
  `/outpost.goauthentik.io/auth/traefik` endpoint.
- The existing wildcard callback Ingress routes the app host's
  `/outpost.goauthentik.io/` prefix to `ak-outpost-gatekeeper-proxy` and uses
  `traefik-default-chain@kubernetescrd`, not Gatekeeper again, to avoid a
  callback loop.
- Include new Authentik middleware/callback resources in
  `config/kustomization.yaml` and new Traefik chains in the Traefik config
  Kustomization. Do not make a new app-specific provider or source credential
  for a proxy-only route.

## Reconciliation ordering

Trace the actual Flux dependencies before changing ordering. The current
contracts are `traefik-install` → `traefik-config`, `authentik-install` →
`authentik-config`, and `apps-manifests` waiting for `apps-storage` and
`traefik-config`; kube-replicator must exist before a replicated native client
Secret can arrive. Do not add a new numbered Flux Kustomization for a normal
app or infer readiness from numeric filenames alone.

## SOPS And Validation

SOPS metadata is MAC-protected. Never patch or expose a `*.sops.yaml` file's
secret values directly. Use `sops edit` to rewrite the complete document and
MAC; only use a non-disclosing integrity check such as
`sops --decrypt <secret> >/dev/null` when that check is explicitly allowed.

Before claiming a native OIDC change complete, verify all of these links:

- source SOPS Secret has the `replicate-to` annotation for the consumer namespace;
- Authentik HelmRelease and provider blueprint use the same source Secret;
- workload `secretKeyRef` names that replica and its `CLIENT_ID` / `CLIENT_SECRET` keys;
- no workload-local Secret retains duplicate client credentials.

Then run:

```bash
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/infrastructure/security/authentik/install >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/apps/apps/<category>/<app> >/dev/null
pre-commit run --files <changed-file> [<changed-file>...]
```
