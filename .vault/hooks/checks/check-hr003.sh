#!/usr/bin/env bash
# ==============================================================================
# HR-003: Mandatory Tags
# ==============================================================================
# Rule: Every wiki/ file must have at least one tag from the approved taxonomy.
# Enforcement: Rejects commits with missing or unapproved tags in wiki/ files.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr003() {
    info "HR-003: Checking mandatory tags..."
    local staged_files
    staged_files=$(get_staged_files)

    # Load approved tags from taxonomy for validation
    local approved_tags=""
    if [[ -f "${VAULT_ROOT}/${TAGS_FILE}" ]]; then
        approved_tags=$(get_approved_tags)
    fi

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
        if [[ -z "$tags" ]]; then
            violation "HR-003" "$file" "No tags found. Every wiki page must have at least one approved tag."
            continue
        fi

        # Validate each tag against approved taxonomy if available
        if [[ -n "$approved_tags" ]]; then
            local has_approved_tag=false
            while IFS= read -r tag; do
                [[ -z "$tag" ]] && continue
                if echo "$approved_tags" | grep -qxF "$tag"; then
                    has_approved_tag=true
                fi
            done <<< "$tags"
            if ! $has_approved_tag; then
                violation "HR-003" "$file" "No approved tags found. Tags must be from the taxonomy in ${TAGS_FILE}."
            fi
        fi
    done <<< "$staged_files"

    success "HR-003: Tag presence check complete"
}
