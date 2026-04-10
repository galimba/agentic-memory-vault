---
title: "Frontmatter Schema"
type: concept
created: {{INIT_DATE}}
updated: {{INIT_DATE}}
status: active
tags:
  - type/concept
  - lifecycle/active
  - domain/engineering
owner: human
confidence: high
---

# Frontmatter Schema

Defines the required and optional YAML frontmatter fields for all wiki pages. Enforced by the pre-commit hook (HR-002).

## Required Fields

| Field | Type | Values | Enforced |
|-------|------|--------|----------|
| `title` | string | Any unique title | HR-002, HR-006 |
| `type` | enum | `concept`, `entity`, `source`, `comparison`, `decision`, `report`, `index` | HR-002 |
| `created` | date | `YYYY-MM-DD` | HR-002 |
| `updated` | date | `YYYY-MM-DD` | HR-002, HR-007 |
| `status` | enum | `draft`, `active`, `review`, `archived`, `deprecated` | HR-002 |
| `tags` | list | At least one tag from `.vault/rules/tags.md` | HR-003 |

## Optional Fields

| Field | Type | Values | Purpose |
|-------|------|--------|---------|
| `sources` | list | Wikilinks to `raw/` files | Provenance tracking |
| `related` | list | Wikilinks to other wiki pages | Knowledge graph |
| `owner` | enum | `agent`, `human`, or a team name | Responsibility |
| `confidence` | enum | `high`, `medium`, `low`, `unverified` | Trust level (SR-009) |

## Example

```yaml
---
title: "LangGraph Evaluation Patterns"
type: concept
created: 2025-01-15
updated: 2025-01-20
status: active
sources:
  - "[[raw/langgraph-benchmarks-2025.pdf]]"
related:
  - "[[wiki/concepts/concept-agent-evaluation.md]]"
  - "[[wiki/entities/entity-langgraph.md]]"
tags:
  - domain/engineering
  - type/concept
  - tool/langgraph
  - lifecycle/active
owner: agent
confidence: high
---
```

## Validation

- The pre-commit hook (`.vault/hooks/pre-commit.sh`) validates HR-002 through HR-009
- The CLI tool validates individual files: `.vault/scripts/vault-tools.sh validate <file>`
- The `updated` field must match the actual last-modified date within ±1 day (HR-007)
- The `title` field must be unique across all wiki pages (HR-006)
- All tags must exist in `.vault/rules/tags.md` and use flat prefix notation (HR-003, HR-009)

## Notes

- Frontmatter delimiters are `---` on their own line
- YAML parsing extracts content between the first and second `---` markers
- Fields are case-sensitive
- List fields use YAML list syntax (indented with `- ` prefix)
