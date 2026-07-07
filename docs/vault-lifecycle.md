# Vault Lifecycle

A Memory Vault goes through five phases: setup, seeding, active use, maintenance, and evolution. This guide describes each phase, what to expect, and how to measure success.

## Phase 1: Setup (1 Day)

**Goal**: A configured, empty vault ready for content.

### Checklist

- [ ] Clone the boilerplate repository
- [ ] Run `bash .vault/scripts/init.sh` (set vault name, org, platform)
- [ ] Run `bash .vault/scripts/vault-tools.sh doctor` to verify structure
- [ ] Review `.vault/rules/soft-rules.md` and adjust defaults for your organization
- [ ] Review `.vault/rules/tags.md` and add domain-specific tags under `custom/`
- [ ] Fill in `docs/company-context.md` with your organization's details
- [ ] Configure branch protection on `main` (require PR reviews, require CI pass)
- [ ] Verify the pre-commit hook is installed: check `.git/hooks/pre-commit`
- [ ] Make your first commit and confirm the pre-commit hook runs

### What success looks like

`vault-tools.sh doctor` reports all directories present, all required files found, hooks installed. Zero content yet, but infrastructure is solid.

## Phase 2: Seeding (1-2 Weeks)

**Goal**: A vault with foundational knowledge -- enough for agents to answer basic questions about your organization.

### Checklist

- [ ] Identify 10-20 foundational documents (architecture decisions, key retrospectives, product specs, onboarding guides)
- [ ] Add documents to `raw/` with descriptive filenames
- [ ] Ingest documents one at a time (SR-001), reviewing agent output after each
- [ ] After every 5 ingestions, run `vault-tools.sh lint` and fix issues
- [ ] Review the wiki graph in Obsidian (if using) to spot disconnected clusters
- [ ] Run `vault-tools.sh orphans` and address orphan pages

### What success looks like

- 10-20 source summaries in `wiki/sources/`
- 20-40 concept and entity pages in `wiki/concepts/` and `wiki/entities/`
- `wiki/index.md` has entries for all pages
- Average link density of 3+ wikilinks per page
- An agent can answer basic questions about your domain using vault content

## Phase 3: Active Use (Ongoing)

**Goal**: The vault is a living knowledge base that grows with your organization.

### Patterns

- **Regular ingestion**: New documents are added to `raw/` and ingested weekly or as they are produced.
- **Query-driven growth**: Agents answer questions and file substantive answers back as wiki pages (SR-012).
- **Agent-driven connections**: Each ingestion updates every materially affected page (SR-011), increasing knowledge density.
- **Human review**: PRs from agent branches are reviewed before merging to `main`.

### What to watch for

- **Orphan accumulation**: Pages created without sufficient links. Run `vault-tools.sh orphans` weekly.
- **Tag sprawl**: Agents creating tags not in the taxonomy. Run `vault-tools.sh tag-audit` weekly.
- **Summary quality drift**: Agents producing shallow summaries. Spot-check `wiki/sources/` regularly.

## Phase 4: Maintenance (Weekly)

**Goal**: Keep the vault healthy, accurate, and well-connected.

### Weekly routine

1. **Run lint**: `bash .vault/scripts/vault-tools.sh lint`
2. **Review stale pages**: `bash .vault/scripts/vault-tools.sh stale`
3. **Check orphans**: `bash .vault/scripts/vault-tools.sh orphans`
4. **Audit tags**: `bash .vault/scripts/vault-tools.sh tag-audit`
5. **Review vault stats**: `bash .vault/scripts/vault-tools.sh stats`

### Addressing lint findings

| Finding | Action |
|---------|--------|
| Missing frontmatter | Agent or human adds required fields |
| Unapproved tags | Add to `tags.md` or replace with approved tag |
| Over 200 lines (warn) / 400 lines (block) | Split into linked sub-pages |
| Orphan page | Add inbound links from related pages or archive |
| Stale page | Re-read source, update content, or mark `status: archived` |
| Not in index | Run `vault-tools.sh index-update` |

## Phase 5: Evolution (Monthly)

**Goal**: Adapt the vault structure and rules as your needs change.

### Monthly review

- **Rules**: Are any soft rules consistently overridden? Update the default.
- **Tags**: Are new tag prefixes needed? Is the `custom/` section growing? Promote frequent custom tags to standard prefixes.
- **Templates**: Do the templates in `templates/` match how agents actually create pages? Update them.
- **Thresholds**: Is the 30-day staleness threshold right for all domains? Tune in `staleness-config.json`.
- **Archive**: Move deprecated or superseded pages to `status: archived`. They remain searchable but are deprioritized.

## Success Metrics

Track these metrics monthly using `vault-tools.sh stats`:

| Metric | Target | How to measure |
|--------|--------|----------------|
| Total wiki pages | Growing month-over-month | `stats` command: "Wiki pages" |
| Link density | 3+ avg wikilinks per page | `stats` command: "Avg links/page" |
| Orphan ratio | Under 10% of pages | `orphans` command count / total pages |
| Stale ratio | Under 15% of pages | `stale` command count / total pages |
| Lint violations | Zero blocking violations | `lint` command: "Violations (blocking)" |
| Query answer rate | Agents answer 80%+ of questions using vault content | Manual tracking |

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Ingesting too many sources at once | Low-quality summaries, many orphans | Slow down, ingest 1-2 per day, review each |
| Skipping lint | Violations accumulate, pre-commit hooks become a wall | Run lint weekly, fix incrementally |
| Not reviewing agent output | Hallucinated content enters the wiki | Spot-check 20% of new pages per week |
| Tag proliferation | Agents invent unapproved tags | Run tag-audit, enforce HR-003 |
| Ignoring orphans | Knowledge graph fragments | Link orphans or archive them monthly |
| Never archiving | Stale pages dilute search quality | Archive pages that are no longer relevant |
| Monolithic pages | Pages hit 200-line limit, forced splits are awkward | Write modularly from the start |
