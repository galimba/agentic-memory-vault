#!/usr/bin/env bash
# Test for vault-tools.sh index-update (issue #10): incremental index
# registration. Asserts that:
#   1. An unregistered wiki page trips the HR-008 hook check.
#   2. index-update appends it under the section matching its frontmatter
#      type, creating the section heading when it does not exist yet.
#   3. Existing entries and human-authored prose are preserved untouched.
#   4. After index-update the HR-008 check passes.
#   5. A second run is a no-op (byte-identical index).
#
# Run: bash .vault/scripts/tests/test-index-update.sh
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
# violation count. Runs in a subshell so the sourced hook config cannot
# leak into the test.
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

# Print the body of "## <section>" from a file (up to the next section)
section_body() {
    awk -v sec="## $2" '
        $0 == sec { on = 1; next }
        on && /^## / { exit }
        on { print }' "$1"
}

# ------------------------------------------------------------------
# Build a minimal vault clone. vault-tools.sh resolves VAULT_ROOT from
# its own location, so the copied script operates inside the tempdir.
# ------------------------------------------------------------------
mkdir -p "$TMPDIR/wiki/concepts" "$TMPDIR/wiki/sources" "$TMPDIR/memory"
cp -r "$REPO_ROOT/.vault" "$TMPDIR/.vault"

# Hand-written index: prose, an existing entry, and NO Decisions section.
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

Curated by humans — this prose line must survive index-update.

## Sources

_No sources yet._

## Concepts

- [[wiki/concepts/concept-existing.md|Existing Concept]] — Already registered.
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

mkpage() {  # mkpage <path> <title> <type> <summary>
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
summary: "$4"
owner: agent
confidence: high
---

# $2
EOF
}

mkpage "$TMPDIR/wiki/concepts/concept-existing.md" "Existing Concept" concept "Already registered."

# ------------------------------------------------------------------
# 1. Baseline: registered-only vault passes HR-008.
# ------------------------------------------------------------------
[[ "$(hr008_violations)" -eq 0 ]] || fail "baseline vault should pass HR-008"

# ------------------------------------------------------------------
# 2. Add unregistered pages: one for an existing section, one for a
# missing section, one for an empty (placeholder) section.
# ------------------------------------------------------------------
mkpage "$TMPDIR/wiki/concepts/concept-new.md" "Brand New Concept" concept "Not yet in the index."
mkpage "$TMPDIR/wiki/concepts/decision-001-adopt.md" "Adopt The Thing" decision "Needs a new Decisions section."
mkpage "$TMPDIR/wiki/sources/source-notes.md" "Source Notes" source "Replaces the Sources placeholder."

[[ "$(hr008_violations)" -eq 3 ]] || fail "HR-008 should flag exactly the 3 unregistered pages"

# ------------------------------------------------------------------
# 3. index-update registers them under the correct sections.
# ------------------------------------------------------------------
(cd "$TMPDIR" && bash .vault/scripts/vault-tools.sh index-update > /dev/null) \
    || fail "index-update exited non-zero"

index="$TMPDIR/wiki/index.md"

section_body "$index" "Concepts" | grep -q 'concept-new.md' \
    || fail "new concept not appended under ## Concepts"
section_body "$index" "Decisions" | grep -q 'decision-001-adopt.md' \
    || fail "## Decisions section was not created for the decision page"
section_body "$index" "Sources" | grep -q 'source-notes.md' \
    || fail "source page not appended under ## Sources"
if section_body "$index" "Sources" | grep -q '_No sources yet._'; then
    fail "placeholder should be replaced when the first entry arrives"
fi

grep -qF 'Curated by humans — this prose line must survive index-update.' "$index" \
    || fail "human prose was not preserved"
[[ "$(grep -cF 'concept-existing.md' "$index")" -eq 1 ]] \
    || fail "existing entry was duplicated or removed"

[[ "$(hr008_violations)" -eq 0 ]] || fail "HR-008 should pass after index-update"

# ------------------------------------------------------------------
# 4. Second run is a no-op.
# ------------------------------------------------------------------
before="$(cksum < "$index")"
(cd "$TMPDIR" && bash .vault/scripts/vault-tools.sh index-update > /dev/null) \
    || fail "second index-update exited non-zero"
[[ "$(cksum < "$index")" == "$before" ]] || fail "second index-update modified the index"

echo "PASS: index-update registers missing pages incrementally"
