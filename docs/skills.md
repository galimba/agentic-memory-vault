# Agent Skills

How first-party and custom agent skills work in this vault: where they live,
how they are governed, and how to author your own.

## What a Skill Is

A skill is a directory containing a `SKILL.md` file (plus optional supporting
files) that teaches an agent a repeatable workflow. The vault ships one
first-party skill, `vault-ops`, which covers the three core operations
(INGEST / QUERY / LINT), the `vault-tools.sh` command surface, and the rules
that most often block commits. It doubles as the reference example for
authoring your own skills.

## Where Skills Live

| Location | Role |
|----------|------|
| `.vault/skills/` | **Canonical, git-tracked.** Audited by the `skill-audit` CI job. |
| `.claude/skills/` | **Per-clone install target.** Gitignored; platforms that auto-discover skills read from here. |

The template tracks skills in `.vault/skills/` because `.claude/` is
deliberately gitignored. During instance initialization, `init.sh` copies
`.vault/skills/*` into `.claude/skills/`. After pulling template updates that
change a skill, re-run the copy:

```bash
mkdir -p .claude/skills && cp -r .vault/skills/* .claude/skills/
```

If `skill-audit` reports a hash mismatch between a manifest and a file, that is
tamper detection working as intended — regenerate the manifest only after a
human has reviewed the change.

## Governance (Why Skills Are Locked Down)

Skills are prompt content that agents execute with their own permissions, so
the vault treats them as an untrusted supply chain. Three layers enforce this:

1. **Policy** — `.vault/schemas/skill-policy.json` defines enforcement levels
   (`strict` by default): file-count and size caps, blocked command patterns,
   no tool-permission escalation via frontmatter, no shell-preprocessing lines,
   and (under `strict`) no external URLs at all.
2. **Pre-commit gate** — `check-skill-hardening.sh` scans staged skill files
   and rejects policy violations and missing manifests at commit time.
3. **Audit** — `vault-tools.sh skill-audit` (also a CI job) verifies each
   skill's `skill-manifest.json`: per-file SHA-256 hashes, size caps,
   unmanifested files, and — under `strict` — a human review sign-off
   (`reviewed_by` + `review_date`).

See `docs/security-hardening.md` for the threat model behind these controls and
`.vault/schemas/skill-manifest.schema.md` for the manifest format.

## Authoring a Skill

1. **Copy the example**: `cp -r .vault/skills/vault-ops .vault/skills/my-skill`
2. **Edit `SKILL.md`**. Keep frontmatter to `name` and `description` only.
   The `description` is the trigger: state what the skill does and when to use
   it. Everything else goes in the body.
3. **Write around the hardening rules.** Under the default `strict` policy the
   scanner rejects, anywhere in any of the skill's markdown files: network
   fetch and package-installation command strings, dynamic code execution
   patterns, the tool-permission frontmatter key, any line beginning with an
   exclamation mark, and any external URL. The blocked-pattern list is
   `blocked_patterns` in `.vault/schemas/skill-policy.json`. The patterns are
   literal substring matches over every line, including prose — an innocent
   word containing a blocked string is also rejected (the dynamic-execution
   pattern ends in a space, so words like "retrieval " followed by a space can
   trip it; the tool-permission key is rejected even when merely mentioned in
   a sentence). Under `strict` the URL allowlist ships empty, so ALL external
   URLs fail. Before committing, grep your skill files against the
   `blocked_patterns` list to find accidental hits.
4. **Generate the manifest**:

   ```bash
   bash .vault/scripts/vault-tools.sh skill-manifest .vault/skills/my-skill
   ```

   Re-run this after every edit; stale hashes fail the audit.
5. **Get human review.** Under `strict`, fill `reviewed_by` and `review_date`
   in `skill-manifest.json` after a human has read the skill. Editing any file
   afterward invalidates the review — regenerate and re-review.
6. **Verify and commit**:

   ```bash
   bash .vault/scripts/vault-tools.sh skill-audit
   ```

   The pre-commit hook runs the same hardening checks; a clean `skill-audit`
   run means the commit will pass them.

## Keeping Skills Lean

Everything in this template must earn its place, and skills are no exception:

- One skill per coherent workflow. Prefer a single well-scoped `SKILL.md` over
  a sprawling multi-file skill — the strict policy caps a skill at 10 files
  and 500 KB, and every file adds review surface.
- Skills summarize and point; they do not duplicate governance. `CLAUDE.md` /
  `AGENTS.md` stay authoritative — a skill that contradicts them is a bug.
- Platform-neutral wording. Skills in this vault are plain markdown readable
  by any agent platform; `.claude/skills/` is just the discovery location for
  platforms that use it. Other platforms can read `.vault/skills/` directly as
  operational playbooks.

## Shipped Skills

| Skill | Purpose |
|-------|---------|
| `vault-ops` | Operate the vault: INGEST / QUERY / LINT checklists, command reference, commit-blocking rules, boundaries digest. |
