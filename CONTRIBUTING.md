# Contributing

Thanks for improving this skill. This repository is intentionally small:
changes should make the documentation framework clearer, safer, or easier
to verify.

## Before You Start

- Read [SKILL.md](SKILL.md), the templates under [templates](templates),
  and the examples under [examples](examples).
- `SKILL.md` (English) is canonical. When you change it, update
  [docs/SKILL.ja.md](docs/SKILL.ja.md) in the same pull request so the two
  stay in sync.
- The templates come in language pairs: a change to a file under
  `templates/en/` must be mirrored in `templates/ja/` (and vice versa) in
  the same pull request.
- Templates contain placeholders only (`<project>`, `<date>`, `<path>`).
  Never fill them with real project content, private repository names, or
  internal absolute paths.
- Do not paste tokens, credentials, private keys, OAuth codes, raw logs,
  customer data, private repository names, or internal absolute paths into
  issues, pull requests, commits, or examples. No token or secret value
  ever belongs in this repository.
- Put personal or organization-specific scan markers in an untracked
  `.private-markers.local` file, not in repository source.

## Grounding Rules

This skill's value is that every rule traces to observed behavior. Keep it
that way:

- Claims about how documentation decays or how agents consume documents
  should be grounded in something observable (a measured incident, a
  reproducible failure). Mark speculation and design-derived-but-unvalidated
  guidance explicitly as unverified.
- Do not remove existing honesty markers ("field-tested", "measured")
  without evidence that changes their status, and do not inflate measured
  numbers (fleet sizes, catch counts) beyond what was observed.

## Development Workflow

1. Create a focused branch.
2. Make the smallest coherent change.
3. Update templates, examples, or README text when user-facing guidance
   changes — keeping the EN/JA pairs in sync.
4. Add or adjust validation when a framework rule should be
   machine-checkable (the canonical-scope heading checks are the existing
   example).
5. Run the validation commands before opening a pull request.

## Validation

From the repository root, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-oss-readiness.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-scan-private-markers.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1
git diff --check
```

If `pwsh` is available, it is also acceptable for the PowerShell scripts:

```powershell
pwsh -NoProfile -File .\scripts\validate-oss-readiness.ps1
pwsh -NoProfile -File .\scripts\test-scan-private-markers.ps1
pwsh -NoProfile -File .\scripts\scan-private-markers.ps1
```

On macOS, Linux, or any POSIX shell with PowerShell 7 (`pwsh`) installed,
use forward slashes:

```bash
pwsh -NoProfile -File ./scripts/validate-oss-readiness.ps1
pwsh -NoProfile -File ./scripts/test-scan-private-markers.ps1
pwsh -NoProfile -File ./scripts/scan-private-markers.ps1
```

## Pull Request Expectations

- Explain the problem and the chosen fix.
- Include validation results.
- Call out any remaining unknowns.
- If the change alters a discipline rule (what a document may own, when to
  compress, when deletion is safe), describe the failure mode it prevents
  concretely.

## Maintainer Notes

Prefer wording and validation that prevent the two real hazards of this
framework: losing the only copy of a fact during compression or deletion,
and "done" claims that were never measured. Avoid adding broad dependencies
or network-backed checks unless they are clearly necessary for public
safety.
