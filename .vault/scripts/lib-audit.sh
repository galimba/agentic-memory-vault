#!/usr/bin/env bash
# ==============================================================================
# LIB-AUDIT — Audit commands for vault-tools
# ==============================================================================
#
# Contains commands for policy and taxonomy auditing:
#   cmd_tag_audit()      — Tag taxonomy audit (usage vs approved tags)
#   cmd_skill_audit()    — Skill hardening policy audit
#   cmd_content_audit()  — Content integrity audit
#
# This file is sourced by vault-tools.sh and depends on functions and
# variables from lib-utils.sh and the entry point configuration.
#
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

# ==============================================================================
# COMMAND: tag-audit
# ==============================================================================
# Audit tag usage: find unapproved tags, unused approved tags, and distribution.

cmd_tag_audit() {
    header "Tag Audit"

    # Get approved tags
    subheader "Loading approved tags from ${TAGS_FILE}"
    local approved_tags_file
    approved_tags_file=$(mktemp)
    if [[ -f "${TAGS_FILE}" ]]; then
        grep -oE '`[a-z][a-z0-9-]*/[a-z][a-z0-9-]*`' "${TAGS_FILE}" | sed 's/`//g' | sort -u > "$approved_tags_file"
        local approved_count
        approved_count=$(wc -l < "$approved_tags_file" | tr -d ' ')
        ok "Loaded ${approved_count} approved tags"
    else
        error "Tags file not found"
        rm -f "$approved_tags_file"
        return 1
    fi

    # Collect all used tags
    subheader "Scanning vault for used tags"
    local used_tags_file
    used_tags_file=$(mktemp)
    while IFS= read -r file; do
        local fm
        fm=$(extract_fm "$file")
        [[ -z "$fm" ]] && continue
        fm_tags "$fm"
    done < <(wiki_files) | sort -u > "$used_tags_file"

    local used_count
    used_count=$(wc -l < "$used_tags_file" | tr -d ' ')
    ok "Found ${used_count} unique tags in use"

    # Find unapproved tags (used but not in taxonomy)
    subheader "Unapproved tags (used but not in taxonomy)"
    local unapproved_file
    unapproved_file=$(mktemp)
    comm -23 "$used_tags_file" "$approved_tags_file" > "$unapproved_file"
    local unapproved_count
    unapproved_count=$(wc -l < "$unapproved_file" | tr -d ' ')
    if [[ $unapproved_count -gt 0 ]]; then
        while IFS= read -r tag; do
            [[ -z "$tag" ]] && continue
            error "Unapproved tag: ${tag}"
        done < "$unapproved_file"
    else
        ok "All used tags are approved"
    fi

    # Find unused approved tags
    subheader "Unused approved tags (in taxonomy but never used)"
    local unused_file
    unused_file=$(mktemp)
    comm -23 "$approved_tags_file" "$used_tags_file" > "$unused_file"
    local unused_count
    unused_count=$(wc -l < "$unused_file" | tr -d ' ')
    echo "  ${unused_count} approved tags are unused (this is normal for a new vault)"

    # Cleanup
    rm -f "$approved_tags_file" "$used_tags_file" "$unapproved_file" "$unused_file"
    echo ""
}

# ==============================================================================
# COMMAND: skill-audit
# ==============================================================================
# Audit skills against the skill hardening policy.
# Reads .vault/schemas/skill-policy.json and scans all skill directories.
# Returns non-zero if policy violations are found.

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

# ==============================================================================
# COMMAND: content-audit
# ==============================================================================
# Audit staged or tracked content against the content hardening policy.
# Reads .vault/schemas/content-policy.json and checks for injection,
# bulk deletions, confidence downgrades, and mass status changes.

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
