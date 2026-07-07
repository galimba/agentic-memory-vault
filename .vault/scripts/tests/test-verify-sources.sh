#!/usr/bin/env bash
# Test for vault-tools.sh verify-sources (issue #7).
#
# Verifies that `sources:` citations in wiki frontmatter are checked
# against files on disk in raw/:
#   1. A page citing an existing raw/ file verifies (exit 0).
#   2. A page with an empty inline list (sources: []) is not flagged.
#   3. A page citing raw/missing.md fails (exit 1) and the missing
#      path is named in the output.
#
# Run: bash .vault/scripts/tests/test-verify-sources.sh
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
mkdir -p "$TMPDIR/wiki/concepts" "$TMPDIR/raw" "$TMPDIR/memory"
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

# A raw source that exists on disk.
cat > "$TMPDIR/raw/existing-source.md" <<EOF
# Existing Source

Some raw material.
EOF

# Page citing the existing raw file (block-list form, quoted, with
# a |display variant thrown in).
cat > "$TMPDIR/wiki/concepts/concept-cited.md" <<EOF
---
title: "Cited Concept"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: draft
sources:
  - "[[raw/existing-source.md]]"
  - "[[raw/existing-source.md|Existing Source]]"
related: []
tags:
  - domain/engineering
  - type/concept
  - lifecycle/active
owner: agent
confidence: high
---

# Cited Concept
EOF

# Page with an empty inline sources list — must not be flagged.
cat > "$TMPDIR/wiki/concepts/concept-no-sources.md" <<EOF
---
title: "Sourceless Concept"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: draft
sources: []
related: []
tags:
  - domain/engineering
  - type/concept
  - lifecycle/active
owner: agent
confidence: high
---

# Sourceless Concept
EOF

# ------------------------------------------------------------------
# Assert 1: all citations resolve → exit 0, page reported verified.
# ------------------------------------------------------------------
out=$(cd "$TMPDIR" && bash .vault/scripts/vault-tools.sh verify-sources 2>&1) \
    || fail "verify-sources exited non-zero on a vault with valid citations: ${out}"
echo "$out" | grep -q 'verified: wiki/concepts/concept-cited.md' \
    || fail "cited page not reported as verified: ${out}"
if echo "$out" | grep -q 'concept-no-sources'; then
    fail "page with empty sources list should not be reported: ${out}"
fi

# ------------------------------------------------------------------
# Assert 2: a dangling citation → exit 1, missing path named.
# Uses the inline-list form to cover both YAML shapes.
# ------------------------------------------------------------------
cat > "$TMPDIR/wiki/concepts/concept-dangling.md" <<EOF
---
title: "Dangling Concept"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: draft
sources: ["[[raw/existing-source.md]]", "[[raw/missing.md]]"]
related: []
tags:
  - domain/engineering
  - type/concept
  - lifecycle/active
owner: agent
confidence: high
---

# Dangling Concept
EOF

rc=0
out=$(cd "$TMPDIR" && bash .vault/scripts/vault-tools.sh verify-sources 2>&1) || rc=$?
[[ "$rc" -eq 1 ]] \
    || fail "verify-sources exited ${rc} on a dangling citation (expected 1): ${out}"
echo "$out" | grep -q 'dangling: wiki/concepts/concept-dangling.md' \
    || fail "dangling page not reported: ${out}"
echo "$out" | grep -q 'raw/missing.md' \
    || fail "missing path raw/missing.md not named in output: ${out}"
echo "$out" | grep -q 'verified: wiki/concepts/concept-cited.md' \
    || fail "valid page no longer reported as verified: ${out}"

echo "PASS: verify-sources detects dangling raw/ citations"
