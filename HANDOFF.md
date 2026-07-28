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

Close the tracked-worktree content-drift gap without weakening the scanner's
existing fail-closed boundaries. Success means a deterministic same-length
atomic replacement fails with the fixed non-reflective reason, both scan modes
reuse the existing safe traversal, and all local and hosted validation remains
green.

## Current position

- Local and remote `main` are equal at `a005c2b`.
- Merged-main run `30237752341` passed Windows, Ubuntu, macOS 15, and Windows
  PowerShell 5.1.
- Open pull requests and issues are both zero.
- The baseline disposable scanner-copy reproduction proved that a same-length
  tracked worktree replacement after snapshot capture passed from stale bytes,
  while a direct control scan detected the replacement.
- Branch `fix/worktree-content-drift` now retains every regular-worktree
  snapshot and re-reads it immediately before reporting. Targeted Git and
  fallback regressions pass with the fixed non-reflective reason.

## Key files

- `SKILL.md` — canonical English source included in the digest.
- `docs/SKILL.ja.md` — Japanese complete version and acknowledgement marker.
- `scripts/validate-oss-readiness.ps1` — strict byte/digest contract.
- `scripts/scan-private-markers.ps1` — snapshot capture and final integrity
  reporting boundary.
- `scripts/test-scan-private-markers.ps1` — deterministic regression owner.
- `docs/worktree-content-drift-hardening*.md` — Class M design and acceptance
  criteria in English and Japanese.
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
- Retain verification metadata only for regular-worktree snapshots. Re-read
  them through the existing safe traversal immediately before final reporting,
  compare bytes exactly, and map all final-boundary failures to one
  non-reflective reason.
- Describe this as a bounded two-observation guarantee, not filesystem
  compare-and-swap after the final read.

## Commands already run

- Targeted same-length atomic replacement — Git and fallback modes both exit
  `2`; fixed reason present; path and sentinel absent.
- PowerShell 7/5.1 readiness and repository scans — passed.
- Gitleaks 8.30.1 directory/history scans and Semgrep 1.165.0 `p/default` —
  zero findings.
- Strict UTF-8/BOM/CR/NUL/TAB/form-feed, final-LF, and whitespace checks —
  passed for all eight changed files.
- PowerShell 7 full scanner self-test — exit `0`, final marker
  `Private marker scan self-test passed.`, stderr zero bytes.

## Known issues

- Hosted cross-platform validation for this branch remains pending until the
  pull request runs.

## Do not re-read

- Pull request #7 review iterations — the final byte and marker contract is
  executable in `scripts/validate-oss-readiness.ps1`.
- Pull requests #5 and #6 work narratives — durable results are in
  `CHANGELOG.md`, merged history, and the central dev log.
- Pull request #9 review iterations — the merged example contracts and their
  shared fail-closed parser are executable in readiness validation.

## Next step

1. Freeze the exact staged tree and patch for independent review.
2. Push, run hosted validation, merge, and revalidate `main`.
