# Tag Taxonomy — Approved Vault Tags

> All tags in this vault MUST use flat prefix notation: `prefix/value`.
> This file is the single source of truth for approved tags.
> Agents MUST NOT create tags outside this list unless instructed by a human.
> New tags are added to this file first, then used in content.
>
> **Format**: `prefix/value` — Description

---

## domain/ — High-Level Business Domain (30 values)

These tags represent the broadest organizational categories. Every page should have at least one domain tag.

- `domain/engineering` — Software engineering, architecture, infrastructure
- `domain/operations` — Business operations, logistics, process management
- `domain/marketing` — Marketing strategy, campaigns, brand, growth
- `domain/sales` — Sales process, pipeline, CRM, revenue
- `domain/business` — Business strategy, planning, models, partnerships
- `domain/rnd` — Research and development, innovation, experimentation
- `domain/outreach` — External communications, PR, community relations
- `domain/finance` — Financial planning, budgeting, accounting, treasury
- `domain/legal` — Legal compliance, contracts, IP, regulatory
- `domain/hr` — Human resources, hiring, culture, benefits, compensation
- `domain/product` — Product management, roadmap, features, specs
- `domain/design` — UX/UI design, visual design, design systems
- `domain/data` — Data engineering, analytics, BI, data science
- `domain/security` — Information security, compliance, risk, access control
- `domain/devops` — CI/CD, deployment, monitoring, SRE, platform
- `domain/support` — Customer support, helpdesk, ticket management
- `domain/quality` — QA, testing, quality assurance, standards
- `domain/strategy` — Corporate strategy, competitive analysis, market positioning
- `domain/governance` — Corporate governance, policies, oversight, audit
- `domain/procurement` — Purchasing, vendor management, supply chain
- `domain/training` — Employee training, onboarding, learning, development
- `domain/communications` — Internal communications, announcements, memos
- `domain/compliance` — Regulatory compliance, certifications, audits
- `domain/infrastructure` — Physical and cloud infrastructure, facilities
- `domain/ai` — Artificial intelligence, machine learning, LLMs, agents
- `domain/innovation` — Innovation programs, hackathons, ideation
- `domain/partnerships` — Strategic partnerships, alliances, integrations
- `domain/customer-success` — Customer lifecycle, retention, satisfaction
- `domain/executive` — C-suite, board, leadership, strategic direction
- `domain/sustainability` — ESG, environmental, social, sustainability

---

## type/ — Content Type Classification (25 values)

What kind of document is this?

- `type/concept` — Explanation of an idea, pattern, or principle
- `type/entity` — Page about a person, company, tool, or product
- `type/source` — Summary of an ingested source document
- `type/comparison` — Side-by-side analysis of alternatives
- `type/decision` — Architecture/business decision record (ADR)
- `type/report` — Analysis, findings, or status report
- `type/index` — Catalog or table of contents page
- `type/runbook` — Step-by-step operational procedure
- `type/playbook` — Strategic guide for a recurring activity
- `type/template` — Reusable document template
- `type/checklist` — Verification or audit checklist
- `type/policy` — Organizational policy document
- `type/spec` — Technical or product specification
- `type/proposal` — Formal proposal or recommendation
- `type/retrospective` — Post-mortem or lessons learned
- `type/meeting-notes` — Notes from a meeting or discussion
- `type/roadmap` — Timeline or plan of deliverables
- `type/faq` — Frequently asked questions
- `type/glossary` — Term definitions
- `type/tutorial` — How-to guide or walkthrough
- `type/evaluation` — Assessment of a tool, vendor, or approach
- `type/benchmark` — Performance test results or comparison data
- `type/hypothesis` — Unverified proposition or assumption
- `type/narrative` — Long-form story, case study, or experience report
- `type/snippet` — Reusable code or text fragment

---

## lifecycle/ — Document Lifecycle Stage (10 values)

Where is this document in its lifecycle?

- `lifecycle/draft` — Under construction, not yet reviewed
- `lifecycle/active` — Current, reviewed, and authoritative
- `lifecycle/review` — Pending review or update
- `lifecycle/archived` — No longer current but retained for reference
- `lifecycle/deprecated` — Superseded by a newer document
- `lifecycle/stale` — Flagged by lint as potentially outdated
- `lifecycle/orphan-candidate` — Few or no inbound links, may need attention
- `lifecycle/seed` — Minimal stub, needs expansion
- `lifecycle/stable` — Mature content unlikely to change frequently
- `lifecycle/experimental` — Exploratory content, may be discarded

---

## priority/ — Urgency and Importance (6 values)

- `priority/critical` — Requires immediate attention
- `priority/high` — Important, should be addressed soon
- `priority/medium` — Standard priority
- `priority/low` — Nice to have, no urgency
- `priority/backlog` — Tracked but not scheduled
- `priority/blocked` — Cannot proceed, awaiting dependency

---

## audience/ — Intended Reader (12 values)

- `audience/executive` — C-suite, board, leadership
- `audience/manager` — Team leads, middle management
- `audience/engineer` — Software developers, architects
- `audience/designer` — UX/UI designers
- `audience/analyst` — Data analysts, business analysts
- `audience/agent` — AI agents consuming the vault
- `audience/all-hands` — Entire organization
- `audience/external` — Customers, partners, public
- `audience/new-hire` — Onboarding content
- `audience/vendor` — Third-party vendors or contractors
- `audience/investor` — Investors, board members
- `audience/compliance-officer` — Regulatory or compliance staff

---

## format/ — Content Format (15 values)

- `format/runbook` — Step-by-step procedures
- `format/playbook` — Strategic guides
- `format/diagram` — Contains or references diagrams
- `format/table` — Primarily tabular data
- `format/narrative` — Long-form prose
- `format/structured` — Highly structured with clear sections
- `format/bullet-list` — Primarily bullet-point format
- `format/code-heavy` — Contains significant code blocks
- `format/reference` — Lookup/reference material
- `format/presentation` — Slide deck or presentation notes
- `format/dashboard` — KPIs, metrics, status overview
- `format/form` — Template requiring fill-in
- `format/log` — Chronological record
- `format/changelog` — Version history
- `format/api-doc` — API documentation

---

## dept/ — Department or Team (20 values)

- `dept/platform` — Platform engineering team
- `dept/backend` — Backend engineering
- `dept/frontend` — Frontend engineering
- `dept/mobile` — Mobile development
- `dept/data-eng` — Data engineering
- `dept/ml` — Machine learning team
- `dept/devops` — DevOps / SRE
- `dept/qa` — Quality assurance
- `dept/product-mgmt` — Product management
- `dept/design-team` — Design team
- `dept/marketing-team` — Marketing team
- `dept/sales-team` — Sales team
- `dept/support-team` — Customer support
- `dept/hr-team` — HR team
- `dept/finance-team` — Finance team
- `dept/legal-team` — Legal team
- `dept/executive-team` — Executive leadership
- `dept/security-team` — Security team
- `dept/research` — Research team
- `dept/growth` — Growth team

---

## tool/ — Technology and Tooling (20 values)

- `tool/langgraph` — LangGraph framework
- `tool/pydantic-ai` — PydanticAI framework
- `tool/openai-sdk` — OpenAI Agents SDK
- `tool/llamaindex` — LlamaIndex framework
- `tool/crewai` — CrewAI multi-agent framework
- `tool/obsidian` — Obsidian knowledge management
- `tool/git` — Git version control
- `tool/github` — GitHub platform
- `tool/claude-code` — Claude Code agent
- `tool/codex` — OpenAI Codex agent
- `tool/cursor` — Cursor IDE
- `tool/docker` — Docker containers
- `tool/kubernetes` — Kubernetes orchestration
- `tool/terraform` — Terraform IaC
- `tool/postgres` — PostgreSQL database
- `tool/redis` — Redis cache/store
- `tool/slack` — Slack communications
- `tool/notion` — Notion workspace
- `tool/jira` — Jira project management
- `tool/mcp` — Model Context Protocol

---

## method/ — Methodology (15 values)

- `method/agile` — Agile methodology
- `method/scrum` — Scrum framework
- `method/kanban` — Kanban workflow
- `method/lean` — Lean methodology
- `method/okr` — Objectives and Key Results
- `method/bmad` — BMAD methodology
- `method/gsd` — Get Stuff Done methodology
- `method/ralph` — RALPH methodology
- `method/design-thinking` — Design thinking process
- `method/six-sigma` — Six Sigma quality
- `method/devops-practice` — DevOps practices
- `method/zettelkasten` — Zettelkasten note method
- `method/para` — PARA organization method
- `method/gtd` — Getting Things Done
- `method/context-engineering` — Context engineering for agents

---

## role/ — Organizational Role (15 values)

- `role/architect` — Software or solutions architect
- `role/developer` — Software developer
- `role/lead` — Tech lead or team lead
- `role/manager` — People or project manager
- `role/director` — Director level
- `role/vp` — Vice president level
- `role/cto` — Chief Technology Officer
- `role/ceo` — Chief Executive Officer
- `role/cfo` — Chief Financial Officer
- `role/pm` — Product manager
- `role/designer-role` — Designer (UX/UI/visual)
- `role/analyst-role` — Business or data analyst
- `role/sre` — Site reliability engineer
- `role/devrel` — Developer relations
- `role/consultant` — External consultant

---

## scope/ — Scope of Impact (8 values)

- `scope/company-wide` — Affects entire organization
- `scope/team` — Affects a single team
- `scope/project` — Scoped to a specific project
- `scope/individual` — Personal or individual scope
- `scope/cross-team` — Spans multiple teams
- `scope/external` — Affects external stakeholders
- `scope/department` — Affects an entire department
- `scope/industry` — Industry-wide relevance

---

## status/ — Operational Status (8 values)

- `status/todo` — Not started
- `status/in-progress` — Currently being worked on
- `status/done` — Completed
- `status/on-hold` — Paused, awaiting input
- `status/cancelled` — Will not be completed
- `status/recurring` — Ongoing, repeating task
- `status/needs-input` — Blocked on external input
- `status/delegated` — Assigned to another party

---

## source-type/ — Origin of Source Material (10 values)

- `source-type/article` — Web article or blog post
- `source-type/paper` — Academic or research paper
- `source-type/repo` — Code repository
- `source-type/book` — Book or book chapter
- `source-type/video` — Video or webinar
- `source-type/podcast` — Podcast episode
- `source-type/documentation` — Official documentation
- `source-type/internal` — Internal company document
- `source-type/conversation` — Meeting notes, chat logs
- `source-type/data` — Dataset, spreadsheet, CSV

---

## confidence/ — Confidence Level (4 values)

- `confidence/verified` — Multiple sources confirm, recently checked
- `confidence/likely` — Single authoritative source
- `confidence/uncertain` — Inferred or extrapolated
- `confidence/unverified` — No backing source

---

## frequency/ — Update Frequency (5 values)

- `frequency/daily` — Updated daily
- `frequency/weekly` — Updated weekly
- `frequency/monthly` — Updated monthly
- `frequency/quarterly` — Updated quarterly
- `frequency/ad-hoc` — Updated as needed

---

## sensitivity/ — Information Sensitivity (5 values)

- `sensitivity/public` — Can be shared externally
- `sensitivity/internal` — Internal use only
- `sensitivity/confidential` — Restricted access
- `sensitivity/restricted` — Need-to-know basis
- `sensitivity/personal` — Contains PII or personal data

---

## region/ — Geographic Region (8 values)

- `region/global` — Worldwide applicability
- `region/north-america` — US, Canada, Mexico
- `region/europe` — European region
- `region/apac` — Asia-Pacific
- `region/latam` — Latin America
- `region/mena` — Middle East and North Africa
- `region/uk` — United Kingdom specifically
- `region/local` — Single office or locale

---

## outcome/ — Solution Outcome (8 values)

- `outcome/cost-reduction` — Reduces costs
- `outcome/revenue-growth` — Increases revenue
- `outcome/efficiency` — Improves operational efficiency
- `outcome/risk-mitigation` — Reduces risk
- `outcome/compliance-met` — Achieves compliance
- `outcome/customer-satisfaction` — Improves customer experience
- `outcome/innovation-unlock` — Enables new capabilities
- `outcome/technical-debt-reduction` — Reduces tech debt

---

## agent/ — Agent-Specific Tags (6 values)

- `agent/generated` — Content was generated by an AI agent
- `agent/reviewed` — Content was reviewed by a human after agent generation
- `agent/ingested` — Content was ingested by the vault pipeline
- `agent/linted` — Content passed lint checks
- `agent/needs-review` — Agent flagged for human review
- `agent/auto-promoted` — Auto-promoted from draft to active

---

## Adding Custom Tags

Organizations should add domain-specific tags using the `custom/` prefix:

```yaml
tags:
  - custom/acme-product-line
  - custom/client-onboarding
  - custom/regulatory-filing
```

To add a new approved tag:

1. Add it to this file under the appropriate prefix (or create a new prefix section)
2. Commit this file change with message `[tags] Added custom/your-tag-name`
3. The tag is now available for use in wiki pages
