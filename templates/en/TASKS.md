# TASKS — <project>

Last updated: <date> (<author/agent>)

## Canonical scope of this document

Single source of truth for: the operational work queue — active, blocked,
and completed tasks. NOT canonical for: requirement-level completeness
(the acceptance table in `docs/REQUIREMENTS.md` owns that), current
position (`HANDOFF.md`), history (`docs/REPORT.md` and git log). If this
ledger disagrees with the repository's observable state (open PRs, CI),
the repository wins.

<Note: `docs/REPORT.md` has no bundled template — point the reference at
whatever owns the history role here (git log and PR bodies are fine in
small repositories).>

Verification-log policy: only the most recent verification run is recorded
here; older runs live in this file's git history. Do not append run after
run.

## Ledger

Status values: `todo` / `in-progress` / `blocked(<gate>)` / `done (PR <ref>)`.

Writing rule: give each finding-style task its file:line location, the
smallest proposed fix, and a confidence level. A row written that way is a
self-contained delegation spec — an agent can execute it without any other
context.

| ID | Task | Priority | Status | Notes (file:line, minimal fix, confidence) |
| --- | --- | --- | --- | --- |
| T-001 | <task> | high | todo | <src/module file:line — change X to Y; confidence high> |
| T-002 | <task> | medium | todo | |

## Latest verification run

- <date>: `<command>` — <result summary> (previous runs: git history of
  this file)

## History (one line per period)

Details live in git log and the referenced PR bodies; this section only
records that a period shipped and where.

- <period>: <what shipped, PR refs>
