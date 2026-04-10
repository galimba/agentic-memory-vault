#!/usr/bin/env bash
# ==============================================================================
# LIB-LINT — Lint and validation commands for vault-tools
# ==============================================================================
#
# Contains commands for vault quality assurance:
#   cmd_lint()       — Full vault lint (frontmatter, tags, lines, orphans, stale, index)
#   cmd_validate()   — Single file validation
#   cmd_orphans()    — Orphan page detection
#   cmd_stale()      — Staleness check
#
# This file is sourced by vault-tools.sh and depends on functions and
# variables from lib-utils.sh and the entry point configuration.
#
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

# ==============================================================================
# COMMAND: orphans
# ==============================================================================
# List wiki pages with no inbound links from other pages.

cmd_orphans() {
    header "Orphan Pages (no inbound links)"

    local orphan_count=0
    while IFS= read -r file; do
        local relative="${file#${VAULT_ROOT}/}"
        # Skip index.md and log.md — they're structural, not content
        if [[ "$relative" == "wiki/index.md" ]] || [[ "$relative" == "wiki/log.md" ]]; then
            continue
        fi
        if ! is_linked "$file"; then
            warning "${relative}"
            orphan_count=$((orphan_count + 1))
        fi
    done < <(wiki_files)

    if [[ $orphan_count -eq 0 ]]; then
        ok "No orphan pages found"
    else
        echo ""
        echo "  Found ${orphan_count} orphan page(s). Consider adding links or removing."
    fi
    echo ""
}

# ==============================================================================
# COMMAND: stale
# ==============================================================================
# List pages not updated within the threshold (default 30 days).

cmd_stale() {
    local threshold="${1:-$DEFAULT_STALE_DAYS}"
    header "Stale Pages (not updated in ${threshold}+ days)"

    local today_ts
    today_ts=$(date +%s)
    local stale_count=0

    while IFS= read -r file; do
        local fm
        fm=$(extract_fm "$file")
        [[ -z "$fm" ]] && continue

        local updated
        updated=$(fm_field "updated" "$fm")
        [[ -z "$updated" ]] && continue

        # Handle template placeholders
        if [[ "$updated" == *"{{"* ]]; then
            continue
        fi

        # SECURITY: Validate date format before passing to date -d
        if ! is_valid_date "$updated"; then
            continue
        fi

        local updated_ts
        updated_ts=$(date -d "$updated" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$updated" +%s 2>/dev/null || echo "0")
        [[ "$updated_ts" == "0" ]] && continue

        local age_days=$(( (today_ts - updated_ts) / 86400 ))
        if [[ $age_days -ge $threshold ]]; then
            local relative="${file#${VAULT_ROOT}/}"
            local title
            title=$(fm_field "title" "$fm")
            warning "${relative} — \"${title}\" (${age_days} days old)"
            stale_count=$((stale_count + 1))
        fi
    done < <(wiki_files)

    if [[ $stale_count -eq 0 ]]; then
        ok "No stale pages found"
    else
        echo ""
        echo "  Found ${stale_count} stale page(s). Review and update or archive."
    fi
    echo ""
}

# ==============================================================================
# COMMAND: validate
# ==============================================================================
# Validate a single file against all applicable rules.

cmd_validate() {
    local file_path="$1"
    if [[ -z "$file_path" ]]; then
        error "Usage: vault-tools.sh validate <file-path>"
        exit 2
    fi

    local full_path
    if [[ "$file_path" = /* ]]; then
        full_path="$file_path"
    else
        full_path="${VAULT_ROOT}/${file_path}"
    fi

    if [[ ! -f "$full_path" ]]; then
        error "File not found: ${full_path}"
        exit 2
    fi

    header "Validating: ${file_path}"
    local violations=0

    # Check frontmatter
    subheader "Frontmatter"
    local fm
    fm=$(extract_fm "$full_path")
    if [[ -z "$fm" ]]; then
        error "No valid frontmatter found"
        violations=$((violations + 1))
    else
        ok "Frontmatter present"
        local title type created updated status
        title=$(fm_field "title" "$fm")
        type=$(fm_field "type" "$fm")
        created=$(fm_field "created" "$fm")
        updated=$(fm_field "updated" "$fm")
        status=$(fm_field "status" "$fm")

        # shellcheck disable=SC2015
        [[ -n "$title" ]] && ok "Title: ${title}" || { error "Missing title"; violations=$((violations+1)); }
        # shellcheck disable=SC2015
        [[ -n "$type" ]] && ok "Type: ${type}" || { error "Missing type"; violations=$((violations+1)); }
        # shellcheck disable=SC2015
        [[ -n "$created" ]] && ok "Created: ${created}" || { error "Missing created"; violations=$((violations+1)); }
        # shellcheck disable=SC2015
        [[ -n "$updated" ]] && ok "Updated: ${updated}" || { error "Missing updated"; violations=$((violations+1)); }
        # shellcheck disable=SC2015
        [[ -n "$status" ]] && ok "Status: ${status}" || { error "Missing status"; violations=$((violations+1)); }
    fi

    # Check tags
    subheader "Tags"
    if [[ -n "$fm" ]]; then
        local tags
        tags=$(fm_tags "$fm")
        if [[ -z "$tags" ]]; then
            error "No tags found"
            violations=$((violations + 1))
        else
            local tag_count
            tag_count=$(echo "$tags" | wc -l | tr -d ' ')
            ok "${tag_count} tag(s) found"
            while IFS= read -r tag; do
                [[ -z "$tag" ]] && continue
                if echo "$tag" | grep -qE '^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$'; then
                    ok "  Valid: ${tag}"
                else
                    error "  Invalid format: ${tag}"
                    violations=$((violations + 1))
                fi
            done <<< "$tags"
        fi
    fi

    # Check line count
    subheader "Line Count"
    local lines
    lines=$(wc -l < "$full_path" | tr -d ' ')
    echo "  Lines: ${lines}"
    if [[ $lines -gt $MAX_MARKDOWN_LINES ]]; then
        error "Exceeds ${MAX_MARKDOWN_LINES} line limit"
        violations=$((violations + 1))
    else
        ok "Within limit"
    fi

    # Check links
    subheader "Links"
    local link_count
    link_count=$(grep -o '\[\[' "$full_path" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Wikilinks: ${link_count}"
    if [[ $link_count -lt 3 ]]; then
        warning "Fewer than 3 links (soft rule SR-003)"
    else
        ok "Good link density"
    fi

    echo ""
    if [[ $violations -gt 0 ]]; then
        error "Validation failed: ${violations} violation(s)"
        return 1
    else
        ok "Validation passed"
        return 0
    fi
}

# ==============================================================================
# COMMAND: lint
# ==============================================================================
# Full vault lint — runs all checks and generates a report.

cmd_lint() {
    header "Full Vault Lint"
    local total_violations=0
    local total_warnings=0

    # 1. Frontmatter validation
    subheader "Frontmatter validation"
    while IFS= read -r file; do
        local relative="${file#${VAULT_ROOT}/}"
        local fm
        fm=$(extract_fm "$file")
        if [[ -z "$fm" ]]; then
            error "${relative}: Missing or invalid frontmatter"
            total_violations=$((total_violations + 1))
        fi
    done < <(wiki_files)
    ok "Frontmatter scan complete"

    # 2. Tag validation
    subheader "Tag validation"
    local unapproved
    unapproved=$(cmd_tag_audit 2>/dev/null | grep -c "Unapproved tag:" || true)
    if [[ $unapproved -gt 0 ]]; then
        total_violations=$((total_violations + unapproved))
    fi
    ok "Tag scan complete"

    # 3. Line count check
    subheader "Line count check"
    while IFS= read -r file; do
        local relative="${file#${VAULT_ROOT}/}"
        if [[ "$relative" == "wiki/index.md" ]] || [[ "$relative" == "wiki/log.md" ]]; then
            continue
        fi
        local lines
        lines=$(wc -l < "$file" | tr -d ' ')
        if [[ $lines -gt $MAX_MARKDOWN_LINES ]]; then
            error "${relative}: ${lines} lines (max ${MAX_MARKDOWN_LINES})"
            total_violations=$((total_violations + 1))
        fi
    done < <(wiki_files)
    ok "Line count scan complete"

    # 4. Orphan check
    subheader "Orphan detection"
    local orphans=0
    while IFS= read -r file; do
        local relative="${file#${VAULT_ROOT}/}"
        if [[ "$relative" == "wiki/index.md" ]] || [[ "$relative" == "wiki/log.md" ]]; then
            continue
        fi
        if ! is_linked "$file"; then
            warning "${relative}: orphan (no inbound links)"
            orphans=$((orphans + 1))
            total_warnings=$((total_warnings + 1))
        fi
    done < <(wiki_files)
    ok "Orphan scan complete (${orphans} found)"

    # 5. Stale content check
    subheader "Staleness check (${DEFAULT_STALE_DAYS} day threshold)"
    local stale=0
    local today_ts
    today_ts=$(date +%s)
    while IFS= read -r file; do
        local fm
        fm=$(extract_fm "$file")
        [[ -z "$fm" ]] && continue
        local updated
        updated=$(fm_field "updated" "$fm")
        [[ -z "$updated" ]] && continue
        [[ "$updated" == *"{{"* ]] && continue
        # SECURITY: Validate date format before passing to date -d
        is_valid_date "$updated" || continue
        local updated_ts
        updated_ts=$(date -d "$updated" +%s 2>/dev/null || echo "0")
        [[ "$updated_ts" == "0" ]] && continue
        local age_days=$(( (today_ts - updated_ts) / 86400 ))
        if [[ $age_days -ge $DEFAULT_STALE_DAYS ]]; then
            local relative="${file#${VAULT_ROOT}/}"
            warning "${relative}: stale (${age_days} days)"
            stale=$((stale + 1))
            total_warnings=$((total_warnings + 1))
        fi
    done < <(wiki_files)
    ok "Staleness scan complete (${stale} found)"

    # 6. Index completeness
    subheader "Index completeness"
    if [[ -f "${INDEX_FILE}" ]]; then
        local unregistered=0
        while IFS= read -r file; do
            local relative="${file#${VAULT_ROOT}/}"
            if [[ "$relative" == "wiki/index.md" ]] || [[ "$relative" == "wiki/log.md" ]]; then
                continue
            fi
            local basename
            basename=$(basename "$relative")
            # SECURITY: Use -F for literal matching (filenames may contain regex metacharacters)
            if ! grep -qF "$basename" "${INDEX_FILE}" 2>/dev/null; then
                error "${relative}: not in index.md"
                unregistered=$((unregistered + 1))
                total_violations=$((total_violations + 1))
            fi
        done < <(wiki_files)
        ok "Index scan complete (${unregistered} unregistered)"
    else
        error "wiki/index.md not found"
        total_violations=$((total_violations + 1))
    fi

    # Summary
    header "Lint Summary"
    echo "  Violations (blocking): ${total_violations}"
    echo "  Warnings (advisory):   ${total_warnings}"
    echo ""

    if [[ $total_violations -gt 0 ]]; then
        error "Lint failed with ${total_violations} violation(s)"
        return 1
    else
        ok "Lint passed"
        return 0
    fi
}
