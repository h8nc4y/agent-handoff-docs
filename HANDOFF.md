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

Keep the merged synthetic-example contracts healthy and begin the next work
unit from current observable repository state. Success means `main` stays
clean, hosted validation remains green, and intentional example structure
changes update the reviewed contract in the same change.

## Current position

- Pull request #9 merged as `f1e6b05`; local and remote `main` are equal.
- Pull request run `30236574907` and merged-main run `30236893869` each passed
  Windows, Ubuntu, macOS 15, and Windows PowerShell 5.1.
- Open pull requests and issues are both zero.
- Readiness now pins the reviewed title and ordered level-two section schema
  of all three public synthetic examples.

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
- Pull request #9 and merged-main hosted validation — all four jobs passed.
- PowerShell 7/5.1 readiness and full scanner self-tests — passed.
- PowerShell 7/5.1 repository scans — passed.
- Gitleaks history/worktree and Semgrep `p/default` — zero findings.
- Strict UTF-8/BOM/CR/NUL/TAB/form-feed and whitespace checks — passed.
- Final independent review — P0=0, P1=0, P2=0, P3=0.

## Known issues

- None currently known.

## Do not re-read

- Pull request #7 review iterations — the final byte and marker contract is
  executable in `scripts/validate-oss-readiness.ps1`.
- Pull requests #5 and #6 work narratives — durable results are in
  `CHANGELOG.md`, merged history, and the central dev log.
- Pull request #9 review iterations — the merged example contracts and their
  shared fail-closed parser are executable in readiness validation.

## Next step

1. Reconcile current issues, pull requests, CI, and observable `main`, then
   select the highest-value safe unblocked task.
