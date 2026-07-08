#!/usr/bin/env bash
# Regression test for HR-003 rejecting the entire source-type/ tag category.
#
# get_approved_tags() in .vault/hooks/lib-hook-utils.sh required the tag
# prefix to match [a-z]+ (letters only), so no bullet under a hyphenated
# prefix heading (source-type/ is the only one in the taxonomy) ever
# entered the approved set. A page tagged only source-type/article was
# rejected by the pre-commit hook with "No approved tags found", despite
# the tag being documented in tags.md and passing HR-009's own notation
# check (issue #39).
#
# Also covers the secondary bug: audit-tags.sh's approved-tag count was
# inflated by an unanchored grep matching the `prefix/value` example in
# this file's own descriptive prose.
#
# Run: bash .vault/scripts/tests/test-tag-regex.sh
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
# Build a minimal vault clone with its own git repo and the real
# pre-commit hook installed.
# ------------------------------------------------------------------
mkdir -p "$FIXTURE_DIR/wiki/concepts" "$FIXTURE_DIR/memory/notes" \
    "$FIXTURE_DIR/memory/logs" "$FIXTURE_DIR/memory/decisions"
cp -r "$VAULT_ROOT/.vault" "$FIXTURE_DIR/.vault"

cat > "$FIXTURE_DIR/wiki/index.md" <<EOF
---
title: "Vault Index"
type: index
created: ${TODAY}
updated: ${TODAY}
status: active
tags:
  - type/index
---

# Vault Index
EOF
printf '## [%s] init | Vault Initialized\n' "$TODAY" > "$FIXTURE_DIR/wiki/log.md"

git -C "$FIXTURE_DIR" init -q
git -C "$FIXTURE_DIR" config user.name "Tag Regex Tester"
git -C "$FIXTURE_DIR" config user.email "tag-regex-tester@example.com"
git -C "$FIXTURE_DIR" add -A
git -C "$FIXTURE_DIR" -c core.hooksPath=/dev/null commit -q -m seed
bash "$FIXTURE_DIR/.vault/scripts/vault-tools.sh" init-hooks >/dev/null

# ------------------------------------------------------------------
# Assert: a page tagged only source-type/article commits successfully
# through the real pre-commit hook.
# ------------------------------------------------------------------
cat > "$FIXTURE_DIR/wiki/concepts/hyphen-prefix.md" <<EOF
---
title: "Hyphenated Prefix Tag Page"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: draft
tags:
  - source-type/article
---

# Hyphenated Prefix Tag Page
EOF
(
    cd "$FIXTURE_DIR" || exit 1
    bash .vault/scripts/vault-tools.sh index-update >/dev/null
)

rc=0
output="$(cd "$FIXTURE_DIR" && git add -A && git commit -m "test: source-type tag" 2>&1)" || rc=$?
[[ "$rc" -eq 0 ]] || fail "commit with only a source-type/* tag was blocked (rc=${rc}): ${output}"
echo "$output" | grep -qE '\[HR-003\]|No approved tags found' \
    && fail "HR-003 violation reported for an approved source-type/* tag"

# ------------------------------------------------------------------
# Assert: get_approved_tags() in the real vault recognizes every
# documented source-type/* tag.
# ------------------------------------------------------------------
approved="$(
    cd "$VAULT_ROOT" || exit 1
    VAULT_ROOT="$VAULT_ROOT" TAGS_FILE=".vault/rules/tags.md" bash -c '
        source .vault/hooks/lib-hook-utils.sh
        get_approved_tags
    '
)"
echo "$approved" | grep -qx "source-type/article" \
    || fail "get_approved_tags() does not recognize source-type/article"

# ------------------------------------------------------------------
# Assert: tag-audit's approved count matches a hand count of taxonomy
# bullets (not inflated by the unanchored-grep prose match).
# ------------------------------------------------------------------
hand_count="$(grep -cE '^\- `[a-z][a-z0-9-]*/[a-z0-9-]+`' "$VAULT_ROOT/.vault/rules/tags.md")"
audit_output="$(cd "$VAULT_ROOT" && bash .vault/scripts/vault-tools.sh tag-audit 2>&1)"
reported_count="$(echo "$audit_output" | grep -oE 'Loaded [0-9]+ approved tags' | grep -oE '[0-9]+')"
[[ "$reported_count" == "$hand_count" ]] \
    || fail "tag-audit reported ${reported_count} approved tags, hand count is ${hand_count}"

echo "PASS: source-type/* tags are approved and tag-audit's count is accurate"
