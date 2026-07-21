---
name: renovate-pr-triage
description: >-
  Triage and review Renovate dependency PRs against this repo's `renovate.json`
  policy. Use when the user says "review pending dependency PRs", "which
  Renovate PRs are safe to merge", "why didn't immich/jellyfin/litellm update",
  "is this chore(deps) PR safe", or when triaging a batch of `chore(deps):`
  PRs/commits. Produces per-PR verdicts (automerge-eligible / manual / blocked)
  grounded in the actual package rules and custom regex managers. Do NOT use for
  general PR code review (use `code-review`/`code-reviewer`) or for non-Renovate
  dependency changes.
---

# Renovate PR Triage

This repo has a non-trivial `renovate.json` with per-image version policies,
grouping, manual-review gates, and custom regex managers. Dependency churn is
~40%+ of recent history, so triage benefits from grounding in the actual rules
rather than guessing.

## When to use

- Triaging open `chore(deps):` PRs (single or batch).
- "Why didn't X update?" or "why is this PR stuck?"
- Deciding automerge eligibility for a pending PR.
- Reviewing a major or 0.x bump.

Do not use for general PR review or for hand-rolled dependency changes.

## Inputs

- PR list (`gh pr list --label dependencies,renovate --state open`) or a single
  PR number / diff.
- Optional: the user's risk appetite for a specific image.

## Workflow

1. Read `renovate.json` end to end before classifying anything.
2. For each PR, identify the affected image/chart and match it to a
   `packageRules` entry by `matchDatasources`, `matchDepNames`,
   `matchPackageNames`, `matchPaths`, and `matchUpdateTypes`.
3. Classify into one of:
   - **automerge-eligible**: minor/patch/digest of a stable image, no manual
     gate matches, `minimumReleaseAge` satisfied.
   - **manual**: major bump, 0.x current version, LiteLLM bump, or an explicit
     `automerge: false` rule.
   - **blocked / wrong**: PR proposes a tag that violates an `allowedVersions`
     regex (e.g. non-semver for Jellyfin, wrong major line for Lidarr, `-rc`
     suffix where a stable regex is enforced).
4. Flag custom-regex-managed updates: `# renovate: datasource=...` comments in
   YAML, including the `-openvino` suffix manager.
5. Note grouping: observability (`loki`, `alloy`, `kube-prometheus-stack`) and
   networking (`traefik`, `metallb`, `external-dns`) land as grouped PRs.

## This repo's specific rules (verify against current `renovate.json`)

Stable-semver pinning (regex-enforced, a non-matching tag is a policy bug):

- `linuxserver/jellyfin`, `linuxserver/tautulli` — `^\d+\.\d+\.\d+$`
- `linuxserver/lidarr` — pinned to `^3\.\d+\.\d+`
- `library/alpine`, `library/busybox` — `^\d+\.\d+\.\d+$`
- `apache/tika` — `^\d+\.\d+\.\d+\.\d+$`
- `blakeblackshear/frigate` — `^\d+\.\d+\.\d+$`
- `danny-avila/librechat-rag-api-dev-lite` — `^v\d+\.\d+\.\d+$` (semver)
- `fscorrupt/posterizarr` — `^\d+\.\d+\.\d+$`
- `immich-app/immich-server` + `immich-app/immich-machine-learning` — grouped as
  "Immich", `^v\d+\.\d+\.\d+$` (semver)

Update-type behavior:

- Minor/patch/digest of stable (`matchCurrentVersion: !/^0/`): automerge after
  `minimumReleaseAge: 5 days`.
- 0.x Kubernetes updates: automerge after 5 days stability.
- Major updates: 5-day wait, then manual review. Kubernetes majors never
  automerge.
- LiteLLM (`berriai/litellm` at `kubernetes/apps/apps/ai/litellm/helmrelease.yaml`):
  **always manual** while local monkey-patches are active. Bumping the image is
  not a routine chore here — route to `litellm-config-change`.

Custom regex managers (verify the `# renovate:` comment is present and correct):

- `-openvino` suffix tag manager (strips suffix for lookup, re-appends on
  update).
- Generic `# renovate: datasource=... depName=... [registryUrl=...]` comment
  manager (applies to `repository:`/`tag:` pairs).
- Helm chart version tracking in `helmrelease.yaml` and
  `kubernetes/components/bjw-s-defaults/kustomization.yaml`.

`lockFileMaintenance` is enabled and auto-merges.

## Output to produce

Per PR:

- **Image/chart** + current → proposed version.
- **Matched rule** (quote the `description` from `renovate.json`).
- **Verdict**: automerge-eligible / manual / blocked, with one-line reason.
- **Risk flags**: major, 0.x, breaking schema (CRDs, Helm values), known-fragile
  component (LiteLLM, Immich ML with VectorChord).
- **Suggested action**: merge / hold-for-stability / close-and-rerun / hand-roll
  because the tag rule is wrong.

## Common gotchas

- An open PR for a `-rc` or unstable tag against a stable-semver image is almost
  always a regex violation or a missing `allowedVersions` rule; do not merge it.
- A LiteLLM `chore(deps)` PR is expected to be manual; verify the local patches
  still apply before merging (see `litellm-config-change`).
- Renovate custom-regex managers depend on the literal `# renovate:` comment
  format. If a PR is missing the version bump entirely, the comment is likely
  malformed.
- Immich server + ML must move together (grouped); a lone PR for one half is
  suspicious.

## References

- `renovate.json` (authoritative — re-read before each triage)
- `kubernetes/apps/apps/ai/litellm/helmrelease.yaml` (LiteLLM manual gate path)
- `.github/workflows/ci.yml` (CI gates that must pass before merge)
