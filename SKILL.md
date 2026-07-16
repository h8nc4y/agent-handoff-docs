---
name: agent-handoff-docs
description: >-
  Documentation framework for multi-session, multi-agent development — how to
  structure project docs so the next agent (or human) picks up work cold. A
  four-document split with declared canonical scope: REQUIREMENTS (with an
  acceptance-criteria status table), as-built ARCHITECTURE, REPORT (history
  and measurements), and one living HANDOFF; plus a START_HERE kickoff file
  and a task ledger that doubles as a delegation spec. Use on symptoms like
  "handoff docs keep going stale", "stale docs", "documentation
  restructuring", "living handoff", "onboarding a new agent onto an existing
  repository", "which document is the source of truth", dated handoff
  snapshots piling up, or 引き継ぎ資料の整理・要件定義書の逆起こし. Includes
  bilingual (EN/JA) templates.
---

# Agent Handoff Docs

A documentation framework for development that spans multiple agent
sessions, multiple agent products, or agents working alongside humans. The
next reader arrives with zero context. What they need is not more
documentation — it is documentation whose ownership is unambiguous: every
file states what it is the source of truth for, exactly one file states
where work stands right now, and everything else can be compressed or
deleted without fear of losing the only copy of a fact.

The file names used below (REQUIREMENTS, ARCHITECTURE, REPORT, HANDOFF,
START_HERE, TASKS) are conventions, not requirements. What matters is that
the names are consistent across every repository you maintain, and that each
document declares its scope at the top.

## When To Use

- Work on a repository spans multiple sessions or is handed between agents
  (or between agents and humans), and every new session pays a re-discovery
  cost before producing anything.
- Handoff documents keep going stale: dated snapshots pile up, "current
  state" appears in several files, and no reader trusts any of them.
- You are onboarding a new agent onto an existing repository and want one
  kickoff prompt that works identically across every repository you own.
- Implementation ran ahead of documentation and you need to reconstruct
  requirements after the fact (reverse-engineered requirements).
- You are about to restructure a pile of legacy documents and need a target
  shape plus a safe migration order.

## The Core Principle: Declared Canonical Scope

Documentation staleness is not caused by carelessness; it is caused by
duplication. When the same fact lives in three files, updating two of them
is a normal, conscientious day's work — and the third file is now a trap for
the next reader. The fix is structural, not motivational:

1. **Every document opens with a canonical-scope declaration**: what this
   document is the single source of truth for, and which neighboring facts
   belong to which other documents. The bundled templates all reserve this
   block as their first section.
2. **One fact, one owner.** Any other document that needs the fact links to
   the owner instead of restating it.
3. **Reality outranks documents.** Write into the declaration that on
   conflict, the repository's observable state (git log, PR state, running
   code, CI results) is the primary source, and the document is the one to
   fix.
4. **The canonical text must live in a file the agent actually reads.**
   Field example: contribution conventions kept in a gitignored,
   agent-specific config file were invisible to a second agent product
   working in the same repository. Promoting the conventions to the
   committed conventions file that both agents load (for example
   `AGENTS.md`), and reducing the agent-specific file to a thin pointer,
   fixed the drift at the root.

Everything else in this skill — the four-document split, the kickoff file,
the living handoff, the ledger — is this principle applied to the four kinds
of facts a project accumulates: intent, design, history, and current state.

## The Four-Document Split

| Document | Single source of truth for | Update when |
| --- | --- | --- |
| REQUIREMENTS | What must be true: functional and non-functional requirements, non-goals, acceptance criteria with status | Scope decisions; an acceptance criterion changes status (with evidence) |
| ARCHITECTURE | The current as-built design: components, data flow, invariants, key files | A merged change alters structure or invariants |
| REPORT | History: investigations, dead ends, measured results, decision context | A work unit produced findings worth keeping; other documents shed history |
| HANDOFF | Where work stands now and the immediate next step | Continuously; compressed at every work-unit boundary |

### REQUIREMENTS — the intent document

Functional requirements, non-functional requirements, explicit non-goals,
and an acceptance-criteria table where every criterion carries a
verification method and a status (`done` with evidence, or `not yet`).

Two field-tested points:

- **Reverse-engineering requirements after implementation is still worth
  it.** Writing the requirements document when the code already exists feels
  backwards, but the acceptance table it produces becomes the canonical
  remaining-work list — the statuses tell the next agent exactly what is
  proven and what is not, independent of any session's memory.
- **Dates and numbers must be re-derived from the artifact, not recalled.**
  In one measured case, a reverse-engineered requirements document stated a
  phase-completion date one day off from what `git log` actually showed. An
  adversarial review caught it; the rule since is that every date or number
  written into a canonical document is read back from the repository, not
  from the author's memory.

### ARCHITECTURE — the as-built document

The design as it currently exists — not the aspirational design, and not the
path taken to get here (that is REPORT's job). Components, data flow,
invariants, storage shapes, and the map of key files.

Describe semantics and invariants; do not mirror shapes the code already
owns. A specification that copies type definitions drifts the first week.
Declare instead: "field shapes are owned by `<types file>`; this document
explains what the fields mean and which combinations are legal."

### REPORT — the history document

Investigation notes, dead ends, benchmark and measurement records, and the
context behind decisions. Append-mostly, ordered by time.

REPORT's existence is what makes the rest of the framework safe: any other
document can be compressed fearlessly, because history is moved here rather
than deleted. When HANDOFF sheds an old hypothesis or REQUIREMENTS drops an
obsolete consideration, the durable part lands in REPORT first. A reader who
asks "why is it built this way?" gets an answer without that answer
cluttering the documents agents read every session.

### HANDOFF — the living now-document

Current position and the immediate next step, nothing else. Its discipline
is strict enough to get its own section below.

### Scaling the split

In a small repository, REPORT can be replaced by git history plus PR bodies,
and ARCHITECTURE can be a section inside README — collapse files, but keep
the declarations ("history lives in PR bodies; this README section is the
as-built truth"). In a large repository, each document can split by topic
under the same scope rules. The declared-scope principle is the part that
does not scale away.

## START_HERE: The Standard Kickoff File

One file, with the same name, in every repository you maintain. A brand-new
agent reads it first and knows where the canonical documents live and how to
begin. Contents, in order:

1. **What this repository is** — one or two lines, stable across months.
2. **Reading order** — a numbered list over the canonical documents
   (typically README → REQUIREMENTS → ARCHITECTURE → HANDOFF → TASKS).
3. **Verification commands** — the exact commands that must pass before any
   PR (build, tests, lint, scanners), or a pointer to the single document
   section that owns them.
4. **Hard gates** — boundaries never to cross without approval (production
   deploys, external posting, paid APIs, publishing).
5. **A next-step pointer** — a reference into HANDOFF's next-step section,
   never the next step itself.

The one rule that keeps START_HERE alive: **no point-in-time information.**
The file describes where truth lives, not what is currently true. Written
this way it survives months without edits, which is exactly what an
entry-point file must do.

The payoff is fleet-wide: with the file standardized across ~30
repositories, a single identical kickoff prompt ("read START_HERE.md, then
continue from the handoff") resumes work in any of them — no per-repository
prompt engineering (field-tested).

Naming: `START_HERE.md` is the generic choice. Where several agent products
with conflicting conventions share a repository, an agent-qualified name
(prefixing the file with the agent's name) is a workable variant — but keep
exactly one entrance file per repository per audience.

Rolling the file out across a fleet is a deployment task; its completion
criterion is a full-fleet existence scan, not the rollout loop's own
bookkeeping (see Verification).

## The Living Handoff Discipline

One HANDOFF per repository, holding only the present. The discipline:

- **Size budget: roughly 1,000 tokens or less.** Past that, the next
  agent's reading cost and the staleness surface both grow faster than the
  value.
- **Keep only**: current goal and success metric; key files; recent
  decisions (one line each); commands already run; known issues; a
  do-not-re-read list; the next step.
- **Put "traps before you touch anything" at the very top** — the one or
  two facts that would otherwise cost the next agent an hour (a test suite
  that pins document contents, a directory that looks stale but is live, a
  command that must not be run twice).
- **Compress on a rhythm**: every few turns during long work, at every
  work-unit boundary, and always before a final report or a context
  handoff. Cut old hypotheses, dead ends, long logs, and duplicate
  statements — after folding anything durable into the document that owns
  it (usually REPORT).
- **Maintain a do-not-re-read list.** When a document is deleted or
  superseded, record what was removed, where its durable content went, and
  that git history can restore it. This single habit is what makes deletion
  safe and cheap — the next agent neither re-reads the stale file nor
  wonders whether it was lost.
- **No secrets.** Never store credentials, tokens, credential-bearing logs,
  or real user data in handoff files — they are exactly the files every
  future session reads.

A handoff kept this way is a snapshot in the present tense. The alternative
— an append-style handoff that grows by session — was measured to become
unreadable within weeks: the current state had to be excavated from under
the history (see Anti-Patterns).

## The Task Ledger

One ledger file (for example `TASKS.md`), canonical for the work queue:
active, blocked, and completed tasks in a table — ID, task, priority,
status, notes.

- **Write rows as delegation specs.** A finding-style row carries the
  file:line location, the smallest proposed fix, and a confidence level.
  Written that way, the row is a self-contained work order: a subagent (or
  a different agent product) can execute it without any further context.
  Field result: 14 parallel implementation tasks delegated straight from
  ledger rows all came back test-green, with zero no-op returns.
- **Declare the verification-log policy in the ledger header**: only the
  most recent verification run is kept; older runs live in this file's git
  history. Without the declaration, conscientious agents append every run
  — in one repository the appendix passed 30 lines within three weeks and
  buried the tasks (see Anti-Patterns).
- **History is one line per period**, with details left to git log and PR
  bodies. The ledger records that a period shipped and which PRs; it does
  not narrate.
- **Division of labor with REQUIREMENTS**: the acceptance table answers
  "is the requirement met?" at requirement level; the ledger answers "what
  is the next unit of work?" at operational level (including review
  findings and chores). A requirement is done when its acceptance row has
  evidence — not merely when its ledger tasks are checked off.

## Anti-Patterns

1. **Dated handoff snapshots.** A new `HANDOFF_<date>.md` per session
   looks diligent and is the opposite: each snapshot is stale the day
   after, the pile grows monotonically, and the next agent must read N
   documents to reconstruct one current state. One living HANDOFF plus
   REPORT for history replaces the whole pile.
2. **Full-append verification logs.** Appending every verification run to
   the ledger or handoff turns signal into noise within weeks (measured:
   30+ lines in three weeks). Keep the latest run; state in the header
   that git history holds the rest.
3. **"Done" written against unmerged work.** A document written on a
   feature branch that declares work complete becomes a false statement
   the moment it is read from the default branch — or the branch dies. In
   one measured consolidation, six separate completion claims had to be
   rolled back because the feature they assumed never merged. Any
   point-in-time claim in a canonical document must be verified against
   the default branch as of writing — a full pass over the claims, not a
   spot check.
4. **Canonical conventions in files agents never read.** Conventions kept
   in a gitignored or agent-invisible file simply do not exist for the
   next agent. Put the canonical text in the committed file every agent
   loads; make agent-specific files thin pointers to it.
5. **Triple-bookkeeping of current position.** When a brief, a handoff,
   and a backlog each maintain their own "where we are", they decay
   independently and disagree within days (observed in an audited
   repository maintaining the same completion history in three places).
   Current position has exactly one owner: HANDOFF. Everything else
   points at it.

## Verification

Documentation about state earns trust only through measurement. Three
rules:

- **Phrase unverified items as a checklist, and the checklist becomes the
  work order.** In REQUIREMENTS (or a dedicated verification section),
  keep an explicit "unverified" list where each entry names the command or
  observation that would verify it. The next agent's instructions are then
  literally "burn down the unverified list" — no separate tasking needed
  (field-tested).
- **Deployment and propagation tasks complete on a full-target scan, not
  on the loop's own claims.** When a change is rolled out across many
  targets (a file deployed to every repository, a header updated in every
  document), the completion evidence is one scan across all targets at the
  end — counting hits against the expected total. Field lesson: a rollout
  reported "deployed to all repositories" while a later full-fleet scan
  found 6 of 30 targets missing; the loop had been interrupted and resumed,
  and the resumption silently dropped part of the plan. The scan catches
  what per-item bookkeeping cannot.
- **Verify claims against the repository's real state, not the local
  checkout.** Local checkouts sit on old branches more often than anyone
  expects. Fetch first, then read files from `origin/<default>` when
  checking what is actually true for the next reader.

## Migration: Restructuring Existing Documents

Adopting this framework in a repository with years of accumulated documents
is itself a hazardous task. The field-tested order:

1. **Inventory and classify** every document: canonical candidate, stale,
   duplicate, or historical.
2. **Before moving anything, grep the tests and CI** for pinned document
   paths and contents. Doc-contract tests (tests that assert a document
   contains a phrase or that a path exists) are common in agent-maintained
   repositories, and a restructure that looks clean will still break them.
   Knowing what is pinned decides what can move at all.
3. **Audit for facts that exist only in the doomed documents** — open
   questions, warnings, unfinished tasks, safety notes — and move them into
   the canonical documents first. Deletion is safe only after this pass.
4. **Fold history into REPORT, then delete the old files.** Git history
   preserves them; record each deletion in HANDOFF's do-not-re-read list
   with the recovery note. Where repository policy requires historical
   files to stay readable in the working tree, an archive directory with an
   indexed README (what each file was, why it was archived) is the
   alternative to deletion.
5. **Scan for dangling references — including backtick-quoted path
   mentions.** Markdown link checkers validate links; they do not validate
   paths mentioned in inline code spans. Field lesson: a restructure passed
   the repository's link guard while three backtick-quoted path references
   to moved files stayed broken; only a full-text grep for the old paths
   caught them.
6. **Re-verify every point-in-time claim against the default branch**
   (anti-pattern 3) before declaring the restructure done.

## Out Of Scope

- SDLC process classification and stage gates — this skill structures the
  documents, not the process around them.
- UI specifications and design documents.
- Tool-specific configuration (agent config files, CI setup, permissions).
  The framework is deliberately agnostic to which agent product reads it.

## Provenance

This skill is distilled from operating a fleet of ~30 repositories
maintained primarily by coding agents across multiple products, where
session handoffs happen daily and every documentation failure eventually
surfaces as a wasted session. Every rule above traces to an observed
failure or a verified recovery — "field-tested" and "measured" mark
behavior that actually occurred, and the numbers (six missing targets of
thirty, 14 parallel delegations, 30-line log noise) are from those
operations with identifying details removed. Guidance that is
design-derived rather than observed is not included.
