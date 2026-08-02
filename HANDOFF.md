# Living Handoff

## Canonical scope of this document

This file owns only the current repository work state and immediate next step.
Security invariants live in `docs/security-boundary-contract.md`; durable
history lives in `CHANGELOG.md` and merged pull requests. Observable Git,
test, and CI state outranks this summary.

## Traps before touching anything

- Keep `scripts/validate-oss-readiness.ps1` encoded as UTF-8 with BOM for
  Windows PowerShell 5.1.
- `SKILL.md` is the English canonical skill. A change to it must update the
  Japanese translation and its hidden `canonical-en-sha256` marker together.

## Current goal and success metric

Keep this repository in a measured wait state after completing the checkout
v7.0.1 upgrade. Future work succeeds when it starts from fresh Git, GitHub, CI,
and contract measurements, preserves the verified workflow/security boundary,
and does not repeat this integrated work.

## Current position

- Baseline `main`, `origin/main`, and live GitHub `main` were
  `71a0194c7eb081ede0e873cf073bf125ec01fe00`; the tree was clean with no open
  issue, pull request, deployment, stash, or additional worktree.
- The official v7.0.1 tag resolves directly to verified commit
  `3d3c42e5aac5ba805825da76410c181273ba90b1`. Both v5.1.0 and v7.0.1 use the
  Node 24 action runtime.
- Validator-first TDD rejected the old workflow with four expected contract
  diagnostics. Updating the two checkout steps restored PowerShell 7 and 5.1
  readiness without changing triggers, permissions, jobs, runners, timeouts,
  steps, or `persist-credentials: false`.
- Pull request #20 merged the reviewed feature commit as
  `b41591039a39ee2a5068e7c46001431e4010d32d`. Its pull-request head run and
  exact post-main run passed all four hosted jobs; the feature and merge trees
  were identical.
- Post-main readiness and repository scans passed under PowerShell 7 and 5.1.
  No open source, runtime, or documentation change remains in this work unit.

## Verified evidence used by this work unit

- Baseline run `30589709258` passed Windows PowerShell 7, Windows PowerShell
  5.1, Ubuntu, and macOS on the baseline commit.
- Baseline readiness passed under PowerShell 7 and 5.1. Scanner self-tests
  passed in 471.6 and 217.2 seconds respectively; repository scans passed in
  17 and 10 seconds respectively.
- Candidate readiness passed under PowerShell 7 and 5.1 in 1.3 and 0.9 seconds;
  repository scans passed in 17.8 and 10.4 seconds. Gitleaks found no leak,
  targeted Semgrep ran 82 rules on five files with no finding, and encoding,
  line-ending, NUL, and whitespace checks passed.
- Two independent read-only reviews of the same staged candidate reported no
  P0, P1, P2, or P3 issue.
- Pull-request head run `30740612980` passed Windows PowerShell 7, Windows
  PowerShell 5.1, Ubuntu, and macOS on feature commit `9174160`.
- Post-main run `30740886674` passed the same four jobs on merge commit
  `b41591039a39ee2a5068e7c46001431e4010d32d`.
- On that merge commit, post-main readiness passed under PowerShell 7 and 5.1
  in 1.6 and 1.0 seconds; repository scans passed in 16.9 and 10.1 seconds.
- Runs `30341569740` and `30350539529` each had one failed job and remain
  excluded from passing evidence.

## Key files

- `.github/workflows/validate.yml` — canonical validation workflow.
- `scripts/validate-oss-readiness.ps1` — readiness and checkout policy.
- `docs/security-boundary-contract.md` — owned security invariants and tests.
- `CHANGELOG.md` and merged pull requests — durable history.

## Recent decisions

- Record a passing pull-request head and a later passing main run for the
  earlier hardening units. Do not relabel either failed immediate post-merge
  run as green.

## Known issues

- `actionlint` remains unconfirmed and is not retried for this work unit.

## Do not re-read

- Pull requests #5–#9 review narratives — durable results are in
  `CHANGELOG.md` and merged history; executable contracts own current behavior.

## Next step

1. Before selecting another work unit, remeasure Git status, default-branch
   drift, open issues and pull requests, and the latest exact-main CI result.
2. If those measurements reveal no safe contract gap, leave this repository
   unchanged and continue the cross-project development loop. `actionlint`
   remains unconfirmed and must not be represented as passing evidence.
