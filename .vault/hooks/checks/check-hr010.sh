#!/usr/bin/env bash
# ==============================================================================
# HR-010: Binary File Quarantine
# ==============================================================================
# Rule: Binary files may only exist in raw/. No binaries in wiki/ or memory/.
# Enforcement: Rejects commits with binary files outside raw/.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr010() {
    info "HR-010: Checking binary file quarantine..."
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Only check wiki/ and memory/ directories
        if [[ "$file" != "${WIKI_DIR}/"* ]] && [[ "$file" != "${MEMORY_DIR}/"* ]]; then
            continue
        fi

        local ext
        ext=$(get_extension "$file")

        # Allow markdown and json
        if extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi
        if [[ "$ext" == "json" ]]; then
            continue
        fi

        # Check if gitkeep
        if [[ "$(basename "$file")" == ".gitkeep" ]]; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        if [[ -f "$full_path" ]] && is_binary "$full_path"; then
            violation "HR-010" "$file" "Binary file detected outside raw/. Move to raw/ and reference via wikilink."
        fi
    done <<< "$staged_files"

    success "HR-010: Binary quarantine check complete"
}
