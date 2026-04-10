# Company Context

> Fill in this template to give agents essential context about your organization.
> This file is referenced by `CLAUDE.md` and loaded during agent context initialization.
> Replace each `[placeholder]` with your information. Delete sections that do not apply.

## Company Overview

- **Company Name**: [Your Company Name]
- **Industry**: [e.g., Financial Services, Healthcare, SaaS, E-commerce]
- **Size**: [e.g., 50 employees, 500 employees, 10,000+ employees]
- **Founded**: [Year]
- **Headquarters**: [City, Country]
- **What we do**: [2-3 sentence description of the company's core business]

## Key Products and Services

- **[Product/Service 1]**: [One-line description]
- **[Product/Service 2]**: [One-line description]
- **[Product/Service 3]**: [One-line description]

## Team Structure

Which teams will use this vault and how:

| Team | Role in vault | Primary operations |
|------|---------------|-------------------|
| [e.g., Engineering] | [e.g., Primary users] | [e.g., INGEST technical docs, QUERY for decisions] |
| [e.g., Product] | [e.g., Consumers] | [e.g., QUERY for engineering context] |
| [e.g., Leadership] | [e.g., Reviewers] | [e.g., Review PR merges, set priorities] |

## Domain-Specific Terminology

Define terms that agents should understand in your context:

| Term | Definition |
|------|-----------|
| [e.g., Sprint] | [e.g., Two-week development cycle] |
| [e.g., ARR] | [e.g., Annual Recurring Revenue] |
| [e.g., Control Plane] | [e.g., Our internal orchestration service] |

## External Systems

Where source material originates:

| System | What comes from it | Ingestion method |
|--------|-------------------|-----------------|
| [e.g., Confluence] | [e.g., Technical specs, meeting notes] | [e.g., Export as markdown, drop in raw/] |
| [e.g., Slack] | [e.g., Decision threads, announcements] | [e.g., Copy-paste key threads to markdown] |
| [e.g., Jira] | [e.g., Epic summaries, retrospectives] | [e.g., Export and summarize] |
| [e.g., Google Docs] | [e.g., Strategy documents, proposals] | [e.g., Download as markdown] |

## Priorities

What should the vault focus on first:

1. [e.g., Engineering architecture decisions from the last 6 months]
2. [e.g., Product roadmap and feature specs]
3. [e.g., Onboarding materials for new engineers]
4. [e.g., Incident post-mortems and lessons learned]

## Sensitivity Guidelines

Content that should NOT go in the vault:

- [e.g., Customer PII (names, emails, account numbers)]
- [e.g., API keys, secrets, credentials]
- [e.g., Unannounced M&A activity]
- [e.g., Individual performance reviews]
- [e.g., Legal proceedings or privileged communications]

Content that requires the `sensitivity/confidential` tag:

- [e.g., Financial projections]
- [e.g., Competitive analysis]
- [e.g., Unreleased product plans]

## Custom Tags to Add

Based on your company context, consider adding these to `.vault/rules/tags.md`:

```yaml
# Example custom tags (add to tags.md before using):
- custom/[your-product-name]
- custom/[your-team-name]
- custom/[your-process-name]
```
