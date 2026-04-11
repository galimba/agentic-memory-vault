#!/usr/bin/env bash
# ==============================================================================
# HR-015: Append-Only Logs
# ==============================================================================
# Rule: wiki/log.md and files under memory/logs/ may only be appended to.
#       Commits that delete or modify existing lines in these files are
#       rejected. Pure additions are allowed.
# Enforcement: Inspects `git diff --cached --numstat` for non-zero deletion
#              counts on protected log paths.
# Bypass: Set LOG_EDIT_ALLOWED=1 to permit legitimate corrections. Document
#         the reason in the commit message.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

check_hr015() {
    info "HR-015: Checking append-only log integrity..."

    if [[ "${LOG_EDIT_ALLOWED:-0}" == "1" ]]; then
        warn "HR-015: LOG_EDIT_ALLOWED=1 — append-only check bypassed"
        return
    fi

    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Only protect the canonical log file and memory session logs.
        local protected=false
        if [[ "$file" == "wiki/log.md" ]]; then
            protected=true
        elif [[ "$file" == memory/logs/*.md ]]; then
            protected=true
        fi
        $protected || continue

        # numstat format: "<added>\t<deleted>\t<path>"
        local numstat
        numstat=$(git diff --cached --numstat -- "$file" 2>/dev/null || echo "")
        [[ -z "$numstat" ]] && continue

        local deletions
        deletions=$(echo "$numstat" | awk '{print $2}')
        [[ -z "$deletions" ]] && continue
        # Binary files report "-" — treat as non-numeric and skip
        [[ "$deletions" == "-" ]] && continue

        if [[ "$deletions" -gt 0 ]]; then
            violation "HR-015" "$file" \
                "Log files are append-only. ${deletions} line(s) deleted. Set LOG_EDIT_ALLOWED=1 to bypass for legitimate corrections."
        fi
    done <<< "$staged_files"

    if [[ $VIOLATIONS -eq 0 ]]; then
        success "HR-015: Append-only log integrity verified"
    fi
}
