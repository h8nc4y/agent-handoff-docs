# Changelog

All notable changes to this project are documented in this file.

The format loosely follows Keep a Changelog conventions.

## Unreleased

### Fixed

- Preserve git's forward-slash tracked paths when resolving files so
  nested files remain in the private-marker scan on Windows and POSIX.
  The previous Windows-only backslash conversion made tracked nested files
  disappear from Linux/macOS scans.
- Include Unix-hidden dotfiles in both git-tracked and working-tree scan
  modes while retaining cross-platform working-tree exclusions for
  `.git`, `node_modules`, and `.cache`.

### Changed

- Add synthetic git-tracked nested-file and dotfile regressions plus
  working-tree path and exclusion regressions, and run full repository
  validation on both Windows and Ubuntu. This makes the documented
  PowerShell 7 POSIX path executable in CI rather than an unmeasured
  portability claim.
- Run synthetic Git fixtures in a hermetic environment and verify that
  ambient repository redirects, hooks, filters, templates, attributes,
  traces, and user configuration cannot affect the test or escape its
  temp tree. The harness sanitizes child-only environment clones, keeps
  the parent environment unchanged, runs the current PowerShell engine,
  and bounds every scanner/Git child with process-tree cleanup.
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
