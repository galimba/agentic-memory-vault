#!/usr/bin/env bash
# ==============================================================================
# HR-008: Index Registration
# ==============================================================================
# Rule: Every wiki/ file (except index.md and log.md) must appear in wiki/index.md.
# Enforcement: Rejects commits with unregistered wiki pages.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr008() {
    info "HR-008: Checking index registration..."
    local index_path="${VAULT_ROOT}/${INDEX_FILE}"

    if [[ ! -f "$index_path" ]]; then
        warn "HR-008: Index file not found at ${INDEX_FILE}. Skipping."
        return
    fi

    local index_content
    index_content=$(cat "$index_path")

    while IFS= read -r -d '' file; do
        local relative_path="${file#${VAULT_ROOT}/}"
        local ext
        ext=$(get_extension "$file")
        if ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        # Skip index.md and log.md themselves
        if [[ "$relative_path" == "${WIKI_DIR}/index.md" ]] || [[ "$relative_path" == "${WIKI_DIR}/log.md" ]]; then
            continue
        fi

        # Check if the file path or filename appears in index.md
        local basename
        basename=$(basename "$relative_path")
        # SECURITY: Use grep -F for literal string match — filenames may contain
        # regex metacharacters (., *, +, etc.) that grep would interpret as patterns.
        if ! echo "$index_content" | grep -qF "$basename" 2>/dev/null; then
            if ! echo "$index_content" | grep -qF "$relative_path" 2>/dev/null; then
                violation "HR-008" "$relative_path" "Not registered in ${INDEX_FILE}. Every wiki page must have an index entry."
            fi
        fi
    # SECURITY: -maxdepth prevents traversal DoS; ! -type l excludes symlinks
    done < <(find "${VAULT_ROOT}/${WIKI_DIR}" -maxdepth "${MAX_FIND_DEPTH}" ! -type l -name "*.md" -print0 2>/dev/null)

    success "HR-008: Index registration check complete"
}
