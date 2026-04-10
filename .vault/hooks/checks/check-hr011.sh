#!/usr/bin/env bash
# ==============================================================================
# HR-011: Vault Configuration Protection
# ==============================================================================
# Rule: No agent may modify .vault/rules/, .vault/hooks/, or .vault/scripts/.
# Enforcement: Rejects agent commits that modify vault configuration directories.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr011() {
    info "HR-011: Checking vault configuration protection..."
    local staged_files
    staged_files=$(get_staged_files)

    local protected_dirs=(".vault/rules/" ".vault/hooks/" ".vault/scripts/")

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        for dir in "${protected_dirs[@]}"; do
            if [[ "$file" == "${dir}"* ]]; then
                violation "HR-011" "$file" "Vault configuration is protected. Submit a human-authored PR to modify ${dir}."
            fi
        done
    done <<< "$staged_files"

    if [[ $VIOLATIONS -eq 0 ]]; then
        success "HR-011: Vault configuration intact"
    fi
}
