---
name: authentik-oidc-app-change
description: >-
  Decide and implement Authentik protection for a workload, choosing native
  OIDC or Traefik forward-auth, and trace the complete provider, application,
  secret, middleware, Kustomize, and runtime-login contract. Use when an app is
  being added to Authentik, moved to native OIDC, or protected by the existing
  Traefik gatekeeper. Proxy-only apps do not automatically need native OIDC
  provider credentials.
---

# Authentik Authentication Change

Use this workflow for the complete GitOps and runtime contract between an
Authentik-protected workload and the identity layer. Decide the authentication
mode before creating any provider or secret. This is a GitOps workflow: do not
patch live Kubernetes or Authentik objects when the repository is the source of
truth.

## Authentication-mode decision

Classify the requested app before editing:

| Mode | Use when | Required repository objects |
| --- | --- | --- |
| Native OIDC | The app owns the browser redirect, authorization-code exchange, token validation, session, user provisioning, or app-specific OIDC roles. | An Authentik OAuth2 provider and application, an Authentik-side `<app>-sso-secret`, and a replicated consumer Secret. |
| Traefik forward-auth | The app has no suitable native OIDC flow and should be protected at the ingress boundary. | The existing Authentik Gatekeeper proxy/outpost, the existing forward-auth middleware chain, and the app ingress annotation. No app-specific native OIDC credentials are implied. |
| Both | Only when the request explicitly requires two independent gates and the two flows are tested separately. | The complete native contract plus the complete ingress middleware contract; avoid accidental double redirects. |

Do not create `<app>-sso-secret`, native `CLIENT_ID`/`CLIENT_SECRET`
environment variables, or an OAuth2 provider merely because an app is
forward-auth protected. The shared Gatekeeper provider/application is the
proxy path. Conversely, do not assume a native OIDC client is protected by an
ingress middleware: the app's callback and token exchange still need their own
provider contract.

Record these decisions before editing:

- app capability and chosen mode;
- exact public hostname, workload namespace, app category, and ingress path;
- for native OIDC, exact issuer slug, callback URI(s), logout/device URI(s) if
  the app documents them, client-authentication method, scopes, and any role
  claim;
- for forward-auth, the ingress route and whether the app needs headers beyond
  the generic Authentik response headers;
- the Authentik access group and the user that must be placed in it;
- whether the app has an account-linking or auto-provisioning setting that
  makes email-based linking possible.

## Mandatory reference trace

Read the nearest subtree `AGENTS.md` files and a complete sibling before
editing. For a `utils` native-OIDC workload, use Karakeep unless a closer app
exists. For forward-auth, use the existing external-proxy ingress and the
Gatekeeper middleware chain.

### Native OIDC trace

1. Authentik source Secret:
   `kubernetes/infrastructure/security/authentik/install/<app>-sso-secret.sops.yaml`
2. Authentik HelmRelease environment and provider blueprint:
   `kubernetes/infrastructure/security/authentik/install/{helmrelease.yaml,blueprint-bootstrap-cm.yaml}`
3. Authentik install Kustomization inclusion.
4. Workload HelmRelease consumer in `kubernetes/apps/apps/<category>/<app>/`.

Before editing, write down the source Secret name and namespace, its
replication target, the Authentik HelmRelease environment names, the blueprint
provider/application IDs, and the exact workload `secretKeyRef`. Do not design
from only the provider or only the app consumer.

### Traefik forward-auth trace

Read all of the following, even when no new Authentik object is needed:

1. the workload ingress and its owning app Kustomization;
2. `kubernetes/infrastructure/networking/traefik/config/middlewares/gatekeeper-auth-chain.yaml`;
3. `kubernetes/infrastructure/security/authentik/config/middleware.yaml` and
   `outpost-callback-ingress.yaml`;
4. the owning Kustomizations and Flux paths for the Traefik and Authentik
   config layers.

The established generic chain is `default-headers`, `crowdsec-bouncer`, then
`authentik-auth`. The forward-auth endpoint is the Gatekeeper outpost service,
and the public callback prefix is `/outpost.goauthentik.io/`. Use a
service-specific middleware/chain only when the app needs a distinct response
header or other proven local behavior; copy the complete sibling chain rather
than making a partial variant.

## Required client-secret contract

This section applies **only** to native OIDC.

- The Authentik-side `<app>-sso-secret` is the one source of `CLIENT_ID` and
  `CLIENT_SECRET`.
- It lives in namespace `authentik`, is SOPS-encrypted, and has
  `replicator.v1.mittwald.de/replicate-to: <workload namespace>`.
- The Authentik HelmRelease reads it as `<APP>_CLIENT_ID` and
  `<APP>_CLIENT_SECRET`; the blueprint provider uses those `!Env` values.
- The workload consumes the replicated Secret by the same name with
  `secretKeyRef` and `CLIENT_ID` / `CLIENT_SECRET` keys.
- Do not store a second copy of client credentials in a workload-local SOPS
  Secret. Local secrets are only for workload-owned credentials, such as a
  session-signing secret.

For forward-auth, there is no native client-secret contract for the protected
app. The shared Gatekeeper proxy provider and outpost authenticate the browser;
the app receives only the headers deliberately exposed by its middleware.

## Native OIDC provider and application workflow

### Exact callback and issuer contract

Derive every URL from the app's actual configuration and the closest working
sibling. Never infer a callback from a rendered hostname or make a callback
wildcard convenient:

- issuer discovery is normally
  `https://sso.${CLUSTER_DOMAIN}/application/o/<application-slug>/.well-known/openid-configuration`;
  use the app's exact issuer form, including its trailing slash convention;
- every Authentik `redirect_uris[].url` uses `matching_mode: strict`;
- copy the complete callback path, scheme, host, port, trailing slash, casing,
  mobile scheme, and logout/device callback from the app's documented flow;
- register only callbacks the app actually sends. Do not register the issuer,
  home page, a wildcard, or a guessed callback as a substitute;
- verify that the app's configured redirect URI is byte-for-byte the same as
  the blueprint URI after `${CLUSTER_DOMAIN}` substitution.

Examples of the repository's exact-sibling style include Karakeep's
`https://keep.${CLUSTER_DOMAIN}/api/auth/callback/custom`, Komga's Spring
`{baseUrl}/{action}/oauth2/code/{registrationId}` contract, and Gitea's
`https://git.${CLUSTER_DOMAIN}/user/oauth2/Authentik/callback`. These are
examples to trace, not values to reuse for a different app.

### Provider/application pairing

Follow the closest working authorization-code confidential provider, but copy
all compatibility-sensitive fields from that sibling: authorization and
invalidation flows, signing/encryption settings, grant type, and
`client_authentication_method`. The provider must reference the client values
from `!Env <APP>_CLIENT_ID` and `!Env <APP>_CLIENT_SECRET`, and the application
must reference that exact provider with `provider: !KeyOf <provider-id>`.

Keep the pairing unambiguous:

- one intended provider and one application slug for the app;
- the blueprint `identifiers` and `!KeyOf` references must resolve to the same
  app, not merely have similar display names;
- the app's issuer slug, application slug, provider, secret name, and workload
  references must agree;
- do not create a second provider/application to work around a callback typo.

### Scopes and claims

Start with the minimum mappings the app requires: `openid`, `email`, and
`profile` are the established baseline for the native web apps here. Add a
custom scope mapping only when the app documents that it consumes it, and add
that mapping to the provider **and** to the app's requested scope list. A role
claim is not an access-control substitute.

For a custom role claim, perform a security review before adding it:

1. identify the exact claim name, accepted values, token (ID token or UserInfo),
   and app setting that consumes it;
2. derive values only from explicit Authentik group membership, with an
   allowlist and deterministic precedence (for example, admin before user);
3. return no privileged value when the user is in neither group, and do not
   derive privilege from email, display name, arbitrary attributes, or a
   client-supplied claim;
4. bind the same intended groups to the Authentik application policy so the
   group controls admission and the claim controls only the downstream app
   role;
5. test a permitted user, an ungrouped user, and a lower-privilege user without
   printing or copying tokens.

The Gitea, Immich, and LiteLLM blueprints are the local role-claim references.
Copy their explicit group checks and precedence shape only after confirming the
new app's expected claim contract. Homepage authorization must not be based on
Homepage claim behavior.

### Group policy binding

Create or reuse the named access group, set its intended membership, add
`AK_BLUEPRINT_USERNAME` where the sibling contract requires the bootstrap user,
and bind the group to the Authentik application with an ordered
`authentik_policies.policybinding`. The policy target must resolve to the
application slug. Do not rely on a role claim, a Homepage card, or an app-side
group check as the only Authentik admission control.

Treat a blueprint group's `attrs.users` as the complete desired membership:
reapplying the blueprint replaces that list rather than appending to it. Include
every intended member in the blueprint and do not assume an out-of-band group
addition will survive reconciliation.

### Dangerous email-account linking

Search the workload configuration for account-linking and auto-provisioning
settings before enabling native OIDC. Treat settings such as
`OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING: "true"` as a security exception,
not as ordinary OIDC wiring:

- keep the default disabled unless the app cannot attach an existing account
  by a stable subject and the requirement is explicit;
- require one locally trusted Authentik issuer, verified email enforcement, an
  exact email claim mapping, and a review of collisions, reassignment, and
  account-takeover consequences;
- confirm that Authentik is the only accepted provider for the app and that the
  access policy still limits who can log in;
- document why the exception is needed next to the setting. If it is only for
  first-login bootstrap, make the temporary sign-up/linking window explicit and
  revert it immediately after bootstrap;
- never enable the setting merely because `email` is one of the normal OIDC
  scopes.

Karakeep is the local example: its dangerous-linking setting is documented as
a temporary bootstrap escape hatch alongside disabled password auth and the
initial sign-up behavior. Treat that comment and the surrounding conditions as
part of the security review, not as a template to enable for every app.

For a parameterized callback or icon URL, copy the exact matching sibling
expression. Do not infer DNS labels from a rendered domain. For custom icons,
the established host pattern is:

```yaml
icon: "https://assets.web.${CLUSTER_DOMAIN}/icons/<app>.svg"
```

## Forward-auth workflow

Forward-auth protects the ingress and does not turn the application into an
OIDC client. For a proxy-only app:

1. annotate the app's Ingress or generated Ingress with the existing
   `traefik-gatekeeper-auth-chain@kubernetescrd` when the generic chain is the
   matching sibling;
2. confirm that the chain is included by the Traefik config Kustomization and
   contains, in order, default headers, CrowdSec, and the Authentik forward-auth
   middleware;
3. confirm `authentik-auth` forwards to
   `http://ak-outpost-gatekeeper-proxy.authentik.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik`,
   trusts the forwarded headers, preserves the location header, and exposes
   only the response headers the app needs;
4. confirm the existing wildcard callback Ingress routes
   `<app>.lan.${CLUSTER_DOMAIN}/outpost.goauthentik.io/` to the Gatekeeper
   outpost and uses the non-authenticated `traefik-default-chain@kubernetescrd`
   so the callback cannot loop back through Gatekeeper;
5. if a special app-specific chain is required, add its middleware and chain in
   their owning config Kustomizations and copy a complete sibling. Do not add a
   native provider secret unless the app also has an independently requested
   native OIDC flow.

Do not put the Gatekeeper callback path behind the Gatekeeper forward-auth
middleware itself. Do not replace the shared proxy provider/application with a
native provider per proxy-only app. If an ingress already has a native app
login, decide explicitly whether the middleware is redundant or intentionally a
second boundary before changing either route.

## Kustomize and dependency ordering

Trace inclusion, not just file presence.

### Native OIDC

- add the source SOPS Secret to
  `kubernetes/infrastructure/security/authentik/install/kustomization.yaml`;
- add its `<APP>_CLIENT_ID`/`<APP>_CLIENT_SECRET` references to the Authentik
  HelmRelease and the provider blueprint;
- do not list the Authentik source Secret in the workload Kustomization; the
  replicator creates the consumer-namespace replica;
- consume the replica from the workload HelmRelease with `secretKeyRef`;
- ensure the app's own Kustomization includes every local resource it consumes,
  and `kubernetes/apps/production/kustomization.yaml` includes the app;
- if the app is new, check the `apps-manifests` Flux Kustomization because it
  has `prune: true` and owns the active workload inventory.

### Forward-auth

- a generic gatekeeper annotation normally needs no new Authentik provider,
  secret, or Authentik config file;
- if a middleware or chain is new, include it in the owning Authentik or
  Traefik config Kustomization and verify the corresponding Flux Kustomization
  path;
- include the app in its owning app Kustomization and production aggregator;
- do not add a new cluster ordering object for an ordinary app. Follow the
  existing dependency graph: `traefik-install` → `traefik-config`,
  `authentik-install` → `authentik-config`, and `apps-manifests` waits for
  `apps-storage` and `traefik-config`. Inspect the actual `dependsOn` fields
  before proposing an ordering change.

The native source/provider/application is reconciled by `authentik-install`;
forward-auth middleware and callback resources are reconciled by
`authentik-config` while the shared chain is in `traefik-config`. The
kube-replicator must be installed before a native consumer can receive its
replica. Do not claim ordering from numeric filenames alone.

## SOPS safety

This workflow never creates or exposes secret values. Follow the dedicated
`kubernetes-sops-secret-lifecycle` skill for creation, editing, rotation,
recipient changes, ownership, and non-disclosing checks. The SOPS MAC includes
unencrypted metadata. Do not patch a `*.sops.yaml` file directly. Use SOPS to
re-encrypt the complete document after changing data or metadata, then validate
the changed Secret without printing it:

```bash
sops --decrypt kubernetes/infrastructure/security/authentik/install/<app>-sso-secret.sops.yaml >/dev/null
```

Never send decrypted output to the terminal, a log, a rendered-manifest file,
`kubectl get -o yaml`, or a commit. If the task explicitly forbids decryption,
skip this check and report that limitation to the parent orchestrator.

## Validation and actual login/callback proof

Static validation must prove the complete selected branch:

- native: source Secret namespace and `replicate-to` annotation, install
  Kustomization entry, matching HelmRelease environment names, matching
  `!Env` blueprint references, provider/application pairing, strict callback
  URI, minimal scopes, group policy binding, workload `secretKeyRef`, and no
  duplicate client credentials in a workload-local Secret;
- forward-auth: app ingress annotation, chain inclusion and order, exact
  forward-auth service address, response headers, callback Ingress prefix and
  non-looping chain, and no invented native provider Secret;
- both: prove each list independently and check for redirect loops or two
  competing session owners.

The parent orchestrator owns execution of validation. When authorized, the
read-only repository checks are:

```bash
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/infrastructure/security/authentik/install >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/infrastructure/security/authentik/config >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/infrastructure/networking/traefik/config >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/apps/apps/<category>/<app> >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/apps/production >/dev/null
pre-commit run --files <changed-file> [<changed-file>...]
```

Do not treat rendering as proof that the login works. With live access, perform
an actual browser test in a private session and record only status/URL facts:

### Native OIDC test

1. Open the app's login URL and confirm it redirects to the exact Authentik
   application slug.
2. In browser network details, confirm the authorization request has the exact
   registered `redirect_uri`, `client_id`, `response_type=code`, the expected
   minimal scopes, and state/nonce. Do not copy authorization codes, tokens, or
   cookies into a ticket or log.
3. Authenticate as a user in the bound group and confirm the callback returns
   to the app without `invalid_redirect_uri`, provider mismatch, or a loop, and
   that the app creates or resumes the intended session.
4. Test an ungrouped user and confirm Authentik denies access before the app
   session is created. If a role claim exists, test the permitted role and the
   lower/no-role case without displaying the token.
5. If account linking is enabled, test the approved verified-email scenario and
   verify that an unrelated or unverified email cannot attach to the account.

### Traefik forward-auth test

1. In a private session, request the protected app without an Authentik cookie
   and confirm the response redirects through the Gatekeeper outpost rather
   than to a nonexistent native provider.
2. Complete Authentik login and confirm the browser returns through the app
   host's `/outpost.goauthentik.io/` callback prefix and then reaches the app.
3. Confirm the callback is not itself challenged by Gatekeeper, the request is
   not redirected repeatedly, and only the intended Authentik response headers
   reach the app.
4. Log out or clear the session and repeat the unauthenticated request. Test a
   user that should be denied by the configured Authentik policy when the proxy
   application has such a restriction.

Use `flux get kustomizations`, `flux get helmreleases -A`, and metadata-only
Secret checks to establish rollout state. Do not use live reconciliation as
validation and do not fetch Secret data. Report live login/callback validation
as unperformed when cluster access or the required test account is unavailable.

## Stop conditions

Stop and ask the parent orchestrator when the requested callback is unknown,
the app requires a role claim whose semantics are undocumented, dangerous email
linking is proposed without an explicit security review, the shared Gatekeeper
contract would need to change, or an Age recipient / `.sops.yaml` rule change is
being suggested. Do not paper over an incomplete contract with a wildcard URI,
copied credentials, a second provider, or a live patch.
