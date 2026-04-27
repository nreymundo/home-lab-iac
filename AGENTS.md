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
- Validate changes with the most direct evidence available for the kind of change you made.

## What Not To Do
- Do not patch, apply, edit, scale, or restart Kubernetes resources directly when the repo can express the change.
- Do not edit generated artifacts as if they were normal source files.
- Never commit plaintext secrets, private keys, or unencrypted Kubernetes Secret manifests.
- Do not broaden a narrowly requested fix into adjacent cleanup.

## Validation And Evidence
- Do not present a config-only theory as a confirmed root cause when live evidence is available.
- Before claiming a fix, use the most direct evidence available in the current environment.
- If live validation is not possible, say so explicitly and describe the result as provisional.
- After a runtime fix, validate against the original failure mode whenever current access allows it.
