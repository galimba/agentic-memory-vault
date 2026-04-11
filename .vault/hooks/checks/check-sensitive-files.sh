#!/usr/bin/env bash
# ==============================================================================
# ADVISORY: Sensitive File Modification Warnings + Content Policy
# ==============================================================================
# This file hosts two non-HR pre-commit checks:
#
#   check_sensitive_files  — Path-prefix advisory warnings when governance
#                             files are touched. Non-blocking.
#
#   check_content_policy   — Injection pattern scanning driven by
#                             .vault/schemas/content-policy.json.
#                             Enforcement level is configurable:
#                               "warn"  — prints a warning, commit proceeds
#                               "block" — records a violation, commit fails
#                             Set CONTENT_POLICY_DISABLED=1 to bypass.
#
# Both checks are called from .vault/hooks/pre-commit.sh main().
# ==============================================================================

SENSITIVE_WARNINGS=0
CONTENT_POLICY_WARNINGS=0

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

# ==============================================================================
# CONTENT POLICY — Instruction Injection Detection
# ==============================================================================
# Scans staged markdown files for instruction-injection patterns defined in
# .vault/schemas/content-policy.json. Enforcement level ("warn" vs "block")
# is read from the same file. This is a minimal subset of the CLI audit at
# .vault/scripts/audits/audit-content.sh — the full audit is still available
# via `vault-tools.sh content-audit`.
check_content_policy() {
    local policy_file="${VAULT_ROOT}/${VAULT_CONFIG_DIR}/schemas/content-policy.json"
    [[ ! -f "$policy_file" ]] && return

    # Explicit bypass for legitimate bulk operations
    if [[ "${CONTENT_POLICY_DISABLED:-0}" == "1" ]]; then
        warn "CONTENT-POLICY: CONTENT_POLICY_DISABLED=1 — scan bypassed"
        return
    fi

    # Read enabled + enforcement fields. Prefer python3 for robustness; fall
    # back to grep/sed for the flat JSON shape so the hook still runs on a
    # minimal machine.
    local enabled="false"
    local enforcement="warn"
    if command -v python3 &>/dev/null; then
        enabled=$(python3 -c "import json; print(str(json.load(open('${policy_file}')).get('enabled', False)).lower())" 2>/dev/null || echo "false")
        enforcement=$(python3 -c "import json; print(json.load(open('${policy_file}')).get('enforcement', 'warn'))" 2>/dev/null || echo "warn")
    else
        if grep -qE '"enabled"[[:space:]]*:[[:space:]]*true' "$policy_file"; then
            enabled="true"
        fi
        local enf
        enf=$(grep -oE '"enforcement"[[:space:]]*:[[:space:]]*"[a-z]+"' "$policy_file" | grep -oE '"[a-z]+"$' | tr -d '"')
        [[ -n "$enf" ]] && enforcement="$enf"
    fi

    [[ "$enabled" != "true" ]] && return

    info "CONTENT-POLICY: Scanning for instruction-injection patterns (${enforcement})..."

    # Extract instruction_patterns list from the policy
    local patterns_raw=""
    if command -v python3 &>/dev/null; then
        patterns_raw=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
for p in policy.get('instruction_patterns', []):
    print(p)
" 2>/dev/null)
    else
        # Flat-JSON fallback: lines inside the instruction_patterns array
        patterns_raw=$(awk '
            /"instruction_patterns"/{flag=1; next}
            flag && /\]/{flag=0}
            flag
        ' "$policy_file" | grep -oE '"[^"]+"' | sed 's/^"//;s/"$//')
    fi

    if [[ -z "$patterns_raw" ]]; then
        success "CONTENT-POLICY: No patterns defined — scan skipped"
        return
    fi

    local staged_files
    staged_files=$(get_staged_files)

    local match_count=0
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        # Only scan markdown content destined for wiki/ or memory/
        if [[ "$file" != wiki/* ]] && [[ "$file" != memory/* ]]; then
            continue
        fi
        [[ "$file" != *.md ]] && continue

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            if grep -qiF "$pattern" "$full_path" 2>/dev/null; then
                match_count=$((match_count + 1))
                if [[ "$enforcement" == "block" ]]; then
                    violation "CONTENT-POLICY" "$file" \
                        "Instruction injection pattern detected: '${pattern}' (enforcement=block)"
                else
                    warn "CONTENT-POLICY: ${file} contains pattern '${pattern}' — review before merging"
                    CONTENT_POLICY_WARNINGS=$((CONTENT_POLICY_WARNINGS + 1))
                fi
            fi
        done <<< "$patterns_raw"
    done <<< "$staged_files"

    if [[ $match_count -eq 0 ]]; then
        success "CONTENT-POLICY: No injection patterns detected"
    elif [[ "$enforcement" == "warn" ]]; then
        echo ""
        warn "================================================"
        warn "  ${match_count} content-policy warning(s) in this commit."
        warn "  Review the flagged files before merging."
        warn "  Set enforcement=block in content-policy.json to"
        warn "  reject such commits automatically."
        warn "================================================"
        echo ""
    fi
}
