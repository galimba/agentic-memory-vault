# Rules Customization — Creating and Adapting Rules

This guide covers creating new rules and customizing the rule system
for your industry. See [Rules Guide](rules-guide.md) for how the
system works.

## Creating a Hard Rule

1. Choose the next ID (HR-014, HR-015, etc.)
2. Add to `.vault/rules/hard-rules.md`:

```markdown
## HR-0XX: Rule Title

**Rule**: Clear, unambiguous statement of what is and isn't allowed.

**Rationale**: Why this rule exists. What goes wrong without it.

**Enforcement**: Which hook function implements this.

**Exception**: Legitimate cases where the rule doesn't apply.
```

3. Implement `check_hr0XX()` in `.vault/hooks/lib-hook-checks.sh`
4. Add the check to `main()` in `.vault/hooks/pre-commit.sh`
5. Add a summary line to `CLAUDE.md` Hard Rules section
6. Test: create a violating file, verify the hook catches it

## Creating a Soft Rule

1. Choose the next ID (SR-016, SR-017, etc.)
2. Add to `.vault/rules/soft-rules.md`:

```markdown
## SR-0XX: Rule Title

**Default**: What the default behavior should be.

**Rationale**: Why this guidance exists.

**When to override**: Scenarios where a different approach fits.
```

3. Optionally add a lint check to `vault-tools.sh`
4. No pre-commit enforcement needed

## Industry Customizations

### Engineering-heavy organizations
- Lower SR-008 stale threshold to 7-14 days
- Add tags: `custom/sprint-N`, `custom/epic-name`
- Add SR: "Architecture decisions MUST have a decision record"

### Regulated industries (finance, healthcare)
- Add HR: "Every wiki page MUST include a `sensitivity/` tag"
- Enable content hardening (`.vault/schemas/content-policy.json`)
- Set SR-010 to strict: no auto-promotion for any type
- Add tags: `custom/regulatory-ref`, `custom/audit-trail`

### Agencies and consultancies
- Add tags per client: `custom/client-acme`
- Add SR: "Client pages MUST use `sensitivity/confidential`"
- Consider separate vaults per client for data isolation

### Research and R&D
- Raise HR-004 warn threshold to 300 (longer research notes)
- Lower SR-009 confidence requirements (more hypotheses)
- Add tags: `custom/experiment-N`, `custom/hypothesis`
- Add SR: "Hypothesis pages MUST link to testing experiments"
