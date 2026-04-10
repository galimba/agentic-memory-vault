# Security Audit Details: Infrastructure and Supply Chain

**Date**: 2026-04-10
**Parent report**: `SECURITY-AUDIT-INFRASTRUCTURE.md`

## GitHub Actions Supply Chain Analysis

### Actions Used and Risk Assessment

| Action | Maintainer | Risk | Notes |
|--------|-----------|------|-------|
| actions/checkout | GitHub (Microsoft) | Low | First-party, widely audited |
| DavidAnson/markdownlint-cli2-action | Single maintainer | Medium | Well-maintained, popular |
| crate-ci/typos | Small team | Medium | Rust ecosystem, active |

### Relevant Supply Chain Incidents (2025)

- **CVE-2025-30066 (tj-actions/changed-files)**: Attacker compromised a maintainer PAT,
  retargeted 350+ git tags to point at a malicious commit. All repos using tag-based
  pinning executed the attacker's code. CI environment variables were exfiltrated.
- **CVE-2025-30154 (reviewdog/action-setup)**: Upstream compromise cascaded to all
  downstream reviewdog actions. Demonstrated transitive dependency risk.
- **Codecov Bash Uploader (2021)**: Malicious curl command injected into the Bash
  uploader script. CI environment variables (including secrets) were exfiltrated for
  two months before detection.

### SHA Pinning Rationale

Tags are mutable references. A compromised maintainer can `git tag -f v4 <malicious-sha>`
and push. SHA pinning ensures the exact code reviewed at pin time is what executes.
The trade-off is that updates require manual SHA bumps, but this is the correct security
posture for CI pipelines that process sensitive code.

## Workflow Security Analysis

### Trigger Safety

The workflow uses two triggers:
- `push: branches: [main]` -- only runs on direct pushes to main
- `pull_request` -- runs on PR events from any branch, including forks

The `pull_request` event is safe: GitHub does not provide repository secrets
to workflows triggered by fork PRs. The `push` trigger only fires on main,
which should be branch-protected.

### Permission Model

All jobs require only `contents: read`. No job needs to:
- Write to the repository
- Create/modify issues or PRs
- Access packages or deployments
- Manage repository settings

The `permissions` block is set at both workflow and job levels for defense in depth.

### Injection Vectors

No `run:` blocks interpolate user-controlled values. The workflow does not use:
- `${{ github.event.issue.title }}`
- `${{ github.event.pull_request.body }}`
- `${{ github.head_ref }}`
- Any other attacker-controllable expression in shell commands

## MCP Server Supply Chain Risks

### Architecture Risk

MCP servers communicate via stdio with no authentication layer. Any process that
can connect to the stdio pipe can send tool calls. This means:
- No mutual authentication between client and server
- No integrity verification of tool responses
- No audit logging at the protocol level

### Documented MCP Security Incidents (2025)

Nine documented incidents including:
1. **Tool poisoning**: Hidden instructions embedded in tool descriptions direct
   the LLM to exfiltrate sensitive data through seemingly benign tool calls
2. **MCPVault v0.9.1**: Symlink-based path traversal allowed reading files
   outside the configured vault directory
3. **Prompt injection via tool responses**: Malicious MCP servers return responses
   containing instructions that override the LLM's system prompt

### Recommendations for MCP Server Trust

1. **Vet server source code** before deployment -- treat MCP servers as trusted code
2. **Run servers in containers** or sandboxed environments with minimal filesystem access
3. **Pin server versions** and review changes before updating
4. **Monitor server behavior** -- log all tool calls and responses
5. **Limit file access** -- configure servers to access only necessary directories
6. **Do not expose MCP servers to untrusted networks** -- stdio is local-only by design
7. **Treat tool descriptions as untrusted input** -- they can contain injection payloads

## Secret Scanning Results

### Scan Coverage

All files in the repository were scanned for:
- API keys and tokens (regex patterns for common providers)
- Passwords and connection strings
- Private keys (PEM, RSA, SSH formats)
- `.env` files and references
- Email addresses and usernames
- Hardcoded internal infrastructure URLs

### Results

**No secrets, credentials, or PII detected.**

The `.gitignore` correctly excludes:
- `.env` and `.env.*` (with `.env.example` exception)
- `*.key` and `*.pem`
- `.obsidian/plugins/*/data.json` (added by this audit)

### Template Safety

Template placeholder values (`{{VAULT_NAME}}`, `{{ORG_NAME}}`, etc.) are used
throughout the repo. These are replaced during initialization and contain no
sensitive defaults.

## License Compliance

- **Repository license**: Apache 2.0 (full text in `LICENSE`)
- **Code of Conduct**: Contributor Covenant v2.1 (CC-BY-4.0, compatible)
- **Dependencies**: No runtime dependencies; CI actions are Apache 2.0 or MIT licensed
- **No incompatible licenses detected**
