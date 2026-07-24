# OpenCode Resources

This repository keeps only project-specific OpenCode skills in
`.opencode/skills/`. It does not provide a project OpenCode configuration,
agents, commands, plugins, or MCP servers.

OpenCode loads the skills when working in this repository or one of its
subdirectories. The active OpenCode installation supplies all other behavior,
including models, permissions, agents, and optional integrations.

## Updating Skills

Add or update a skill as `.opencode/skills/<skill-name>/SKILL.md`. Each skill
should describe when it applies and contain the repository-specific workflow it
needs. Restart OpenCode after changing a skill so the updated instructions are
loaded.
