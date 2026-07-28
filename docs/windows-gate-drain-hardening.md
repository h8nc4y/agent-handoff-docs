# Windows gate drain hardening

## Classification and objective

This is a Class M reliability and security-boundary fix. The Windows launch
gate already fails closed when its target-side stdout or stderr pipe does not
close, but its fixed 100 ms post-exit drain window is not derived from the
parent helper's bounded drain contract.

The objective is to preserve byte-exact transport during ordinary scheduler
delay without allowing a descendant-held pipe to keep the owned Job alive
indefinitely.

## Evidence and impact

- Merged-main run `30341569740` failed the first PowerShell 7 raw-transport
  regression before any worktree-content-drift fixture ran.
- The exact pull-request tree passed run `30341015703`, and the exact merged
  tree passed a bounded local PowerShell 7 rerun.
- Historical run `30144735948` failed with the same raw-transport assertion
  before the worktree-content-drift change existed.
- `Invoke-PrivateMarkerWindowsGateProxy` still uses the 100 ms
  `Task.WaitAll` budget introduced in pull request #2. Pull request #3 changed
  hosted PowerShell 5.1 coverage but did not change that gate budget.

The failed assertion did not expose the bounded-result fields, so the hosted
failure alone cannot prove which field differed. The unchanged 100 ms drain
and the first raw regression's 5-second test-only outer timeout were both
unaddressed timing boundaries shared by the current and historical failures.
A later loaded local run preserved every expected stdout/stderr byte but
reported `TimedOut=True` and exit `0` under that 5-second probe budget. This is
dual-bound evidence, not proof of the old hosted run's exact field-level cause.
The regression suite must prove both corrected boundaries deterministically
instead of treating a successful rerun as evidence that the problem
disappeared.

## Design

1. Add an explicit Windows gate output-drain budget to
   `Invoke-PrivateMarkerBoundedProcess`.
2. Derive the effective gate budget as the smaller of that value and the
   parent `DrainTimeoutMilliseconds`, then include it in the trusted gate
   payload.
3. Validate the payload value before starting the requested target.
4. Wait for both fixed-buffer copy tasks only for that effective budget.
5. If both tasks complete, preserve the requested child's exact exit code and
   byte streams. If either task remains open, return exit `125` without
   reporting possibly truncated output as the child's real result.
6. Keep the parent timeout, kill-on-close Job ownership, output limits, and
   final cleanup deadlines unchanged.
7. Use the existing finite 30,000 ms production default for all three targeted
   Windows timing probes: the first raw transport, delayed-within-budget, and
   over-budget inherited-pipe cases. Do not change the production
   implementation/default or the native Git fixture's independent budget.

The default gate budget is 1,000 ms. The parent rejects values outside
1–60,000 ms and passes the smaller of the configured value and its existing
drain budget. The gate independently accepts only a raw JSON integer in the
same range before constructing the requested child.

## Acceptance criteria

- A small synthetic stdin/stdout/stderr exchange preserves bytes, EOF, and a
  nonzero exit code exactly.
- A synthetic descendant holds the target-side pipes for more than 100 ms but
  less than the gate budget; the gate still returns exact bytes and the
  requested child's exit code.
- A synthetic descendant holds the pipes beyond the gate budget; the gate
  returns `125`, the owned Job stops the descendant, and no delayed sentinel is
  written.
- Timeout, output-limit, tree-stop, stream-drain, and total bounded-return
  contracts remain intact.
- Failures report only bounded result flags, exit code, lengths, and equality
  booleans; raw binary content is not reflected.
- Targeted regressions pass on local PowerShell 7 and Windows PowerShell 5.1.
- Full repository validation passes locally and on the hosted Windows, Ubuntu,
  macOS, and Windows PowerShell 5.1 matrix.

## Local implementation evidence

- Pre-fix PowerShell 7 targeted run: exit `1`; a 300 ms holder returned `125`,
  its completion sentinel was absent, and five malformed budgets started the
  requested synthetic child.
- Post-fix PowerShell 7 targeted run: exit `0`, final success marker, stderr
  zero bytes, and no scanner or gate process remained.
- Post-fix Windows PowerShell 5.1 targeted run: exit `0`, final success marker,
  stderr zero bytes, and no scanner or gate process remained.
- The PS5.1 timing fixtures use BOM-less `-File` scripts so their own transport
  is not contaminated by `-EncodedCommand` CLIXML framing.
- The final explicit-override fixture uses a 2,000 ms gate budget for the
  300 ms benign holder. The over-budget fixture requests 5,000 ms while the
  parent drain is 2,000 ms and holds the inherited pipe for 4,000 ms, proving
  the effective parent cap and exit-`125` cleanup path.
- Focused-review rerun before the final test-budget change: exit `1`; the first
  raw transport returned `TimedOut=True`, exit `0`, stdout 12/12 exact, stderr
  8/8 exact, output limit false, tree stopped, and streams drained. This
  measured result proved the 5,000 ms test-only budget was too short.
- The next bounded attempt at 10,000 ms also exited `1`: `TimedOut=True`, exit
  `0`, stdout 0/12, stderr 0/8, output limit false, tree stopped, and streams
  drained. Host load made both short fixture-specific limits unreliable, so the
  final first-raw, delayed, and over-budget timing probes use the existing
  30,000 ms production default as their finite test budget. The original hosted
  failure's missing field-level cause remains unconfirmed.

## Non-goals

- Waiting without a finite deadline.
- Allowing descendants to outlive the owned Windows Job.
- Changing POSIX process-group behavior.
- Claiming that a successful CI rerun proves the original timing failure's
  exact field-level cause.
