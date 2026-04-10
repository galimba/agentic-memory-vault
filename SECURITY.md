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

### Recommended Security Posture

- Use git branch protection on `main`
- Require PR reviews before merging agent-generated content
- Run `vault-tools.sh lint` in CI on every PR
- Periodically audit `wiki/` content for accuracy and appropriateness
- Back up your vault regularly (it's a git repo — push to a remote)
