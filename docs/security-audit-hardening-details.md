# Security Audit Hardening Details

> Detailed test results and proposed rule specifications.
> See `SECURITY-AUDIT-HARDENING.md` for the executive summary.

## Detailed Test Results (25 Adversarial Tests)

### HR-001: Raw Directory Immutability

- **Test 1**: Created file in `raw/`, staged it. Hook detected and blocked.
- **Test 2**: Planted `[human]` in `COMMIT_EDITMSG` before hook ran. In
  worktrees, the path `$VAULT_ROOT/.git/COMMIT_EDITMSG` fails because
  `.git` is a file. In normal repos, this bypass would succeed because the
  hook reads `COMMIT_EDITMSG` before git writes it (it contains the
  previous commit's message). **Vulnerability in non-worktree repos.**
- **Blast radius**: If bypassed, source documents can be silently altered,
  destroying the provenance chain that the entire wiki depends on.

### HR-002: Mandatory Frontmatter

- **Test 3**: File without any `---` delimiters. Detected.
- **Test 4**: File with only `title` in frontmatter (missing type, created,
  updated, status). Detected -- missing fields reported individually.
- **Test 5**: File with invalid type value (`malicious`). Detected.
- **No bypass found.** The parser is robust against partial frontmatter.

### HR-003: Mandatory Tags

- **Test 6**: File with no `tags:` field. Detected.
- **Test 7**: File with `tags: []` (empty array). Detected.
- **Critical gap found**: Tags like `evil/payload` were accepted because
  `check_hr003()` only checked presence, not taxonomy membership.
  The `get_approved_tags()` function existed but was never called.
- **Fix applied**: Added taxonomy validation loop in `check_hr003()`.

### HR-004: Markdown Length Limit

- **Test 8**: 205-line file in `wiki/concepts/`. Detected (blocked).
- **Test 9**: 203-line file in `memory/`. Detected (blocked).
- **Exempt files** (`wiki/index.md`, `wiki/log.md`) correctly skip check.

### HR-005: Code File Minimum Length

- **Test 10**: 2-line script in `.vault/scripts/`. Detected.
- **Test 11**: 2-line script in `.vault/hooks/`. Detected.
- **Test 12**: Script placed in `wiki/concepts/` (outside `.vault/`).
  Not checked by HR-005 (only monitors `.vault/scripts/` and `.vault/hooks/`).
  This is by design -- HR-005 targets vault infrastructure code only.

### HR-006: Unique Page Titles

- **Test 13**: Two files with identical `title` in frontmatter. Detected.
- Note: Check scans ALL existing `wiki/` files, not just staged ones (correct).

### HR-007: Updated Field Accuracy

- **Test 14**: File with `updated: 2020-01-01` (6+ years stale). Detected.
- **Test 15**: File with `updated: 2030-01-01` (future date). Detected.
- Tolerance of 1 day is correctly applied.

### HR-008: Index Registration

- **Test 16**: New file in `wiki/concepts/` not listed in `wiki/index.md`.
  Detected. Check uses basename grep against index content.
- **Potential evasion**: If a file's basename appears in index.md as part of
  another word (e.g., `test.md` matching `my-test.md`), a false positive
  could occur. Low risk in practice.

### HR-009: Flat Tag Notation

- **Test 17**: Nested tag `type/concept/subconcept`. Detected.
- **Test 18**: Bare tag `concept` (no prefix). Detected.
- **Test 19**: Tag with space `type/my concept`. Detected.
- Regex `^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$` is well-constructed.

### HR-010: Binary File Quarantine

- **Test 20**: PNG binary in `wiki/`. Detected.
- **Test 21**: JPEG binary in `memory/`. Detected.
- **Test 22**: Text file with `.png` extension. Correctly allowed (uses
  `file --mime-type` content detection, not extension matching).

## Proposed New Hard Rules

### HR-011: Vault Configuration Directory Protection

**Rule**: The `.vault/` directory (including `hooks/`, `rules/`, `schemas/`,
`scripts/`) SHOULD NOT be modified by agents. Changes to these files require
human review.

**Rationale**: An agent modifying `.vault/hooks/pre-commit.sh` can disable
all enforcement. The LayerX attack demonstrated that 3 lines in a config file
can cause an agent to perform SQL injection. Similarly, modifying
`.vault/rules/hard-rules.md` redefines what is enforced.

**Enforcement**: Pre-commit warning (applied). Cannot be a blocking rule
because humans legitimately modify these files. Requires CODEOWNERS and
branch protection for full enforcement.

**Backward compatible**: Yes (advisory only).

### HR-012: Agent Configuration File Protection

**Rule**: `CLAUDE.md`, `AGENTS.md`, and `CODEX.md` SHOULD NOT be modified by
agents. These files define agent behavior and are human-managed.

**Rationale**: If an agent can rewrite its own instructions, it can remove
any behavioral constraint. This is the fundamental prompt injection risk.

**Enforcement**: Pre-commit warning (applied). Add to CLAUDE.md instructions.

**Backward compatible**: Yes (advisory only).

### HR-013: CI/CD Pipeline Protection

**Rule**: The `.github/` directory SHOULD NOT be modified by agents.

**Rationale**: CI pipelines are the second line of defense after pre-commit
hooks. An agent modifying `.github/workflows/lint.yml` could disable the
`vault-doctor` job, removing CI-level validation.

**Enforcement**: Pre-commit warning (applied).

**Backward compatible**: Yes (advisory only).

### HR-014: Claude Code Settings Protection

**Rule**: The `.claude/` directory (especially `settings.json` and
`settings.local.json`) SHOULD NOT be modified by agents.

**Rationale**: `.claude/settings.json` controls agent permissions. An agent
could grant itself broader permissions or disable deny rules.

**Enforcement**: Pre-commit warning (applied).

**Backward compatible**: Yes (advisory only).

## Known Limitations of Hook-Based Enforcement

1. `git commit --no-verify` skips all hooks (git design, unfixable)
2. `git merge -s ours` silently discards changes from other branches
3. Hooks run locally and can be deleted or replaced by any user
4. Pre-commit hooks cannot determine if the committer is human or agent
5. An agent with filesystem access can modify the hook itself
6. 50+ bash subcommands can bypass Claude Code deny-rule regex patterns

These limitations mean that pre-commit hooks are a **speed bump, not a wall**.
True enforcement requires CI-level checks, branch protection, CODEOWNERS
files, and signed commits.
