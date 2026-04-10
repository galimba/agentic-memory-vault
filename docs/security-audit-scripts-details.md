---
title: "Security Audit Details: Bash Scripts"
type: report
created: 2026-04-10
updated: 2026-04-10
status: active
tags:
  - domain/security
  - type/report
  - lifecycle/active
---

# Security Audit Details: Bash Scripts

Detailed PoCs and analysis. Summary in [[SECURITY-AUDIT-SCRIPTS.md]].

## Finding 1: CRITICAL -- sed Injection in init.sh

**File**: `.vault/scripts/init.sh`, lines 37-43 (original)

**Vulnerable code** (before fix):

```bash
read -rp "Vault name: " VAULT_NAME
sed -i -e "s/{{VAULT_NAME}}/${VAULT_NAME}/g" file.md
```

**PoC attack strings**:

- `VAULT_NAME="test/e s/status/pwned/g"` -- rewrites arbitrary content
- `VAULT_NAME="test & whoami"` -- `&` inserts the matched text
- `VAULT_NAME="a/b/c"` -- breaks the sed delimiter causing errors

**Impact**: An attacker who controls init.sh input can rewrite any content
in any markdown file processed by `find`. Since init.sh runs on first setup,
this is exploitable if a malicious fork provides pre-filled values.

**Fix applied**: `escape_sed_replacement()` escapes `\`, `/`, `&`.
`validate_input()` rejects `$(...)`, backticks, null bytes, and control chars.

## Finding 2: HIGH -- Symlink Path Traversal

**Files**: All three scripts

**Attack scenario**: An agent creates `wiki/concepts/evil -> /etc/` symlink.
When `find` or `extract_frontmatter` processes this, it reads files outside
the vault. Specifically:

- `extract_frontmatter` reads the symlink target's content as frontmatter
- `find "${WIKI_DIR}" -name "*.md"` follows symlinks into `/etc/`
- `grep -rl` in `is_linked` follows symlinks recursively
- An agent could read `.git/config` via `wiki/sources/config -> ../../.git/config`

**Fix applied**: `! -type l` excludes symlinks from `find`; `extract_frontmatter`
and `extract_fm` check `[[ -L "$file" ]]` and skip; pre-commit hook rejects
staged symlinks with a dedicated SEC check.

## Finding 3: HIGH -- grep Regex Injection via Filenames

**Files**: pre-commit.sh:685, vault-tools.sh:163,606

**Vulnerable code** (before fix):

```bash
basename=$(basename "$relative_path")
grep -q "$basename" "${INDEX_FILE}"
```

**PoC**: Create a file named `wiki/sources/.*` (literally `.*`).
`grep -q ".*"` matches every line, so this file always appears registered.
Conversely, a file named `wiki/sources/[test].md` causes grep to interpret
`[test]` as a character class.

**Impact**: False positives/negatives in index registration (HR-008) and
orphan detection. Not directly exploitable for RCE, but undermines the
validation system that agents rely on.

**Fix applied**: Changed `grep -q "$basename"` to `grep -qF "$basename"`
and `grep -rl "$target_basename"` to `grep -Frl "$target_basename"`.
`-F` flag treats the pattern as a literal string.

## Finding 4: HIGH -- DoS via Oversized Files

**Files**: Both pre-commit.sh and vault-tools.sh

**Attack scenarios**:

- 10 million line file: `wc -l` hangs for seconds; `extract_frontmatter`
  reads entire file line by line into a bash variable (memory exhaustion)
- 100MB frontmatter block (no closing `---`): `extract_frontmatter` reads
  the entire file, accumulating content in `$frontmatter` variable
- 50MB `wiki/index.md`: Every `grep` against it on every commit

**Fix applied**: `MAX_FILE_SIZE_BYTES=1048576` (1MB). `is_oversized()` checks
file size via `stat` before processing. `extract_frontmatter` limits parsing
to 100 frontmatter lines. `extract_fm` uses `NR<=102` guard in awk.

## Finding 5: MEDIUM -- date -d Injection via Frontmatter

**Files**: pre-commit.sh:296-297, vault-tools.sh:303,583

**Vulnerable code** (before fix):

```bash
updated=$(fm_field "updated" "$fm")
date -d "$updated" +%s
```

**PoC**: GNU `date -d` accepts natural language: `"next year"`, `"1 hour ago"`,
`"TZ=UTC0 2000-01-01"`. A frontmatter `updated: "1970-01-01 + 99999 days"`
bypasses staleness checks. While not RCE, it subverts validation logic.

**Fix applied**: `is_valid_date()` validates strict `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`
regex before any value reaches `date -d`.

## Finding 6: MEDIUM -- Unbounded find Traversal

**Files**: pre-commit.sh:606,690, vault-tools.sh:148,154

**Attack scenario**: Create `wiki/a/b/c/d/.../` nested 1000 levels deep.
`find` with no `-maxdepth` recurses through all levels, consuming CPU and
potentially hitting filesystem limits.

**Fix applied**: `MAX_FIND_DEPTH=10` applied to all `find` invocations.

## Finding 7: MEDIUM -- Unbounded Frontmatter Parsing

**File**: pre-commit.sh `extract_frontmatter()`

**Attack scenario**: A file with `---` on line 1 but no closing `---` and
50,000 lines of YAML-like content. The `while read` loop accumulates all
content into the `$frontmatter` variable.

**Fix applied**: Added `max_fm_lines=100` counter. Parsing stops after 100
frontmatter lines. `extract_fm` in vault-tools.sh uses `NR<=102` awk guard.

## Finding 8: LOW -- echo -e with User-Controlled Data

**File**: vault-tools.sh:820

```bash
echo -e "$output" > "${INDEX_FILE}"
```

`$output` contains frontmatter titles from wiki pages. `echo -e` interprets
escape sequences (`\n`, `\t`, `\x41`). A title containing `\n---\ntitle:`
could inject YAML frontmatter structure into the rebuilt index.

**Mitigation**: Use `printf '%s' "$output"` instead. Not fixed because
the function relies on `\n` expansion for newlines in the template.
This is a design issue requiring a rewrite of `cmd_index_rebuild`.

## Finding 9: LOW -- chmod +x Glob Scope

**File**: init.sh:82-83

```bash
chmod +x "${VAULT_ROOT}/.vault/scripts/"*.sh
chmod +x "${VAULT_ROOT}/.vault/hooks/"*.sh
```

If an attacker places a `.sh` file in these directories before init runs,
it becomes executable. However, making a file executable does not run it.

**Mitigation**: Document that users should review files before running init.

## Finding 10: INFO -- Hook Bypass

`git commit --no-verify` skips all pre-commit hooks. This is by design in
git and cannot be prevented. Agents could be instructed to use this flag.

**Mitigation**: Enforce validation in CI (the repo already has vault-doctor
in GitHub Actions). Server-side hooks are the only complete solution.

## Finding 11: INFO -- TOCTOU Race Condition

Between `get_staged_files` (snapshot of staged files) and actual file
validation, a concurrent `git add` could modify the staging area. This is
inherent to git's pre-commit hook architecture.

**Mitigation**: Not practically exploitable in normal agent workflows. The
commit itself is atomic -- the hook validates what was staged at hook start.

## Finding 12: INFO -- grep-Based YAML Parsing

Scripts parse YAML with `grep`/`sed`/`awk` instead of a proper YAML parser.
This means:

- Duplicate keys: `title: safe\ntitle: malicious` -- grep returns "safe"
  (first match), but a YAML parser would use "malicious" (last wins)
- Multi-line values: Not supported, values must be single-line
- Anchors/aliases: Ignored entirely
- Flow sequences: Partially supported for tags

This is a design limitation, not a fixable bug. For security-critical YAML
validation, integrate `yq` or a Python YAML linter in CI.
