# Worked Examples: Full-Scan Verification Commands

Deployment and propagation claims ("deployed to every repository",
"header added to every document") are complete only when one scan across
all targets confirms them — counting hits against the expected total.
Per-item bookkeeping inside the rollout loop does not count: interrupted
and resumed loops silently drop planned items (measured: a rollout
reported complete while 6 of 30 targets were missing).

All paths below are placeholders.

## Fleet-wide existence scan

Did every repository under a projects root receive `START_HERE.md`?

POSIX:

```bash
total=0; missing=0
for repo in "$HOME"/projects/*/; do
  [ -d "$repo/.git" ] || continue
  total=$((total + 1))
  if [ ! -f "$repo/START_HERE.md" ]; then
    missing=$((missing + 1))
    echo "MISSING: $repo"
  fi
done
echo "checked $total repositories, missing $missing"
```

PowerShell:

```powershell
$root = Join-Path $HOME 'projects'   # placeholder projects root
$repos = Get-ChildItem -LiteralPath $root -Directory |
  Where-Object { Test-Path (Join-Path $_.FullName '.git') }
$missing = $repos | Where-Object {
  -not (Test-Path (Join-Path $_.FullName 'START_HERE.md'))
}
"checked $($repos.Count) repositories, missing $($missing.Count)"
$missing | ForEach-Object { "MISSING: $($_.FullName)" }
```

Report the counts, not just "done": "30 checked, 0 missing" is evidence;
"deployed everywhere" is a claim.

## Every-document header scan

Did every document under `docs/` get the canonical-scope declaration?

```bash
expected=$(git ls-files 'docs/*.md' | wc -l)
actual=$(git grep -l "Canonical scope of this document" -- 'docs/*.md' | wc -l)
echo "expected $expected, found $actual"
git ls-files 'docs/*.md' |
  while read -r f; do
    grep -q "Canonical scope of this document" "$f" || echo "MISSING: $f"
  done
```

## Dangling-reference sweep after moving or deleting documents

Link checkers validate markdown links; they do not validate paths
mentioned in backtick code spans (measured: three backtick-quoted path
references survived a passing link check). Sweep the full text for every
old path:

```bash
# after moving docs/OLD_NOTES.md away:
git grep -n "OLD_NOTES.md"
```

Expected outcome: zero hits, or only the do-not-re-read entry that
records the move. Run one sweep per moved or deleted path.

## Point-in-time facts against the default branch

Local checkouts sit on old branches more often than anyone expects. When
verifying what is true for the next reader, read from `origin/<default>`,
not from the working tree:

```bash
git fetch origin
git ls-tree --name-only origin/main            # what actually exists
git show origin/main:HANDOFF.md                # what it actually says
```

Use this before consolidating documents: every "X is complete" claim you
are about to copy forward must hold on the default branch as of now, not
on a feature branch that may never merge. Check all such claims, not a
sample — in one measured consolidation, six separate completion claims
assumed a branch that never landed.

## Turning scan output into the ledger

When a scan finds gaps, the output is already the work order. Convert
each `MISSING:` line into a ledger row (target, smallest fix, confidence)
and the follow-up agent needs no further context — see the task-ledger
chapter of the skill.
