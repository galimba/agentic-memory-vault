#!/usr/bin/env bash
# Test for vault-tools.sh index maintenance in the split-index layout (#9/#10):
#   1. Below the threshold, index-split is a no-op.
#   2. index-split partitions an oversized single index: the root shrinks to
#      <=200 lines, keeps its section headings (stable anchors) plus pointer
#      wikilinks, preserves preamble prose, and entries land in wiki/index-*.md
#      sub-indexes with valid index frontmatter.
#   3. The HR-008 hook check accepts pages registered only in a sub-index.
#   4. A healthy split vault passes `vault-tools.sh lint` (split-aware
#      index completeness).
#   5. index-update appends new pages to the right sub-index.
#   6. index-rebuild preserves the split layout (pointer root + sub-indexes).
#   7. index-rebuild ADOPTS the split layout on its own when a freshly rebuilt
#      single-file index would overflow the threshold, with no prior split.
#
# Run: bash .vault/scripts/tests/test-index-split.sh
# Exit: 0 on PASS, non-zero on any FAIL.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

TODAY="$(date +%Y-%m-%d)"

# Run the real HR-008 hook check against the temp vault and echo the
# violation count (subshell keeps the sourced hook config contained).
hr008_violations() (
    VAULT_ROOT="$TMPDIR"; WIKI_DIR="wiki"; INDEX_FILE="wiki/index.md"
    MAX_FIND_DEPTH=10; MAX_FILE_SIZE_BYTES=1048576
    MARKDOWN_EXTENSIONS=("md" "markdown")
    RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
    source "$REPO_ROOT/.vault/hooks/lib-hook-utils.sh"
    source "$REPO_ROOT/.vault/hooks/checks/check-hr008.sh"
    check_hr008 > /dev/null
    echo "$VIOLATIONS"
)

run_tool() {  # run_tool <command> [args...]
    (cd "$TMPDIR" && bash .vault/scripts/vault-tools.sh "$@" > /dev/null) \
        || fail "vault-tools.sh $* exited non-zero"
}

mkpage() {  # mkpage <path> <title> <type>
    cat > "$1" <<EOF
---
title: "$2"
type: $3
created: ${TODAY}
updated: ${TODAY}
status: draft
sources: []
related: []
tags:
  - domain/engineering
  - type/concept
summary: "Generated page for the index-split test."
owner: agent
confidence: high
---

# $2
EOF
}

# ------------------------------------------------------------------
# Seed a vault with enough pages for a >250-line rebuilt index (270 pages).
# ------------------------------------------------------------------
mkdir -p "$TMPDIR/wiki/concepts" "$TMPDIR/wiki/sources" "$TMPDIR/wiki/entities" "$TMPDIR/memory/notes"
cp -r "$REPO_ROOT/.vault" "$TMPDIR/.vault"

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

for i in $(seq 1 90); do
    mkpage "$TMPDIR/wiki/concepts/concept-gen-${i}.md" "Generated Concept ${i}" concept
    mkpage "$TMPDIR/wiki/sources/source-gen-${i}.md" "Generated Source ${i}" source
    mkpage "$TMPDIR/wiki/entities/entity-gen-${i}.md" "Generated Entity ${i}" entity
done

index="$TMPDIR/wiki/index.md"

# ------------------------------------------------------------------
# Build a single oversized index. Lift the auto-split threshold so this
# rebuild does NOT split — we want a single index for index-split to act on.
# ------------------------------------------------------------------
(cd "$TMPDIR" && INDEX_SPLIT_THRESHOLD=100000 bash .vault/scripts/vault-tools.sh index-rebuild > /dev/null) \
    || fail "forced-single index-rebuild exited non-zero"
lines_before="$(wc -l < "$index" | tr -d ' ')"
[[ "$lines_before" -gt 250 ]] || fail "seeded index has only ${lines_before} lines (need >250)"
if compgen -G "$TMPDIR/wiki/index-*.md" > /dev/null; then
    fail "forced-single rebuild unexpectedly created sub-indexes"
fi

# Preamble prose that the split must carry over into the rewritten root.
awk '{ print } /^# Vault Index$/ { print ""; print "Curated preamble note for the split test." }' \
    "$index" > "$index.tmp" && mv "$index.tmp" "$index"

# ------------------------------------------------------------------
# 1. Below an explicit threshold: no-op.
# ------------------------------------------------------------------
run_tool index-split 100000
if compgen -G "$TMPDIR/wiki/index-*.md" > /dev/null; then
    fail "index-split created sub-indexes although below the threshold"
fi

# ------------------------------------------------------------------
# 2. Real split: pointer root + populated sub-indexes.
# ------------------------------------------------------------------
run_tool index-split

lines_after="$(wc -l < "$index" | tr -d ' ')"
[[ "$lines_after" -le 200 ]] || fail "root index still has ${lines_after} lines (limit 200)"

for section in Sources Concepts Entities; do
    grep -q "^## ${section}$" "$index" \
        || fail "root index lost its ## ${section} heading (anchor must stay stable)"
done
grep -qF '[[wiki/index-concepts.md|Concepts Index]]' "$index" \
    || fail "root index has no pointer wikilink to the concepts sub-index"
grep -qF 'Curated preamble note for the split test.' "$index" \
    || fail "preamble prose was not preserved in the root index"

grep -qF 'concept-gen-42.md' "$TMPDIR/wiki/index-concepts.md" \
    || fail "concept entries did not land in wiki/index-concepts.md"
grep -qF 'source-gen-42.md' "$TMPDIR/wiki/index-sources.md" \
    || fail "source entries did not land in wiki/index-sources.md"
grep -qF 'entity-gen-42.md' "$TMPDIR/wiki/index-entities.md" \
    || fail "entity entries did not land in wiki/index-entities.md"
if grep -qF 'concept-gen-42.md' "$index"; then
    fail "entries remained in the root index after the split"
fi

head -1 "$TMPDIR/wiki/index-concepts.md" | grep -qx -- '---' \
    || fail "sub-index is missing YAML frontmatter"
grep -q '^type: index$' "$TMPDIR/wiki/index-concepts.md" \
    || fail "sub-index frontmatter is missing type: index"

# ------------------------------------------------------------------
# 3. HR-008 accepts pages registered only in a sub-index.
# ------------------------------------------------------------------
[[ "$(hr008_violations)" -eq 0 ]] \
    || fail "HR-008 flagged pages that are registered in sub-indexes"

# ------------------------------------------------------------------
# 4. A healthy split vault passes lint (split-aware index completeness).
# ------------------------------------------------------------------
(cd "$TMPDIR" && bash .vault/scripts/vault-tools.sh lint > /dev/null 2>&1) \
    || fail "lint should exit 0 on a healthy split vault"

# ------------------------------------------------------------------
# 5. index-update appends new pages to the right sub-index.
# ------------------------------------------------------------------
mkpage "$TMPDIR/wiki/concepts/concept-late.md" "Late Concept" concept
[[ "$(hr008_violations)" -eq 1 ]] || fail "HR-008 should flag the late page"
run_tool index-update
grep -qF 'concept-late.md' "$TMPDIR/wiki/index-concepts.md" \
    || fail "index-update did not append to the concepts sub-index"
[[ "$(hr008_violations)" -eq 0 ]] || fail "HR-008 should pass after split-layout index-update"

# ------------------------------------------------------------------
# 6. index-rebuild preserves the split layout.
# ------------------------------------------------------------------
run_tool index-rebuild
[[ "$(wc -l < "$index" | tr -d ' ')" -le 200 ]] \
    || fail "index-rebuild abandoned the split layout (root over 200 lines)"
grep -qF '[[wiki/index-concepts.md|Concepts Index]]' "$index" \
    || fail "rebuilt root index lost its sub-index pointer"
grep -qF 'concept-gen-1.md' "$TMPDIR/wiki/index-concepts.md" \
    || fail "rebuilt concepts sub-index lost existing entries"
grep -qF 'concept-late.md' "$TMPDIR/wiki/index-concepts.md" \
    || fail "rebuilt concepts sub-index lost the late page"
[[ "$(hr008_violations)" -eq 0 ]] || fail "HR-008 should pass after split-layout rebuild"

# ------------------------------------------------------------------
# 7. index-rebuild ADOPTS the split layout from scratch when a freshly
#    rebuilt single-file index would overflow the threshold (no prior split).
# ------------------------------------------------------------------
rm -f "$TMPDIR"/wiki/index.md "$TMPDIR"/wiki/index-*.md
run_tool index-rebuild
compgen -G "$TMPDIR/wiki/index-*.md" > /dev/null \
    || fail "index-rebuild did not adopt the split layout for an oversized vault"
[[ "$(wc -l < "$index" | tr -d ' ')" -le 200 ]] \
    || fail "auto-split root index exceeds 200 lines"
grep -qF '[[wiki/index-concepts.md|Concepts Index]]' "$index" \
    || fail "auto-split root index has no sub-index pointer"
[[ "$(hr008_violations)" -eq 0 ]] || fail "HR-008 should pass after auto-split rebuild"

echo "PASS: index-split, split-aware lint, and auto-split rebuild all satisfied"
