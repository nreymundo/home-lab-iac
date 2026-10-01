# Review Guidelines

Reviewer-only rules for human and AI reviewers of this repository. These are
kept separate from `AGENTS.md` so contributor-facing agent rules and
reviewer-facing policy don't get entangled. Agents reviewing pull requests in
this repo must read this file first.

## Accepted Design Choices

These patterns are deliberate. Do not flag them as findings without new, specific evidence:

- **Privileged containers inside isolated VMs.** Sandbox/DinD-style runners may run privileged when the VM itself is the isolation boundary. Privileged-in-isolated-VM is not privileged-on-host.
- **Mutable image tags (`:latest`, major tags).** Updates are pulled by tag on Renovate's schedule, not SHA-pinned. Do not recommend digest pinning.
- **Internal-network endpoints without TLS verification.** Proxmox/LiteLLM/other LAN APIs skip TLS verification by design; the network is the trust boundary.
- **VLAN assignments.** Service VLAN placement is deliberate per-network design, not "default/shared by accident."
- **Authentik blueprint authority.** Repository blueprints are the source of truth for the Authentik configuration and group membership they declare. Reapplication overwrites out-of-band changes to those managed fields; `state: present` with `attrs.users` intentionally replaces the membership list. Make changes in the blueprint, not the UI. Do not recommend `state: created` to preserve out-of-band membership changes.

Deviations from these are design questions to ask, not blockers to raise.

## Review Discipline

- Scope every finding to the PR's diff. Do not review, flag, or summarize files outside the changed-file list.
- Base each finding on the change itself or on new, specific evidence — not on the absence of a pattern used elsewhere in the repo.
- Verdicts are binary: approve (no blockers) or request changes (at least one blocker). Minor findings and notes never block approval.
- Findings must warrant action. If nothing needs to change, say so plainly instead of inventing polish items.
- A previously reviewed and accepted pattern (including anything in Accepted Design Choices) is settled; do not re-litigate it on later PRs.
- New Authentik group names use lowercase words separated by hyphens (for example, `continuwuity-users`). Do not require renaming existing groups unless an explicit migration is requested.
