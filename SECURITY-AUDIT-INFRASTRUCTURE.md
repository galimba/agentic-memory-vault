# Security Audit: Infrastructure and Supply Chain

**Date**: 2026-04-10
**Scope**: CI/CD pipeline, dependencies, supply chain, secrets, license compliance
**Auditor**: Automated security audit

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 1 (remediated) |
| HIGH     | 1 (remediated) |
| MEDIUM   | 2 (1 remediated, 1 documented) |
| LOW      | 2 (documented) |
| INFO     | 4 |

## CRITICAL Findings

### C-1: GitHub Actions pinned by mutable tags (REMEDIATED)

All 4 third-party actions used mutable tag references (`@v4`, `@v19`, `@v1`).
An attacker who compromises a maintainer's GitHub PAT can retag a malicious commit
(as demonstrated by CVE-2025-30066 on tj-actions/changed-files and
CVE-2025-30154 on reviewdog/action-setup).

**Actions taken**: All actions in `.github/workflows/lint.yml` are now pinned to
full 40-character commit SHAs with tag comments for readability.

| Action | Old | New SHA |
|--------|-----|---------|
| actions/checkout | @v4 | @34e114876b0b11c390a56381ad16ebd13914f8d5 |
| DavidAnson/markdownlint-cli2-action | @v19 | @05f32210e84442804257b2a6f20b273450ec8265 |
| crate-ci/typos | @v1 | @02ea592e44b3a53c302f697cddca7641cd051c3d |

## HIGH Findings

### H-1: Missing workflow permissions block (REMEDIATED)

The workflow had no `permissions:` block, defaulting to the repository's global
permissions (often `write-all` for public repos). This violates the principle of
least privilege.

**Action taken**: Added `permissions: contents: read` at both workflow and job levels.
No job requires write permissions.

## MEDIUM Findings

### M-1: Obsidian plugin data.json not gitignored (REMEDIATED)

`.obsidian/plugins/*/data.json` files can contain API keys, tokens, and sensitive
plugin configuration. These were not excluded by `.gitignore`.

**Action taken**: Added `.obsidian/plugins/*/data.json` to `.gitignore`.

### M-2: MCP server supply chain risks (DOCUMENTED)

Local MCP servers use stdio transport with no authentication. Documented risks:
- 9 documented MCP security incidents in 2025
- Tool poisoning: hidden instructions in tool descriptions enable data exfiltration
- MCPVault v0.9.1 fixed symlink-based path traversal bypass
- No standard mechanism to verify MCP server integrity

See `docs/security-audit-infrastructure-details.md` for full analysis.

## LOW Findings

### L-1: Template placeholder values in issue templates

`.github/ISSUE_TEMPLATE/config.yml` contains `{{GITHUB_ORG}}` placeholders.
These will produce broken URLs until replaced during initialization. Not a
security risk but could confuse users of template-generated repos.

### L-2: Obsidian plugin supply chain

Obsidian plugins run unsandboxed with full filesystem and network access.
CVE-2021-42057 demonstrated code execution via Dataview plugin injection.
Several common plugins (Cortex, Claudian) transmit vault content to external APIs.

See `docs/plugin-security.md` for full analysis and recommendations.

## INFO Findings

### I-1: No secrets, credentials, or PII detected

Full-repo scan found no API keys, tokens, passwords, private keys, connection
strings, email addresses, or `.env` files. `.gitignore` correctly excludes
`.env`, `*.key`, and `*.pem`.

### I-2: Fork PR safety verified

The workflow uses only `push` (to main) and `pull_request` triggers.
No `pull_request_target` trigger exists. Fork PRs cannot access repository
secrets. No user-controlled values are interpolated in `run:` blocks.

### I-3: Template repository safety verified

No cached tokens, secrets, or environment-specific values exist in tracked files.
Git hooks are not copied by "Use this template" (they install via `init.sh`).
Workflows do not reference the template org/repo name in ways that would break.

### I-4: License compliance verified

Apache 2.0 license is properly applied. CODE_OF_CONDUCT.md references
Contributor Covenant v2.1 (CC-BY-4.0 licensed, compatible with Apache 2.0).
No code from incompatible licenses detected.

## Detailed Reports

- `docs/plugin-security.md` -- Obsidian plugin supply chain risks
- `docs/security-audit-infrastructure-details.md` -- MCP risks and extended analysis
