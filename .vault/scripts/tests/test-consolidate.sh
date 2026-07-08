#!/usr/bin/env bash
# Test for `vault-tools.sh consolidate` (issue #16).
#
# Seeds a temp vault with three mutually-related concept pages that share
# 2+ approved tags and are past their staleness threshold, plus one fresh
# page with the same tags and links. Asserts:
#   - consolidate exits 0 and writes memory/notes/consolidation-YYYY-MM-DD.md
#   - all three stale pages land in one group
#   - the fresh page is NOT in any group
#   - the report has valid frontmatter (title/type/created)
#
# Run: bash .vault/scripts/tests/test-consolidate.sh
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
# ~60 days back: past the 30-day threshold for domain/engineering pages.
STALE_DATE="$(date -d "-60 days" +%Y-%m-%d)"

# ------------------------------------------------------------------
# Build a minimal vault clone in a tempdir. vault-tools.sh resolves
# VAULT_ROOT from its own location, so running the copied script
# operates entirely inside the tempdir — no git repo needed.
# ------------------------------------------------------------------
mkdir -p "$TMPDIR/wiki/concepts" "$TMPDIR/memory/notes"
cp -r "$VAULT_ROOT/.vault" "$TMPDIR/.vault"

cat > "$TMPDIR/wiki/index.md" <<EOF
---
title: "Index"
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
title: "Log"
type: index
created: ${TODAY}
updated: ${TODAY}
status: active
tags:
  - type/index
owner: agent
confidence: high
---

# Log
EOF

# Three stale pages, mutually related (a -> b, b -> c, c -> a), sharing
# the approved tags domain/engineering + type/concept + lifecycle/active.
seed_page() {
    local name="$1" related="$2" updated="$3"
    cat > "$TMPDIR/wiki/concepts/concept-${name}.md" <<EOF
---
title: "Concept ${name}"
type: concept
created: ${updated}
updated: ${updated}
status: active
sources: []
related:
  - "[[wiki/concepts/concept-${related}.md]]"
tags:
  - domain/engineering
  - type/concept
  - lifecycle/active
owner: agent
confidence: medium
---

# Concept ${name}

Overlapping content about the same topic.
EOF
}

seed_page "alpha" "beta"  "$STALE_DATE"
seed_page "beta"  "gamma" "$STALE_DATE"
seed_page "gamma" "alpha" "$STALE_DATE"
# Fresh page: same tags and a related link into the cluster, but updated
# today — must be excluded by the staleness filter.
seed_page "delta" "alpha" "$TODAY"

# ------------------------------------------------------------------
# Run consolidate via the code path under test.
# ------------------------------------------------------------------
(cd "$TMPDIR" && bash .vault/scripts/vault-tools.sh consolidate >/dev/null) \
    || fail "consolidate exited non-zero"

report="$TMPDIR/memory/notes/consolidation-${TODAY}.md"
[[ -f "$report" ]] || fail "report not written to memory/notes/consolidation-${TODAY}.md"

# ------------------------------------------------------------------
# Assert 1: report has valid frontmatter fields.
# ------------------------------------------------------------------
grep -q "^title: \"Consolidation Report ${TODAY}\"" "$report" || fail "report missing title frontmatter"
grep -q "^type: report" "$report" || fail "report missing type: report"
grep -q "^created: ${TODAY}" "$report" || fail "report missing created: ${TODAY}"
grep -q "^  - type/report" "$report" || fail "report missing type/report tag"
grep -q "^  - lifecycle/active" "$report" || fail "report missing lifecycle/active tag"

# ------------------------------------------------------------------
# Assert 2: exactly one group containing all three stale pages.
# ------------------------------------------------------------------
grep -q "^## Group 1" "$report" || fail "report has no Group 1"
if grep -q "^## Group 2" "$report"; then
    fail "report has more than one group"
fi
group_section="$(awk '/^## Group 1/,0' "$report")"
for name in alpha beta gamma; do
    grep -q "concept-${name}.md" <<< "$group_section" \
        || fail "concept-${name}.md missing from Group 1"
done

# ------------------------------------------------------------------
# Assert 3: the fresh page is not in any group.
# ------------------------------------------------------------------
if grep -q "concept-delta.md" <<< "$group_section"; then
    fail "fresh page concept-delta.md appeared in a group"
fi

# ------------------------------------------------------------------
# Assert 4: report-only — no wiki page was modified.
# ------------------------------------------------------------------
grep -q "updated: ${STALE_DATE}" "$TMPDIR/wiki/concepts/concept-alpha.md" \
    || fail "consolidate modified a wiki page"

echo "PASS: consolidate groups stale overlapping pages and writes the report"
