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

Harden the CI Action and child-process environment boundaries. Success means
all acceptance criteria in `docs/security-boundary-contract.md` have measured
evidence, the pull request is merged, and the default branch is clean.

## Key files

- `.github/workflows/validate.yml`
- `scripts/validate-oss-readiness.ps1`
- `scripts/private-marker-process.ps1`
- `scripts/test-scan-private-markers.ps1`
- `docs/security-boundary-contract.md`

## Recent decisions

- Pin `actions/checkout` to the commit currently advertised by the official
  `actions/checkout` `v5` and `v5.1.0` refs.
- Rebuild child environments from an empty map; do not maintain a denylist of
  ambient variable names.
- Keep the scanner-entrypoint pass-through test-only and limited to explicit
  `GIT_*`, `PATH`, and the documented local-marker scanner input.
- Treat `.github/workflows/validate.yml` and its embedded canonical source in
  `scripts/validate-oss-readiness.ps1` as one reviewed change; readiness
  rejects any unpaired workflow mutation.

## Verification

- PS5, PS7, and Linux-equivalent readiness validation passes.
- PS5, PS7, and Linux-equivalent private-marker self-tests pass. The final
  fresh-process PS5 run completed in 199.1 seconds after the primary scanner
  fixture and later index/worktree fixture setup were moved behind the checked
  fail-fast contract. Raw transport probes retain their independent deadlines.
- PS5, PS7, and Linux-equivalent repository private-marker scans pass.
- Independent adversarial review found no remaining P1/P2/P3 issue after the
  YAML-shape, canonical-job, sentinel-fixture, and finite Windows launch-budget
  fixes. A final focused review also found no remaining issue in the complete
  canonical-workflow check or its cross-workflow pinning boundary.
- The immediate-spawn race fixture passed ten focused attempts after its
  loaded-host launch budget was widened from five to ten seconds; timeout,
  tree-stop, stream-drain, and sentinel assertions remain unchanged.
- Post-sync Semgrep (82 rules over 32 tracked files), Gitleaks, private-marker,
  YAML parse, BOM, and whitespace checks pass.
- PR #3 run `30139528418` passed the full Ubuntu job and Windows PS7
  readiness/self-test/scan, then its shared 25-minute Windows job canceled the
  still-running PS5.1 step. Run `30140406899` exposed a masked PS5.1 fixture
  prerequisite failure after the earlier PS7 suite. PS5.1 now has a fresh,
  independently bounded Windows job, and checked fixtures fail at their actual
  setup error. Fresh-job run `30141534665` then measured a checked fixture Git
  operation exceeding 20 seconds under runner load. Checked setup Git now has
  a finite 60-second budget and the independent PS5.1 job has a measured
  40-minute bound. Run `30142585670` then proved the three original primary
  fixture setup calls still accumulated a failed init before a later
  "not a git repository" exception; those calls now use the same fail-fast
  checked setup contract. The final PR-head result is authoritative.
- Past runs belong to Git history and pull-request checks.

## Known issues

- None beyond the work described above.

## Do not re-read

- No superseded document in this work unit.

## Next step

Merge PR #3 only after every final-head check passes. On the merged default
branch, reconcile with `origin/main` before selecting the next work unit.
