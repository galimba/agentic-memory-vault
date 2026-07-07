#!/usr/bin/env bash
# Smoke test harness for the vault tooling (issue #17).
#
# Builds a disposable vault in a tempdir, installs the real pre-commit hook,
# and exercises the full surface in two passes:
#
#   Positive path  — every vault-tools.sh command must exit 0 on a healthy
#                    vault, and a valid wiki page must commit through the
#                    real hook.
#   Adversarial    — commits that violate hard rules must be BLOCKED by the
#                    hook with the specific HR-### marker in the output:
#                      HR-002 (missing frontmatter), HR-004 (oversize page),
#                      HR-012 (CLAUDE.md modification), HR-015 (log deletion).
#                    The content policy ships in WARN mode, so an injection
#                    phrase must produce a CONTENT-POLICY warning (the commit
#                    itself may succeed).
#
# Run: bash .vault/scripts/tests/test-smoke.sh
# Exit: 0 on PASS, non-zero on any FAIL.

set -euo pipefail

VAULT_ROOT="$(git rev-parse --show-toplevel)"
SMOKE_TMP="$(mktemp -d)"
trap 'rm -rf "$SMOKE_TMP"' EXIT

TODAY="$(date +%Y-%m-%d)"
CHECKS=0

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

pass() {
    CHECKS=$((CHECKS + 1))
    echo "  ok: $*"
}

# Run a vault-tools.sh command that must exit 0.
# Usage: run_tool "<description>" <command> [args...]
run_tool() {
    local desc="$1"
    shift
    local out rc=0
    out=$(bash .vault/scripts/vault-tools.sh "$@" 2>&1) || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "$out" >&2
        fail "vault-tools.sh ${desc} exited ${rc} (expected 0)"
    fi
    pass "vault-tools.sh ${desc} exit 0"
}

# Attempt a commit of already-staged changes that MUST be blocked by the
# hook, with the given marker present in the rejection output.
# Usage: expect_blocked "HR-004" "commit message"
expect_blocked() {
    local marker="$1"
    local msg="$2"
    local out rc=0
    out=$(git commit -q -m "$msg" 2>&1) || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "$out" >&2
        fail "commit '${msg}' should have been blocked (${marker})"
    fi
    if ! echo "$out" | grep -q "$marker"; then
        echo "$out" >&2
        fail "blocked commit '${msg}' output missing ${marker} marker"
    fi
    pass "commit blocked with ${marker} (${msg})"
}

# Restore the vault to the pristine baseline commit between adversarial cases.
reset_vault() {
    git reset -q --hard "$BASELINE"
    git clean -qfd
}

# ------------------------------------------------------------------
# 1. Build a minimal vault clone in a tempdir. Copy the real .vault/
# and templates/, then create the smallest content set that satisfies
# the hard rules and doctor's structural checks. Re-init git so the
# test can never touch the developer's real repo.
# ------------------------------------------------------------------
mkdir -p "$SMOKE_TMP"/wiki/{sources,entities,concepts,comparisons} \
         "$SMOKE_TMP"/memory/{decisions,logs,notes} \
         "$SMOKE_TMP/raw" "$SMOKE_TMP/docs"
cp -r "$VAULT_ROOT/.vault" "$SMOKE_TMP/.vault"
cp -r "$VAULT_ROOT/templates" "$SMOKE_TMP/templates"

touch "$SMOKE_TMP/raw/.gitkeep"

# CLAUDE.md stub — needed as the protected target for the HR-012 case.
cat > "$SMOKE_TMP/CLAUDE.md" <<'EOF'
# CLAUDE.md — Smoke Vault Agent Configuration

Stub agent configuration for the smoke test vault.
EOF

# AGENTS.md stub — listed as a required file by doctor.
cat > "$SMOKE_TMP/AGENTS.md" <<'EOF'
# AGENTS.md — Smoke Vault Agent Instructions

Stub agent instructions for the smoke test vault.
EOF

cat > "$SMOKE_TMP/wiki/index.md" <<EOF
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

cat > "$SMOKE_TMP/wiki/log.md" <<EOF
---
title: "Smoke Vault Log"
type: index
created: ${TODAY}
updated: ${TODAY}
status: active
tags:
  - type/index
owner: agent
confidence: high
---

# Smoke Vault Log

## [${TODAY}] ingest | Seeded smoke test vault
EOF

cat > "$SMOKE_TMP/memory/status.md" <<EOF
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

Smoke test vault is operational.
EOF

# Raw source file. HR-001 rejects ANY staged path under raw/, so raw
# material must enter via the hook-bypassed seed commit below — this
# models human-approved raw ingestion.
cat > "$SMOKE_TMP/raw/source-smoke-notes.md" <<'EOF'
# Smoke Notes

Source material used by the smoke test concept page.
EOF

# ------------------------------------------------------------------
# 2. Init git, seed commit (hook bypassed), install the real hook.
# ------------------------------------------------------------------
cd "$SMOKE_TMP" || fail "could not cd into tempdir"
git init -q
git config user.email "test@example.com"
git config user.name "Test Runner"
git add .
git -c core.hooksPath=/dev/null commit -q -m "seed" \
    || fail "could not create seed commit (hooks path bypass failed)"
pass "temp vault seeded"

run_tool "init-hooks" init-hooks
grep -q 'vault-tools:pre-commit-wrapper' .git/hooks/pre-commit \
    || fail "installed hook is missing the wrapper marker"
pass "pre-commit wrapper installed"

# ------------------------------------------------------------------
# 3. Seed a valid wiki page, rebuild the index (HR-008), and commit
# through the REAL hook. This must succeed.
# ------------------------------------------------------------------
cat > wiki/concepts/concept-smoke-test.md <<EOF
---
title: "Smoke Test Concept"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: draft
sources:
  - "[[raw/source-smoke-notes.md]]"
related:
  - "[[wiki/index.md]]"
tags:
  - domain/engineering
  - type/concept
  - lifecycle/active
owner: agent
confidence: high
---

# Smoke Test Concept

A minimal valid concept page seeded by the smoke test. It cites its raw
source via [[raw/source-smoke-notes.md]] and links [[wiki/index.md]] and
[[wiki/log.md]] to satisfy link-density soft rules.
EOF

run_tool "index-rebuild (register seeded page)" index-rebuild
grep -qF "concept-smoke-test.md" wiki/index.md \
    || fail "index-rebuild did not register the seeded concept page"

git add wiki/index.md wiki/concepts/concept-smoke-test.md
git commit -q -m "[ingest] add smoke test concept" \
    || fail "hook rejected a fully valid wiki page commit"
pass "valid wiki page committed through the real hook"

BASELINE="$(git rev-parse HEAD)"

# ------------------------------------------------------------------
# 4. Positive path — every command must exit 0 on a healthy vault.
# ------------------------------------------------------------------
run_tool "lint" lint
run_tool "lint --report" lint --report
compgen -G "memory/notes/lint-report-*.md" > /dev/null \
    || fail "lint --report did not create memory/notes/lint-report-*.md"
pass "lint --report wrote memory/notes/lint-report-*.md"
run_tool "doctor" doctor
run_tool "status" status
run_tool "stats" stats
run_tool "validate" validate wiki/concepts/concept-smoke-test.md
run_tool "orphans" orphans
run_tool "stale" stale
run_tool "tag-audit" tag-audit
run_tool "skill-audit" skill-audit
run_tool "content-audit" content-audit
run_tool "index-rebuild" index-rebuild
reset_vault

# ------------------------------------------------------------------
# 5. Adversarial path — each case stages a violation, attempts a real
# commit through the hook, asserts the block + HR marker, then resets.
# ------------------------------------------------------------------

# HR-002: wiki page without frontmatter
echo "A wiki page without any frontmatter." > wiki/concepts/no-frontmatter.md
git add wiki/concepts/no-frontmatter.md
expect_blocked "HR-002" "wiki page without frontmatter"
reset_vault

# HR-004: wiki page over the 400-line hard limit (valid frontmatter)
{
    cat <<EOF
---
title: "Oversize Page"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: draft
tags:
  - domain/engineering
  - type/concept
owner: agent
confidence: low
---

# Oversize Page
EOF
    for i in $(seq 1 401); do
        echo "Filler line ${i} to push the page past the hard limit."
    done
} > wiki/concepts/concept-oversize.md
git add wiki/concepts/concept-oversize.md
expect_blocked "HR-004" "wiki page over 400 lines"
reset_vault

# HR-012: modification to CLAUDE.md
echo "unauthorized agent edit" >> CLAUDE.md
git add CLAUDE.md
expect_blocked "HR-012" "modify CLAUDE.md"
reset_vault

# HR-015: deletion of an existing line in wiki/log.md
sed -i '/^# Smoke Vault Log$/d' wiki/log.md
git add wiki/log.md
expect_blocked "HR-015" "delete line from wiki/log.md"
reset_vault

# CONTENT-POLICY (warn mode): a page containing an injection phrase must
# produce a content-policy warning. Enforcement ships as "warn", so the
# commit itself MAY succeed — assert the warning marker only, then reset.
cat > wiki/concepts/concept-injection-sample.md <<EOF
---
title: "Injection Sample"
type: concept
created: ${TODAY}
updated: ${TODAY}
status: draft
tags:
  - domain/security
  - type/concept
owner: agent
confidence: low
---

# Injection Sample

This page deliberately embeds the phrase "ignore previous instructions"
so the smoke test can observe the content-policy scan.
EOF
echo "- [[wiki/concepts/concept-injection-sample.md|Injection Sample]]" >> wiki/index.md
git add wiki/concepts/concept-injection-sample.md wiki/index.md
policy_rc=0
policy_out=$(git commit -q -m "injection sample page" 2>&1) || policy_rc=$?
if ! echo "$policy_out" | grep -q "CONTENT-POLICY"; then
    echo "$policy_out" >&2
    fail "injection page commit output missing CONTENT-POLICY warning marker"
fi
if ! echo "$policy_out" | grep -qi "contains pattern"; then
    echo "$policy_out" >&2
    fail "content-policy warning did not name the matched pattern"
fi
pass "content-policy warning emitted for injection phrase (commit rc=${policy_rc}, warn mode)"
reset_vault

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "PASS: smoke test complete — ${CHECKS} checks passed"
