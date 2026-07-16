# Worked Examples: Do-Not-Re-Read Entries

The do-not-re-read list lives in `HANDOFF.md`. Its job: when a document is
deleted or superseded, the next agent must neither re-read the stale
content nor wonder whether something was lost. Every entry answers three
questions — what went away, where the durable content lives now, and how
to recover the original if ever needed.

Write the entry at the moment of deletion, in the same commit or PR. An
entry written later reconstructs from memory, which is exactly what this
list exists to avoid.

## Good entries

A deleted document whose durable content was folded elsewhere:

```markdown
## Do not re-read

- `docs/NOTES_SETUP.md` — deleted in PR #41; the two still-valid warnings
  (proxy config, flaky test) moved to `docs/REQUIREMENTS.md` (unverified
  checklist) and `HANDOFF.md` (traps). Recoverable via git history.
```

A superseded document replaced by a canonical one:

```markdown
- `docs/handoff-<date>.md` and later dated snapshots — superseded by this
  living HANDOFF in PR #52; decision context moved to `docs/REPORT.md`.
  Recoverable via git history. Do not resurrect the dated-snapshot
  pattern.
```

An archived (not deleted) document, where repository policy keeps history
readable in the working tree:

```markdown
- `docs/archive/` — frozen historical documents with an index README
  explaining what each was and why it was archived. Read only when
  investigating past decisions; nothing in it describes current state.
```

A dead investigation, so the next agent does not repeat it:

```markdown
- The <library> migration spike — abandoned; blockers recorded in
  `docs/REPORT.md` under "migration spike". Do not re-investigate unless
  the upstream issue linked there is resolved.
```

## Weak entries (avoid)

```markdown
- Old docs — cleaned up.                # what docs? where did content go?
- `docs/NOTES.md` — deleted.           # was anything in it still true?
- See git history for removed files.   # forces the next agent to diff-hunt
```

Each weak entry forces the next agent to do archaeology — which costs more
than the deletion saved.

## Maintenance

- Keep entries one to three lines; details belong in `docs/REPORT.md` or
  the PR that made the change.
- When an entry itself stops mattering (the deleted file's topic is gone
  entirely), delete the entry — the list obeys the same living-handoff
  compression as everything else in the file.
