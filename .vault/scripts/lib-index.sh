#!/usr/bin/env bash
# ==============================================================================
# LIB-INDEX — Index maintenance commands for vault-tools
# ==============================================================================
#   cmd_index_rebuild()  — Full regeneration of the index from wiki/ frontmatter
#   cmd_index_update()   — Incremental append of unregistered pages (#10)
#   cmd_index_split()    — Partition an oversized index into sub-indexes (#9)
#
# Split layout: when wiki/index-*.md files exist, the root wiki/index.md keeps
# its section headings (stable anchors for external links) but each section
# only points to the sub-index holding the entries. All commands here detect
# the layout and read/write the right files. Sourced by vault-tools.sh.
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

# Threshold (lines) at/above which the index splits: index-split partitions
# here, index-rebuild auto-splits above it. Override via env or the CLI arg.
: "${INDEX_SPLIT_THRESHOLD:=250}"

# Standard frontmatter types, in the section order the index emits them
INDEX_STANDARD_TYPES=(source concept entity comparison decision report evaluation)

# --- Shared helpers -------------------------------------------------------------

# Map a frontmatter type to its index section title
index_section_title() {
    case "$1" in
        source) echo "Sources" ;;         concept) echo "Concepts" ;;
        entity) echo "Entities" ;;        comparison) echo "Comparisons" ;;
        decision) echo "Decisions" ;;     report) echo "Reports" ;;
        evaluation) echo "Evaluations" ;; *) echo "Other" ;;
    esac
}

# Map an index section title to its sub-index file (split layout).
# Non-standard sections all collapse into index-other.md.
index_subindex_for_section() {
    case "$1" in
        Sources|Concepts|Entities|Comparisons|Decisions|Reports|Evaluations)
            echo "${WIKI_DIR}/index-${1,,}.md" ;;
        *)  echo "${WIKI_DIR}/index-other.md" ;;
    esac
}

# Format a single index entry line: index_entry_line <rel-path> <title> <summary>
index_entry_line() {
    echo "- [[${1}|${2}]] — ${3}"
}

# True when the vault uses the split index layout (any wiki/index-*.md)
index_split_exists() {
    compgen -G "${WIKI_DIR}/index-*.md" > /dev/null
}

# True when a wiki-relative path is a structural index/log file
index_is_structural() {
    [[ "$1" == "wiki/index.md" || "$1" == wiki/index-*.md || "$1" == "wiki/log.md" ]]
}

# Emit standard frontmatter for a generated index page
index_frontmatter() {
    printf -- '---\ntitle: "%s"\ntype: index\ncreated: %s\nupdated: %s\nstatus: active\n' \
        "$1" "$(date +%Y-%m-%d)" "$(date +%Y-%m-%d)"
    printf -- 'tags:\n  - type/index\n  - lifecycle/active\n  - agent/generated\n---\n'
}

# Refresh the frontmatter updated field of a modified index file (HR-007)
index_touch_updated() {
    sed -i "s/^updated: .*/updated: $(date +%Y-%m-%d)/" "$1"
}

# A page is registered when its basename or relative path appears in the
# root index OR any split sub-index (mirrors check-hr008.sh).
# SECURITY: grep -F for literal match — filenames may contain metacharacters.
index_page_registered() {
    local base; base=$(basename "$1")
    grep -qF -e "$base" -e "$1" "${INDEX_FILE}" "${WIKI_DIR}"/index-*.md 2>/dev/null
}

# index_page_meta <file> <relative-path> — read a page's metadata into
# INDEX_META_{TITLE,TYPE,SUMMARY} with the shared fallbacks. 1 = no frontmatter.
index_page_meta() {
    local fm
    fm=$(extract_fm "$1")
    [[ -z "$fm" ]] && return 1
    INDEX_META_TITLE=$(fm_field "title" "$fm")
    INDEX_META_TYPE=$(fm_field "type" "$fm")
    INDEX_META_SUMMARY=$(fm_field "summary" "$fm")
    : "${INDEX_META_TITLE:=$2}" "${INDEX_META_TYPE:=uncategorized}" "${INDEX_META_SUMMARY:=(no summary)}"
}

# Collect all wiki pages into INDEX_TYPE_PAGES[type] (newline-joined entry
# lines). Skips structural files and pages without frontmatter.
declare -A INDEX_TYPE_PAGES=()
index_collect_pages() {
    INDEX_TYPE_PAGES=()
    local file relative
    while IFS= read -r file; do
        relative="${file#"${VAULT_ROOT}"/}"
        index_is_structural "$relative" && continue
        index_page_meta "$file" "$relative" || continue
        INDEX_TYPE_PAGES["$INDEX_META_TYPE"]+="$(index_entry_line "$relative" "$INDEX_META_TITLE" "$INDEX_META_SUMMARY")"$'\n'
    done < <(wiki_files)
}

# List collected non-standard types, sorted for determinism
index_other_types() {
    local type
    for type in "${!INDEX_TYPE_PAGES[@]}"; do
        case "$type" in
            source|concept|entity|comparison|decision|report|evaluation) ;;
            *) echo "$type" ;;
        esac
    done | sort
}

# Append an entry line under "## <section>" of an index file, preserving all
# other content. Creates the section at EOF when the heading is missing;
# replaces a generated "_No <x> yet._" placeholder when it is the only content.
index_append_entry() {
    local file="$1" section="$2" entry="$3"
    local placeholder_re='^_No .* yet\._$'
    local lines=() out=() i start=-1 end insert_after
    mapfile -t lines < "$file"
    end=${#lines[@]}
    for ((i = 0; i < ${#lines[@]}; i++)); do
        if ((start < 0)); then
            [[ "${lines[i]}" == "## ${section}" ]] && start=$i
        elif [[ "${lines[i]}" == "## "* ]]; then
            end=$i; break
        fi
    done
    if ((start < 0)); then
        { echo ""; echo "## ${section}"; echo ""; echo "$entry"; } >> "$file"
        return
    fi
    insert_after=$start  # insert after the last non-blank line of the section
    for ((i = start + 1; i < end; i++)); do
        [[ -n "${lines[i]//[[:space:]]/}" ]] && insert_after=$i
    done
    for ((i = 0; i < ${#lines[@]}; i++)); do
        if ((i != insert_after)); then out+=("${lines[i]}")
        elif [[ "${lines[i]}" =~ $placeholder_re ]]; then out+=("$entry")
        elif ((insert_after == start)); then out+=("${lines[i]}" "" "$entry")
        else out+=("${lines[i]}" "$entry")
        fi
    done
    printf '%s\n' "${out[@]}" > "$file"
}

# Strip leading/trailing blank lines from stdin, keep interior ones
_index_trim_blank_edges() {
    awk '{ l[NR] = $0; if ($0 ~ /[^[:space:]]/) { if (!s) s = NR; e = NR } }
         END { for (i = s; i <= e && s; i++) print l[i] }'
}

# --- COMMAND: index-rebuild ---------------------------------------------------
# Regenerate the index from wiki/ frontmatter. Writes a split pointer root +
# sub-indexes when already split or when the rebuilt index overflows (#9).

cmd_index_rebuild() {
    header "Rebuilding wiki/index.md"
    index_collect_pages
    _index_write_root single
    # Adopt (when oversized) or preserve (when sub-indexes already exist) the
    # split layout; the single write above becomes the pre-split root (#9).
    if index_split_exists || [[ "$(wc -l < "${INDEX_FILE}" | tr -d ' ')" -gt "${INDEX_SPLIT_THRESHOLD}" ]]; then
        _index_rebuild_subindexes
        _index_write_root split
    fi
    ok "Index rebuilt with entries from $(count_files "${WIKI_DIR}" "*.md") wiki pages"
    echo ""
}

# Emit the section body for one type: its entries, or a placeholder
_index_emit_entries() {
    local type="$1" section="$2"
    if [[ -n "${INDEX_TYPE_PAGES[$type]+x}" ]]; then
        printf '%s' "${INDEX_TYPE_PAGES[$type]}"
    else
        echo "_No ${section,,} yet._"
    fi
}

# Emit collected entries for every non-standard type (the "Other" body)
_index_emit_other_entries() {
    local type
    while IFS= read -r type; do
        printf '%s' "${INDEX_TYPE_PAGES[$type]}"
    done < <(index_other_types)
}

# Write the full root index. $1 = layout: "single" (entries inline) or
# "split" (pointer lines to the sub-index files that exist).
_index_write_root() {
    local layout="$1" type section sub_path
    {
        index_frontmatter "Vault Index"
        printf '\n# Vault Index\n\n'
        for type in "${INDEX_STANDARD_TYPES[@]}" other; do
            section=$(index_section_title "$type")
            sub_path=$(index_subindex_for_section "$section")
            if [[ "$type" == "other" ]]; then
                # Other appears only when non-standard pages or its file exist
                [[ -n "$(index_other_types)" || ( "$layout" == "split" && -f "$sub_path" ) ]] || continue
            fi
            printf '## %s\n\n' "$section"
            if [[ "$layout" == "split" && -f "$sub_path" ]]; then
                echo "See [[${sub_path#"${VAULT_ROOT}"/}|${section} Index]] for all entries."
            elif [[ "$type" == "other" ]]; then
                _index_emit_other_entries
            else
                _index_emit_entries "$type" "$section"
            fi
            echo ""
        done
    } > "${INDEX_FILE}"
}

# Write one sub-index file for a section. $2 is the pre-rendered entry body.
_index_write_subindex() {
    local section="$1" body="$2" sub_path
    sub_path=$(index_subindex_for_section "$section")
    {
        index_frontmatter "Vault Index — ${section}"
        printf '\n# Vault Index — %s\n\n' "$section"
        printf 'Part of the split index. Root: [[wiki/index.md|Vault Index]].\n\n'
        printf '## %s\n\n%s' "$section" "$body"
    } > "$sub_path"
}

# Regenerate every sub-index. A sub-index is (re)written when pages of its
# type exist OR the file already exists (never silently drop one — HR-014).
_index_rebuild_subindexes() {
    local type section sub_path other_body
    for type in "${INDEX_STANDARD_TYPES[@]}"; do
        section=$(index_section_title "$type")
        sub_path=$(index_subindex_for_section "$section")
        if [[ -n "${INDEX_TYPE_PAGES[$type]+x}" || -f "$sub_path" ]]; then
            _index_write_subindex "$section" "$(_index_emit_entries "$type" "$section")"$'\n'
        fi
    done
    other_body=$(_index_emit_other_entries)
    if [[ -n "$other_body" ]]; then
        _index_write_subindex "Other" "$other_body"$'\n'
    elif [[ -f "$(index_subindex_for_section Other)" ]]; then
        _index_write_subindex "Other" "_No other pages yet._"$'\n'
    fi
}

# --- COMMAND: index-update ------------------------------------------------------
# Incremental index maintenance (#10). Appends entries for wiki pages missing
# from the index, under the section matching their frontmatter type. Never
# removes or rewrites existing entries or prose — that is index-rebuild's job.

cmd_index_update() {
    header "Updating index (incremental)"
    [[ -f "${INDEX_FILE}" ]] || { error "wiki/index.md not found. Run: vault-tools.sh index-rebuild"; return 2; }

    local split=false added=0 file
    index_split_exists && split=true
    declare -A touched=()
    while IFS= read -r file; do
        local relative="${file#"${VAULT_ROOT}"/}"
        index_is_structural "$relative" && continue
        index_page_registered "$relative" && continue
        if ! index_page_meta "$file" "$relative"; then
            warning "${relative}: no frontmatter — skipped (fix HR-002 first)"
            continue
        fi

        local section target
        section=$(index_section_title "$INDEX_META_TYPE")
        if $split; then
            target=$(index_subindex_for_section "$section")
            if [[ ! -f "$target" ]]; then
                _index_seed_subindex "$section"
                touched["${INDEX_FILE}"]=1
            fi
        else
            target="${INDEX_FILE}"
        fi

        index_append_entry "$target" "$section" \
            "$(index_entry_line "$relative" "$INDEX_META_TITLE" "$INDEX_META_SUMMARY")"
        touched["$target"]=1
        added=$((added + 1))
        ok "Registered ${relative} under ## ${section} in ${target#"${VAULT_ROOT}"/}"
    done < <(wiki_files)

    if [[ $added -eq 0 ]]; then
        ok "Index already up to date — no unregistered pages"
    else
        local touched_file
        for touched_file in "${!touched[@]}"; do
            index_touch_updated "$touched_file"
        done
        ok "Added ${added} missing entries to the index"
    fi
    echo ""
}

# Create an empty sub-index skeleton and point the root index at it. The
# root section heading is reused when present (stable anchors) or created.
_index_seed_subindex() {
    local section="$1" sub_rel
    sub_rel="$(index_subindex_for_section "$section")" && sub_rel="${sub_rel#"${VAULT_ROOT}"/}"
    _index_write_subindex "$section" ""
    if ! grep -qF "$sub_rel" "${INDEX_FILE}"; then
        index_append_entry "${INDEX_FILE}" "$section" \
            "See [[${sub_rel}|${section} Index]] for all entries."
    fi
}

# --- COMMAND: index-split -------------------------------------------------------
# Partition an oversized wiki/index.md into per-section sub-indexes (#9). The
# root keeps its section headings so external #anchors stay stable; each
# section body moves to its sub-index behind a pointer.

cmd_index_split() {
    header "Splitting wiki/index.md into sub-indexes"
    [[ -f "${INDEX_FILE}" ]] || { error "wiki/index.md not found. Run: vault-tools.sh index-rebuild"; return 2; }
    local threshold="${1:-${INDEX_SPLIT_THRESHOLD}}"
    [[ "$threshold" =~ ^[0-9]+$ ]] || { error "Threshold must be a number, got: ${threshold}"; return 2; }

    local line_count
    line_count=$(wc -l < "${INDEX_FILE}" | tr -d ' ')
    if [[ $line_count -le $threshold ]]; then
        ok "wiki/index.md has ${line_count} lines (threshold: ${threshold}) — no split needed"
        echo ""; return 0
    fi
    if index_split_exists; then
        warning "Split layout already exists but index.md still has ${line_count} lines."
        warning "Move remaining prose manually or run index-rebuild to regenerate."
        echo ""; return 0
    fi

    # Parse the root index: preamble (frontmatter + intro) and sections
    local preamble=() section_order=() current="" line
    declare -A section_body=()
    while IFS= read -r line; do
        if [[ "$line" == "## "* ]]; then
            current="${line#\#\# }"
            section_order+=("$current")
        elif [[ -z "$current" ]]; then
            preamble+=("$line")
        else
            section_body["$current"]+="${line}"$'\n'
        fi
    done < "${INDEX_FILE}"

    # Hand each populated section body off to its sub-index; keep empty /
    # placeholder-only sections in the root untouched.
    local placeholder_re='^_No .* yet\._$'
    declare -A section_split=()
    local other_written="" section body sub_path
    for section in "${section_order[@]}"; do
        body=$(printf '%s' "${section_body[$section]:-}" | _index_trim_blank_edges)
        if [[ -z "$body" ]] || { [[ "$body" =~ $placeholder_re ]] && [[ $(wc -l <<< "$body") -eq 1 ]]; }; then
            continue
        fi
        sub_path=$(index_subindex_for_section "$section")
        if [[ "$sub_path" == */index-other.md && -n "$other_written" ]]; then
            # Additional custom section: append to the shared other sub-index
            { echo ""; echo "## ${section}"; echo ""; echo "$body"; } >> "$sub_path"
        else
            _index_write_subindex "$section" "$body"$'\n'
        fi
        if [[ "$sub_path" == */index-other.md ]]; then
            other_written=1
        fi
        section_split["$section"]="$sub_path"
        ok "Moved '## ${section}' entries to ${sub_path#"${VAULT_ROOT}"/}"
    done

    # Rewrite the root: preamble + same headings, pointers where split
    {
        printf '%s\n' "${preamble[@]}" | _index_trim_blank_edges
        for section in "${section_order[@]}"; do
            printf '\n## %s\n\n' "$section"
            if [[ -n "${section_split[$section]+x}" ]]; then
                echo "See [[${section_split[$section]#"${VAULT_ROOT}"/}|${section} Index]] for all entries."
            else
                printf '%s' "${section_body[$section]:-}" | _index_trim_blank_edges
            fi
        done
    } > "${INDEX_FILE}"
    index_touch_updated "${INDEX_FILE}"

    local new_count
    new_count=$(wc -l < "${INDEX_FILE}" | tr -d ' ')
    if [[ $new_count -gt 200 ]]; then
        warning "Root index still has ${new_count} lines (>200) — trim its prose manually"
    else
        ok "Root index reduced from ${line_count} to ${new_count} lines"
    fi
    echo ""
}
