---
name: litellm-config-change
description: >-
  Add or change a LiteLLM model, provider, credential, pricing entry, local
  Python patch, or cache/streaming behavior in this repo's locally-customized
  LiteLLM deployment under `kubernetes/apps/apps/ai/litellm/`. Use when the user
  says "add a model to LiteLLM", "add ZAI/OpenAI/GPT-5/Codex/GLM provider",
  "change LiteLLM caching/streaming/pricing", "bump LiteLLM image", or "fix
  LiteLLM responses/cache". Remember the image is manual-review-gated by
  `renovate.json` because local monkey-patches must keep applying. Do NOT use
  for routine app onboarding (use `k8s-app-onboarding`) or for non-LiteLLM AI
  gateway work.
---

# LiteLLM Config Change

This LiteLLM deployment is heavily customized: configmap-mounted Python patches,
a Headroom callback adapter installed via an initContainer, a sidecar Valkey
cache, SSO via Authentik, and a CNPG database. Image bumps are **always manual
review** while the local patches are active.

## When to use

- Add/remove a model or provider in `configmap.yaml`.
- Update pricing or reasoning defaults.
- Add/change credentials (provider keys, SSO, master/salt, DB URL).
- Add or modify a mounted patch (e.g. `cache_bypass.py`,
  `chatgpt_responses_streaming_patch.py`, `vllm_model_discovery.py`,
  `chatgpt_codex_catalog.py`, `zai_coding_catalog.py`, `headroom_adapter.py`).
- Change cache backend (Valkey/Redis) or streaming behavior.
- Bump the LiteLLM image tag (manual gate — see below).

Do not use for general workload onboarding or unrelated AI gateway work.

## Files in scope

```
kubernetes/apps/apps/ai/litellm/
  helmrelease.yaml          # main + valkey controllers, initContainer, mounts
  configmap.yaml            # config.yaml + all mounted Python patches
  kustomization.yaml
  cnpg-cluster.yaml         # litellm-pg
  litellm-secrets.sops.yaml        # LITELLM_MASTER_KEY, LITELLM_SALT_KEY
  litellm-db-secrets.sops.yaml     # DATABASE_URL
  litellm-credentials.sops.yaml    # provider API keys (envFrom)
```

SSO secret `litellm-sso-secret` lives under
`kubernetes/infrastructure/security/authentik/install/`.

## Workflow

1. **Identify the edit surface**:
   - Model list / pricing / router → `configmap.yaml` `config.yaml` entry.
   - Provider credentials → `litellm-credentials.sops.yaml` (SOPS) and a
     matching `envFrom`/`secretKeyRef` in `helmrelease.yaml`.
   - Behaviour patch (cache bypass, streaming, discovery, catalog) → new key in
     `configmap.yaml`, mounted `subPath` in `helmrelease.yaml` `persistence.config`,
     and imported by `sitecustomize.py` or `litellm_startup.py` as needed.
2. **Preserve the patch contract**: `PYTHONPATH=/opt/headroom:/etc/litellm` is
   set in `helmrelease.yaml` and must include any new patch path. New patches
   must be added to the main container's `advancedMounts.config` entries.
3. **Keep Headroom working**: the `install-headroom` initContainer installs to
   `/opt/headroom` from `headroom-requirements.txt` with `--require-hashes`. If
   a patch depends on a new Headroom version, update both the requirements file
   and verify the hash.
4. **Validate the patch applies** before bumping the image — patches load via
   `sitecustomize.py` at interpreter startup; a silent import failure breaks
   LiteLLM at runtime, not at deploy time.
5. **Image bump policy**: `renovate.json` marks `berriai/litellm` as manual
   review (`automerge: false`) specifically because of these patches. Treat any
   image bump as: read the upstream changelog, verify each patch still applies,
   run a smoke test (call `/health/liveliness`, `/health/readiness`, and a
   minimal `/chat/completions`). See `renovate-pr-triage`.

## Validation

```bash
# Render the LiteLLM kustomization
kubectl kustomize --load-restrictor=LoadRestrictionsNone \
  kubernetes/apps/apps/ai/litellm >/dev/null

# Repo-wide manifest + secret policy
scripts/kubeconform.sh
pre-commit run --files kubernetes/apps/apps/ai/litellm/*

# Live (only if reachable + intended)
flux get helmrelease litellm -n ai
kubectl -n ai logs deploy/litellm-main
curl -fsS https://litellm.lan.${CLUSTER_DOMAIN}/health/readiness
```

After deploying, call LiteLLM with a tiny request against each newly added
model to confirm routing and credentials.

## Anti-patterns

- Editing `configmap.yaml` without verifying the new patch is mounted in
  `helmrelease.yaml` `persistence.config.advancedMounts.main.main`.
- Bumping the LiteLLM image as a routine `chore(deps)` without re-verifying
  patches — this is exactly the failure mode `renovate.json:165-174` protects
  against.
- Adding provider keys as plaintext env vars instead of
  `litellm-credentials.sops.yaml` (blocked by pre-commit + CI).
- Changing cache backend without checking `cache_bypass.py` and the Valkey
  sidecar configuration together.
- Forgetting that `PYTHONPATH` ordering matters: `/opt/headroom` must come
  before `/etc/litellm`.

## References

- `kubernetes/apps/apps/ai/litellm/helmrelease.yaml`
- `kubernetes/apps/apps/ai/litellm/configmap.yaml`
- `renovate.json` LiteLLM package rule (manual gate)
- `kubernetes/apps/apps/AGENTS.md`, `kubernetes/apps/AGENTS.md`
