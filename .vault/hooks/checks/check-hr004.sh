#!/usr/bin/env bash
# ==============================================================================
# HR-004: Markdown Length Limit
# ==============================================================================
# Rule: Markdown files in wiki/ or memory/ warn at 200 lines, block at 400 lines.
# Index files (wiki/index.md and wiki/index-*.md sub-indexes) are exempt from
# the generic limits but have their own budget: warn above 250 lines, block
# above 400 (issue #9). Fix an oversized root index with
# `vault-tools.sh index-split`; a full sub-index is curated down instead.
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

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local line_count
        # Index files get their own thresholds instead of the generic ones.
        if [[ "$file" == "${WIKI_DIR}/index.md" ]] || [[ "$file" == "${WIKI_DIR}/index-"*.md ]]; then
            line_count=$(count_lines "$full_path")
            # index-split only partitions the root index; a sub-index is already
            # split, so its remedy is curating or archiving entries instead.
            local index_hint
            if [[ "$file" == "${WIKI_DIR}/index.md" ]]; then
                index_hint="Run: bash .vault/scripts/vault-tools.sh index-split"
            else
                index_hint="This sub-index is already split — curate or archive its entries to shrink it"
            fi
            if [[ $line_count -gt $MAX_INDEX_LINES ]]; then
                violation "HR-004" "$file" "Index file exceeds ${MAX_INDEX_LINES} line hard limit (has ${line_count} lines). ${index_hint}"
            elif [[ $line_count -gt $WARN_INDEX_LINES ]]; then
                warn "HR-004: ${file} has ${line_count} lines (index warning threshold: ${WARN_INDEX_LINES}). ${index_hint}"
            fi
            continue
        fi

        if is_exempt "$file"; then
            continue
        fi

        line_count=$(count_lines "$full_path")
        if [[ $line_count -gt $MAX_MARKDOWN_LINES ]]; then
            violation "HR-004" "$file" "Exceeds ${MAX_MARKDOWN_LINES} line hard limit (has ${line_count} lines). Split into linked sub-pages."
        elif [[ $line_count -gt $WARN_MARKDOWN_LINES ]]; then
            warn "HR-004: ${file} has ${line_count} lines (recommended max: ${WARN_MARKDOWN_LINES}). Consider splitting."
        fi
    done <<< "$staged_files"

    success "HR-004: Markdown length check complete"
}
