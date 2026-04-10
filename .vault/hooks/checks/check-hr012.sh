#!/usr/bin/env bash
# ==============================================================================
# HR-012: Agent Configuration Protection
# ==============================================================================
# Rule: No agent may modify CLAUDE.md, AGENTS.md, or CODEX.md.
# Enforcement: Rejects agent commits that modify agent configuration files.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr012() {
    info "HR-012: Checking agent configuration protection..."
    local staged_files
    staged_files=$(get_staged_files)
    local protected_files=("CLAUDE.md" "AGENTS.md" "CODEX.md")

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        for pf in "${protected_files[@]}"; do
            if [[ "$file" == "$pf" ]]; then
                violation "HR-012" "$file" "Agent configuration files are protected. Submit a human-authored PR to modify."
            fi
        done
    done <<< "$staged_files"

    if [[ $VIOLATIONS -eq 0 ]]; then
        success "HR-012: Agent configuration intact"
    fi
}
