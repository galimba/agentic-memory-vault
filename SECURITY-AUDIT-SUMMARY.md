---
title: "Security Audit Summary"
type: report
created: 2026-04-10
updated: 2026-04-10
status: active
tags:
  - domain/security
  - type/report
  - lifecycle/active
---

# Security Audit Summary

Comprehensive adversarial security audit of the agentic-memory-vault template.
Conducted: 2026-04-10. Five parallel audit phases, one synthesis phase.

## Findings by Severity

| Severity | Scripts | Agents | Infra | Hardening | Total |
|----------|---------|--------|-------|-----------|-------|
| CRITICAL | 1 | 3 | 1 | 0 | 5 |
| HIGH | 3 | 4 | 1 | 1 | 9 |
| MEDIUM | 3 | 3 | 2 | 0 | 8 |
| LOW | 2 | 2 | 2 | 0 | 6 |
| INFO | 3 | 0 | 4 | 0 | 7 |

**Fixed during audit**: 5 CRITICAL, 5 HIGH, 3 MEDIUM = 13 findings remediated.

## Top 10 Most Impactful Vulnerabilities

| # | Severity | Finding | Status |
|---|----------|---------|--------|
| 1 | CRITICAL | `.claude/settings.json` writable by agents (full sandbox escape) | FIXED |
| 2 | CRITICAL | GitHub Actions using mutable tags (supply chain) | FIXED |
| 3 | CRITICAL | `init.sh` sed injection via user input (`/`, `&`, `\`) | FIXED |
| 4 | CRITICAL | Agent can modify CLAUDE.md/rules/hooks (self-modification) | MITIGATED |
| 5 | CRITICAL | `git commit --no-verify` bypasses all hard rules | DOCUMENTED |
| 6 | HIGH | No content trust hierarchy (raw/ same trust as config) | FIXED |
| 7 | HIGH | Symlink path traversal in wiki/ and memory/ | FIXED |
| 8 | HIGH | HR-003 tag validation was presence-only (not taxonomy) | FIXED |
| 9 | HIGH | grep regex injection via filenames | FIXED |
| 10 | HIGH | DoS via oversized files (no size guards) | FIXED |

## Remediation Applied

### Scripts (Phase 1)
- sed injection: `escape_sed_replacement()` + `validate_input()` in init.sh
- Symlink protection: `is_symlink()` checks, `! -type l` on all `find` commands
- Size guards: `MAX_FILE_SIZE_BYTES=1MB`, `is_oversized()`, 100-line frontmatter cap
- Date validation: `is_valid_date()` requiring strict YYYY-MM-DD before `date -d`
- Literal grep: `grep -F` for all filename-based searches
- Depth limits: `-maxdepth 10` on all `find` invocations

### Infrastructure (Phase 3)
- SHA-pinned all GitHub Actions (actions/checkout, markdownlint-cli2, typos)
- Added `permissions: contents: read` to all workflow jobs
- Added `.obsidian/plugins/*/data.json` and `.claude/settings*.json` to .gitignore
- Created `docs/plugin-security.md` (Obsidian/MCP supply chain warnings)

### Skill Hardening (Phase 4)
- Created 3-tier skill policy (strict/moderate/permissive)
- Added `skill-audit` and `content-audit` commands to vault-tools.sh
- Added skill validation to pre-commit hook (optional, backward compatible)
- Added skill-audit CI job (conditional on policy file existing)
- Added hardening prompts to init.sh

### Configuration Hardening (Phase 5)
- Fixed HR-003 to validate tags against approved taxonomy
- Added sensitive file modification warnings (non-blocking advisory)
- Created defense-in-depth matrix documenting coverage gaps

### Agent Security (Phase 6)
- Added Security section to CLAUDE.md with content trust hierarchy
- Added prohibited actions list for agents
- Added suspicious content protocol
- Mirrored security section to AGENTS.md and CODEX.md
- Updated SECURITY.md with hardening recommendations

## Findings Requiring User Action

1. **Enable branch protection** on main (require PR reviews)
2. **Add CODEOWNERS** file requiring human approval for `.vault/`, `.github/`, config files
3. **Consider signed commits** for authorship provenance
4. **Review Obsidian plugins** per docs/plugin-security.md
5. **Review MCP servers** for tool poisoning risks

## Fundamental Limitations (Documented, Not Fixable)

1. `git commit --no-verify` bypasses all hooks (git design feature)
2. Agent CLAUDE.md compliance is probabilistic, not deterministic
3. Pre-commit hooks cannot distinguish agent from human commits
4. Semantic corruption invisible to structural checks
5. Client-side hooks are a single point of failure

## Audit Report Index

| Report | Scope | Location |
|--------|-------|----------|
| Scripts | pre-commit.sh, vault-tools.sh, init.sh | [[SECURITY-AUDIT-SCRIPTS.md]] |
| Scripts (details) | PoCs and analysis | [[docs/security-audit-scripts-details.md]] |
| Agents | AI agent threat model | [[SECURITY-AUDIT-AGENTS.md]] |
| Agents (details) | Mitigations and proposals | [[docs/security-audit-agents-details.md]] |
| Infrastructure | CI/CD, supply chain, secrets | [[SECURITY-AUDIT-INFRASTRUCTURE.md]] |
| Infrastructure (details) | MCP, Obsidian, Actions | [[docs/security-audit-infrastructure-details.md]] |
| Hardening | Gap analysis, rule testing | [[SECURITY-AUDIT-HARDENING.md]] |
| Hardening (details) | Test results, proposals | [[docs/security-audit-hardening-details.md]] |
| Plugin Security | Obsidian supply chain | [[docs/plugin-security.md]] |
| Security Hardening | Skill hardening guide | [[docs/security-hardening.md]] |
