# agent-handoff-docs

[![Validate](https://github.com/h8nc4y/agent-handoff-docs/actions/workflows/validate.yml/badge.svg)](https://github.com/h8nc4y/agent-handoff-docs/actions/workflows/validate.yml)

An agent skill for Claude Code and Codex: a documentation framework for
multi-session, multi-agent development. It structures a repository's
documents so the next agent (or human) picks up work cold — a four-document
split (REQUIREMENTS / as-built ARCHITECTURE / REPORT / living HANDOFF),
START_HERE kickoff files, canonical-source discipline, task ledgers that
double as delegation specs, and verification checklists that become the
next agent's work orders. Includes bilingual (English/Japanese) templates.

## What It Solves

Development that spans agent sessions accumulates a familiar documentation
failure: dated handoff snapshots pile up, "current state" is maintained in
three places and trusted in none, and every new session burns time
re-discovering what is already known. The root cause is structural —
duplicated facts with no declared owner — so the fix is structural too:

- **Declared canonical scope**: every document opens by stating what it is
  the single source of truth for, and that on conflict the repository's
  observable state wins.
- **The four-document split**: intent (REQUIREMENTS, with an
  acceptance-criteria status table), current design (ARCHITECTURE,
  as-built), history (REPORT), and current position (one living HANDOFF).
  Because history has a home, everything else can be compressed without
  fear.
- **START_HERE**: one kickoff file with the same name in every repository,
  free of point-in-time information, so a single identical prompt resumes
  work anywhere (field-tested across ~30 repositories).
- **The living handoff discipline**: roughly 1,000 tokens, current state
  only, "traps before you touch anything" at the top, a do-not-re-read
  list that makes deleting stale docs safe.
- **A task ledger that doubles as a delegation spec**: rows carry
  file:line, the smallest fix, and confidence — measured result: 14
  parallel implementations delegated straight from ledger rows, zero
  no-ops.
- **Verification as work orders**: unverified items are phrased as a
  checklist the next agent burns down, and deployment tasks complete only
  on a full-target scan (which once caught 6 of 30 targets silently
  missed).

## Who It Is For

- Anyone running multi-session agent development on one repository or a
  fleet of them, with handoffs between sessions, agents, or agent
  products.
- Claude Code and Codex users who want both tools to read the same
  project documents without per-tool duplication.
- Teams retro-fitting documentation onto repositories where
  implementation ran ahead of docs (reverse-engineered requirements).

## Install

Clone the repository:

```bash
git clone https://github.com/h8nc4y/agent-handoff-docs.git
cd agent-handoff-docs
```

### Claude Code

Claude Code auto-invokes the skill when a task matches the `description`
frontmatter. Install for your user account on shells with POSIX syntax:

```bash
dest="${HOME}/.claude/skills/agent-handoff-docs"
if [ -e "$dest" ]; then
  echo "Install target already exists: $dest"
else
  mkdir -p "$dest"
  cp SKILL.md "$dest/SKILL.md"
  cp -R templates "$dest/templates"
fi
```

Install for your user account from PowerShell:

```powershell
$dest = Join-Path $HOME '.claude\skills\agent-handoff-docs'
if (Test-Path -LiteralPath $dest) {
  throw "Install target already exists: $dest"
}
New-Item -ItemType Directory -Path $dest | Out-Null
Copy-Item -LiteralPath .\SKILL.md -Destination (Join-Path $dest 'SKILL.md')
Copy-Item -LiteralPath .\templates -Destination (Join-Path $dest 'templates') -Recurse
```

Notes:

- If you set `CLAUDE_CONFIG_DIR`, replace `~/.claude` with that directory.
- To scope the skill to a single project instead, copy the same files to
  `.claude/skills/agent-handoff-docs/` inside that project's repository.
- Copying `templates/` is optional but recommended: the agent can then
  instantiate the four documents without fetching anything.

The existence guard is intentional: do not overwrite an already-installed
skill without reviewing the local copy first.

### Codex (agent skills)

Manual Codex-style skill install on shells with POSIX syntax:

```bash
dest="${HOME}/.agents/skills/agent-handoff-docs"
if [ -e "$dest" ]; then
  echo "Install target already exists: $dest"
else
  mkdir -p "$dest"
  cp SKILL.md "$dest/SKILL.md"
  cp -R templates "$dest/templates"
fi
```

Manual Codex-style skill install from PowerShell:

```powershell
$dest = Join-Path $HOME '.agents\skills\agent-handoff-docs'
if (Test-Path -LiteralPath $dest) {
  throw "Install target already exists: $dest"
}
New-Item -ItemType Directory -Path $dest | Out-Null
Copy-Item -LiteralPath .\SKILL.md -Destination (Join-Path $dest 'SKILL.md')
Copy-Item -LiteralPath .\templates -Destination (Join-Path $dest 'templates') -Recurse
```

To scope the skill to a single project instead, copy the same files to
`.agents/skills/agent-handoff-docs/` inside that repository — Codex scans
`.agents/skills` from the working directory up to the repository root (per
the official skills documentation).

If your agent reads skills from a different directory, check its
documentation and copy `SKILL.md` (plus `templates/` if you want them
offline) into the matching `skills/agent-handoff-docs/` folder.

## Repository Layout

```
SKILL.md                 The skill (English, canonical)
docs/SKILL.ja.md         Japanese full version
templates/en/            English templates (placeholders only)
  START_HERE.md          Kickoff file
  REQUIREMENTS.md        Requirements with acceptance-criteria table
  HANDOFF.md             Living handoff
  TASKS.md               Task ledger / delegation specs
templates/ja/            Japanese templates (same four files)
examples/                Synthetic worked examples
scripts/                 Local validation (readiness, private-marker scan)
```

Every template reserves its first section for the canonical-scope
declaration — the one habit the whole framework hangs on.

## Manual Use

Reach for the skill when you see one of these symptoms:

- Handoff or requirements documents keep going stale, or dated handoff
  snapshots are piling up.
- "Current state" appears in several documents and they disagree.
- A new agent session needs onboarding onto an existing repository, and
  you want one kickoff prompt that works across all your repositories.
- Implementation finished but requirements were never written down
  (reverse-engineering them still pays off — the acceptance table becomes
  the canonical remaining-work list).
- A docs restructure is planned and you need a target shape plus a safe
  migration order (including checking for doc-contract tests first).

Then follow [SKILL.md](SKILL.md): declare each document's canonical scope,
split intent / design / history / current state, deploy START_HERE, keep
the handoff living and small, write ledger rows as delegation specs, and
verify deployment-style claims with full-target scans.

## Templates

Eight files, four document types × two languages, under
[templates/en](templates/en) and [templates/ja](templates/ja):

| Template | Suggested location | Role |
| --- | --- | --- |
| `START_HERE.md` | repository root | Standard kickoff file: reading order, verification commands, hard gates — no point-in-time information |
| `REQUIREMENTS.md` | `docs/` | FR / NFR / non-goals / acceptance-criteria table with evidence-gated statuses, plus an unverified checklist |
| `HANDOFF.md` | repository root | Living handoff: traps first, current position, do-not-re-read list, next step |
| `TASKS.md` | repository root | Task ledger: delegation-ready rows, latest-run-only verification log, one-line-per-period history |

The locations are suggestions matching the templates' cross-references —
adjust both together if your repository differs.

The templates contain placeholders only (`<project>`, `<date>`, `<path>`)
— copy one into a repository, fill the placeholders, and delete nothing
but placeholders. ARCHITECTURE and REPORT are deliberately not templated:
their shape is repository-specific, and their canonical-scope declarations
are shown in the examples instead.

## Synthetic Examples

- [Canonical-scope declarations](examples/canonical-scope-declarations.md)
  — worked opening declarations for all six document types, including the
  conventions-file (thin-pointer) arrangement.
- [Do-not-re-read entries](examples/do-not-reread-entries.md) — how to
  record deletions and supersessions so the next agent skips them safely.
- [Full-scan verification commands](examples/full-scan-verification-commands.md)
  — command patterns for full-target existence scans, dangling-reference
  sweeps (including backtick-quoted paths), and default-branch fact
  checks.

The examples use placeholders only. Do not replace them with secrets, real
repository paths you cannot publish, or customer data in public issues.

## Related Skills

- [multi-agent-delegation](https://github.com/h8nc4y/multi-agent-delegation)
  — the delegation side of the same operation: how to write delegation
  prompts and verify subagent output. Its ledger-as-delegation-spec
  pattern and this skill's task-ledger chapter describe the same artifact
  from two directions.

## 日本語概要 (Japanese Overview)

マルチセッション・マルチエージェント開発のための引き継ぎ資料
フレームワークです。

- **正本責務の宣言**: すべての資料の冒頭に「この資料は何の単一の正本か・
  隣の事実はどの資料の持ち物か・実状態と食い違ったら実状態が正」を
  書く。陳腐化の根本原因（重複）を構造で断つ。
- **4分割型**: REQUIREMENTS（要件の正本。FR/NFR/受け入れ基準表つき）／
  ARCHITECTURE（as-built の現行仕様）／REPORT（経緯・検討過程・実測
  記録。古い記述はここへ退避するので他資料を安心して圧縮できる）／
  HANDOFF（living handoff = 現在地と次の一手のみ、目安1,000トークン
  以下）。
- **START_HERE**: 全リポジトリ同名のキックオフ1枚（読み順・検証
  コマンド・ゲート。時点情報は書かない）。約30リポジトリへの標準配備で
  「どのリポジトリでも同一プロンプトで引き継ぎ可能」を実測済み。
- **タスク台帳**: file:line＋最小修正案＋confidence の行がそのまま
  委譲 spec になる（14体並列委譲・空振りゼロの実測あり）。検証ログは
  直近のみ保持し、過去は git 履歴参照と台帳ヘッダに明記。
- **検証**: 未検証チェックリストがそのまま次エージェントの作業指示に
  なる。配備系タスクの完了条件は「配備した」の宣言ではなく全対象横断の
  存在スキャン実測（30対象中6件の配備漏れを検出した実測あり）。

日本語の完全版は [docs/SKILL.ja.md](docs/SKILL.ja.md)、日本語の雛形は
[templates/ja](templates/ja) にあります。インストールは上記の手順
どおり、`SKILL.md`（と必要なら `templates/`）を Claude Code なら
`~/.claude/skills/agent-handoff-docs/` へ、Codex なら
`~/.agents/skills/agent-handoff-docs/` へコピーしてください。

## Safety Notes

- Never store secrets, tokens, credential-bearing logs, or real user data
  in handoff files — they are read by every future session.
- Treat deletion of documents as safe only after their durable content is
  folded into the canonical documents and the deletion is recorded in the
  do-not-re-read list (git history preserves the files themselves).
- Never paste tokens, credentials, private repository names, or internal
  absolute paths into public issues or pull requests.

## Limitations

- The framework is a written discipline, not a tool: nothing enforces the
  canonical-scope declarations automatically. Doc-contract tests (tests
  that pin document phrases or paths) can machine-check parts of it, but
  designing those is repository-specific and out of scope here.
- The measured results quoted (fleet size, delegation counts, scan
  catches) come from one operation's repositories; your ratios will vary.
- The templates assume a git repository and a PR-based workflow for the
  evidence and history conventions.

## Non-Goals

- No SDLC process classification or stage-gate framework — this skill
  structures documents, not the process around them.
- No UI specification or design-document formats.
- No tool-specific configuration (agent config files, CI setup,
  permissions) — the framework stays agnostic to which agent product
  reads the documents.
- No automation that generates or rewrites the documents for you.

## Validation

Run the full local validation from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-oss-readiness.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-scan-private-markers.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1
```

If `pwsh` is available, the same checks can be run with:

```powershell
pwsh -NoProfile -File .\scripts\validate-oss-readiness.ps1
pwsh -NoProfile -File .\scripts\test-scan-private-markers.ps1
pwsh -NoProfile -File .\scripts\scan-private-markers.ps1
```

On macOS, Linux, or any POSIX shell with PowerShell 7 (`pwsh`) installed:

```bash
pwsh -NoProfile -File ./scripts/validate-oss-readiness.ps1
pwsh -NoProfile -File ./scripts/test-scan-private-markers.ps1
pwsh -NoProfile -File ./scripts/scan-private-markers.ps1
```

Also run Git whitespace checks on your working changes before publishing:

```bash
git diff --check
```

The GitHub Actions workflow runs the same validation, scan self-test,
private-marker scan, and a committed-tree whitespace check on pull
requests and pushes to `main`.

## Contributing

Contributions are welcome when they make the framework clearer, safer, or
easier to verify. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a
pull request.

Keep all examples synthetic. Do not include tokens, credentials, private
repository names, internal absolute paths, or customer data.

For local-only private markers, create an untracked
`.private-markers.local` file with one literal marker per line, or set
`AGENT_HANDOFF_DOCS_PRIVATE_MARKERS` with newline-separated markers. The
scanner reads these values but does not print the matched marker.

## Security

If you find unsafe guidance or accidental private-data exposure, follow
[SECURITY.md](SECURITY.md) and use private reporting for sensitive
details.

## License

MIT. See [LICENSE](LICENSE).
