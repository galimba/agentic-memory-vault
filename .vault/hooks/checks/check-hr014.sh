#!/usr/bin/env bash
# ==============================================================================
# HR-014: No File Deletion in wiki/ or memory/
# ==============================================================================
# Rule: Agents must not delete files from wiki/ or memory/. To remove content
#       from the active vault, set status: archived in frontmatter instead.
# Enforcement: Checks git diff --cached --name-only --diff-filter=D for deleted
#       files and --diff-filter=R for renames out of wiki/ and memory/.
#       Rejects the commit if any are found.
# Bypass: VAULT_ALLOW_DELETE=1 for legitimate cleanup (secrets, PII, test
#       artifacts).
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr014() {
    info "HR-014: Checking for prohibited file deletions..."

    # Allow explicit bypass for legitimate cleanup
    if [[ "${VAULT_ALLOW_DELETE:-0}" == "1" ]]; then
        warn "HR-014: VAULT_ALLOW_DELETE=1 — file deletion check bypassed"
        return
    fi

    local deleted_files
    deleted_files=$(git diff --cached --name-only --diff-filter=D 2>/dev/null || true)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        if [[ "$file" == wiki/* ]] || [[ "$file" == memory/* ]]; then
            violation "HR-014" "$file" \
                "File deletion is prohibited. Set 'status: archived' in frontmatter instead. Use VAULT_ALLOW_DELETE=1 to bypass for legitimate cleanup."
        fi
    done <<< "$deleted_files"

    # Also catch renames that move files OUT of protected directories
    local rename_status
    rename_status=$(git diff --cached --name-status --diff-filter=R 2>/dev/null || true)

    while IFS=$'\t' read -r status old_path new_path; do
        [[ -z "$old_path" ]] && continue

        # Check if file is being renamed OUT of a protected directory
        local old_protected=false
        if [[ "$old_path" == wiki/* ]] || [[ "$old_path" == memory/* ]]; then
            old_protected=true
        fi

        local new_protected=false
        if [[ "$new_path" == wiki/* ]] || [[ "$new_path" == memory/* ]]; then
            new_protected=true
        fi

        if $old_protected && ! $new_protected; then
            violation "HR-014" "$old_path" \
                "Renaming files out of wiki/ or memory/ is prohibited (target: ${new_path}). Set 'status: archived' instead. Use VAULT_ALLOW_DELETE=1 to bypass."
        fi
    done <<< "$rename_status"

    if [[ $VIOLATIONS -eq 0 ]]; then
        success "HR-014: No prohibited file deletions"
    fi
}
