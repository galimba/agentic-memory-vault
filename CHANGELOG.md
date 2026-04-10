# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/{{GITHUB_ORG}}/memory-vault-boilerplate/releases/tag/v0.1.0
