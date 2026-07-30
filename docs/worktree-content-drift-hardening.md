# Tracked Worktree Content-Drift Hardening

## Classification and objective

This is a Class M security bug fix. Prevent the private-marker scanner from
reporting success when a tracked regular worktree file is atomically replaced
with different bytes of the same length after the scanner captures its initial
snapshot.

## Impact and scope

The current post-read check rejects reparse, type, and length drift, while the
final report gate rechecks only Git index metadata. A same-length worktree
replacement can therefore make a successful report describe stale bytes.

The fix applies to retained regular-worktree snapshots in both Git-index mode
and working-tree fallback mode. Index-only and missing-worktree scan targets do
not have a regular worktree path to revalidate.

## Design

1. Retain the repository-relative path and initial bytes for every regular
   worktree snapshot.
2. Immediately before reporting, re-open each retained path through the same
   fail-closed traversal used for initial capture.
3. Compare the final bytes with the initial snapshot byte for byte.
4. Map missing, reparse, type, size, read, and byte drift at this final boundary
   to the fixed non-reflective reason `integrity: worktree-content-drift`.
5. Keep deterministic synchronization only in a disposable scanner copy used
   by the regression test. Production code receives no delay or test hook.

## Acceptance criteria

- A same-length atomic replacement after snapshot capture exits `2` with
  `integrity: worktree-content-drift`.
- The failure output contains neither the path nor the synthetic sentinel.
- Existing clean, staged-only, worktree-only, missing-worktree, reparse, and
  index-drift behavior remains unchanged.
- PowerShell 7 and Windows PowerShell 5.1 readiness, the PowerShell 7 full
  synthetic suite, repository scanning, encoding/whitespace checks, Gitleaks,
  and Semgrep pass.

## Non-goal

The boundary proves equality at the initial and final observations. It does not
claim filesystem compare-and-swap semantics after the final re-read.

## Verification record

On 2026-07-28, targeted Git-index and fallback regressions each exited `2`
with the fixed reason and without reflecting the path or sentinel. PowerShell
7 and Windows PowerShell 5.1 readiness and repository scans passed. The
PowerShell 7 full synthetic suite exited `0`; strict text hygiene, Gitleaks
directory/history scans, Semgrep `p/default`, and `git diff --check` also
passed. Pull request #11 head run `30341015703` passed all four hosted jobs;
the three PowerShell 7 jobs ran the full suite containing the content-drift
regression. Its immediate post-merge run `30341569740` had one failed Windows
PowerShell 7 job and is not counted as passing evidence. Later main runs
`30354646900` and `30496527183` passed all four jobs, including the three
PowerShell 7 full-suite jobs.
