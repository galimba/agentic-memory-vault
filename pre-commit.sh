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
    # Read the file and extract content between first and second ---
    local in_frontmatter=false
    local frontmatter=""
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
    done < <(find "${VAULT_ROOT}/${WIKI_DIR}" -name "*.md" -print0 2>/dev/null)

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
        if ! echo "$index_content" | grep -q "$basename" 2>/dev/null; then
            if ! echo "$index_content" | grep -q "$relative_path" 2>/dev/null; then
                violation "HR-008" "$relative_path" "Not registered in ${INDEX_FILE}. Every wiki page must have an index entry."
            fi
        fi
    done < <(find "${VAULT_ROOT}/${WIKI_DIR}" -name "*.md" -print0 2>/dev/null)

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
# MAIN EXECUTION
# ==============================================================================

main() {
    echo ""
    echo "=============================================="
    echo "  VAULT PRE-COMMIT VALIDATION"
    echo "=============================================="
    echo ""

    # Run all checks
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
        echo "=============================================="
        echo ""
        exit 0
    fi
}

# Run main unless sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
