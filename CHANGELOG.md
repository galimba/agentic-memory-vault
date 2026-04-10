# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
