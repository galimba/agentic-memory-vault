#!/usr/bin/env bash
# ==============================================================================
# VAULT PRE-COMMIT HOOK — Check Functions Library
# ==============================================================================
#
# This file contains all check functions (HR-001 through HR-013, skill
# hardening, and sensitive file checks) used by the pre-commit hook.
# It is sourced by pre-commit.sh and should not be executed directly.
#
# REQUIRES: lib-hook-utils.sh must be sourced first.
#
# CHECKS:
#   HR-001: Raw directory immutability
#   HR-002: Mandatory frontmatter
#   HR-003: Mandatory tags
#   HR-004: Markdown length limit (warn 200, hard block 400)
#   HR-005: Code file maximum length (warn 400, hard block 600)
#   HR-006: Unique page titles
#   HR-007: Updated field accuracy
#   HR-008: Index registration
#   HR-009: Flat tag notation
#   HR-010: Binary file quarantine
#   HR-011: Vault configuration protection
#   HR-012: Agent configuration protection
#   HR-013: CI and template protection
#   SKILL:  Skill hardening enforcement
#   ADVISORY: Sensitive file modification warnings
#
# ==============================================================================

# ==============================================================================
# HR-001: RAW DIRECTORY IMMUTABILITY
# ==============================================================================
# No agent may modify files in raw/. Requires CODEOWNERS approval via PR.

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

# ==============================================================================
# HR-002: MANDATORY FRONTMATTER
# ==============================================================================
# Every .md file in wiki/ must have valid YAML frontmatter with required fields.

check_hr002() {
    info "HR-002: Checking mandatory frontmatter..."
    local staged_files
    staged_files=$(get_staged_files)
    local required_fields=("title" "type" "created" "updated" "status" "tags")
    local valid_types=("concept" "entity" "source" "comparison" "decision" "report" "index" "evaluation")
    local valid_statuses=("draft" "active" "review" "archived" "deprecated")

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        # Only check wiki/ markdown files
        local ext
        ext=$(get_extension "$file")
        if [[ "$file" != "${WIKI_DIR}/"* ]] || ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        # Check file starts with ---
        local first_line
        first_line=$(head -1 "$full_path" 2>/dev/null || echo "")
        if [[ "$first_line" != "---" ]]; then
            violation "HR-002" "$file" "Missing YAML frontmatter. File must start with ---"
            continue
        fi

        local frontmatter
        frontmatter=$(extract_frontmatter "$full_path")
        if [[ -z "$frontmatter" ]]; then
            violation "HR-002" "$file" "Invalid frontmatter. No closing --- found."
            continue
        fi

        # Check each required field exists
        for field in "${required_fields[@]}"; do
            local value
            value=$(get_frontmatter_field "$field" "$frontmatter")
            if [[ -z "$value" ]] && [[ "$field" != "tags" ]]; then
                violation "HR-002" "$file" "Missing required frontmatter field: ${field}"
            fi
        done

        # Validate type enum
        local type_value
        type_value=$(get_frontmatter_field "type" "$frontmatter")
        if [[ -n "$type_value" ]]; then
            local type_valid=false
            for valid_type in "${valid_types[@]}"; do
                if [[ "$type_value" == "$valid_type" ]]; then
                    type_valid=true
                    break
                fi
            done
            if ! $type_valid; then
                violation "HR-002" "$file" "Invalid type '${type_value}'. Must be one of: ${valid_types[*]}"
            fi
        fi

        # Validate status enum
        local status_value
        status_value=$(get_frontmatter_field "status" "$frontmatter")
        if [[ -n "$status_value" ]]; then
            local status_valid=false
            for valid_status in "${valid_statuses[@]}"; do
                if [[ "$status_value" == "$valid_status" ]]; then
                    status_valid=true
                    break
                fi
            done
            if ! $status_valid; then
                violation "HR-002" "$file" "Invalid status '${status_value}'. Must be one of: ${valid_statuses[*]}"
            fi
        fi

    done <<< "$staged_files"

    success "HR-002: Frontmatter check complete"
}

# ==============================================================================
# HR-003: MANDATORY TAGS
# ==============================================================================
# Every wiki/ file must have at least one tag from the approved taxonomy.

check_hr003() {
    info "HR-003: Checking mandatory tags..."
    local staged_files
    staged_files=$(get_staged_files)

    # Load approved tags from taxonomy for validation
    local approved_tags=""
    if [[ -f "${VAULT_ROOT}/${TAGS_FILE}" ]]; then
        approved_tags=$(get_approved_tags)
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")
        if [[ "$file" != "${WIKI_DIR}/"* ]] || ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local frontmatter
        frontmatter=$(extract_frontmatter "$full_path")
        [[ -z "$frontmatter" ]] && continue

        local tags
        tags=$(get_frontmatter_tags "$frontmatter")
        if [[ -z "$tags" ]]; then
            violation "HR-003" "$file" "No tags found. Every wiki page must have at least one approved tag."
            continue
        fi

        # Validate each tag against approved taxonomy if available
        if [[ -n "$approved_tags" ]]; then
            local has_approved_tag=false
            while IFS= read -r tag; do
                [[ -z "$tag" ]] && continue
                if echo "$approved_tags" | grep -qxF "$tag"; then
                    has_approved_tag=true
                fi
            done <<< "$tags"
            if ! $has_approved_tag; then
                violation "HR-003" "$file" "No approved tags found. Tags must be from the taxonomy in ${TAGS_FILE}."
            fi
        fi
    done <<< "$staged_files"

    success "HR-003: Tag presence check complete"
}

# ==============================================================================
# HR-004: MARKDOWN LENGTH LIMIT
# ==============================================================================
# Markdown files in wiki/ or memory/ warn at 200 lines, block at 400 lines.

check_hr004() {
    info "HR-004: Checking markdown length limits (warn ${WARN_MARKDOWN_LINES}, max ${MAX_MARKDOWN_LINES} lines)..."
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")

        if [[ "$file" != "${WIKI_DIR}/"* ]] && [[ "$file" != "${MEMORY_DIR}/"* ]]; then
            continue
        fi
        if ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi
        if is_exempt "$file"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local line_count
        line_count=$(count_lines "$full_path")
        if [[ $line_count -gt $MAX_MARKDOWN_LINES ]]; then
            violation "HR-004" "$file" "Exceeds ${MAX_MARKDOWN_LINES} line hard limit (has ${line_count} lines). Split into linked sub-pages."
        elif [[ $line_count -gt $WARN_MARKDOWN_LINES ]]; then
            warn "HR-004: ${file} has ${line_count} lines (recommended max: ${WARN_MARKDOWN_LINES}). Consider splitting."
        fi
    done <<< "$staged_files"

    success "HR-004: Markdown length check complete"
}

# ==============================================================================
# HR-005: CODE FILE LENGTH LIMIT
# ==============================================================================
# Code files in .vault/ and .claude/ warn at 400 lines, block at 600 lines.

check_hr005() {
    info "HR-005: Checking code file length limits (warn ${WARN_CODE_LINES}, max ${MAX_CODE_LINES} lines)..."
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")

        # Check code files in .vault/ and .claude/
        if [[ "$file" != "${VAULT_CONFIG_DIR}/"* ]] && [[ "$file" != ".claude/"* ]]; then
            continue
        fi

        # Skip config files
        if extension_in_list "$ext" "${CONFIG_EXTENSIONS[@]}"; then
            continue
        fi

        # Skip non-code files
        if ! extension_in_list "$ext" "${CODE_EXTENSIONS[@]}"; then
            continue
        fi

        # Check exemptions
        if is_exempt "$file"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local line_count
        line_count=$(count_lines "$full_path")
        if [[ $line_count -gt $MAX_CODE_LINES ]]; then
            violation "HR-005" "$file" "Exceeds ${MAX_CODE_LINES} line limit (has ${line_count} lines). Split into modular files with clear responsibilities."
        elif [[ $line_count -gt $WARN_CODE_LINES ]]; then
            warn "HR-005: ${file} has ${line_count} lines (recommended max: ${WARN_CODE_LINES}). Consider modularizing."
        fi
    done <<< "$staged_files"

    success "HR-005: Code length check complete"
}

# ==============================================================================
# HR-006: UNIQUE PAGE TITLES
# ==============================================================================
# No two files in wiki/ may share the same title frontmatter value.

check_hr006() {
    info "HR-006: Checking unique page titles..."

    # Build a map of all wiki/ titles
    declare -A title_map
    local duplicates_found=false

    while IFS= read -r -d '' file; do
        local ext
        ext=$(get_extension "$file")
        if ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local frontmatter
        frontmatter=$(extract_frontmatter "$file")
        [[ -z "$frontmatter" ]] && continue

        local title
        title=$(get_frontmatter_field "title" "$frontmatter")
        [[ -z "$title" ]] && continue

        local relative_path="${file#${VAULT_ROOT}/}"

        if [[ -n "${title_map[$title]+x}" ]]; then
            violation "HR-006" "$relative_path" "Duplicate title '${title}' — also found in ${title_map[$title]}"
            duplicates_found=true
        else
            title_map["$title"]="$relative_path"
        fi
    # SECURITY: -maxdepth prevents traversal DoS; ! -type l excludes symlinks
    done < <(find "${VAULT_ROOT}/${WIKI_DIR}" -maxdepth "${MAX_FIND_DEPTH}" ! -type l -name "*.md" -print0 2>/dev/null)

    success "HR-006: Title uniqueness check complete"
}

# ==============================================================================
# HR-007: UPDATED FIELD ACCURACY
# ==============================================================================
# Modified files must have updated field matching commit date (+-1 day).

check_hr007() {
    info "HR-007: Checking updated field accuracy..."
    local staged_files
    staged_files=$(get_staged_files)
    local today
    today=$(today_date)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")
        if [[ "$file" != "${WIKI_DIR}/"* ]] || ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local frontmatter
        frontmatter=$(extract_frontmatter "$full_path")
        [[ -z "$frontmatter" ]] && continue

        local updated_value
        updated_value=$(get_frontmatter_field "updated" "$frontmatter")
        [[ -z "$updated_value" ]] && continue

        local diff
        diff=$(date_diff "$today" "$updated_value")
        if [[ $diff -gt $DATE_TOLERANCE ]]; then
            violation "HR-007" "$file" "Updated field '${updated_value}' is ${diff} days from today (${today}). Tolerance is ${DATE_TOLERANCE} day(s)."
        fi
    done <<< "$staged_files"

    success "HR-007: Updated field check complete"
}

# ==============================================================================
# HR-008: INDEX REGISTRATION
# ==============================================================================
# Every wiki/ file (except index.md and log.md) must appear in wiki/index.md.

check_hr008() {
    info "HR-008: Checking index registration..."
    local index_path="${VAULT_ROOT}/${INDEX_FILE}"

    if [[ ! -f "$index_path" ]]; then
        warn "HR-008: Index file not found at ${INDEX_FILE}. Skipping."
        return
    fi

    local index_content
    index_content=$(cat "$index_path")

    while IFS= read -r -d '' file; do
        local relative_path="${file#${VAULT_ROOT}/}"
        local ext
        ext=$(get_extension "$file")
        if ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        # Skip index.md and log.md themselves
        if [[ "$relative_path" == "${WIKI_DIR}/index.md" ]] || [[ "$relative_path" == "${WIKI_DIR}/log.md" ]]; then
            continue
        fi

        # Check if the file path or filename appears in index.md
        local basename
        basename=$(basename "$relative_path")
        # SECURITY: Use grep -F for literal string match — filenames may contain
        # regex metacharacters (., *, +, etc.) that grep would interpret as patterns.
        if ! echo "$index_content" | grep -qF "$basename" 2>/dev/null; then
            if ! echo "$index_content" | grep -qF "$relative_path" 2>/dev/null; then
                violation "HR-008" "$relative_path" "Not registered in ${INDEX_FILE}. Every wiki page must have an index entry."
            fi
        fi
    # SECURITY: -maxdepth prevents traversal DoS; ! -type l excludes symlinks
    done < <(find "${VAULT_ROOT}/${WIKI_DIR}" -maxdepth "${MAX_FIND_DEPTH}" ! -type l -name "*.md" -print0 2>/dev/null)

    success "HR-008: Index registration check complete"
}

# ==============================================================================
# HR-009: FLAT TAG NOTATION
# ==============================================================================
# Tags must match pattern: prefix/value (exactly one slash, no spaces).

check_hr009() {
    info "HR-009: Checking flat tag notation..."
    local staged_files
    staged_files=$(get_staged_files)
    local tag_pattern='^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$'

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")
        if [[ "$file" != "${WIKI_DIR}/"* ]] || ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local frontmatter
        frontmatter=$(extract_frontmatter "$full_path")
        [[ -z "$frontmatter" ]] && continue

        local tags
        tags=$(get_frontmatter_tags "$frontmatter")
        [[ -z "$tags" ]] && continue

        while IFS= read -r tag; do
            [[ -z "$tag" ]] && continue
            if ! echo "$tag" | grep -qE "$tag_pattern"; then
                violation "HR-009" "$file" "Invalid tag format '${tag}'. Must match prefix/value (lowercase, hyphenated, one slash)."
            fi
        done <<< "$tags"
    done <<< "$staged_files"

    success "HR-009: Tag notation check complete"
}

# ==============================================================================
# HR-010: BINARY FILE QUARANTINE
# ==============================================================================
# Binary files may only exist in raw/. No binaries in wiki/ or memory/.

check_hr010() {
    info "HR-010: Checking binary file quarantine..."
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Only check wiki/ and memory/ directories
        if [[ "$file" != "${WIKI_DIR}/"* ]] && [[ "$file" != "${MEMORY_DIR}/"* ]]; then
            continue
        fi

        local ext
        ext=$(get_extension "$file")

        # Allow markdown and json
        if extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi
        if [[ "$ext" == "json" ]]; then
            continue
        fi

        # Check if gitkeep
        if [[ "$(basename "$file")" == ".gitkeep" ]]; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        if [[ -f "$full_path" ]] && is_binary "$full_path"; then
            violation "HR-010" "$file" "Binary file detected outside raw/. Move to raw/ and reference via wikilink."
        fi
    done <<< "$staged_files"

    success "HR-010: Binary quarantine check complete"
}

# ==============================================================================
# HR-011: VAULT CONFIGURATION PROTECTION
# ==============================================================================

check_hr011() {
    info "HR-011: Checking vault configuration protection..."
    local staged_files
    staged_files=$(get_staged_files)

    local protected_dirs=(".vault/rules/" ".vault/hooks/" ".vault/scripts/")

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        for dir in "${protected_dirs[@]}"; do
            if [[ "$file" == "${dir}"* ]]; then
                violation "HR-011" "$file" "Vault configuration is protected. Submit a human-authored PR to modify ${dir}."
            fi
        done
    done <<< "$staged_files"

    if [[ $VIOLATIONS -eq 0 ]]; then
        success "HR-011: Vault configuration intact"
    fi
}

# ==============================================================================
# HR-012: AGENT CONFIGURATION PROTECTION
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

# ==============================================================================
# HR-013: CI AND TEMPLATE PROTECTION
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

# ==============================================================================
# SKILL HARDENING: PRE-COMMIT SKILL VALIDATION
# ==============================================================================
# If .vault/schemas/skill-policy.json exists and is enabled, validate any
# staged files in skill directories. This check is fully optional and
# backward compatible — if the policy file is absent or disabled, this
# entire section is skipped silently.

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

# ==============================================================================
# SENSITIVE FILE MODIFICATION WARNINGS
# ==============================================================================
# These checks emit warnings (not blocking violations) when files critical to
# vault security are modified. Pre-commit hooks cannot distinguish agent commits
# from human commits, so these are advisory. The intent is to surface changes
# to governance files that a human reviewer should scrutinize.

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
