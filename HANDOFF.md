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

Keep the merged skill-translation acknowledgement healthy and begin the next
work unit from current observable repository state. Success means `main`
stays clean, the latest hosted validation remains green, and canonical skill
changes receive bilingual review plus a marker update in one change.

## Current position

- Pull request #7 merged as `09afb1f` after all four hosted jobs succeeded.
- The `main` push run `30214378747` also passed Windows, Ubuntu, macOS 15, and
  Windows PowerShell 5.1.
- The Japanese complete skill acknowledges the normalized canonical digest.
- No source defect or open follow-up issue is known for this work unit.

## Key files

- `SKILL.md` — canonical English source included in the digest.
- `docs/SKILL.ja.md` — Japanese complete version and acknowledgement marker.
- `scripts/validate-oss-readiness.ps1` — strict byte/digest contract.
- `CONTRIBUTING.md` — bilingual semantic-review responsibility.
- `README.md` and `CHANGELOG.md` — public behavior and durable history.

## Recent decisions

- Read source as raw bytes, remove at most one physical UTF-8 BOM, decode
  strict UTF-8, then normalize line endings before SHA-256.
- Treat a second BOM as U+FEFF content and reject stale, duplicated,
  case-variant, displaced, or malformed markers.
- Treat the digest only as canonical-revision acknowledgement. It does not
  verify translation meaning.

## Commands already run

- PowerShell 7/5.1 readiness, scanner self-tests, and repository scans — passed.
- Semgrep `p/default` — 82 rules over 32 files, zero findings.
- Gitleaks — about 437 KB scanned, no leak finding.
- Final independent review — P1=0, P2=0, P3=0.
- Pull request #7 and merged-main CI — all four jobs passed.

## Known issues

- None currently known.

## Do not re-read

- Pull request #7 review iterations — the final byte and marker contract is
  executable in `scripts/validate-oss-readiness.ps1`.
- Pull requests #5 and #6 work narratives — durable results are in
  `CHANGELOG.md`, merged history, and the central dev log.

## Next step

1. Reconcile current issues, pull requests, CI, and observable `main`, then
   select the highest-value safe unblocked task.
