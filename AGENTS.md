# Repo-Wide Agent Rules

This file defines durable repo-wide behavior. Read the nearest subtree `AGENTS.md` before making changes in a specific area, and use `CONTRIBUTING.md` for contributor workflow, examples, and command details.

## Commit Messages
- Follow the commit message format defined in `CONTRIBUTING.md`.
- Keep the commit subject limited to the requested change summary.
- Do not add attribution to a person, tool, or AI assistant unless explicitly instructed.

## What To Do
- Prefer changing source-of-truth files over mutating live systems or generated artifacts.
- Use the repo's GitOps workflow when a Kubernetes change can be expressed in git.
- Keep changes narrowly scoped to the user's request.
- Before proposing a new design, recovery workflow, or external research, inspect relevant in-repo sibling implementations first.
- When a proven local pattern exists, adapt it directly; do not add abstractions, safeguards, or recovery procedures unless the existing pattern demonstrably cannot meet the requirement.
- Keep investigation proportional: stop discovery once direct runtime evidence and an in-repo reference identify the minimal Git fix.
- Validate changes with the most direct evidence available for the kind of change you made.

## jCodeMunch Exploration
- When jCodeMunch MCP tools are available and this repository is indexed, prefer them for unfamiliar code exploration, symbol and text search, dependency/reference tracing, change-impact analysis, and task-context assembly.
- Use native tools for known paths, complete reads of process-control files such as `AGENTS.md` and `README.md`, command output, test output, files outside the index, and pre-edit line-number verification.
- Fall back to native tools when the index is unavailable or stale.
- Never index decrypted secrets, credential material, or local override files. Keep them excluded from the index even when they are ignored by git.

## What Not To Do
- Do not patch, apply, edit, scale, or restart Kubernetes resources directly when the repo can express the change.
- Do not edit generated artifacts as if they were normal source files.
- Never commit plaintext secrets, private keys, or unencrypted Kubernetes Secret manifests.
- Do not broaden a narrowly requested fix into adjacent cleanup.

## Remote Host Access
- Before assuming how to reach a host — alias, `ProxyJump` hop, `IdentityFile`, or port — check `~/.ssh/config`.
- `~/.ssh/config` may `Include` other files (e.g. `~/.ssh/conf.d/*` or per-host config); check those too, not just the top-level file.

## Validation And Evidence
- Do not present a config-only theory as a confirmed root cause when live evidence is available.
- Before claiming a fix, use the most direct evidence available in the current environment.
- If live validation is not possible, say so explicitly and describe the result as provisional.
- After a runtime fix, validate against the original failure mode whenever current access allows it.
