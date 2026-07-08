#!/usr/bin/env bash
# Test for the blame command (issue #14).
#
# Builds a disposable vault inside a fresh git repo, commits a wiki page,
# appends a matching wiki/log.md entry dated today, and asserts that
# `vault-tools.sh blame` correlates the commit with the log entry:
#   - exit 0 and output containing the short SHA and the log entry title
#   - exit 2 with usage on a nonexistent file
#
# Run: bash .vault/scripts/tests/test-blame.sh
# Exit: 0 on PASS, non-zero on any FAIL.

set -euo pipefail

VAULT_ROOT="$(git rev-parse --show-toplevel)"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

TODAY="$(date +%Y-%m-%d)"

# ------------------------------------------------------------------
# Build a minimal vault clone in a tempdir with its own git repo.
# Hooks are bypassed via core.hooksPath=/dev/null so the fixture
# commits don't need to satisfy the full pre-commit rule set.
# ------------------------------------------------------------------
mkdir -p "$FIXTURE_DIR/wiki/concepts" "$FIXTURE_DIR/memory"
cp -r "$VAULT_ROOT/.vault" "$FIXTURE_DIR/.vault"

git -C "$FIXTURE_DIR" init -q
git -C "$FIXTURE_DIR" config user.name "Blame Tester"
git -C "$FIXTURE_DIR" config user.email "blame-tester@example.com"

cat > "$FIXTURE_DIR/wiki/log.md" <<EOF
---
title: "Operations Log"
type: index
created: ${TODAY}
updated: ${TODAY}
status: active
tags:
  - type/index
owner: agent
confidence: high
---

# Operations Log
EOF

cat > "$FIXTURE_DIR/wiki/concepts/concept-blame.md" <<EOF
---
title: "Blame Test Concept"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: draft
sources: []
related: []
tags:
  - domain/engineering
  - type/concept
owner: agent
confidence: high
---

# Blame Test Concept
EOF

git -C "$FIXTURE_DIR" add -A
git -C "$FIXTURE_DIR" -c core.hooksPath=/dev/null commit -q -m "[ingest] Added blame test concept"

# Append two same-day log entries: one whose block lists the target page
# in "Files modified" (definite match) and one that does not (date-only).
cat >> "$FIXTURE_DIR/wiki/log.md" <<EOF

## [${TODAY}] ingest | Blame Test Concept Ingested

- **Agent**: test
- **Files modified**: wiki/concepts/concept-blame.md
- **Summary**: fixture entry that mentions the target path

## [${TODAY}] query | Unrelated Same-Day Operation

- **Agent**: test
- **Files modified**: wiki/index.md
- **Summary**: fixture entry that does not mention the target path
EOF

git -C "$FIXTURE_DIR" add -A
git -C "$FIXTURE_DIR" -c core.hooksPath=/dev/null commit -q -m "[log] Log entry for blame test"

short_sha="$(git -C "$FIXTURE_DIR" log --format="%h" -1 -- wiki/concepts/concept-blame.md)"
[[ -n "$short_sha" ]] || fail "could not resolve the fixture commit SHA"

# ------------------------------------------------------------------
# Assert 1: blame on the committed page exits 0 and correlates the
# commit with the log entry appended above.
# ------------------------------------------------------------------
output="$(cd "$FIXTURE_DIR" && bash .vault/scripts/vault-tools.sh blame wiki/concepts/concept-blame.md)" \
    || fail "blame exited non-zero on a committed wiki page"

echo "$output" | grep -q "$short_sha" \
    || fail "blame output missing the short SHA ${short_sha}"
echo "$output" | grep -q "log: ingest | Blame Test Concept Ingested" \
    || fail "blame output missing the correlated log entry title"

# Path-aware correlation (issue #14: match by date AND file path): the
# entry naming the page must NOT be date-only; the unrelated one must be.
echo "$output" | grep "log: ingest | Blame Test Concept Ingested" \
    | grep -q "(date match only)" \
    && fail "path-matched log entry wrongly labeled as date match only"
echo "$output" | grep "log: query | Unrelated Same-Day Operation" \
    | grep -q "(date match only)" \
    || fail "date-only log entry not labeled '(date match only)'"

# ------------------------------------------------------------------
# Assert: a file outside the vault is rejected with exit 2.
# Explicit /tmp template: must land outside the fixture vault even when
# the caller's environment exports TMPDIR.
# ------------------------------------------------------------------
outside_file="$(mktemp /tmp/blame-outside.XXXXXX)"
rc=0
output="$(cd "$FIXTURE_DIR" && bash .vault/scripts/vault-tools.sh blame "$outside_file" 2>&1)" || rc=$?
rm -f "$outside_file"
[[ "$rc" -eq 2 ]] || fail "blame on an outside-vault file exited ${rc}, expected 2"
echo "$output" | grep -q "outside the vault" \
    || fail "blame error output missing outside-the-vault message"

# ------------------------------------------------------------------
# Assert 2: blame on a nonexistent file exits 2 with usage.
# ------------------------------------------------------------------
rc=0
output="$(cd "$FIXTURE_DIR" && bash .vault/scripts/vault-tools.sh blame wiki/no-such-page.md 2>&1)" || rc=$?
[[ "$rc" -eq 2 ]] || fail "blame on a nonexistent file exited ${rc}, expected 2"
echo "$output" | grep -q "Usage: vault-tools.sh blame" \
    || fail "blame error output missing usage line"

echo "PASS: blame correlates commits with wiki/log.md entries"
