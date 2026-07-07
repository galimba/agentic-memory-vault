#!/usr/bin/env bash
# Test for the skill manifest generator (vault-tools.sh skill-manifest).
#
# Proves the full round trip: generate a manifest for a fresh skill, verify
# the required schema fields and a recomputed SHA-256, then record a human
# review (reviewed_by/review_date) and confirm the strict skill-audit passes.
#
# Run: bash .vault/scripts/tests/test-skill-manifest.sh
# Exit: 0 on PASS, non-zero on any FAIL.

set -euo pipefail

VAULT_ROOT="$(git rev-parse --show-toplevel)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

command -v python3 >/dev/null || fail "python3 is required for this test"

# ------------------------------------------------------------------
# Build a minimal vault clone in a tempdir so the test is
# self-contained and cannot touch the developer's real repo.
# ------------------------------------------------------------------
mkdir -p "$TMPDIR/wiki" "$TMPDIR/memory"
cp -r "$VAULT_ROOT/.vault" "$TMPDIR/.vault"
cp -r "$VAULT_ROOT/templates" "$TMPDIR/templates" 2>/dev/null || true

cat > "$TMPDIR/wiki/index.md" <<'EOF'
---
title: "Index"
type: index
created: 2026-07-07
updated: 2026-07-07
status: active
tags:
  - type/index
owner: agent
confidence: high
---

# Vault Index
EOF

cat > "$TMPDIR/wiki/log.md" <<'EOF'
---
title: "Log"
type: index
created: 2026-07-07
updated: 2026-07-07
status: active
tags:
  - type/index
owner: agent
confidence: high
---

# Log
EOF

cat > "$TMPDIR/memory/status.md" <<'EOF'
---
title: "Status"
type: report
created: 2026-07-07
updated: 2026-07-07
status: active
tags:
  - type/report
owner: agent
confidence: high
---

# Status
EOF

# ------------------------------------------------------------------
# Create a dummy skill. Content is deliberately inert: no blocked
# patterns, no lines starting with "!", no external URLs (see
# .vault/schemas/skill-policy.json).
# ------------------------------------------------------------------
mkdir -p "$TMPDIR/.vault/skills/dummy-skill"
cat > "$TMPDIR/.vault/skills/dummy-skill/SKILL.md" <<'EOF'
---
name: dummy-skill
description: A harmless placeholder skill used by the manifest generator test.
---

# Dummy Skill

This skill exists only to exercise the manifest generator in tests.
It performs no actions and contains no automation of any kind.
EOF

cd "$TMPDIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test Runner"

# ------------------------------------------------------------------
# Generate the manifest via the code path under test.
# ------------------------------------------------------------------
bash .vault/scripts/vault-tools.sh skill-manifest .vault/skills/dummy-skill >/dev/null \
    || fail "skill-manifest exited non-zero"

MANIFEST=".vault/skills/dummy-skill/skill-manifest.json"
[[ -f "$MANIFEST" ]] || fail "manifest was not created at ${MANIFEST}"

# ------------------------------------------------------------------
# Assert 1: all schema-required fields are present and non-empty,
# and the files[] array lists exactly SKILL.md.
# ------------------------------------------------------------------
python3 - "$MANIFEST" <<'EOF' || fail "manifest failed schema field validation"
import json
import sys

with open(sys.argv[1]) as fh:
    m = json.load(fh)

for key in ("name", "version", "author", "description", "created", "updated"):
    assert m.get(key), f"missing or empty required field: {key}"

assert m["name"] == "dummy-skill", f"unexpected name: {m['name']}"
files = m.get("files")
assert isinstance(files, list) and len(files) == 1, f"expected 1 file entry, got: {files}"
entry = files[0]
assert entry["path"] == "SKILL.md", f"unexpected path: {entry['path']}"
assert len(entry["sha256"]) == 64, "sha256 is not a 64-char hex digest"
assert entry["size_bytes"] > 0, "size_bytes must be positive"
EOF

# ------------------------------------------------------------------
# Assert 2: the recorded SHA-256 matches an independent recomputation.
# ------------------------------------------------------------------
recorded_hash=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['files'][0]['sha256'])")
actual_hash=$(sha256sum .vault/skills/dummy-skill/SKILL.md | awk '{print $1}')
[[ "$recorded_hash" == "$actual_hash" ]] \
    || fail "manifest sha256 (${recorded_hash}) does not match recomputed hash (${actual_hash})"

# ------------------------------------------------------------------
# Assert 3: after a human review is recorded, the strict skill-audit
# passes end-to-end (manifest + review + hash verification).
# ------------------------------------------------------------------
python3 - "$MANIFEST" <<'EOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    m = json.load(fh)
m["reviewed_by"] = "test-reviewer"
m["review_date"] = "2026-07-07"
with open(path, "w") as fh:
    json.dump(m, fh, indent=2)
    fh.write("\n")
EOF

bash .vault/scripts/vault-tools.sh skill-audit >/dev/null \
    || fail "skill-audit rejected a reviewed skill with a freshly generated manifest"

echo "PASS: skill-manifest generates a valid, audit-passing manifest"
