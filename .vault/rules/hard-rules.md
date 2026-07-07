# Hard Rules — Non-Negotiable Vault Constraints

> These rules are enforced by hooks and pre-commit scripts. Violations block commits. These rules exist to maintain vault integrity, agent reliability, and data safety. They are not configurable.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** in this document are to
be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

## HR-001: Raw Directory Immutability

**Rule**: Agents and automated processes **MUST NOT** create, modify, rename, or delete files in `raw/`. Only humans add files to `raw/` (manually or via Obsidian Web Clipper).

**Rationale**: `raw/` is the provenance layer. If sources can be modified after ingestion, the wiki loses its grounding truth. Every wiki claim must trace back to an unmodified source.

**Enforcement**: Pre-commit hook unconditionally rejects any commit that
modifies `raw/`. Humans add files to `raw/` via pull requests that bypass
client-side hooks at merge time. Use CODEOWNERS to require maintainer
approval for PRs touching `raw/`.

---

## HR-002: Mandatory Frontmatter

**Rule**: Every `.md` file in `wiki/` **MUST** begin with valid YAML frontmatter containing at minimum: `title`, `type`, `created`, `updated`, `status`, `tags`.

**Rationale**: Frontmatter is how agents discover, filter, and reason about vault contents.
Without it, pages become invisible to programmatic access.
Dataview queries, index generation, and lint operations all depend on structured frontmatter.

**Enforcement**: Pre-commit hook (`check_hr002` in `.vault/hooks/checks/check-hr002.sh`) validates YAML frontmatter and rejects files missing required fields.

---

## HR-003: Mandatory Tags

**Rule**: Every file in `wiki/` **MUST** include at least one tag from the approved taxonomy (`.vault/rules/tags.md`). Tags **MUST** use the flat prefix notation: `prefix/value`.

**Rationale**: Tags are the primary discovery mechanism for agents.
A page without tags is a page that cannot be found by category, domain, or type.
Flat prefixes ensure consistent machine parsing without ambiguity.

**Enforcement**: Pre-commit hook (`check_hr003` in `.vault/hooks/checks/check-hr003.sh`) checks tags against the approved list.

---

## HR-004: Markdown Length Limit

**Rule**: Markdown files in `wiki/` or `memory/` should stay under **200
lines** (soft warning) and **MUST NOT** exceed **400 lines** (hard
limit). If content requires more space, split into linked sub-pages with
a parent page that serves as an index.

**Rationale**: Long files degrade agent performance. Context windows are
finite. Agents reading a 500-line file waste tokens on content irrelevant
to their current task. Short, focused pages with clear links outperform
monolithic documents for both retrieval and comprehension. The 200-line
target encourages modular knowledge. The 400-line ceiling catches files
that genuinely need splitting.

**Enforcement**: Pre-commit hook warns at 200 lines and rejects files
exceeding 400 lines in `wiki/` and `memory/`.

**Exception**: `wiki/index.md` and `wiki/log.md` are exempt. These files
grow indefinitely by design. When `index.md` exceeds 500 lines, split
into `wiki/index-{{category}}.md` files with a root index linking to them.

---

## HR-005: Code File Length Limit

**Rule**: Standalone code files (`.sh`, `.py`, `.js`, `.ts`, etc.) in
`.vault/` should stay under **400 lines** (soft warning) and **MUST NOT**
exceed **600 lines** (hard limit). If a file exceeds the limit, split
it into modular files with clear responsibilities and a single entry point
that sources them.

**Rationale**: Long code files are hard to read, review, and maintain. A
single 800-line bash script with 15 functions is less maintainable than
four 200-line files with clear names and responsibilities. Modular files
enable focused code review, independent testing, and easier onboarding.

**Enforcement**: Pre-commit hook warns at 400 lines and rejects code files
exceeding 600 lines in `.vault/scripts/`, `.vault/hooks/`, and
`.claude/skills/*/`.

**Exception**: Library files (`lib-*.sh`) sourced by an entry point are
exempt from the maximum — their size is governed by the entry point's
ability to stay under the limit. Configuration files (`.json`, `.yaml`,
`.toml`) are exempt.

---

## HR-006: Unique Page Titles

**Rule**: Two files in `wiki/` **MUST NOT** share the same `title` frontmatter value. Titles are the primary human-readable identifier and the basis for `[[wikilink]]` resolution.

**Rationale**: Duplicate titles cause ambiguous wikilinks.
When an agent writes `[[API Design Principles]]` and two pages share that title,
the link target is undefined. Uniqueness eliminates this class of error.

**Enforcement**: Pre-commit hook (`check_hr006` in `.vault/hooks/checks/check-hr006.sh`) scans all `wiki/` frontmatter and rejects duplicates.

---

## HR-007: Updated Field Accuracy

**Rule**: The `updated` field in frontmatter **MUST** reflect the actual date
of the last meaningful content change.
Agents **MUST** update this field whenever they modify page content
(not for metadata-only changes).

**Rationale**: The `updated` field drives staleness detection in lint operations. An inaccurate date means stale content goes undetected, degrading vault quality over time.

**Enforcement**: Pre-commit hook (`check_hr007` in `.vault/hooks/checks/check-hr007.sh`) verifies that modified files have an `updated` value matching the commit date (±1 day tolerance).

---

## HR-008: Index Registration

**Rule**: Every file in `wiki/` (except `index.md` and `log.md` themselves) **MUST** have a corresponding entry in `wiki/index.md`. The entry **MUST** include the file path and a one-line summary.

**Rationale**: `wiki/index.md` is the primary retrieval mechanism.
Agents read the index first to locate relevant pages.
An unregistered page is an invisible page — it exists on disk
but is functionally absent from the knowledge base.

**Enforcement**: Pre-commit hook (`check_hr008` in `.vault/hooks/checks/check-hr008.sh`) compares `wiki/` file listing against index entries.

---

## HR-009: Flat Tag Notation

**Rule**: Tags **MUST** use exactly one level of prefixing: `prefix/value`. Tags **MUST NOT** use deeper nesting (`prefix/sub/value`), appear bare without a prefix (`#concept`), or contain spaces.

**Rationale**: Flat prefixes balance expressiveness with parseability.
A single `grep` or `awk` command can extract all tags of a given prefix.
Deeper nesting requires recursive parsing.
Bare tags without prefixes are ambiguous
(is `#active` a lifecycle state, a project status, or a tag about the word "active"?).

**Enforcement**: Pre-commit hook (`check_hr009` in `.vault/hooks/checks/check-hr009.sh`) enforces the `prefix/value` pattern via regex.

---

## HR-010: Binary File Quarantine

**Rule**: Binary files (images, PDFs, spreadsheets, archives, executables)
**MUST** be stored in `raw/` only.
The `wiki/` and `memory/` directories **MUST** contain only `.md` files
and `.json` configuration files.

**Rationale**: Binary files cannot be diffed by git, cannot be read by agents,
and inflate repository size.
Keeping them quarantined in `raw/` ensures that `wiki/` and `memory/`
remain lightweight, fully text-searchable, and git-friendly.
Agents reference binaries via paths (`[[raw/images/diagram.png]]`)
rather than embedding them.

**Enforcement**: Pre-commit hook (`check_hr010` in `.vault/hooks/checks/check-hr010.sh`) rejects non-text files outside `raw/`.

---

## HR-011: Vault Configuration Protection

**Rule**: Agents **MUST NOT** modify files in `.vault/rules/`, `.vault/hooks/`,
or `.vault/scripts/`. These directories contain the vault's governance
and enforcement mechanisms. Changes require human-authored PRs.

**Rationale**: If an agent can modify the rules that govern it, the rules
are meaningless. A prompt-injected agent could weaken hard rules, disable
hooks, or modify lint logic to hide violations. Protecting the governance
layer from agent modification is the foundation of vault integrity.

**Enforcement**: Pre-commit hook rejects any commit that modifies files
in `.vault/rules/`, `.vault/hooks/`, or `.vault/scripts/`.

---

## HR-012: Agent Configuration Protection

**Rule**: Agents **MUST NOT** modify `CLAUDE.md`, `AGENTS.md`, or `CODEX.md`.
These files define agent behavior constraints. Changes require
human-authored PRs.

**Rationale**: These files are the agent's instruction set. An agent that
modifies its own instructions can grant itself arbitrary permissions,
disable safety constraints, or remove rate limits. This is the most
critical protection after raw/ immutability.

**Enforcement**: Pre-commit hook rejects any commit that modifies
`CLAUDE.md`, `AGENTS.md`, or `CODEX.md` in the repository root.

---

## HR-013: CI and Template Protection

**Rule**: Agents **MUST NOT** modify files in `.github/` or `templates/`.
Workflow files control CI enforcement. Template files shape all future
wiki pages.

**Rationale**: A compromised workflow could disable all CI checks,
allowing rule violations to merge unchecked. A compromised template
could inject adversarial content into every future wiki page created
from it.

**Enforcement**: Pre-commit hook rejects any commit that modifies files
in `.github/` or `templates/`.

---

## HR-014: No File Deletion

**Rule**: Agents **MUST NOT** delete files from `wiki/` or `memory/`.
To remove content from the active vault, set `status: archived` in
the file's frontmatter. The file remains in the working tree and
git history but is excluded from active queries, lint reports, and
staleness checks by its archived status.

**Rationale**: Every documented AI agent data-loss incident involved
file deletion — whether through `git rm`, file truncation, or
accidental removal during refactoring. Preventing deletion
structurally eliminates the entire failure class. This pattern is
independently used by Zep/Graphiti (invalid_at timestamps), Mem0
(invalid relationship marking), and SoulClaw (immutable core memory).
The vault's implementation uses `status: archived` as the
invalidation marker, which the existing staleness and lint systems
already respect.

**Enforcement**: Pre-commit hook (`check_hr014` in
`.vault/hooks/checks/check-hr014.sh`) checks for deleted files
(`--diff-filter=D`) and renames out of protected directories
(`--diff-filter=R`) in `wiki/` and `memory/`. Rejects the commit
if any are found.

**Exception**: Set `VAULT_ALLOW_DELETE=1` environment variable to
bypass for legitimate cleanup (removing accidentally committed
secrets, PII, or test artifacts). Document the reason in the commit
message.

---

## HR-015: Append-Only Logs

**Rule**: `wiki/log.md` and files under `memory/logs/` are append-only.
Existing lines in these files **MUST NOT** be deleted or modified;
commits that do so are rejected. Only pure additions are allowed.

**Rationale**: The operations log is the vault's audit trail. If agents
can rewrite log history, there is no reliable record of what happened.
Append-only enforcement ensures accountability and aligns with the
"git-as-memory" pattern where logs serve as immutable records.

**Enforcement**: Pre-commit hook (`check_hr015` in
`.vault/hooks/checks/check-hr015.sh`) inspects
`git diff --cached --numstat` for each staged log file and rejects the
commit if the deletion count is non-zero.

**Exception**: Set the `LOG_EDIT_ALLOWED=1` environment variable to bypass
the check for legitimate corrections (e.g., fixing a typo in a log
entry). Document the reason in the commit message when you do.

