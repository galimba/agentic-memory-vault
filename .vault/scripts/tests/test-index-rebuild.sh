#!/usr/bin/env bash
# Regression test for index-rebuild dropping pages with non-standard types.
#
# Reproduces the bug where cmd_index_rebuild collected pages into type_pages
# keyed by frontmatter type, but the emit loop iterated only the fixed list
# "source concept entity comparison decision report evaluation". The
# '*) section_title="Other" ;;' case arm was unreachable, so pages with any
# other type (including the "uncategorized" fallback the function itself
# assigns) were collected but never written to wiki/index.md — and
# check-hr008.sh then blocked their commits forever (issue #26).
#
# Run: bash .vault/scripts/tests/test-index-rebuild.sh
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
# Build a minimal vault clone in a tempdir. vault-tools.sh resolves
# VAULT_ROOT from its own location, so running the copied script
# operates entirely inside the tempdir — no git repo needed.
# ------------------------------------------------------------------
mkdir -p "$TMPDIR/wiki/concepts" "$TMPDIR/memory"
cp -r "$VAULT_ROOT/.vault" "$TMPDIR/.vault"
cp -r "$VAULT_ROOT/templates" "$TMPDIR/templates" 2>/dev/null || true

# Minimum wiki skeleton (index.md gets overwritten by index-rebuild).
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

cat > "$TMPDIR/memory/status.md" <<EOF
---
title: "Status"
type: report
created: ${TODAY}
updated: ${TODAY}
status: active
tags:
  - type/report
owner: agent
confidence: high
---

# Status
EOF

# One page with a standard type...
cat > "$TMPDIR/wiki/concepts/concept-standard.md" <<EOF
---
title: "Standard Concept Page"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: draft
sources: []
related: []
tags:
  - domain/engineering
  - type/concept
summary: "A concept page with a standard type."
owner: agent
confidence: high
---

# Standard Concept Page
EOF

# ...and one with a type outside the fixed emit list.
cat > "$TMPDIR/wiki/concepts/custom-page.md" <<EOF
---
title: "Custom Type Page"
type: custom
created: ${TODAY}
updated: ${TODAY}
status: draft
sources: []
related: []
tags:
  - domain/engineering
  - type/concept
summary: "A page whose type is not in the standard list."
owner: agent
confidence: high
---

# Custom Type Page
EOF

# ------------------------------------------------------------------
# Rebuild the index via the code path under test.
# ------------------------------------------------------------------
(cd "$TMPDIR" && bash .vault/scripts/vault-tools.sh index-rebuild >/dev/null) \
    || fail "index-rebuild exited non-zero"

index="$TMPDIR/wiki/index.md"

# ------------------------------------------------------------------
# Assert 1: the standard-typed page lands under "## Concepts".
# ------------------------------------------------------------------
awk '/^## Concepts/,/^## [^C]/' "$index" | grep -q 'Standard Concept Page' \
    || fail "concept page missing from the Concepts section"

# ------------------------------------------------------------------
# Assert 2: the custom-typed page lands under "## Other". Before the
# fix it was silently dropped from the rebuilt index entirely.
# ------------------------------------------------------------------
grep -q '^## Other' "$index" \
    || fail "no Other section despite a page with a non-standard type"
awk '/^## Other/,0' "$index" | grep -q 'Custom Type Page' \
    || fail "custom-typed page missing from the Other section"

# ------------------------------------------------------------------
# Assert 3: with the custom-typed page gone, a rebuild must NOT emit
# an empty Other section.
# ------------------------------------------------------------------
rm "$TMPDIR/wiki/concepts/custom-page.md"
(cd "$TMPDIR" && bash .vault/scripts/vault-tools.sh index-rebuild >/dev/null) \
    || fail "index-rebuild exited non-zero on second run"
if grep -q '^## Other' "$index"; then
    fail "empty Other section emitted when no non-standard types exist"
fi

echo "PASS: index-rebuild emits non-standard types under Other"
