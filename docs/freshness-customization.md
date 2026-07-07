# Freshness Customization

The template ships exactly **one** canonical freshness model: binary per-domain
and per-type staleness thresholds in `.vault/schemas/staleness-config.json`.
This document records the decision to keep it that way, and provides recipes
for adopters who outgrow binary thresholds and want to build richer freshness
signals in their own vault instance.

## The Template's Model

A page is either stale or it is not. The config that decides this lives in
`.vault/schemas/staleness-config.json`:

- `default_threshold_days` — fallback threshold (default: 30 days)
- `domain_thresholds` — overrides keyed by `domain/` tag
  (e.g., `domain/operations`: 14)
- `type_thresholds` — overrides keyed by frontmatter `type`
  (e.g., `type/runbook`: 14, `type/decision`: 90)
- `exempt_statuses` — pages with these statuses (`archived`, `deprecated`)
  are never flagged as stale

At lint time, `resolve_stale_threshold` (in `.vault/scripts/lib-utils.sh`)
resolves a per-file threshold by taking the **most restrictive** matching
value — the minimum of the default, any matching domain tag, and any matching
type override. `is_stale_exempt` skips exempt statuses. Both `vault-tools.sh
stale` and `vault-tools.sh lint` use this resolution; an explicit threshold
(`vault-tools.sh stale 14`) overrides the config globally for that run.

See the [Staleness Thresholds](configuration.md#staleness-thresholds) section
of the configuration reference for the full config walkthrough.

## Decision Record

**Date**: 2026-07-07

### Context

Two proposals extended the freshness model beyond binary thresholds:

- [#8](https://github.com/galimba/agentic-memory-vault/issues/8) — a
  `vault-tools.sh decay` command computing a continuous freshness score with
  exponential decay and per-type weights.
- [#12](https://github.com/galimba/agentic-memory-vault/issues/12) —
  `lifecycle/hot`, `lifecycle/warm`, and `lifecycle/glacier` tier tags plus a
  `retier` suggestion command.

Both are useful at scale, but each introduces a second freshness signal
alongside the binary thresholds. A page could then be simultaneously "not
stale" (threshold), "below min score" (decay), and tagged `lifecycle/warm`
(tier) — three signals that can and will contradict each other. Every extra
signal also expands the customization surface adopters must understand,
configure, and keep consistent.

### Decision

The template **keeps binary per-domain/per-type thresholds as its one
canonical freshness model**. Decay scoring (#8) and lifecycle tier tags (#12)
will **not** be implemented in the template. Instead, both issues are closed
as adopter customizations, with the recipes below documenting how to build
them in a vault instance.

This follows the template's design principles (see
[roadmap.md](roadmap.md#design-principles)): *boilerplate, not framework* —
if an adopter can build it in 30 minutes, document the pattern instead of
shipping code.

### Consequences

- Agents and humans read one freshness signal; there is nothing to reconcile.
- The template's configuration surface stays small: one JSON file, one
  resolution rule.
- Adopters with mature, large vaults must build decay scoring or tier tags
  themselves — but the recipes below reuse existing helpers, so the cost is
  low and the result is tailored to their content mix.

## Recipe: Continuous Decay Scoring

From [#8](https://github.com/galimba/agentic-memory-vault/issues/8). Instead
of a binary stale/fresh verdict, compute a score per page:

```text
score = weight * 0.5^(age_days / half_life_days)
```

where `weight` is a per-type multiplier and `age_days` is days since the
frontmatter `updated` date. Pages below a `min_score` threshold are surfaced
for review, worst first.

Suggested config block, added to `.vault/schemas/staleness-config.json`:

```json
"decay": {
  "half_life_days": 14,
  "min_score": 0.5,
  "type_weights": {
    "type/decision": 1.5,
    "type/runbook": 0.8,
    "type/concept": 1.0,
    "type/entity": 1.0,
    "type/source": 1.2,
    "type/report": 0.7
  }
}
```

Implementation pointers:

- Create `.vault/scripts/audits/audit-decay.sh` — audit modules in
  `.vault/scripts/audits/` are auto-globbed by `vault-tools.sh`, so a new
  module loads without touching the dispatcher's source lines. You still add
  a `cmd_decay` dispatch arm and a help-text line for a new command.
- Reuse the helpers in `lib-utils.sh`: `wiki_files` to enumerate pages,
  `extract_fm` / `fm_field` to read frontmatter, `is_stale_exempt` to skip
  archived and deprecated pages, and `resolve_stale_threshold` if you want
  per-page half-lives derived from the existing threshold config.
- Keep it **report-only**, per the vault's report-don't-mutate principle:
  print scores, never rewrite `status`, `confidence`, or tags. Acting on the
  report (e.g., archiving low-score pages) is a bulk status change and
  requires human approval per the CLAUDE.md "Ask first" boundaries.

## Recipe: Lifecycle Tier Tags

From [#12](https://github.com/galimba/agentic-memory-vault/issues/12). Add
three tags to the `lifecycle/` section of `.vault/rules/tags.md`:

- `lifecycle/hot` — referenced in the last 7 days or explicitly high-priority
- `lifecycle/warm` — referenced in the last 30 days
- `lifecycle/glacier` — older than 90 days with no recent references, status
  still active

The pre-commit hook's approved-tag loader extracts tags from the bullet lines
of `tags.md`, so adding the three bullets is the entire taxonomy change — no
hook or schema edits needed.

The critical design constraint: tiers must be **derived views of one
underlying signal** (page age against the threshold config, or a decay score
if you built the recipe above), never a second source of truth. If agents can
set tier tags independently of the signal that defines them, the tags drift
and contradict the staleness report. Recompute tiers from the signal (a
report-only `retier` suggestion command, modeled on the audit-module pattern
above, works well) and treat any mismatch as a lint finding.

Applying suggested tiers across many pages is a **bulk tag change** and
requires human approval per the CLAUDE.md "Ask first" boundaries — the
command suggests, a human applies.
