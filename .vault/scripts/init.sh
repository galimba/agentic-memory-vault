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
# IDEMPOTENCY: Warn if vault has already been initialized.
# ==============================================================================
if [[ -f "${VAULT_ROOT}/.vault/.initialized" ]]; then
    echo ""
    echo "WARNING: This vault has already been initialized."
    echo ""
    cat "${VAULT_ROOT}/.vault/.initialized"
    echo ""
    read -rp "Re-initialize? This will overwrite current configuration. [y/N]: " REINIT
    if [[ ! "${REINIT}" =~ ^[Yy] ]]; then
        echo "Aborted."
        exit 0
    fi
fi

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
# Rejects: $(...), backticks, and control characters (except tab).
# Null bytes cannot appear in bash variables (C-string storage), so no check
# is needed — attempting `*$'\0'*` collapses to `**` and matches everything.
# ==============================================================================
validate_input() {
    local name="$1"
    local value="$2"
    if [[ "$value" == *'$('* ]] || [[ "$value" == *'`'* ]]; then
        echo "ERROR: ${name} contains forbidden characters (\$(...) or backticks)."
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
read -rp "Repository name (e.g., my-vault): " REPO_NAME
read -rp "GitHub maintainer user or team for CODEOWNERS (e.g., my-team): " MAINTAINER
INIT_DATE=$(date +%Y-%m-%d)

# Strip leading @ from MAINTAINER if present (normalize)
MAINTAINER="${MAINTAINER#@}"

# Validate inputs before use
validate_input "VAULT_NAME" "$VAULT_NAME"
validate_input "ORG_NAME" "$ORG_NAME"
validate_input "GITHUB_ORG" "$GITHUB_ORG"
validate_input "PLATFORM" "$PLATFORM"
validate_input "REPO_NAME" "$REPO_NAME"
validate_input "MAINTAINER" "$MAINTAINER"

# Escape inputs for safe sed replacement
VAULT_NAME_SED=$(escape_sed_replacement "$VAULT_NAME")
ORG_NAME_SED=$(escape_sed_replacement "$ORG_NAME")
GITHUB_ORG_SED=$(escape_sed_replacement "$GITHUB_ORG")
PLATFORM_SED=$(escape_sed_replacement "$PLATFORM")
REPO_NAME_SED=$(escape_sed_replacement "$REPO_NAME")
MAINTAINER_SED=$(escape_sed_replacement "$MAINTAINER")
INIT_DATE_SED=$(escape_sed_replacement "$INIT_DATE")

echo ""
echo "Configuring vault: ${VAULT_NAME}"
echo "Organization: ${ORG_NAME}"
echo "GitHub: ${GITHUB_ORG}"
echo "Repository: ${REPO_NAME}"
echo "Maintainer: @${MAINTAINER}"
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
    -e "s/{{REPO_NAME}}/${REPO_NAME_SED}/g" \
    -e "s/{{MAINTAINER}}/${MAINTAINER_SED}/g" \
    {} +
echo "  Done"

# Replace placeholders in YAML config files (.github/)
echo "Replacing placeholders in config files..."
find "${VAULT_ROOT}/.github" -maxdepth 5 -name "*.yml" ! -type l -type f -exec sed -i \
    -e "s/{{GITHUB_ORG}}/${GITHUB_ORG_SED}/g" \
    -e "s/{{REPO_NAME}}/${REPO_NAME_SED}/g" \
    -e "s/{{MAINTAINER}}/${MAINTAINER_SED}/g" \
    {} + 2>/dev/null || true
echo "  Done"

# ==============================================================================
# INSTANCE SCAFFOLDING
# ==============================================================================
# Reorganize template documentation for use as an instance vault.
# This phase copies templates/readme-instance.md and templates/onboarding-instance.md
# (already substituted by the global sed pass above) to their final locations,
# replaces the template CHANGELOG with a fresh one, and cleans up CONTRIBUTING.md.
# ==============================================================================
echo ""
echo "================================================"
echo "  Instance Scaffolding"
echo "================================================"
echo ""
echo "The current README.md contains template documentation."
echo "I can reorganize it for your vault instance:"
echo ""
echo "  README.md                         -> Rewritten as your team's gateway"
echo "  docs/vault-template-readme.md     -> Template docs (preserved)"
echo "  docs/onboarding.md               -> Starter onboarding guide"
echo "  CHANGELOG.md                     -> Fresh changelog"
echo "  CONTRIBUTING.md                  -> Updated for your repo"
echo "  docs/roadmap.md                  -> Moved to docs/vault-template-roadmap.md"
echo ""
read -rp "Proceed? [Y/n]: " SCAFFOLD
SCAFFOLD="${SCAFFOLD:-Y}"

if [[ "${SCAFFOLD}" =~ ^[Yy] ]]; then
    echo ""

    # 1. Move template README, install instance README
    {
        echo "> This file contains the original template documentation."
        echo "> Upstream template: https://github.com/galimba/agentic-memory-vault"
        echo ""
        cat "${VAULT_ROOT}/README.md"
    } > "${VAULT_ROOT}/docs/vault-template-readme.md"
    cp "${VAULT_ROOT}/templates/readme-instance.md" "${VAULT_ROOT}/README.md"
    echo "  README.md replaced with instance gateway"

    # 2. Generate onboarding guide
    cp "${VAULT_ROOT}/templates/onboarding-instance.md" "${VAULT_ROOT}/docs/onboarding.md"
    echo "  docs/onboarding.md generated"

    # 3. Replace CHANGELOG with a fresh one
    cat > "${VAULT_ROOT}/CHANGELOG.md" <<CHANGELOG_EOF
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - ${INIT_DATE}

### Added

- Initialized vault from [agentic-memory-vault](https://github.com/galimba/agentic-memory-vault) template (v0.4.0)

[Unreleased]: https://github.com/${GITHUB_ORG}/${REPO_NAME}/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/${GITHUB_ORG}/${REPO_NAME}/releases/tag/v0.1.0
CHANGELOG_EOF
    echo "  CHANGELOG.md replaced with fresh instance changelog"

    # 4. Clean up CONTRIBUTING.md — remove template-specific "Two Types" section
    #    Match by content (not line numbers) since earlier sed may have shifted lines
    sed -i '/^## Two Types of Contributions$/,/^## How to Report Bugs$/{/^## How to Report Bugs$/!d;}' \
        "${VAULT_ROOT}/CONTRIBUTING.md"
    echo "  CONTRIBUTING.md updated for instance"

    # 5. Reset vault version from template version to instance 0.1.0
    for verfile in CLAUDE.md AGENTS.md; do
        sed -i 's/\*\*Vault Version\*\*: `0\.[0-9]\+\.[0-9]\+`/**Vault Version**: `0.1.0`/' \
            "${VAULT_ROOT}/${verfile}" 2>/dev/null || true
    done
    echo "  Vault version reset to 0.1.0 in CLAUDE.md and AGENTS.md"

    # 6. Move template roadmap
    {
        echo "> This file contains the original template roadmap."
        echo "> Upstream template: https://github.com/galimba/agentic-memory-vault"
        echo ""
        cat "${VAULT_ROOT}/docs/roadmap.md"
    } > "${VAULT_ROOT}/docs/vault-template-roadmap.md"
    rm "${VAULT_ROOT}/docs/roadmap.md"
    echo "  docs/roadmap.md moved to docs/vault-template-roadmap.md"

    echo ""
    echo "  Instance scaffolding complete"
else
    echo "  Skipped. You can reorganize files manually later."
fi

echo ""

# Initialize git if needed, or fix remote if cloned from template
if [[ ! -d "${VAULT_ROOT}/.git" ]]; then
    echo "Initializing git repository..."
    git -C "${VAULT_ROOT}" init
    echo "  Done"
else
    CURRENT_REMOTE=$(git -C "${VAULT_ROOT}" remote get-url origin 2>/dev/null || true)
    if [[ -n "$CURRENT_REMOTE" ]] && [[ "$CURRENT_REMOTE" == *"agentic-memory-vault"* ]]; then
        NEW_REMOTE="https://github.com/${GITHUB_ORG}/${REPO_NAME}.git"
        echo "Current git remote points to the template repository."
        echo "  Current:   ${CURRENT_REMOTE}"
        echo "  Suggested: ${NEW_REMOTE}"
        read -rp "Update remote origin? [Y/n]: " UPDATE_REMOTE
        UPDATE_REMOTE="${UPDATE_REMOTE:-Y}"
        if [[ "${UPDATE_REMOTE}" =~ ^[Yy] ]]; then
            git -C "${VAULT_ROOT}" remote set-url origin "${NEW_REMOTE}"
            echo "  Remote updated"
        else
            echo "  Skipped. Update manually: git remote set-url origin <your-url>"
        fi
    fi
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
    # cmd_init_hooks is the single source of truth for hook installation.
    # Do NOT add a silent `cp` fallback here — the original implementation
    # did that and masked a bug where the flat-copied hook could not find
    # its own library files, silently disabling HR enforcement.
    if ! bash "${VAULT_ROOT}/.vault/scripts/vault-tools.sh" init-hooks; then
        echo "  ERROR: hook install failed. Run manually: bash .vault/scripts/vault-tools.sh init-hooks" >&2
        exit 2
    fi
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
echo "Since v0.2.0 it is enabled by default in 'warn' mode — violations"
echo "are reported but do not block commits. Set enforcement=block in"
echo ".vault/schemas/content-policy.json to make it blocking."
echo ""
read -rp "Keep content integrity checking enabled? [Y/n] (default: Y): " CONTENT_HARDENING
CONTENT_HARDENING="${CONTENT_HARDENING:-Y}"

if [[ "$CONTENT_HARDENING" =~ ^[Nn]$ ]]; then
    sed -i 's/"enabled": true/"enabled": false/' "${VAULT_ROOT}/.vault/schemas/content-policy.json"
    echo "  Content hardening disabled"
else
    echo "  Content hardening enabled (warn mode)"
fi

# Offer to run diagnostics
echo ""
read -rp "Run vault diagnostics (vault-tools.sh doctor)? [Y/n]: " RUN_DOCTOR
RUN_DOCTOR="${RUN_DOCTOR:-Y}"

if [[ "${RUN_DOCTOR}" =~ ^[Yy] ]]; then
    echo ""
    bash "${VAULT_ROOT}/.vault/scripts/vault-tools.sh" doctor
fi

# ==============================================================================
# SAVE INITIALIZATION STATE
# ==============================================================================
cat > "${VAULT_ROOT}/.vault/.initialized" <<INIT_EOF
vault_name=${VAULT_NAME}
org_name=${ORG_NAME}
repo_name=${REPO_NAME}
github_org=${GITHUB_ORG}
maintainer=${MAINTAINER}
platform=${PLATFORM}
init_date=${INIT_DATE}
template_version=0.4.0
INIT_EOF
echo "  State saved to .vault/.initialized"

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
echo "If initialization failed partway, re-run init.sh and confirm re-initialization."
echo ""
echo "Useful commands:"
echo "  bash .vault/scripts/vault-tools.sh doctor       — Run full diagnostics"
echo "  bash .vault/scripts/vault-tools.sh lint         — Run lint checks"
echo "  bash .vault/scripts/vault-tools.sh skill-audit  — Audit skill security"
echo "  bash .vault/scripts/vault-tools.sh status       — View vault status"
echo "  bash .vault/scripts/vault-tools.sh help         — See all commands"
echo ""
