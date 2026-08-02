# Checkout v7 upgrade

## Classification and objective

- **Class:** M.
- **Objective:** Upgrade both canonical `actions/checkout` steps from v5.1.0
  to the verified official v7.0.1 full commit SHA.
- **Affected:** `.github/workflows/validate.yml`, the executable workflow
  contract and mutation fixtures, `CHANGELOG.md`, and the living handoff.
- **Unaffected:** Triggers, `contents: read`, the four hosted jobs, runners,
  25-minute timeouts, step sets, scanner behavior,
  `persist-credentials: false`, `SKILL.md`, templates, release tags, and
  GitHub Releases.

## Provenance and compatibility

- The official `actions/checkout` v7.0.1 tag resolves directly to commit
  `3d3c42e5aac5ba805825da76410c181273ba90b1`; GitHub reports the commit
  verification as valid.
- The release is published and is not marked immutable, so the workflow keeps
  the verified full commit SHA rather than the tag.
- v5.1.0 and v7.0.1 both use the Node 24 action runtime. This workflow does not
  use an authenticated Git command from a container action.

## Requirements

1. Both checkout steps use the same v7.0.1 full commit SHA and exact version
   comment.
2. Each checkout retains its immediately owned
   `with.persist-credentials: false` input.
3. The validator rejects mutable `@v7`, the legacy v5.1.0 full SHA, a stale
   version comment, and every previously rejected external `uses:` form.
4. The reviewed canonical workflow remains otherwise byte-equivalent after
   line-ending normalization.
5. Historical v5.1.0 changelog evidence remains historical and is not rewritten.

## Verification plan

- Measure baseline readiness, scanner self-tests, repository scans, and the
  latest four-job hosted run.
- Update the validator first and observe the old workflow fail, then update the
  workflow and require readiness under PowerShell 7 and Windows PowerShell 5.1.
- Freeze the final source and run repository scans, Gitleaks, targeted Semgrep,
  encoding/line-ending checks, `git diff --check`, and independent review.
- Verify the exact pull-request head and post-main commit on Windows PowerShell
  7, Windows PowerShell 5.1, Ubuntu, and macOS.

## Handoff

- **State:** doing. Official provenance, runtime compatibility, baseline live
  state, baseline local gates, validator-first RED / workflow GREEN, and final
  candidate local security/hygiene gates are verified. Two independent
  read-only reviews found no P0, P1, P2, or P3 issue.
- **Local evidence:** Final readiness and repository scans passed under
  PowerShell 7 and 5.1. Gitleaks found no leak; targeted Semgrep ran 82 rules
  on five files with no finding; UTF-8/BOM profiles, LF, NUL, and
  `git diff --check` passed.
- **External boundary:** No secret, OAuth, real data, production, deployment,
  paid operation, tag, or GitHub Release is used.
- **Not yet verified:** v7.0.1 pull-request/main hosted runs.
