#!/usr/bin/env bash
# ==============================================================================
# HR-005: Code File Length Limit
# ==============================================================================
# Rule: Code files in .vault/ and .claude/ warn at 400 lines, block at 600 lines.
# Enforcement: Rejects commits with code files exceeding the hard limit.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr005() {
    info "HR-005: Checking code file length limits (warn ${WARN_CODE_LINES}, max ${MAX_CODE_LINES} lines)..."
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")

        # Check code files in .vault/ and .claude/
        if [[ "$file" != "${VAULT_CONFIG_DIR}/"* ]] && [[ "$file" != ".claude/"* ]]; then
            continue
        fi

        # Skip config files
        if extension_in_list "$ext" "${CONFIG_EXTENSIONS[@]}"; then
            continue
        fi

        # Skip non-code files
        if ! extension_in_list "$ext" "${CODE_EXTENSIONS[@]}"; then
            continue
        fi

        # Check exemptions
        if is_exempt "$file"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local line_count
        line_count=$(count_lines "$full_path")
        if [[ $line_count -gt $MAX_CODE_LINES ]]; then
            violation "HR-005" "$file" "Exceeds ${MAX_CODE_LINES} line limit (has ${line_count} lines). Split into modular files with clear responsibilities."
        elif [[ $line_count -gt $WARN_CODE_LINES ]]; then
            warn "HR-005: ${file} has ${line_count} lines (recommended max: ${WARN_CODE_LINES}). Consider modularizing."
        fi
    done <<< "$staged_files"

    success "HR-005: Code length check complete"
}
