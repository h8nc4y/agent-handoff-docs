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

Upgrade both canonical `actions/checkout` steps from v5.1.0 to the verified
official v7.0.1 full commit SHA. This work succeeds when the exact workflow and
validator mutations agree, local PowerShell/security gates pass, independent
review is clear, and the pull-request head plus post-main runs pass all four
hosted jobs without changing any other workflow boundary.

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
- Final candidate readiness, repository scans, Gitleaks, Semgrep, encoding,
  and whitespace checks passed. Two independent read-only reviews found no
  P0, P1, P2, or P3 issue. Pull-request CI, merge, and post-main evidence
  remain pending.

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

1. Push one focused pull request, verify all four hosted jobs on its exact
   head, merge, and verify the post-main run.
2. Sync integration evidence, clean the task branch, and return the repository
   to its measured wait state. Do not retry `actionlint` in this work unit.
