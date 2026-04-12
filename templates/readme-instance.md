# {{VAULT_NAME}}

Knowledge vault for {{ORG_NAME}} -- a git-based knowledge base managed by AI agents and humans.

Built from the [agentic-memory-vault](https://github.com/galimba/agentic-memory-vault) template.

## Quick Start

```bash
# Clone and set up
git clone https://github.com/{{GITHUB_ORG}}/{{REPO_NAME}}.git
cd {{REPO_NAME}}

# Drop a source document and tell your agent to ingest it
cp ~/documents/your-doc.md raw/
# In your agent: "Ingest the new file in raw/your-doc.md"

# Verify vault health
bash .vault/scripts/vault-tools.sh doctor
```

## How It Works

Agents perform three operations:

- **INGEST** -- Process source documents from `raw/` into structured wiki pages
- **QUERY** -- Answer questions using vault contents, with `[[wikilink]]` citations
- **LINT** -- Health-check the vault for stale content, orphans, and rule violations

## Directory Map

```
raw/          Source documents (immutable -- add via PRs)
wiki/         Agent-generated knowledge pages
  sources/    Summaries of ingested documents
  concepts/   Ideas, patterns, principles
  entities/   People, companies, tools
  index.md    Master catalog -- agents read this first
  log.md      Append-only operations log
memory/       Operational state (decisions, logs, notes)
.vault/       Configuration (rules, schemas, hooks, scripts)
templates/    Document templates for each content type
docs/         Guides and reference documentation
```

## Critical Rules

These rules are enforced by git hooks and will block your commit:

| Rule | What it means |
|------|--------------|
| HR-001 | Never modify files in `raw/` -- it is immutable |
| HR-002 | Every wiki page needs valid YAML frontmatter |
| HR-004 | Markdown pages must stay under 400 lines (warning at 200) |
| HR-008 | Every wiki page must be registered in `wiki/index.md` |
| HR-014 | Never delete files in `wiki/` or `memory/` -- set `status: archived` instead |

Full rules: `.vault/rules/hard-rules.md` and `.vault/rules/soft-rules.md`

## Contributing Knowledge

| Who | How |
|-----|-----|
| **Engineers** | Clone the repo, drop sources in `raw/` via PRs, tell your agent to ingest. See [Onboarding Guide](docs/onboarding.md). |
| **Non-technical contributors** | Upload files to `raw/` via GitHub web UI, review agent-generated pages, flag stale info. See [Onboarding Guide](docs/onboarding.md). |
| **AI agents** | Read `wiki/index.md` first, then `CLAUDE.md` or `AGENTS.md`. Perform INGEST, QUERY, or LINT operations. |

## Useful Commands

```bash
bash .vault/scripts/vault-tools.sh doctor    # Full diagnostics
bash .vault/scripts/vault-tools.sh lint      # Run lint checks
bash .vault/scripts/vault-tools.sh status    # View vault status
bash .vault/scripts/vault-tools.sh stale     # Find stale pages
bash .vault/scripts/vault-tools.sh help      # See all commands
```

## Links

- [Onboarding Guide](docs/onboarding.md) -- Detailed guide for new team members
- [Getting Started](docs/getting-started.md) -- Setup, first ingestion, first query
- [Template Reference](docs/vault-template-readme.md) -- Full architecture, rules, and FAQ
- [Contributing](CONTRIBUTING.md) -- How to contribute to this vault
- [Agent Configuration](CLAUDE.md) -- Full agent specification

## Platform Support

| Platform | Config File |
|----------|-------------|
| Claude Code | `CLAUDE.md` |
| Codex | `CODEX.md` |
| Copilot / Cursor / Other | `AGENTS.md` |

## License

[Apache License 2.0](LICENSE)
