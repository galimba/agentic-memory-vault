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

echo ""
echo "Configuring vault: ${VAULT_NAME}"
echo "Organization: ${ORG_NAME}"
echo "GitHub: ${GITHUB_ORG}"
echo "Platform: ${PLATFORM}"
echo "Date: ${INIT_DATE}"
echo ""

# Replace placeholders in markdown files
echo "Replacing placeholders in markdown files..."
find "${VAULT_ROOT}" -name "*.md" -not -path "${VAULT_ROOT}/.git/*" -type f -exec sed -i \
    -e "s/{{VAULT_NAME}}/${VAULT_NAME}/g" \
    -e "s/{{ORG_NAME}}/${ORG_NAME}/g" \
    -e "s/{{PLATFORM}}/${PLATFORM}/g" \
    -e "s/{{INIT_DATE}}/${INIT_DATE}/g" \
    -e "s/{{GITHUB_ORG}}/${GITHUB_ORG}/g" \
    {} +
echo "  Done"

# Replace placeholders in YAML config files (.github/)
echo "Replacing placeholders in config files..."
find "${VAULT_ROOT}/.github" -name "*.yml" -type f -exec sed -i \
    -e "s/{{GITHUB_ORG}}/${GITHUB_ORG}/g" \
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
echo "  bash .vault/scripts/vault-tools.sh doctor   — Run full diagnostics"
echo "  bash .vault/scripts/vault-tools.sh lint     — Run lint checks"
echo "  bash .vault/scripts/vault-tools.sh status   — View vault status"
echo "  bash .vault/scripts/vault-tools.sh help     — See all commands"
echo ""
