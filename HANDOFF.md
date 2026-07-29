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

Ensure every `actions/checkout` step disables credential persistence and make
readiness reject an omitted, enabled, duplicated, or misplaced setting. This
work unit is complete after both local PowerShell paths and scanners pass, an
independent review is clear, the pull request is merged, and post-merge hosted
validation is green.

## Current position

- The primary checkout is clean and local `main` matches `origin/main`.
- No pull request or issue is open. Recheck observable Git/GitHub state instead
  of copying a current commit SHA into this living file.
- An isolated task branch adds `persist-credentials: false` to both checkout
  steps without changing workflow pins, triggers, permissions, jobs, matrix,
  timeouts, or commands.
- Readiness now owns the repository-wide checkout credential policy and its
  missing, enabled, borrowed, duplicated, and partial-coverage regressions.
- Readiness, the scanner self-test, and the repository scan pass locally under
  PowerShell 7 and Windows PowerShell 5.1. Gitleaks and Semgrep also pass.

## Verified historical closeout

- Pull request #13 merged the feature as `02b451d`. Head run `30354157531` and
  post-main run `30354646900` passed PowerShell 7, PowerShell 5.1, Ubuntu, and
  macOS.
- Pull request #14 merged the closeout as `d48e8ac`. Head run `30355295973` and
  final main run `30355898226` passed the same four hosted jobs.

## Key files

- `.github/workflows/validate.yml` — canonical validation workflow.
- `scripts/validate-oss-readiness.ps1` — readiness and checkout policy.
- `docs/security-boundary-contract.md` — owned security invariants and tests.
- `CHANGELOG.md` and merged pull requests — durable history.

## Recent decisions

- Place bare `persist-credentials: false` immediately under every checkout
  action. A later step or another checkout cannot satisfy that checkout.

## Known issues

- `actionlint` remains unconfirmed and is not retried for this work unit.

## Do not re-read

- Pull requests #5–#9 review narratives — durable results are in
  `CHANGELOG.md` and merged history; executable contracts own current behavior.

## Next step

Perform an independent frozen-diff review, then stage the exact reviewed files,
run the global security hook, commit, and open the pull request.
