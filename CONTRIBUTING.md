# Contributing to Memory Vault Boilerplate

## Welcome

Thank you for your interest in contributing. This project provides a knowledge vault template
used by teams working with AI agents. Your contributions help improve the foundation that
many organizations build on. Please read our [Code of Conduct](CODE_OF_CONDUCT.md)
before participating.

## Two Types of Contributions

**a) Contributing to the template repo** — Improving the boilerplate for everyone (new rules, better scripts, documentation fixes). This is what this guide covers.

**b) Using the template for your own vault** — Cloning and customizing for your organization. That's normal usage, not a contribution. No PR needed.

## How to Report Bugs

- Use the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.yml) issue template
- Include: OS, shell version, agent platform, steps to reproduce
- Include the output of `bash .vault/scripts/vault-tools.sh doctor` if relevant

## How to Suggest Features

- Open a [Feature Request](.github/ISSUE_TEMPLATE/feature_request.yml) issue before submitting a PR for major changes
- For new tags or rules: use the [Vault Rule Proposal](.github/ISSUE_TEMPLATE/vault_rule_proposal.yml) template

## How to Submit Changes

1. Fork the repository
2. Create a branch: `feature/description`, `fix/description`, or `docs/description`
3. Make your changes
4. Run linters locally:

   ```bash
   markdownlint '**/*.md'
   shellcheck .vault/**/*.sh
   ```

5. Run vault diagnostics:

   ```bash
   bash .vault/scripts/vault-tools.sh doctor
   ```

6. Commit using Conventional Commits (see below)
7. Push and open a PR against `main`
8. Fill in the [PR template](.github/pull_request_template.md) completely

## Commit Message Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description
```

**Types**: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`

**Scopes**: `vault`, `rules`, `tags`, `hooks`, `scripts`, `docs`, `ci`, `templates`

### Examples

```
feat(tags): add custom/healthcare domain tags
fix(hooks): correct frontmatter date parsing for BSD date
docs(vault): add batch ingestion example to ingestion guide
chore(ci): update markdownlint-cli2 action to v19
refactor(scripts): extract frontmatter parser into shared function
feat(rules): add SR-016 for minimum entity page completeness
docs(templates): add report template with executive summary section
```

## What Makes a Good PR

- One logical change per PR
- All linters pass (CI will check)
- Markdown files in `wiki/` and `memory/` stay under 200 lines (warning) / 400 lines (hard limit)
- Code files in `.vault/` stay under 400 lines (warning) / 600 lines (hard limit)
- New tags are added to `.vault/rules/tags.md` before being used
- Update `CHANGELOG.md` under `[Unreleased]`

## Development Setup

Minimal — no build step required.

```bash
git clone https://github.com/galimba/agentic-memory-vault.git
cd agentic-memory-vault
```

**Optional tools** (for running linters locally):

- [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2): `npm install -g markdownlint-cli2`
- [shellcheck](https://www.shellcheck.net/): `apt install shellcheck` or `brew install shellcheck`
- [yamllint](https://github.com/adrienverge/yamllint): `pip install yamllint`

## Style Guide

- **Markdown**: Follow `.markdownlint.yaml` rules
- **Shell**: Follow `.shellcheckrc` rules, use `set -euo pipefail`
- **YAML frontmatter**: Follow `.vault/schemas/frontmatter.md`
- **Tags**: Flat prefix notation only (`prefix/value`)
- **File naming**: `kebab-case` for all files

## Recognition

Contributors are recognized in `CHANGELOG.md` and in GitHub's contributor graph.
