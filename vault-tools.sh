#!/usr/bin/env bash
# ==============================================================================
# VAULT TOOLS — Consolidated CLI for Vault Operations
# ==============================================================================
#
# Provides CLI commands for the three vault operations (INGEST, QUERY, LINT)
# plus utilities for vault management, status reporting, and maintenance.
#
# USAGE:
#   ./vault-tools.sh lint              Run full vault lint
#   ./vault-tools.sh status            Show vault status
#   ./vault-tools.sh validate <file>   Validate a single file
#   ./vault-tools.sh index-rebuild     Rebuild wiki/index.md from scratch
#   ./vault-tools.sh orphans           List orphan pages
#   ./vault-tools.sh stale [days]      List stale pages (default: 30 days)
#   ./vault-tools.sh tag-audit         Audit tag usage across vault
#   ./vault-tools.sh stats             Show vault statistics
#   ./vault-tools.sh init-hooks        Install git hooks
#   ./vault-tools.sh doctor            Full diagnostic check
#
# EXIT CODES:
#   0 — Success
#   1 — Lint violations or errors found
#   2 — Script error
#
# DEPENDENCIES:
#   - bash 4.0+
#   - grep, awk, sed, find, wc, sort, uniq
#   - git
#   - file (for binary detection)
#   - date
#
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

VAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WIKI_DIR="${VAULT_ROOT}/wiki"
RAW_DIR="${VAULT_ROOT}/raw"
MEMORY_DIR="${VAULT_ROOT}/memory"
VAULT_CONFIG="${VAULT_ROOT}/.vault"
TAGS_FILE="${VAULT_CONFIG}/rules/tags.md"
INDEX_FILE="${WIKI_DIR}/index.md"
LOG_FILE="${WIKI_DIR}/log.md"
STATUS_FILE="${MEMORY_DIR}/status.md"

MAX_MARKDOWN_LINES=200
MIN_CODE_LINES=500
DEFAULT_STALE_DAYS=30

# Color output
if [[ "${NO_COLOR:-0}" == "1" ]] || [[ ! -t 1 ]]; then
    RED="" ; GREEN="" ; YELLOW="" ; BLUE="" ; CYAN="" ; RESET=""
else
    RED="\033[0;31m" ; GREEN="\033[0;32m" ; YELLOW="\033[0;33m"
    BLUE="\033[0;34m" ; CYAN="\033[0;36m" ; RESET="\033[0m"
fi

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Print section header
# Usage: header "Vault Lint Report"
header() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}  $1${RESET}"
    echo -e "${CYAN}══════════════════════════════════════════════${RESET}"
    echo ""
}

# Print sub-section
# Usage: subheader "Checking frontmatter"
subheader() {
    echo -e "${BLUE}── $1${RESET}"
}

# Print success
# Usage: ok "All clear"
ok() {
    echo -e "  ${GREEN}✓${RESET} $1"
}

# Print warning
# Usage: warning "File may be stale"
warning() {
    echo -e "  ${YELLOW}⚠${RESET} $1"
}

# Print error
# Usage: error "Missing frontmatter"
error() {
    echo -e "  ${RED}✗${RESET} $1"
}

# Extract frontmatter from a markdown file
# Returns YAML between first two --- delimiters
extract_fm() {
    local file="$1"
    [[ ! -f "$file" ]] && return
    awk '/^---$/{if(++n==2)exit; next} n==1{print}' "$file"
}

# Get a field from frontmatter text
# Usage: fm_field "title" "$frontmatter"
fm_field() {
    echo "$2" | grep -E "^$1:" | head -1 | sed "s/^$1:[[:space:]]*//" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//'
}

# Get tags from frontmatter as newline-separated list
# Usage: fm_tags "$frontmatter"
fm_tags() {
    local fm="$1"
    local in_tags=false
    echo "$fm" | while IFS= read -r line; do
        if [[ "$line" =~ ^tags: ]]; then
            in_tags=true
            if [[ "$line" =~ \[.*\] ]]; then
                echo "$line" | sed 's/tags:[[:space:]]*\[//' | sed 's/\]//' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
                in_tags=false
            fi
            continue
        fi
        if $in_tags; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
                echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/^["'"'"']//' | sed 's/["'"'"']$//'
            elif [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
        fi
    done
}

# Count files matching a pattern
# Usage: count_files "wiki/sources" "*.md"
count_files() {
    find "$1" -name "$2" -type f 2>/dev/null | wc -l | tr -d ' '
}

# Get all wiki markdown files
# Usage: wiki_files
wiki_files() {
    find "${WIKI_DIR}" -name "*.md" -type f 2>/dev/null | sort
}

# Get all raw files
# Usage: raw_files
raw_files() {
    find "${RAW_DIR}" -type f ! -name ".gitkeep" 2>/dev/null | sort
}

# Check if a page is referenced by any other page
# Usage: is_linked "wiki/concepts/concept-foo.md"
is_linked() {
    local target_basename
    target_basename=$(basename "$1")
    local count
    count=$(grep -rl "$target_basename" "${WIKI_DIR}" 2>/dev/null | grep -v "$1" | wc -l | tr -d ' ')
    [[ $count -gt 0 ]]
}

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
        links=$(grep -o '\[\[' "$file" 2>/dev/null | wc -l | tr -d ' ')
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
# COMMAND: tag-audit
# ==============================================================================
# Audit tag usage: find unapproved tags, unused approved tags, and distribution.

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

        [[ -n "$title" ]] && ok "Title: ${title}" || { error "Missing title"; violations=$((violations+1)); }
        [[ -n "$type" ]] && ok "Type: ${type}" || { error "Missing type"; violations=$((violations+1)); }
        [[ -n "$created" ]] && ok "Created: ${created}" || { error "Missing created"; violations=$((violations+1)); }
        [[ -n "$updated" ]] && ok "Updated: ${updated}" || { error "Missing updated"; violations=$((violations+1)); }
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
    cmd_tag_audit 2>/dev/null | grep -c "Unapproved tag" | read -r unapproved || unapproved=0
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
            if ! grep -q "$basename" "${INDEX_FILE}" 2>/dev/null; then
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

    if [[ -f "$src" ]]; then
        cp "$src" "$dst"
        chmod +x "$dst"
        ok "Installed pre-commit hook"
    else
        error "Hook source not found: ${src}"
        exit 2
    fi

    echo ""
}

# ==============================================================================
# COMMAND: doctor
# ==============================================================================
# Full diagnostic — checks structure, config, hooks, and content health.

cmd_doctor() {
    header "Vault Doctor — Full Diagnostic"

    subheader "Directory Structure"
    local required_dirs=("raw" "wiki" "wiki/sources" "wiki/entities" "wiki/concepts" "wiki/comparisons" "memory" "memory/decisions" "memory/logs" "memory/notes" ".vault" ".vault/rules" ".vault/schemas" ".vault/hooks" ".vault/scripts" "templates" "docs")
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
    if [[ -x "${VAULT_ROOT}/.git/hooks/pre-commit" ]]; then
        ok "pre-commit hook installed and executable"
    else
        warning "pre-commit hook not installed. Run: vault-tools.sh init-hooks"
    fi

    subheader "Template Files"
    local template_count
    template_count=$(count_files "${VAULT_ROOT}/templates" "*.md")
    echo "  Templates found: ${template_count}"

    # Run lint
    subheader "Running lint..."
    cmd_lint || true

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

# ==============================================================================
# HELP
# ==============================================================================

cmd_help() {
    echo ""
    echo "Vault Tools — CLI for Vault Operations"
    echo ""
    echo "Usage: vault-tools.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  lint              Run full vault lint"
    echo "  status            Show vault status"
    echo "  stats             Show detailed vault statistics"
    echo "  validate <file>   Validate a single file"
    echo "  orphans           List orphan pages"
    echo "  stale [days]      List stale pages (default: 30)"
    echo "  tag-audit         Audit tag usage"
    echo "  index-rebuild     Rebuild wiki/index.md"
    echo "  init-hooks        Install git hooks"
    echo "  doctor            Full diagnostic check"
    echo "  help              Show this help"
    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        lint)           cmd_lint "$@" ;;
        status)         cmd_status "$@" ;;
        stats)          cmd_stats "$@" ;;
        validate)       cmd_validate "$@" ;;
        orphans)        cmd_orphans "$@" ;;
        stale)          cmd_stale "$@" ;;
        tag-audit)      cmd_tag_audit "$@" ;;
        index-rebuild)  cmd_index_rebuild "$@" ;;
        init-hooks)     cmd_init_hooks "$@" ;;
        doctor)         cmd_doctor "$@" ;;
        help|--help|-h) cmd_help "$@" ;;
        *)
            error "Unknown command: ${command}"
            cmd_help
            exit 2
            ;;
    esac
}

main "$@"
