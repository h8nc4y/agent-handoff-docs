# Living Handoff

## Canonical scope of this document

This file owns only the current repository work state and immediate next step.
Security invariants live in `docs/security-boundary-contract.md`; durable
history lives in `CHANGELOG.md` and merged pull requests. Observable Git,
test, and CI state outranks this summary.

## Traps before touching anything

- Keep `scripts/validate-oss-readiness.ps1` encoded as UTF-8 with BOM for
  Windows PowerShell 5.1.
- The first executable bounded-helper invocation in
  `scripts/test-scan-private-markers.ps1` is structurally guarded; insert new
  runtime fixtures only after the raw-transport regression.

## Current goal and success metric

Keep the merged template-section contract healthy and begin the next work unit
from current observable repository state. Success means `main` stays clean,
the latest hosted validation remains green, and a future template-structure
change updates its schema and mutation fixtures together.

## Current position

- Pull request #5 merged as `ed6f154` after all four hosted jobs succeeded.
- The `main` push run `30211103677` also passed Windows, Ubuntu, macOS 15, and
  Windows PowerShell 5.1.
- Bundled English and Japanese templates now have reviewed H1 and ordered H2
  contracts with 19 adversarial mutation regressions.
- No source defect or open follow-up issue is known for this work unit.

## Key files

- `scripts/validate-oss-readiness.ps1` — template contract and mutations.
- `templates/en/*.md` — reviewed English template structure.
- `templates/ja/*.md` — reviewed Japanese template structure.
- `README.md` — contributor-facing validation behavior.
- `CHANGELOG.md` — durable change record.

## Recent decisions

- Validate only the bundled source templates; repositories remain free to
  customize copied templates.
- Require the reviewed ATX H1/H2 structure. Fence-external Setext headings,
  raw HTML H1/H2, malformed backtick fences, and ambiguous peer structures
  fail closed.
- Preserve CRLF input, subordinate H3-H6 headings, valid fenced examples, and
  PowerShell 7 / Windows PowerShell 5.1 compatibility.

## Commands already run

- PowerShell 7/5.1 readiness, scanner self-tests, and repository scans — passed.
- Semgrep `p/default` — 82 rules over 32 files, zero findings.
- Gitleaks — about 417 KB scanned, no leak finding.
- Final independent review — P1=0, P2=0, P3=0.
- Pull request #5 and merged-main CI — all four jobs passed.

## Known issues

- None currently known.

## Do not re-read

- Pull request #4 handoff narrative — durable results are in `CHANGELOG.md`
  and merged history.
- Pull request #5 review iterations — final contract and regressions are
  executable in `scripts/validate-oss-readiness.ps1`.

## Next step

1. Reconcile current issues, pull requests, CI, and observable `main`, then
   select the highest-value safe unblocked task.
