#!/usr/bin/env bash
# Test for the memory-refresh command (issue #11).
#
# Builds a disposable vault with a git repo, then asserts:
#   1. memory-refresh creates MEMORY.md under 200 lines with the Core
#      pointers (wiki/index.md) and the fixed section headings.
#   2. Recently Active Pages lists a committed wiki page (from git log)
#      but never the Core pointers wiki/index.md / wiki/log.md.
#   3. The command is idempotent: a second run differs from the first
#      only in the "Refreshed:" date line, or not at all.
#   4. Latest Lint Report switches from "none yet" to the newest
#      memory/notes/lint-report-*.md once one exists.
#   5. doctor accepts the generated file (exit 0, no MEMORY.md warning).
#
# Run: bash .vault/scripts/tests/test-memory-refresh.sh
# Exit: 0 on PASS, non-zero on any FAIL.

set -euo pipefail

VAULT_ROOT="$(git rev-parse --show-toplevel)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

TODAY="$(date +%Y-%m-%d)"

# ------------------------------------------------------------------
# Build a minimal vault clone in a tempdir with its own git repo so
# the recently-active section has real history to read.
# ------------------------------------------------------------------
mkdir -p "$TMPDIR"/wiki/{sources,entities,concepts,comparisons} \
         "$TMPDIR"/memory/{decisions,logs,notes} \
         "$TMPDIR/raw" "$TMPDIR/docs"
cp -r "$VAULT_ROOT/.vault" "$TMPDIR/.vault"
cp -r "$VAULT_ROOT/templates" "$TMPDIR/templates"

touch "$TMPDIR/raw/.gitkeep"

cat > "$TMPDIR/CLAUDE.md" <<'EOF'
# CLAUDE.md — Test Vault Agent Configuration

Stub agent configuration for the memory-refresh test vault.
EOF

cat > "$TMPDIR/AGENTS.md" <<'EOF'
# AGENTS.md — Test Vault Agent Instructions

Stub agent instructions for the memory-refresh test vault.
EOF

cat > "$TMPDIR/wiki/index.md" <<EOF
---
title: "Vault Index"
type: index
created: ${TODAY}
updated: ${TODAY}
status: active
tags:
  - type/index
owner: agent
confidence: high
---

# Vault Index
EOF

cat > "$TMPDIR/wiki/log.md" <<EOF
---
title: "Test Vault Log"
type: index
created: ${TODAY}
updated: ${TODAY}
status: active
tags:
  - type/index
owner: agent
confidence: high
---

# Test Vault Log

## [${TODAY}] ingest | Seeded memory-refresh test vault
EOF

cat > "$TMPDIR/memory/status.md" <<EOF
---
title: "Vault Status"
type: report
created: ${TODAY}
updated: ${TODAY}
status: active
tags:
  - type/report
owner: agent
confidence: high
---

# Vault Status

Test vault is operational.
EOF

cat > "$TMPDIR/wiki/concepts/concept-memory-test.md" <<EOF
---
title: "Memory Test Concept"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: draft
sources: []
related:
  - "[[wiki/index.md]]"
tags:
  - domain/engineering
  - type/concept
  - lifecycle/active
summary: "A concept page used to exercise the recently-active section."
owner: agent
confidence: high
---

# Memory Test Concept

Links [[wiki/index.md]] and [[wiki/log.md]].
EOF

cd "$TMPDIR" || fail "could not cd into tempdir"
git init -q
git config user.email "test@example.com"
git config user.name "Test Runner"
bash .vault/scripts/vault-tools.sh index-rebuild >/dev/null \
    || fail "index-rebuild exited non-zero"
git add .
git -c core.hooksPath=/dev/null commit -q -m "seed" \
    || fail "could not create seed commit"

# ------------------------------------------------------------------
# Assert 1: memory-refresh creates a thin MEMORY.md with the pointers.
# ------------------------------------------------------------------
bash .vault/scripts/vault-tools.sh memory-refresh >/dev/null \
    || fail "memory-refresh exited non-zero"
[[ -f MEMORY.md ]] || fail "MEMORY.md was not created"

lines=$(wc -l < MEMORY.md | tr -d ' ')
[[ $lines -lt 200 ]] || fail "MEMORY.md has ${lines} lines (must be < 200)"

grep -qF '[[wiki/index.md]]' MEMORY.md \
    || fail "MEMORY.md is missing the wiki/index.md pointer"
for heading in "## Core" "## Rules" "## Latest Lint Report" "## Recently Active Pages"; do
    grep -qF "$heading" MEMORY.md || fail "MEMORY.md is missing section: ${heading}"
done
grep -qF 'memory-refresh' MEMORY.md \
    || fail "MEMORY.md footer does not mention the memory-refresh command"

# ------------------------------------------------------------------
# Assert 2: the committed concept page shows up as recently active;
# Core pointers are excluded from that section.
# ------------------------------------------------------------------
active_section=$(awk '/^## Recently Active Pages/,/^---$/' MEMORY.md)
echo "$active_section" | grep -qF 'wiki/concepts/concept-memory-test.md' \
    || fail "committed wiki page missing from Recently Active Pages"
! echo "$active_section" | grep -qF 'wiki/index.md' \
    || fail "wiki/index.md must not appear under Recently Active Pages"
! echo "$active_section" | grep -qF 'wiki/log.md' \
    || fail "wiki/log.md must not appear under Recently Active Pages"

# ------------------------------------------------------------------
# Assert 3: idempotent — second run differs only in the date line.
# ------------------------------------------------------------------
cp MEMORY.md "$TMPDIR/first-run.md"
bash .vault/scripts/vault-tools.sh memory-refresh >/dev/null \
    || fail "second memory-refresh exited non-zero"
if ! diff_out=$(diff "$TMPDIR/first-run.md" MEMORY.md); then
    non_date=$(echo "$diff_out" | grep -c '^[<>]' || true)
    date_lines=$(echo "$diff_out" | grep -c '^[<>] Refreshed: ' || true)
    [[ "$non_date" == "$date_lines" ]] \
        || { echo "$diff_out" >&2; fail "second run changed more than the Refreshed date line"; }
fi

# ------------------------------------------------------------------
# Assert 4: newest lint report is picked up on the next refresh.
# ------------------------------------------------------------------
echo "# Lint Report" > "memory/notes/lint-report-${TODAY}.md"
bash .vault/scripts/vault-tools.sh memory-refresh >/dev/null \
    || fail "memory-refresh exited non-zero after lint report appeared"
grep -qF "[[memory/notes/lint-report-${TODAY}.md]]" MEMORY.md \
    || fail "MEMORY.md does not point at the newest lint report"

# ------------------------------------------------------------------
# Assert 5: doctor accepts the generated MEMORY.md (exit 0, no warning
# about MEMORY.md being missing or oversized).
# ------------------------------------------------------------------
doctor_out=$(bash .vault/scripts/vault-tools.sh doctor 2>&1) \
    || { echo "$doctor_out" >&2; fail "doctor exited non-zero with MEMORY.md present"; }
if echo "$doctor_out" | grep -q 'MEMORY.md.*\(missing\|limit\)'; then
    echo "$doctor_out" >&2
    fail "doctor warned about a valid MEMORY.md"
fi

echo "PASS: memory-refresh generates a valid, idempotent MEMORY.md"
