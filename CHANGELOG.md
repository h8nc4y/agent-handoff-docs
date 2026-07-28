# Changelog

All notable changes to this project are documented in this file.

The format loosely follows Keep a Changelog conventions.

## Unreleased

### Added

- Require the Japanese complete skill to acknowledge the normalized SHA-256
  of canonical `SKILL.md`. Readiness regressions pin BOM and LF/CRLF
  equivalence and reject stale, uppercase, duplicated, displaced, or
  differently normalized markers. Byte-level regressions ignore exactly one
  physical UTF-8 BOM, retain any second BOM as content, and reject malformed
  UTF-8. The digest records review of a canonical revision; bilingual review
  still owns semantic translation correctness.
- Validate the exact reviewed title and ordered level-two section schema of
  every bundled English and Japanese template. Mutation regressions reject
  missing, duplicated, reordered, demoted, fenced-only, unexpected, and
  unclosed-fence forms, including indented/empty ATX headings, Setext
  headings, raw HTML H1/H2 tags, and malformed backtick fences, while
  retaining CRLF compatibility and subordinate headings.
- Apply the same reviewed title and ordered level-two section contract to all
  three bundled synthetic example documents. This turns truncation, accidental
  replacement, and unreviewed peer-section drift into readiness failures
  instead of accepting any file that merely retains the expected path.

### Fixed

- Revalidate every retained regular-worktree snapshot immediately before the
  private-marker scanner reports. The final fail-closed pass reuses the safe
  path traversal and compares bytes exactly, so a same-length atomic
  replacement cannot turn a stale clean snapshot into a successful report.
  Missing, reparse, type, size, read, and content drift at that boundary use
  the fixed non-reflective `integrity: worktree-content-drift` reason.
- Canonicalize the synthetic self-test temp root through every POSIX ancestor
  link before creating Git fixtures. This keeps the scanner's strict root
  identity check intact while aligning macOS temporary paths such as a logical
  `/var` alias with Git's physical path. Add an ancestor-symlink regression so
  future fixture changes cannot reintroduce `git-root-mismatch` failures.
- Pin `actions/checkout` v5.1.0 to its verified full commit SHA and make OSS
  readiness reject every active external workflow `uses:` entry that is not a
  canonical owner/repository reference pinned to a lowercase 40-character
  commit SHA. Add positive and negative policy regressions so one valid pin
  cannot mask a mutable tag, branch, expression, abbreviated SHA, Docker
  reference, explicit/escaped mapping, or YAML anchor/alias (including
  flow-style folded forms).
- Rebuild bounded child environments from an empty map instead of subtracting
  known names from `ProcessStartInfo`'s ambient clone. Retain only trusted
  OS/runtime paths, isolated home/temp/config paths, fixed locale values, and
  explicit Git controls; the test-only scanner entrypoint bridge permits only
  explicit Git/test inputs. Add Windows/POSIX positive and negative fixtures
  for required runtime values and forbidden credential, loader, agent, cloud,
  custom, and hostile PATH values.
- Run Windows PowerShell 5.1 validation in its own fresh Windows job instead
  of after the full PowerShell 7 suite. The hosted PowerShell 5.1 job performs
  readiness by explicitly launching `powershell.exe` from the hosted `pwsh`
  runner shell, then checks whitespace, all within 25 minutes. The full
  self-test and repository scan remain measured local PS5 gates and run in
  hosted CI under PowerShell 7 on Windows and Ubuntu. Checked Git fixtures now
  fail at the first broken setup
  prerequisite instead of masking it with a later missing-index exception,
  or a later "not a git repository" exception. All primary and secondary
  scanner/index/worktree fixture setup uses a finite 60-second budget on the
  loaded PowerShell 5.1 runner; raw transport probes retain their independent
  deadlines.
  Scope readiness assertions and regressions to that exact job block so the
  main matrix cannot mask a missing PS5.1 step or timeout. Require the complete
  built-in validation workflow to match its reviewed canonical source so an
  extra YAML field, job, step, or scalar wrapper cannot spoof the scoped
  checks.
- Preserve git's forward-slash tracked paths when resolving files so
  nested files remain in the private-marker scan on Windows and POSIX.
  The previous Windows-only backslash conversion made tracked nested files
  disappear from Linux/macOS scans.
- Include Unix-hidden dotfiles in both git-tracked and working-tree scan
  modes while retaining cross-platform working-tree exclusions for
  `.git`, `node_modules`, and `.cache`.

### Changed

- Run the complete PowerShell 7 validation suite on the standard `macos-15`
  runner as well as Windows and Ubuntu. Readiness now requires that runner in
  the exact canonical workflow, and a targeted mutation regression rejects its
  removal. A passing macOS run measures the self-test's forced native `libc`
  `setsid(2)` gate without adding a dependency, cache, artifact, or release
  step. The evidence marker now requires a zero target exit, a start
  confirmation written by the grandchild payload itself, an observed
  descendant-held pipe after parent exit, successful cleanup/drain, and a
  suppressed delayed sentinel; synthetic regressions reject nonzero-command,
  unconfirmed-start, and non-pipe-leak results.
- Add synthetic git-tracked nested-file and dotfile regressions plus
  working-tree path and exclusion regressions, and run full repository
  validation on both Windows and Ubuntu. This makes the documented
  PowerShell 7 POSIX path executable in CI rather than an unmeasured
  portability claim.
- Run synthetic Git fixtures in a hermetic environment and verify that
  ambient repository redirects, hooks, filters, templates, attributes,
  traces, and user configuration cannot affect the test or escape its
  temp tree. The harness builds child-only environments from an empty
  allowlist, keeps the parent environment unchanged, runs the current
  PowerShell engine, and bounds every scanner/Git child with process-tree
  cleanup.
- Scan the exact index blob and the current regular worktree snapshot,
  read intent-to-add directly from extended index flags, and recheck raw
  stage/debug metadata after content matching. Fail closed on conflicts,
  gitlinks, tracked local marker configuration, malformed/corrupt indexes,
  reparse ancestors, drift, oversized inputs, and repository-root
  mismatches.
- Bound file-system entries, scan targets, lines, regex matches, findings,
  bytes, child output, processes, and runtime. Stream directory and line
  enumeration, cap the redacted report, exclude leaf `.git` metadata, and
  escape control, bidi/format, and logical line-separator characters in
  displayed paths.
- Disable Git replace objects, lazy object fetching, and transport
  protocols for scanner children. Add synthetic regressions for hostile
  ambient indexes, staged/worktree/missing states, replace refs, symlink
  blobs, process output caps, and descendant cleanup.
- Assign the Windows gate wrapper to a kill-on-close Job before releasing
  scanner work, and isolate POSIX children in a process group using either
  the system `setsid` executable or a gated `libc` fallback. Use
  errno-aware `kill(2)` cleanup so only success or an already-absent group
  counts as stopped. Derive the platform from the runtime instead of
  caller-controlled environment, verify direct Job membership and
  parent-first cleanup, and run ten consecutive immediate-descendant
  timeout races.
- Preserve binary stdin, stdout, stderr, EOF, and exit codes across the
  first Windows Job gate with fixed-size streaming buffers and a bounded
  final drain. Invoke the trusted gate through `-File` so Windows
  PowerShell 5.1 cannot add CLIXML framing, and temporarily select then
  restore BOM-less UTF-8 input during process startup so raw Git batch
  requests cannot gain a preamble. Keep native Git and binary echo
  regressions at the top-level helper boundary because scanner fixtures
  already inside the owned Job exercise only its reuse path.
- Read index blobs through one bounded `git cat-file --batch` stream and
  reject byte-level `git ls-files --stage` or `--debug` changes before
  reporting success. Treat `.env` variants, PEM/certificate/key files,
  and extensionless text files as scan candidates.
- Run the Windows matrix checks under Windows PowerShell 5.1 as well as
  PowerShell 7.

## 0.1.0 - 2026-07-16

### Added

- Initial agent-handoff-docs skill (`SKILL.md`): declared canonical scope
  as the core principle, the four-document split (REQUIREMENTS with an
  acceptance-criteria status table, as-built ARCHITECTURE, REPORT for
  history, one living HANDOFF), the START_HERE standard kickoff file, the
  living-handoff discipline (size budget, traps-first, do-not-re-read
  list), the task ledger as delegation spec, anti-patterns, full-scan
  verification rules, and a migration order for restructuring existing
  documents.
- Japanese full version of the skill (`docs/SKILL.ja.md`).
- Bilingual templates (English and Japanese, placeholders only):
  `START_HERE.md`, `REQUIREMENTS.md`, `HANDOFF.md`, `TASKS.md`, each
  reserving its first section for the canonical-scope declaration.
- Synthetic examples: canonical-scope declarations for all six document
  types, do-not-re-read entry patterns, and full-scan verification
  command patterns.
- Private-marker scan for common secret prefixes, private-looking
  absolute paths, and non-allowlisted GitHub repository URLs, with a
  self-test (including URL-allowlist cases) and local marker support
  through `.private-markers.local` or the
  `AGENT_HANDOFF_DOCS_PRIVATE_MARKERS` environment variable.
- OSS readiness validation script covering required public project
  files, skill frontmatter, and the canonical-scope headings in every
  bundled template.
- GitHub Actions workflow for validation, private-marker scanning, and
  committed-tree whitespace checks.
- Issue and pull request templates with sanitized-report guidance.
- Contributor, security, code of conduct, editor, and Git attribute
  documentation.
