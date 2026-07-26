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

Measure the POSIX native `setsid(2)` fallback on a real macOS runner. Success
means the standard `macos-15` job runs the complete PowerShell 7 validation
suite, every acceptance criterion in `docs/security-boundary-contract.md` has
current pull-request evidence, and the merged default branch is clean.

## Key files

- `.github/workflows/validate.yml`
- `scripts/validate-oss-readiness.ps1`
- `scripts/private-marker-process.ps1`
- `scripts/test-scan-private-markers.ps1`
- `docs/security-boundary-contract.md`
- `README.md`
- `CHANGELOG.md`

## Recent decisions

- Use the public repository's standard `macos-15` runner; do not add a larger
  runner, external service, dependency, cache, artifact, or release step.
- Run the same full PowerShell 7 suite on macOS rather than a reduced smoke
  test. The existing self-test explicitly forces the native POSIX session gate.
- Treat `.github/workflows/validate.yml`, its embedded canonical source, and
  the runner-presence assertions in `scripts/validate-oss-readiness.ps1` as one
  reviewed change.

## Verification

- Baseline `main` commit `2a73dad` equals `origin/main` and has a successful
  Validate run (`30147382074`).
- Open issue and pull-request counts were both zero when this work unit began.
- TDD RED: readiness reported the missing `macos-15` runner and accepted
  missing-runner mutation. After the paired workflow/canonical-source change,
  readiness passes on local PowerShell 7 and Windows PowerShell 5.1.
- Review-fix TDD RED: readiness rejected missing POSIX detached/race exit-code
  checks and the absent evidence-eligibility regression. The fixed predicate
  rejects nonzero commands and unconfirmed grandchild starts; the payload
  itself writes the start confirmation before its delayed action. Evidence
  also requires the bounded helper to observe a descendant-held pipe after the
  parent exits; a non-pipe-leak synthetic result is rejected.
- Latest path-fix local full gates pass: PowerShell 7
  readiness/self-test/scan in about 457 seconds and Windows PowerShell 5.1
  readiness/self-test/scan in about 202 seconds.
- Semgrep `p/default` ran 82 rules over 32 tracked files with zero findings.
  Gitleaks scanned about 389 KB with no leak finding.
- Pull request #4 run `30200866202` passed all four jobs at commit `ebf18db`.
  macOS job `89790451214` emitted the forced native-session marker once,
  completed the full self-test and repository scan, and contained zero
  `git-root-mismatch` lines.
- The first macOS run exposed logical `/var` versus physical `/private/var`
  fixture roots after emitting the marker. The scanner identity guard stayed
  unchanged; physicalizing only the synthetic temp root fixed the failure.

## Known issues

- No source defect is known after the successful cross-platform run. The
  evidence-only documentation commit still needs final-head CI before merge.

## Do not re-read

- No superseded document in this work unit.

## Next step

Commit the evidence snapshot, push it to pull request #4, and require the
macOS, Windows, Ubuntu, and Windows PowerShell 5.1 checks to pass again on the
final head. Reconfirm the successful final-head macOS log contains the forced
native `libc` `setsid(2)` evidence marker, then merge and clean the branch.
