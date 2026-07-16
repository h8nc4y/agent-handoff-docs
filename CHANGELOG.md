# Changelog

All notable changes to this project are documented in this file.

The format loosely follows Keep a Changelog conventions.

## Unreleased

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
