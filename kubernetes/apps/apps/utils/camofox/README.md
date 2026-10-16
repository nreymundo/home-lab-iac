# Camofox browser service

Camofox runs in `utils` with one replica and a Longhorn-backed `/root/.camofox`
volume. Profile state contains site credentials; only trusted operators should
have access to this service. The initial limits allow two browser sessions and
five tabs per session, with a 3Gi container memory limit. Telemetry and noVNC
are disabled.

## Access

- Human API documentation: `https://browser.lan.<cluster-domain>/docs`.
  Authentik admits the `camofox-users` group and injects the backend Bearer
  token. The bootstrap operator is the initial group member. Homepage links
  here using Camofox's upstream fox mascot.
- Hermes and scripts: `https://browser-api.lan.<cluster-domain>`.
  Traefik applies the existing LAN allowlist; Camofox also requires a Bearer
  token. `/health` is intentionally unauthenticated for probes.
- The API is not a browser desktop. noVNC is disabled; no ports 6080/5900 are
  published. Add an authenticated visual route separately if interactive
  browser login is needed.

The app-local `camofox-secrets.sops.yaml` owns `camofox-secrets` in `utils`.
Kube-replicator delivers the same Secret to `authentik`, whose HelmRelease
reads `ACCESS_KEY` for its Camofox header mapping. Do not create an independent
copy of this key in Authentik. Camofox uses `ACCESS_KEY` for both
`CAMOFOX_ACCESS_KEY` (general API) and `CAMOFOX_API_KEY` (cookie import), since
Hermes sends a single Bearer credential. `ADMIN_KEY` is a separate credential
for `/stop`; Hermes does not need it.

The human and machine routes are two authentication methods for the same
trusted browser service. Session `userId` values separate browser state but
are not user authorization boundaries. API-key holders and admitted human
operators must be trusted with all sessions on this instance.

## Hermes activation

After GitOps deploys the service, verify that the installed
`tools/browser_camofox.py` sends the `CAMOFOX_API_KEY` Bearer header. Configure
the active Hermes profile's protected `.env` with:

```dotenv
CAMOFOX_URL=https://browser-api.lan.<cluster-domain>
CAMOFOX_API_KEY=<ACCESS_KEY from the app-owned encrypted Secret>
```

Use a protected secret-editing workflow to deliver the key; do not print it in
shell output or paste it into an agent conversation. Do not use your personal
Authentik password. Select Camofox in `hermes tools` under Browser Automation,
which sets `browser.cloud_provider: camofox`, and fully restart that profile's
Hermes process. Setting only the URL does not override an existing backend
selection. These Hermes profile files are operator-managed, outside the
Ansible role's current desired state.

For persistent site logins, add this to the same profile's `config.yaml` and
restart Hermes:

```yaml
browser:
  cloud_provider: camofox
  camofox:
    managed_persistence: true
```

Camofox's persistence plugin is enabled by default in the pinned image. Hermes
must send its stable profile-scoped identity for later tasks to reuse logins.

## Rollout and acceptance

Storage reconciles through `apps-storage`; the workload and source Secret
through `apps-manifests`. Wait for the replicated `camofox-secrets` in
`authentik`, then check Authentik's HelmRelease, Camofox's HelmRelease, and the
Gatekeeper outpost. Authentik server/worker rollouts require this replica;
there is no dependency from `apps-manifests` back to Authentik readiness.
Reloader watches the source/replica consumers for later credential rotation.
Update Hermes's protected environment at the same time when rotating its key.

Static checks must render the app, storage, production app aggregator,
Authentik install/config, and Traefik config, then run the repository hooks.
Runtime acceptance requires:

1. A fresh browser is redirected from `/docs` to Authentik; the intended user
   can return and use the docs, while a user outside `camofox-users` is denied.
2. API requests to `/tabs` without a token or with a wrong token return 401;
   the correct token works from the Hermes VM. A token does not bypass the
   machine route's LAN restriction. Direct Service access still requires it.
3. Hermes navigates, snapshots, clicks, types, takes screenshots, and cleans
   up without SSO redirects. Cookie import works with its configured key;
   `/stop` rejects that key without the separate admin credential.
4. A controlled test login survives a new task, a Hermes restart, and a
   Camofox pod replacement once managed persistence is enabled.
5. Repeat the issue's bot.sannysoft.com and bot-detector.rebrowser.net checks
   and compare with the Chromium baseline. `/health` alone does not prove that
   Firefox starts or that the persistence plugin loaded successfully.

Use read-only Flux/pod inspection for rollout evidence. Do not use live
reconciliation, restarts, or pod replacement as local validation; exercise
restart persistence during an explicitly intended rollout/test window.
