# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **HR-001**: Removed `[human]` commit-message bypass. Raw directory modifications now require PRs with CODEOWNERS approval
- **HR-004**: Changed from hard block at 200 lines to soft warning at 200, hard block at 400
- **HR-005**: Inverted from code minimum (500 lines) to code maximum (warn 400, block 600). Library files (lib-*.sh) are exempt
- **SR-004**: Replaced percentage-based summary length (20-50%) with absolute word count tiers
- **SR-010**: Acknowledged enforcement gap — rule is trust-based, documented how to add enforcement
- **SR-011**: Rewritten from count-based (5-15 pages) to intent-based (every materially affected page)
- **SR-012**: Replaced length threshold (>5 sentences) with quality criteria (novelty + reusability)
- **Rate limits**: Added escape hatches for legitimate bulk operations (batch ingestion, tag renames)

### Added

- **HR-011**: Vault configuration protection (`.vault/rules/`, `.vault/hooks/`, `.vault/scripts/`)
- **HR-012**: Agent configuration protection (`CLAUDE.md`, `AGENTS.md`, `CODEX.md`)
- **HR-013**: CI and template protection (`.github/`, `templates/`)
- `docs/rules-guide.md` — how the rule system works, enforcement layers, thresholds
- `docs/rules-customization.md` — creating new rules, industry-specific templates

### Refactored

- Modularized `pre-commit.sh` (1269→218 lines) into entry point + `lib-hook-utils.sh` + `lib-hook-checks.sh`
- Modularized `vault-tools.sh` (1573→144 lines) into entry point + `lib-utils.sh` + `lib-audit.sh` + `lib-lint.sh` + `lib-manage.sh`
- Split audit commands (`cmd_skill_audit`, `cmd_content_audit`, `cmd_tag_audit`) from `lib-manage.sh`/`lib-lint.sh` into dedicated `lib-audit.sh`

### Fixed

- Updated 7 stale enforcement references in `hard-rules.md` pointing to nonexistent individual hook scripts
- Updated 5 stale SR-004 references from percentage-based "20-50%" to word count tiers
- Added HR-011/012/013 to README.md "Rules at a Glance" table (was missing)
- Fixed `docs/configuration.md` to reference 13 hard rules (was 10)
- Fixed SR-002 in `soft-rules.md` to say "warn at 200, block at 400" (was "hard limit is 200")
- Added `{{GITHUB_ORG}}` to CLAUDE.md initialization checklist and `docs/configuration.md` identity table
- Created `AUDIT-NOTES.md` documenting remaining edge cases and v0.2.0 suggestions

## [0.1.0] - {{INIT_DATE}}

### Added

- Initial vault boilerplate structure (raw/, wiki/, memory/, .vault/, templates/, docs/)
- CLAUDE.md agent configuration with three operations (INGEST, QUERY, LINT)
- AGENTS.md platform-agnostic agent instructions
- CODEX.md OpenAI Codex-specific overrides
- 10 hard rules with pre-commit hook enforcement (HR-001 through HR-010)
- 15 soft rules with configurable defaults (SR-001 through SR-015)
- 200+ approved tags across 18 prefix categories
- YAML frontmatter schema with validation
- Consolidated pre-commit hook enforcing all hard rules
- Consolidated vault-tools.sh CLI with lint, status, stats, validate, orphans, stale, tag-audit, index-rebuild, doctor commands
- Interactive init.sh setup script
- 6 document templates (concept, entity, source, comparison, decision, report)
- Wiki index and operations log
- Memory status dashboard
- Staleness configuration with per-domain thresholds

[Unreleased]: https://github.com/{{GITHUB_ORG}}/memory-vault-boilerplate/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/{{GITHUB_ORG}}/memory-vault-boilerplate/releases/tag/v0.1.0
