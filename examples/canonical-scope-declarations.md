# Worked Examples: Canonical-Scope Declarations

Synthetic examples of the opening declaration each document carries. All
names are placeholders. The declaration is always the first section after
the title, so a reader who opens any file learns immediately what it owns,
what it does not, and what wins on conflict.

## START_HERE.md

```markdown
## Canonical scope of this document

Single source of truth for: this repository's reading order and entry
points. NOT canonical for anything that changes week to week — current
state lives in `HANDOFF.md`, the work queue in `TASKS.md`. If this file
disagrees with the repository's observable state, the repository wins and
this file is the one to fix.
```

## docs/REQUIREMENTS.md

```markdown
## Canonical scope of this document

Single source of truth for: what <project> must do (FR/NFR), what it must
not do (non-goals), and the acceptance criteria with status. The
acceptance table is the canonical remaining-work list at requirement
level. NOT canonical for: the as-built design (`docs/ARCHITECTURE.md`),
history (`docs/REPORT.md`), the work queue (`TASKS.md`).
```

## docs/ARCHITECTURE.md

Note the shape-ownership line: the code owns its own shapes, and the
document says so instead of copying them.

```markdown
## Canonical scope of this document

Single source of truth for: the current as-built design — components,
data flow, invariants, key files. NOT the design history (that is
`docs/REPORT.md`) and NOT the field shapes: record layouts are owned by
`src/types.ts`; this document explains what the fields mean and which
combinations are legal. Update only for merged changes.
```

## docs/REPORT.md

```markdown
## Canonical scope of this document

Single source of truth for: history — investigations, dead ends, measured
results, and the context behind decisions. Append-mostly, ordered by
time. Other documents move their history here before compressing; nothing
in this file describes the current state (that is `HANDOFF.md`).
```

## HANDOFF.md

```markdown
## Canonical scope of this document

Single source of truth for: current position and the immediate next step
— nothing else. Requirements, design, history, and the work queue each
have their own canonical documents (see START_HERE.md for the map). If
this document disagrees with the repository's observable state, the
repository wins — check `git log` and open PRs first, then fix this
document. Size budget: ~1,000 tokens.
```

## TASKS.md

```markdown
## Canonical scope of this document

Single source of truth for: the operational work queue — active, blocked,
and completed tasks. NOT canonical for requirement-level completeness
(the acceptance table in `docs/REQUIREMENTS.md`). Verification-log
policy: latest run only; older runs live in this file's git history.
```

## The conventions file and the thin pointer

When two agent products share a repository and one of them cannot see the
other's config file (for example because it is gitignored), put the
canonical conventions in the committed file both agents read, and reduce
the agent-specific file to a pointer:

`AGENTS.md` (committed — canonical):

```markdown
## Canonical scope of this document

Single source of truth for: contribution conventions, verification
commands, and hard gates for every agent working in this repository.
Agent-specific config files must not restate these rules — they point
here.
```

`CLAUDE.md` (agent-specific — thin pointer):

```markdown
Conventions for this repository are canonical in @AGENTS.md. This file
intentionally adds nothing.
```

The same arrangement works in the other direction — whichever file every
agent actually loads is the one that holds the canonical text.
