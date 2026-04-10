#!/usr/bin/env bash
# ==============================================================================
# VAULT PRE-COMMIT HOOK — Consolidated Enforcement of All Hard Rules
# ==============================================================================
#
# This script runs before every git commit. It validates all staged files against
# the vault's hard rules defined in .vault/rules/hard-rules.md. Any violation
# causes the commit to be rejected with a clear error message.
#
# INSTALLATION:
#   cp .vault/hooks/pre-commit.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Or use the init script which sets this up automatically:
#   .vault/scripts/init.sh
#
# RULES ENFORCED:
#   HR-001: Raw directory immutability
#   HR-002: Mandatory frontmatter
#   HR-003: Mandatory tags
#   HR-004: Markdown length limit (200 lines)
#   HR-005: Code file minimum length (500 lines)
#   HR-006: Unique page titles
#   HR-007: Updated field accuracy
#   HR-008: Index registration
#   HR-009: Flat tag notation
#   HR-010: Binary file quarantine
#
# EXIT CODES:
#   0 — All checks passed
#   1 — One or more hard rule violations detected
#   2 — Script error (missing dependencies, malformed config)
#
# DEPENDENCIES:
#   - bash 4.0+
#   - grep (GNU or BSD)
#   - awk
#   - sed
#   - date
#   - file (for binary detection)
#   - python3 (optional — required for skill hardening enforcement)
#
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Vault root is the git repository root
VAULT_ROOT="$(git rev-parse --show-toplevel)"

# Directories
RAW_DIR="raw"
WIKI_DIR="wiki"
MEMORY_DIR="memory"
VAULT_CONFIG_DIR=".vault"
SCRIPTS_DIR=".vault/scripts"
HOOKS_DIR=".vault/hooks"
TEMPLATES_DIR="templates"

# Hard rule thresholds
MAX_MARKDOWN_LINES=200
MIN_CODE_LINES=500

# Files exempt from line count rules
EXEMPT_FILES=(
    "wiki/index.md"
    "wiki/log.md"
    ".vault/hooks/pre-commit.sh"
    ".vault/scripts/init.sh"
    ".vault/scripts/vault-tools.sh"
)

# File extensions considered "code" for HR-005
CODE_EXTENSIONS=("sh" "py" "js" "ts" "rb" "go" "rs" "java" "pl" "lua")

# File extensions considered "markdown" for HR-004
MARKDOWN_EXTENSIONS=("md" "markdown")

# File extensions considered "config" and exempt from code length rules
CONFIG_EXTENSIONS=("json" "yaml" "yml" "toml" "ini" "cfg" "env" "gitignore" "gitkeep")

# Tags file location
TAGS_FILE="${VAULT_CONFIG_DIR}/rules/tags.md"

# Index file location
INDEX_FILE="${WIKI_DIR}/index.md"

# Date tolerance for HR-007 (days)
DATE_TOLERANCE=1

# ==============================================================================
# SECURITY THRESHOLDS
# ==============================================================================
# Maximum file size (in bytes) to process. Files exceeding this are skipped
# to prevent denial-of-service via enormous frontmatter or line counting.
MAX_FILE_SIZE_BYTES=1048576  # 1 MB

# Maximum find depth to prevent deeply nested directory traversal attacks
MAX_FIND_DEPTH=10

# Color output (disable with NO_COLOR=1)
if [[ "${NO_COLOR:-0}" == "1" ]] || [[ ! -t 1 ]]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    RESET=""
else
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[0;33m"
    BLUE="\033[0;34m"
    RESET="\033[0m"
fi

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Track violations globally
VIOLATIONS=0
VIOLATION_MESSAGES=()

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
# GET STAGED FILES
# ==============================================================================

# Get list of staged files (added, modified, renamed)
# Excludes deleted files since they don't need validation
get_staged_files() {
    git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true
}

# ==============================================================================
# HR-001: RAW DIRECTORY IMMUTABILITY
# ==============================================================================
# No agent may modify files in raw/. Only human commits (prefixed [human]) are allowed.

check_hr001() {
    info "HR-001: Checking raw/ directory immutability..."
    local commit_msg
    commit_msg=$(cat "${VAULT_ROOT}/.git/COMMIT_EDITMSG" 2>/dev/null || echo "")

    # If commit message starts with [human], allow raw/ modifications
    if [[ "$commit_msg" == "[human]"* ]]; then
        success "HR-001: Human commit detected, raw/ modifications allowed"
        return
    fi

    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if [[ "$file" == "${RAW_DIR}/"* ]]; then
            # Also check deleted files in raw/
            violation "HR-001" "$file" "Raw directory is immutable. Only [human] prefixed commits may modify raw/."
        fi
    done <<< "$staged_files"

    # Also check deleted files
    local deleted_files
    deleted_files=$(git diff --cached --name-only --diff-filter=D 2>/dev/null || true)
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if [[ "$file" == "${RAW_DIR}/"* ]]; then
            violation "HR-001" "$file" "Cannot delete files from raw/. Raw directory is immutable."
        fi
    done <<< "$deleted_files"

    if [[ $VIOLATIONS -eq 0 ]]; then
        success "HR-001: Raw directory intact"
    fi
}

# ==============================================================================
# HR-002: MANDATORY FRONTMATTER
# ==============================================================================
# Every .md file in wiki/ must have valid YAML frontmatter with required fields.

check_hr002() {
    info "HR-002: Checking mandatory frontmatter..."
    local staged_files
    staged_files=$(get_staged_files)
    local required_fields=("title" "type" "created" "updated" "status" "tags")
    local valid_types=("concept" "entity" "source" "comparison" "decision" "report" "index" "evaluation")
    local valid_statuses=("draft" "active" "review" "archived" "deprecated")

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        # Only check wiki/ markdown files
        local ext
        ext=$(get_extension "$file")
        if [[ "$file" != "${WIKI_DIR}/"* ]] || ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        # Check file starts with ---
        local first_line
        first_line=$(head -1 "$full_path" 2>/dev/null || echo "")
        if [[ "$first_line" != "---" ]]; then
            violation "HR-002" "$file" "Missing YAML frontmatter. File must start with ---"
            continue
        fi

        local frontmatter
        frontmatter=$(extract_frontmatter "$full_path")
        if [[ -z "$frontmatter" ]]; then
            violation "HR-002" "$file" "Invalid frontmatter. No closing --- found."
            continue
        fi

        # Check each required field exists
        for field in "${required_fields[@]}"; do
            local value
            value=$(get_frontmatter_field "$field" "$frontmatter")
            if [[ -z "$value" ]] && [[ "$field" != "tags" ]]; then
                violation "HR-002" "$file" "Missing required frontmatter field: ${field}"
            fi
        done

        # Validate type enum
        local type_value
        type_value=$(get_frontmatter_field "type" "$frontmatter")
        if [[ -n "$type_value" ]]; then
            local type_valid=false
            for valid_type in "${valid_types[@]}"; do
                if [[ "$type_value" == "$valid_type" ]]; then
                    type_valid=true
                    break
                fi
            done
            if ! $type_valid; then
                violation "HR-002" "$file" "Invalid type '${type_value}'. Must be one of: ${valid_types[*]}"
            fi
        fi

        # Validate status enum
        local status_value
        status_value=$(get_frontmatter_field "status" "$frontmatter")
        if [[ -n "$status_value" ]]; then
            local status_valid=false
            for valid_status in "${valid_statuses[@]}"; do
                if [[ "$status_value" == "$valid_status" ]]; then
                    status_valid=true
                    break
                fi
            done
            if ! $status_valid; then
                violation "HR-002" "$file" "Invalid status '${status_value}'. Must be one of: ${valid_statuses[*]}"
            fi
        fi

    done <<< "$staged_files"

    success "HR-002: Frontmatter check complete"
}

# ==============================================================================
# HR-003: MANDATORY TAGS
# ==============================================================================
# Every wiki/ file must have at least one tag from the approved taxonomy.

check_hr003() {
    info "HR-003: Checking mandatory tags..."
    local staged_files
    staged_files=$(get_staged_files)

    # Load approved tags from taxonomy for validation
    local approved_tags=""
    if [[ -f "${VAULT_ROOT}/${TAGS_FILE}" ]]; then
        approved_tags=$(get_approved_tags)
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")
        if [[ "$file" != "${WIKI_DIR}/"* ]] || ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local frontmatter
        frontmatter=$(extract_frontmatter "$full_path")
        [[ -z "$frontmatter" ]] && continue

        local tags
        tags=$(get_frontmatter_tags "$frontmatter")
        if [[ -z "$tags" ]]; then
            violation "HR-003" "$file" "No tags found. Every wiki page must have at least one approved tag."
            continue
        fi

        # Validate each tag against approved taxonomy if available
        if [[ -n "$approved_tags" ]]; then
            local has_approved_tag=false
            while IFS= read -r tag; do
                [[ -z "$tag" ]] && continue
                if echo "$approved_tags" | grep -qxF "$tag"; then
                    has_approved_tag=true
                fi
            done <<< "$tags"
            if ! $has_approved_tag; then
                violation "HR-003" "$file" "No approved tags found. Tags must be from the taxonomy in ${TAGS_FILE}."
            fi
        fi
    done <<< "$staged_files"

    success "HR-003: Tag presence check complete"
}

# ==============================================================================
# HR-004: MARKDOWN LENGTH LIMIT
# ==============================================================================
# No markdown file in wiki/ or memory/ may exceed 200 lines.

check_hr004() {
    info "HR-004: Checking markdown length limits (max ${MAX_MARKDOWN_LINES} lines)..."
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")

        # Only check wiki/ and memory/ markdown files
        if [[ "$file" != "${WIKI_DIR}/"* ]] && [[ "$file" != "${MEMORY_DIR}/"* ]]; then
            continue
        fi
        if ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        # Check exemptions
        if is_exempt "$file"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local line_count
        line_count=$(count_lines "$full_path")
        if [[ $line_count -gt $MAX_MARKDOWN_LINES ]]; then
            violation "HR-004" "$file" "Exceeds ${MAX_MARKDOWN_LINES} line limit (has ${line_count} lines). Split into linked sub-pages."
        fi
    done <<< "$staged_files"

    success "HR-004: Markdown length check complete"
}

# ==============================================================================
# HR-005: CODE FILE MINIMUM LENGTH
# ==============================================================================
# Standalone code files in .vault/scripts/ or .vault/hooks/ must be >= 500 lines.

check_hr005() {
    info "HR-005: Checking code file minimum length (min ${MIN_CODE_LINES} lines)..."
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")

        # Only check code files in scripts/ and hooks/
        if [[ "$file" != "${SCRIPTS_DIR}/"* ]] && [[ "$file" != "${HOOKS_DIR}/"* ]]; then
            continue
        fi

        # Skip config files
        if extension_in_list "$ext" "${CONFIG_EXTENSIONS[@]}"; then
            continue
        fi

        # Skip non-code files
        if ! extension_in_list "$ext" "${CODE_EXTENSIONS[@]}"; then
            continue
        fi

        # Check exemptions
        if is_exempt "$file"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local line_count
        line_count=$(count_lines "$full_path")
        if [[ $line_count -lt $MIN_CODE_LINES ]]; then
            violation "HR-005" "$file" "Below ${MIN_CODE_LINES} line minimum (has ${line_count} lines). Consolidate into a comprehensive tool file."
        fi
    done <<< "$staged_files"

    success "HR-005: Code length check complete"
}

# ==============================================================================
# HR-006: UNIQUE PAGE TITLES
# ==============================================================================
# No two files in wiki/ may share the same title frontmatter value.

check_hr006() {
    info "HR-006: Checking unique page titles..."

    # Build a map of all wiki/ titles
    declare -A title_map
    local duplicates_found=false

    while IFS= read -r -d '' file; do
        local ext
        ext=$(get_extension "$file")
        if ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local frontmatter
        frontmatter=$(extract_frontmatter "$file")
        [[ -z "$frontmatter" ]] && continue

        local title
        title=$(get_frontmatter_field "title" "$frontmatter")
        [[ -z "$title" ]] && continue

        local relative_path="${file#${VAULT_ROOT}/}"

        if [[ -n "${title_map[$title]+x}" ]]; then
            violation "HR-006" "$relative_path" "Duplicate title '${title}' — also found in ${title_map[$title]}"
            duplicates_found=true
        else
            title_map["$title"]="$relative_path"
        fi
    # SECURITY: -maxdepth prevents traversal DoS; ! -type l excludes symlinks
    done < <(find "${VAULT_ROOT}/${WIKI_DIR}" -maxdepth "${MAX_FIND_DEPTH}" ! -type l -name "*.md" -print0 2>/dev/null)

    success "HR-006: Title uniqueness check complete"
}

# ==============================================================================
# HR-007: UPDATED FIELD ACCURACY
# ==============================================================================
# Modified files must have updated field matching commit date (±1 day).

check_hr007() {
    info "HR-007: Checking updated field accuracy..."
    local staged_files
    staged_files=$(get_staged_files)
    local today
    today=$(today_date)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")
        if [[ "$file" != "${WIKI_DIR}/"* ]] || ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local frontmatter
        frontmatter=$(extract_frontmatter "$full_path")
        [[ -z "$frontmatter" ]] && continue

        local updated_value
        updated_value=$(get_frontmatter_field "updated" "$frontmatter")
        [[ -z "$updated_value" ]] && continue

        local diff
        diff=$(date_diff "$today" "$updated_value")
        if [[ $diff -gt $DATE_TOLERANCE ]]; then
            violation "HR-007" "$file" "Updated field '${updated_value}' is ${diff} days from today (${today}). Tolerance is ${DATE_TOLERANCE} day(s)."
        fi
    done <<< "$staged_files"

    success "HR-007: Updated field check complete"
}

# ==============================================================================
# HR-008: INDEX REGISTRATION
# ==============================================================================
# Every wiki/ file (except index.md and log.md) must appear in wiki/index.md.

check_hr008() {
    info "HR-008: Checking index registration..."
    local index_path="${VAULT_ROOT}/${INDEX_FILE}"

    if [[ ! -f "$index_path" ]]; then
        warn "HR-008: Index file not found at ${INDEX_FILE}. Skipping."
        return
    fi

    local index_content
    index_content=$(cat "$index_path")

    while IFS= read -r -d '' file; do
        local relative_path="${file#${VAULT_ROOT}/}"
        local ext
        ext=$(get_extension "$file")
        if ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        # Skip index.md and log.md themselves
        if [[ "$relative_path" == "${WIKI_DIR}/index.md" ]] || [[ "$relative_path" == "${WIKI_DIR}/log.md" ]]; then
            continue
        fi

        # Check if the file path or filename appears in index.md
        local basename
        basename=$(basename "$relative_path")
        # SECURITY: Use grep -F for literal string match — filenames may contain
        # regex metacharacters (., *, +, etc.) that grep would interpret as patterns.
        if ! echo "$index_content" | grep -qF "$basename" 2>/dev/null; then
            if ! echo "$index_content" | grep -qF "$relative_path" 2>/dev/null; then
                violation "HR-008" "$relative_path" "Not registered in ${INDEX_FILE}. Every wiki page must have an index entry."
            fi
        fi
    # SECURITY: -maxdepth prevents traversal DoS; ! -type l excludes symlinks
    done < <(find "${VAULT_ROOT}/${WIKI_DIR}" -maxdepth "${MAX_FIND_DEPTH}" ! -type l -name "*.md" -print0 2>/dev/null)

    success "HR-008: Index registration check complete"
}

# ==============================================================================
# HR-009: FLAT TAG NOTATION
# ==============================================================================
# Tags must match pattern: prefix/value (exactly one slash, no spaces).

check_hr009() {
    info "HR-009: Checking flat tag notation..."
    local staged_files
    staged_files=$(get_staged_files)
    local tag_pattern='^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$'

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local ext
        ext=$(get_extension "$file")
        if [[ "$file" != "${WIKI_DIR}/"* ]] || ! extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        local frontmatter
        frontmatter=$(extract_frontmatter "$full_path")
        [[ -z "$frontmatter" ]] && continue

        local tags
        tags=$(get_frontmatter_tags "$frontmatter")
        [[ -z "$tags" ]] && continue

        while IFS= read -r tag; do
            [[ -z "$tag" ]] && continue
            if ! echo "$tag" | grep -qE "$tag_pattern"; then
                violation "HR-009" "$file" "Invalid tag format '${tag}'. Must match prefix/value (lowercase, hyphenated, one slash)."
            fi
        done <<< "$tags"
    done <<< "$staged_files"

    success "HR-009: Tag notation check complete"
}

# ==============================================================================
# HR-010: BINARY FILE QUARANTINE
# ==============================================================================
# Binary files may only exist in raw/. No binaries in wiki/ or memory/.

check_hr010() {
    info "HR-010: Checking binary file quarantine..."
    local staged_files
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Only check wiki/ and memory/ directories
        if [[ "$file" != "${WIKI_DIR}/"* ]] && [[ "$file" != "${MEMORY_DIR}/"* ]]; then
            continue
        fi

        local ext
        ext=$(get_extension "$file")

        # Allow markdown and json
        if extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then
            continue
        fi
        if [[ "$ext" == "json" ]]; then
            continue
        fi

        # Check if gitkeep
        if [[ "$(basename "$file")" == ".gitkeep" ]]; then
            continue
        fi

        local full_path="${VAULT_ROOT}/${file}"
        if [[ -f "$full_path" ]] && is_binary "$full_path"; then
            violation "HR-010" "$file" "Binary file detected outside raw/. Move to raw/ and reference via wikilink."
        fi
    done <<< "$staged_files"

    success "HR-010: Binary quarantine check complete"
}

# ==============================================================================
# SKILL HARDENING: PRE-COMMIT SKILL VALIDATION
# ==============================================================================
# If .vault/schemas/skill-policy.json exists and is enabled, validate any
# staged files in skill directories. This check is fully optional and
# backward compatible — if the policy file is absent or disabled, this
# entire section is skipped silently.

check_skill_hardening() {
    local policy_file="${VAULT_ROOT}/${VAULT_CONFIG_DIR}/schemas/skill-policy.json"

    # Skip silently if no policy file exists
    [[ ! -f "$policy_file" ]] && return

    # python3 is required for JSON parsing in skill hardening
    if ! command -v python3 &>/dev/null; then
        warn "SKILL-HARDENING: python3 not found — skill policy enforcement skipped."
        warn "Install python3 to enable skill hardening checks."
        return
    fi

    # Skip silently if hardening is disabled
    local enabled
    enabled=$(python3 -c "import json; print(json.load(open('${policy_file}'))['enabled'])" 2>/dev/null || echo "False")
    [[ "$enabled" != "True" ]] && return

    info "SKILL-HARDENING: Checking staged skill files..."

    # Read skill directories from policy
    local skill_dirs
    skill_dirs=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
for d in policy.get('skill_directories', []):
    print(d)
" 2>/dev/null)

    # Check if any staged files are in skill directories
    local staged_files
    staged_files=$(get_staged_files)
    local skill_files_staged=false

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        while IFS= read -r skill_dir; do
            [[ -z "$skill_dir" ]] && continue
            if [[ "$file" == "${skill_dir}/"* ]]; then
                skill_files_staged=true
                break 2
            fi
        done <<< "$skill_dirs"
    done <<< "$staged_files"

    if ! $skill_files_staged; then
        success "SKILL-HARDENING: No skill files staged"
        return
    fi

    # Read enforcement level and settings
    local enforcement
    enforcement=$(python3 -c "import json; print(json.load(open('${policy_file}'))['enforcement'])" 2>/dev/null || echo "strict")

    local level_settings
    level_settings=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
level = policy['levels'].get(policy['enforcement'], policy['levels']['strict'])
for k, v in level.items():
    if isinstance(v, list):
        print(f'{k}=|{chr(10).join(str(i) for i in v)}|')
    else:
        print(f'{k}={v}')
" 2>/dev/null)

    # Parse settings
    local require_manifest="True"
    local allow_tool_escalation="False"
    local allow_shell_preprocessing="False"
    local allow_external_urls="False"
    local blocked_patterns_raw=""

    while IFS= read -r setting_line; do
        local key="${setting_line%%=*}"
        local val="${setting_line#*=}"
        case "$key" in
            require_manifest) require_manifest="$val" ;;
            allow_tool_escalation) allow_tool_escalation="$val" ;;
            allow_shell_preprocessing) allow_shell_preprocessing="$val" ;;
            allow_external_urls) allow_external_urls="$val" ;;
            blocked_patterns) blocked_patterns_raw="${val}" ;;
        esac
    done <<< "$level_settings"

    # Parse blocked patterns into array
    local -a blocked_patterns=()
    if [[ -n "$blocked_patterns_raw" ]]; then
        local inner="${blocked_patterns_raw#|}"
        inner="${inner%|}"
        while IFS= read -r pat; do
            [[ -n "$pat" ]] && blocked_patterns+=("$pat")
        done <<< "$inner"
    fi

    # Read URL blocklist
    local url_blocklist
    url_blocklist=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
for u in policy.get('url_blocklist', []):
    print(u)
" 2>/dev/null)

    local url_allowlist
    url_allowlist=$(python3 -c "
import json
with open('${policy_file}') as f:
    policy = json.load(f)
for u in policy.get('url_allowlist', []):
    print(u)
" 2>/dev/null)

    # Validate each staged skill file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local in_skill_dir=false
        while IFS= read -r skill_dir; do
            [[ -z "$skill_dir" ]] && continue
            if [[ "$file" == "${skill_dir}/"* ]]; then
                in_skill_dir=true
                break
            fi
        done <<< "$skill_dirs"

        $in_skill_dir || continue

        local full_path="${VAULT_ROOT}/${file}"
        [[ ! -f "$full_path" ]] && continue

        # Determine the skill root directory (first subdirectory under skill_dir)
        local skill_root=""
        while IFS= read -r skill_dir; do
            [[ -z "$skill_dir" ]] && continue
            if [[ "$file" == "${skill_dir}/"* ]]; then
                # Extract the skill subdirectory name
                local remainder="${file#${skill_dir}/}"
                local skill_subdir="${remainder%%/*}"
                skill_root="${VAULT_ROOT}/${skill_dir}/${skill_subdir}"
                break
            fi
        done <<< "$skill_dirs"

        # Check manifest requirement for the skill root
        if [[ "$require_manifest" == "True" ]] && [[ -n "$skill_root" ]] && [[ -d "$skill_root" ]]; then
            if [[ ! -f "${skill_root}/skill-manifest.json" ]]; then
                violation "SKILL" "$file" "Skill directory missing required skill-manifest.json (${enforcement} enforcement)"
            fi
        fi

        # Only scan markdown files for content violations
        local ext
        ext=$(get_extension "$file")
        if extension_in_list "$ext" "${MARKDOWN_EXTENSIONS[@]}"; then

            # Check for blocked patterns
            for pattern in "${blocked_patterns[@]}"; do
                if grep -qF "$pattern" "$full_path" 2>/dev/null; then
                    violation "SKILL" "$file" "Blocked pattern '${pattern}' detected (${enforcement} enforcement)"
                fi
            done

            # Check for allowed-tools frontmatter
            if [[ "$allow_tool_escalation" == "False" ]]; then
                if grep -qE '^allowed-tools:' "$full_path" 2>/dev/null; then
                    violation "SKILL" "$file" "Tool escalation via allowed-tools blocked (${enforcement} enforcement)"
                fi
            fi

            # Check for !command preprocessing
            if [[ "$allow_shell_preprocessing" == "False" ]]; then
                if grep -qE '^!' "$full_path" 2>/dev/null; then
                    violation "SKILL" "$file" "Shell preprocessing syntax blocked (${enforcement} enforcement)"
                fi
            fi

            # Check for external URLs
            if [[ "$allow_external_urls" == "False" ]]; then
                local urls_in_file
                urls_in_file=$(grep -oE 'https?://[a-zA-Z0-9./?=_%&:@#~-]+' "$full_path" 2>/dev/null || true)
                while IFS= read -r url; do
                    [[ -z "$url" ]] && continue
                    local domain
                    # shellcheck disable=SC2001
                    domain=$(echo "$url" | sed 's|https\?://\([^/]*\).*|\1|')
                    local allowed=false
                    while IFS= read -r allow_domain; do
                        [[ -z "$allow_domain" ]] && continue
                        if [[ "$domain" == *"$allow_domain"* ]]; then
                            allowed=true
                            break
                        fi
                    done <<< "$url_allowlist"
                    if ! $allowed; then
                        violation "SKILL" "$file" "External URL blocked: ${url} (${enforcement} enforcement)"
                    fi
                done <<< "$urls_in_file"
            else
                # Check blocklist even in permissive mode
                while IFS= read -r blocked_domain; do
                    [[ -z "$blocked_domain" ]] && continue
                    if grep -qF "$blocked_domain" "$full_path" 2>/dev/null; then
                        violation "SKILL" "$file" "Blocklisted domain '${blocked_domain}' detected"
                    fi
                done <<< "$url_blocklist"
            fi
        fi
    done <<< "$staged_files"

    success "SKILL-HARDENING: Skill file validation complete"
}

# ==============================================================================
# SENSITIVE FILE MODIFICATION WARNINGS
# ==============================================================================
# These checks emit warnings (not blocking violations) when files critical to
# vault security are modified. Pre-commit hooks cannot distinguish agent commits
# from human commits, so these are advisory. The intent is to surface changes
# to governance files that a human reviewer should scrutinize.

SENSITIVE_WARNINGS=0

check_sensitive_files() {
    info "ADVISORY: Checking for sensitive file modifications..."
    local staged_files
    staged_files=$(get_staged_files)

    # Also include deleted files in sensitivity check
    local deleted_files
    deleted_files=$(git diff --cached --name-only --diff-filter=D 2>/dev/null || true)
    local all_changed_files
    all_changed_files=$(printf '%s\n%s' "$staged_files" "$deleted_files" | sort -u)

    # Define sensitive path patterns and their risk descriptions
    local sensitive_patterns=(
        ".vault/hooks/|VAULT HOOKS — controls all pre-commit enforcement"
        ".vault/rules/|VAULT RULES — defines what is enforced"
        ".vault/scripts/|VAULT SCRIPTS — operational tooling"
        ".vault/schemas/|VAULT SCHEMAS — validation definitions"
        ".github/|CI/CD PIPELINES — controls automated checks"
        ".claude/|CLAUDE CODE SETTINGS — agent permission configuration"
        "templates/|CONTENT TEMPLATES — injected into all future pages"
    )

    # Exact-match sensitive files
    local sensitive_files=(
        "CLAUDE.md|AGENT CONFIG — primary agent instruction file"
        "AGENTS.md|AGENT CONFIG — platform-agnostic agent instructions"
        "CODEX.md|AGENT CONFIG — Codex-specific agent instructions"
    )

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Check path-prefix patterns
        for pattern_desc in "${sensitive_patterns[@]}"; do
            local pattern="${pattern_desc%%|*}"
            local desc="${pattern_desc##*|}"
            if [[ "$file" == "$pattern"* ]]; then
                warn "SENSITIVE FILE MODIFIED: ${file} — ${desc}"
                SENSITIVE_WARNINGS=$((SENSITIVE_WARNINGS + 1))
                break
            fi
        done

        # Check exact-match files
        for file_desc in "${sensitive_files[@]}"; do
            local sensitive_name="${file_desc%%|*}"
            local desc="${file_desc##*|}"
            if [[ "$file" == "$sensitive_name" ]]; then
                warn "SENSITIVE FILE MODIFIED: ${file} — ${desc}"
                SENSITIVE_WARNINGS=$((SENSITIVE_WARNINGS + 1))
            fi
        done
    done <<< "$all_changed_files"

    if [[ $SENSITIVE_WARNINGS -gt 0 ]]; then
        echo ""
        warn "================================================"
        warn "  ${SENSITIVE_WARNINGS} sensitive file(s) modified in this commit."
        warn "  If this is an agent-authored commit, a human"
        warn "  reviewer MUST verify these changes before merge."
        warn "================================================"
        echo ""
    else
        success "ADVISORY: No sensitive file modifications detected"
    fi
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    echo ""
    echo "=============================================="
    echo "  VAULT PRE-COMMIT VALIDATION"
    echo "=============================================="
    echo ""

    # SECURITY: Check for symlinks in staged files before running other checks.
    # Symlinks in wiki/ or memory/ can point outside the vault, enabling path
    # traversal attacks where scripts read /etc/passwd or .git/config.
    info "SEC: Checking for symlinks in staged files..."
    local staged_files_sec
    staged_files_sec=$(get_staged_files)
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local full_path="${VAULT_ROOT}/${file}"
        if is_symlink "$full_path"; then
            violation "SEC" "$file" "Symlinks are not allowed in vault content directories. Remove the symlink and use a regular file."
        fi
    done <<< "$staged_files_sec"
    success "SEC: Symlink check complete"

    # Run all hard rule checks
    check_hr001
    check_hr002
    check_hr003
    check_hr004
    check_hr005
    check_hr006
    check_hr007
    check_hr008
    check_hr009
    check_hr010

    # Run optional hardening checks (no-op if not configured)
    check_skill_hardening

    # Run advisory checks (non-blocking)
    check_sensitive_files

    echo ""
    echo "=============================================="

    if [[ $VIOLATIONS -gt 0 ]]; then
        echo -e "${RED}  COMMIT BLOCKED: ${VIOLATIONS} violation(s) detected${RESET}"
        echo "=============================================="
        echo ""
        echo "Violations:"
        for msg in "${VIOLATION_MESSAGES[@]}"; do
            echo -e "  $msg"
        done
        echo ""
        echo "Fix the violations above and try again."
        echo "See .vault/rules/hard-rules.md for rule details."
        echo ""
        exit 1
    else
        echo -e "${GREEN}  ALL CHECKS PASSED${RESET}"
        if [[ $SENSITIVE_WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}  (${SENSITIVE_WARNINGS} advisory warning(s) — review recommended)${RESET}"
        fi
        echo "=============================================="
        echo ""
        exit 0
    fi
}

# Run main unless sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
