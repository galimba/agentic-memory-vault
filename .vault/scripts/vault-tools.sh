#!/usr/bin/env bash
# ==============================================================================
# VAULT TOOLS — Consolidated CLI for Vault Operations
# ==============================================================================
#
# Provides CLI commands for the three vault operations (INGEST, QUERY, LINT)
# plus utilities for vault management, status reporting, and maintenance.
#
# USAGE:
#   ./vault-tools.sh lint [--report]   Run full vault lint (--report writes
#                                      memory/notes/lint-report-YYYY-MM-DD.md)
#   ./vault-tools.sh status            Show vault status
#   ./vault-tools.sh validate <file>   Validate a single file
#   ./vault-tools.sh index-rebuild     Rebuild wiki/index.md from scratch
#   ./vault-tools.sh orphans           List orphan pages
#   ./vault-tools.sh stale [days]      List stale pages (default: 30 days)
#   ./vault-tools.sh tag-audit         Audit tag usage across vault
#   ./vault-tools.sh skill-audit       Audit skills against hardening policy
#   ./vault-tools.sh skill-manifest <dir>  Generate/refresh skill-manifest.json
#   ./vault-tools.sh content-audit     Audit content integrity
#   ./vault-tools.sh verify-sources    Verify sources: citations resolve to raw/ files
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

WARN_MARKDOWN_LINES=200
MAX_MARKDOWN_LINES=400
WARN_CODE_LINES=400
MAX_CODE_LINES=600
DEFAULT_STALE_DAYS=30

# ==============================================================================
# SECURITY THRESHOLDS
# ==============================================================================
MAX_FILE_SIZE_BYTES=1048576  # 1 MB — skip files larger than this
MAX_FIND_DEPTH=10            # prevent deeply nested directory traversal

# Color output
if [[ "${NO_COLOR:-0}" == "1" ]] || [[ ! -t 1 ]]; then
    RED="" ; GREEN="" ; YELLOW="" ; BLUE="" ; CYAN="" ; RESET=""
else
    RED="\033[0;31m" ; GREEN="\033[0;32m" ; YELLOW="\033[0;33m"
    BLUE="\033[0;34m" ; CYAN="\033[0;36m" ; RESET="\033[0m"
fi

# ==============================================================================
# SOURCE LIBRARY MODULES
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib-utils.sh"

# Source audit files FIRST (lib-lint.sh depends on cmd_tag_audit)
for audit_file in "${SCRIPT_DIR}/audits/"audit-*.sh; do
    # shellcheck source=/dev/null
    source "$audit_file"
done

source "${SCRIPT_DIR}/lib-lint.sh"
source "${SCRIPT_DIR}/lib-manage.sh"
source "${SCRIPT_DIR}/lib-skills.sh"

# ==============================================================================
# HELP
# ==============================================================================

cmd_help() {
    echo ""
    echo "Vault Tools — CLI for Vault Operations"
    echo ""
    echo "Usage: vault-tools.sh <command> [options]"
    echo ""
    echo "Lint & Validation:"
    echo "  lint [--report]   Run full vault lint (--report writes to memory/notes/)"
    echo "  validate <file>   Validate a single file"
    echo "  orphans           List orphan pages"
    echo "  stale [days]      List stale pages (default: 30)"
    echo ""
    echo "Audits:"
    echo "  tag-audit         Audit tag usage"
    echo "  skill-audit       Audit skill security"
    echo "  skill-manifest <dir>  Generate or refresh a skill's manifest"
    echo "  content-audit     Audit content integrity"
    echo "  verify-sources    Verify sources: citations resolve to raw/ files"
    echo ""
    echo "Management:"
    echo "  status            Show vault status"
    echo "  stats             Show detailed vault statistics"
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
        skill-audit)    cmd_skill_audit "$@" ;;
        skill-manifest) cmd_skill_manifest "$@" ;;
        content-audit)  cmd_content_audit "$@" ;;
        verify-sources) cmd_verify_sources "$@" ;;
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
