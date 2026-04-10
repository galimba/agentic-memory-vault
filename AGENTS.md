# AGENTS.md — Platform-Agnostic Agent Instructions

> This file mirrors the core instructions from `CLAUDE.md` in a platform-neutral format.
> Any AI agent (Claude Code, Codex, Copilot, Cursor, or custom) should be able to
> operate this vault by reading this file.

## Vault Identity

- **Vault Name**: `{{VAULT_NAME}}`
- **Organization**: `{{ORG_NAME}}`
- **Vault Version**: `0.1.0`
- **Initialized**: `{{INIT_DATE}}`

## Architecture

Three-layer knowledge vault based on the Karpathy LLM Wiki pattern:

| Layer | Directory | Owner | Purpose |
|-------|-----------|-------|---------|
| 1 | `raw/` | Human | Immutable source documents. NEVER modify. |
| 2 | `wiki/` | Agent | Generated knowledge pages. Agents own this. |
| 3 | `memory/` | Agent | Operational state: decisions, logs, notes. |

Support directories: `.vault/` (config), `templates/` (page templates), `docs/` (human docs).

## Context Loading Order

1. Read this file (`AGENTS.md`) or `CLAUDE.md`
2. Read `wiki/index.md` — discover vault contents
3. Read `memory/status.md` — understand current state
4. Read `.vault/rules/hard-rules.md` — understand constraints
5. Load task-specific wiki pages as needed

## Three Operations

### INGEST — Process new source material

1. Read the source document in `raw/`
2. Create or update a summary page in `wiki/sources/`
3. Update `wiki/index.md` with the new entry
4. Update 5-15 related wiki pages (concepts, entities, comparisons)
5. Append an entry to `wiki/log.md`
6. Validate all modified files against `.vault/schemas/`
7. Verify tags comply with `.vault/rules/tags.md`

### QUERY — Answer questions using the vault

1. Read `wiki/index.md` to locate relevant pages
2. Read those pages and synthesize an answer
3. Cite sources using `[[wikilinks]]`
4. Optionally file the answer back as a new wiki page
5. Append query record to `wiki/log.md`

### LINT — Health check the vault

1. Check for contradictions between wiki pages
2. Find orphan pages (no inbound links)
3. Identify stale content (no updates in >30 days)
4. Verify all pages have valid frontmatter
5. Verify all tags are from the approved taxonomy
6. Check compliance with `.vault/rules/`
7. Report findings to `memory/notes/lint-report-{{DATE}}.md`
8. Suggest new pages, connections, or questions

## Hard Rules (Non-Negotiable)

1. **NEVER modify files in `raw/`**
2. **Every `wiki/` file MUST have valid YAML frontmatter**
3. **Every `wiki/` file MUST include at least one approved tag**
4. **Markdown files MUST NOT exceed 200 lines** (split into linked sub-pages)
5. **Code files MUST be at least 500 lines**
6. **All wiki page titles MUST be unique**
7. **Frontmatter `updated` field MUST reflect actual last-modified date**
8. **Every `wiki/` file MUST be registered in `wiki/index.md`**
9. **Tags MUST use flat prefix notation**: `prefix/value`
10. **Binary files MUST be stored in `raw/`** only

Full details: `.vault/rules/hard-rules.md`

## Frontmatter Schema

```yaml
---
title: "Page Title"
type: concept | entity | source | comparison | decision | report | index
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: draft | active | review | archived | deprecated
sources:
  - "[[raw/filename.md]]"
related:
  - "[[wiki/concepts/related-page.md]]"
tags:
  - domain/engineering
  - type/concept
  - lifecycle/active
owner: agent | human | team-name
confidence: high | medium | low | unverified
---
```

## File Naming

- Wiki pages: `kebab-case.md`
- Source summaries: `source-{{original-filename}}.md`
- Entity pages: `entity-{{name}}.md`
- Concept pages: `concept-{{topic}}.md`
- Comparison pages: `comparison-{{a}}-vs-{{b}}.md`
- Decision records: `decision-{{number}}-{{title}}.md`

## Wikilinks

- Use `[[relative/path/to/file.md]]` for all internal links
- Use `[[relative/path/to/file.md|Display Text]]` for display names
- Never use absolute paths

## Git Workflow

- Branch per session: `agent/{{agent-id}}/{{task-description}}`
- Atomic commits: `[operation] description`
- PRs require lint pass before merge
- Main branch is protected

## References

- Full specification: `CLAUDE.md`
- Tag taxonomy: `.vault/rules/tags.md`
- Soft rules: `.vault/rules/soft-rules.md`
- Templates: `templates/`
