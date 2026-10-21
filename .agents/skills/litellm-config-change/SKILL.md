---
name: litellm-config-change
description: >-
  Inspect or change this repo's LiteLLM models, providers, credentials, routing,
  fallbacks, pricing, caching, Python compatibility patches, or image version under
  kubernetes/apps/apps/ai/litellm/. Image updates require manual review of active
  patches. Use for LiteLLM configuration and feature comparisons, not general
  app onboarding or unrelated AI gateways.
---

# LiteLLM Config Change

This deployment uses ConfigMap-mounted Python integrations, a separate Valkey
controller for response caching, Authentik SSO, a CNPG database, and a Headroom
sidecar used for request compression.

## Source and activation contract

All paths below are relative to `kubernetes/apps/apps/ai/litellm/`:

- `configmap.yaml`: embedded `config.yaml` with models, credential references,
  aliases, router settings, cache settings, and callbacks.
- `scripts/*.py`: Python source of truth. Do not embed patches in `configmap.yaml`.
- `kustomization.yaml`: merges scripts into `litellm-config` through
  `configMapGenerator.files`, with a stable ConfigMap name.
- `helmrelease.yaml`: image, main and Valkey controllers, environment, and mounts.
  Python files mount under `persistence.config.advancedMounts.main.main` using
  `subPath`; `PYTHONPATH=/etc/litellm` makes them importable.
- `cnpg-cluster.yaml`: database and backup configuration.
- `litellm-credentials.sops.yaml`: provider credentials consumed through `envFrom`.
- `litellm-secrets.sops.yaml`: master and salt keys.
- `litellm-guardrail-fingerprints.sops.yaml`: hashes used by the secrets
  guardrail. Its JSON value is delivered through `envFrom`; it contains only
  SHA-256 fingerprints, not source credentials.
- `litellm-db-secrets.sops.yaml`: database credentials and URL.

The Authentik-owned `litellm-sso-secret` comes from
`kubernetes/infrastructure/security/authentik/install/`; consume its namespace
replica directly. Use the SOPS lifecycle skill for secret changes.

`sitecustomize.py` invokes `litellm_startup.worker_startup_hook()`, also registered
through `LITELLM_WORKER_STARTUP_HOOKS`. Keep patches idempotent. For new modules,
trace source → generator entry → mount → activation. A mounted or imported module
is not evidence that its patch is enabled; inspect the actual startup hook.

## Current behavior to verify before changing

- The startup hook enables virtual-key model-discovery route access, the ChatGPT
  Responses string-input normalization backport, and OpenRouter rerank support.
  Catalog, reasoning, streaming/cache, vLLM-discovery, retry, and file-authoritative
  router implementations remain present but their hook calls are commented out.
  Do not restore them merely because their files still exist.
- `cache_bypass.proxy_handler_instance` is registered independently as a callback.
  Key metadata can disable cache reads/writes or remove selected request parameters
  globally or by requested model name. Check this when diagnosing client differences.
  For `cloud/codex-auto` and `cloud/glm-auto`, the same hook removes client effort
  controls before routing (including nested/extra-body forms), while preserving
  unrelated reasoning fields. Its deployment hook copies the resolved effort into
  a retained Responses `reasoning` object so a summary-only object cannot shadow
  `reasoning_effort`. This is request normalization; model selection stays native.
  Direct model requests keep client effort precedence. Keep the scope restricted
  to these auto routes and test both chat and Responses before changing the hook.
- `secrets-observer` runs after Headroom and uses native pre-call, deployment, and
  post-call hooks because unified translations omit Decisions, some rerank/Responses
  fields, and cloud fallbacks after local dispatch. Its `pre_call` and `post_call`
  modes are both required: post-call mode gates response notices and streaming hooks.
  `GUARDRAIL_SECRETS_MODE` accepts
  `redact`, `observe`, or `off`: redact replaces spans found by every detector
  and continues processing, observe reports without modifying payloads, and off
  bypasses scanning. The safe default is `observe`; Helm explicitly selects
  `redact`. Redacted chat requests receive a model-context notice and an
  assistant-visible notice, including streamed completions. Non-streaming Responses
  API output receives an assistant-visible notice in its `output_text` block.
  Direct `apply_guardrail` calls scan extracted text
  inputs and redact the caller-owned text list in place. The response header
  `X-LiteLLM-Secrets-Guardrail: redacted` marks sanitized requests. The
  applied-guardrail header indicates evaluation, not sanitization. In redact mode,
  scanner failure stops cloud dispatch with a retryable 503; reporting failures
  remain non-blocking. Observe/off and trusted local routes keep their policies.
  Keep `SET_DEBUG` disabled to avoid request-payload debug logging. Keep
  fingerprints in the workload-owned SOPS Secret and rotate them by hashing current
  source values locally without printing values or hashes. Exact fingerprints match
  intact values only; they do not detect arbitrary truncation or encoding. Credential
  assignments include quoted JSON keys; assignments whose field name ends in a
  reference segment (`_name`, `_id`, `_ref`, `_url`, `_path`, `_label`, `_uri`,
  `_file`) are exempt from heuristic assignment redaction, while format and
  fingerprint detectors still scan their values. Whole placeholder expressions,
  bare environment references, bracket-form environment lookups, common getenv
  calls and unquoted config/settings/credentials properties bypass assignment
  heuristics; literal defaults and concatenations are still inspected. Format
  detectors exempt only exact published examples or fully x-masked token payloads,
  never placeholder substrings. Fingerprints scan original text, including SOPS
  and redaction wrappers. Only known typed `[REDACTED: <detector>]` markers bypass
  assignment scanning; format detection still inspects them. Structured text fields named `data` are
  scanned, while known audio, image, video, and file payloads are skipped. MCP
  gateway traffic is not scanned. Unresolved local routes use the stable `local/`
  and `hosted_vllm/` prefixes; a resolved `api_base` is authoritative and is also
  compared with the configured llama-swap endpoint, so LAN-backed local routes are
  skipped while cloud fallbacks are checked again at deployment. Sanitized audit
  summaries include mode, outcome, detector counts, duration, and correlation ID; matched
  content is never logged. Redaction preserves surrounding request structure and
  local-route exemptions remain intact.
- `GUARDRAIL_SECRETS_JUDGE` (default `off`, Helm selects `async`) adds a verdict cache
  for ambiguous assignments only: captures without a cached verdict are redacted
  fail-closed, then classified out-of-band by the local decisions model through the
  llama-swap backend's native `/v1/systemone` Decisions API directly, not chat
  completions (`GUARDRAIL_SECRETS_JUDGE_ENDPOINT`/`_AUTH` default to
  the llama-swap credential env; `_MODEL` defaults to d3-mini, `_TIMEOUT` to 30 s,
  `_MAX_INFLIGHT` to 2). Verdicts persist in SQLite on the litellm volume
  (`GUARDRAIL_SECRETS_JUDGE_DB`, default under /var/lib/litellm) and store only
  SHA-256 scoped digests, never span/context text. Cache keys include detector,
  previous/current-line context, model, endpoint and policy version; appended turns
  do not change existing line context. PASS lasts 24 hours and REDACT seven days
  (`GUARDRAIL_SECRETS_JUDGE_PASS_TTL`/`_REDACT_TTL`, seconds). Bump
  `GUARDRAIL_SECRETS_JUDGE_VERSION` when replacing a model behind the same name.
  Legacy global verdicts are discarded. A PASS lets matching replays carry the
  span verbatim; REDACT keeps redaction without re-judging until expiry. Only exact
  normalized PASS/REDACT choices are accepted; malformed answers stay undecided.
  Format detections and fingerprints are never judged. Judge failures write no verdict: the span stays
  redacted, retries back off per span, and three consecutive failures pause
  judging globally for five minutes. A bounded 128-item queue drains at the configured
  concurrency; queued work expires after five minutes. Cache/database entries and
  backoff state are capped at 20,000. Request lookups are memory-only; HTTP and
  persistence run off the event loop, with no inference wait in request handling.
  Failed writes cannot grant a PASS. Audit lines carry judge_pass/judge_enqueued;
  `litellm_secrets_judge_*` and `litellm_secrets_scan_failures_total` expose bounded-label
  outcomes, latency, queue and inflight counts without content or digest labels.
- `router_settings.model_group_alias` maps friendly `local/*` and `cloud/*` names
  to canonical primary deployments. Service fallback chains are keyed on
  `cloud/fast`, `cloud/general`, `cloud/coder`, and `cloud/deep`; their destinations
  are matching `cloud/<type>-fallback` aliases. Each fallback alias maps directly to
  a canonical model name and has no fallback chain of its own. The prefix describes
  where the target runs; future local targets use `local/<type>-fallback`. Explicit
  canonical model names and local routes have no configured failover. Verify source
  and destination alias resolution on image updates.
- `cloud/codex-auto` is an opt-in native `auto_router/complexity_router` deployment,
  configured entirely in `configmap.yaml`. Its four tiers select Luna/low,
  Luna/high, Sol/high, and Astra/high through dedicated `cloud/codex-*-*`
  deployments. These deployment names carry reasoning defaults; they are not
  `model_group_alias` entries. Native per-tier `litellm_params` pin effort on auto
  routes; ingress normalization also protects retained decisions and classifier
  failures, where this build otherwise restores client effort. Direct requests
  to the presets still allow caller overrides.
  Jev uses `classifier_type: oss_classifier` with the existing
  `openrouter/~typesafe/jev-latest` decision deployment, without a new credential or
  custom routing engine. Classification failure selects Astra/high; inference
  failures use per-tier fallback chains to the existing fast/deep fallback aliases,
  with explicit fallback effort parameters to preserve the selected level.
  `classification_mode: user_turn` retains the choice through tool continuations
  only when the client supplies a stable session identifier (for example
  `metadata.session_id`); a new human ask reclassifies. `session_affinity` remains
  false so the first model does not pin the entire conversation. Verify both chat
  and Responses routing, client effort precedence, session reuse, selected-tier
  fallbacks, summary preservation, and Auto-Routers UI visibility when changing
  this configuration. Validate client `xhigh`, streaming, turn reuse, and
  classifier/provider/image failures against the installed LiteLLM version.
  `cloud/decision` remains a direct Jev alias; other existing cloud/local routes
  do not opt into auto routing.
- `cloud/glm-auto` uses the same native Jev classifier and user-turn policy. Its
  tiers are GLM-5.3-Flash/low, Flash/high, GLM-5.3/high, and GLM-5.3/max,
  through `cloud/glm-flash-low`, `cloud/glm-flash-high`, `cloud/glm-high`, and
  `cloud/glm-max`. They reuse the `zai-coding` credential and provider parameters;
  `low`, `high`, and `max` are the supported effort values. Classification failure
  selects GLM/high, while each tier's inference fallback is `cloud/coder-fallback`
  (the independent ChatGPT subscription). Switching between GLM models does not
  replenish their shared Coding Plan quota. Flash tiers advertise vision support;
  main GLM tiers explicitly do not. Native modality routing only searches higher
  tiers, so `cloud/glm-auto` also falls back to `cloud/glm-flash-high` when routing
  fails before a tier is dispatched. With a failed classifier, native modality
  handling has no decided tier and instead selects the first compatible tier,
  Flash/low. Validate both image paths and their enforced effort: a classified
  text-only tier falls back to Flash/high; classifier failure uses Flash/low.
  Auto-route effort ownership and stable-session requirements match
  `cloud/codex-auto`.
- Local model entries share the llama-swap credential/backend. Another local model
  is not an independent host-outage fallback. Check endpoint, tool, modality,
  context, and embedding-space compatibility when proposing destinations.
- Git intends to own configuration (`general_settings.store_model_in_db: false`),
  while the HelmRelease also sets `STORE_MODEL_IN_DB: "True"`. Verify the installed
  version's effective precedence and DB configuration before diagnosing drift.
  The disabled file-authority patch is not an ownership guarantee.
- Read the image tag from the HelmRelease. Renovate admits stable tags only, even
  when the selected image is a manually chosen release candidate. Compare features
  with that exact build; current documentation may describe unreleased changes.

## Changes and validation

Edit model/router settings in the embedded configuration, Python in `scripts/`,
and provider credential references in the owning configuration and HelmRelease.
Trace affected clients such as Open WebUI and Hindsight before changing shared aliases.

Image updates remain manual under the LiteLLM rule in `renovate.json`. Read upstream
release notes and verify active patches against the candidate image, including
imports of retained modules. Rendering manifests cannot prove Python compatibility.

For workload changes, follow the applicable Kubernetes validation chain:

```bash
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/apps/apps/ai/litellm >/dev/null
scripts/kubeconform.sh
pre-commit run --files <changed-file> [<changed-file>...]
```

Include changed `scripts/*.py` files explicitly. Documentation-only skill changes
need skill validation and applicable file hooks, not cluster or inference tests.

`scripts/test_litellm_guardrail.py` exercises scanner, cache, HTTP, lifecycle and
failure behavior with synthetic fixtures. `.github/workflows/litellm-guardrail.yml`
runs it offline in the HelmRelease's selected image.

Run Python integration tests that import the full proxy in a separate local
runtime matching the deployed image, with provider HTTP mocked. Extra proxy
interpreters inside the production container share its memory limit and have
caused an OOM restart; do not use the running proxy pod as the test runner.

When live inspection is relevant, check the HelmRelease, deployment, readiness,
and startup logs without exposing credentials or prompt contents. After an authorized
rollout, validate changed endpoints: ChatGPT Responses (string input and streaming),
chat completions, or reranking as applicable. Use tiny requests to verify credentials
and record the actual serving model for routing changes.

For fallbacks, test alias resolution, destination key access, and the failure path
in isolation. Recent proxy versions strip `mock_testing_fallbacks` from incoming
requests; use direct Router tests or an isolated provider-error scenario instead.
Keep runtime claims provisional when live validation is unavailable.

## References

- `kubernetes/AGENTS.md`, `kubernetes/apps/AGENTS.md`, `kubernetes/apps/apps/AGENTS.md`
- `renovate.json` LiteLLM package rule and the `renovate-pr-triage` skill
- [Official fallback documentation](https://docs.litellm.ai/docs/proxy/reliability)
- [Official Auto Routing reference](https://docs.litellm.ai/docs/proxy/auto_routing)
