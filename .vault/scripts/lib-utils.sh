#!/usr/bin/env bash
# ==============================================================================
# LIB-UTILS — Shared utility functions for vault-tools
# ==============================================================================
#
# Provides output formatting, security utilities, and file/directory query
# functions used by all vault-tools command modules.
#
# This file is sourced by vault-tools.sh and expects all configuration
# variables (VAULT_ROOT, WIKI_DIR, RAW_DIR, color codes, thresholds, etc.)
# to be set by the caller before sourcing.
#
# ==============================================================================

# This file is sourced by vault-tools.sh — do not execute directly
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "Source this file, don't execute it directly."; exit 1; }

# ==============================================================================
# OUTPUT FORMATTING
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

# ==============================================================================
# SECURITY UTILITY FUNCTIONS
# ==============================================================================

# Check if a file exceeds the safe processing size limit.
# Returns 0 if the file is too large and should be skipped.
is_oversized() {
    local file_path="$1"
    [[ ! -f "$file_path" ]] && return 1
    local size
    size=$(stat -c%s "$file_path" 2>/dev/null || stat -f%z "$file_path" 2>/dev/null || echo "0")
    [[ "$size" -gt "$MAX_FILE_SIZE_BYTES" ]]
}

# Validate a date string matches YYYY-MM-DD format strictly.
is_valid_date() {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

# Extract frontmatter from a markdown file
# Returns YAML between first two --- delimiters
# SECURITY: Skips symlinks and oversized files
extract_fm() {
    local file="$1"
    [[ ! -f "$file" ]] && return
    # SECURITY: Skip symlinks to prevent path traversal
    [[ -L "$file" ]] && return
    # SECURITY: Skip oversized files to prevent DoS
    if is_oversized "$file"; then
        warning "Skipping oversized file: ${file}"
        return
    fi
    # SECURITY: Limit frontmatter extraction to first 100 lines
    awk '/^---$/{if(++n==2)exit; next} n==1 && NR<=102{print}' "$file"
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

# ==============================================================================
# FILE / DIRECTORY QUERIES
# ==============================================================================

# Count files matching a pattern
# Usage: count_files "wiki/sources" "*.md"
count_files() {
    find "$1" -maxdepth "${MAX_FIND_DEPTH}" ! -type l -name "$2" -type f 2>/dev/null | wc -l | tr -d ' '
}

# Get all wiki markdown files
# Usage: wiki_files
# SECURITY: -maxdepth prevents DoS via deep nesting; ! -type l excludes symlinks
wiki_files() {
    find "${WIKI_DIR}" -maxdepth "${MAX_FIND_DEPTH}" ! -type l -name "*.md" -type f 2>/dev/null | sort
}

# Get all raw files
# Usage: raw_files
raw_files() {
    find "${RAW_DIR}" -maxdepth "${MAX_FIND_DEPTH}" ! -type l -type f ! -name ".gitkeep" 2>/dev/null | sort
}

# Check if a page is referenced by any other page
# Usage: is_linked "wiki/concepts/concept-foo.md"
is_linked() {
    local target_basename
    target_basename=$(basename "$1")
    local count
    # SECURITY: Use grep -Frl for literal matching — filenames may contain
    # regex metacharacters (., *, +, etc.) that grep would interpret as patterns.
    count=$(grep -Frl "$target_basename" "${WIKI_DIR}" 2>/dev/null | grep -Fv "$1" | wc -l | tr -d ' ')
    [[ $count -gt 0 ]]
}
