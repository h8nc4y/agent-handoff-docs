# REQUIREMENTS — <project>

Last updated: <date> (<author/agent>)

## Canonical scope of this document

Single source of truth for: what <project> must do (functional and
non-functional requirements), what it must not do (non-goals), and the
acceptance criteria with their current status. The acceptance table below
is the canonical remaining-work list at requirement level. NOT canonical
for: how the system is currently built (`docs/ARCHITECTURE.md`), history
and measurements (`docs/REPORT.md`), the operational work queue
(`TASKS.md`), current position (`HANDOFF.md`). If this document disagrees
with the repository's observable state, the repository wins.

<Note: `docs/ARCHITECTURE.md` and `docs/REPORT.md` have no bundled
template — point these references at whatever owns those roles here (a
README section and git history are fine in small repositories).>

## Purpose and background

<Why this project exists; one short paragraph. Decision context and the
paths not taken belong in `docs/REPORT.md`.>

## Functional requirements

| ID | Requirement | Priority | Notes |
| --- | --- | --- | --- |
| FR-1 | <the system shall ...> | must | |
| FR-2 | <the system shall ...> | should | |

## Non-functional requirements

| ID | Requirement | Notes |
| --- | --- | --- |
| NFR-1 | <performance / security / portability constraint> | |

## Non-goals

- <explicitly out of scope, so the next agent does not build it>

## Acceptance criteria

Status rule: mark `done` only with evidence produced by the verification
column (a command output, CI run, or PR reference) — re-derive dates and
numbers from the repository, not from memory. Everything else stays
`not yet`. The `not yet` rows are the canonical remaining work.

| ID | Criterion (observable outcome) | Verification (command / procedure) | Status | Evidence |
| --- | --- | --- | --- | --- |
| AC-1 | <what can be observed when this is met> | <how to check it> | not yet | |
| AC-2 | <what can be observed when this is met> | <how to check it> | not yet | |

## Unverified checklist

Each entry names the command or observation that would verify it. Burning
down this list is the next agent's standing work order.

- [ ] <claim> — verify with: `<command>`

## Open questions

| ID | Question | Decision owner | Status |
| --- | --- | --- | --- |
| Q-1 | <what needs a human/owner decision> | <who> | open |
