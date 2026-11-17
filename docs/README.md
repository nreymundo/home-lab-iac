# Docs

Index for the human-facing documentation in this folder. Contributor workflow
and security practices live at the repository root.

- [decisions-and-tradeoffs.md](decisions-and-tradeoffs.md) — durable control
  and automation decisions, Checkov exceptions, and backup strategy.
- [kubernetes-bootstrap.md](kubernetes-bootstrap.md) — bootstrap and restore
  runbook for the Flux-managed cluster, including registry, secrets, PVC, and
  CNPG recovery paths.
- [k3s-provisioning.md](k3s-provisioning.md) — provision K3s and manage
  node lifecycle before bootstrapping Flux.
- [ubuntu-host-provisioning.md](ubuntu-host-provisioning.md) — unified Ubuntu
  provisioning, role APIs, validation evidence and rollout requirements.
- [opencode.md](opencode.md) — how OpenCode discovers repository skills
  under `.agents/skills/`.

Root-level docs: [CONTRIBUTING.md](../CONTRIBUTING.md),
[SECURITY.md](../SECURITY.md), and [REVIEW_GUIDELINES.md](../REVIEW_GUIDELINES.md).
