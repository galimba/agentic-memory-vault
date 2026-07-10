# CLAUDE.md — Claude Code Adapter

> Loaded automatically by Claude Code at session start. The canonical agent
> specification is `AGENTS.md`, imported below — all rules, operations,
> boundaries, and schemas live there. Do not duplicate its content here
> (HR-012: agents must not modify this file, `AGENTS.md`, or `CODEX.md`;
> changes require human PRs).

@AGENTS.md

## Claude Code Specifics

- Follow the Context Loading Order in `AGENTS.md` after this file loads: `MEMORY.md`, then `wiki/index.md`, `memory/status.md`, `.vault/rules/hard-rules.md`.
- Bundled skills are installed to `.claude/skills/` by `init.sh` (canonical copies live in `.vault/skills/`). The `vault-ops` skill is the playbook for INGEST / QUERY / LINT — use it for any vault operation.
- After pulling template updates, re-copy skills: `mkdir -p .claude/skills && cp -r .vault/skills/. .claude/skills/`

## Initializing a New Vault

If the Identity section of `AGENTS.md` still contains unreplaced `{{...}}`
placeholder values, the vault is uninitialized: stop and ask the human to run
`bash .vault/scripts/init.sh`. Setup guide: `docs/getting-started.md`.
