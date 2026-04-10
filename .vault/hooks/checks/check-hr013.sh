#!/usr/bin/env bash
# ==============================================================================
# HR-013: CI and Template Protection
# ==============================================================================
# Rule: No agent may modify .github/ or templates/.
# Enforcement: Rejects agent commits that modify CI workflows or templates.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr013() {
    info "HR-013: Checking CI and template protection..."
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if [[ "$file" == ".github/"* ]] || [[ "$file" == "templates/"* ]]; then
            violation "HR-013" "$file" "CI workflows and templates are protected. Submit a human-authored PR to modify."
        fi
    done <<< "$staged_files"

    if [[ $VIOLATIONS -eq 0 ]]; then
        success "HR-013: CI and templates intact"
    fi
}
