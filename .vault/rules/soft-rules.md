# Soft Rules — Configurable Vault Guidelines

> These rules are recommendations, not hard enforcement. Customize them for your organization. Agents should follow these unless instructed otherwise. Violations generate warnings during lint, not commit rejections.

## SR-001: One Source at a Time

**Default**: Ingest one source document per session. Review the generated wiki pages before ingesting the next source.

**Rationale**: Batch ingestion risks cross-contamination of concepts and reduces human oversight. One-at-a-time builds understanding incrementally.

**When to override**: High-volume onboarding (e.g., importing 50 existing company docs). Use batch mode with a dedicated lint pass afterward.

---

## SR-002: Target Page Length

**Default**: Wiki pages should target **80-150 lines** (hard limit is 200). Shorter pages are fine for narrow topics. Pages approaching 200 lines should be proactively split.

---

## SR-003: Minimum Link Density

**Default**: Each wiki page should contain at least **3 wikilinks** to other pages. This ensures the knowledge graph remains connected.

**When to override**: Highly specialized pages with no natural connections. Tag them `lifecycle/orphan-candidate` for future review.

---

## SR-004: Source Summary Length

**Default**: Source summaries in `wiki/sources/` should be **20-50% of the original document length**. Summaries should capture key claims, data points, and conclusions — not reproduce the original.

---

## SR-005: Log Entry Format

**Default**: Log entries in `wiki/log.md` follow this format:

```markdown
## [YYYY-MM-DD] operation | Title
- **Agent**: agent-id or human
- **Files modified**: list of paths
- **Summary**: one-line description
```

---

## SR-006: Decision Record Format

**Default**: Decision records in `memory/decisions/` use the ADR format:

```markdown
---
title: "Decision: {{Title}}"
type: decision
status: accepted | superseded | deprecated
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags:
  - type/decision
  - domain/{{relevant-domain}}
---

## Context
What is the situation that requires a decision?

## Decision
What was decided?

## Consequences
What are the expected outcomes, both positive and negative?

## Alternatives Considered
What other options were evaluated and why were they rejected?
```

---

## SR-007: Lint Frequency

**Default**: Run a full lint pass at least **once per week**. For active vaults with daily ingestion, run lint daily.

---

## SR-008: Staleness Threshold

**Default**: Pages not updated in **30 days** are flagged as potentially stale during lint. This threshold can be adjusted per-domain (e.g., HR policies may be stable for 90+ days; engineering docs may go stale in 7 days).

**Configuration**: Set thresholds in `.vault/schemas/staleness-config.json`.

---

## SR-009: Confidence Calibration

**Default**: Use the `confidence` frontmatter field as follows:

| Value | Meaning |
|-------|---------|
| `high` | Multiple corroborating sources, recently verified |
| `medium` | Single authoritative source, not recently verified |
| `low` | Inferred, extrapolated, or based on outdated sources |
| `unverified` | No source backing, agent-generated hypothesis |

---

## SR-010: Review Gates

**Default**: Pages with `status: draft` require human review before promotion to `status: active`. Agents may create draft pages freely but should not auto-promote them.

**When to override**: Low-risk content (meeting notes, daily logs) can be auto-promoted. Configure exceptions in `.vault/schemas/auto-promote-config.json`.

---

## SR-011: Cross-Reference on Ingest

**Default**: When ingesting a new source, the agent should update **5-15 existing wiki pages** that the new source relates to. This keeps the wiki interconnected and current.

---

## SR-012: Query Filing

**Default**: When an agent answers a query and the answer is substantive (>5 sentences), file it back into the wiki as a new page or append to an existing page. This compounds knowledge over time.

---

## SR-013: Entity Page Structure

**Default**: Entity pages (people, companies, tools, products) should include:

```
- Key Facts (structured list)
- Description (2-3 paragraphs)
- Relationships (links to related entities)
- Sources (links to raw/ documents)
- Timeline (if applicable)
```

---

## SR-014: Comparison Page Structure

**Default**: Comparison pages should include:

```
- Summary (which option is recommended and why)
- Comparison Table (feature-by-feature)
- Context (when each option is appropriate)
- Sources
```

---

## SR-015: Naming Conventions for Custom Tags

**Default**: When adding organization-specific tags beyond the base taxonomy, follow these conventions:

- Use lowercase, hyphenated values: `domain/data-engineering` not `domain/DataEngineering`
- Add new tags to `.vault/rules/tags.md` before using them
- Prefix custom tags with `custom/` if they are organization-specific and unlikely to be useful in the boilerplate: `custom/acme-internal`
