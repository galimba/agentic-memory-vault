#!/usr/bin/env bash
# ==============================================================================
# SKILL HARDENING: Pre-commit Skill Validation
# ==============================================================================
# Rule: If .vault/schemas/skill-policy.json exists and is enabled, validate any
#       staged files in skill directories.
# Enforcement: Optional — skipped silently if policy file is absent or disabled.
# See: .vault/schemas/skill-policy.json for policy configuration.
# ==============================================================================

check_skill_hardening() {
    local policy_file="${VAULT_ROOT}/${VAULT_CONFIG_DIR}/schemas/skill-policy.json"

    # Skip silently if no policy file exists
    [[ ! -f "$policy_file" ]] && return

    # python3 is required for JSON parsing in skill hardening
    if ! command -v python3 &>/dev/null; then
        warn "SKILL-HARDENING: python3 not found — skill policy enforcement skipped."
        warn "Install python3 to enable skill hardening checks."
        return
    fi

    # Skip silently if hardening is disabled
    local enabled
    enabled=$(python3 -c "import json; print(json.load(open('${policy_file}'))['enabled'])" 2>/dev/null || echo "False")
    [[ "$enabled" != "True" ]] && return

    info "SKILL-HARDENING: Checking staged skill files..."

    # Read skill directories from policy
    local skill_dirs
    skill_dirs=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
for d in policy.get('skill_directories', []):
    print(d)
" 2>/dev/null)

    # Check if any staged files are in skill directories
    local staged_files
    staged_files=$(get_staged_files)
    local skill_files_staged=false

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        while IFS= read -r skill_dir; do
            [[ -z "$skill_dir" ]] && continue
            if [[ "$file" == "${skill_dir}/"* ]]; then
                skill_files_staged=true
                break 2
            fi
        done <<< "$skill_dirs"
    done <<< "$staged_files"

    if ! $skill_files_staged; then
        success "SKILL-HARDENING: No skill files staged"
        return
    fi

    # Read enforcement level and settings
    local enforcement
    enforcement=$(python3 -c "import json; print(json.load(open('${policy_file}'))['enforcement'])" 2>/dev/null || echo "strict")

    local level_settings
    level_settings=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
level = policy['levels'].get(policy['enforcement'], policy['levels']['strict'])
for k, v in level.items():
    if isinstance(v, list):
        print(f'{k}=|{chr(10).join(str(i) for i in v)}|')
    else:
        print(f'{k}={v}')
" 2>/dev/null)

    # Parse settings
    local require_manifest="True"
    local allow_tool_escalation="False"
    local allow_shell_preprocessing="False"
    local allow_external_urls="False"
    local blocked_patterns_raw=""

    while IFS= read -r setting_line; do
        local key="${setting_line%%=*}"
        local val="${setting_line#*=}"
        case "$key" in
            require_manifest) require_manifest="$val" ;;
            allow_tool_escalation) allow_tool_escalation="$val" ;;
            allow_shell_preprocessing) allow_shell_preprocessing="$val" ;;
            allow_external_urls) allow_external_urls="$val" ;;
            blocked_patterns) blocked_patterns_raw="${val}" ;;
        esac
    done <<< "$level_settings"

    # Parse blocked patterns into array
    local -a blocked_patterns=()
    if [[ -n "$blocked_patterns_raw" ]]; then
        local inner="${blocked_patterns_raw#|}"
        inner="${inner%|}"
        while IFS= read -r pat; do
            [[ -n "$pat" ]] && blocked_patterns+=("$pat")
        done <<< "$inner"
    fi

    # Read URL blocklist
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

    # Validate each staged skill file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local in_skill_dir=false
        while IFS= read -r skill_dir; do
            [[ -z "$skill_dir" ]] && continue
            if [[ "$file" == "${skill_dir}/"* ]]; then
                in_skill_dir=true
                break
            fi
        done <<< "$skill_dirs"

        $in_skill_dir || continue

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        # Determine the skill root directory (first subdirectory under skill_dir)
        local skill_root=""
        while IFS= read -r skill_dir; do
            [[ -z "$skill_dir" ]] && continue
            if [[ "$file" == "${skill_dir}/"* ]]; then
                # Extract the skill subdirectory name
                local remainder="${file#${skill_dir}/}"
                local skill_subdir="${remainder%%/*}"
                skill_root="${VAULT_ROOT}/${skill_dir}/${skill_subdir}"
                break
            fi
        done <<< "$skill_dirs"

        # Check manifest requirement for the skill root
        if [[ "$require_manifest" == "True" ]] && [[ -n "$skill_root" ]] && [[ -d "$skill_root" ]]; then
            if [[ ! -f "${skill_root}/skill-manifest.json" ]]; then
                violation "SKILL" "$file" "Skill directory missing required skill-manifest.json (${enforcement} enforcement)"
            fi
        fi

        # Only scan markdown files for content violations
        local ext
        ext=$(get_extension "$file")
        if extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then

            # Check for blocked patterns
            for pattern in "${blocked_patterns[@]}"; do
                if grep -qF "$pattern" "$full_path" 2>/dev/null; then
                    violation "SKILL" "$file" "Blocked pattern '${pattern}' detected (${enforcement} enforcement)"
                fi
            done

            # Check for allowed-tools frontmatter
            if [[ "$allow_tool_escalation" == "False" ]]; then
                if grep -qE '^allowed-tools:' "$full_path" 2>/dev/null; then
                    violation "SKILL" "$file" "Tool escalation via allowed-tools blocked (${enforcement} enforcement)"
                fi
            fi

            # Check for !command preprocessing
            if [[ "$allow_shell_preprocessing" == "False" ]]; then
                if grep -qE '^!' "$full_path" 2>/dev/null; then
                    violation "SKILL" "$file" "Shell preprocessing syntax blocked (${enforcement} enforcement)"
                fi
            fi

            # Check for external URLs
            if [[ "$allow_external_urls" == "False" ]]; then
                local urls_in_file
                urls_in_file=$(grep -oE 'https?://[a-zA-Z0-9./?=_%&:@#~-]+' "$full_path" 2>/dev/null || true)
                while IFS= read -r url; do
                    [[ -z "$url" ]] && continue
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
                        violation "SKILL" "$file" "External URL blocked: ${url} (${enforcement} enforcement)"
                    fi
                done <<< "$urls_in_file"
            else
                # Check blocklist even in permissive mode
                while IFS= read -r blocked_domain; do
                    [[ -z "$blocked_domain" ]] && continue
                    if grep -qF "$blocked_domain" "$full_path" 2>/dev/null; then
                        violation "SKILL" "$file" "Blocklisted domain '${blocked_domain}' detected"
                    fi
                done <<< "$url_blocklist"
            fi
        fi
    done <<< "$staged_files"

    success "SKILL-HARDENING: Skill file validation complete"
}
