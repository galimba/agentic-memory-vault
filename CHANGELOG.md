# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Comprehensive smoke test harness (`.vault/scripts/tests/test-smoke.sh`):
  builds a disposable vault, installs the real pre-commit hook, asserts
  every `vault-tools.sh` command exits 0 on a healthy vault, and verifies
  adversarial commits are blocked with the right markers (HR-002, HR-004,
  HR-012, HR-015) plus the warn-mode content-policy warning (#17).

### Fixed

- `vault-tools.sh doctor` now exits non-zero when it finds blocking
  issues — missing required directories or files, a broken pre-commit
  hook, or a failing lint — so the `vault-doctor` CI job can actually
  gate merges ([#25]). Warnings, including the un-initialized template
  state, remain non-fatal.
- New `tests` CI job runs every script under `.vault/scripts/tests/`;
  the pre-commit installation test was previously not exercised by any
  CI job ([#25]).
- The entire Lint workflow failed GitHub's workflow validation —
  `skill-audit` used `hashFiles()` in a job-level `if`, which GitHub
  only allows at step level, so every Actions run (including on `main`)
  failed in 0 seconds with no jobs since the guard was introduced. The
  guard is now a step-level file test ([#25]).
- Latent lint debt that surfaced the moment CI ran for real: eleven
  markdownlint spacing/length errors in `.vault/rules/soft-rules.md`,
  `docs/rules-customization.md`, and `docs/rules-guide.md`, plus one
  ShellCheck SC2015 info on the doctor's hook dry-run (flagged by the
  runner's older ShellCheck; intentional `|| true` guard, now annotated).
- `index-rebuild` silently dropped wiki pages whose frontmatter `type` was
  outside the seven standard sections (including the `uncategorized`
  fallback it assigns itself), leaving them out of `wiki/index.md` so
  HR-008 blocked their commits. Such pages are now emitted under a single
  `## Other` section, omitted entirely when no such pages exist (#26).
- `evaluation` frontmatter type accepted by the pre-commit hook (HR-002)
  and emitted by `index rebuild` is now documented in the type enum in
  `.vault/schemas/frontmatter.md`, `CLAUDE.md`, and `AGENTS.md` (#27).
- `CLAUDE.md` tag taxonomy claim corrected from "100+ categories" to the
  actual counts: 19 prefix categories, 230 approved tags (#27).

- `fm_field` in `.vault/scripts/lib-utils.sh` no longer propagates grep's
  non-zero exit when a frontmatter field is absent, which crashed
  `index-rebuild` (and any other command under `set -euo pipefail`) on
  pages missing an optional field such as `summary` (found by #17's
  smoke test).
- `test-pre-commit-install.sh` seeds pages with today's date instead of a
  hardcoded `2026-04-11`, which HR-007 (updated-field accuracy, ±1 day)
  started rejecting once the date passed.

[#25]: https://github.com/galimba/agentic-memory-vault/issues/25

## [0.4.0] - 2026-04-12

### Added

- Instance scaffolding phase in `init.sh`: reorganizes README, generates
  onboarding guide, creates fresh CHANGELOG, updates CONTRIBUTING for
  instance audience.
- Instance README template (`templates/readme-instance.md`) and onboarding
  template (`templates/onboarding-instance.md`).
- `{{REPO_NAME}}` and `{{MAINTAINER}}` prompts during initialization
  (7 placeholders total, up from 5).
- Idempotency guard: `.vault/.initialized` marker prevents accidental
  re-initialization.
- Git remote origin detection and update prompt for repos cloned from
  the template.
- Doctor checks for initialization state and remaining placeholders in
  `vault-tools.sh`.

### Fixed

- Hardcoded `galimba/agentic-memory-vault` references in 9 files replaced
  with init-time placeholders (`{{GITHUB_ORG}}/{{REPO_NAME}}`).
- `.github/CODEOWNERS` no longer hardcoded to `@galimba`; uses
  `@{{MAINTAINER}}` populated during init.
- `CODE_OF_CONDUCT.md` enforcement contact populated during init instead
  of `[INSERT CONTACT METHOD]`.
- `AGENTS.md` and `CLAUDE.md` vault version now reflects template version
  and resets to `0.1.0` for instances during scaffolding.
- `README.md` version badge updated to match template release.

### Changed

- Vault version bumped to 0.4.0 in CLAUDE.md, AGENTS.md, README.md.
- `docs/configuration.md` documents new placeholders and scaffolding phase.
- `docs/getting-started.md` prompt table expanded from 4 to 7 values.

## [0.3.0] - 2026-04-12

### Added

- HR-014: Agents cannot delete files from `wiki/` or `memory/`. Set
  `status: archived` in frontmatter instead. Use `VAULT_ALLOW_DELETE=1`
  for legitimate cleanup. This rule closes the last unprotected
  deletion surface in the vault.
- "Never delete files" added to the Boundaries block in CLAUDE.md,
  AGENTS.md, and CODEX.md.
- `docs/roadmap.md` linking to 11 open GitHub Issues covering deferred
  features from the v0.2.0 improvement work.
- Priority, type, and scope label taxonomy on the issue tracker to give
  contributors a consistent triage vocabulary.
- `infra` added to the `CONTRIBUTING.md` conventional-commit type list for
  CI and tooling work (used by the new smoke test harness issue).

### Changed

- Hard rule count updated from 14 to 15 across all documentation.
- `docs/rules-customization.md` template updated: next available
  rule ID is now HR-016.
- Vault version bumped to 0.3.0 in CLAUDE.md, AGENTS.md, README.md.

## [0.2.0] - 2026-04-11

### Fixed

- `cmd_stale()` and `cmd_lint()` now actually read
  `.vault/schemas/staleness-config.json` (A1). Per-domain and per-type
  thresholds plus `exempt_statuses` were shipped in v0.1.0 but inert —
  every file was checked against the hardcoded 30-day default. v0.2.0
  resolves the most restrictive matching threshold per file via
  `resolve_stale_threshold()` in `lib-utils.sh`.
- `.vault/schemas/content-policy.json` now ships with `"enabled": true`
  and a new `"enforcement": "warn"` field (A2). The instruction-pattern
  detection was dormant in v0.1.0; v0.2.0 runs it in pre-commit via
  `check_content_policy` in `check-sensitive-files.sh`. `block`
  enforcement is opt-in for strict environments.
- `CLAUDE.md` / `AGENTS.md` LINT step 7 previously referenced a
  `memory/notes/lint-report-{{DATE}}.md` artefact that nothing wrote.
  Fixed by implementing `_write_lint_report()` (see Added).

### Added

- `vault-tools.sh lint --report` now writes a structured report to
  `memory/notes/lint-report-YYYY-MM-DD.md` with summary counts, orphan
  and stale totals, and recommendations. `vault-tools.sh doctor`
  automatically runs lint with `--report` (B3).
- `HR-015: Append-only logs` — new hard rule and new pre-commit check
  (`.vault/hooks/checks/check-hr015.sh`) rejecting any commit that
  deletes or modifies existing lines in `wiki/log.md` or
  `memory/logs/*.md`. Set `LOG_EDIT_ALLOWED=1` to bypass for legitimate
  corrections (B5).
- `CONTENT_POLICY_DISABLED=1` environment bypass for the new content
  policy check (A2).
- Three-tier **Always / Ask first / Never** Boundaries block in
  `CLAUDE.md`, `AGENTS.md`, and `CODEX.md` replacing the flat
  "Prohibited Actions" list. The new block adds an explicit "Ask first"
  tier so agents pause on ambiguous actions instead of silently
  proceeding (C2).

### Changed

- `check_skill_hardening` was already wired into pre-commit in v0.1.0;
  v0.2.0 documents this explicitly in the pre-commit header comment so
  operators can see which policy-driven checks run. No functional
  change — the audit that previously only ran via `vault-tools.sh
  skill-audit` and CI has been running at commit time since v0.1.0
  (A3).
- `init.sh` content-hardening prompt now defaults to Y (keep enabled)
  to match the new v0.2.0 default.
- `docs/configuration.md` documents staleness-config wiring and the
  optional `jq` dependency.
- `docs/security-hardening.md` documents the new `enforcement` field
  and `CONTENT_POLICY_DISABLED` bypass.
- `CLAUDE.md` / `AGENTS.md` `Vault Version` bumped to `0.2.0`.

### Notes

- HR-014 is intentionally reserved. Content policy ships as a
  configurable warn-level check, not as a hard rule, so future growth
  of the hard-rule list can claim HR-014 without renumbering HR-015.

## [0.1.0] - {{INIT_DATE}}

### Added

- Initial vault boilerplate structure (raw/, wiki/, memory/, .vault/, templates/, docs/)
- CLAUDE.md agent configuration with three operations (INGEST, QUERY, LINT)
- AGENTS.md platform-agnostic agent instructions
- CODEX.md OpenAI Codex-specific overrides
- 13 hard rules with modular pre-commit hook enforcement (HR-001 through HR-013)
  - HR-011: Vault configuration protection (`.vault/rules/`, `.vault/hooks/`, `.vault/scripts/`)
  - HR-012: Agent configuration protection (`CLAUDE.md`, `AGENTS.md`, `CODEX.md`)
  - HR-013: CI and template protection (`.github/`, `templates/`)
- 15 soft rules with configurable defaults (SR-001 through SR-015)
- 200+ approved tags across 18 prefix categories
- YAML frontmatter schema with validation
- Modular pre-commit enforcement: 15 individual check files in `.vault/hooks/checks/` discovered by glob, orchestrated by a thin `pre-commit.sh` entry point plus `lib-hook-utils.sh`
- Modular CLI: `vault-tools.sh` entry point with `lib-utils.sh`, `lib-lint.sh`, `lib-manage.sh`, and dedicated `lib-audit.sh` for skill/content/tag audits
- 3-tier skill hardening framework (strict / moderate / permissive) with manifest verification
- Content integrity checking with instruction injection detection
- Rate-limit escape hatches for legitimate bulk operations (batch ingestion, tag renames, index rebuilds)
- Interactive `init.sh` setup script
- 6 document templates (concept, entity, source, comparison, decision, report)
- Wiki index and operations log
- Memory status dashboard
- Staleness configuration with per-domain thresholds
- `docs/rules-guide.md` — how the rule system works, enforcement layers, thresholds
- `docs/rules-customization.md` — creating new rules, industry-specific templates
- Architecture diagrams embedded in README (`docs/architecture.png`, `docs/vaults.png`)

[Unreleased]: https://github.com/galimba/agentic-memory-vault/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/galimba/agentic-memory-vault/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/galimba/agentic-memory-vault/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/galimba/agentic-memory-vault/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/galimba/agentic-memory-vault/releases/tag/v0.1.0
