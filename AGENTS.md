# Repo-Wide Agent Rules

This file defines durable repo-wide behavior. Read the nearest subtree `AGENTS.md` before making changes in a specific area, and use `CONTRIBUTING.md` for contributor workflow, examples, and command details.

## Commit Messages
- Follow the commit message format defined in `CONTRIBUTING.md`.
- Keep the commit subject limited to the requested change summary.
- Do not add attribution to a person, tool, or AI assistant unless explicitly instructed.

## Git Workflow
- Before committing or pushing, verify `git status`, the current branch and upstream, and the intended commit target. Use a dedicated Git worktree when concurrent branch changes or isolated amendment work makes the active worktree ambiguous. Before amending or force-pushing, confirm the target is the branch tip and that no unrelated commits will be rewritten.

## What To Do
- Prefer changing source-of-truth files over mutating live systems or generated artifacts.
- Use the repo's GitOps workflow when a Kubernetes change can be expressed in git.
- Keep changes narrowly scoped to the user's request.
- Before proposing a new design, recovery workflow, or external research, inspect relevant in-repo sibling implementations first.
- When a proven local pattern exists, adapt it directly; do not add abstractions, safeguards, or recovery procedures unless the existing pattern demonstrably cannot meet the requirement.
- For an integration that crosses manifests or namespaces, trace the complete proven contract before editing: source/provider, namespace delivery mechanism, and consumer. Do not replace a shared-secret replication pattern with copied workload-local credentials.
- For a parameterized URL, hostname, or ingress value, copy the complete matching sibling expression. Do not infer where a variable belongs from a rendered hostname.
- Keep secret ownership in its source-of-truth layer: workload-local app values under `kubernetes/apps/apps/`, shared service values under `kubernetes/infrastructure/`, cluster identity under `kubernetes/clusters/production/`, and Ansible-only values under `ansible/secrets/`. Do not cross those boundaries because the files share SOPS syntax.
- Stop discovery only after direct evidence identifies the root cause and an in-repo reference identifies the minimal Git fix. A failing hop, symptom, or plausible configuration theory is not sufficient.
- Validate changes with the most direct evidence available for the kind of change you made.

## Change Discipline
- For an unfamiliar configuration or integration change, finish evidence gathering and state the complete proposed source change, validation, and expected rollout before editing.
- A request to explain, review, or pause supersedes earlier approval. Do not edit, commit, revert, or push until fresh approval is given.

## jCodeMunch Exploration
- When jCodeMunch MCP tools are available and this repository is indexed, prefer them for unfamiliar code exploration, symbol and text search, dependency/reference tracing, change-impact analysis, and task-context assembly.
- Use native tools for known paths, complete reads of process-control files such as `AGENTS.md` and `README.md`, command output, test output, files outside the index, and pre-edit line-number verification.
- Fall back to native tools when the index is unavailable or stale.
- Never index decrypted secrets, credential material, or local override files. Keep them excluded from the index even when they are ignored by git.

## What Not To Do
- Do not patch, apply, edit, scale, or restart Kubernetes resources directly when the repo can express the change.
- Do not edit generated artifacts as if they were normal source files.
- Never commit plaintext secrets, private keys, or unencrypted Kubernetes Secret manifests.
- Do not patch a `*.sops.yaml` document directly, including its unencrypted metadata. Use SOPS to re-encrypt the complete document after a change, then verify it with `sops --decrypt`; the SOPS MAC covers the whole document.
- Treat Age recipient or `.sops.yaml` rule changes as high-risk key-management work with no routine undocumented procedure; do not make them during ordinary secret creation, editing, or rotation.
- Do not broaden a narrowly requested fix into adjacent cleanup.

## Remote Host Access
- Before assuming how to reach a host — alias, `ProxyJump` hop, `IdentityFile`, or port — check `~/.ssh/config`.
- `~/.ssh/config` may `Include` other files (e.g. `~/.ssh/conf.d/*` or per-host config); check those too, not just the top-level file.

## Validation And Evidence
- Do not present a config-only theory as a confirmed root cause when live evidence is available.
- Before claiming a fix, use the most direct evidence available in the current environment.
- If live validation is not possible, say so explicitly and describe the result as provisional.
- After a runtime fix, validate against the original failure mode whenever current access allows it.
