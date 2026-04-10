# Memory Vault Boilerplate

A structured, agent-first knowledge base for organizations using AI agents (Claude Code, Codex, Copilot, Cursor) alongside human teams. Clone, initialize, and start building institutional memory that both humans and AI agents can read, write, and reason over.

## Architecture

Based on the [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern, extended for enterprise multi-agent use.

```
raw/              Immutable source documents (human-managed)
wiki/             Agent-generated knowledge (agent-managed)
  sources/        Summaries of ingested documents
  entities/       Pages about people, companies, tools
  concepts/       Explanations of ideas, patterns, principles
  comparisons/    Side-by-side analyses
  index.md        Master catalog — agents read this first
  log.md          Append-only operations log
memory/           Operational state
  decisions/      Architecture and business decision records
  logs/           Agent session logs
  notes/          Running notes, lint reports
  status.md       Current vault health
.vault/           Configuration (human-managed)
  rules/          Hard rules, soft rules, tag taxonomy
  schemas/        Frontmatter and content schemas
  hooks/          Git pre-commit enforcement
  scripts/        CLI tools (lint, status, diagnostics)
templates/        Document templates for each content type
docs/             Human documentation
```

## Quick Start

```bash
git clone https://github.com/your-org/memory-vault-boilerplate.git my-vault
cd my-vault
bash .vault/scripts/init.sh
```

## Three Operations

Agents perform exactly three operations: **INGEST** (process new sources), **QUERY** (answer questions from the vault), **LINT** (health-check the vault). See `CLAUDE.md` for full specification.

## Rules

Hard rules (enforced by git hooks) ensure vault integrity. Soft rules (configurable) guide agent behavior. See `.vault/rules/` for details.

## Tag System

200+ approved tags using flat prefix notation (`domain/engineering`, `type/concept`, `lifecycle/active`). See `.vault/rules/tags.md` for the full taxonomy.

## License

MIT
