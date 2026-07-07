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
# List pages whose age exceeds their staleness threshold.
#
# Threshold resolution:
#   - If a numeric argument is supplied, it is used globally for every file
#     (preserves the historical CLI contract: `vault-tools.sh stale 14`).
#   - Otherwise, each file's threshold is resolved from
#     .vault/schemas/staleness-config.json via resolve_stale_threshold(),
#     taking the most restrictive matching domain/type override.
# Pages whose status matches `exempt_statuses` in the config are skipped.

cmd_stale() {
    local explicit_threshold=""
    if [[ $# -gt 0 ]]; then
        explicit_threshold="$1"
    fi
    local header_label="${explicit_threshold:-per-file (staleness-config.json)}"
    header "Stale Pages (threshold: ${header_label})"

    local today_ts
    today_ts=$(date +%s)
    local stale_count=0

    while IFS= read -r file; do
        local fm
        fm=$(extract_fm "$file")
        [[ -z "$fm" ]] && continue

        local status
        status=$(fm_field "status" "$fm")
        if is_stale_exempt "$status"; then
            continue
        fi

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

        local file_threshold
        if [[ -n "$explicit_threshold" ]]; then
            file_threshold="$explicit_threshold"
        else
            file_threshold=$(resolve_stale_threshold "$fm")
        fi

        local age_days=$(( (today_ts - updated_ts) / 86400 ))
        if [[ $age_days -ge $file_threshold ]]; then
            local relative="${file#${VAULT_ROOT}/}"
            local title
            title=$(fm_field "title" "$fm")
            warning "${relative} — \"${title}\" (${age_days} days old, threshold ${file_threshold})"
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
    link_count=$( { grep -o '\[\[' "$full_path" 2>/dev/null || true; } | wc -l | tr -d ' ')
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
#
# Flags:
#   --report   Write a structured markdown report to
#              memory/notes/lint-report-YYYY-MM-DD.md (B3).

cmd_lint() {
    local write_report=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --report) write_report=true; shift ;;
            *) shift ;;
        esac
    done

    header "Full Vault Lint"
    local total_violations=0
    local total_warnings=0
    local orphans=0
    local stale=0

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

    # 5. Stale content check — per-domain/type thresholds via resolve_stale_threshold
    subheader "Staleness check (per-file via staleness-config.json)"
    local today_ts
    today_ts=$(date +%s)
    while IFS= read -r file; do
        local fm
        fm=$(extract_fm "$file")
        [[ -z "$fm" ]] && continue
        local status
        status=$(fm_field "status" "$fm")
        if is_stale_exempt "$status"; then
            continue
        fi
        local updated
        updated=$(fm_field "updated" "$fm")
        [[ -z "$updated" ]] && continue
        [[ "$updated" == *"{{"* ]] && continue
        # SECURITY: Validate date format before passing to date -d
        is_valid_date "$updated" || continue
        local updated_ts
        updated_ts=$(date -d "$updated" +%s 2>/dev/null || echo "0")
        [[ "$updated_ts" == "0" ]] && continue
        local file_threshold
        file_threshold=$(resolve_stale_threshold "$fm")
        local age_days=$(( (today_ts - updated_ts) / 86400 ))
        if [[ $age_days -ge $file_threshold ]]; then
            local relative="${file#${VAULT_ROOT}/}"
            warning "${relative}: stale (${age_days} days, threshold ${file_threshold})"
            stale=$((stale + 1))
            total_warnings=$((total_warnings + 1))
        fi
    done < <(wiki_files)
    ok "Staleness scan complete (${stale} found)"

    # 6. Index completeness — a page counts as registered when it appears in
    # the root wiki/index.md OR any wiki/index-*.md sub-index (split layout).
    # Reuses the lib-index helpers so this mirrors check-hr008.sh exactly.
    subheader "Index completeness"
    if [[ -f "${INDEX_FILE}" ]]; then
        local unregistered=0
        while IFS= read -r file; do
            local relative="${file#${VAULT_ROOT}/}"
            index_is_structural "$relative" && continue
            if ! index_page_registered "$relative"; then
                error "${relative}: not registered in wiki/index.md or any sub-index"
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

    if $write_report; then
        _write_lint_report "$total_violations" "$total_warnings" "$orphans" "$stale"
    fi

    if [[ $total_violations -gt 0 ]]; then
        error "Lint failed with ${total_violations} violation(s)"
        return 1
    else
        ok "Lint passed"
        return 0
    fi
}

# ==============================================================================
# INTERNAL: _write_lint_report
# ==============================================================================
# Writes a structured lint report to memory/notes/lint-report-YYYY-MM-DD.md.
# Frontmatter is valid per the schema; content is kept under the SR-002
# 200-line soft target so the file remains agent-readable.
# Called only when cmd_lint is invoked with --report.

_write_lint_report() {
    local violations="$1" warnings="$2" orphans="$3" stale="$4"
    local report_date
    report_date=$(date +%Y-%m-%d)
    local notes_dir="${MEMORY_DIR}/notes"
    local report_file="${notes_dir}/lint-report-${report_date}.md"

    mkdir -p "$notes_dir"

    cat > "$report_file" <<EOF
---
title: "Lint Report ${report_date}"
type: report
created: ${report_date}
updated: ${report_date}
status: active
tags:
  - type/report
  - lifecycle/active
  - format/log
  - agent/generated
owner: agent
confidence: high
---

# Lint Report — ${report_date}

Automated vault lint output. Regenerated each time
\`vault-tools.sh lint --report\` runs.

## Summary

| Metric                | Count |
|-----------------------|-------|
| Violations (blocking) | ${violations} |
| Warnings (advisory)   | ${warnings} |
| Orphan pages          | ${orphans} |
| Stale pages           | ${stale} |

## Recommendations

EOF

    {
        if [[ $violations -gt 0 ]]; then
            echo "- ${violations} blocking violation(s). See lint console output for details."
        fi
        if [[ $orphans -gt 0 ]]; then
            echo "- ${orphans} orphan page(s) have no inbound links. Add links or archive."
        fi
        if [[ $stale -gt 0 ]]; then
            echo "- ${stale} stale page(s) exceed their per-domain or per-type threshold. Review and update."
        fi
        if [[ $violations -eq 0 && $warnings -eq 0 && $orphans -eq 0 && $stale -eq 0 ]]; then
            echo "_Vault is healthy. No action needed._"
        fi
    } >> "$report_file"

    # Soft 200-line cap (SR-002 target)
    local report_lines
    report_lines=$(wc -l < "$report_file" | tr -d ' ')
    if [[ $report_lines -gt 200 ]]; then
        warning "Lint report is ${report_lines} lines (SR-002 target: 200)"
    fi

    ok "Lint report written to memory/notes/lint-report-${report_date}.md"
}
