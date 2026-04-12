#!/usr/bin/env bash
# ==============================================================================
# VAULT PRE-COMMIT HOOK — Entry Point
# ==============================================================================
#
# This script runs before every git commit. It validates all staged files against
# the vault's hard rules defined in .vault/rules/hard-rules.md. Any violation
# causes the commit to be rejected with a clear error message.
#
# This is the entry point that sources modular libraries:
#   lib-hook-utils.sh       — utility functions, logging, file inspection
#   checks/check-hr*.sh    — individual hard rule check functions (HR-001 through HR-015)
#   checks/check-*.sh      — additional checks (skill hardening, sensitive files)
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
#   HR-004: Markdown length limit (warn 200, block 400 lines)
#   HR-005: Code file length limit (warn 400, block 600 lines)
#   HR-006: Unique page titles
#   HR-007: Updated field accuracy
#   HR-008: Index registration
#   HR-009: Flat tag notation
#   HR-010: Binary file quarantine
#   HR-011: Vault configuration protection
#   HR-012: Agent configuration protection
#   HR-013: CI and template protection
#   HR-014: No file deletion in wiki/ or memory/
#   HR-015: Append-only logs (wiki/log.md, memory/logs/)
#
# POLICY CHECKS:
#   check_skill_hardening — driven by .vault/schemas/skill-policy.json
#   check_content_policy  — driven by .vault/schemas/content-policy.json
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
WARN_MARKDOWN_LINES=200
MAX_MARKDOWN_LINES=400
WARN_CODE_LINES=400
MAX_CODE_LINES=600

# Files exempt from line count rules
EXEMPT_FILES=(
    "wiki/index.md"
    "wiki/log.md"
    ".vault/scripts/init.sh"
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
# SOURCE LIBRARIES
# ==============================================================================

# Resolve the directory this script lives in (handles symlinked hooks)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utility functions
# shellcheck source=lib-hook-utils.sh
source "${HOOK_DIR}/lib-hook-utils.sh"

# Source all check files (auto-discovered from checks/ directory)
for check_file in "${HOOK_DIR}/checks/"*.sh; do
    # shellcheck source=/dev/null
    source "$check_file"
done

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
    check_hr011
    check_hr012
    check_hr013
    check_hr014
    check_hr015

    # Run optional hardening checks (no-op if policy file is absent or disabled)
    check_skill_hardening
    check_content_policy

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
