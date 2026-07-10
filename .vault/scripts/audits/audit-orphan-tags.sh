#!/usr/bin/env bash
# ==============================================================================
# AUDIT: Orphan Tags
# ==============================================================================
# Purpose: List approved tags (from .vault/rules/tags.md) used by zero wiki
#          pages. Unlike tag-audit's summary count, this prints each orphan
#          tag on its own line so the list is directly reviewable or
#          scriptable.
# Usage: vault-tools.sh orphan-tags
# Dependencies: Requires lib-utils.sh to be sourced first.
# ==============================================================================

cmd_orphan_tags() {
    header "Orphan Tags (approved, but used by zero wiki pages)"

    local approved_tags_file
    approved_tags_file=$(mktemp)
    if [[ -f "${TAGS_FILE}" ]]; then
        grep -E '^\- `[a-z][a-z0-9-]*/[a-z0-9-]+`' "${TAGS_FILE}" \
            | sed 's/^- `//' | sed 's/`.*//' | sort -u > "$approved_tags_file"
    else
        error "Tags file not found"
        rm -f "$approved_tags_file"
        return 1
    fi

    local used_tags_file
    used_tags_file=$(mktemp)
    while IFS= read -r file; do
        local fm
        fm=$(extract_fm "$file")
        [[ -z "$fm" ]] && continue
        fm_tags "$fm"
    done < <(wiki_files) | sort -u > "$used_tags_file"

    local orphan_file
    orphan_file=$(mktemp)
    comm -23 "$approved_tags_file" "$used_tags_file" > "$orphan_file"
    local orphan_count
    orphan_count=$(wc -l < "$orphan_file" | tr -d ' ')

    if [[ $orphan_count -eq 0 ]]; then
        ok "No orphan tags found"
    else
        while IFS= read -r tag; do
            [[ -z "$tag" ]] && continue
            warning "${tag}"
        done < "$orphan_file"
        echo ""
        echo "  ${orphan_count} approved tag(s) are unused."
    fi

    rm -f "$approved_tags_file" "$used_tags_file" "$orphan_file"
    echo ""
}
