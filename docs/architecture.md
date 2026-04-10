# Architecture

This document explains the design decisions behind the Memory Vault: why it is structured this way, what alternatives were considered, and how the pieces fit together.

## Why Three Layers

The vault follows the **Karpathy LLM Wiki** pattern: separate provenance from synthesis from operations.

| Layer | Directory | Owner | Mutability |
|-------|-----------|-------|------------|
| 1. Source | `raw/` | Human | Immutable (HR-001) |
| 2. Knowledge | `wiki/` | Agent | Agent-writable, human-reviewable |
| 3. Operations | `memory/` | Agent | Decisions, logs, notes, status |

**Rationale**: When sources are immutable, every claim in the wiki can be traced back to an
unmodified original. If agents could edit sources, you lose ground truth.
If knowledge and operations are mixed, you cannot distinguish
"what we know" from "what we decided to do about it."

**Alternative considered**: A single flat directory with metadata-based filtering.
Rejected because agents perform better with explicit directory-level affordances --
reading `wiki/sources/` is unambiguous in a way that filtering by `type: source`
across a flat namespace is not.

## Why Flat Tags Over Nested Hierarchies

Tags use **flat prefix notation**: `domain/engineering`, `type/concept`, `lifecycle/active`.

**Rationale**: Agent parseability. A single regex (`^prefix/value$`) extracts any tag.
Nested hierarchies (`domain/engineering/backend/api`) require recursive parsing
and introduce ambiguity -- is `backend` a sub-domain or a team?
Flat prefixes keep every tag exactly one level deep, making programmatic filtering trivial.

**Alternative considered**: Obsidian's nested tag syntax (`#domain/engineering/backend`).
Rejected because nesting creates implicit parent tags and agents must decide
at which level to filter. With flat tags, you use `dept/backend` separately
from `domain/engineering` -- explicit over implicit.

## Why Markdown Length Limits (HR-004)

Markdown files in `wiki/` or `memory/` should stay under 200 lines (warning)
and must not exceed 400 lines (hard block).

**Rationale**: Context window optimization. Agents process pages individually.
A 500-line page forces an agent to load irrelevant content alongside relevant content,
wasting tokens and reducing precision.
Short, focused pages with clear `[[wikilinks]]` between them enable targeted retrieval --
the agent reads only the pages it needs.

The 200-line target encourages modular knowledge: instead of one sprawling "API Design" page,
you get `concept-api-design-principles.md`, `concept-api-versioning.md`,
and `concept-api-error-handling.md`, each focused and independently retrievable.
The 400-line ceiling catches files that genuinely need splitting.

**Exception**: `wiki/index.md` and `wiki/log.md` are exempt. They grow indefinitely by design. When `index.md` exceeds 500 lines, split into category-specific index files.

## Why Code Length Limits (HR-005)

Standalone code files in `.vault/` should stay under 400 lines (warning)
and must not exceed 600 lines (hard block).

**Rationale**: Modularity over monoliths. Long code files are hard to read,
review, and maintain. The vault ships with modular code files: entry points
(`vault-tools.sh`, `pre-commit.sh`) source focused library files
(`lib-utils.sh`, `lib-lint.sh`, `lib-hook-checks.sh`, etc.).
Each module has clear responsibilities and can be reviewed independently.

**Exception**: Library files (`lib-*.sh`) sourced by an entry point are exempt.
Configuration files (`.json`, `.yaml`, `.toml`) are exempt.

## Why Index-Based Retrieval Over Vector Databases

The vault uses `wiki/index.md` as its primary retrieval mechanism, not embeddings or vector search.

**Rationale**: At vault scale (hundreds of pages, not millions), a deterministic index outperforms semantic search for agents:

- **Deterministic**: The agent reads the index and knows exactly which pages exist. No recall/precision tradeoffs.
- **Transparent**: A human can read the index and understand what the agent will find. Vector similarity is opaque.
- **Zero infrastructure**: No embedding service, no vector database, no indexing pipeline. Just a markdown file.
- **Git-native**: The index is versioned, diffable, and mergeable. Vector databases require separate backup.

**When to reconsider**: If the vault exceeds 1,000 wiki pages, consider augmenting
(not replacing) the index with semantic search.
The index remains the source of truth; embeddings become an optional discovery layer.

## How INGEST, QUERY, and LINT Interact

```
                    Human drops file
                          |
                          v
    raw/source.md ----[INGEST]----> wiki/sources/source-*.md
                          |              |
                          |         wiki/concepts/concept-*.md
                          |         wiki/entities/entity-*.md
                          |              |
                          v              v
                    wiki/index.md   wiki/log.md
                          |
                          v
                 Human asks question
                          |
                          v
                    [QUERY] reads index --> reads relevant pages
                          |
                          v
                    Answer (optionally filed as new wiki page)
                          |
                          v
                    wiki/log.md (query recorded)

                    [LINT] runs periodically
                          |
                          v
                    Checks: frontmatter, tags, line counts,
                    orphans, staleness, index completeness
                          |
                          v
                    memory/notes/lint-report-*.md
```

Data flows one direction: `raw/` -> `wiki/` -> `memory/`. Raw is never modified. Wiki grows through ingestion. Memory captures operational decisions and health reports.

## How Git Branching Enables Multi-Agent Concurrency

Each agent session creates its own branch: `agent/{{agent-id}}/{{task}}`. This enables multiple agents to work simultaneously without conflicts.

**Branch lifecycle**:

1. Agent creates branch from `main`
2. Agent performs its operation (ingest, lint, etc.)
3. Agent commits changes atomically
4. Human reviews PR and merges to `main`

**Conflict hotspots**:

| File | Conflict risk | Resolution |
|------|---------------|------------|
| `wiki/index.md` | High (every ingest touches it) | Rebuild with `vault-tools.sh index-rebuild` |
| `wiki/log.md` | Medium (append-only) | Accept both entries, sort by date |
| Content pages | Low (agents rarely edit the same page) | Agent re-reads and reconciles |

**Why not trunk-based development?** Agents cannot resolve merge conflicts interactively. Branch-per-session with PR review gives humans a checkpoint before changes reach `main`.
