# Git Workflow

This guide covers branching, commit conventions, PR workflow, CI integration, multi-agent concurrency, and conflict resolution for the Memory Vault.

## Branch Naming

| Actor | Pattern | Example |
|-------|---------|---------|
| Agent | `agent/{{agent-id}}/{{task}}` | `agent/claude-01/ingest-q1-retro` |
| Human | `feature/{{description}}` | `feature/add-security-tags` |
| Human | `fix/{{description}}` | `fix/broken-frontmatter` |
| Maintenance | `chore/{{description}}` | `chore/weekly-lint-fixes` |

Agent IDs should be short and stable across sessions (e.g., `claude-01`, `codex-02`, `cursor-main`).

## Commit Message Format

All commits follow the pattern: `[operation] description`

### Standard operations

| Prefix | When to use | Example |
|--------|-------------|---------|
| `[ingest]` | Source ingestion | `[ingest] Added source on Q1 engineering retro` |
| `[query]` | Filing a query answer | `[query] Filed answer on deployment pipeline design` |
| `[lint]` | Fixing lint issues | `[lint] Fixed orphan pages and missing index entries` |
| `[raw]` | Adding files to `raw/` (via PR) | `[raw] Added raw source document` |
| `[tags]` | Tag taxonomy changes | `[tags] Added custom/acme-onboarding` |
| `[config]` | Vault configuration | `[config] Updated staleness thresholds` |
| `[fix]` | Bug fixes | `[fix] Corrected broken wikilink in concept-api.md` |
| `[chore]` | Maintenance | `[chore] Rebuilt index after merge` |

### Commit atomicity

Each commit should represent one logical change:

- One source ingestion (including all generated pages) = one commit
- One lint fix session = one commit
- One tag addition = one commit

Do not bundle unrelated changes. This makes PRs reviewable and reverts safe.

## PR Workflow

### Agent-initiated PRs

1. Agent creates branch from `main`: `agent/claude-01/ingest-q1-retro`
2. Agent performs the operation and commits
3. Agent (or human) opens a PR to `main`
4. CI runs (markdownlint, shellcheck, yamllint, typos, vault-doctor)
5. Human reviews: checks summary quality, frontmatter correctness, link density
6. Human merges (squash or merge commit, per team preference)
7. Agent branch is deleted after merge

### What to review in PRs

| Check | What to look for |
|-------|-----------------|
| Source summary | Captures key claims, links to raw source, correct length |
| Frontmatter | All required fields, correct type and status, valid tags |
| Links | 3+ wikilinks per page, links resolve to real pages |
| Index | New pages are registered in `wiki/index.md` |
| Log | Ingestion/query recorded in `wiki/log.md` |
| No `raw/` changes | Agents must not modify `raw/` (enforced by HR-001) |

## Branch Protection

Configure these settings on `main` in your Git hosting provider:

### Recommended settings

- **Require pull request reviews**: At least 1 approval before merge
- **Require status checks to pass**: Enable the `lint.yml` CI jobs
- **No direct push to main**: All changes go through PRs
- **Require branches to be up to date**: Prevents stale merges
- **Auto-delete head branches**: Clean up after merge

### Status checks to require

From `.github/workflows/lint.yml`:

- `lint-markdown` -- markdownlint on all `.md` files
- `lint-shell` -- ShellCheck on `.vault/**/*.sh`
- `lint-yaml` -- yamllint on YAML/JSON config files
- `check-typos` -- typos checker across the vault
- `vault-doctor` -- full vault diagnostic via `vault-tools.sh doctor`

## CI Integration

The vault ships with `.github/workflows/lint.yml` that runs on every push to `main` and every PR.

### Adding custom CI checks

To add a check, add a new job to `lint.yml`:

```yaml
  custom-check:
    name: Custom Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Your check
        run: bash .vault/scripts/vault-tools.sh your-command
```

The `vault-tools.sh` script supports extending with new commands -- add a `cmd_your_command()` function and register it in the `main()` case statement.

## Multi-Agent Concurrency

Multiple agents can work on the vault simultaneously because each operates on its own branch.

### How it works

1. Agent A creates `agent/claude-01/ingest-source-a`
2. Agent B creates `agent/codex-02/ingest-source-b`
3. Both work in parallel, committing to their own branches
4. Both open PRs to `main`
5. First PR merges cleanly
6. Second PR may have conflicts (usually in `wiki/index.md` or `wiki/log.md`)
7. Human resolves conflicts and merges

### Reducing conflicts

- Agents should pull latest `main` before starting work
- Keep operations atomic -- small, focused changes merge more cleanly
- Stagger large ingestions rather than running them in parallel

## Resolving Conflicts

### wiki/index.md (most common)

The index is the highest-conflict file because every ingestion adds entries.

**Resolution**: Do not manually merge. Instead, rebuild the index:

```bash
git checkout main
git pull
git checkout agent/your-branch
git rebase main
# If index.md conflicts:
bash .vault/scripts/vault-tools.sh index-rebuild
git add wiki/index.md
git rebase --continue
```

### wiki/log.md (occasional)

The log is append-only. Both sides added entries at the end.

**Resolution**: Accept both entries and sort by date:

```bash
# During merge/rebase, accept both changes
# Ensure entries are in chronological order
git add wiki/log.md
```

### Content pages (rare)

Two agents rarely edit the same concept or entity page. When they do:

**Resolution**: The second agent should re-read the page (now including the first agent's
changes) and reconcile its additions. This is a manual process --
the human reviewer should verify both contributions are preserved.

### Prevention

To avoid conflicts entirely for large operations, use a sequential workflow:

1. Agent A ingests and merges
2. Agent B pulls `main`, then ingests and merges
3. Repeat

This is slower but eliminates all conflict risk.
