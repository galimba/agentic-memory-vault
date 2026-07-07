---
title: "Roadmap"
---

# Roadmap

Planned features and improvements for the memory vault boilerplate,
organized by priority. Contributions are welcome on any item — see
[CONTRIBUTING.md](../CONTRIBUTING.md) for how to get started.

## Planned Features

| Feature | Issue | Priority | Labels |
|---------|-------|----------|--------|
| Source verification command | [#7](https://github.com/galimba/agentic-memory-vault/issues/7) | Deferred | `help wanted` |
| Decay scoring for freshness | [#8](https://github.com/galimba/agentic-memory-vault/issues/8) | Low | `discussion` |
| Auto-split index for large vaults | [#9](https://github.com/galimba/agentic-memory-vault/issues/9) | Medium | `help wanted` |
| Incremental index update | [#10](https://github.com/galimba/agentic-memory-vault/issues/10) | Medium | `good first issue` |
| MEMORY.md root pointer index | [#11](https://github.com/galimba/agentic-memory-vault/issues/11) | Deferred | `discussion` |
| Lifecycle tier tags | [#12](https://github.com/galimba/agentic-memory-vault/issues/12) | Low | `discussion` |
| Multi-agent namespacing | [#13](https://github.com/galimba/agentic-memory-vault/issues/13) | Deferred | `discussion` |
| Git blame helper | [#14](https://github.com/galimba/agentic-memory-vault/issues/14) | Low | `good first issue` |
| RFC 2119 language pass | [#15](https://github.com/galimba/agentic-memory-vault/issues/15) | Low | `good first issue` |
| Consolidation command | [#16](https://github.com/galimba/agentic-memory-vault/issues/16) | Low | `discussion` |
| Smoke test harness | [#17](https://github.com/galimba/agentic-memory-vault/issues/17) | Medium | `help wanted` |

## Where to Start

Issues labeled [`good first issue`](../../labels/good%20first%20issue)
are scoped for newcomers:

- **Incremental index update** — one function, clear test case
- **Git blame helper** — pure git wrapper, no rule changes
- **RFC 2119 language pass** — docs-only, zero code

Issues labeled [`help wanted`](../../labels/help%20wanted) need
contributors with deeper vault knowledge.

Issues labeled [`discussion`](../../labels/discussion) need
community input on design questions before implementation begins.

## What Already Shipped

| Version | Highlights |
|---------|-----------|
| v0.5.0 | Working CI (fixed a workflow that failed GitHub's validation and had failed every run since v0.4.0), honest `doctor` exit codes, a script test suite wired into CI, the `index-rebuild` "Other" section fix, `evaluation` type schema alignment, a documentation drift sweep, and the first shipped agent skill (`vault-ops`) with its `skill-manifest` generator |
| v0.4.0 | Instance scaffolding: `init.sh` instance phase, instance README and onboarding templates, 7 init placeholders, `.vault/.initialized` idempotency guard |
| v0.3.0 | HR-014: No file deletion — agents must archive instead of delete |
| v0.2.0 | Per-domain staleness thresholds, content policy (warn mode), lint reports, append-only logs (HR-015), three-tier agent boundaries |
| v0.1.0 | Three-layer architecture, 13 hard rules, 15 soft rules, 200+ tags, modular hook checks, skill hardening framework |

## Design Principles

These guide which features ship and which stay deferred:

1. **Boilerplate, not framework.** If a user can build it in
   30 minutes, document the pattern instead of shipping code.
2. **Bash + markdown + git.** No databases, no external services.
   Optional `jq` is tolerated, and `python3` is used for JSON parsing
   in the skill-hardening and content-policy tooling. The core wiki
   workflow requires neither.
3. **Report, don't mutate.** New analysis commands produce reports.
   They never auto-modify content without human approval.
4. **One file per responsibility.** New commands get their own
   file in `audits/` or `checks/`.
5. **Bugs before features.** Fix what is broken before building
   what is new.
