# Audit Notes — Adversarial Stress Test Results

Tested on: 2026-04-10
Vault version: 0.1.0

## Script Bugs

- `vault-tools.sh validate` with no file argument crashes with "unbound variable" (line 111 in lib-lint.sh). Should print a usage hint like "Usage: vault-tools.sh validate <file>".
- `vault-tools.sh stats` exits with code 1 even when all output appears correct. The Link Density section is likely hitting a non-zero return from grep or wc under `set -e` when processing files with zero wikilinks.
- `vault-tools.sh stale abc` accepts a non-numeric days argument silently. Should validate that the argument is a positive integer.
- `vault-tools.sh stale 0` runs without warning, though a 0-day threshold would flag every page as stale.

## Documentation Inaccuracies

- README.md "Rules at a Glance" table only lists HR-001 through HR-010. The vault actually enforces HR-001 through HR-013. Missing: HR-011 (vault config protection), HR-012 (agent config protection), HR-013 (CI/template protection).
- docs/configuration.md line 120 says "Enforces all 10 hard rules (HR-001 through HR-010)" but there are 13 hard rules.
- soft-rules.md SR-002 says "(hard limit is 200)" but the actual hard (blocking) limit in pre-commit.sh and hard-rules.md HR-004 is 400 lines. 200 is the warning threshold, not the blocking threshold.
- CLAUDE.md initialization checklist lists only four placeholders (VAULT_NAME, ORG_NAME, INIT_DATE, PLATFORM) but init.sh also replaces {{GITHUB_ORG}} in README.md, CONTRIBUTING.md, CHANGELOG.md, and .github/ISSUE_TEMPLATE/config.yml.
- docs/configuration.md identity fields table also omits {{GITHUB_ORG}}.

## Missing Error Handling

- No input validation for the `stale` subcommand's numeric argument.
- No guard for `validate` subcommand when called without required argument.
- The `stats` command does not handle the empty-vault case gracefully (exits non-zero).

## Stale Worktrees

- `.claude/worktrees/` contains 5 leftover agent worktree directories (agent-a3634919, agent-ae128bbb, agent-a3a95889, agent-afcb6508, agent-af11ee25). These contain old copies of the repo from before the security audit and still reference individual hook scripts (protect-raw.sh, validate-frontmatter.sh, etc.) that no longer exist.
- `.gitignore` does not include `.claude/worktrees/`. If these are committed, they add significant noise. Consider adding `.claude/worktrees/` to .gitignore.

## Tag Taxonomy

- All tags used in templates/, wiki/, and memory/ are present in .vault/rules/tags.md (227 of 231 approved tags are unused, which is expected for a fresh vault).
- No broken links found in docs/, README.md, or CONTRIBUTING.md.
- No references to old individual hook scripts in the main repo (only in stale worktrees).

## Tests That Passed Clean

- vault-tools.sh with no arguments: shows help, exit 0
- vault-tools.sh with unknown command: shows error + help, exit 2
- All 6 library files pass bash -n syntax check
- lint runs clean on the empty vault
- tag-audit runs clean
- doctor runs clean (correctly warns about missing pre-commit hook)
- content-audit and skill-audit run clean
- status runs clean
- validate with nonexistent file gives proper error

## Suggestions for v0.2.0

- Add argument validation to `stale` (must be positive integer).
- Add a guard in `validate` for missing file argument.
- Fix `stats` exit code when vault has few or no wikilinks.
- Update README.md hard rules table to include HR-011 through HR-013.
- Update docs/configuration.md to say "13 hard rules" and list HR-011 through HR-013.
- Fix SR-002 to say "(warn at 200, block at 400)" instead of "(hard limit is 200)".
- Add {{GITHUB_ORG}} to CLAUDE.md initialization checklist and docs/configuration.md identity table.
- Add `.claude/worktrees/` to .gitignore.
- Consider cleaning up the 5 stale worktree directories.
