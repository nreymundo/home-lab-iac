# Decisions and Trade-offs

This is the short record of durable control and automation decisions. Source
configuration remains authoritative; issues and PRs hold implementation evidence.

## Controls

GitHub Actions runs on pull requests, `master` pushes, and manual dispatches.
PRs and pushes select infrastructure jobs based on changed paths, including
Markdown under those paths. Manual dispatch runs all infrastructure checks.

| Control | Enforcement | Purpose |
| --- | --- | --- |
| Repository hygiene | Local pre-commit | Whitespace, line endings, YAML syntax, large files, and `yamllint`. |
| Layer lint and formatting | Local pre-commit | `ansible-lint`, Packer formatting, and Terraform formatting. |
| Secret guards | Local pre-commit | Block key material and plaintext Kubernetes Secrets; encrypt `*.sops.yaml`. |
| Kubeconform | Local pre-commit and CI | Render and statically validate Kubernetes manifests. |
| Trivy | Manual local hook and CI | Fail on HIGH/CRITICAL filesystem vulnerabilities and secrets. |
| Checkov | Path-filtered local pre-commit and CI | Enforce Terraform and Kubernetes policy from `.checkov.yaml`. |
| Commit messages | Local commit-msg hook and CI | Enforce the commit policy and block attribution trailers. |

`CONTRIBUTING.md`, `.pre-commit-config.yaml`, and `.github/workflows/ci.yml`
are the command and configuration references.

## Checkov exceptions

Prefer resource-local exceptions with an adjacent reason. Issue
[#676](https://github.com/nreymundo/home-lab-iac/issues/676) contains the
hardening history and validation evidence.

| Check or boundary | Reason | Revisit when |
| --- | --- | --- |
| `CKV_K8S_43` | Version tags avoid high-churn digest-only Renovate updates; use specific versions or SHAs. | Digest updates become low-noise or supply-chain requirements change. |
| Generated Flux output and SOPS files | Generated output is not hand-edited; Checkov does not decrypt Secrets. | Ownership or safe encrypted-manifest scanning changes. |
| `CKV_K8S_35`: Renovate and Immich auto-stack | Upstream jobs require environment credentials. | Native file-backed input is supported. |
| `CKV_K8S_38`: Paperless | Supported in-pod backup/sync requires narrowly scoped namespace `pods` read and `pods/exec` access. | A reliable external interface or independent authentication exists. |
| `CKV_K8S_40` | Upstream UID `1000`, kubectl-job UID `1001`, and NFS UID/GID `99:100` are current compatibility contracts. | Image compatibility or NFS ownership/ACLs change. |

## Terraform automation

Terraform roots use an S3-compatible backend for remote state. Atlantis is not deployed: in this
public repository, exposing plan output and accepting Terraform interactions
through PR comments is not worth the added credentialed webhook service and
attack surface, even with strong controls. Reconsider only with a tightly
controlled review surface, restricted ingress and credentials, strict allowlists,
and explicit apply authorization.

## Backups

A successful backup Job proves authentication and archive creation;
`pg_restore --list` on a read-only NFS mount proves the archive is readable.
Periodically restore into a disposable PostgreSQL instance to prove recovery.

## AI gateway routing and cost

Clients use stable aliases from the [LiteLLM configuration](../kubernetes/apps/apps/ai/litellm/configmap.yaml)
rather than binding to a specific model release. `local/chat` uses the local
Qwen workhorse. Open WebUI transcription takes a different approach: `cloud/stt`
sends audio to OpenAI first and falls back to `local/stt-fast` (Whisper). It is
not a local-only route. Multiple local aliases share the llama-swap backend and
do not provide independent failover if that backend is unavailable.

Subscription model entries use estimated API-equivalent prices so proxy usage
can be compared across providers. These shadow prices are not charges from the
subscription provider.

## Hindsight workload limits

The [Hindsight HelmRelease](../kubernetes/apps/apps/ai/hindsight/helmrelease.yaml)
defines four worker slots: one reserved each for retain, consolidation, and
mental-model refresh, plus one shared slot. Graph maintenance needs shared
capacity; reserving every slot prevents it from running even when the worker
is otherwise idle.

Both API and worker cap reranking at 100 candidates to reduce remote reranker
token-per-minute pressure. This trades retrieval coverage beyond the first
100 candidates for smaller requests; the reranker model and per-document token
limit remain unchanged.

Local coding-agent clients use `"reflectTimeoutMs": 60000` in
`~/.hindsight/coding-agent.json`. Persistent plugins pick up that setting in
their next session. The client deadline is separate from the server's
600-second reflect wall timeout.

Operation retention remains disabled. Historical failures are not automatically
replayed or deleted. Cancel only equivalent, parked duplicate refresh operations
through Hindsight's operations API, preserving running work and one pending
refresh per bank and mental model.
