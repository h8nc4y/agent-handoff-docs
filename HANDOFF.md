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

Close the stale hosted-evidence status for three merged hardening units. This
work unit succeeds when the security contract and paired English/Japanese
evidence records cite only measured runs, preserve failed-run caveats, and pass
the documentation review and repository gates.

## Current position

- The primary checkout was clean and matched remote `main` when this isolated
  documentation worktree was created.
- Pull request #11 and #12 head runs passed all four hosted jobs. Their
  immediate post-merge runs each had one failed job and are not cited as green
  evidence.
- Pull request #13 head and post-main runs, and the audited main run, passed all
  four hosted jobs with all three hardening units integrated.
- The security contract and paired worktree/Windows evidence records now
  distinguish the passing evidence from the two failed post-merge runs.
- Runtime scripts, tests, workflows, canonical `SKILL.md`, and its Japanese
  translation are unchanged.
- Readiness, the scanner self-test, and the repository scan passed under
  PowerShell 7 and Windows PowerShell 5.1 for this documentation-only diff.
- Gitleaks found no leaks in the directory or 19-commit history. Semgrep
  `p/default` exited `0` on the exact six changed documents.

## Verified evidence used by this work unit

- Pull request #11 head run `30341015703` and pull request #12 head run
  `30350038650` passed Windows PowerShell 7, Windows PowerShell 5.1, Ubuntu,
  and macOS.
- Pull request #13 head run `30354157531` and post-main run `30354646900`
  passed the same four hosted jobs.
- Audited main run `30496527183` passed the same four jobs.
- Runs `30341569740` and `30350539529` each had one failed job and remain
  excluded from passing evidence.

## Key files

- `.github/workflows/validate.yml` — canonical validation workflow.
- `scripts/validate-oss-readiness.ps1` — readiness and checkout policy.
- `docs/security-boundary-contract.md` — owned security invariants and tests.
- `CHANGELOG.md` and merged pull requests — durable history.

## Recent decisions

- Record a passing pull-request head and a later passing main run for the
  earlier hardening units. Do not relabel either failed immediate post-merge
  run as green.

## Known issues

- `actionlint` remains unconfirmed and is not retried for this work unit.

## Do not re-read

- Pull requests #5–#9 review narratives — durable results are in
  `CHANGELOG.md` and merged history; executable contracts own current behavior.

## Next step

1. Stage only the six documentation files, commit through the global security
   hook, and open a pull request. Merge only after all four hosted jobs pass.
2. After merge, recheck observable main and CI state, then select the next task
   from current issues, pull requests, or reproducible failures.
