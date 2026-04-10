#!/usr/bin/env bash
# ==============================================================================
# HR-006: Unique Page Titles
# ==============================================================================
# Rule: No two files in wiki/ may share the same title frontmatter value.
# Enforcement: Rejects commits that introduce duplicate titles.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr006() {
    info "HR-006: Checking unique page titles..."

    # Build a map of all wiki/ titles
    declare -A title_map
    local duplicates_found=false

    while IFS= read -r -d '' file; do
        local ext
        ext=$(get_extension "$file")
        if ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local frontmatter
        frontmatter=$(extract_frontmatter "$file")
        [[ -z "$frontmatter" ]] && continue

        local title
        title=$(get_frontmatter_field "title" "$frontmatter")
        [[ -z "$title" ]] && continue

        local relative_path="${file#${VAULT_ROOT}/}"

        if [[ -n "${title_map[$title]+x}" ]]; then
            violation "HR-006" "$relative_path" "Duplicate title '${title}' — also found in ${title_map[$title]}"
            duplicates_found=true
        else
            title_map["$title"]="$relative_path"
        fi
    # SECURITY: -maxdepth prevents traversal DoS; ! -type l excludes symlinks
    done < <(find "${VAULT_ROOT}/${WIKI_DIR}" -maxdepth "${MAX_FIND_DEPTH}" ! -type l -name "*.md" -print0 2>/dev/null)

    success "HR-006: Title uniqueness check complete"
}
