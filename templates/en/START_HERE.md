# START_HERE — <project>

> Standard kickoff file, same name in every repository you maintain. A new
> agent (or human) reads this file first to learn where the canonical
> documents live and how to begin. Keep this file free of point-in-time
> information so it never goes stale.

## Canonical scope of this document

Single source of truth for: this repository's reading order and entry
points — and for the verification commands and hard gates below ONLY when
no other document owns them (when a conventions document such as
`AGENTS.md` owns them, those sections become pointers to it; ownership
moves, it is never shared). NOT canonical for anything that changes week
to week — current state lives in `HANDOFF.md`, the work queue in
`TASKS.md`. If this file disagrees with the repository's observable
state, the repository wins and this file is the one to fix.

## What this repository is

<One or two lines. Purpose only — nothing that changes weekly.>

## Reading order (canonical documents)

1. `README.md` — overview and public entry point
2. `docs/REQUIREMENTS.md` — requirements and acceptance criteria (intent)
3. `docs/ARCHITECTURE.md` — current as-built design
4. `HANDOFF.md` — where work stands now
5. `TASKS.md` — task ledger

<Adjust names and paths to this repository, but keep the shape:
overview → intent → design → current state → work queue. History
(`docs/REPORT.md`) is read on demand, not by default.>

## Verification commands

Run before any PR:

```
<build / test / lint / scan commands, exactly as they must be run,
or a pointer to the one document section that owns them>
```

## Hard gates (never cross without approval)

- <e.g., no production deploys / no external posting / no paid API usage>
- <e.g., which branch is protected, what needs owner sign-off>

<If a conventions document owns the gates, replace this list with a
pointer to it.>

## Next step

Read the "Next step" section of `HANDOFF.md`. This file intentionally
contains no current-state information — do not add any here.
