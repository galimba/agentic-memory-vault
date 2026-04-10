# CODEX.md — OpenAI Codex Overrides

> Codex-specific configuration that extends `AGENTS.md`. Read `AGENTS.md` first for the full vault specification. This file only contains overrides and Codex-specific guidance.

## Platform

This vault instance uses OpenAI Codex as its primary agent platform.

## Codex-Specific Behavior

### File Access

Codex operates in a sandboxed environment. When working with this vault:

- Read `AGENTS.md` for the full operational specification
- All vault operations (INGEST, QUERY, LINT) follow the same steps as documented in `AGENTS.md`
- Use the CLI tool at `.vault/scripts/vault-tools.sh` for diagnostics

### Context Loading

Codex should load context in this order:

1. This file (`CODEX.md`) — Codex-specific overrides
2. `AGENTS.md` — Full operational specification
3. `wiki/index.md` — Vault contents catalog
4. `memory/status.md` — Current vault state

### Commit Messages

When Codex creates commits, use this format:

```
[operation] description

Agent: codex
Session: {{session-id}}
```

## Overrides

No overrides from the base `AGENTS.md` specification. All hard rules, soft rules, frontmatter schemas, and tag taxonomies apply as documented.

## References

- Platform-agnostic instructions: `AGENTS.md`
- Full specification: `CLAUDE.md`
- Hard rules: `.vault/rules/hard-rules.md`
- Tag taxonomy: `.vault/rules/tags.md`
