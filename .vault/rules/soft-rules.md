# Soft Rules — Configurable Vault Guidelines

> These rules are recommendations, not hard enforcement.
> Customize them for your organization.
> Agents **SHOULD** follow these unless instructed otherwise.
> Violations generate warnings during lint, not commit rejections.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** in this document are to
be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

## SR-001: One Source at a Time

**Default**: Agents **SHOULD** ingest one source document per session. Generated wiki pages **SHOULD** be reviewed before ingesting the next source.

**Rationale**: Batch ingestion risks cross-contamination of concepts and reduces human oversight. One-at-a-time builds understanding incrementally.

**When to override**: High-volume onboarding (e.g., importing 50 existing company docs). Use batch mode with a dedicated lint pass afterward.

---

## SR-002: Target Page Length

**Default**: Wiki pages **SHOULD** target **80-150 lines** (warn at 200, block at 400). Shorter pages **MAY** be used for narrow topics. Pages approaching 200 lines **SHOULD** be proactively split.

---

## SR-003: Minimum Link Density

**Default**: Each wiki page **SHOULD** contain at least **3 wikilinks** to other pages. This ensures the knowledge graph remains connected.

**When to override**: Highly specialized pages with no natural connections. Tag them `lifecycle/orphan-candidate` for future review.

---

## SR-004: Source Summary Length

**Default**: Source summaries in `wiki/sources/` **SHOULD** use absolute word
count ranges based on source length:

| Source Length | Summary Target |
|-------------|----------------|
| Under 2,000 words | 100-500 words |
| 2,000-10,000 words | 500-2,000 words |
| Over 10,000 words | 2,000-5,000 words |

Summaries **MUST NOT** exceed 5,000 words regardless of source length.
Summaries **SHOULD** capture key claims, data points, and conclusions —
not reproduce the original. For very short sources (<500 words), the
summary **MAY** be nearly as long as the original if the content is dense.

---

## SR-005: Log Entry Format

**Default**: Log entries in `wiki/log.md` **SHOULD** follow this format:

```markdown
## [YYYY-MM-DD] operation | Title
- **Agent**: agent-id or human
- **Files modified**: list of paths
- **Summary**: one-line description
```

---

## SR-006: Decision Record Format

**Default**: Decision records in `memory/decisions/` **SHOULD** use the ADR format:

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

**Default**: A full lint pass **SHOULD** run at least **once per week**. For active vaults with daily ingestion, lint **SHOULD** run daily.

---

## SR-008: Staleness Threshold

**Default**: Pages not updated in **30 days** are flagged as potentially stale during lint.
This threshold **MAY** be adjusted per-domain
(e.g., HR policies may be stable for 90+ days; engineering docs may go stale in 7 days).

**Configuration**: Set thresholds in `.vault/schemas/staleness-config.json`.

---

## SR-009: Confidence Calibration

**Default**: Agents **SHOULD** use the `confidence` frontmatter field as follows:

| Value | Meaning |
|-------|---------|
| `high` | Multiple corroborating sources, recently verified |
| `medium` | Single authoritative source, not recently verified |
| `low` | Inferred, extrapolated, or based on outdated sources |
| `unverified` | No source backing, agent-generated hypothesis |

---

## SR-010: Review Gates

**Default**: Pages with `status: draft` **SHOULD** require human review
before promotion to `status: active`. Agents **MAY** create draft pages
freely but **SHOULD NOT** auto-promote to active.

**Enforcement**: This rule is NOT automatically enforced by hooks.
Enforcement relies on one or more of:

1. **Git workflow** (recommended): Require PR reviews for branches that
   modify `status:` fields. Use `git diff` in CI to detect status
   transitions from `draft` to `active` and flag them for review.
2. **CLAUDE.md instructions**: The agent configuration tells agents not
   to set `status: active` directly. This is trust-based.
3. **Manual review**: Lint reports include draft page counts. Humans
   periodically review and promote pages.

**When to override**: Low-risk content (meeting notes, daily logs) can be
auto-promoted. Add a `auto_promote_types` list to
`.vault/schemas/staleness-config.json` to configure which page types skip
review.

---

## SR-011: Cross-Reference on Ingest

**Default**: When ingesting a new source, the agent **SHOULD** update every
existing wiki page that the new source materially affects. A "material
affect" means the source adds new information, contradicts existing
claims, or provides updated data relevant to that page.

**Guidance**: Most sources affect 5-15 pages. Use these checkpoints:

- If fewer than 3 pages are affected, verify the source isn't too narrow
  to warrant a standalone ingestion. Consider appending to an existing
  source summary instead.
- If more than 20 pages are affected, split the ingestion into focused
  passes (e.g., update entity pages first, then concept pages) and
  request a human checkpoint between passes.

---

## SR-012: Query Filing

**Default**: When an agent answers a query, the answer **SHOULD** be filed
back into the wiki ONLY if both conditions are met:

1. **Novelty**: The answer reveals knowledge not already captured in
   existing wiki pages.
2. **Reusability**: The knowledge is likely to be useful for future
   queries from other agents or humans.

One-off questions, personal preferences, and answers that simply
recombine existing wiki content **SHOULD NOT** be filed back. When filing,
agents **SHOULD** prefer appending to an existing relevant page over
creating a new page.

---

## SR-013: Entity Page Structure

**Default**: Entity pages (people, companies, tools, products) **SHOULD** include:

```
- Key Facts (structured list)
- Description (2-3 paragraphs)
- Relationships (links to related entities)
- Sources (links to raw/ documents)
- Timeline (if applicable)
```

---

## SR-014: Comparison Page Structure

**Default**: Comparison pages **SHOULD** include:

```
- Summary (which option is recommended and why)
- Comparison Table (feature-by-feature)
- Context (when each option is appropriate)
- Sources
```

---

## SR-015: Naming Conventions for Custom Tags

**Default**: When adding organization-specific tags beyond the base taxonomy, agents **SHOULD** follow these conventions:

- Use lowercase, hyphenated values: `domain/data-engineering` not `domain/DataEngineering`
- Add new tags to `.vault/rules/tags.md` before using them
- Prefix custom tags with `custom/` if they are organization-specific and unlikely to be useful in the boilerplate: `custom/acme-internal`

---

## SR-016: One Writer per Branch

**Default**: Within a single branch, `wiki/` has exactly **one writing agent**. Other agents working on the same branch write to their namespaced
scratch space in `memory/agents/<agent-id>/` instead. Scratch notes are promoted into `wiki/` by the single writer.

**Guidance**:

- Name scratch directories after the stable agent ID used in branch names: `memory/agents/claude-01/`
- Scratch notes are free-form working files; they become subject to the full wiki conventions only when promoted
- The single writer reviews, reconciles, and files scratch content into `wiki/`, updating `wiki/index.md` and `wiki/log.md` as usual

**Rationale**: One writer per branch prevents merge conflicts and semantic corruption in `wiki/` without requiring file-level locks.
Branch-per-session remains the primary isolation mechanism; this rule covers the case where multiple agents share a branch.

**When to override**: Single-agent sessions — the rule is trivially satisfied. This is a **coordination protocol, not an enforced policy**: no hook or lint check verifies it.
