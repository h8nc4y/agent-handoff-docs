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

Replace the Windows launch gate's fixed 100 ms post-exit drain with an explicit
bounded budget derived from the parent contract. Success means ordinary
scheduler delay preserves exact raw transport, an over-budget inherited pipe
still returns `125` and is killed with the owned Job, and all local and hosted
validation is green.

## Current position

- Local and remote `main` are equal at `6603a83`.
- Pull request #11 run `30341015703` passed every hosted job, but merged-main
  run `30341569740` failed the first Windows PowerShell 7 raw-transport
  assertion before the new worktree-drift fixtures ran.
- The exact merged tree then passed one bounded local PowerShell 7 full
  self-test with exit `0`, the final success marker, and zero stderr bytes.
- Historical run `30144735948` failed the same assertion before pull request
  #11 existed. Both the fixed 100 ms gate drain and the raw regression's
  explicit 5-second test timeout are therefore pre-existing reliability
  boundaries, not regressions introduced by worktree verification.
- A later loaded local targeted run preserved stdout 12/12 and stderr 8/8
  exactly but returned `TimedOut=True`, exit `0`, with the tree stopped and
  streams drained. This proves the 5-second test budget was independently too
  tight; it does not identify the old hosted run's missing field-level cause.
- Open pull requests and issues are both zero.
- Branch `fix/windows-gate-drain-budget` now passes an explicit validated
  budget in the trusted payload. Missing/coerced/out-of-range values fail before
  child start; a 300 ms holder preserves exact transport under an explicit
  2-second budget; a 4-second holder requesting 5 seconds is capped by the
  parent's 2-second drain, returns `125`, and is killed with the owned Job.
- The three targeted Windows timing probes—first raw transport,
  delayed-within-budget, and over-budget inherited pipe—use the existing finite
  30-second production default. The production implementation/default and
  native Git fixture remain unchanged.

## Key files

- `SKILL.md` — canonical English source included in the digest.
- `docs/SKILL.ja.md` — Japanese complete version and acknowledgement marker.
- `scripts/validate-oss-readiness.ps1` — strict byte/digest contract.
- `scripts/scan-private-markers.ps1` — snapshot capture and final integrity
  reporting boundary.
- `scripts/test-scan-private-markers.ps1` — deterministic regression owner.
- `docs/worktree-content-drift-hardening*.md` — Class M design and acceptance
  criteria in English and Japanese.
- `docs/windows-gate-drain-hardening*.md` — current Class M design, evidence,
  and acceptance criteria.
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
- Pass a finite Windows gate output-drain budget in the trusted payload. Never
  exceed the parent's drain budget or remove the exit `125` fail-closed path.
- Treat the hosted failure's exact field-level cause as unconfirmed because the
  old assertion emitted no bounded-result metadata. Prove the corrected timing
  boundary with deterministic synthetic fixtures.

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
- Exact merged-main diagnostic PowerShell 7 full self-test — exit `0`, final
  marker present, stderr zero bytes, and no matching process remained.
- Targeted Windows gate RED — exit `1`; invalid payloads started their child
  and the 300 ms holder returned `125`.
- Targeted Windows gate GREEN on PowerShell 7 and Windows PowerShell 5.1 —
  both exit `0`, final marker present, stderr zero bytes, and no scanner/gate
  process remained.
- Focused-review attempts under later host load then timed out the first raw
  probe at 5 seconds (12/12 and 8/8 exact) and 10 seconds (0/12 and 0/8).
  Both stopped the tree and drained streams. Attempt three uses the existing
  30-second production default as the finite test-only budget.

## Known issues

- Merged-main run `30341569740` remains red until the bounded Windows gate
  follow-up is implemented and validated.
- Final full scanner self-tests and hosted validation for this branch remain
  pending.

## Do not re-read

- Pull request #7 review iterations — the final byte and marker contract is
  executable in `scripts/validate-oss-readiness.ps1`.
- Pull requests #5 and #6 work narratives — durable results are in
  `CHANGELOG.md`, merged history, and the central dev log.
- Pull request #9 review iterations — the merged example contracts and their
  shared fail-closed parser are executable in readiness validation.

## Next step

1. Run non-scanner static/security gates and freeze the exact staged tree.
2. Request independent P0–P3 review of the freeze.
3. After the shared scanner slot is available, run final PowerShell 7/5.1 full
   self-tests and repository scans.
4. Push, validate the hosted matrix, merge, and revalidate `main`.
