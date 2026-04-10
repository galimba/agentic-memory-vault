#!/usr/bin/env bash
# ==============================================================================
# HR-002: Mandatory Frontmatter
# ==============================================================================
# Rule: Every .md file in wiki/ must have valid YAML frontmatter with required fields.
# Enforcement: Rejects commits with missing or invalid frontmatter in wiki/ files.
# See: .vault/rules/hard-rules.md for full specification.
# ==============================================================================

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
