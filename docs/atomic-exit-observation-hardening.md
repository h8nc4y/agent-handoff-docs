# Atomic process-exit observation hardening

## Classification and objective

This is a Class M reliability and security-boundary fix. The bounded process
helper must never report its initial exit code after a child has completed and
all other health flags are successful.

The objective is to make one process-exit observation per polling iteration and
reuse that observation for timeout handling, exit-code capture, and the
successful stream-drain break.

## Evidence and cause

- Pull request #12 run `30350038650` passed Windows PowerShell 7, Windows
  PowerShell 5.1, Ubuntu, and macOS at head `a1b6074`.
- Merge commit `bff81eb` then triggered post-main run `30350539529`.
- That run passed both Windows jobs and macOS. Ubuntu alone failed the forged
  `OS` scanner regression while its sanitized stdout still said the scan
  passed.
- `Invoke-Scanner` records a separate failure when timeout, output limit,
  process-tree stop, or stream drain is unhealthy. The hosted log contained
  only the nonzero-exit assertion.
- The bounded polling loop read `Process.HasExited` three times in one
  iteration. The first read could be false, then the stream-completion break
  could observe true before the exit-code capture ran. The result remained
  otherwise healthy but retained the initial exit code `-1`.

The same merge SHA passed the prior Ubuntu job, so the failure depended on the
timing of the process transition. The three-read source path explains the
observed combination without attributing it to the Windows gate change.

## Design

1. Read `Process.HasExited` once per polling iteration after stream task
   updates.
2. Reuse that snapshot for the timeout boundary, exit-code capture, and the
   successful drain-completion break.
3. If the child changes from running to exited after the snapshot, observe and
   capture it on the next bounded 5 ms polling iteration.
4. Seal the source contract with an AST validator. The target loop must contain
   exactly one direct `process.HasExited` read assigned to
   `processHasExited`, and exactly four snapshot references: assignment,
   timeout, exit capture, and break.
5. Add `-ExitObservationOnly` to run the structural checks and first fast-exit
   raw transport regression without the wider fixture matrix.
6. When the forged-`OS` scanner regression fails, report only fixed bounded
   result fields and byte lengths. Do not reflect scanner output or local paths.
7. Keep the PowerShell 5.1-executed process helper BOM-less and use its existing
   English/ASCII source-comment convention. Japanese rationale belongs in this
   companion document; a BOM-less Japanese source comment can be decoded as
   ANSI by Windows PowerShell 5.1 and absorb the following statement.

## Acceptance criteria

- The AST source seal fails on the three-read implementation and passes on the
  single-snapshot implementation.
- Validator regressions accept the intended snapshot shape and reject multiple
  direct reads or an unused snapshot.
- `-ExitObservationOnly` passes on PowerShell 7, Windows PowerShell 5.1, and a
  bounded native Linux PowerShell container.
- The normal PowerShell 7 and Windows PowerShell 5.1 full self-tests pass after
  exact freeze and independent review.
- Hosted validation passes Windows PowerShell 7, Windows PowerShell 5.1,
  Ubuntu, and macOS at the reviewed head and again on merged `main`.
- No scanner, gate, or target process remains after each bounded run.

## Local evidence

- Test-first AST seal before the production change: false, with three direct
  `HasExited` reads in the target loop.
- AST seal after the production change: true, with one direct read and four
  snapshot references.
- PowerShell 7 `-ExitObservationOnly`: exit `0`, exact final marker, stderr
  zero bytes.
- Windows PowerShell 5.1 `-ExitObservationOnly`: exit `0`, exact final marker,
  stderr zero bytes.
- Cached Linux image
  `sha256:a52d8a7eeb3c925dd9ef2e77409d2d2ccb18556a59ec2e166265c595b9d60cfa`
  with network disabled, a read-only root/repository mount,
  `no-new-privileges`, finite CPU/memory/PID limits, and a 45-second watchdog:
  exit `0`, exact final marker, stderr zero bytes, residual containers zero.

## Non-goals

- Do not change the 30-second process timeout, output limits, drain budgets,
  Job Object behavior, or POSIX process-group cleanup.
- Do not reinterpret caller-controlled `OS` environment values.
- Do not weaken the Windows gate drain or immediate-spawn containment fixtures.
- Do not treat a rerun of the failed post-main job as proof for changed source;
  validate the new reviewed head instead.
