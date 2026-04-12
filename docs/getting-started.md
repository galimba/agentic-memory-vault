# Getting Started

This guide walks you through setting up your Memory Vault, ingesting your first document, running your first query, and verifying vault health.

## Prerequisites

- **Git** 2.20+ (for branch operations and hooks)
- **Bash** 4.0+ (required by vault scripts; macOS users may need `brew install bash`)
- **Standard Unix tools**: `grep`, `awk`, `sed`, `find`, `wc`, `sort`, `uniq`, `file`, `date`
- **Obsidian** (optional) for visual browsing and graph view of the wiki

Verify your environment:

```bash
git --version       # 2.20+
bash --version      # 4.0+
```

## Clone and Initialize

1. Clone the boilerplate:

```bash
git clone https://github.com/{{GITHUB_ORG}}/{{REPO_NAME}}.git my-vault
cd my-vault
```

2. Run the initialization script:

```bash
bash .vault/scripts/init.sh
```

The script prompts for six values:

| Prompt | Example | What it does |
|--------|---------|--------------|
| Vault name | `acme-memory` | Replaces `{{VAULT_NAME}}` in all `.md` files |
| Organization | `Acme Corp` | Replaces `{{ORG_NAME}}` everywhere |
| GitHub org | `acme-corp` | Replaces `{{GITHUB_ORG}}` in URLs and config |
| Platform | `claude-code` | Sets `{{PLATFORM}}` (claude-code, codex, copilot, cursor, custom) |
| Repository name | `my-vault` | Replaces `{{REPO_NAME}}` in URLs and config |
| Maintainer | `my-team` | Sets `{{MAINTAINER}}` in CODEOWNERS and CODE_OF_CONDUCT |
| Date | (auto-detected) | Sets `{{INIT_DATE}}` to today |

The script also offers to reorganize template documentation for your instance
(README, onboarding guide, changelog), initializes git (if needed), offers to
update the remote origin, installs the pre-commit hook, and makes all scripts
executable. State is saved to `.vault/.initialized`.

3. Verify initialization:

```bash
bash .vault/scripts/vault-tools.sh doctor
```

This checks directory structure, required files, hooks, and runs a lint pass.

## First Source Ingestion

1. **Drop a markdown file into `raw/`**:

```bash
cp ~/documents/q1-engineering-retro.md raw/q1-engineering-retro.md
git checkout -b add/q1-retro
git add raw/q1-engineering-retro.md
git commit -m "Added Q1 engineering retrospective"
git push -u origin add/q1-retro
# Create and merge PR (CODEOWNERS approval required)
```

Note: The pre-commit hook unconditionally blocks commits to `raw/`.
Add files via PRs, which bypass client-side hooks at merge time.

2. **Tell your agent to ingest it**:

> "Ingest the new file in raw/q1-engineering-retro.md"

3. **What gets created**:

| File | Purpose |
|------|---------|
| `wiki/sources/source-q1-engineering-retro.md` | Summary of the source document (word count tiers per SR-004) |
| `wiki/concepts/concept-*.md` | New or updated concept pages extracted from the source |
| `wiki/entities/entity-*.md` | New or updated entity pages (people, tools, teams mentioned) |
| `wiki/index.md` | Updated with entries for all new pages |
| `wiki/log.md` | New entry recording the ingestion operation |

## First Query

Ask your agent a question about the vault contents:

> "What were the main takeaways from the Q1 engineering retrospective?"

The agent will read `wiki/index.md`, locate relevant pages, synthesize an answer, cite sources with `[[wikilinks]]`, and log the query in `wiki/log.md`.

## First Lint Pass

Run the vault health check:

```bash
bash .vault/scripts/vault-tools.sh lint
```

The lint checks, in order:

1. **Frontmatter validation** -- every wiki page has required YAML fields
2. **Tag validation** -- all tags are from the approved taxonomy
3. **Line count check** -- warns at 200 lines, blocks at 400 lines
4. **Orphan detection** -- pages with no inbound links (warning, not blocking)
5. **Staleness check** -- pages not updated in 30+ days (warning)
6. **Index completeness** -- every wiki page is registered in `wiki/index.md`

Output ends with a summary: violations (blocking) and warnings (advisory).

## Understanding the Output

After ingestion, review these files:

- **`wiki/sources/source-*.md`**: The agent's summary. Check that key claims are captured and sourced back to `[[raw/original-file.md]]`.
- **`wiki/index.md`**: Scroll to find new entries. Each should have the file path and a one-line summary.
- **`wiki/log.md`**: The latest entry records what operation was performed, which files were modified, and a brief summary.
- **`wiki/concepts/` and `wiki/entities/`**: New or updated knowledge pages. Verify the agent linked them to related pages (SR-003 recommends 3+ links per page).

## Next Steps

- Customize soft rules: [Configuration Guide](configuration.md)
- Add company context: [Company Context Template](company-context.md)
- Plan your ingestion pipeline: [Ingestion Guide](ingestion-guide.md)
- Understand the architecture: [Architecture](architecture.md)
