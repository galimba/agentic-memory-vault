# Skill Manifest Schema

When `require_manifest` is `true` in `skill-policy.json`, every skill directory
must contain a `skill-manifest.json` file that describes and locks the skill's
contents. The manifest enables hash-based tamper detection and provides
metadata for audit tooling.

## JSON Schema

```json
{
  "name": "string (required) — human-readable skill name",
  "version": "string (required) — semver, e.g. 1.0.0",
  "author": "string (required) — author identifier",
  "description": "string (required) — what the skill does",
  "created": "string (required) — ISO 8601 date, e.g. 2026-04-10",
  "updated": "string (required) — ISO 8601 date of last change",
  "reviewed_by": "string (optional) — who reviewed and approved",
  "review_date": "string (optional) — ISO 8601 date of review",
  "files": [
    {
      "path": "string (required) — relative path from skill dir",
      "sha256": "string (required) — hex SHA-256 hash of file",
      "size_bytes": "number (required) — file size in bytes"
    }
  ]
}
```

## Field Descriptions

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Display name of the skill |
| `version` | Yes | Semantic version (MAJOR.MINOR.PATCH) |
| `author` | Yes | Author name, email, or org identifier |
| `description` | Yes | Brief description of skill purpose |
| `created` | Yes | Date the skill was first created |
| `updated` | Yes | Date the skill was last modified |
| `reviewed_by` | No | Reviewer identity (human or team) |
| `review_date` | No | Date of the most recent review |
| `files` | Yes | Array of all files in the skill |
| `files[].path` | Yes | Relative path from the skill directory root |
| `files[].sha256` | Yes | SHA-256 hex digest of the file contents |
| `files[].size_bytes` | Yes | Size of the file in bytes |

## Example Manifest

```json
{
  "name": "vault-query-helper",
  "version": "1.0.0",
  "author": "platform-team@example.com",
  "description": "Assists with structured vault queries",
  "created": "2026-04-01",
  "updated": "2026-04-10",
  "reviewed_by": "security-team",
  "review_date": "2026-04-09",
  "files": [
    {
      "path": "SKILL.md",
      "sha256": "a1b2c3d4e5f6...64-char hex digest",
      "size_bytes": 1234
    },
    {
      "path": "prompts/query-template.md",
      "sha256": "f6e5d4c3b2a1...64-char hex digest",
      "size_bytes": 567
    }
  ]
}
```

## Computing SHA-256 Hashes

Use `sha256sum` (Linux) or `shasum -a 256` (macOS):

```bash
# Single file
sha256sum .claude/skills/my-skill/SKILL.md

# All files in a skill directory
find .claude/skills/my-skill -type f ! -name skill-manifest.json \
  -exec sha256sum {} \;
```

The manifest itself (`skill-manifest.json`) is excluded from hashing.

## Creating a Manifest for a New Skill

1. Place all skill files in the skill directory
2. Run the hash command above for each file
3. Create `skill-manifest.json` with the schema shown above
4. Fill in `name`, `version`, `author`, `description`, `created`, `updated`
5. Populate the `files` array with each file's `path`, `sha256`, `size_bytes`
6. Optionally have a reviewer sign off and fill `reviewed_by`, `review_date`
7. Run `vault-tools.sh skill-audit` to verify everything passes

## Verification During Audit

The `skill-audit` command verifies manifests by:

1. Reading every entry in `files` array
2. Computing SHA-256 of the actual file on disk
3. Comparing against the recorded `sha256` value
4. Flagging any mismatch as a **critical** violation
5. Flagging any on-disk files not listed in the manifest
6. Flagging any manifest entries for files that no longer exist

A hash mismatch means the file was modified after the manifest was created,
which may indicate tampering or an un-reviewed change.

## Integration with Enforcement Levels

| Level | Manifest Required | Review Required |
|-------|-------------------|-----------------|
| `strict` | Yes | Yes (`reviewed_by` + `review_date`) |
| `moderate` | Yes | No |
| `permissive` | No | No |
