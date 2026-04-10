# CLAUDE.md — Vault Agent Configuration

> This file is loaded at the start of every agent session. It is the single source of truth for how agents interact with this vault. Co-evolve this file with your team as conventions stabilize.

## Identity

- **Vault Name**: `{{VAULT_NAME}}` <!-- Replace during initialization -->
- **Organization**: `{{ORG_NAME}}` <!-- Replace during initialization -->
- **Vault Version**: `0.1.0`
- **Initialized**: `{{INIT_DATE}}` <!-- Replace during initialization -->
- **Primary Agent Platform**: `{{PLATFORM}}` <!-- claude-code | codex | copilot | cursor | custom -->

## Architecture

This vault follows the **Karpathy LLM Wiki** pattern with extensions for multi-agent enterprise use.

### Three-Layer Structure

```
raw/          # Layer 1: Immutable source documents. NEVER modify files here.
wiki/         # Layer 2: Agent-generated knowledge pages. Agents own this layer entirely.
memory/       # Layer 3: Operational state — decisions, logs, running notes.
```

### Support Directories

```
.vault/       # Vault configuration, rules, schemas, hooks, scripts. Human-managed.
templates/    # Frontmatter and content templates for each document type.
docs/         # Vault documentation for humans. How-to guides, onboarding.
```

### Critical Files

| File | Location | Purpose |
|------|----------|---------|
| `CLAUDE.md` | Root | Agent configuration (this file) |
| `AGENTS.md` | Root | Platform-agnostic agent instructions (mirrors this file) |
| `CODEX.md` | Root | OpenAI Codex-specific overrides |
| `index.md` | `wiki/` | Master catalog of all wiki pages |
| `log.md` | `wiki/` | Append-only chronological record of all operations |
| `status.md` | `memory/` | Current vault health and operational state |

## Operations

Agents perform exactly **three operations** on this vault:

### 1. INGEST — Process new source material

```
Trigger: New file appears in raw/ OR human requests ingestion
Steps:
  1. Read the source document in raw/
  2. Create or update a summary page in wiki/sources/
  3. Update wiki/index.md with the new entry
  4. Update 5-15 related wiki pages (concepts, entities, comparisons)
  5. Append an entry to wiki/log.md
  6. Validate all modified files against .vault/schemas/
  7. Verify tags comply with .vault/rules/tags.md
```

### 2. QUERY — Answer questions using the vault

```
Trigger: Human or agent asks a question
Steps:
  1. Read wiki/index.md to locate relevant pages
  2. Read those pages and synthesize an answer
  3. Cite sources using [[wikilinks]]
  4. Optionally file the answer back as a new wiki page
  5. Append query record to wiki/log.md
```

### 3. LINT — Health check the vault

```
Trigger: Scheduled or manual request
Steps:
  1. Check for contradictions between wiki pages
  2. Find orphan pages (no inbound links)
  3. Identify stale content (no updates in >30 days)
  4. Verify all pages have valid frontmatter
  5. Verify all tags are from the approved taxonomy
  6. Check compliance with .vault/rules/
  7. Report findings to memory/notes/lint-report-{{DATE}}.md
  8. Suggest new pages, connections, or questions
```

## Rules

### Hard Rules (Enforced — violations block commits)

All hard rules are defined in `.vault/rules/hard-rules.md`. Summary:

1. **NEVER modify files in `raw/`**. This directory is immutable.
2. **Every file in `wiki/` MUST have valid YAML frontmatter** per `.vault/schemas/frontmatter.md`.
3. **Every file in `wiki/` MUST include at least one tag** from the approved taxonomy.
4. **Markdown files MUST NOT exceed 200 lines**. Split into linked sub-pages if needed.
5. **Code files MUST be at least 500 lines** (scripts, tools, automation). Shorter code belongs inline in markdown or as snippets in a wiki page.
6. **All wiki page titles MUST be unique** across the vault.
7. **Frontmatter `updated` field MUST reflect the actual last-modified date**.
8. **No file may exist in `wiki/` without a corresponding entry in `wiki/index.md`**.
9. **Tags MUST use flat prefix notation**: `#domain/engineering`, not nested hierarchies.
10. **Binary files (images, PDFs) MUST be stored in `raw/`**, never in `wiki/` or `memory/`.

### Soft Rules (Configurable — adapt to your workflow)

All soft rules are defined in `.vault/rules/soft-rules.md`. Defaults:

1. Prefer one source ingested at a time with human review.
2. Wiki pages should target 80-150 lines for optimal agent readability.
3. Each wiki page should link to at least 3 other wiki pages.
4. Concept pages should include a "Related Concepts" section.
5. Entity pages should include a "Key Facts" structured section.
6. Source summaries should be 20-50% the length of the original.
7. Log entries should follow the format: `## [YYYY-MM-DD] operation | Title`.
8. Decision records should use the ADR (Architecture Decision Record) format.
9. Lint should run at least weekly.
10. Stale content threshold: 30 days without update triggers review.

## Frontmatter Schema

Every wiki page MUST include this YAML frontmatter:

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

## Tag Taxonomy

The complete tag taxonomy is defined in `.vault/rules/tags.md`. Tags use **flat prefix notation** for maximum agent parseability.

### Tag Prefix Categories (Summary)

| Prefix | Purpose | Example |
|--------|---------|---------|
| `domain/` | High-level business domain | `domain/engineering` |
| `type/` | Content type classification | `type/concept` |
| `lifecycle/` | Document lifecycle stage | `lifecycle/active` |
| `priority/` | Urgency or importance | `priority/critical` |
| `audience/` | Intended reader | `audience/executive` |
| `format/` | Content format | `format/runbook` |
| `dept/` | Department or team | `dept/platform` |
| `tool/` | Tool or technology | `tool/langgraph` |
| `method/` | Methodology | `method/agile` |
| `role/` | Organizational role | `role/architect` |

See `.vault/rules/tags.md` for the full taxonomy with 100+ categories.

## Agent Behavior

### Context Loading Order

1. Read this file (`CLAUDE.md`) — always loaded first
2. Read `wiki/index.md` — understand vault contents
3. Read `memory/status.md` — understand current state
4. Read `.vault/rules/hard-rules.md` — understand constraints
5. Load task-specific wiki pages as needed

### File Naming Conventions

- Wiki pages: `kebab-case.md` (e.g., `langgraph-evaluation.md`)
- Source summaries: `source-{{original-filename}}.md`
- Entity pages: `entity-{{name}}.md`
- Concept pages: `concept-{{topic}}.md`
- Comparison pages: `comparison-{{a}}-vs-{{b}}.md`
- Decision records: `decision-{{number}}-{{title}}.md`
- Log entries: Appended to `wiki/log.md`, never separate files

### Wikilink Conventions

- Use `[[relative/path/to/file.md]]` for all internal links
- Use `[[relative/path/to/file.md|Display Text]]` for display names
- Never use absolute paths
- Never use bare URLs for internal vault content

### Git Workflow

- Each agent session creates a branch: `agent/{{agent-id}}/{{task-description}}`
- Commits are atomic: one logical change per commit
- Commit messages follow: `[operation] description` (e.g., `[ingest] Added source on LangGraph benchmarks`)
- PRs require lint pass before merge
- Main branch is protected

## Initialization Checklist

When a company first clones this boilerplate:

- [ ] Replace `{{VAULT_NAME}}`, `{{ORG_NAME}}`, `{{INIT_DATE}}`, `{{PLATFORM}}` in this file
- [ ] Run `.vault/scripts/init.sh` to configure platform-specific files
- [ ] Review and customize `.vault/rules/soft-rules.md`
- [ ] Review and customize `.vault/rules/tags.md` (add domain-specific tags)
- [ ] Add company-specific context to `docs/company-context.md`
- [ ] Choose and enable hooks in `.vault/hooks/`
- [ ] Commit and push to your repository
- [ ] Begin ingesting your first source documents into `raw/`
