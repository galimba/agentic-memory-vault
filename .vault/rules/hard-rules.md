# Hard Rules — Non-Negotiable Vault Constraints

> These rules are enforced by hooks and pre-commit scripts. Violations block commits. These rules exist to maintain vault integrity, agent reliability, and data safety. They are not configurable.

## HR-001: Raw Directory Immutability

**Rule**: No agent or automated process may create, modify, rename, or delete files in `raw/`. Only humans add files to `raw/` (manually or via Obsidian Web Clipper).

**Rationale**: `raw/` is the provenance layer. If sources can be modified after ingestion, the wiki loses its grounding truth. Every wiki claim must trace back to an unmodified source.

**Enforcement**: Pre-commit hook `.vault/hooks/protect-raw.sh` rejects any commit that modifies `raw/` unless the commit message starts with `[human]`.

---

## HR-002: Mandatory Frontmatter

**Rule**: Every `.md` file in `wiki/` MUST begin with valid YAML frontmatter containing at minimum: `title`, `type`, `created`, `updated`, `status`, `tags`.

**Rationale**: Frontmatter is how agents discover, filter, and reason about vault contents.
Without it, pages become invisible to programmatic access.
Dataview queries, index generation, and lint operations all depend on structured frontmatter.

**Enforcement**: Pre-commit hook `.vault/hooks/validate-frontmatter.sh` parses YAML and rejects files missing required fields.

---

## HR-003: Mandatory Tags

**Rule**: Every file in `wiki/` MUST include at least one tag from the approved taxonomy (`.vault/rules/tags.md`). Tags MUST use the flat prefix notation: `prefix/value`.

**Rationale**: Tags are the primary discovery mechanism for agents.
A page without tags is a page that cannot be found by category, domain, or type.
Flat prefixes ensure consistent machine parsing without ambiguity.

**Enforcement**: Pre-commit hook `.vault/hooks/validate-tags.sh` checks tags against the approved list.

---

## HR-004: Markdown Length Limit

**Rule**: No markdown file in `wiki/` or `memory/` may exceed **200 lines**. If content requires more space, split into linked sub-pages with a parent page that serves as an index.

**Rationale**: Long files degrade agent performance. Context windows are finite.
Agents reading a 500-line file waste tokens on content irrelevant to their current task.
Short, focused pages with clear links outperform monolithic documents
for both retrieval and comprehension.
The 200-line limit forces modular, composable knowledge.

**Enforcement**: Pre-commit hook `.vault/hooks/check-line-count.sh` rejects markdown files exceeding 200 lines.

**Exception**: `wiki/index.md` and `wiki/log.md` are exempt.
These files grow indefinitely by design.
When `index.md` exceeds 500 lines, split into
`wiki/index-{{category}}.md` files with a root index linking to them.

---

## HR-005: Code File Minimum Length

**Rule**: Standalone code files (`.sh`, `.py`, `.js`, `.ts`, etc.)
in `.vault/scripts/` or `.vault/hooks/` MUST be at least **500 lines**.
Shorter code belongs inline in markdown pages or as fenced code blocks in wiki entries.

**Rationale**: Short scripts proliferate without governance.
A vault with fifty 20-line shell scripts becomes unmaintainable.
By requiring 500+ lines, the vault forces consolidation of related functionality
into well-documented, comprehensive tool files.
This is a code quality gate, not a size mandate —
the 500 lines should include documentation, error handling, and tests.

**Enforcement**: Pre-commit hook `.vault/hooks/check-code-length.sh` rejects code files under 500 lines.

**Exception**: `.gitkeep` files, configuration files (`.json`, `.yaml`, `.toml`), and the init script `.vault/scripts/init.sh` are exempt.

---

## HR-006: Unique Page Titles

**Rule**: No two files in `wiki/` may share the same `title` frontmatter value. Titles are the primary human-readable identifier and the basis for `[[wikilink]]` resolution.

**Rationale**: Duplicate titles cause ambiguous wikilinks.
When an agent writes `[[API Design Principles]]` and two pages share that title,
the link target is undefined. Uniqueness eliminates this class of error.

**Enforcement**: Pre-commit hook `.vault/hooks/check-unique-titles.sh` scans all `wiki/` frontmatter and rejects duplicates.

---

## HR-007: Updated Field Accuracy

**Rule**: The `updated` field in frontmatter MUST reflect the actual date
of the last meaningful content change.
Agents MUST update this field whenever they modify page content
(not for metadata-only changes).

**Rationale**: The `updated` field drives staleness detection in lint operations. An inaccurate date means stale content goes undetected, degrading vault quality over time.

**Enforcement**: Pre-commit hook `.vault/hooks/check-updated-field.sh` verifies that modified files have an `updated` value matching the commit date (±1 day tolerance).

---

## HR-008: Index Registration

**Rule**: Every file in `wiki/` (except `index.md` and `log.md` themselves) MUST have a corresponding entry in `wiki/index.md`. The entry must include the file path and a one-line summary.

**Rationale**: `wiki/index.md` is the primary retrieval mechanism.
Agents read the index first to locate relevant pages.
An unregistered page is an invisible page — it exists on disk
but is functionally absent from the knowledge base.

**Enforcement**: Pre-commit hook `.vault/hooks/check-index-registration.sh` compares `wiki/` file listing against index entries.

---

## HR-009: Flat Tag Notation

**Rule**: Tags MUST use exactly one level of prefixing: `prefix/value`. No deeper nesting (`prefix/sub/value`), no bare tags without prefix (`#concept`), no spaces in tags.

**Rationale**: Flat prefixes balance expressiveness with parseability.
A single `grep` or `awk` command can extract all tags of a given prefix.
Deeper nesting requires recursive parsing.
Bare tags without prefixes are ambiguous
(is `#active` a lifecycle state, a project status, or a tag about the word "active"?).

**Enforcement**: Pre-commit hook `.vault/hooks/validate-tags.sh` enforces the `prefix/value` pattern via regex.

---

## HR-010: Binary File Quarantine

**Rule**: Binary files (images, PDFs, spreadsheets, archives, executables)
MUST be stored in `raw/` only.
The `wiki/` and `memory/` directories may contain only `.md` files
and `.json` configuration files.

**Rationale**: Binary files cannot be diffed by git, cannot be read by agents,
and inflate repository size.
Keeping them quarantined in `raw/` ensures that `wiki/` and `memory/`
remain lightweight, fully text-searchable, and git-friendly.
Agents reference binaries via paths (`[[raw/images/diagram.png]]`)
rather than embedding them.

**Enforcement**: Pre-commit hook `.vault/hooks/check-binary-quarantine.sh` rejects non-text files outside `raw/`.
