#!/usr/bin/env bash
# ==============================================================================
# HR-004: Markdown Length Limit
# ==============================================================================
# Rule: Markdown files in wiki/ or memory/ warn at 200 lines, block at 400 lines.
# Enforcement: Rejects commits with markdown files exceeding the hard limit.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr004() {
    info "HR-004: Checking markdown length limits (warn ${WARN_MARKDOWN_LINES}, max ${MAX_MARKDOWN_LINES} lines)..."
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")

        if [[ "$file" != "${WIKI_DIR}/"* ]] && [[ "$file" != "${MEMORY_DIR}/"* ]]; then
            continue
        fi
        if ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi
        if is_exempt "$file"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local line_count
        line_count=$(count_lines "$full_path")
        if [[ $line_count -gt $MAX_MARKDOWN_LINES ]]; then
            violation "HR-004" "$file" "Exceeds ${MAX_MARKDOWN_LINES} line hard limit (has ${line_count} lines). Split into linked sub-pages."
        elif [[ $line_count -gt $WARN_MARKDOWN_LINES ]]; then
            warn "HR-004: ${file} has ${line_count} lines (recommended max: ${WARN_MARKDOWN_LINES}). Consider splitting."
        fi
    done <<< "$staged_files"

    success "HR-004: Markdown length check complete"
}
