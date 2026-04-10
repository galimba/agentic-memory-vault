# Ingestion Guide

Step-by-step instructions for ingesting source documents into the vault. Ingestion is the primary way knowledge enters the system.

## What Belongs in raw/

The `raw/` directory accepts source material that agents will summarize and extract knowledge from:

- Markdown documents (`.md`)
- Plain text files (`.txt`)
- Exported notes from Confluence, Notion, Google Docs
- Meeting transcripts and minutes
- Technical specifications and RFCs
- Retrospectives and post-mortems
- Strategy documents and proposals
- Research papers and articles (as markdown or text)
- Binary files (PDFs, images) for reference -- stored in `raw/` but not processed by agents

## What Does NOT Belong in raw/

- **Secrets or credentials** -- API keys, passwords, tokens
- **PII** -- customer names, emails, account numbers (unless explicitly approved)
- **Entire code repositories** -- use links to repos instead
- **Duplicate content** -- if it is already in `raw/`, do not add it again
- **Temporary or ephemeral content** -- daily standups, one-off chats

## Preparing a Document for Ingestion

1. **Convert to markdown or plain text.** Agents process text, not binary formats.
2. **Use a descriptive filename** in kebab-case: `q1-engineering-retro.md`, not `doc1.md`.
3. **Include context at the top.** If the document lacks a title or date, add a brief header so the agent knows what it is reading.
4. **Remove sensitive information.** Redact PII, secrets, or privileged content before adding to `raw/`.

## Concrete Example: Ingesting a Q1 Retrospective

### Step 1: Add the source document

Create `raw/q1-engineering-retro.md`:

```markdown
# Q1 2026 Engineering Retrospective

**Date**: 2026-04-01
**Participants**: Platform team, Backend team, SRE

## What Went Well
- Migrated 3 services to Kubernetes, reducing deploy time by 40%
- Adopted LangGraph for agent orchestration pilot

## What Needs Improvement
- Incident response time averaged 45 minutes (target: 15)
- Test coverage dropped from 85% to 72%

## Action Items
- Implement on-call runbooks for top 5 failure modes
- Mandate 80% coverage gate in CI pipeline
```

### Step 2: Commit the raw file

```bash
git add raw/q1-engineering-retro.md
git commit -m "[human] Added Q1 2026 engineering retrospective"
```

### Step 3: Tell the agent to ingest

> "Ingest the new file at raw/q1-engineering-retro.md"

### Step 4: What the agent creates

The agent follows the 7-step INGEST operation:

| Step | Action | Result |
|------|--------|--------|
| 1 | Read source in `raw/` | Agent reads `raw/q1-engineering-retro.md` |
| 2 | Create summary | `wiki/sources/source-q1-engineering-retro.md` |
| 3 | Update index | New entry in `wiki/index.md` |
| 4 | Update related pages | Creates/updates `concept-incident-response.md`, `entity-langgraph.md`, `concept-test-coverage.md`, etc. |
| 5 | Append to log | New entry in `wiki/log.md` |
| 6 | Validate files | Checks frontmatter against `.vault/schemas/frontmatter.md` |
| 7 | Verify tags | Ensures all tags are in `.vault/rules/tags.md` |

### Step 5: Review the output

Check the source summary:

- Does it capture the key claims? (Kubernetes migration, LangGraph adoption, incident response gap)
- Does it link back to the raw source? (`sources: ["[[raw/q1-engineering-retro.md]]"]`)
- Is it 20-50% the length of the original? (SR-004)

Check the index entry in `wiki/index.md`:

- Is the new source summary listed?
- Are new concept/entity pages listed?

Check `wiki/log.md` for the ingestion record:

```markdown
## [2026-04-10] ingest | Q1 Engineering Retrospective
- **Agent**: claude-code
- **Files modified**: wiki/sources/source-q1-engineering-retro.md, wiki/index.md, ...
- **Summary**: Ingested Q1 retro, created 4 new pages, updated 3 existing
```

## The 7 INGEST Steps Explained

1. **Read source**: The agent reads the raw file in full. It does not modify it (HR-001).
2. **Create summary**: A new page in `wiki/sources/` with frontmatter, key takeaways, and source link. Named `source-{{original-filename}}.md`.
3. **Update index**: Add the source summary and any new pages to `wiki/index.md` with one-line descriptions (HR-008).
4. **Update related pages**: The agent identifies 5-15 existing wiki pages that relate to the new source and updates them with new information or links (SR-011). It may also create new concept, entity, or comparison pages.
5. **Append to log**: A timestamped entry in `wiki/log.md` recording the operation (SR-005).
6. **Validate**: The agent checks all modified files against the frontmatter schema.
7. **Verify tags**: All tags on modified files are checked against `.vault/rules/tags.md` (HR-003, HR-009).

## Batch Ingestion

For initial vault setup when you have many existing documents:

1. Drop all source files into `raw/` and commit with `[human]` prefix.
2. Override SR-001 (one source at a time) by telling the agent: "Batch ingest all new files in raw/. Process each one sequentially."
3. After batch ingestion, run a full lint pass: `bash .vault/scripts/vault-tools.sh lint`
4. Review the generated wiki pages. Batch ingestion may produce lower-quality cross-references because the agent processes sources without seeing the full wiki state.
5. Run orphan detection: `bash .vault/scripts/vault-tools.sh orphans` and address any disconnected pages.
