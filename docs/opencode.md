# OpenCode Integration

This repository configures the project-scoped jCodeMunch MCP server in
`.opencode/opencode.json`. OpenCode starts it only while working in this
repository or one of its subdirectories.

## Prerequisite

Install [uv](https://docs.astral.sh/uv/) so `uvx` is available on `PATH`.
The first OpenCode session that starts the MCP downloads the pinned
`jcodemunch-mcp` version. Later sessions reuse uv's local package cache.

If `uv`, a compatible Python runtime, or network access for the first download
is unavailable, OpenCode remains usable but jCodeMunch will be unavailable for
that session.

## Local Data

jCodeMunch stores its index and cached source outside the repository at:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/jcodemunch
```

The directory is local to each machine and is not version controlled. A fresh
clone therefore needs to be indexed independently. Ask OpenCode to index the
current project before using jCodeMunch exploration tools.

The project configuration disables anonymous savings telemetry, remote AI
summaries, cross-repository traversal, and persistent session statistics.

## Updates

The MCP version is intentionally pinned in `.opencode/opencode.json`. Update
that pin deliberately after reviewing the jCodeMunch release and restart
OpenCode for a configuration change to take effect.
