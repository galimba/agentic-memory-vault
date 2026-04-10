# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Older releases | No |

## Reporting a Vulnerability

- Use GitHub's **Private Vulnerability Reporting** (Security tab → Report a vulnerability)
- Do **not** open public issues for security concerns
- You will receive acknowledgment within 48 hours
- Detailed response within 7 days

## Scope

**Covered:**

- Pre-commit hooks (`.vault/hooks/`)
- CLI tools (`.vault/scripts/`)
- Init script behavior
- Template content that could introduce issues when used

**Not covered:**

- Content users add to their own vaults after generation
- Third-party Obsidian plugins
- AI model behavior (that is the model provider's responsibility)

## Security Considerations for Vault Operators

### AI Agent Access

- Agents with vault access can read all files in the vault
- Do **not** store secrets, API keys, passwords, or PII in vault files
- Use environment variables or external secret managers for sensitive data
- The `raw/` directory may contain documents with sensitive information — consider access controls

### Script Safety

- All scripts use `set -euo pipefail` for fail-fast behavior
- Review `.vault/hooks/pre-commit.sh` and `.vault/scripts/vault-tools.sh` before first use
- Scripts perform filesystem operations (read, write, delete) within the vault directory only
- No scripts make network requests or access external services
- No scripts require elevated privileges (sudo)

### Git Hook Security

- Pre-commit hooks run automatically before every commit
- Hooks are **not** copied when using GitHub's "Use this template" feature
- Users must manually install hooks via `bash .vault/scripts/init.sh`
- This is a security feature: users explicitly opt into hook execution

### Adversarial Input Risk

- Files in `raw/` are read by AI agents during ingestion
- Source documents could contain adversarial instructions
- **Mitigation**: Human review of `raw/` contents before agent ingestion
- The vault's hard rules (HR-001: `raw/` immutability) prevent agents from modifying sources

### Agent Threat Model

AI agents with vault access operate in a trust-based compliance model.
The vault mitigates agent-related risks through layered defenses:

- **Content trust hierarchy**: `raw/` is untrusted input; `wiki/` is
  agent-generated (may contain errors); config files are trusted
- **Pre-commit hooks**: Enforce hard rules, reject symlinks, warn on
  sensitive file modifications
- **CI checks**: Lint, shellcheck, and skill audit run on every PR
- **Skill hardening** (optional): Policy-based validation of Claude Code
  skills, blocking dangerous patterns and tool escalation

See `CLAUDE.md` Security section for the full agent constraint set.

### Supply Chain Considerations

- GitHub Actions are SHA-pinned (not tag-based) to prevent tag-retargeting
- Obsidian plugins run with full filesystem access — see `docs/plugin-security.md`
- MCP servers use stdio transport with no authentication layer
- Skill hardening can block malicious Claude Code skills at commit time

### Configuration Hardening Checklist

- [ ] Enable branch protection on `main` (require PR reviews)
- [ ] Add CODEOWNERS requiring human approval for `.vault/`, `.github/`, config files
- [ ] Run `bash .vault/scripts/init.sh` and choose skill hardening level
- [ ] Review `.gitignore` includes `.claude/settings*.json`
- [ ] Disable Obsidian plugin auto-updates for security-critical vaults
- [ ] Consider signed commits for authorship provenance
- [ ] Run `vault-tools.sh skill-audit` before installing third-party skills
- [ ] Periodically audit `wiki/` content for accuracy
- [ ] Back up your vault regularly (push to a remote)
