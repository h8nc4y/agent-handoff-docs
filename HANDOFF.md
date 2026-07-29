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

Maintain the merged atomic process-exit observation contract. This work unit is
complete while the repository remains clean, local `main` matches
`origin/main`, and current hosted validation remains green.

## Current position

- The primary checkout is clean and local `main` matches `origin/main`.
- No pull request or issue is open. Recheck observable Git/GitHub state instead
  of copying a current commit SHA into this living file.
- The bounded polling loop snapshots `Process.HasExited` once after stream
  updates and reuses it for timeout, exit capture, and break. The AST seal is
  green with one direct read and four snapshot references.

## Verified historical closeout

- Pull request #13 merged the feature as `02b451d`. Head run `30354157531` and
  post-main run `30354646900` passed PowerShell 7, PowerShell 5.1, Ubuntu, and
  macOS.
- Pull request #14 merged the closeout as `d48e8ac`. Head run `30355295973` and
  final main run `30355898226` passed the same four hosted jobs.

## Key files

- `scripts/validate-oss-readiness.ps1` — readiness and atomic-exit contract.
- `docs/atomic-exit-observation-hardening*.md` — current Class M exit-race
  design and evidence.
- `CHANGELOG.md` and merged pull requests — durable history.

## Recent decisions

- Snapshot process exit once per polling iteration. Never let timeout, exit
  capture, and successful drain completion perform independent `HasExited`
  reads.

## Known issues

- No known source, test, or hosted-validation issue remains for the atomic
  exit-observation change.

## Do not re-read

- Pull requests #5–#9 review narratives — durable results are in
  `CHANGELOG.md` and merged history; executable contracts own current behavior.

## Next step

No immediate follow-up is required for this change. Select the next task from
current repository issues, pull requests, or reproducible test failures.
