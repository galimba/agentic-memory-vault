#!/usr/bin/env bash
# ==============================================================================
# HR-007: Updated Field Accuracy
# ==============================================================================
# Rule: Modified files must have updated field matching commit date (+-1 day).
# Enforcement: Rejects commits where the updated field is stale.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr007() {
    info "HR-007: Checking updated field accuracy..."
    local staged_files
    staged_files=$(get_staged_files)
    local today
    today=$(today_date)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")
        if [[ "$file" != "${WIKI_DIR}/"* ]] || ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local frontmatter
        frontmatter=$(extract_frontmatter "$full_path")
        [[ -z "$frontmatter" ]] && continue

        local updated_value
        updated_value=$(get_frontmatter_field "updated" "$frontmatter")
        [[ -z "$updated_value" ]] && continue

        local diff
        diff=$(date_diff "$today" "$updated_value")
        if [[ $diff -gt $DATE_TOLERANCE ]]; then
            violation "HR-007" "$file" "Updated field '${updated_value}' is ${diff} days from today (${today}). Tolerance is ${DATE_TOLERANCE} day(s)."
        fi
    done <<< "$staged_files"

    success "HR-007: Updated field check complete"
}
