---
title: "Security Audit: Bash Scripts"
type: report
created: 2026-04-10
updated: 2026-04-10
status: active
tags:
  - domain/security
  - type/report
  - lifecycle/active
---

# Security Audit: Bash Scripts

Adversarial security audit of all bash scripts in `.vault/hooks/` and `.vault/scripts/`.
Conducted 2026-04-10. Detailed PoCs and analysis in [[docs/security-audit-scripts-details.md]].

## Scope

| File | Lines | Role |
|------|-------|------|
| `.vault/hooks/pre-commit.sh` | ~936 | Git pre-commit hook |
| `.vault/scripts/vault-tools.sh` | ~923 | CLI for vault operations |
| `.vault/scripts/init.sh` | ~164 | First-run initialization |

## Findings Summary

| # | Severity | Vulnerability | File | Fixed |
|---|----------|--------------|------|-------|
| 1 | CRITICAL | sed injection via user input | init.sh:37-43 | YES |
| 2 | HIGH | Path traversal via symlinks | pre-commit.sh, vault-tools.sh | YES |
| 3 | HIGH | Regex injection via filenames in grep | pre-commit.sh:685, vault-tools.sh:163,606 | YES |
| 4 | HIGH | DoS via oversized files (no size guards) | pre-commit.sh, vault-tools.sh | YES |
| 5 | MEDIUM | date -d injection via frontmatter | pre-commit.sh:296, vault-tools.sh:303,583 | YES |
| 6 | MEDIUM | Unbounded find traversal depth | pre-commit.sh:606,690, vault-tools.sh:148 | YES |
| 7 | MEDIUM | Unbounded frontmatter parsing (memory DoS) | pre-commit.sh:extract_frontmatter | YES |
| 8 | LOW | echo -e with user-controlled data | vault-tools.sh:820 | INFO |
| 9 | LOW | chmod +x glob may catch unintended files | init.sh:82-83 | INFO |
| 10 | INFO | git commit --no-verify bypasses hooks | pre-commit.sh (all) | N/A |
| 11 | INFO | TOCTOU between staging and validation | pre-commit.sh | N/A |
| 12 | INFO | YAML parsing without real parser | pre-commit.sh, vault-tools.sh | N/A |

## Fixes Applied

### CRITICAL: sed injection in init.sh (Finding 1)

User input from `read -rp` was interpolated directly into `sed -i -e "s/.../${VAR}/g"`.
`/`, `&`, `\` in input caused sed command corruption or injection.

**Fix**: Added `escape_sed_replacement()` and `validate_input()` functions.
Rejects `$(...)`, backticks, null bytes. Escapes `/`, `&`, `\` for safe sed usage.

### HIGH: Symlink path traversal (Finding 2)

No check prevented symlinks in `wiki/` pointing to `/etc/passwd` or `.git/config`.
`find`, `extract_frontmatter`, and `extract_fm` all followed symlinks.

**Fix**: Added `is_symlink()` check; pre-commit blocks staged symlinks;
`extract_frontmatter` and `extract_fm` skip symlinks; `find` uses `! -type l`;
added `is_within_vault()` utility.

### HIGH: grep regex injection (Finding 3)

`grep -q "$basename"` treated filenames as regex. A file named `.*` matches everything.

**Fix**: Changed all filename-matching `grep` calls to `grep -F` (literal mode).

### HIGH: No file size limits (Finding 4)

A 100MB frontmatter block or 10M-line file caused unbounded memory/CPU consumption.

**Fix**: Added `MAX_FILE_SIZE_BYTES=1048576` (1MB). `is_oversized()` skips large files
before parsing. Frontmatter extraction limited to 100 lines.

### MEDIUM: date -d injection (Finding 5)

Frontmatter `updated: "next thursday"` or crafted strings parsed by GNU `date -d`.

**Fix**: Added `is_valid_date()` requiring strict `YYYY-MM-DD` format before `date -d`.

### MEDIUM: Unbounded find depth (Finding 6)

Deeply nested directories (e.g., `wiki/a/b/c/.../z/`) caused `find` to recurse forever.

**Fix**: Added `MAX_FIND_DEPTH=10` and `-maxdepth` to all `find` invocations.

## Attack Vectors Tested but Not Exploitable

### Command injection via filenames

Variables are properly double-quoted throughout (`"$file"`, `"$full_path"`).
No `eval`, no unquoted backtick expansion. Filenames containing `$(rm -rf /)`
are safely handled as literal strings by bash due to proper quoting.

### YAML deserialization attacks

Python-style YAML deserialization tags (!!python) are not dangerous here because
scripts use `grep`/`sed`/`awk` for YAML parsing, not a real YAML parser. These
tags are treated as literal text. However, this grep-based parsing means malformed
YAML can bypass validation (documented as INFO finding).

### Privilege escalation

No scripts use `sudo`, `curl`, `wget`, `pip`, `npm`, or download remote code.
No scripts write outside `$VAULT_ROOT`. No scripts source external files.

## Known Limitations (Not Fixable in Scripts)

1. **git commit --no-verify**: Bypasses all hooks. Document in security policy.
2. **TOCTOU race**: Between `get_staged_files` and validation, files could change.
   This is inherent to git hooks and cannot be fully mitigated.
3. **Agent self-modification**: An agent can modify `.vault/hooks/pre-commit.sh`
   source, but this does not affect the installed copy in `.git/hooks/` until
   `init-hooks` runs again.
4. **grep-based YAML parsing**: Not a real YAML parser. Duplicate keys, multi-line
   values, and anchors/aliases are not properly handled. Mitigation: use a real
   YAML linter in CI.
