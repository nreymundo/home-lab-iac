# Open WebUI

[Open WebUI](https://github.com/open-webui/open-webui) chat interface for AI models, served at
`https://chat.lan.${CLUSTER_DOMAIN}` in the `ai` namespace.

- Image: `ghcr.io/open-webui/open-webui` (Renovate-tracked)
- Auth: native Authentik OIDC only (`open-webui-sso-secret` replicated from the Authentik
  namespace; no password login, no forward-auth)
- Models: routed through LiteLLM (`litellm-main.ai.svc.cluster.local:4000/v1`), with no model
  allowlists. OpenRouter access is provided separately by the imported pipe described below.
- Web search: SearXNG (`searxng-main.utils.svc.cluster.local:8080`)
- Persistence: `open-webui` PVC (5Gi, `longhorn-r2`, Longhorn daily/weekly recurring backups,
  `helm.sh/resource-policy: keep`), mounted at `/app/backend/data`
- Local secrets are consolidated in `open-webui-secrets`: `WEBUI_SECRET_KEY`,
  `LITELLM_API_KEY`, and `OPENROUTER_API_KEY`.

Functions and valves are stored in the Open WebUI database on the `open-webui` PVC; they are not
Git-managed.

## OpenRouter pipe (v2.7.3) import

OpenRouter access is provided by the Open-WebUI-OpenRouter-pipe function, imported through the
UI rather than declared in Git.

Import asset:

- URL: `https://github.com/rbb-dev/Open-WebUI-OpenRouter-pipe/releases/download/v2.7.3/open_webui_openrouter_pipe_bundled.py`
- sha256: `54d24107d8123d5aa11db21245e40e0f266e16c9694683ed3085bfc47fe387fe`

Procedure:

1. Back up the `open-webui` PVC before importing (or rely on the Longhorn daily/weekly
   recurring backups; take a fresh snapshot if the last one is stale).
2. Download the asset and verify the checksum:
   ```bash
   curl -fLO https://github.com/rbb-dev/Open-WebUI-OpenRouter-pipe/releases/download/v2.7.3/open_webui_openrouter_pipe_bundled.py
   sha256sum open_webui_openrouter_pipe_bundled.py
   # expect 54d24107d8123d5aa11db21245e40e0f266e16c9694683ed3085bfc47fe387fe
   ```
3. In Open WebUI, go to Admin Panel -> Functions -> Import Function, and upload the verified
   `open_webui_openrouter_pipe_bundled.py`.
4. Enable the imported function.
5. Open its Valves and verify the `API_KEY` valve is seeded from the environment
   (`OPENROUTER_API_KEY` from `open-webui-secrets`, stored encrypted because
   `ENABLE_VALVE_ENCRYPTION=true`). Set `MODEL_ID=auto`.

### Rollback

1. Disable the function in Admin Panel -> Functions.
2. Delete the function from Admin Panel -> Functions.
3. Revoke the OpenRouter API key at <https://openrouter.ai/keys> if it may have leaked.

These actions operate only on the database resident in the `open-webui` PVC; no Git resources are
involved.
