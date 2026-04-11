#!/usr/bin/env bash
# ==============================================================================
# LIB-MANAGE — Management commands for vault-tools
# ==============================================================================
#
# Contains commands for vault management and maintenance:
#   cmd_stats()          — Vault statistics (file counts, tags, links)
#   cmd_status()         — Vault status overview
#   cmd_doctor()         — Full diagnostic check
#   cmd_init_hooks()     — Git hook installation
#   cmd_index_rebuild()  — wiki/index.md regeneration
#
# This file is sourced by vault-tools.sh and depends on functions and
# variables from lib-utils.sh and the entry point configuration.
#
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

# ==============================================================================
# COMMAND: stats
# ==============================================================================
# Show vault statistics — file counts, tag distribution, link density.

cmd_stats() {
    header "Vault Statistics"

    local total_raw total_wiki total_sources total_concepts total_entities total_comparisons total_decisions total_memory
    total_raw=$(count_files "${RAW_DIR}" "*" )
    total_wiki=$(count_files "${WIKI_DIR}" "*.md")
    total_sources=$(count_files "${WIKI_DIR}/sources" "*.md")
    total_concepts=$(count_files "${WIKI_DIR}/concepts" "*.md")
    total_entities=$(count_files "${WIKI_DIR}/entities" "*.md")
    total_comparisons=$(count_files "${WIKI_DIR}/comparisons" "*.md")
    total_decisions=$(count_files "${MEMORY_DIR}/decisions" "*.md")
    total_memory=$(count_files "${MEMORY_DIR}" "*.md")

    subheader "File Counts"
    echo "  Raw sources:      ${total_raw}"
    echo "  Wiki pages:       ${total_wiki}"
    echo "    Sources:        ${total_sources}"
    echo "    Concepts:       ${total_concepts}"
    echo "    Entities:       ${total_entities}"
    echo "    Comparisons:    ${total_comparisons}"
    echo "  Memory files:     ${total_memory}"
    echo "    Decisions:      ${total_decisions}"

    # Count total words in wiki
    subheader "Content Volume"
    local total_words=0
    while IFS= read -r file; do
        local words
        words=$(wc -w < "$file" 2>/dev/null || echo 0)
        total_words=$((total_words + words))
    done < <(wiki_files)
    echo "  Total wiki words: ${total_words}"
    echo "  Avg words/page:   $(( total_wiki > 0 ? total_words / total_wiki : 0 ))"

    # Tag distribution
    subheader "Tag Distribution (top 20 prefixes)"
    local tag_counts_file
    tag_counts_file=$(mktemp)
    while IFS= read -r file; do
        local fm
        fm=$(extract_fm "$file")
        [[ -z "$fm" ]] && continue
        fm_tags "$fm"
    done < <(wiki_files) | sed 's|/.*||' | sort | uniq -c | sort -rn | head -20 > "$tag_counts_file"

    if [[ -s "$tag_counts_file" ]]; then
        while IFS= read -r line; do
            echo "    $line"
        done < "$tag_counts_file"
    else
        echo "    (no tags found)"
    fi
    rm -f "$tag_counts_file"

    # Link density
    subheader "Link Density"
    local total_links=0
    local pages_with_links=0
    while IFS= read -r file; do
        local links
        links=$( { grep -o '\[\[' "$file" 2>/dev/null || true; } | wc -l | tr -d ' ')
        total_links=$((total_links + links))
        if [[ $links -gt 0 ]]; then
            pages_with_links=$((pages_with_links + 1))
        fi
    done < <(wiki_files)
    echo "  Total wikilinks:     ${total_links}"
    echo "  Pages with links:    ${pages_with_links}/${total_wiki}"
    echo "  Avg links/page:      $(( total_wiki > 0 ? total_links / total_wiki : 0 ))"

    echo ""
}

# ==============================================================================
# COMMAND: status
# ==============================================================================
# Show current vault health and status.

cmd_status() {
    header "Vault Status"

    subheader "Counts"
    echo "  Raw sources:   $(count_files "${RAW_DIR}" "*")"
    echo "  Wiki pages:    $(count_files "${WIKI_DIR}" "*.md")"
    echo "  Memory files:  $(count_files "${MEMORY_DIR}" "*.md")"

    subheader "Git Status"
    if git -C "${VAULT_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
        local branch
        branch=$(git -C "${VAULT_ROOT}" branch --show-current 2>/dev/null || echo "unknown")
        local uncommitted
        uncommitted=$(git -C "${VAULT_ROOT}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        echo "  Branch:        ${branch}"
        echo "  Uncommitted:   ${uncommitted} file(s)"
        local last_commit
        last_commit=$(git -C "${VAULT_ROOT}" log -1 --format="%ai" 2>/dev/null || echo "unknown")
        echo "  Last commit:   ${last_commit}"
    else
        warning "Not a git repository"
    fi

    subheader "Health"
    local has_claude_md="no"
    [[ -f "${VAULT_ROOT}/CLAUDE.md" ]] && has_claude_md="yes"
    local has_index="no"
    [[ -f "${INDEX_FILE}" ]] && has_index="yes"
    local has_log="no"
    [[ -f "${LOG_FILE}" ]] && has_log="yes"
    local has_tags="no"
    [[ -f "${TAGS_FILE}" ]] && has_tags="yes"

    echo "  CLAUDE.md:     ${has_claude_md}"
    echo "  wiki/index.md: ${has_index}"
    echo "  wiki/log.md:   ${has_log}"
    echo "  tags.md:       ${has_tags}"
    echo ""
}

# ==============================================================================
# COMMAND: init-hooks
# ==============================================================================
# Install git hooks.

cmd_init_hooks() {
    header "Installing Git Hooks"

    local hooks_dir="${VAULT_ROOT}/.git/hooks"
    if [[ ! -d "$hooks_dir" ]]; then
        error "Not a git repository. Run 'git init' first."
        exit 2
    fi

    local src="${VAULT_CONFIG}/hooks/pre-commit.sh"
    local dst="${hooks_dir}/pre-commit"

    if [[ ! -f "$src" ]]; then
        error "Hook source not found: ${src}"
        exit 2
    fi

    # Install a wrapper that execs the real script from .vault/hooks/.
    # A flat cp would break the hook: pre-commit.sh resolves its libraries
    # via BASH_SOURCE, which after copy points at .git/hooks/ where
    # lib-hook-utils.sh and checks/ do not exist, so every commit fails
    # with an opaque source error before any check runs.
    cat > "$dst" <<'HOOK'
#!/usr/bin/env bash
# vault-tools:pre-commit-wrapper v1
# Auto-generated by vault-tools.sh init-hooks. Do not edit.
# Delegates to .vault/hooks/pre-commit.sh so its BASH_SOURCE-based
# library resolution still finds lib-hook-utils.sh and checks/*.sh.
# Invoked via `bash` (not `exec $script`) so that the delegated
# script does not need to be marked executable — source files in
# .vault/hooks/ are tracked as non-executable in git.
set -euo pipefail
VAULT_ROOT="$(git rev-parse --show-toplevel)"
exec bash "${VAULT_ROOT}/.vault/hooks/pre-commit.sh" "$@"
HOOK
    chmod +x "$dst"
    ok "Installed pre-commit hook (wrapper → .vault/hooks/pre-commit.sh)"

    echo ""
}

# ==============================================================================
# COMMAND: doctor
# ==============================================================================
# Full diagnostic — checks structure, config, hooks, and content health.

cmd_doctor() {
    header "Vault Doctor — Full Diagnostic"

    subheader "Directory Structure"
    local required_dirs=("raw" "wiki" "wiki/sources" "wiki/entities" "wiki/concepts" "wiki/comparisons" "memory" "memory/decisions" "memory/logs" "memory/notes" ".vault" ".vault/rules" ".vault/schemas" ".vault/hooks" ".vault/hooks/checks" ".vault/scripts" ".vault/scripts/audits" "templates" "docs")
    for dir in "${required_dirs[@]}"; do
        if [[ -d "${VAULT_ROOT}/${dir}" ]]; then
            ok "${dir}/"
        else
            error "${dir}/ — MISSING"
        fi
    done

    subheader "Required Files"
    local required_files=("CLAUDE.md" "AGENTS.md" "wiki/index.md" "wiki/log.md" "memory/status.md" ".vault/rules/hard-rules.md" ".vault/rules/soft-rules.md" ".vault/rules/tags.md" ".vault/schemas/frontmatter.md")
    for file in "${required_files[@]}"; do
        if [[ -f "${VAULT_ROOT}/${file}" ]]; then
            ok "${file}"
        else
            error "${file} — MISSING"
        fi
    done

    subheader "Git Hooks"
    local hook_path="${VAULT_ROOT}/.git/hooks/pre-commit"
    if [[ ! -x "$hook_path" ]]; then
        warning "pre-commit hook not installed. Run: vault-tools.sh init-hooks"
    elif ! grep -q 'vault-tools:pre-commit-wrapper' "$hook_path"; then
        error "pre-commit hook is a legacy flat copy (will silently fail). Reinstall: vault-tools.sh init-hooks"
    else
        # Dry-run the hook with no staged files to verify it can source its
        # libraries. If BASH_SOURCE-based library resolution is broken, the
        # source line prints "No such file or directory" on stderr even
        # before any check runs.
        local hook_out
        hook_out="$(cd "${VAULT_ROOT}" && "$hook_path" </dev/null 2>&1 || true)"
        if echo "$hook_out" | grep -q 'No such file or directory\|command not found'; then
            error "pre-commit hook fails to source its libraries:"
            echo "$hook_out" | sed 's/^/      /'
        else
            ok "pre-commit hook installed and functional"
        fi
    fi

    subheader "Template Files"
    local template_count
    template_count=$(count_files "${VAULT_ROOT}/templates" "*.md")
    echo "  Templates found: ${template_count}"

    # Run lint with report output so memory/notes/ always has a fresh
    # lint-report-YYYY-MM-DD.md after doctor runs.
    subheader "Running lint..."
    cmd_lint --report || true

    echo ""
    ok "Doctor complete"
}

# ==============================================================================
# COMMAND: index-rebuild
# ==============================================================================
# Rebuild wiki/index.md by scanning all wiki pages.

cmd_index_rebuild() {
    header "Rebuilding wiki/index.md"

    local output=""
    output+="---\n"
    output+="title: \"Vault Index\"\n"
    output+="type: index\n"
    output+="created: $(date +%Y-%m-%d)\n"
    output+="updated: $(date +%Y-%m-%d)\n"
    output+="status: active\n"
    output+="tags:\n"
    output+="  - type/index\n"
    output+="  - lifecycle/active\n"
    output+="  - agent/generated\n"
    output+="---\n\n"
    output+="# Vault Index\n\n"

    # Collect pages by type
    declare -A type_pages
    while IFS= read -r file; do
        local relative="${file#${VAULT_ROOT}/}"
        [[ "$relative" == "wiki/index.md" ]] && continue
        [[ "$relative" == "wiki/log.md" ]] && continue

        local fm
        fm=$(extract_fm "$file")
        [[ -z "$fm" ]] && continue

        local title type summary
        title=$(fm_field "title" "$fm")
        type=$(fm_field "type" "$fm")
        summary=$(fm_field "summary" "$fm")
        [[ -z "$title" ]] && title="$relative"
        [[ -z "$type" ]] && type="uncategorized"
        [[ -z "$summary" ]] && summary="(no summary)"

        type_pages["$type"]+="- [[${relative}|${title}]] — ${summary}\n"
    done < <(wiki_files)

    # Output by type
    for type in source concept entity comparison decision report evaluation; do
        local section_title
        case "$type" in
            source) section_title="Sources" ;;
            concept) section_title="Concepts" ;;
            entity) section_title="Entities" ;;
            comparison) section_title="Comparisons" ;;
            decision) section_title="Decisions" ;;
            report) section_title="Reports" ;;
            evaluation) section_title="Evaluations" ;;
            *) section_title="Other" ;;
        esac
        output+="## ${section_title}\n\n"
        if [[ -n "${type_pages[$type]+x}" ]]; then
            output+="${type_pages[$type]}\n"
        else
            output+="_No ${section_title,,} yet._\n\n"
        fi
    done

    echo -e "$output" > "${INDEX_FILE}"
    ok "Index rebuilt with entries from $(count_files "${WIKI_DIR}" "*.md") wiki pages"
    echo ""
}
