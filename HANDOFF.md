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

Make the public synthetic examples executable reviewed contracts instead of
existence-only files. Success means readiness rejects title or level-two
section drift in every example, while the current valid examples pass on both
PowerShell 7 and Windows PowerShell 5.1.

## Current position

- `main` and `origin/main` both point to `ca1253f`; the working tree was clean
  before branch `test/lock-synthetic-example-contracts` was created.
- Open pull requests and issues are both zero.
- Main push run `30214901387` passed the hosted validation workflow.
- Readiness now pins the reviewed title and ordered level-two section schema
  of all three public synthetic examples.
- A temporary `## Maintenance` to `### Maintenance` mutation failed with the
  expected file-specific diagnostic, then was reverted.

## Key files

- `SKILL.md` — canonical English source included in the digest.
- `docs/SKILL.ja.md` — Japanese complete version and acknowledgement marker.
- `scripts/validate-oss-readiness.ps1` — strict byte/digest contract.
- `examples/*.md` — public synthetic guidance whose reviewed structure is the
  current validation target.
- `README.md` and `CHANGELOG.md` — public behavior and durable history.

## Recent decisions

- Read source as raw bytes, remove at most one physical UTF-8 BOM, decode
  strict UTF-8, then normalize line endings before SHA-256.
- Treat a second BOM as U+FEFF content and reject stale, duplicated,
  case-variant, displaced, or malformed markers.
- Treat the digest only as canonical-revision acknowledgement. It does not
  verify translation meaning.
- Reuse the exact reviewed Markdown title/section parser already exercised by
  19 fail-closed template mutations; do not add a YAML or Markdown dependency.

## Commands already run

- `git fetch --prune origin` — succeeded; local and remote main are equal.
- `gh pr list` / `gh issue list` — no open work.
- `gh run list` — latest main validation succeeded.
- PowerShell 7/5.1 readiness and full scanner self-tests — passed.
- PowerShell 7/5.1 repository scans — passed.
- Gitleaks history/worktree and Semgrep `p/default` — zero findings.
- Strict UTF-8/BOM/CR/NUL/TAB/form-feed and whitespace checks — passed.

## Known issues

- None currently known.

## Do not re-read

- Pull request #7 review iterations — the final byte and marker contract is
  executable in `scripts/validate-oss-readiness.ps1`.
- Pull requests #5 and #6 work narratives — durable results are in
  `CHANGELOG.md`, merged history, and the central dev log.

## Next step

1. Freeze and independently review the exact patch, then publish and verify
   hosted validation if clearance is granted.
