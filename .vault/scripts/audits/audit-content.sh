#!/usr/bin/env bash
# ==============================================================================
# AUDIT: Content Integrity
# ==============================================================================
# Purpose: Audit staged or tracked content against the content hardening policy.
#          Checks for injection, bulk deletions, confidence downgrades, and
#          mass status changes.
# Usage: vault-tools.sh content-audit
# Dependencies: Requires lib-utils.sh to be sourced first.
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

cmd_content_audit() {
    header "Content Integrity Audit"

    local policy_file="${VAULT_CONFIG}/schemas/content-policy.json"

    # Exit cleanly if no policy file exists
    if [[ ! -f "$policy_file" ]]; then
        ok "No content policy found at ${policy_file#${VAULT_ROOT}/}. Content hardening is not configured."
        echo ""
        return 0
    fi

    # Check if hardening is enabled
    local enabled
    enabled=$(python3 -c "import json; print(json.load(open('${policy_file}'))['enabled'])" 2>/dev/null || echo "False")
    if [[ "$enabled" != "True" ]]; then
        ok "Content hardening is disabled in policy. Skipping audit."
        echo ""
        return 0
    fi

    # Read policy settings
    local policy_json
    policy_json=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
checks = policy.get('checks', {})
for k, v in checks.items():
    print(f'{k}={v}')
print('---')
for p in policy.get('instruction_patterns', []):
    print(p)
" 2>/dev/null)

    # Parse check settings
    local detect_injection="True"
    local max_deletion_pct=20
    local flag_confidence="True"
    local flag_mass_status="True"
    local max_files_per_commit=25

    local in_patterns=false
    local -a injection_patterns=()

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            in_patterns=true
            continue
        fi
        if $in_patterns; then
            [[ -n "$line" ]] && injection_patterns+=("$line")
        else
            local key="${line%%=*}"
            local val="${line#*=}"
            case "$key" in
                detect_instruction_injection) detect_injection="$val" ;;
                max_deletion_percentage) max_deletion_pct="$val" ;;
                flag_confidence_downgrades) flag_confidence="$val" ;;
                flag_mass_status_changes) flag_mass_status="$val" ;;
                max_files_per_commit) max_files_per_commit="$val" ;;
            esac
        fi
    done <<< "$policy_json"

    local total_violations=0
    local total_warnings=0

    # Get staged markdown files (or all tracked markdown files if not in git context)
    local md_files
    md_files=$(git -C "${VAULT_ROOT}" diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.md$' || true)
    if [[ -z "$md_files" ]]; then
        # If no staged files, scan all tracked markdown files in wiki/ and memory/
        md_files=$(git -C "${VAULT_ROOT}" ls-files '*.md' 2>/dev/null | grep -E '^(wiki/|memory/)' || true)
    fi

    # --- Check: max_files_per_commit ---
    subheader "File count check"
    local staged_count
    staged_count=$(git -C "${VAULT_ROOT}" diff --cached --name-only --diff-filter=ACMR 2>/dev/null | wc -l | tr -d ' ')
    if [[ $staged_count -gt $max_files_per_commit ]]; then
        error "Staged file count (${staged_count}) exceeds limit of ${max_files_per_commit}"
        total_violations=$((total_violations + 1))
    else
        ok "Staged files: ${staged_count}/${max_files_per_commit}"
    fi

    # --- Check: detect_instruction_injection ---
    if [[ "$detect_injection" == "True" ]]; then
        subheader "Instruction injection scan"
        local injection_count=0
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local full_path="${VAULT_ROOT}/${file}"
            [[ ! -f "$full_path" ]] && continue
            for pattern in "${injection_patterns[@]}"; do
                if grep -qiF "$pattern" "$full_path" 2>/dev/null; then
                    error "${file}: injection pattern detected — '${pattern}'"
                    injection_count=$((injection_count + 1))
                fi
            done
        done <<< "$md_files"
        if [[ $injection_count -gt 0 ]]; then
            total_violations=$((total_violations + injection_count))
        else
            ok "No instruction injection patterns found"
        fi
    fi

    # --- Check: max_deletion_percentage ---
    subheader "Deletion percentage check"
    local deletion_warnings=0
    local staged_modified
    staged_modified=$(git -C "${VAULT_ROOT}" diff --cached --name-only --diff-filter=M 2>/dev/null | grep -E '\.md$' || true)
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        # Get previous version word count
        local prev_words
        prev_words=$(git -C "${VAULT_ROOT}" show "HEAD:${file}" 2>/dev/null | wc -w | tr -d ' ')
        [[ "$prev_words" == "0" ]] && continue

        local curr_words
        curr_words=$(wc -w < "$full_path" 2>/dev/null | tr -d ' ')

        if [[ $curr_words -lt $prev_words ]]; then
            local deleted=$((prev_words - curr_words))
            local pct=$((deleted * 100 / prev_words))
            if [[ $pct -gt $max_deletion_pct ]]; then
                error "${file}: ${pct}% content deleted (${deleted}/${prev_words} words, limit ${max_deletion_pct}%)"
                deletion_warnings=$((deletion_warnings + 1))
            fi
        fi
    done <<< "$staged_modified"
    if [[ $deletion_warnings -gt 0 ]]; then
        total_violations=$((total_violations + deletion_warnings))
    else
        ok "No excessive deletions detected"
    fi

    # --- Check: flag_confidence_downgrades ---
    if [[ "$flag_confidence" == "True" ]]; then
        subheader "Confidence downgrade check"
        local confidence_warnings=0
        local confidence_order="high medium low unverified"
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local full_path="${VAULT_ROOT}/${file}"
            [[ ! -f "$full_path" ]] && continue

            local prev_fm
            prev_fm=$(git -C "${VAULT_ROOT}" show "HEAD:${file}" 2>/dev/null | awk '/^---$/{if(++n==2)exit; next} n==1{print}')
            [[ -z "$prev_fm" ]] && continue

            local curr_fm
            curr_fm=$(extract_fm "$full_path")
            [[ -z "$curr_fm" ]] && continue

            local prev_conf
            prev_conf=$(echo "$prev_fm" | grep -E '^confidence:' | head -1 | sed 's/^confidence:[[:space:]]*//')
            local curr_conf
            curr_conf=$(fm_field "confidence" "$curr_fm")

            if [[ -n "$prev_conf" ]] && [[ -n "$curr_conf" ]] && [[ "$prev_conf" != "$curr_conf" ]]; then
                # Check if it's a downgrade (higher index = lower confidence)
                local prev_idx=0 curr_idx=0 idx=0
                for level in $confidence_order; do
                    if [[ "$level" == "$prev_conf" ]]; then prev_idx=$idx; fi
                    if [[ "$level" == "$curr_conf" ]]; then curr_idx=$idx; fi
                    idx=$((idx + 1))
                done
                if [[ $curr_idx -gt $prev_idx ]]; then
                    warning "${file}: confidence downgraded from '${prev_conf}' to '${curr_conf}'"
                    confidence_warnings=$((confidence_warnings + 1))
                    total_warnings=$((total_warnings + 1))
                fi
            fi
        done <<< "$staged_modified"
        if [[ $confidence_warnings -eq 0 ]]; then
            ok "No confidence downgrades detected"
        fi
    fi

    # --- Check: flag_mass_status_changes ---
    if [[ "$flag_mass_status" == "True" ]]; then
        subheader "Mass status change check"
        local status_changes=0
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local full_path="${VAULT_ROOT}/${file}"
            [[ ! -f "$full_path" ]] && continue

            local prev_fm
            prev_fm=$(git -C "${VAULT_ROOT}" show "HEAD:${file}" 2>/dev/null | awk '/^---$/{if(++n==2)exit; next} n==1{print}')
            [[ -z "$prev_fm" ]] && continue

            local curr_fm
            curr_fm=$(extract_fm "$full_path")
            [[ -z "$curr_fm" ]] && continue

            local prev_status
            prev_status=$(echo "$prev_fm" | grep -E '^status:' | head -1 | sed 's/^status:[[:space:]]*//')
            local curr_status
            curr_status=$(fm_field "status" "$curr_fm")

            if [[ -n "$prev_status" ]] && [[ -n "$curr_status" ]] && [[ "$prev_status" != "$curr_status" ]]; then
                status_changes=$((status_changes + 1))
            fi
        done <<< "$staged_modified"
        # Flag if 5+ status changes in a single commit
        if [[ $status_changes -ge 5 ]]; then
            warning "Mass status change detected: ${status_changes} files changed status in one commit"
            total_warnings=$((total_warnings + 1))
        else
            ok "Status changes within normal range (${status_changes} files)"
        fi
    fi

    # Summary
    header "Content Audit Summary"
    echo "  Violations (blocking): ${total_violations}"
    echo "  Warnings (advisory):   ${total_warnings}"
    echo ""

    if [[ $total_violations -gt 0 ]]; then
        error "Content audit failed with ${total_violations} violation(s)"
        return 1
    else
        ok "Content audit passed"
        return 0
    fi
}
