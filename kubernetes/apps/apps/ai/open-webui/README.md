# Open WebUI

[Open WebUI](https://github.com/open-webui/open-webui) chat interface for AI models, served at
`https://chat.lan.${CLUSTER_DOMAIN}` in the `ai` namespace.

- Image: `ghcr.io/open-webui/open-webui` (Renovate-tracked)
- Auth: native Authentik OIDC only (`open-webui-sso-secret` replicated from the Authentik
  namespace; no password login, no forward-auth)
- Models: routed through LiteLLM (`litellm-main.ai.svc.cluster.local:4000/v1`), with no model
  allowlists. OpenRouter access is provided separately by the imported pipe described below.
- Database: dedicated CNPG PostgreSQL cluster `open-webui-pg` (PostgreSQL 18, 1 instance,
  5Gi `longhorn-r2`) with pgvector (extension `vector`, pgvector 0.8.2 bundled in the
  `ghcr.io/cloudnative-pg/postgresql:18` image, created by the cluster bootstrap). Open WebUI
  uses `VECTOR_DB=pgvector` against `DATABASE_URL`; the extension is not created by the app
  (`PGVECTOR_CREATE_EXTENSION=false`)
- RAG embeddings: LiteLLM model `local/embedding` (`RAG_EMBEDDING_ENGINE=openai`,
  `RAG_OPENAI_API_BASE_URL=http://litellm-main.ai.svc.cluster.local:4000/v1`), stored in
  pgvector at up to 2560 dimensions using halfvec (`PGVECTOR_USE_HALFVEC=true`) with HNSW
  indexes
- Web search: SearXNG (`searxng-main.utils.svc.cluster.local:8080`)
- Cache: ephemeral Valkey controller (`open-webui-valkey`, 6379, emptyDir) used only for
  websocket fan-out / live state coordination (`WEBSOCKET_MANAGER=redis`,
  `REDIS_URL=redis://open-webui-valkey:6379/0`); it is intentionally not persistent and holds
  no durable data
- Persistence: `open-webui` PVC (5Gi, `longhorn-r2`, Longhorn daily/weekly recurring backups,
  `helm.sh/resource-policy: keep`), mounted at `/app/backend/data`. Since the PostgreSQL
  cutover it holds only uploads and cache; the legacy SQLite database remains on it solely as
  a rollback copy
- Local secrets are consolidated in `open-webui-secrets`: `WEBUI_SECRET_KEY`,
  `LITELLM_API_KEY`, and `OPENROUTER_API_KEY`. Database credentials live in
  `open-webui-db-secrets` (`username`, `password`, `DATABASE_URL`), shared by the CNPG
  bootstrap (database/owner `open_webui`) and the app
- Backups: `open-webui-pg` ships WAL and base backups via barman to
  `s3://cloudnative-pg/open-webui` (server `open-webui-pg-v1`, gzip) with 21d retention and a
  weekly `ScheduledBackup` (`open-webui-pg-backup`, Sunday midnight), plus the Longhorn
  recurring-job labels on the cluster pods

## Fresh cutover warning: SQLite data is not migrated

Open WebUI does not migrate an existing SQLite database to PostgreSQL. The first start against
`open-webui-pg` begins with an empty database. Existing users, chats, functions, and valves
from the SQLite era are **not** carried over; they require manual migration or must be
recreated/re-imported (functions can be re-imported, valves re-entered; see the OpenRouter
procedure below for an example). The pre-cutover SQLite database is preserved on the
`open-webui` PVC for manual export/rollback.

## OpenRouter pipe (v2.7.3) import

OpenRouter access is provided by the Open-WebUI-OpenRouter-pipe function, imported through the
UI rather than declared in Git.

Import asset:

- URL: `https://github.com/rbb-dev/Open-WebUI-OpenRouter-pipe/releases/download/v2.7.3/open_webui_openrouter_pipe_bundled.py`
- sha256: `54d24107d8123d5aa11db21245e40e0f266e16c9694683ed3085bfc47fe387fe`

Procedure:

1. Take a fresh backup before importing: trigger an on-demand CNPG base backup with
   `kubectl cnpg backup open-webui-pg -n ai`, or verify a recent successful backup from the
   weekly `open-webui-pg-backup` schedule, since functions now live in PostgreSQL.
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

These actions operate only on the `open_webui` database in the `open-webui-pg` CNPG cluster;
no Git resources are involved.
