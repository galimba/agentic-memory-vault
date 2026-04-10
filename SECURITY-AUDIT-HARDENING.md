# Security Audit and Hardening Report

> Audit date: 2026-04-10 | Auditor: automated | Vault version: 0.1.0

## Executive Summary

25 adversarial tests were executed against all 10 hard rules. All existing
rules detect their target violations. Three critical gaps were found and two
were fixed in this pass. The vault's defense posture relies on a single
enforcement layer (pre-commit hooks) that is trivially bypassed with
`git commit --no-verify`.

## Hard Rule Test Results

| Rule | Detection | Bypass Found | Fix Applied |
|------|-----------|-------------|-------------|
| HR-001 raw/ immutability | PASS | COMMIT_EDITMSG plantable in non-worktree repos | No (design limitation) |
| HR-002 mandatory frontmatter | PASS | None | N/A |
| HR-003 mandatory tags | PARTIAL | Unapproved tags accepted (presence-only check) | YES - taxonomy validation added |
| HR-004 markdown 200-line limit | PASS | None | N/A |
| HR-005 code 500-line minimum | PASS | Only checks .vault/scripts and .vault/hooks | N/A (by design) |
| HR-006 unique titles | PASS | None | N/A |
| HR-007 updated field accuracy | PASS | None | N/A |
| HR-008 index registration | PASS | None | N/A |
| HR-009 flat tag notation | PASS | None | N/A |
| HR-010 binary quarantine | PASS | Text files with binary extensions pass (correct behavior) | N/A |

## Critical Gaps Found

### Gap 1: HR-003 did not validate tags against taxonomy

`check_hr003()` only checked that tags existed, not that they were from
`.vault/rules/tags.md`. Any tag like `evil/payload` was accepted.
**Fixed**: Added taxonomy validation using `get_approved_tags()`.

### Gap 2: No protection for governance files

The pre-commit hook protects `raw/` and validates `wiki/` content but has
zero checks on files that control enforcement itself.

| Unprotected Asset | Impact if Modified |
|---|---|
| `.vault/hooks/pre-commit.sh` | Disables ALL enforcement |
| `.vault/rules/hard-rules.md` | Redefines what rules exist |
| `CLAUDE.md` / `AGENTS.md` / `CODEX.md` | Rewrites agent instructions |
| `.github/workflows/` | Disables CI checks |
| `.claude/settings.json` | Grants permissive agent permissions |
| `templates/` | Injects content into all future pages |

**Fixed**: Added advisory warnings for sensitive file modifications.

### Gap 3: `--no-verify` bypasses everything

`git commit --no-verify` skips all hooks. This is a git design feature,
not fixable at the hook level. CI-level enforcement is the only mitigation.

## Defense-in-Depth Matrix

| Asset | Pre-commit | CI Lint | Branch Prot. | CLAUDE.md Instruct. | Signed Commits |
|---|---|---|---|---|---|
| raw/ sources | PROTECTED | UNPROTECTED | PARTIAL | PROTECTED | UNPROTECTED |
| wiki/ content | PROTECTED | PROTECTED | PARTIAL | PROTECTED | UNPROTECTED |
| .vault/hooks/ | **WARN** | UNPROTECTED | PARTIAL | UNPROTECTED | UNPROTECTED |
| .vault/rules/ | **WARN** | UNPROTECTED | PARTIAL | UNPROTECTED | UNPROTECTED |
| CLAUDE.md | **WARN** | UNPROTECTED | PARTIAL | UNPROTECTED | UNPROTECTED |
| AGENTS.md | **WARN** | UNPROTECTED | PARTIAL | UNPROTECTED | UNPROTECTED |
| .github/ | **WARN** | UNPROTECTED | PARTIAL | UNPROTECTED | UNPROTECTED |
| .claude/ | **WARN** | UNPROTECTED | PARTIAL | UNPROTECTED | UNPROTECTED |
| templates/ | **WARN** | UNPROTECTED | PARTIAL | UNPROTECTED | UNPROTECTED |

**WARN** = advisory warning added by this audit (non-blocking).
**PARTIAL** = depends on repo configuration (branch protection rules vary).

### Single Points of Failure

1. **Pre-commit hook is the only active enforcement layer** -- bypassed by `--no-verify`
2. **No CI job validates governance file integrity** -- `vault-doctor` checks structure, not tampering
3. **Agent instruction files are trust-based** -- CLAUDE.md says "NEVER modify raw/" but nothing enforces this beyond the hook
4. **No signed commit requirement** -- any actor can forge commit authorship

## Proposed New Hard Rules

Details and rationale in `docs/security-audit-hardening-details.md`.

| ID | Rule | Enforcement |
|---|---|---|
| HR-011 | `.vault/` is agent-read-only | Pre-commit warning (applied) |
| HR-012 | Agent config files are agent-read-only | Pre-commit warning (applied) |
| HR-013 | `.github/` is agent-read-only | Pre-commit warning (applied) |
| HR-014 | `.claude/` settings are agent-read-only | Pre-commit warning (applied) |

## Applied Hardening Measures

1. **HR-003 taxonomy validation**: `check_hr003()` now validates tags against
   `.vault/rules/tags.md` approved taxonomy, not just presence
2. **Sensitive file warnings**: New `check_sensitive_files()` function warns
   when governance files are modified (non-blocking, advisory)
3. **Coverage**: `.vault/`, `CLAUDE.md`, `AGENTS.md`, `CODEX.md`, `.github/`,
   `.claude/`, `templates/` are all monitored

## Limitations

- Pre-commit hooks cannot distinguish agent from human commits
- `git commit --no-verify` bypasses all hooks
- Advisory warnings are non-blocking by design (to not break human workflows)
- Agent compliance with CLAUDE.md instructions is trust-based, not enforced
- An agent can modify the pre-commit hook itself to remove checks

## Recommendations for Future Work

1. Add CI job that checksums `.vault/hooks/pre-commit.sh` against a known-good hash
2. Add CODEOWNERS file requiring human approval for `.vault/`, `.github/`, agent config files
3. Enable branch protection requiring PR reviews for main
4. Consider signed commits to establish authorship provenance
5. Add agent instruction hardening (HR-011 through HR-014) to CLAUDE.md and AGENTS.md
