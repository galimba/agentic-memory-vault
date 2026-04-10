#!/usr/bin/env bash
# ==============================================================================
# VAULT INITIALIZATION SCRIPT
# ==============================================================================
# Run this after cloning the boilerplate to configure for your organization.
# This file is EXEMPT from the 500-line code minimum (HR-005).
# Usage: bash .vault/scripts/init.sh
# ==============================================================================

set -euo pipefail

VAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ==============================================================================
# SECURITY: Escape user input for safe use in sed replacement strings.
# sed treats /, &, \, and newlines as special in the replacement part of s///.
# This function escapes all of them so user input is treated as literal text.
# Usage: escaped=$(escape_sed_replacement "$raw_input")
# ==============================================================================
escape_sed_replacement() {
    local input="$1"
    # Order matters: escape backslashes first, then other metacharacters
    input="${input//\\/\\\\}"   # \ -> \\
    input="${input//\//\\/}"    # / -> \/
    input="${input//&/\\&}"     # & -> \&
    # Remove newlines entirely — they break sed and should not appear in names
    input="${input//$'\n'/}"
    printf '%s' "$input"
}

# ==============================================================================
# SECURITY: Validate user input does not contain shell metacharacters that
# could cause command injection when interpolated into sed expressions.
# Rejects: $, `, embedded nulls, and control characters (except tab).
# ==============================================================================
validate_input() {
    local name="$1"
    local value="$2"
    if [[ "$value" == *'$('* ]] || [[ "$value" == *'`'* ]] || [[ "$value" == *$'\0'* ]]; then
        echo "ERROR: ${name} contains forbidden characters (\$(...), backticks, or null bytes)."
        echo "Please re-run init.sh with a safe value."
        exit 2
    fi
    # Reject control characters other than tab — strip tabs before testing
    local stripped="${value//$'\t'/}"
    if [[ "$stripped" =~ [[:cntrl:]] ]]; then
        echo "ERROR: ${name} contains control characters."
        exit 2
    fi
}

echo ""
echo "================================================"
echo "  MEMORY VAULT — Initialization"
echo "================================================"
echo ""

# Gather configuration
read -rp "Vault name (e.g., acme-memory): " VAULT_NAME
read -rp "Organization name (e.g., Acme Corp): " ORG_NAME
read -rp "GitHub org or username (e.g., acme-corp): " GITHUB_ORG
read -rp "Primary agent platform [claude-code/codex/copilot/cursor/custom]: " PLATFORM
INIT_DATE=$(date +%Y-%m-%d)

# Validate inputs before use
validate_input "VAULT_NAME" "$VAULT_NAME"
validate_input "ORG_NAME" "$ORG_NAME"
validate_input "GITHUB_ORG" "$GITHUB_ORG"
validate_input "PLATFORM" "$PLATFORM"

# Escape inputs for safe sed replacement
VAULT_NAME_SED=$(escape_sed_replacement "$VAULT_NAME")
ORG_NAME_SED=$(escape_sed_replacement "$ORG_NAME")
GITHUB_ORG_SED=$(escape_sed_replacement "$GITHUB_ORG")
PLATFORM_SED=$(escape_sed_replacement "$PLATFORM")
INIT_DATE_SED=$(escape_sed_replacement "$INIT_DATE")

echo ""
echo "Configuring vault: ${VAULT_NAME}"
echo "Organization: ${ORG_NAME}"
echo "GitHub: ${GITHUB_ORG}"
echo "Platform: ${PLATFORM}"
echo "Date: ${INIT_DATE}"
echo ""

# Replace placeholders in markdown files
# SECURITY: Uses escaped values to prevent sed injection via /, &, or \
echo "Replacing placeholders in markdown files..."
find "${VAULT_ROOT}" -maxdepth 10 -name "*.md" -not -path "${VAULT_ROOT}/.git/*" ! -type l -type f -exec sed -i \
    -e "s/{{VAULT_NAME}}/${VAULT_NAME_SED}/g" \
    -e "s/{{ORG_NAME}}/${ORG_NAME_SED}/g" \
    -e "s/{{PLATFORM}}/${PLATFORM_SED}/g" \
    -e "s/{{INIT_DATE}}/${INIT_DATE_SED}/g" \
    -e "s/{{GITHUB_ORG}}/${GITHUB_ORG_SED}/g" \
    {} +
echo "  Done"

# Replace placeholders in YAML config files (.github/)
echo "Replacing placeholders in config files..."
find "${VAULT_ROOT}/.github" -maxdepth 5 -name "*.yml" ! -type l -type f -exec sed -i \
    -e "s/{{GITHUB_ORG}}/${GITHUB_ORG_SED}/g" \
    {} + 2>/dev/null || true
echo "  Done"

echo ""

# Initialize git if needed
if [[ ! -d "${VAULT_ROOT}/.git" ]]; then
    echo "Initializing git repository..."
    git -C "${VAULT_ROOT}" init
    echo "  Done"
fi

# Offer to install hooks (explain first, then ask)
echo ""
echo "Git hooks enforce the vault's hard rules before every commit."
echo "The pre-commit hook checks: frontmatter validity, tag compliance,"
echo "line limits, title uniqueness, index registration, and more."
echo ""
read -rp "Install git pre-commit hook? [Y/n]: " INSTALL_HOOKS
INSTALL_HOOKS="${INSTALL_HOOKS:-Y}"

if [[ "${INSTALL_HOOKS}" =~ ^[Yy] ]]; then
    bash "${VAULT_ROOT}/.vault/scripts/vault-tools.sh" init-hooks 2>/dev/null || {
        cp "${VAULT_ROOT}/.vault/hooks/pre-commit.sh" "${VAULT_ROOT}/.git/hooks/pre-commit"
        chmod +x "${VAULT_ROOT}/.git/hooks/pre-commit"
    }
    echo "  Hooks installed"
else
    echo "  Skipped. Install later: bash .vault/scripts/vault-tools.sh init-hooks"
fi

# Make scripts executable
chmod +x "${VAULT_ROOT}/.vault/scripts/"*.sh 2>/dev/null || true
chmod +x "${VAULT_ROOT}/.vault/hooks/"*.sh 2>/dev/null || true

# Security Hardening
echo ""
echo "================================================"
echo "  Security Hardening"
echo "================================================"
echo ""
echo "Skill hardening protects against malicious Claude Code skills."
echo "Levels: strict (recommended), moderate, permissive, none"
echo ""
read -rp "Enable skill hardening? [strict/moderate/permissive/none] (default: strict): " SKILL_HARDENING
SKILL_HARDENING="${SKILL_HARDENING:-strict}"

# SECURITY: Validate enum before interpolating into sed
case "$SKILL_HARDENING" in
    strict|moderate|permissive|none) ;;
    *)
        echo "ERROR: Invalid hardening level '${SKILL_HARDENING}'. Must be strict, moderate, permissive, or none."
        exit 2
        ;;
esac

if [[ "$SKILL_HARDENING" != "none" ]]; then
    cp "${VAULT_ROOT}/.vault/schemas/skill-policy.json" "${VAULT_ROOT}/.vault/schemas/skill-policy.json.bak" 2>/dev/null || true
    sed -i "s/\"enforcement\": \"strict\"/\"enforcement\": \"${SKILL_HARDENING}\"/" "${VAULT_ROOT}/.vault/schemas/skill-policy.json"
    echo "  Skill hardening enabled (${SKILL_HARDENING})"
else
    sed -i 's/"enabled": true/"enabled": false/' "${VAULT_ROOT}/.vault/schemas/skill-policy.json"
    echo "  Skill hardening disabled"
fi
rm -f "${VAULT_ROOT}/.vault/schemas/skill-policy.json.bak"

echo ""
echo "Content hardening detects injection attacks and bulk manipulation."
echo "This is optional and disabled by default."
echo ""
read -rp "Enable content integrity checking? [y/N] (default: N): " CONTENT_HARDENING
CONTENT_HARDENING="${CONTENT_HARDENING:-N}"

if [[ "$CONTENT_HARDENING" =~ ^[Yy]$ ]]; then
    sed -i 's/"enabled": false/"enabled": true/' "${VAULT_ROOT}/.vault/schemas/content-policy.json"
    echo "  Content hardening enabled"
else
    echo "  Content hardening disabled (default)"
fi

# Offer to run diagnostics
echo ""
read -rp "Run vault diagnostics (vault-tools.sh doctor)? [Y/n]: " RUN_DOCTOR
RUN_DOCTOR="${RUN_DOCTOR:-Y}"

if [[ "${RUN_DOCTOR}" =~ ^[Yy] ]]; then
    echo ""
    bash "${VAULT_ROOT}/.vault/scripts/vault-tools.sh" doctor
fi

echo ""
echo "================================================"
echo "  Initialization Complete!"
echo "================================================"
echo ""
echo "What's next:"
echo ""
echo "  1. Review and customize .vault/rules/soft-rules.md"
echo "  2. Add domain-specific tags to .vault/rules/tags.md"
echo "  3. Fill in your company context in docs/company-context.md"
echo "  4. Drop your first source document into raw/"
echo "  5. Tell your agent: 'Ingest the new file in raw/'"
echo ""
echo "Useful commands:"
echo "  bash .vault/scripts/vault-tools.sh doctor       — Run full diagnostics"
echo "  bash .vault/scripts/vault-tools.sh lint         — Run lint checks"
echo "  bash .vault/scripts/vault-tools.sh skill-audit  — Audit skill security"
echo "  bash .vault/scripts/vault-tools.sh status       — View vault status"
echo "  bash .vault/scripts/vault-tools.sh help         — See all commands"
echo ""
