#!/usr/bin/env bash
# Regression test for the pre-commit hook install path.
#
# Reproduces the bug where init-hooks installed .vault/hooks/pre-commit.sh
# as a flat cp into .git/hooks/pre-commit. Under that install, pre-commit.sh
# resolved its library paths via BASH_SOURCE, which after the copy pointed at
# .git/hooks/ — where lib-hook-utils.sh and checks/ do not exist. With
# set -euo pipefail at the top of the script, sourcing the missing file
# killed the hook before any HR check function was defined, so every commit
# (valid and invalid alike) was rejected with an opaque "No such file or
# directory" error and none of HR-001..HR-015 ever ran.
#
# Run: bash .vault/scripts/tests/test-pre-commit-install.sh
# Exit: 0 on PASS, non-zero on any FAIL.

set -euo pipefail

VAULT_ROOT="$(git rev-parse --show-toplevel)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# ------------------------------------------------------------------
# Build a minimal vault clone in a tempdir. Copy only what the hook
# and init-hooks need. We re-init git inside the tempdir so the
# test is self-contained and cannot touch the developer's real repo.
# ------------------------------------------------------------------
mkdir -p "$TMPDIR/wiki/concepts"
cp -r "$VAULT_ROOT/.vault" "$TMPDIR/.vault"
cp -r "$VAULT_ROOT/templates" "$TMPDIR/templates" 2>/dev/null || true

# Minimum wiki skeleton (index.md is required for HR-008, even empty).
cat > "$TMPDIR/wiki/index.md" <<'EOF'
---
title: "Index"
type: index
created: 2026-04-11
updated: 2026-04-11
status: active
tags:
  - type/index
owner: agent
confidence: high
---

# Vault Index

- [[concepts/valid.md]]
EOF

cat > "$TMPDIR/wiki/log.md" <<'EOF'
---
title: "Log"
type: index
created: 2026-04-11
updated: 2026-04-11
status: active
tags:
  - type/index
owner: agent
confidence: high
---

# Log
EOF

mkdir -p "$TMPDIR/memory"
cat > "$TMPDIR/memory/status.md" <<'EOF'
---
title: "Status"
type: report
created: 2026-04-11
updated: 2026-04-11
status: active
tags:
  - type/report
owner: agent
confidence: high
---

# Status
EOF

cd "$TMPDIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test Runner"
git add .
git -c core.hooksPath=/dev/null commit -q -m "seed" \
    || fail "could not create seed commit (hooks path bypass failed)"

# ------------------------------------------------------------------
# Install the hook via the code path under test.
# ------------------------------------------------------------------
bash .vault/scripts/vault-tools.sh init-hooks >/dev/null \
    || fail "init-hooks exited non-zero"

# ------------------------------------------------------------------
# Assert 1: wrapper marker present. A flat cp install lacks this
# marker, so this assertion alone catches the original bug.
# ------------------------------------------------------------------
grep -q 'vault-tools:pre-commit-wrapper' .git/hooks/pre-commit \
    || fail "wrapper marker missing from .git/hooks/pre-commit — install path still uses flat cp"

# ------------------------------------------------------------------
# Assert 2: hook dry run with no staged files must not print
# "No such file or directory" on stderr. The buggy install failed
# here because sourcing lib-hook-utils.sh from .git/hooks/ errored.
# ------------------------------------------------------------------
hook_out="$(.git/hooks/pre-commit </dev/null 2>&1 || true)"
if echo "$hook_out" | grep -q 'No such file or directory\|command not found'; then
    echo "$hook_out" >&2
    fail "hook prints source errors on dry run — libraries not loading"
fi

# ------------------------------------------------------------------
# Assert 3: a properly-frontmattered file registered in the index
# must commit successfully. The buggy hook rejected ALL commits
# (valid and invalid alike) with the same opaque source error, so
# this assertion is the strongest single reproduction of the real
# user impact.
# ------------------------------------------------------------------
cat > wiki/concepts/valid.md <<'EOF'
---
title: "Valid Page"
type: concept
created: 2026-04-11
updated: 2026-04-11
status: draft
sources: []
related: []
tags:
  - domain/engineering
  - type/concept
owner: agent
confidence: high
---

# Valid Page

A minimal valid page used by the hook install test.
EOF

git add wiki/concepts/valid.md
git commit -q -m "valid file should pass hook" \
    || fail "hook rejected a valid file — enforcement is broken or over-eager"

# ------------------------------------------------------------------
# Assert 4: a file with no frontmatter, no tags, and not registered
# in the index MUST be rejected, AND the rejection output must
# include an HR-### violation marker (not just a source error).
# ------------------------------------------------------------------
echo "no frontmatter, no tags, not in index" > wiki/concepts/invalid.md
git add wiki/concepts/invalid.md
reject_out="$(git commit -m "should be rejected" 2>&1 || true)"
if echo "$reject_out" | grep -q 'committed\|master\|main'; then
    # git commit success lines include "master" / "main" / "committed"
    if git log -1 --pretty=%s | grep -q 'should be rejected'; then
        fail "hook allowed a non-compliant commit"
    fi
fi
if ! echo "$reject_out" | grep -qE 'HR-[0-9]{3}'; then
    echo "$reject_out" >&2
    fail "rejection output did not include any HR-### violation marker — checks never ran"
fi

echo "PASS: pre-commit hook install is functional"
