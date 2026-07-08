#!/usr/bin/env bash
# ==============================================================================
# AUDIT: Consolidation Candidates
# ==============================================================================
# Purpose: Identify groups of 3+ stale, topically overlapping wiki pages that
#          are candidates for human-driven merging (issue #16).
# Usage: vault-tools.sh consolidate
# Dependencies: Requires lib-utils.sh to be sourced first.
#
# PAIRING RULE (deterministic, no tuning knobs):
#   Two pages PAIR when they share >= 2 approved tags AND at least one of
#   them lists the other in its `related:` frontmatter. The DIRECT-REFERENCE
#   variant is implemented: a mutual or one-way `related:` entry pairs the
#   pages; merely sharing a common third `related:` target does NOT.
#
# GROUPING RULE:
#   Only pages already past their staleness threshold enter the pair graph
#   (resolve_stale_threshold per page; statuses matching is_stale_exempt —
#   archived/deprecated — are skipped). Candidate groups are the connected
#   components of the pair graph with >= 3 members, so every member of every
#   reported group is past its own threshold by construction.
#
# REPORT-ONLY: writes memory/notes/consolidation-YYYY-MM-DD.md and never
# modifies, merges, or deletes any wiki page. Exits 0 (advisory) unless
# report I/O fails.
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

# Extract `related:` wikilink targets from a frontmatter blob, one basename
# per line. Handles quoted entries, [[path]] brackets, and |display suffixes.
# Usage: _consolidate_related_basenames "$frontmatter"
_consolidate_related_basenames() {
    local fm="$1"
    local in_rel=false
    echo "$fm" | while IFS= read -r line; do
        if [[ "$line" =~ ^related: ]]; then
            in_rel=true
            continue
        fi
        if $in_rel; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
                local entry
                entry=$(echo "$line" \
                    | sed 's/^[[:space:]]*-[[:space:]]*//' \
                    | sed 's/[[:space:]]*$//' \
                    | sed 's/^["'"'"']//' | sed 's/["'"'"']$//' \
                    | sed 's/^\[\[//' | sed 's/\]\]$//' | sed 's/|.*$//')
                [[ -n "$entry" ]] && basename "$entry"
            elif [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
        fi
    done
}

# Union-find over the global _CONS_PARENT array.
_consolidate_find() {
    local x=$1
    while [[ ${_CONS_PARENT[$x]} -ne $x ]]; do
        x=${_CONS_PARENT[$x]}
    done
    echo "$x"
}

cmd_consolidate() {
    header "Consolidation Candidates"

    local today today_ts
    today=$(date +%Y-%m-%d)
    today_ts=$(date +%s)

    # Load approved tag taxonomy (same extraction as tag-audit). Only
    # approved tags count toward the >= 2 shared-tag pairing rule.
    local approved_file
    approved_file=$(mktemp)
    if [[ -f "${TAGS_FILE}" ]]; then
        grep -oE '`[a-z][a-z0-9-]*/[a-z][a-z0-9-]*`' "${TAGS_FILE}" \
            | sed 's/`//g' | sort -u > "$approved_file"
    else
        warning "Tags file not found — treating all tags as approved"
    fi

    # ------------------------------------------------------------------
    # Collect stale candidate pages
    # ------------------------------------------------------------------
    subheader "Collecting stale candidate pages"
    local -a c_file=() c_title=() c_tags=() c_related=() c_updated=() c_age=() c_threshold=()
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
        if ! is_valid_date "$updated"; then
            continue
        fi

        local updated_ts
        updated_ts=$(date -d "$updated" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$updated" +%s 2>/dev/null || echo "0")
        [[ "$updated_ts" == "0" ]] && continue

        local file_threshold age_days
        file_threshold=$(resolve_stale_threshold "$fm")
        age_days=$(( (today_ts - updated_ts) / 86400 ))
        if [[ $age_days -lt $file_threshold ]]; then
            continue
        fi

        local tags
        tags=$(fm_tags "$fm" | sort -u)
        if [[ -s "$approved_file" ]]; then
            tags=$(comm -12 <(echo "$tags") "$approved_file")
        fi

        c_file+=("${file#"${VAULT_ROOT}"/}")
        c_title+=("$(fm_field "title" "$fm")")
        c_tags+=("$tags")
        c_related+=("$(_consolidate_related_basenames "$fm")")
        c_updated+=("$updated")
        c_age+=("$age_days")
        c_threshold+=("$file_threshold")
    done < <(wiki_files)

    local n=${#c_file[@]}
    ok "${n} stale candidate page(s)"

    # ------------------------------------------------------------------
    # Build pair graph: >= 2 shared approved tags AND a direct related:
    # reference (mutual or one-way). Group via union-find.
    # ------------------------------------------------------------------
    subheader "Building pair graph"
    _CONS_PARENT=()
    local -a pair_i=() pair_j=() pair_text=()
    local i j
    for ((i = 0; i < n; i++)); do
        _CONS_PARENT[i]=$i
    done
    for ((i = 0; i < n; i++)); do
        for ((j = i + 1; j < n; j++)); do
            local shared shared_count
            shared=$(comm -12 <(echo "${c_tags[$i]}") <(echo "${c_tags[$j]}") | grep -c . || true)
            shared_count=${shared:-0}
            [[ $shared_count -lt 2 ]] && continue

            local base_i base_j i_to_j=false j_to_i=false
            base_i=$(basename "${c_file[$i]}")
            base_j=$(basename "${c_file[$j]}")
            grep -Fxq "$base_j" <<< "${c_related[$i]}" && i_to_j=true
            grep -Fxq "$base_i" <<< "${c_related[$j]}" && j_to_i=true
            if ! $i_to_j && ! $j_to_i; then
                continue
            fi

            local direction
            if $i_to_j && $j_to_i; then
                direction="mutual \`related:\`"
            elif $i_to_j; then
                direction="\`related:\` from ${base_i}"
            else
                direction="\`related:\` from ${base_j}"
            fi
            local shared_list
            shared_list=$(comm -12 <(echo "${c_tags[$i]}") <(echo "${c_tags[$j]}") | sed 's/^/`/; s/$/`/' | paste -sd',' - | sed 's/,/, /g')

            pair_i+=("$i")
            pair_j+=("$j")
            pair_text+=("[[${c_file[$i]}]] and [[${c_file[$j]}]] — ${direction}; ${shared_count} shared tags: ${shared_list}")

            # Union
            local ri rj
            ri=$(_consolidate_find "$i")
            rj=$(_consolidate_find "$j")
            [[ $ri -ne $rj ]] && _CONS_PARENT[rj]=$ri
        done
    done
    ok "${#pair_i[@]} qualifying pair(s)"

    # Connected components with >= 3 members
    local -A comp_members=()
    for ((i = 0; i < n; i++)); do
        local root
        root=$(_consolidate_find "$i")
        comp_members[$root]="${comp_members[$root]:-} $i"
    done
    local -a groups=()
    local root
    for root in "${!comp_members[@]}"; do
        read -r -a members <<< "${comp_members[$root]}"
        [[ ${#members[@]} -ge 3 ]] && groups+=("${comp_members[$root]}")
    done

    # ------------------------------------------------------------------
    # Write report (report-only: no wiki page is ever modified here)
    # ------------------------------------------------------------------
    local notes_dir="${MEMORY_DIR}/notes"
    local report_file="${notes_dir}/consolidation-${today}.md"
    mkdir -p "$notes_dir"

    cat > "$report_file" <<EOF
---
title: "Consolidation Report ${today}"
type: report
created: ${today}
updated: ${today}
status: active
tags:
  - type/report
  - lifecycle/active
  - agent/generated
owner: agent
confidence: medium
---

# Consolidation Report — ${today}

Advisory report from \`vault-tools.sh consolidate\`. Pairing rule: two pages
pair when they share >= 2 approved tags AND one lists the other in its
\`related:\` frontmatter (direct reference — mutual or one-way; a shared
third-party \`related:\` target does not pair). Groups are connected
components of the pair graph with >= 3 members; every member is past its
staleness threshold. Report-only: no wiki page was modified.

## Summary

- Stale candidate pages: ${n}
- Qualifying pairs: ${#pair_i[@]}
- Consolidation groups: ${#groups[@]}
EOF

    if [[ ${#groups[@]} -eq 0 ]]; then
        {
            echo ""
            echo "## Groups"
            echo ""
            echo "_No consolidation candidates found. No action needed._"
        } >> "$report_file"
    else
        local g=0 m p
        for root in "${!comp_members[@]}"; do
            read -r -a members <<< "${comp_members[$root]}"
            [[ ${#members[@]} -lt 3 ]] && continue
            g=$((g + 1))

            # Group-wide tag intersection
            local group_tags="${c_tags[${members[0]}]}"
            for m in "${members[@]}"; do
                group_tags=$(comm -12 <(echo "$group_tags") <(echo "${c_tags[$m]}"))
            done
            local group_tags_line
            group_tags_line=$(echo "$group_tags" | sed '/^$/d' | sed 's/^/`/; s/$/`/' | paste -sd',' - | sed 's/,/, /g')
            [[ -z "$group_tags_line" ]] && group_tags_line="_(none shared by all members; overlap is pairwise)_"

            {
                echo ""
                echo "## Group ${g} (${#members[@]} pages)"
                echo ""
                echo "### Members"
                echo ""
                for m in $(printf '%s\n' "${members[@]}" | sort -n); do
                    echo "- [[${c_file[$m]}]] — \"${c_title[$m]}\" (updated ${c_updated[$m]}, ${c_age[$m]} days old, threshold ${c_threshold[$m]})"
                done
                echo ""
                echo "### Shared tags (all members)"
                echo ""
                echo "- ${group_tags_line}"
                echo ""
                echo "### Link evidence"
                echo ""
                for ((p = 0; p < ${#pair_i[@]}; p++)); do
                    if [[ " ${members[*]} " == *" ${pair_i[$p]} "* && " ${members[*]} " == *" ${pair_j[$p]} "* ]]; then
                        echo "- ${pair_text[$p]}"
                    fi
                done
                echo ""
                echo "**Suggested action**: review these ${#members[@]} pages for merging into a single canonical page; set \`status: archived\` on superseded members."
            } >> "$report_file"
        done
    fi

    rm -f "$approved_file"

    subheader "Results"
    if [[ ${#groups[@]} -eq 0 ]]; then
        ok "No consolidation candidates found"
    else
        warning "${#groups[@]} consolidation group(s) found — human review suggested"
    fi
    ok "Consolidation report written to memory/notes/consolidation-${today}.md"
    echo ""
}
