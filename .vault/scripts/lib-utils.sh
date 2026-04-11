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

# ==============================================================================
# STALENESS CONFIG LOADER
# ==============================================================================
# Reads .vault/schemas/staleness-config.json and resolves the staleness
# threshold for a given file based on its domain tags and type. Falls back
# to default_threshold_days if no specific override matches. Uses jq when
# available, with a bash-only fallback for the flat JSON shape.
#
# Config file shape (see .vault/schemas/staleness-config.json):
#   {
#     "default_threshold_days": 30,
#     "domain_thresholds": { "domain/engineering": 30, ... },
#     "type_thresholds":   { "type/runbook": 14, ... },
#     "exempt_statuses":   ["archived", "deprecated"]
#   }
# ==============================================================================

_STALE_CONFIG_LOADED=false
_STALE_DEFAULT=30
_STALE_EXEMPT_STATUSES=""
declare -A _STALE_OVERRIDES=()

# Load staleness config once, cache in globals
_load_stale_config() {
    if $_STALE_CONFIG_LOADED; then
        return
    fi
    _STALE_CONFIG_LOADED=true

    local config_file="${VAULT_ROOT}/.vault/schemas/staleness-config.json"
    if [[ ! -f "$config_file" ]]; then
        return
    fi

    if command -v jq &>/dev/null; then
        _STALE_DEFAULT=$(jq -r '.default_threshold_days // 30' "$config_file" 2>/dev/null || echo "30")
        _STALE_EXEMPT_STATUSES=$(jq -r '(.exempt_statuses // []) | join(",")' "$config_file" 2>/dev/null || echo "")
        while IFS='=' read -r key val; do
            [[ -z "$key" ]] && continue
            _STALE_OVERRIDES["$key"]="$val"
        done < <(jq -r '(.domain_thresholds // {}) | to_entries[] | "\(.key)=\(.value)"' "$config_file" 2>/dev/null)
        while IFS='=' read -r key val; do
            [[ -z "$key" ]] && continue
            _STALE_OVERRIDES["$key"]="$val"
        done < <(jq -r '(.type_thresholds // {}) | to_entries[] | "\(.key)=\(.value)"' "$config_file" 2>/dev/null)
    else
        # Bash-only fallback for the flat JSON shape.
        local default_match
        default_match=$(grep -oE '"default_threshold_days"[[:space:]]*:[[:space:]]*[0-9]+' "$config_file" | grep -oE '[0-9]+$')
        [[ -n "$default_match" ]] && _STALE_DEFAULT="$default_match"

        # exempt_statuses: ["archived", "deprecated"]
        local exempt_line
        exempt_line=$(grep -oE '"exempt_statuses"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$config_file")
        if [[ -n "$exempt_line" ]]; then
            _STALE_EXEMPT_STATUSES=$(echo "$exempt_line" | grep -oE '"[a-z][a-z0-9_-]*"' | tr -d '"' | paste -sd',')
        fi

        # Scan for "prefix/value": number entries (both domain_thresholds and type_thresholds)
        while IFS= read -r line; do
            if [[ "$line" =~ \"([a-z][a-z0-9_-]*/[a-z0-9_-]+)\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"
                _STALE_OVERRIDES["$key"]="$val"
            fi
        done < "$config_file"
    fi
}

# Resolve the staleness threshold for a file given its frontmatter.
# Args: $1 = frontmatter blob (output of extract_fm)
# Returns: threshold in days (echoed to stdout)
# Logic: find the minimum of matching type override, matching domain
#        overrides, and the default. Most restrictive wins.
resolve_stale_threshold() {
    local fm="$1"
    _load_stale_config

    local threshold=$_STALE_DEFAULT

    # Check type override: "type/<value>"
    local file_type
    file_type=$(fm_field "type" "$fm")
    if [[ -n "$file_type" && -n "${_STALE_OVERRIDES["type/$file_type"]+x}" ]]; then
        local type_thresh="${_STALE_OVERRIDES["type/$file_type"]}"
        if [[ $type_thresh -lt $threshold ]]; then
            threshold=$type_thresh
        fi
    fi

    # Check domain overrides via the file's tags
    local tags
    tags=$(fm_tags "$fm")
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        if [[ -n "${_STALE_OVERRIDES["$tag"]+x}" ]]; then
            local tag_thresh="${_STALE_OVERRIDES["$tag"]}"
            if [[ $tag_thresh -lt $threshold ]]; then
                threshold=$tag_thresh
            fi
        fi
    done <<< "$tags"

    echo "$threshold"
}

# Return 0 if a status is exempt from staleness checks, 1 otherwise.
is_stale_exempt() {
    local status="$1"
    [[ -z "$status" ]] && return 1
    _load_stale_config
    [[ -z "$_STALE_EXEMPT_STATUSES" ]] && return 1
    case ",$_STALE_EXEMPT_STATUSES," in
        *,"$status",*) return 0 ;;
        *) return 1 ;;
    esac
}
