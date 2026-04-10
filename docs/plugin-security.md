# Obsidian Plugin Supply Chain Security

## Threat Model

Obsidian plugins run with **full filesystem and network access**. There is no sandboxing,
no permission model, and no capability restrictions. Any installed plugin can read, write,
or delete any file the Obsidian process can access, and make arbitrary network requests.

## Key Risks

### No Sandboxing

- Plugins execute arbitrary JavaScript in Obsidian's Electron runtime
- A plugin can read your entire vault, exfiltrate contents, or modify files silently
- Plugins can access environment variables, local network services, and the clipboard

### Auto-Update Risk

- After initial community review, plugin updates deploy automatically
- A compromised maintainer account can push malicious code to all users
- There is no re-review process for updates; only new plugins are reviewed

### Known Vulnerabilities

- **CVE-2021-42057**: Dataview plugin had arbitrary code execution via code-evaluation
  injection. Malicious vault content could execute code through Dataview queries
- Community plugins have no formal CVE tracking process

### Plugins That Send Content to External APIs

These plugins transmit vault content over the network by design:

- **Cortex** -- sends note content to AI APIs for summarization and linking
- **Claudian** -- sends vault content to Anthropic's Claude API
- **Various GPT plugins** -- send content to OpenAI endpoints
- **Remotely Save / Obsidian Git** -- sync vault contents to external services
- **Readwise / Zotero integrations** -- exchange data with external services

Any plugin making network requests can potentially exfiltrate vault data.

## How to Audit Plugin Behavior

1. **Review source code** before installing -- all community plugins are open source
2. **Check the plugin's `main.js`** for `fetch()`, `XMLHttpRequest`, `requestUrl`,
   `require('child_process')`, or `require('fs')` calls
3. **Monitor network traffic** using browser DevTools (Ctrl+Shift+I in Obsidian)
4. **Review `data.json`** in `.obsidian/plugins/<plugin>/` for stored credentials
5. **Check plugin permissions** in the community plugin listing
6. **Review the maintainer's GitHub profile** -- single-maintainer plugins are higher risk

## Recommendations for Security-Sensitive Vaults

### Do

- Pin plugin versions by disabling auto-update in Settings > Community Plugins
- Audit plugin source code before installation and after each manual update
- Add `.obsidian/plugins/*/data.json` to `.gitignore` (may contain API keys)
- Use a separate Obsidian vault for sensitive content vs. general notes
- Prefer plugins with multiple maintainers and active development

### Do Not

- Do not install plugins that require API keys without understanding the data flow
- Do not enable "Restricted Mode Off" on vaults containing secrets or credentials
- Do not use community plugins in air-gapped or compliance-regulated environments
  without formal security review
- Do not trust plugins solely based on download count or star ratings

### Plugins to Avoid in High-Security Environments

- Any plugin that sends content to external AI APIs (Cortex, Claudian, GPT plugins)
- Plugins that sync to third-party cloud services without encryption
- Plugins from inactive or single-commit repositories
- Plugins that request filesystem access outside the vault directory

## MCP Server Integration Warning

When using Obsidian alongside MCP servers (e.g., for AI agent workflows),
the attack surface compounds. A compromised plugin could manipulate vault files
that MCP servers then process, creating a transitive trust chain.
See the security audit report for MCP-specific risks.
