# HANDOFF — <project>

Last updated: <date> (<author/agent>)

## Canonical scope of this document

Single source of truth for: current position and the immediate next step —
nothing else. NOT canonical for: requirements (`docs/REQUIREMENTS.md`),
current design (`docs/ARCHITECTURE.md`), history and measurements
(`docs/REPORT.md`), the work queue (`TASKS.md`), conventions and gates
(`<conventions file, e.g. AGENTS.md>`). If this document disagrees with
the repository's observable state, the repository wins — check `git log`
and open PRs first, then fix this document.

Size budget: keep this file under roughly 1,000 tokens. Compress at every
work-unit boundary and before any final report: fold durable history into
`docs/REPORT.md`, then cut it here. Never store secrets, tokens,
credential-bearing logs, or real user data in this file.

## Traps before you touch anything

- <the one or two facts that would otherwise cost the next agent an hour>

## Current goal and success metric

- Goal: <what this work stream is trying to achieve>
- Done when: <the observable success condition>

## Current position

- <3-8 bullets, present tense, no history>

## Key files

- `<path>` — <why it matters now>

## Recent decisions

- <decision, one line; context and alternatives live in docs/REPORT.md>

## Commands already run

- `<command>` — <result in a few words>

## Known issues

- <issue and where it is tracked (TASKS id)>

## Do not re-read

- `<old doc or path>` — deleted/superseded in <commit or PR ref>; durable
  content folded into `<canonical doc>`; recoverable via git history.

## Next step

1. <the smallest next action, executable without asking anything>
