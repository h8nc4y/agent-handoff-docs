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

Prevent bundled English and Japanese document templates from silently losing,
duplicating, or reordering their required level-two sections. Success means the
readiness validator rejects structural mutations in either language, accepts
the reviewed templates on PowerShell 7 and Windows PowerShell 5.1, and the
merged default branch passes all hosted validation jobs.

## Current position

- `main` and `origin/main` both pointed to `f7e24ce` when this work began.
- No open issue or pull request existed at task selection time.
- Branch `test/lock-template-section-contract` owns this Class M work unit.
- Mutation tests first demonstrated that the previous canonical-scope-only
  check accepted missing, reordered, duplicated, demoted, fenced, and
  wrong-title variants.
- The validator now enforces each reviewed title and ordered H2 schema while
  permitting subordinate headings and CRLF input.
- Independent review found two P2 parser gaps: valid indented/Setext/empty
  headings were not recognized, and an invalid backtick fence could hide an
  actual peer heading. Both now fail closed with dedicated regressions.
- Second review found one P2 raw-HTML gap; fence-external H1/H2 tags now fail
  closed case-insensitively with attribute-bearing fixtures.
- Third review found one P2 HTML-whitespace edge; form-feed-separated H1/H2
  attributes are now covered by the raw-tag rejection and a regression.

## Key files

- `scripts/validate-oss-readiness.ps1` — template contract and mutation tests.
- `templates/en/*.md` — reviewed English template structure.
- `templates/ja/*.md` — reviewed Japanese template structure.
- `README.md` — validation behavior exposed to contributors.
- `CHANGELOG.md` — durable change record.

## Recent decisions

- Validate only the bundled template schema; project adopters remain free to
  customize copied templates.
- Require the reviewed H1 and exact ordered H2 list while allowing subordinate
  H3-H6 content within a section.
- Ignore heading-looking text inside fenced code blocks so examples cannot
  satisfy the contract.

## Commands already run

- `git fetch --prune origin` — completed; `main == origin/main`.
- GitHub issue/PR query — both open counts were zero.
- GitHub Actions query — latest `main` Validate run `30201622699` succeeded.
- `pwsh -NoProfile -File .\scripts\validate-oss-readiness.ps1` — passed.
- `powershell.exe ... -File .\scripts\validate-oss-readiness.ps1` — passed.
- PowerShell 7/5.1 scanner self-tests — both passed.
- PowerShell 7/5.1 repository scans — both passed.
- Semgrep `p/default` — 82 rules over 32 files, zero findings.
- Gitleaks — about 417 KB scanned, no leak finding.
- Final independent review — P1=0, P2=0, P3=0 at raw diff SHA-256
  `ebac2070849b437976b52227997829c578c9cf4934bd9f4e4b529ff3befa4e19`.

## Known issues

- No source defect is known in the reviewed worktree.

## Do not re-read

- Pull request #4 handoff narrative — merged and summarized in `CHANGELOG.md`;
  current CI evidence is available from GitHub Actions.

## Next step

1. Commit and push the reviewed change, open a pull request, and require every
   hosted validation job to pass before merge.
