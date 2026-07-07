#!/usr/bin/env bash
# ==============================================================================
# LIB-BLAME — Page history correlation for vault-tools
# ==============================================================================
#
# Contains the blame command:
#   cmd_blame() — Show the git change history of a vault file and correlate
#                 each commit with the matching wiki/log.md entry, answering
#                 "why does this page say X?"
#
# Uses `git log --follow` so history is tracked across renames. Log entries
# are matched by date against the SR-005 heading format:
#   ## [YYYY-MM-DD] operation | Title
# and refined by file path: entries whose block does not mention the target
# path are labeled "(date match only)".
#
# This file is sourced by vault-tools.sh and depends on functions and
# variables from lib-utils.sh and the entry point configuration.
#
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

# ==============================================================================
# COMMAND: blame
# ==============================================================================
# Usage: vault-tools.sh blame <file-path>
#
# Behavior:
#   - Prints one row per commit: DATE | SHA | AUTHOR | SUMMARY
#   - Beneath each row, lists wiki/log.md entries whose heading date matches
#     the commit date ("log: <operation> | <title>"), or a note when none
#     does. Entries that do not mention the file path in their block are
#     suffixed "(date match only)".
#   - Exit 2 on missing/invalid argument, exit 1 when not in a git repo.

cmd_blame() {
    header "Vault Blame"

    local target="${1:-}"
    if [[ -z "$target" ]]; then
        error "Usage: vault-tools.sh blame <file-path>"
        return 2
    fi

    # Resolve the target: as given (relative to cwd) or relative to VAULT_ROOT
    local abs_path
    if [[ -f "$target" ]]; then
        abs_path="$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"
    elif [[ -f "${VAULT_ROOT}/${target}" ]]; then
        abs_path="${VAULT_ROOT}/${target}"
    else
        error "File not found: ${target}"
        error "Usage: vault-tools.sh blame <file-path>"
        return 2
    fi
    local rel_path="${abs_path#"${VAULT_ROOT}"/}"
    if [[ "$rel_path" == /* ]]; then
        error "File is outside the vault: ${target}"
        return 2
    fi

    if ! git -C "${VAULT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        warning "Not inside a git repository — blame requires git history"
        return 1
    fi

    # %x1f (unit separator) cannot appear in names/summaries, unlike '|'
    local history
    history="$(git -C "${VAULT_ROOT}" log --follow \
        --format="%h%x1f%ad%x1f%an%x1f%s" --date=short -- "$rel_path")"
    if [[ -z "$history" ]]; then
        warning "No git history found for ${rel_path} (not committed yet?)"
        return 0
    fi

    subheader "History for ${rel_path}"
    echo ""
    printf "  %-10s | %-9s | %-20s | %s\n" "DATE" "SHA" "AUTHOR" "SUMMARY"
    printf "  %-10s-+-%-9s-+-%-20s-+-%s\n" "----------" "---------" \
        "--------------------" "----------------------------------------"

    local sha commit_date author summary log_matches log_line
    while IFS=$'\x1f' read -r sha commit_date author summary; do
        printf "  %-10s | %-9s | %-20s | %s\n" \
            "$commit_date" "$sha" "$author" "$summary"

        # Correlate with wiki/log.md entries (SR-005): match headings by
        # date, then check each entry's block for the file path (from the
        # "Files modified" list). Date-only matches are flagged as such.
        # Path detection is a substring test: a block mentioning a longer
        # path that contains this one (e.g. page.md.bak) also counts.
        # The kind is emitted BEFORE the heading so a tab inside a heading
        # title cannot corrupt the field split below.
        log_matches=""
        if [[ -f "${LOG_FILE}" ]]; then
            log_matches="$(awk -v tag="## [${commit_date}]" -v p="$rel_path" '
                /^## \[/ {
                    if (inblk) print (hit ? "path" : "date") "\t" head
                    inblk = (index($0, tag) == 1); head = $0; hit = 0; next
                }
                inblk && index($0, p) { hit = 1 }
                END { if (inblk) print (hit ? "path" : "date") "\t" head }
            ' "${LOG_FILE}" || true)"
        fi
        if [[ -n "$log_matches" ]]; then
            local match_kind suffix
            while IFS=$'\t' read -r match_kind log_line; do
                suffix=""
                [[ "$match_kind" == "date" ]] && suffix=" (date match only)"
                printf "  %-10s |   log: %s%s\n" "" \
                    "${log_line#\#\# \[${commit_date}\] }" "$suffix"
            done <<< "$log_matches"
        else
            printf "  %-10s |   log: (no matching entry)\n" ""
        fi
    done <<< "$history"
    echo ""
}
