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

This deployment uses ConfigMap-mounted Python compatibility patches, a separate
Valkey controller for response caching, Authentik SSO, and a CNPG database.
Headroom and its installation initContainer are no longer present.

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
  `model_group_alias` entries. Explicit caller effort overrides those defaults.
  Jev uses `classifier_type: oss_classifier` with the existing
  `openrouter/~typesafe/jev-latest` decision deployment, without a new credential or
  Python routing callback. Classification failure selects Astra/high; inference
  failures use per-tier fallback chains to the existing fast/deep fallback aliases.
  `classification_mode: user_turn` retains the choice through tool continuations
  only when the client supplies a stable session identifier (for example
  `metadata.session_id`); a new human ask reclassifies. `session_affinity` remains
  false so the first model does not pin the entire conversation. Verify both chat
  and Responses routing, client effort precedence, session reuse, selected-tier
  fallbacks, and Auto-Routers UI visibility when changing this configuration.
  `cloud/decision` remains a direct Jev alias; other existing cloud/local routes
  do not opt into auto routing.
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
