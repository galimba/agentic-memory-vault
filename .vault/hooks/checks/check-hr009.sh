#!/usr/bin/env bash
# ==============================================================================
# HR-009: Flat Tag Notation
# ==============================================================================
# Rule: Tags must match pattern: prefix/value (exactly one slash, no spaces).
# Enforcement: Rejects commits with malformed tags in wiki/ files.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr009() {
    info "HR-009: Checking flat tag notation..."
    local staged_files
    staged_files=$(get_staged_files)
    local tag_pattern='^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$'

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

        local tags
        tags=$(get_frontmatter_tags "$frontmatter")
        [[ -z "$tags" ]] && continue

        while IFS= read -r tag; do
            [[ -z "$tag" ]] && continue
            if ! echo "$tag" | grep -qE "$tag_pattern"; then
                violation "HR-009" "$file" "Invalid tag format '${tag}'. Must match prefix/value (lowercase, hyphenated, one slash)."
            fi
        done <<< "$tags"
    done <<< "$staged_files"

    success "HR-009: Tag notation check complete"
}
