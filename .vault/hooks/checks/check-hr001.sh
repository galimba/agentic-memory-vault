#!/usr/bin/env bash
# ==============================================================================
# HR-001: Raw Directory Immutability
# ==============================================================================
# Rule: No agent may modify files in raw/. Requires CODEOWNERS approval via PR.
# Enforcement: Rejects any commit that modifies or deletes files in raw/.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr001() {
    info "HR-001: Checking raw/ directory immutability..."

    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if [[ "$file" == "${RAW_DIR}/"* ]]; then
            violation "HR-001" "$file" "Raw directory is immutable. Use a PR with CODEOWNERS approval to modify raw/."
        fi
    done <<< "$staged_files"

    # Also check deleted files
    local deleted_files
    deleted_files=$(git diff --cached --name-only --diff-filter=D 2>/dev/null || true)
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if [[ "$file" == "${RAW_DIR}/"* ]]; then
            violation "HR-001" "$file" "Cannot delete files from raw/. Raw directory is immutable."
        fi
    done <<< "$deleted_files"

    if [[ $VIOLATIONS -eq 0 ]]; then
        success "HR-001: Raw directory intact"
    fi
}
