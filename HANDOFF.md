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

Turn the English/Japanese skill synchronization rule into an executable
change-acknowledgement contract. Success means an English-only canonical
change fails readiness, equivalent BOM/LF/CRLF transport forms remain stable,
semantic translation review is not overstated, and all hosted jobs pass on
the merged default branch.

## Current position

- `main` and `origin/main` both pointed to `22d2879` when this work began.
- No open issue or pull request existed at task selection time.
- Branch `test/lock-skill-translation-digest` owns this Class M work unit.
- TDD RED: both PowerShell engines rejected the missing Japanese digest marker.
- GREEN: the reviewed marker and seven negative digest mutations pass on
  PowerShell 7 and Windows PowerShell 5.1.
- Independent review found one P2 double-BOM gap caused by `Get-Content`
  stripping a physical BOM before string normalization. The contract now reads
  raw bytes, strips at most one BOM, decodes strict UTF-8, and keeps a second
  BOM as content.

## Key files

- `SKILL.md` — canonical English source included in the digest.
- `docs/SKILL.ja.md` — Japanese complete version and acknowledgement marker.
- `scripts/validate-oss-readiness.ps1` — normalized digest contract.
- `CONTRIBUTING.md` — human translation-review responsibility.
- `README.md` and `CHANGELOG.md` — public behavior and durable history.

## Recent decisions

- Normalize only a leading BOM and line endings before hashing, so the marker
  is portable without ignoring later document content.
- Require one lowercase marker directly below the fixed Japanese title.
- Describe the marker as review acknowledgement, never proof of translation
  quality.

## Commands already run

- GitHub issue/PR query — both open counts were zero.
- Latest `main` run `30211636145` — all four jobs passed.
- PowerShell 7/5.1 readiness RED before marker and GREEN after marker.
- PowerShell 7/5.1 scanner self-tests — both passed.
- PowerShell 7/5.1 repository scans — both passed.
- Semgrep `p/default` — 82 rules over 32 files, zero findings.
- Gitleaks — about 437 KB scanned, no leak finding.
- Final independent review — P1=0, P2=0, P3=0 at raw diff SHA-256
  `bfec791172cadbc332139796f8ce176e58b560f5c45749d3412baab139e9e2de`.

## Known issues

- No source defect is known in the reviewed worktree.

## Do not re-read

- Pull requests #5 and #6 work narratives — durable results are in
  `CHANGELOG.md`, merged history, and the previous dev-log entry.

## Next step

1. Commit and push the reviewed change, open a pull request, and require every
   hosted validation job to pass before merge.
