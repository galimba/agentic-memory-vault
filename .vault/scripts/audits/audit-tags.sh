#!/usr/bin/env bash
# ==============================================================================
# AUDIT: Tag Taxonomy
# ==============================================================================
# Purpose: Audit tag usage — find unapproved tags, unused approved tags, and
#          distribution across the vault.
# Usage: vault-tools.sh tag-audit
# Dependencies: Requires lib-utils.sh to be sourced first.
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

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
