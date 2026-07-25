# Security Policy

This repository documents a project-documentation framework for agent
development. It should never contain secrets, but its guidance instructs
agents to compress, delete, and restructure project documents — so unsafe
guidance that could destroy the only copy of information, or that could
lead agents to record secrets in long-lived handoff files, is treated as a
security problem too.

## Supported Versions

The `main` branch is the supported version. Tagged releases receive fixes
through new tags on `main`.

## Reporting A Vulnerability

Use GitHub private vulnerability reporting for:

- A real secret, credential, or private identifier accidentally committed
  to this repository.
- Guidance that could cause agents to lose the only copy of project
  information (for example a deletion step without the fold-first and
  do-not-re-read safeguards), or to write credentials or personal data
  into handoff documents.
- A validation gap that allows unsafe public examples.

Do not open a public issue containing tokens, credentials, private keys,
OAuth material, customer data, raw secret-bearing logs, or private
repository names and internal paths.

## Public Issue Safety

Public issues may include:

- Symptom class, such as "template heading check false pass" or
  "migration order loses content".
- Sanitized document excerpts using placeholder project, path, and
  repository names.
- Scan or validation output with private values redacted.

Public issues must not include:

- Secret values or secret-display command output.
- Private repository names, internal absolute paths, hostnames, or
  customer data.
- Raw agent transcripts or handoff documents that contain any of the
  above.

## Scanner Coverage

The private-marker scanner (`scripts/scan-private-markers.ps1`) is a
best-effort safety net, not a guarantee. For git-tracked text paths, it
scans both the exact index blob and a distinct current regular worktree
snapshot. It reads intent-to-add from the index extended flags and
rechecks raw stage/debug metadata immediately before reporting. It does
not follow worktree links or fetch missing Git objects; ambiguous index,
root, link, encoding, process, drift, count, or size states fail closed.
File, entry, line, regex-match, finding, byte, process, output, and time
budgets bound hostile input. The initial Windows Job gate streams native
stdin, stdout, and stderr through fixed-size buffers with a bounded final
drain, preserving binary Git output without PowerShell or CLIXML framing.
Windows PowerShell 5.1 process startup uses a temporary BOM-less UTF-8
input encoding and restores the caller's encoding before returning.
Bounded scanner and Git children do not inherit the parent process
environment. Their environment starts empty and receives only OS/runtime
values derived from trusted APIs, isolation-root paths, fixed command
directories, locale values, and explicit local-only Git controls. The
scanner-entrypoint test bridge permits only explicit `GIT_*`, `PATH`, and
documented local-marker inputs; representative credential, loader, agent,
cloud, and unrelated variables are covered by negative fixtures on Windows
and POSIX.
The scanner checks a curated set of secret prefixes (GitHub,
OpenAI, AWS, GCP, Slack, Stripe, PEM key blocks, and similar),
private-looking absolute Windows paths, non-allowlisted GitHub repository
URLs, and configured local markers, and it redacts any matched value.
`.private-markers.local` must remain untracked. The scanner does not
detect every possible secret format and is no substitute for keeping real
credentials out of the repository in the first place. Treat a passing
scan as "no known marker found," not "definitely safe."

The validation workflow pins external GitHub Actions to full commit SHAs.
`scripts/validate-oss-readiness.ps1` scans every active external `uses:`
entry in every workflow file and rejects tags, branches, abbreviated SHAs,
expressions, Docker references, and non-canonical/unparseable forms. The
dependency-free PowerShell 5.1 policy also rejects YAML explicit keys,
escaped/folded double-quoted scalars, and anchors/aliases because those forms
can decode or alias into a hidden semantic `uses` key. The
complete boundary and acceptance criteria are documented in
[`docs/security-boundary-contract.md`](docs/security-boundary-contract.md).

## Response Expectations

Maintainers should acknowledge actionable security reports when available,
remove or redact unsafe public material, and prefer guidance that reduces
data-exposure and information-loss risk. If real exposure is possible,
rotate the affected secret outside this public repository and document
only the remediation status.
