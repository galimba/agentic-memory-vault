#!/usr/bin/env bash
# ==============================================================================
# LIB-SKILLS — Skill manifest tooling for vault-tools
# ==============================================================================
#
# Contains commands for skill packaging and review workflows:
#   cmd_skill_manifest() — Generate or refresh skill-manifest.json for a skill
#
# The manifest schema is defined in .vault/schemas/skill-manifest.schema.md
# and verified by cmd_skill_audit (audits/audit-skills.sh). Under a strict
# skill policy the manifest must also carry non-empty reviewed_by and
# review_date fields recorded by a human reviewer.
#
# This file is sourced by vault-tools.sh and depends on functions and
# variables from lib-utils.sh and the entry point configuration.
#
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

# ==============================================================================
# COMMAND: skill-manifest
# ==============================================================================
# Generate or refresh skill-manifest.json for a skill directory.
#
# Usage: vault-tools.sh skill-manifest <skill-dir>
#
# Behavior:
#   - New manifest: fills metadata defaults (name from dir basename, version
#     1.0.0, author from git config, placeholder description) and warns that
#     description and human review must be completed before committing.
#   - Existing manifest: preserves name/version/author/description/created
#     and any reviewed_by/review_date. If file hashes changed or files were
#     added/removed, prints a prominent warning that the prior review is
#     invalidated — the review fields are still preserved; the human decides.
#   - Always sets updated to today and rewrites the files[] array from disk.

cmd_skill_manifest() {
    header "Skill Manifest Generator"

    local skill_dir="${1:-}"
    if [[ -z "$skill_dir" ]]; then
        error "Usage: vault-tools.sh skill-manifest <skill-dir>"
        return 2
    fi
    if [[ ! -d "$skill_dir" ]]; then
        error "Skill directory not found: ${skill_dir}"
        return 2
    fi
    if ! command -v python3 &>/dev/null; then
        error "python3 is required to generate manifests but was not found in PATH"
        return 2
    fi

    # Normalize to an absolute path so relative entries are computed reliably
    skill_dir="$(cd "$skill_dir" && pwd)"
    local manifest_file="${skill_dir}/skill-manifest.json"
    local skill_name
    skill_name=$(basename "$skill_dir")

    subheader "Skill: ${skill_name} (${skill_dir#${VAULT_ROOT}/})"

    if [[ ! -f "${skill_dir}/SKILL.md" ]]; then
        warning "No SKILL.md found — is this really a skill directory?"
    fi

    # --- Collect files: relative path, sha256, size in bytes ---
    # The manifest itself is excluded from hashing per the schema.
    local entries=""
    local file_count=0
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local rel="${f#${skill_dir}/}"
        local hash size
        hash=$(sha256sum "$f" | awk '{print $1}')
        size=$(stat -c%s "$f" 2>/dev/null || wc -c < "$f" | tr -d ' ')
        entries+="${rel}|${hash}|${size}"$'\n'
        file_count=$((file_count + 1))
    done < <(find "$skill_dir" -type f ! -name "skill-manifest.json" 2>/dev/null | sort)

    if [[ $file_count -eq 0 ]]; then
        warning "No files found in skill directory — manifest will have an empty files[] array"
    fi

    # --- Author default for new manifests ---
    local author
    author=$(git config user.name 2>/dev/null || true)
    [[ -z "$author" ]] && author="unknown"

    local today
    today=$(date +%Y-%m-%d)

    # --- Write the manifest via python3 (consistent with audit-skills.sh) ---
    # Prints NEW / CHANGED / UNCHANGED so the shell can react below.
    local py_status
    py_status=$(MANIFEST_FILE="$manifest_file" ENTRIES="$entries" TODAY="$today" \
        DEFAULT_NAME="$skill_name" DEFAULT_AUTHOR="$author" python3 <<'PYEOF'
import json
import os

manifest_file = os.environ["MANIFEST_FILE"]
today = os.environ["TODAY"]

files = []
for line in os.environ.get("ENTRIES", "").splitlines():
    if not line.strip():
        continue
    # rsplit: the path itself may contain '|', the hash and size cannot
    path, sha, size = line.rsplit("|", 2)
    files.append({"path": path, "sha256": sha, "size_bytes": int(size)})

existing = None
if os.path.exists(manifest_file):
    with open(manifest_file) as fh:
        existing = json.load(fh)

if existing is not None:
    # Preserve human-owned metadata, including review sign-off
    manifest = {
        "name": existing.get("name", os.environ["DEFAULT_NAME"]),
        "version": existing.get("version", "1.0.0"),
        "author": existing.get("author", os.environ["DEFAULT_AUTHOR"]),
        "description": existing.get("description", "TODO: describe this skill"),
        "created": existing.get("created", today),
        "updated": today,
    }
    for opt in ("reviewed_by", "review_date"):
        if existing.get(opt):
            manifest[opt] = existing[opt]
    manifest["files"] = files
    old_hashes = {e.get("path"): e.get("sha256") for e in existing.get("files", [])}
    new_hashes = {e["path"]: e["sha256"] for e in files}
    status = "CHANGED" if old_hashes != new_hashes else "UNCHANGED"
else:
    manifest = {
        "name": os.environ["DEFAULT_NAME"],
        "version": "1.0.0",
        "author": os.environ["DEFAULT_AUTHOR"],
        "description": "TODO: describe this skill",
        "created": today,
        "updated": today,
        "files": files,
    }
    status = "NEW"

with open(manifest_file, "w") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")

print(status)
PYEOF
    ) || { error "python3 failed to write the manifest"; return 2; }

    case "$py_status" in
        NEW)
            warning "New manifest created with placeholder metadata."
            warning "Before committing under a strict skill policy you must:"
            warning "  1. Replace the placeholder 'description'"
            warning "  2. Obtain human review and record reviewed_by + review_date"
            ;;
        CHANGED)
            warning "=================================================================="
            warning "SKILL CONTENT CHANGED: files were added, removed, or modified"
            warning "since the previous manifest. Any prior human review is now"
            warning "INVALIDATED — under a strict skill policy this skill requires a"
            warning "fresh review. reviewed_by/review_date were preserved as-is; a"
            warning "human must re-review and update (or clear) them deliberately."
            warning "=================================================================="
            ;;
        UNCHANGED)
            ok "File contents unchanged since previous manifest (metadata refreshed)"
            ;;
    esac

    ok "Manifest written: ${manifest_file#${VAULT_ROOT}/} (${file_count} files)"
    echo ""
    return 0
}
