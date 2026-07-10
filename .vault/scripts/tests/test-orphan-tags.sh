#!/usr/bin/env bash
# Test for `vault-tools.sh orphan-tags`.
#
# Seeds a temp vault with a copy of the real .vault/rules/tags.md (so the
# approved taxonomy is real) and a single wiki page that uses only one
# approved tag. Asserts:
#   - orphan-tags exits 0
#   - a tag the page does NOT use is listed as orphaned
#   - the tag the page DOES use is NOT listed as orphaned
#
# Run: bash .vault/scripts/tests/test-orphan-tags.sh
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

mkdir -p "$TMPDIR/wiki/concepts"
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

# Only page in the vault. Uses domain/engineering — leaves every other
# approved tag (e.g. domain/legal, priority/critical) unused.
cat > "$TMPDIR/wiki/concepts/concept-solo.md" <<EOF
---
title: "Concept Solo"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: active
sources: []
related: []
tags:
  - domain/engineering
  - type/concept
  - lifecycle/active
owner: agent
confidence: medium
---

# Concept Solo

Only page in this scratch vault.
EOF

output="$(cd "$TMPDIR" && bash .vault/scripts/vault-tools.sh orphan-tags)" \
    || fail "orphan-tags exited non-zero"

grep -q "domain/legal" <<< "$output" \
    || fail "expected unused approved tag domain/legal to be listed as orphaned"

if grep -q "domain/engineering" <<< "$output"; then
    fail "domain/engineering is used by concept-solo.md and must not be listed as orphaned"
fi

echo "PASS: orphan-tags lists unused approved tags and excludes used ones"
