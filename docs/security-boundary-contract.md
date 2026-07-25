# Security Boundary Contract

## Canonical scope of this document

This document is the source of truth for the repository's CI dependency-pin
policy and bounded child-process environment boundary. Implementation details
live in the named scripts; current work status lives in `HANDOFF.md`; release
history lives in `CHANGELOG.md`. If this document conflicts with executable
tests or the merged default branch, the executable repository state wins and
this document must be corrected.

## Objective

Prevent two ambient supply-chain paths from influencing repository validation:

1. a mutable or dynamically selected external GitHub Action revision; and
2. an unrelated parent-process environment variable reaching a scanner or Git
   child merely because `ProcessStartInfo` cloned the parent environment.

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

## Implementation ownership

- `.github/workflows/validate.yml`: immutable Action revisions and the
  Windows/Ubuntu execution matrix.
- `scripts/validate-oss-readiness.ps1`: repository-wide external `uses:`
  policy, the built-in workflow canonical source, and positive and negative
  policy regressions.
- `scripts/private-marker-process.ps1`: minimum child environment builder and
  Git-specific safety controls.
- `scripts/test-scan-private-markers.ps1`: cross-platform positive and negative
  environment fixtures, parent-state checks, and scanner regressions.

## Acceptance criteria and test plan

| Criterion | Verification | Status |
| --- | --- | --- |
| Checkout uses the verified official full SHA | readiness validation and workflow review | locally verified; Windows/Ubuntu PR CI required |
| Any mutable, aliased, escaped, or malformed external `uses:` fails closed | synthetic positive/negative readiness fixtures on Windows and Ubuntu | locally verified on PS5, PS7, and Linux-equivalent container; Windows/Ubuntu PR CI required |
| The built-in workflow cannot hide or redirect required checks | exact canonical-source comparison and mutation regression | locally verified on PS5, PS7, and Linux-equivalent container; Windows/Ubuntu PR CI required |
| Ambient credential, loader, agent, and custom variables are absent in bounded children | cross-platform environment probe | locally verified on PS5, PS7, and Linux-equivalent container; Windows/Ubuntu PR CI required |
| Required OS/runtime, isolation, PATH, locale, and Git controls remain usable | cross-platform positive environment probe and full scanner self-test | locally verified on PS5, PS7, and Linux-equivalent container; Windows/Ubuntu PR CI required |
| Windows PowerShell 5.1 and PowerShell 7 behavior remains compatible | local full PS5 validation and repository scan, hosted PS5 readiness/whitespace smoke, and hosted Windows/Ubuntu PS7 full self-test plus repository scan | locally verified; Windows/Ubuntu PR CI required |
| POSIX behavior remains compatible | Linux-equivalent local run and Ubuntu CI | locally verified; Ubuntu PR CI required |
| Repository security scan and whitespace checks pass | private-marker scan, Semgrep, Gitleaks, and `git diff --check` | locally verified; Windows/Ubuntu PR CI required |

## Non-goals

- Pinning GitHub-hosted runner images, which GitHub exposes through managed
  labels rather than repository-controlled commit SHAs.
- Passing secrets, OAuth credentials, production data, or cloud credentials to
  validation children.
- Deploying or publishing any artifact.
