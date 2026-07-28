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

Make bounded process-exit observation atomic within each polling iteration.
Success means a fast child cannot skip exit-code capture between separate
`HasExited` reads, targeted Windows/Linux evidence is green, final full
self-tests pass on the exact reviewed freeze, and hosted validation is green.

## Current position

- Local and remote `main` are equal at merge commit `bff81eb` from pull request
  #12.
- Pull request #12 head run `30350038650` passed Windows PowerShell 7, Windows
  PowerShell 5.1, Ubuntu, and macOS. It included the corrected 250 ms
  immediate-spawn fixture and the 1-second production gate budget.
- Post-main run `30350539529` passed both Windows jobs and macOS. Ubuntu alone
  failed the forged-`OS` scanner assertion while sanitized stdout still said
  the scan passed.
- `Invoke-Scanner` adds a separate failure for unhealthy timeout, output-limit,
  tree-stop, or stream-drain flags. The hosted log contained only the nonzero
  exit assertion.
- The bounded polling loop read `Process.HasExited` three times per iteration.
  A false-to-true transition could therefore enter the successful drain break
  before exit-code capture and return the initial `-1` with healthy flags.
- Branch `fix/atomic-exit-observation` snapshots `HasExited` once after stream
  updates and reuses it for timeout, exit capture, and break. The AST seal was
  red with three direct reads and is green with one read and four snapshot
  references.
- The forged-`OS` failure now emits only fixed bounded flags and byte lengths.
  `-ExitObservationOnly` runs structural checks plus the first fast-exit raw
  transport regression without entering the wider fixture matrix.

## Key files

- `SKILL.md` — canonical English source included in the digest.
- `docs/SKILL.ja.md` — Japanese complete version and acknowledgement marker.
- `scripts/validate-oss-readiness.ps1` — strict byte/digest contract.
- `scripts/scan-private-markers.ps1` — snapshot capture and final integrity
  reporting boundary.
- `scripts/test-scan-private-markers.ps1` — deterministic regression owner.
- `docs/atomic-exit-observation-hardening*.md` — current Class M exit-race
  design, evidence, and acceptance criteria.
- `README.md` and `CHANGELOG.md` — public behavior and durable history.

## Recent decisions

- Snapshot process exit once per polling iteration. Never let timeout, exit
  capture, and successful drain completion perform independent `HasExited`
  reads.
- Keep fast-exit failure diagnostics non-reflective: fixed flags, exit state,
  and byte lengths only.
- Keep BOM-less PowerShell 5.1-executed source comments in the repository's
  established English/ASCII style; keep Japanese rationale in companion docs.

## Commands already run

- Exit-observation AST seal RED — target loop direct `HasExited` reads `3`,
  static seal false.
- Exit-observation AST seal GREEN — target loop direct read `1`, snapshot
  references `4`, static seal true.
- `-ExitObservationOnly` on PowerShell 7 and Windows PowerShell 5.1 — both exit
  `0`, exact final marker, stderr zero bytes.
- Cached Linux image `a52d8a7eeb3c` with network disabled, read-only
  root/repository, `no-new-privileges`, finite resources, and a 45-second
  watchdog — exit `0`, exact final marker, stderr zero bytes, residual
  containers zero.
- A BOM-less Japanese source comment made Windows PowerShell 5.1 absorb the
  following snapshot assignment into the comment token. Restoring the file's
  established English/ASCII comment convention produced one assignment and
  four references in the PS5.1 AST, then the targeted test passed.
- PowerShell 7/5.1 OSS readiness — both exit `0`.
- Text hygiene across eight changed/new files — strict UTF-8, no BOM/CRLF/NUL/
  tab/form-feed, final LF present; `git diff --check` passed.
- Gitleaks 8.30.1 directory/history — zero findings. Semgrep 1.165.0
  `p/default` — 82 rules, 38 tracked targets, zero findings.

## Known issues

- Exact-freeze full self-tests, independent review, repository private-marker
  scans, and hosted validation for `fix/atomic-exit-observation` remain
  pending.

## Do not re-read

- Pull request #7 review iterations — the final byte and marker contract is
  executable in `scripts/validate-oss-readiness.ps1`.
- Pull requests #5 and #6 work narratives — durable results are in
  `CHANGELOG.md`, merged history, and the central dev log.
- Pull request #9 review iterations — the merged example contracts and their
  shared fail-closed parser are executable in readiness validation.

## Next step

1. Run non-scanner text/security gates and freeze the exact staged tree.
2. Request independent P0–P3 review of the freeze.
3. After the shared scanner slot is available, run final PowerShell 7/5.1 full
   self-tests and repository scans.
4. Push, validate the hosted matrix, merge, and revalidate `main`.
