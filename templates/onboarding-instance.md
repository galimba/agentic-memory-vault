# Onboarding Guide -- {{VAULT_NAME}}

Welcome to {{VAULT_NAME}}, {{ORG_NAME}}'s knowledge vault. This guide covers
everything you need to start contributing, whether you write code or not.

## What Is This Vault

{{VAULT_NAME}} is a git-based knowledge management system where AI agents and
humans collaborate to build institutional memory. Source documents go into `raw/`,
agents process them into structured wiki pages in `wiki/`, and the vault maintains
itself through automated linting and health checks.

Three operations drive everything:

- **INGEST** -- An agent reads a source document and creates structured wiki pages
- **QUERY** -- An agent answers questions using the vault's knowledge
- **LINT** -- Automated checks find stale content, orphan pages, and rule violations

## For Engineers

### Setup

```bash
git clone https://github.com/{{GITHUB_ORG}}/{{REPO_NAME}}.git
cd {{REPO_NAME}}
bash .vault/scripts/vault-tools.sh doctor   # Verify everything is healthy
```

See [Getting Started](getting-started.md) for detailed setup including prerequisites.

### Adding Knowledge

1. **Add a source document** to `raw/` via a pull request:

   ```bash
   git checkout -b add/my-document
   cp ~/documents/my-doc.md raw/
   git add raw/my-doc.md
   git commit -m "Added my-doc source"
   git push -u origin add/my-document
   ```

   Note: The pre-commit hook blocks direct commits to `raw/`. Use PRs, which
   bypass client-side hooks at merge time.

2. **Tell your agent to ingest it**:

   > "Ingest the new file in raw/my-doc.md"

3. **Review the output**: Check `wiki/sources/`, `wiki/concepts/`, `wiki/entities/`
   for the generated pages. Verify accuracy and suggest corrections.

### Git Workflow

- Each agent session creates its own branch: `agent/<id>/<task>`
- Changes merge through pull requests
- CODEOWNERS requires maintainer approval for `.vault/`, `.github/`, and config files
- See [Git Workflow Guide](git-workflow.md) for conflict resolution

### The Three Operations

**INGEST**: Tell your agent to process a file from `raw/`. The agent creates a
summary in `wiki/sources/`, updates or creates concept/entity pages, registers
everything in `wiki/index.md`, and logs the operation in `wiki/log.md`.

**QUERY**: Ask your agent a question. It reads `wiki/index.md` to find relevant
pages, synthesizes an answer with `[[wikilink]]` citations, and optionally files
the answer as a new wiki page.

**LINT**: Run `bash .vault/scripts/vault-tools.sh lint` or ask your agent to lint.
It checks frontmatter, tags, line counts, orphans, staleness, and index completeness.

### Rules You Must Know

**Hard rules** are enforced by git hooks and will block your commit:

| Rule | Impact |
|------|--------|
| HR-001 | `raw/` is immutable -- add files via PRs only |
| HR-002 | Every wiki page needs valid YAML frontmatter |
| HR-003 | Every wiki page needs at least one approved tag |
| HR-004 | Markdown pages: warn at 200 lines, block at 400 |
| HR-006 | Wiki page titles must be unique |
| HR-007 | The `updated` frontmatter field must be accurate |
| HR-008 | Every wiki page must appear in `wiki/index.md` |
| HR-014 | Never delete wiki/memory files -- archive instead |
| HR-015 | Log files are append-only |

**Soft rules** are guidelines that won't block commits but should be followed:

| Guideline | Default |
|-----------|---------|
| Target page length | 80-150 lines |
| Minimum wikilinks per page | 3 |
| Staleness threshold | 30 days without update triggers review |
| Lint frequency | At least weekly |

Full rules: `.vault/rules/hard-rules.md` and `.vault/rules/soft-rules.md`

### The 200-Line Page Budget

Wiki pages should target 80-150 lines. This is not arbitrary -- it is sized for
agent context windows. A 200-line page fits comfortably in an agent's working
memory alongside the index and other context. Pages over 400 lines are blocked
by HR-004. If a page grows too large, split it into linked sub-pages.

### Context Rot

Knowledge decays. The vault fights this with:

- **Staleness detection**: Pages not updated in 30+ days are flagged during lint
  (threshold varies by domain -- see `.vault/schemas/staleness-config.json`)
- **Orphan detection**: Pages with no inbound links are flagged
- **Confidence tracking**: Each page has a `confidence` field (high/medium/low/unverified)
- **Regular lint runs**: Schedule weekly lints to catch drift early

## For Non-Technical Contributors

You do not need git expertise to contribute to {{VAULT_NAME}}. Here are the
main ways you can help:

### Browse the Vault

- **On GitHub**: Navigate to `wiki/index.md` in the repository to see all pages.
  Click through to read any page.
- **In Obsidian** (optional): Clone the repository and open it as an Obsidian vault.
  The graph view shows how pages connect to each other.

### Upload Source Documents

1. Go to the repository on GitHub
2. Navigate to the `raw/` folder
3. Click "Add file" then "Upload files"
4. Drag your document (markdown preferred) and create a pull request
5. A maintainer will merge it, then an agent will process it

### Review Agent-Generated Pages

After an agent ingests a document, review the generated pages in `wiki/`:

- Are the key claims captured accurately?
- Are important entities (people, tools, teams) identified?
- Are the connections to other concepts reasonable?
- Is anything missing or misrepresented?

Open an issue or leave a PR comment if you find problems.

### Flag Stale Information

If you notice a wiki page that is outdated:

- Open an issue describing what changed and which page is affected
- Or edit the page directly: update the content and set `status: review` in the
  frontmatter so a maintainer can verify

### Write Decision Records

Important decisions should be documented. Use the template at
`templates/template-decision.md` to create an Architecture Decision Record (ADR)
in `memory/decisions/`.

## Getting Help

- [Getting Started Guide](getting-started.md) -- Detailed setup and first operations
- [Configuration Guide](configuration.md) -- Customizing rules, tags, and thresholds
- [SUPPORT.md](../SUPPORT.md) -- How to get help and report issues
- [Full Template Reference](vault-template-readme.md) -- Complete architecture, rules, FAQ
