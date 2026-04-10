#!/usr/bin/env bash
# ==============================================================================
# VAULT PRE-COMMIT HOOK — Utility Functions Library
# ==============================================================================
#
# This file contains all utility functions used by the pre-commit hook checks.
# It is sourced by pre-commit.sh and should not be executed directly.
#
# CONTENTS:
#   - Violation tracking (violation, info, warn, success)
#   - File inspection (is_exempt, get_extension, extension_in_list)
#   - Frontmatter parsing (extract_frontmatter, get_frontmatter_field,
#     get_frontmatter_tags, get_approved_tags)
#   - Binary detection (is_binary)
#   - Line counting (count_lines)
#   - Date utilities (today_date, date_diff)
#   - Security utilities (is_oversized, is_symlink, is_within_vault,
#     is_valid_date)
#   - Git helpers (get_staged_files)
#
# ==============================================================================

# ==============================================================================
# VIOLATION TRACKING
# ==============================================================================

# Track violations globally
VIOLATIONS=0
VIOLATION_MESSAGES=()

# ==============================================================================
# LOGGING FUNCTIONS
# ==============================================================================

# Log a violation with rule ID and file path
# Usage: violation "HR-001" "file.md" "Description of the violation"
violation() {
    local rule_id="$1"
    local file_path="$2"
    local message="$3"
    VIOLATIONS=$((VIOLATIONS + 1))
    VIOLATION_MESSAGES+=("${RED}[${rule_id}]${RESET} ${file_path}: ${message}")
}

# Log an informational message
# Usage: info "Processing file.md"
info() {
    echo -e "${BLUE}[INFO]${RESET} $1"
}

# Log a warning (non-blocking)
# Usage: warn "File may have issues"
warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

# Log a success message
# Usage: success "All checks passed"
success() {
    echo -e "${GREEN}[PASS]${RESET} $1"
}

# ==============================================================================
# FILE INSPECTION UTILITIES
# ==============================================================================

# Check if a file path matches any exempt pattern
# Usage: is_exempt "wiki/index.md"
# Returns: 0 if exempt, 1 if not
is_exempt() {
    local file_path="$1"
    for exempt in "${EXEMPT_FILES[@]}"; do
        if [[ "$file_path" == "$exempt" ]]; then
            return 0
        fi
    done
    # Library files (lib-*.sh) and individual check/audit modules are sourced by entry points
    local basename
    basename=$(basename "$file_path")
    if [[ "$basename" == lib-*.sh ]] || [[ "$file_path" == *"/checks/"*.sh ]] || [[ "$file_path" == *"/audits/"*.sh ]]; then
        return 0
    fi
    return 1
}

# Get file extension (lowercase)
# Usage: get_extension "file.MD" => "md"
get_extension() {
    local filename="$1"
    local ext="${filename##*.}"
    echo "${ext,,}"
}

# Check if extension is in a list
# Usage: extension_in_list "sh" "${CODE_EXTENSIONS[@]}"
extension_in_list() {
    local ext="$1"
    shift
    local list=("$@")
    for item in "${list[@]}"; do
        if [[ "$ext" == "$item" ]]; then
            return 0
        fi
    done
    return 1
}

# ==============================================================================
# FRONTMATTER PARSING
# ==============================================================================

# Extract YAML frontmatter from a markdown file
# Usage: extract_frontmatter "file.md"
# Returns: The YAML content between --- delimiters, or empty string
extract_frontmatter() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        echo ""
        return
    fi
    # SECURITY: Skip symlinks to prevent path traversal
    if is_symlink "$file_path"; then
        warn "Skipping symlink: ${file_path}"
        echo ""
        return
    fi
    # SECURITY: Skip oversized files to prevent DoS
    if is_oversized "$file_path"; then
        warn "Skipping oversized file: ${file_path}"
        echo ""
        return
    fi
    # Read the file and extract content between first and second ---
    # SECURITY: Limit frontmatter to 100 lines to prevent memory exhaustion
    local in_frontmatter=false
    local frontmatter=""
    local fm_lines=0
    local max_fm_lines=100
    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            if $in_frontmatter; then
                # End of frontmatter
                echo "$frontmatter"
                return
            else
                # Start of frontmatter
                in_frontmatter=true
                continue
            fi
        fi
        if $in_frontmatter; then
            fm_lines=$((fm_lines + 1))
            if [[ $fm_lines -gt $max_fm_lines ]]; then
                warn "Frontmatter exceeds ${max_fm_lines} lines, truncating: ${file_path}"
                echo "$frontmatter"
                return
            fi
            frontmatter="${frontmatter}${line}"$'\n'
        fi
    done < "$file_path"
    # If we never found closing ---, frontmatter is invalid
    echo ""
}

# Extract a specific field value from YAML frontmatter
# Usage: get_frontmatter_field "title" "$frontmatter_content"
# Returns: The field value or empty string
get_frontmatter_field() {
    local field_name="$1"
    local frontmatter="$2"
    echo "$frontmatter" | grep -E "^${field_name}:" | head -1 | sed "s/^${field_name}:[[:space:]]*//" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//'
}

# Extract tags list from YAML frontmatter
# Usage: get_frontmatter_tags "$frontmatter_content"
# Returns: One tag per line
get_frontmatter_tags() {
    local frontmatter="$1"
    local in_tags=false
    echo "$frontmatter" | while IFS= read -r line; do
        if [[ "$line" =~ ^tags: ]]; then
            in_tags=true
            # Check for inline tags: tags: [tag1, tag2]
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
                # Next field started, stop reading tags
                break
            fi
        fi
    done
}

# Get the list of approved tag prefixes from tags.md
# Usage: get_approved_tags
# Returns: One approved tag per line
get_approved_tags() {
    if [[ ! -f "${VAULT_ROOT}/${TAGS_FILE}" ]]; then
        warn "Tags file not found at ${TAGS_FILE}. Skipping tag validation."
        return
    fi
    grep -E '^\- `[a-z]+/[a-z0-9-]+`' "${VAULT_ROOT}/${TAGS_FILE}" | sed 's/^- `//' | sed 's/`.*//'
}

# ==============================================================================
# BINARY DETECTION
# ==============================================================================

# Check if a file is binary
# Usage: is_binary "file.pdf"
# Returns: 0 if binary, 1 if text
is_binary() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        return 1
    fi
    local file_type
    file_type=$(file --mime-type -b "$file_path" 2>/dev/null || echo "unknown")
    case "$file_type" in
        text/*|application/json|application/xml|application/javascript)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# ==============================================================================
# LINE COUNTING AND DATE UTILITIES
# ==============================================================================

# Count lines in a file
# Usage: count_lines "file.md"
count_lines() {
    wc -l < "$1" 2>/dev/null || echo "0"
}

# Get today's date in ISO format
# Usage: today_date => "2026-04-10"
today_date() {
    date +%Y-%m-%d
}

# Calculate date difference in days
# Usage: date_diff "2026-04-10" "2026-04-08" => 2
date_diff() {
    local date1="$1"
    local date2="$2"
    # SECURITY: Validate date format before passing to date -d.
    # Malicious frontmatter could craft values like "TZ=X date" or other
    # strings that cause unexpected behavior when parsed by GNU date.
    if ! is_valid_date "$date1" || ! is_valid_date "$date2"; then
        echo "999"
        return
    fi
    local ts1 ts2
    ts1=$(date -d "$date1" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$date1" +%s 2>/dev/null || echo "0")
    ts2=$(date -d "$date2" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$date2" +%s 2>/dev/null || echo "0")
    if [[ "$ts1" == "0" ]] || [[ "$ts2" == "0" ]]; then
        echo "999"
        return
    fi
    local diff=$(( (ts1 - ts2) ))
    if [[ $diff -lt 0 ]]; then
        diff=$(( -diff ))
    fi
    echo $(( diff / 86400 ))
}

# ==============================================================================
# SECURITY UTILITY FUNCTIONS
# ==============================================================================

# Check if a file exceeds the safe processing size limit.
# Returns 0 if the file is too large and should be skipped.
# Usage: is_oversized "/path/to/file"
is_oversized() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        return 1
    fi
    local size
    size=$(stat -c%s "$file_path" 2>/dev/null || stat -f%z "$file_path" 2>/dev/null || echo "0")
    [[ "$size" -gt "$MAX_FILE_SIZE_BYTES" ]]
}

# Check if a path is a symlink. Symlinks in wiki/ or memory/ are a path
# traversal risk because they can point outside the vault.
# Returns 0 if the path is a symlink, 1 otherwise.
# Usage: is_symlink "/path/to/file"
is_symlink() {
    [[ -L "$1" ]]
}

# Validate that a resolved file path is within the vault root.
# Prevents path traversal via symlinks or ../.. sequences.
# Returns 0 if safe, 1 if the file escapes the vault.
# Usage: is_within_vault "/path/to/file"
is_within_vault() {
    local file_path="$1"
    local resolved
    resolved=$(readlink -f "$file_path" 2>/dev/null || realpath "$file_path" 2>/dev/null || echo "")
    if [[ -z "$resolved" ]]; then
        return 1
    fi
    local vault_resolved
    vault_resolved=$(readlink -f "$VAULT_ROOT" 2>/dev/null || realpath "$VAULT_ROOT" 2>/dev/null)
    # Use trailing slash to prevent sibling directory prefix match
    # e.g., /home/user/vault must not match /home/user/vault-backup
    [[ "$resolved" == "${vault_resolved}/"* ]] || [[ "$resolved" == "${vault_resolved}" ]]
}

# Validate a date string matches YYYY-MM-DD format strictly.
# Prevents injection via date -d with crafted values.
# Returns 0 if valid, 1 otherwise.
# Usage: is_valid_date "2026-04-10"
is_valid_date() {
    local date_str="$1"
    [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

# ==============================================================================
# GIT HELPERS
# ==============================================================================

# Get list of staged files (added, modified, renamed)
# Excludes deleted files since they don't need validation
get_staged_files() {
    git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true
}
