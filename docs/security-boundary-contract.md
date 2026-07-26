# Security Boundary Contract

## Canonical scope of this document

This document is the source of truth for the repository's CI dependency-pin
policy and bounded child-process environment boundary. Implementation details
live in the named scripts; current work status lives in `HANDOFF.md`; release
history lives in `CHANGELOG.md`. If this document conflicts with executable
tests or the merged default branch, the executable repository state wins and
this document must be corrected.

## Objective

Prevent ambient supply-chain paths from influencing repository validation and
keep the bounded POSIX cleanup contract portable:

1. a mutable or dynamically selected external GitHub Action revision; and
2. an unrelated parent-process environment variable reaching a scanner or Git
   child merely because `ProcessStartInfo` cloned the parent environment; and
3. a platform-specific process-session path silently working on Linux while
   failing on macOS, where an external `setsid` executable is commonly absent.

## Threat model and invariants

- Every active external `uses:` entry under `.github/workflows/` must use an
  owner/repository reference pinned to one lowercase 40-character Git commit
  SHA. Repository-local `./` actions remain allowed.
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

## Implementation ownership

- `.github/workflows/validate.yml`: immutable Action revisions and the
  Windows/Ubuntu/macOS execution matrix.
- `scripts/validate-oss-readiness.ps1`: repository-wide external `uses:`
  policy, the built-in workflow canonical source, and positive and negative
  policy regressions.
- `scripts/private-marker-process.ps1`: minimum child environment builder and
  Git-specific safety controls.
- `scripts/test-scan-private-markers.ps1`: cross-platform positive and negative
  environment fixtures, parent-state checks, and scanner regressions.

## Acceptance criteria and test plan

Evidence snapshot: pull request #4 run `30200866202` passed the hosted
Windows, Ubuntu, macOS 15, and Windows PowerShell 5.1 jobs at commit
`ebf18db`. The successful macOS job `89790451214` emitted the forced native
`libc` `setsid(2)` evidence marker, completed the full self-test and repository
scan, and reported no `git-root-mismatch`.

| Criterion | Verification | Status |
| --- | --- | --- |
| Checkout uses the verified official full SHA | readiness validation and workflow review | verified locally and in the evidence snapshot |
| Any mutable, aliased, escaped, or malformed external `uses:` fails closed | synthetic positive/negative readiness fixtures on Windows, Ubuntu, and macOS | verified on local PS5/PS7 and all hosted PS7 runners |
| The built-in workflow cannot hide or redirect required checks | exact canonical-source comparison and mutation regression | verified on local PS5/PS7 and all hosted PS7 runners |
| Ambient credential, loader, agent, and custom variables are absent in bounded children | cross-platform environment probe | verified on hosted Windows, Ubuntu, and macOS |
| Required OS/runtime, isolation, PATH, locale, and Git controls remain usable | cross-platform positive environment probe and full scanner self-test | verified on hosted Windows, Ubuntu, and macOS |
| Windows PowerShell 5.1 and PowerShell 7 behavior remains compatible | local full PS5 validation and repository scan, hosted PS5 readiness/whitespace smoke, and hosted Windows/Ubuntu/macOS PS7 full self-test plus repository scan | verified locally and in the evidence snapshot |
| POSIX behavior, including the native session fallback, remains compatible | full self-test on Ubuntu and macOS; the fixture forces `libc` `setsid(2)` and rejects nonzero or unconfirmed-spawn evidence | verified on hosted Ubuntu and macOS |
| Repository security scan and whitespace checks pass | private-marker scan, Semgrep, Gitleaks, and `git diff --check` | private-marker and whitespace checks verified locally and in the evidence snapshot; Semgrep and Gitleaks verified locally |

## Non-goals

- Pinning GitHub-hosted runner images, which GitHub exposes through managed
  labels rather than repository-controlled commit SHAs.
- Passing secrets, OAuth credentials, production data, or cloud credentials to
  validation children.
- Deploying or publishing any artifact.
