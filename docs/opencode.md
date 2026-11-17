# OpenCode Resources

Repository-specific skills live in [`.agents/skills/`](../.agents/skills/),
which OpenCode can discover from this project. The repository does not
provide project OpenCode configuration, agents, commands, plugins, or MCP
servers.

Work from the repository or one of its subdirectories. Your OpenCode
installation supplies models, permissions, agents, and optional integrations.

## Updating Skills

Add or update `.agents/skills/<skill-name>/SKILL.md`. Include `name` and
`description` in the front matter, and document when the skill applies and
which repository-specific workflow to follow. Restart OpenCode to load the
updated instructions.
