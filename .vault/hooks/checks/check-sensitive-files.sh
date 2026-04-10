#!/usr/bin/env bash
# ==============================================================================
# ADVISORY: Sensitive File Modification Warnings
# ==============================================================================
# Rule: Emit warnings (non-blocking) when governance-critical files are modified.
# Enforcement: Advisory only — does not block commits, surfaces changes for review.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

SENSITIVE_WARNINGS=0

check_sensitive_files() {
    info "ADVISORY: Checking for sensitive file modifications..."
    local staged_files
    staged_files=$(get_staged_files)

    # Also include deleted files in sensitivity check
    local deleted_files
    deleted_files=$(git diff --cached --name-only --diff-filter=D 2>/dev/null || true)
    local all_changed_files
    all_changed_files=$(printf '%s\n%s' "$staged_files" "$deleted_files" | sort -u)

    # Define sensitive path patterns and their risk descriptions
    local sensitive_patterns=(
        ".vault/hooks/|VAULT HOOKS — controls all pre-commit enforcement"
        ".vault/rules/|VAULT RULES — defines what is enforced"
        ".vault/scripts/|VAULT SCRIPTS — operational tooling"
        ".vault/schemas/|VAULT SCHEMAS — validation definitions"
        ".github/|CI/CD PIPELINES — controls automated checks"
        ".claude/|CLAUDE CODE SETTINGS — agent permission configuration"
        "templates/|CONTENT TEMPLATES — injected into all future pages"
    )

    # Exact-match sensitive files
    local sensitive_files=(
        "CLAUDE.md|AGENT CONFIG — primary agent instruction file"
        "AGENTS.md|AGENT CONFIG — platform-agnostic agent instructions"
        "CODEX.md|AGENT CONFIG — Codex-specific agent instructions"
    )

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Check path-prefix patterns
        for pattern_desc in "${sensitive_patterns[@]}"; do
            local pattern="${pattern_desc%%|*}"
            local desc="${pattern_desc##*|}"
            if [[ "$file" == "$pattern"* ]]; then
                warn "SENSITIVE FILE MODIFIED: ${file} — ${desc}"
                SENSITIVE_WARNINGS=$((SENSITIVE_WARNINGS + 1))
                break
            fi
        done

        # Check exact-match files
        for file_desc in "${sensitive_files[@]}"; do
            local sensitive_name="${file_desc%%|*}"
            local desc="${file_desc##*|}"
            if [[ "$file" == "$sensitive_name" ]]; then
                warn "SENSITIVE FILE MODIFIED: ${file} — ${desc}"
                SENSITIVE_WARNINGS=$((SENSITIVE_WARNINGS + 1))
            fi
        done
    done <<< "$all_changed_files"

    if [[ $SENSITIVE_WARNINGS -gt 0 ]]; then
        echo ""
        warn "================================================"
        warn "  ${SENSITIVE_WARNINGS} sensitive file(s) modified in this commit."
        warn "  If this is an agent-authored commit, a human"
        warn "  reviewer MUST verify these changes before merge."
        warn "================================================"
        echo ""
    else
        success "ADVISORY: No sensitive file modifications detected"
    fi
}
