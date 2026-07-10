# CODEX.md — OpenAI Codex Adapter

> Codex entry point. The canonical agent specification is `AGENTS.md` — read it
> in full before any vault operation. This file contains only Codex-specific
> overrides (HR-012: agents must not modify this file, `AGENTS.md`, or
> `CLAUDE.md`; changes require human PRs).

## Context Loading

1. This file (`CODEX.md`)
2. `AGENTS.md` — the full specification: operations, hard rules, boundaries, schemas
3. Then continue with the Context Loading Order defined in `AGENTS.md` (`MEMORY.md`, `wiki/index.md`, `memory/status.md`, `.vault/rules/hard-rules.md`)

## Commit Messages

When Codex creates commits, append an agent trailer to the standard `[operation] description` format from `AGENTS.md`:

```
[operation] description

Agent: codex
Session: {{session-id}}
```

## Overrides

None. All hard rules, soft rules, boundaries, frontmatter schemas, and tag
taxonomies apply exactly as documented in `AGENTS.md`.
