# Security Boundary Contract

## Canonical scope of this document

This document is the source of truth for the repository's CI dependency-pin
policy, bounded child-process environment boundary, and private-marker
snapshot-integrity boundary. Implementation details live in the named scripts;
current work status lives in `HANDOFF.md`; release history lives in
`CHANGELOG.md`. If this document conflicts with executable tests or the merged
default branch, the executable repository state wins and this document must be
corrected.

## Objective

Prevent ambient supply-chain paths from influencing repository validation and
keep the bounded POSIX cleanup contract portable:

1. a mutable or dynamically selected external GitHub Action revision;
2. checkout credentials remaining configured for later Git commands; and
3. an unrelated parent-process environment variable reaching a scanner or Git
   child merely because `ProcessStartInfo` cloned the parent environment; and
4. a platform-specific process-session path silently working on Linux while
   failing on macOS, where an external `setsid` executable is commonly absent;
   and
5. a tracked regular worktree file changing after its bytes were captured but
   before a successful private-marker report is emitted.

## Threat model and invariants

- Every active external `uses:` entry under `.github/workflows/` must use an
  owner/repository reference pinned to one lowercase 40-character Git commit
  SHA. Repository-local `./` actions remain allowed.
- Every active `actions/checkout` step must immediately set
  `with.persist-credentials` to the bare boolean `false`. Missing, enabled,
  duplicated, or later-step values fail closed.
- Non-canonical, dynamic, abbreviated, tag, branch, Docker, and unparseable
  external `uses:` forms fail closed.
- Because the validator must also run on Windows PowerShell 5.1 without a YAML
  dependency, workflows using explicit mapping keys, escaped/folded
  double-quoted scalars, or YAML anchors/aliases fail closed. These constructs
  can otherwise decode or alias into a hidden semantic `uses` key.
- The built-in `.github/workflows/validate.yml` must match its reviewed
  canonical source exactly after line-ending normalization. Extra fields,
  jobs, steps, scalar wrappers, and disabled or redirected checks therefore
  fail closed. Intentional workflow changes update both representations in one
  review.
- A bounded child starts from an empty environment map. It receives only
  runtime values derived from trusted OS APIs, isolation-root paths, a fixed
  locale, a bounded executable search path, and the scanner's explicit Git
  safety controls.
- The test-only scanner-entrypoint boundary may pass only explicit `GIT_*`
  variables, `PATH`, and the documented
  `AGENT_HANDOFF_DOCS_PRIVATE_MARKERS` scanner input; unrelated requested or
  ambient variables remain absent.
- Parent-process environment values and parent environment state are never
  copied or mutated by the bounded helper.
- The full PowerShell 7 validation suite runs on standard Windows, Ubuntu, and
  macOS runners. The macOS run must execute the self-test fixture that forces
  the native `libc` `setsid(2)` gate instead of relying on an external
  `setsid` executable.
- A native-session evidence marker is valid only when the target command exits
  zero, the grandchild payload confirms that it started, bounded cleanup
  is requested because the exited parent left a descendant-held pipe, cleanup
  stops and drains the process group, and the delayed grandchild sentinel does
  not appear.
- The Windows launch gate receives an explicit output-drain budget from the
  bounded parent. The effective gate budget never exceeds the parent's drain
  budget. Completion within that window preserves the requested child's exact
  byte streams and exit code; an inherited pipe that remains open beyond the
  window returns `125` and releases the parent to close the owned Job.
- Each bounded polling iteration reads `Process.HasExited` once. Timeout
  handling, exit-code capture, and successful stream-drain completion reuse
  that snapshot, so a fast exit cannot skip capture and return the initial exit
  code with otherwise healthy result flags.
- Every tracked regular worktree snapshot retains enough non-sensitive
  verification data to re-open the same relative path through the scanner's
  fail-closed path traversal. Immediately before final reporting, the scanner
  re-reads each retained path and compares its bytes exactly with the initial
  snapshot.
- A missing path, reparse path, type change, oversized file, read failure, or
  byte mismatch during final worktree verification fails with the fixed,
  non-reflective reason `integrity: worktree-content-drift`. The reason never
  includes a path or file content.
- This is a bounded two-observation contract: the final observed worktree
  bytes must exactly equal the initial snapshot. It is not a filesystem
  compare-and-swap guarantee and does not claim to detect a change after the
  final re-read.

## Implementation ownership

- `.github/workflows/validate.yml`: immutable Action revisions and the
  Windows/Ubuntu/macOS execution matrix.
- `scripts/validate-oss-readiness.ps1`: repository-wide external `uses:`
  and checkout-credential policies, the built-in workflow canonical source,
  and positive and negative policy regressions.
- `scripts/private-marker-process.ps1`: minimum child environment builder and
  Git-specific safety controls, including the bounded Windows gate drain.
- `scripts/scan-private-markers.ps1`: fail-closed tracked-worktree traversal,
  immutable scan snapshots, and final byte-for-byte snapshot verification.
- `scripts/test-scan-private-markers.ps1`: cross-platform positive and negative
  environment fixtures, parent-state checks, and deterministic scanner
  regressions, including same-length atomic worktree replacement.

## Acceptance criteria and test plan

Evidence snapshot: pull request #4 run `30200866202` passed the hosted
Windows, Ubuntu, macOS 15, and Windows PowerShell 5.1 jobs at commit
`ebf18db`. The successful macOS job `89790451214` emitted the forced native
`libc` `setsid(2)` evidence marker, completed the full self-test and repository
scan, and reported no `git-root-mismatch`.

| Criterion | Verification | Status |
| --- | --- | --- |
| Checkout uses the verified official full SHA | readiness validation and workflow review | verified locally and in the evidence snapshot |
| Checkout does not persist credentials for later Git commands | repository-wide checkout-input policy, exact canonical-source comparison, and mutation regressions | verified locally on PS5/PS7; hosted verification pending |
| Any mutable, aliased, escaped, or malformed external `uses:` fails closed | synthetic positive/negative readiness fixtures on Windows, Ubuntu, and macOS | verified on local PS5/PS7 and all hosted PS7 runners |
| The built-in workflow cannot hide or redirect required checks | exact canonical-source comparison and mutation regression | verified on local PS5/PS7 and all hosted PS7 runners |
| Ambient credential, loader, agent, and custom variables are absent in bounded children | cross-platform environment probe | verified on hosted Windows, Ubuntu, and macOS |
| Required OS/runtime, isolation, PATH, locale, and Git controls remain usable | cross-platform positive environment probe and full scanner self-test | verified on hosted Windows, Ubuntu, and macOS |
| Windows PowerShell 5.1 and PowerShell 7 behavior remains compatible | local full PS5 validation and repository scan, hosted PS5 readiness/whitespace smoke, and hosted Windows/Ubuntu/macOS PS7 full self-test plus repository scan | verified locally and in the evidence snapshot |
| POSIX behavior, including the native session fallback, remains compatible | full self-test on Ubuntu and macOS; the fixture forces `libc` `setsid(2)` and rejects nonzero or unconfirmed-spawn evidence | verified on hosted Ubuntu and macOS |
| A same-length tracked-worktree replacement cannot produce a stale success report | deterministic disposable-scanner-copy regression pauses after snapshot capture, atomically replaces the worktree file, and requires `integrity: worktree-content-drift` | verified locally on PowerShell 7; hosted cross-platform evidence pending |
| Windows gate scheduling delay does not corrupt raw transport, while a descendant-held pipe still fails closed | exact immediate transport, delayed-drain success beyond 100 ms, malformed payload fail-before-start, and over-budget inherited-pipe cleanup regressions | verified locally on PowerShell 7 and Windows PowerShell 5.1; hosted evidence pending |
| A fast child exit cannot skip exit-code capture between polling reads | AST single-snapshot seal, fast-exit `-ExitObservationOnly` regression on both Windows hosts and native Linux, forged-`OS` scanner regression, and hosted four-OS validation | targeted Windows and bounded native Linux evidence verified; full and hosted evidence pending |
| Repository security scan and whitespace checks pass | private-marker scan, Semgrep, Gitleaks, and `git diff --check` | private-marker and whitespace checks verified locally and in the evidence snapshot; Semgrep and Gitleaks verified locally |

## Non-goals

- Pinning GitHub-hosted runner images, which GitHub exposes through managed
  labels rather than repository-controlled commit SHAs.
- Passing secrets, OAuth credentials, production data, or cloud credentials to
  validation children.
- Claiming a filesystem compare-and-swap guarantee after the final worktree
  re-read has completed.
- Deploying or publishing any artifact.
