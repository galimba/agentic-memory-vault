#!/usr/bin/env bash
# ==============================================================================
# HR-014: No File Deletion in wiki/ or memory/
# ==============================================================================
# Rule: Agents must not delete files from wiki/ or memory/. To remove content
#       from the active vault, set status: archived in frontmatter instead.
#       Git history preserves all content; this rule ensures the working tree
#       never loses knowledge through deletion.
# Enforcement: Checks git diff --cached for deleted files (diff-filter=D) in
#       wiki/ and memory/ directories. Rejects the commit if any are found.
# Bypass: VAULT_ALLOW_DELETE=1 for legitimate cleanup by vault administrators.
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

    if [[ $VIOLATIONS -eq 0 ]]; then
        success "HR-014: No prohibited file deletions"
    fi
}
