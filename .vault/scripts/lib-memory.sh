#!/usr/bin/env bash
# ==============================================================================
# LIB-MEMORY — MEMORY.md pointer index tooling for vault-tools
# ==============================================================================
#
# Contains commands for maintaining the root MEMORY.md entry-point file:
#   cmd_memory_refresh() — Regenerate MEMORY.md deterministically from
#                          the current vault state
#
# MEMORY.md is a thin (<200 line) pointer index agents load right after
# CLAUDE.md. It holds pointers only — the full page catalog lives in
# wiki/index.md. It is agent-editable operational state (NOT protected by
# HR-012) and safe to regenerate at any time: two consecutive runs yield
# identical content except the "Refreshed:" date line.
#
# This file is sourced by vault-tools.sh and depends on functions and
# variables from lib-utils.sh and the entry point configuration.
#
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

# ==============================================================================
# COMMAND: memory-refresh
# ==============================================================================
# Regenerate MEMORY.md from the current vault state.
#
# Usage: vault-tools.sh memory-refresh
#
# Sections:
#   Core                  — wiki/index.md, wiki/log.md, memory/status.md
#   Rules                 — hard-rules.md, soft-rules.md, tags.md
#   Latest Lint Report    — newest memory/notes/lint-report-*.md, or "none yet"
#   Recently Active Pages — up to 10 wiki pages by git last-touched date
#                           (index.md/log.md excluded; "none yet" when empty;
#                           a note when the vault is not a git repository)

cmd_memory_refresh() {
    header "Refreshing MEMORY.md"

    local memory_md="${VAULT_ROOT}/MEMORY.md"
    local today
    today=$(date +%Y-%m-%d)

    # --- Latest lint report (gitignored; newest by date-stamped filename) ---
    local lint_line
    local latest_report
    # `|| true`: find exits 1 when memory/notes/ does not exist, which would
    # kill the script through pipefail inside the command substitution.
    latest_report=$(find "${MEMORY_DIR}/notes" -maxdepth 1 ! -type l \
        -name "lint-report-*.md" -type f 2>/dev/null | sort | tail -n 1 || true)
    if [[ -n "$latest_report" ]]; then
        lint_line="- [[${latest_report#"${VAULT_ROOT}"/}]]"
    else
        lint_line="- none yet — run \`bash .vault/scripts/vault-tools.sh lint --report\`"
    fi

    # --- Recently active wiki pages (git last-touched date, newest first) ---
    # One git-log walk over wiki/: the first time a file appears is its most
    # recent touch. Core pointers (index.md, log.md) and files no longer on
    # disk are skipped. Capped at 10 entries for a stable, thin file.
    local active_lines=""
    if git -C "${VAULT_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
        local line current_date="" count=0
        declare -A seen=()
        while IFS= read -r line; do
            [[ $count -ge 10 ]] && break
            if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                current_date="$line"
                continue
            fi
            [[ "$line" == wiki/*.md ]] || continue
            [[ "$line" == "wiki/index.md" || "$line" == "wiki/log.md" ]] && continue
            [[ -n "${seen[$line]+x}" ]] && continue
            [[ -f "${VAULT_ROOT}/${line}" ]] || continue
            seen["$line"]=1
            active_lines+="- [[${line}]] (${current_date})"$'\n'
            count=$((count + 1))
        done < <(git -C "${VAULT_ROOT}" -c core.quotePath=false log \
            --format='%ad' --date=short --name-only -- wiki/ 2>/dev/null)
        [[ -z "$active_lines" ]] && active_lines="- none yet"$'\n'
    else
        active_lines="- not available — vault is not a git repository"$'\n'
    fi

    # --- Write the file ---
    {
        echo "# MEMORY.md — Vault Entry Points"
        echo ""
        echo "Thin pointer index for agents: load this right after \`CLAUDE.md\` to find"
        echo "the vault's key files in one read. Pointers only — the full page catalog"
        echo "lives in [[wiki/index.md]]."
        echo ""
        echo "Refreshed: ${today}"
        echo ""
        echo "## Core"
        echo ""
        echo "- [[wiki/index.md]] — master catalog of all wiki pages"
        echo "- [[wiki/log.md]] — append-only chronological record of all operations"
        echo "- [[memory/status.md]] — current vault health and operational state"
        echo ""
        echo "## Rules"
        echo ""
        echo "- [[.vault/rules/hard-rules.md]] — enforced constraints (violations block commits)"
        echo "- [[.vault/rules/soft-rules.md]] — configurable conventions"
        echo "- [[.vault/rules/tags.md]] — approved tag taxonomy"
        echo ""
        echo "## Latest Lint Report"
        echo ""
        echo "${lint_line}"
        echo ""
        echo "## Recently Active Pages"
        echo ""
        printf '%s' "$active_lines"
        echo ""
        echo "---"
        echo ""
        echo "Generated by \`bash .vault/scripts/vault-tools.sh memory-refresh\` — safe for"
        echo "agents to regenerate at any time."
    } > "$memory_md"

    local total_lines
    total_lines=$(wc -l < "$memory_md" | tr -d ' ')
    ok "MEMORY.md refreshed (${total_lines} lines)"
    echo ""
    return 0
}
