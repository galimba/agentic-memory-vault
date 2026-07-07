# Configuration Reference

This guide covers every configurable aspect of the vault: identity fields, rules, tags, staleness thresholds, git workflow, and hooks.

## Identity Fields (CLAUDE.md / AGENTS.md)

After running `init.sh`, these placeholders are replaced in all `.md` and `.yml` files:

| Field | Location | Purpose |
|-------|----------|---------|
| `{{VAULT_NAME}}` | Identity section, README, CONTRIBUTING | Human-readable vault identifier |
| `{{ORG_NAME}}` | Identity section | Your organization name |
| `{{PLATFORM}}` | Identity section | Primary agent platform (`claude-code`, `codex`, `copilot`, `cursor`, `custom`) |
| `{{INIT_DATE}}` | Identity section, frontmatter, CHANGELOG | Date the vault was initialized |
| `{{GITHUB_ORG}}` | README, CONTRIBUTING, CHANGELOG, config.yml, roadmap | GitHub organization for repo URLs |
| `{{REPO_NAME}}` | README, CONTRIBUTING, CHANGELOG, config.yml, roadmap | Repository name for repo URLs |
| `{{MAINTAINER}}` | CODEOWNERS, CODE_OF_CONDUCT | GitHub maintainer user or team |

To change these after initialization, search-and-replace across all `.md` files.
The `init.sh` script uses `sed` and can be re-run, but it only replaces
the `{{placeholder}}` syntax, not already-substituted values.

## Instance Scaffolding

During `init.sh`, you are offered the option to reorganize template documentation:

- `README.md` is replaced with a compact instance gateway README
- The original template README is preserved at `docs/vault-template-readme.md`
- A starter onboarding guide is generated at `docs/onboarding.md`
- `CHANGELOG.md` is replaced with a fresh instance changelog
- `CONTRIBUTING.md` is updated for your repository
- `docs/roadmap.md` is moved to `docs/vault-template-roadmap.md`

This step is optional — declining it leaves all files in their template state
(with placeholder URLs already substituted).

## Soft Rules

Edit `.vault/rules/soft-rules.md` to customize agent behavior. Each rule has a default, rationale, and override guidance.

| Rule | Default | How to customize |
|------|---------|-----------------|
| SR-001 | One source per session | Override for batch onboarding |
| SR-002 | 80-150 line target per page | Adjust range (hard max is 400) |
| SR-003 | 3+ wikilinks per page | Lower for specialized pages |
| SR-004 | Summaries use absolute word count ranges | Adjust per source length tier |
| SR-005 | Log format `[YYYY-MM-DD] op \| Title` | Customize fields |
| SR-006 | ADR format for decisions | Swap to RFC or custom template |
| SR-007 | Lint weekly | Increase for active vaults |
| SR-008 | 30-day staleness threshold | Customize per-domain (see below) |
| SR-009 | Confidence calibration | Adjust meanings |
| SR-010 | Drafts require human review (trust-based) | Add CI enforcement or auto-promote |
| SR-011 | Update all materially affected pages on ingest | Adjust thresholds |
| SR-012 | File novel, reusable query answers | Disable for ephemeral queries |
| SR-013 | Entity page structure | Customize sections |
| SR-014 | Comparison page structure | Customize sections |
| SR-015 | Custom tags use `custom/` prefix | Define your prefix convention |
| SR-016 | One `wiki/` writer per branch | Adapt scratch-space naming under `memory/agents/` |

Agents read `soft-rules.md` during context loading. Changes take effect on the next agent session.

## Tag Taxonomy

The full tag list lives in `.vault/rules/tags.md`. The vault ships with 230 approved tags across 19 prefix categories, plus the reserved `custom/` prefix for organization-specific tags.

### Adding custom tags

1. Open `.vault/rules/tags.md`
2. Add your tag under the appropriate prefix section (or create a new section)
3. Follow the format: `- \`prefix/value\` -- Description`
4. Use lowercase, hyphenated values: `domain/data-engineering`, not `domain/DataEngineering`
5. For organization-specific tags, use the `custom/` prefix: `custom/acme-onboarding`
6. Commit with message: `[tags] Added custom/your-tag-name`

### Creating a new prefix category

Add a new `## prefix/ -- Description` section to `tags.md`. The pre-commit hook validates tags against this file using regex extraction, so new prefixes are automatically recognized.

## Staleness Thresholds

Configure per-domain staleness in `.vault/schemas/staleness-config.json`:

```json
{
  "default_threshold_days": 30,
  "domain_thresholds": {
    "domain/engineering": 30,
    "domain/operations": 14,
    "domain/hr": 60
  },
  "type_thresholds": {
    "type/runbook": 14,
    "type/decision": 90,
    "type/concept": 60
  },
  "exempt_statuses": ["archived", "deprecated"]
}
```

- `default_threshold_days`: Fallback when no domain or type match
- `domain_thresholds`: Override by domain tag
- `type_thresholds`: Override by content type
- `exempt_statuses`: Pages with these statuses are never flagged as stale

Since v0.2.0 this config is actually read at lint time. `cmd_stale` and
`cmd_lint` resolve a per-file threshold by taking the most restrictive
matching override (minimum of default, matching domain tag, matching
type), and skip any file whose status is in `exempt_statuses`. Passing
an explicit threshold (`vault-tools.sh stale 14`) still overrides the
config globally for that run.

If `jq` is installed it is used for reliable JSON parsing; otherwise a
bash-only fallback handles the flat JSON shape. Installing `jq` is
recommended but not required.

## Git Workflow Configuration

### Branch protection (recommended)

Configure in your Git hosting provider (GitHub, GitLab, etc.):

- **Require pull request reviews** before merging to `main`
- **Require status checks** (the `lint.yml` CI workflow) to pass
- **No direct push** to `main` -- all changes via PR
- **Require linear history** (optional, simplifies log)

### Branch naming

| Who | Pattern | Example |
|-----|---------|---------|
| Agent | `agent/{{agent-id}}/{{task}}` | `agent/claude-01/ingest-q1-retro` |
| Human | `feature/{{description}}` | `feature/add-security-tags` |

### Commit messages

Format: `[operation] description`

- `[ingest] Added source on Q1 engineering retrospective`
- `[lint] Fixed orphan pages and stale content`
- `[raw] Added raw source document` (via PR only)
- `[tags] Added custom/acme-onboarding tag`

## Hooks

### Pre-commit hook

Located at `.vault/hooks/pre-commit.sh`, installed to `.git/hooks/pre-commit` by `init.sh`.

Enforces all 15 hard rules (HR-001 through HR-015). Violations block the commit with a clear error message identifying the rule, file, and issue.

### Customizing the pre-commit hook

The hook is a consolidated 800+ line bash script. To add checks:

1. Add a new `check_hrXXX()` function following the existing pattern
2. Call it from `main()` alongside the other checks
3. Use the `violation()` helper to report issues: `violation "HR-011" "$file" "Description"`
4. Document the new rule in `.vault/rules/hard-rules.md`

### Reinstalling hooks

If hooks are lost (e.g., fresh clone):

```bash
bash .vault/scripts/vault-tools.sh init-hooks
```

## CI Integration

The `.github/workflows/lint.yml` workflow runs on every push to `main` and every PR:

| Job | Tool | What it checks |
|-----|------|----------------|
| `lint-markdown` | markdownlint | Markdown formatting |
| `lint-shell` | ShellCheck | Shell script quality |
| `lint-yaml` | yamllint | YAML syntax |
| `check-typos` | typos | Spelling errors |
| `vault-doctor` | vault-tools.sh | Full vault diagnostic |
