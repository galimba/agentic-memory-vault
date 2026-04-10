#!/usr/bin/env bash
# ==============================================================================
# AUDIT: Skill Hardening
# ==============================================================================
# Purpose: Audit skills against the skill hardening policy. Reads
#          .vault/schemas/skill-policy.json and scans all skill directories.
# Usage: vault-tools.sh skill-audit
# Dependencies: Requires lib-utils.sh to be sourced first.
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

cmd_skill_audit() {
    header "Skill Hardening Audit"

    local policy_file="${VAULT_CONFIG}/schemas/skill-policy.json"

    # Exit cleanly if no policy file exists
    if [[ ! -f "$policy_file" ]]; then
        ok "No skill policy found at ${policy_file#${VAULT_ROOT}/}. Skill hardening is not configured."
        echo ""
        return 0
    fi

    # Check if hardening is enabled
    local enabled
    enabled=$(python3 -c "import json; print(json.load(open('${policy_file}'))['enabled'])" 2>/dev/null || echo "False")
    if [[ "$enabled" != "True" ]]; then
        ok "Skill hardening is disabled in policy. Skipping audit."
        echo ""
        return 0
    fi

    # Read enforcement level
    local enforcement
    enforcement=$(python3 -c "import json; print(json.load(open('${policy_file}'))['enforcement'])" 2>/dev/null || echo "strict")
    subheader "Enforcement level: ${enforcement}"

    # Read level-specific settings via Python for reliable JSON parsing
    local level_json
    level_json=$(python3 -c "
import json, sys
with open('${policy_file}') as f:
    policy = json.load(f)
level = policy['levels'].get(policy['enforcement'], policy['levels']['strict'])
# Print settings one per line: key=value
for k, v in level.items():
    if isinstance(v, list):
        print(f'{k}=|{chr(10).join(str(i) for i in v)}|')
    else:
        print(f'{k}={v}')
" 2>/dev/null)

    # Parse level settings
    local require_manifest="True"
    local require_human_review="True"
    local allow_external_urls="False"
    local allow_shell_preprocessing="False"
    local allow_tool_escalation="False"
    local max_file_count=10
    local max_total_size_kb=500
    local blocked_patterns_raw=""

    while IFS= read -r setting_line; do
        local key="${setting_line%%=*}"
        local val="${setting_line#*=}"
        case "$key" in
            require_manifest) require_manifest="$val" ;;
            require_human_review) require_human_review="$val" ;;
            allow_external_urls) allow_external_urls="$val" ;;
            allow_shell_preprocessing) allow_shell_preprocessing="$val" ;;
            allow_tool_escalation) allow_tool_escalation="$val" ;;
            max_file_count) max_file_count="$val" ;;
            max_total_size_kb) max_total_size_kb="$val" ;;
            blocked_patterns) blocked_patterns_raw="${val}" ;;
        esac
    done <<< "$level_json"

    # Read URL lists
    local url_blocklist
    url_blocklist=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
for u in policy.get('url_blocklist', []):
    print(u)
" 2>/dev/null)

    local url_allowlist
    url_allowlist=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
for u in policy.get('url_allowlist', []):
    print(u)
" 2>/dev/null)

    # Read skill directories
    local skill_dirs
    skill_dirs=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
for d in policy.get('skill_directories', []):
    print(d)
" 2>/dev/null)

    # Read blocked patterns into an array
    local -a blocked_patterns=()
    if [[ -n "$blocked_patterns_raw" ]]; then
        local inner="${blocked_patterns_raw#|}"
        inner="${inner%|}"
        while IFS= read -r pat; do
            [[ -n "$pat" ]] && blocked_patterns+=("$pat")
        done <<< "$inner"
    fi

    local total_violations=0
    local total_warnings=0
    local skills_found=0

    # Scan each skill directory
    while IFS= read -r skill_dir_rel; do
        [[ -z "$skill_dir_rel" ]] && continue
        local skill_base="${VAULT_ROOT}/${skill_dir_rel}"

        if [[ ! -d "$skill_base" ]]; then
            ok "Skill directory ${skill_dir_rel}/ does not exist (nothing to audit)"
            continue
        fi

        subheader "Scanning ${skill_dir_rel}/"

        # Find skill subdirectories (each subdirectory is a skill)
        # Also check if the directory itself contains SKILL.md (flat layout)
        local -a skill_paths=()
        while IFS= read -r subdir; do
            [[ -z "$subdir" ]] && continue
            skill_paths+=("$subdir")
        done < <(find "$skill_base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

        # Check for flat layout (SKILL.md directly in skill_base)
        if [[ -f "${skill_base}/SKILL.md" ]]; then
            skill_paths+=("$skill_base")
        fi

        if [[ ${#skill_paths[@]} -eq 0 ]]; then
            ok "No skills found in ${skill_dir_rel}/"
            continue
        fi

        for skill_path in "${skill_paths[@]}"; do
            local skill_name
            skill_name=$(basename "$skill_path")
            local skill_rel="${skill_path#${VAULT_ROOT}/}"
            skills_found=$((skills_found + 1))

            subheader "Skill: ${skill_name} (${skill_rel})"

            # --- Check manifest ---
            local manifest_file="${skill_path}/skill-manifest.json"
            if [[ "$require_manifest" == "True" ]]; then
                if [[ ! -f "$manifest_file" ]]; then
                    error "Missing skill-manifest.json (required by ${enforcement} policy)"
                    total_violations=$((total_violations + 1))
                else
                    ok "Manifest present"

                    # Verify human review fields if required
                    if [[ "$require_human_review" == "True" ]]; then
                        local reviewed_by
                        reviewed_by=$(python3 -c "import json; print(json.load(open('${manifest_file}')).get('reviewed_by', ''))" 2>/dev/null)
                        local review_date
                        review_date=$(python3 -c "import json; print(json.load(open('${manifest_file}')).get('review_date', ''))" 2>/dev/null)
                        if [[ -z "$reviewed_by" ]] || [[ -z "$review_date" ]]; then
                            error "Manifest missing reviewed_by/review_date (required by ${enforcement} policy)"
                            total_violations=$((total_violations + 1))
                        else
                            ok "Human review recorded: ${reviewed_by} on ${review_date}"
                        fi
                    fi

                    # Verify SHA-256 hashes
                    local hash_failures=0
                    local manifest_file_count
                    manifest_file_count=$(python3 -c "import json; print(len(json.load(open('${manifest_file}')).get('files', [])))" 2>/dev/null || echo "0")

                    local manifest_entries
                    manifest_entries=$(python3 -c "
import json
with open('${manifest_file}') as f:
    manifest = json.load(f)
for entry in manifest.get('files', []):
    print(entry['path'] + '|' + entry['sha256'])
" 2>/dev/null)

                    while IFS='|' read -r entry_path entry_hash; do
                        [[ -z "$entry_path" ]] && continue
                        local full_entry="${skill_path}/${entry_path}"
                        if [[ ! -f "$full_entry" ]]; then
                            error "Manifest lists ${entry_path} but file not found"
                            hash_failures=$((hash_failures + 1))
                            continue
                        fi
                        local actual_hash
                        actual_hash=$(sha256sum "$full_entry" 2>/dev/null | awk '{print $1}')
                        if [[ "$actual_hash" != "$entry_hash" ]]; then
                            error "Hash mismatch: ${entry_path} (expected ${entry_hash:0:16}..., got ${actual_hash:0:16}...)"
                            hash_failures=$((hash_failures + 1))
                        fi
                    done <<< "$manifest_entries"

                    if [[ $hash_failures -gt 0 ]]; then
                        total_violations=$((total_violations + hash_failures))
                    else
                        ok "All file hashes verified (${manifest_file_count} files)"
                    fi

                    # Check for unmanifested files
                    while IFS= read -r disk_file; do
                        [[ -z "$disk_file" ]] && continue
                        local disk_rel="${disk_file#${skill_path}/}"
                        [[ "$disk_rel" == "skill-manifest.json" ]] && continue
                        if ! echo "$manifest_entries" | grep -q "^${disk_rel}|"; then
                            error "File ${disk_rel} exists on disk but not in manifest"
                            total_violations=$((total_violations + 1))
                        fi
                    done < <(find "$skill_path" -type f ! -name "skill-manifest.json" 2>/dev/null | sort)
                fi
            fi

            # --- Scan for blocked patterns ---
            local pattern_violations=0
            while IFS= read -r content_file; do
                [[ -z "$content_file" ]] && continue
                local content_rel="${content_file#${skill_path}/}"
                for pattern in "${blocked_patterns[@]}"; do
                    if grep -qF "$pattern" "$content_file" 2>/dev/null; then
                        error "Blocked pattern '${pattern}' found in ${content_rel}"
                        pattern_violations=$((pattern_violations + 1))
                    fi
                done
            done < <(find "$skill_path" -type f -name "*.md" 2>/dev/null | sort)
            if [[ $pattern_violations -gt 0 ]]; then
                total_violations=$((total_violations + pattern_violations))
            else
                ok "No blocked patterns detected"
            fi

            # --- Check for allowed-tools frontmatter (blocked in strict/moderate) ---
            if [[ "$allow_tool_escalation" == "False" ]]; then
                local tool_escalation_found=false
                while IFS= read -r md_file; do
                    [[ -z "$md_file" ]] && continue
                    if grep -qE '^allowed-tools:' "$md_file" 2>/dev/null; then
                        local md_rel="${md_file#${skill_path}/}"
                        error "Tool escalation via allowed-tools in ${md_rel}"
                        tool_escalation_found=true
                        total_violations=$((total_violations + 1))
                    fi
                done < <(find "$skill_path" -type f -name "*.md" 2>/dev/null)
                if ! $tool_escalation_found; then
                    ok "No tool escalation detected"
                fi
            fi

            # --- Check for !command preprocessing (blocked in strict/moderate) ---
            if [[ "$allow_shell_preprocessing" == "False" ]]; then
                local preprocessing_found=false
                while IFS= read -r md_file; do
                    [[ -z "$md_file" ]] && continue
                    if grep -qE '^!' "$md_file" 2>/dev/null; then
                        local md_rel="${md_file#${skill_path}/}"
                        error "Shell preprocessing syntax found in ${md_rel}"
                        preprocessing_found=true
                        total_violations=$((total_violations + 1))
                    fi
                done < <(find "$skill_path" -type f -name "*.md" 2>/dev/null)
                if ! $preprocessing_found; then
                    ok "No shell preprocessing detected"
                fi
            fi

            # --- Scan for external URLs ---
            if [[ "$allow_external_urls" == "False" ]]; then
                local url_violations=0
                while IFS= read -r content_file; do
                    [[ -z "$content_file" ]] && continue
                    local content_rel="${content_file#${skill_path}/}"
                    local urls_in_file
                    urls_in_file=$(grep -oE 'https?://[a-zA-Z0-9./?=_%&:@#~-]+' "$content_file" 2>/dev/null || true)
                    while IFS= read -r url; do
                        [[ -z "$url" ]] && continue
                        # Check if URL domain is in allowlist
                        local domain
                        # shellcheck disable=SC2001
                        domain=$(echo "$url" | sed 's|https\?://\([^/]*\).*|\1|')
                        local allowed=false
                        while IFS= read -r allow_domain; do
                            [[ -z "$allow_domain" ]] && continue
                            if [[ "$domain" == *"$allow_domain"* ]]; then
                                allowed=true
                                break
                            fi
                        done <<< "$url_allowlist"
                        if ! $allowed; then
                            error "External URL blocked: ${url} in ${content_rel}"
                            url_violations=$((url_violations + 1))
                        fi
                    done <<< "$urls_in_file"
                done < <(find "$skill_path" -type f 2>/dev/null | sort)
                if [[ $url_violations -gt 0 ]]; then
                    total_violations=$((total_violations + url_violations))
                else
                    ok "No blocked external URLs"
                fi
            else
                # Even in permissive mode, check URL blocklist
                local blocklist_violations=0
                while IFS= read -r content_file; do
                    [[ -z "$content_file" ]] && continue
                    local content_rel="${content_file#${skill_path}/}"
                    while IFS= read -r blocked_domain; do
                        [[ -z "$blocked_domain" ]] && continue
                        if grep -qF "$blocked_domain" "$content_file" 2>/dev/null; then
                            error "Blocklisted domain '${blocked_domain}' found in ${content_rel}"
                            blocklist_violations=$((blocklist_violations + 1))
                        fi
                    done <<< "$url_blocklist"
                done < <(find "$skill_path" -type f 2>/dev/null | sort)
                if [[ $blocklist_violations -gt 0 ]]; then
                    total_violations=$((total_violations + blocklist_violations))
                else
                    ok "No blocklisted URLs"
                fi
            fi

            # --- Check file count and total size ---
            local file_count=0
            local total_size=0
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                file_count=$((file_count + 1))
                local fsize
                fsize=$(stat --printf="%s" "$f" 2>/dev/null || stat -f "%z" "$f" 2>/dev/null || echo "0")
                total_size=$((total_size + fsize))
            done < <(find "$skill_path" -type f 2>/dev/null)
            local total_size_kb=$((total_size / 1024))

            if [[ $file_count -gt $max_file_count ]]; then
                error "File count ${file_count} exceeds limit of ${max_file_count}"
                total_violations=$((total_violations + 1))
            else
                ok "File count: ${file_count}/${max_file_count}"
            fi

            if [[ $total_size_kb -gt $max_total_size_kb ]]; then
                error "Total size ${total_size_kb} KB exceeds limit of ${max_total_size_kb} KB"
                total_violations=$((total_violations + 1))
            else
                ok "Total size: ${total_size_kb} KB / ${max_total_size_kb} KB"
            fi

            # --- Check for executable files ---
            local exec_warnings=0
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                local f_rel="${f#${skill_path}/}"
                local f_ext
                f_ext=$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]')
                case "$f_ext" in
                    sh|py|rb|pl|js|ts|bash|zsh)
                        warning "Executable file type detected: ${f_rel}"
                        exec_warnings=$((exec_warnings + 1))
                        total_warnings=$((total_warnings + 1))
                        ;;
                esac
                if [[ -x "$f" ]]; then
                    warning "File has execute permission: ${f_rel}"
                    exec_warnings=$((exec_warnings + 1))
                    total_warnings=$((total_warnings + 1))
                fi
            done < <(find "$skill_path" -type f 2>/dev/null)
            if [[ $exec_warnings -eq 0 ]]; then
                ok "No executable files detected"
            fi

        done
    done <<< "$skill_dirs"

    # Summary
    header "Skill Audit Summary"
    echo "  Enforcement level:   ${enforcement}"
    echo "  Skills scanned:      ${skills_found}"
    echo "  Violations (blocking): ${total_violations}"
    echo "  Warnings (advisory):   ${total_warnings}"
    echo ""

    if [[ $total_violations -gt 0 ]]; then
        error "Skill audit failed with ${total_violations} violation(s)"
        return 1
    else
        ok "Skill audit passed"
        return 0
    fi
}
