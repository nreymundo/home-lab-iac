# Headroom evaluation

LiteLLM calls the Headroom sidecar at `http://127.0.0.1:8787/v1/compress`
through its native `headroom-compression` pre-call guardrail. Clients continue
to use the existing LiteLLM URL and model names. Headroom has no Service or
ingress and receives no provider credentials.

Compression is opt-in (`default_on: false`). Attach
`"guardrails": ["headroom-compression"]` to a dedicated virtual key using
LiteLLM's `/key/generate` or `/key/update` API. For a single Chat Completions
request, add the same top-level field to the request body; for Anthropic
Messages, use `"litellm_metadata": {"guardrails": ["headroom-compression"]}`.
Use the dedicated key for Responses evaluation as well.

With an opted-in key, send `x-headroom-bypass: true` for an uncompressed
comparison. The header only disables compression; `false` does not enable it.
The configured five-second compression timeout and `fail_open` behavior let
requests continue uncompressed when Headroom fails. A persistent sidecar
readiness failure still makes the shared pod unready.

Both auto routers leave their per-hop compression settings unset, preserving
key/request activation. Setting `auto_router_routing_compression` or
`auto_router_model_compression` would override that activation policy for
the router's requests.

Headroom's writable state and model cache use an `emptyDir`, retained across
container restarts but discarded with the pod. Model artifacts may download
again after pod replacement. This is an evaluation deployment, not durable
conversation storage. LiteLLM retains native CCR retrieval handling; requests
that produce retrieval hashes can add a `headroom_retrieve` tool and buffer
streaming output while fulfilling retrieval, so measure time to first token.

## Validation after rollout

1. Check the HelmRelease, both main-pod containers, and Headroom readiness.
2. Compare identical synthetic conversations with large, repetitive tool
   results using the opted-in key and its bypass header. Check token savings,
   answer quality, and latency in LiteLLM's guardrail logs. The applied-guardrail
   header alone does not establish savings or successful compression.
3. Exercise Chat Completions, Anthropic Messages, Responses string and structured
   input, streaming, images, and tool continuations. Include both
   `cloud/codex-auto` and `cloud/glm-auto`, confirming model selection and
   reasoning effort remain correct.
4. In an isolated proxy, make Headroom unavailable and confirm the original
   request proceeds uncompressed. Do not stop the production sidecar for testing.

The exact LiteLLM release has Responses and streaming Headroom tests, but
rendered manifests do not establish provider/client compatibility. Keep normal
keys unmodified until these runtime comparisons pass. To disable compression,
remove the guardrail from the evaluation key.

References: [LiteLLM Headroom integration](https://docs.litellm.ai/docs/proxy/headroom),
[auto-router compression](https://docs.litellm.ai/docs/proxy/auto_routing#compression),
and [versioned Headroom tests](https://github.com/BerriAI/litellm/blob/v1.106.0-rc.4/tests/unit/proxy/guardrails/guardrail_hooks/test_headroom.py).
