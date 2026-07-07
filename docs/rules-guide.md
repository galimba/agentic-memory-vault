# Rules Guide — Understanding and Configuring Vault Governance

This guide explains how the vault's rule system works, how to customize
it for your organization, and how to create new rules.

## How Rules Work

The vault enforces two categories of rules:

**Hard rules** (HR-001 through HR-015) are non-negotiable constraints
enforced by the pre-commit git hook. A commit that violates any hard
rule is rejected. Hard rules protect vault integrity — they prevent
data loss, corruption, and security breaches.

**Soft rules** (SR-001 through SR-016) are configurable guidelines
checked during lint operations. Violations generate warnings, not
rejections. Soft rules encode best practices that vary by organization.

## Enforcement Layers

| Layer | What it catches | When it runs |
|-------|----------------|--------------|
| Pre-commit hook | Hard rule violations | Every commit |
| CI pipeline | Lint warnings + hard rules | Every PR |
| Lint (`vault-tools.sh`) | Soft rule violations | Weekly / on-demand |
| Branch protection | Unauthorized merges | On merge to main |
| CODEOWNERS | Unreviewed critical changes | On PR review |
| CLAUDE.md instructions | Agent behavioral constraints | Every session |

The first three are automated. The last three require GitHub config.

## Configurable Thresholds

| Rule | Default | Config location | Notes |
|------|---------|----------------|-------|
| HR-004 warn | 200 lines | `pre-commit.sh` `WARN_MARKDOWN_LINES` | Lower for dense vaults |
| HR-004 max | 400 lines | `pre-commit.sh` `MAX_MARKDOWN_LINES` | Raise cautiously |
| HR-005 warn | 400 lines | `pre-commit.sh` `WARN_CODE_LINES` | Lower for small modules |
| HR-005 max | 600 lines | `pre-commit.sh` `MAX_CODE_LINES` | Rarely needs change |
| SR-008 stale | 30 days | `staleness-config.json` | Set per-domain |
| Rate: sources | 10/session | `CLAUDE.md` | Higher for onboarding |
| Rate: pages | 25/commit | `CLAUDE.md` | Higher during refactors |

Edit the config location and commit. Changes take effect immediately
for hooks, next run for lint.

## Rule Interaction and Precedence

Hard rules always take precedence over soft rules. Agent instruction
rules (CLAUDE.md) are trust-based, not enforcement-based. Design
critical constraints as hard rules, not just CLAUDE.md instructions.

Multiple rules may apply to the same file. All are checked
independently — a file must pass every applicable rule.

## When to Create New Rules

**Add a hard rule** when a security vulnerability, recurring agent
error, or data integrity issue has a detectable pattern that can be
validated at commit time.

**Add a soft rule** when a best practice emerges from usage patterns,
a quality standard needs documentation, or a configurable guideline
helps new team members.

For rule creation templates and industry-specific customization
examples, see [Rules Customization](rules-customization.md).

## Auditing Your Rules

Run `vault-tools.sh doctor` to verify all rules are properly
configured and enforcement mechanisms are in place.

Run `vault-tools.sh lint` to check soft rule compliance across the
vault.

Review rules quarterly:

- Are any rules routinely overridden? (Too strict)
- Are violations slipping through? (Insufficient enforcement)
- Has the team found a new failure mode? (New rule needed)
- Are any rules never triggered? (Possibly unnecessary)
