# Repo-Wide Agent Rules

This file defines durable repo-wide behavior. Read the nearest subtree `AGENTS.md` before making changes in a specific area, and use `CONTRIBUTING.md` for contributor workflow, examples, and command details.

## Commit Messages
- Follow the commit message format defined in `CONTRIBUTING.md`.
- Keep the commit subject limited to the requested change summary.
- Do not add attribution to a person, tool, or AI assistant unless explicitly instructed.

## Git Workflow
- When creating or updating a pull request, follow the pull request description policy in `CONTRIBUTING.md`.
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
- Keep one-time remediation, cleanup, and migration steps out of persistent code, configuration, roles, and variables unless the user explicitly requests they be persisted. Perform authorized one-time operations separately; commit only the ongoing desired state.
- Do not create README files, per-folder documentation, evaluation guides, or runbooks unless the user explicitly requests that documentation. Touching a folder or implementing a feature does not authorize adding documentation there. Keep detailed explanations in the chat; do not substitute another documentation filename or expand the PR description to hold unsolicited documentation. PR descriptions must follow the concise policy in `CONTRIBUTING.md`.
- Across every app and layer, do not create a new test folder or commit an ad hoc test harness unless the user explicitly requests it. When no test folder exists for the affected code, keep one-off validation scripts outside the repository. Authorization to validate a change does not authorize adding test infrastructure.
- Before editing, check the planned changes against every applicable repo and skill requirement, including ownership, reference patterns, asset formats, and validation. Do not replace those requirements with implementation preferences.
- For an unfamiliar configuration or integration change, finish evidence gathering and state the complete proposed source change, validation, and expected rollout before editing.
- During already-authorized implementation, questions, explanations, status requests, and reviews are steering, not cancellation. Answer or review, then continue the authorized work, including fixes within the requested scope. Do not require fresh approval solely because the user asked a question or requested a review.
- Stop mutations when the user explicitly asks to pause, stop, or perform a read-only review, withdraws approval, or changes the scope in a way that requires clarification. A standalone review request does not authorize implementing its findings.
- Carry authorized changes through the required validation and requested delivery steps, including commits and pushes when authorized. Do not substitute a findings report or a promise for an explicitly requested fix. If a step is blocked, state the concrete blocker and complete the unaffected work without asking again for permission already granted.

## Editor Schema Metadata
- For new YAML files, and for existing YAML files lacking a schema directive that are being materially modified, add a `# yaml-language-server: $schema=<url>` directive pointing at the maintained schema when one exists. This is the root file's domain: GitHub Actions workflows, tooling configs (`.pre-commit-config.yaml`, `.checkov.yaml`, and similar), and any other YAML outside an owned subtree. Do not retrofit directives into files you are not otherwise touching.
- Kubernetes YAML follows `kubernetes/AGENTS.md`, which mandates the same rule for custom-resource manifests.
- Ansible YAML does not take schema directives: it is validated by the ansible language server and ansible-lint, and generic YAML schemas produce false positives on Ansible constructs.
- Terraform and Packer are HCL, not YAML; they use their native language servers and no schema comments.
- Do not mass-annotate files, annotate SOPS-encrypted files, or treat editor metadata as a replacement for validation.

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

## Reviewer Rules
- AI and human reviewers must read `REVIEW_GUIDELINES.md` at the repo root
  before reviewing. It defines accepted design choices that must not be
  flagged as findings and the expected review discipline.

## Validation And Evidence
- Do not present a config-only theory as a confirmed root cause when live evidence is available.
- Before claiming a fix, use the most direct evidence available in the current environment.
- If live validation is not possible, say so explicitly and describe the result as provisional.
- After a runtime fix, validate against the original failure mode whenever current access allows it.
