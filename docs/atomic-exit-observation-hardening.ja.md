# process exit 観測の atomic 化

## 分類と目的

本変更は Class M の信頼性・セキュリティ境界修正である。bounded process
helper は、child が完了し他の health flag がすべて成功しているのに、初期
exit code を返してはならない。

目的は polling iteration ごとに process exit を一度だけ観測し、その値を
timeout、exit code capture、stream drain 完了の break で共有することである。

## 証拠と原因

- pull request #12 の run `30350038650` は head `a1b6074` で Windows
  PowerShell 7、Windows PowerShell 5.1、Ubuntu、macOS に成功した。
- merge commit `bff81eb` の post-main run `30350539529` では、Windows
  2件と macOS が成功し、Ubuntu だけが forged `OS` scanner regression で
  失敗した。sanitize 済み stdout は scan 成功を示していた。
- `Invoke-Scanner` は timeout、output limit、process-tree stop、stream drain
  が不健康なら別 failure を記録する。hosted log は nonzero exit assertion
  だけを含んでいた。
- bounded polling loop は同じ iteration で `Process.HasExited` を3回読んで
  いた。最初が false の後、exit code capture より先に stream 完了 break が
  true を観測すると、他の flag は healthy のまま初期 exit code `-1` が残る。

同じ merge SHA の直前 Ubuntu job は成功しており、失敗は process 状態遷移の
timing に依存した。source の3回 read は実測された組合せを説明し、Windows
gate 変更を原因と仮定する必要はない。

## 設計

1. stream task 更新後、polling iteration ごとに `Process.HasExited` を一度だけ
   読む。
2. その snapshot を timeout 境界、exit code capture、drain 完了 break で
   共有する。
3. snapshot 後に child が running から exited へ変わった場合は、次の有限
   5 ms polling iteration で観測し、exit code を確定する。
4. AST validator で source contract を固定する。対象 loop の direct
   `process.HasExited` は `processHasExited` への assignment 1件だけとし、
   snapshot 参照は assignment、timeout、exit capture、break の4件とする。
5. `-ExitObservationOnly` を追加し、広い fixture matrix に入らず structural
   check と最初の fast-exit raw transport regression を実行できるようにする。
6. forged `OS` scanner regression の失敗時は fixed bounded result field と
   byte length だけを報告する。scanner output や local path は反映しない。
7. PowerShell 5.1 が実行する process helper は BOMなしを維持し、既存の
   English / ASCII source comment 規約に従う。日本語の理由は本 companion
   document に置く。BOMなし日本語 source comment は Windows PowerShell 5.1
   で ANSI decode され、次の statement を comment に取り込む場合がある。

## 受入条件

- AST source seal は3回 read 実装で失敗し、single snapshot 実装で成功する。
- validator regression は意図した snapshot 形だけを受理し、複数 direct
  read と未使用 snapshot を拒否する。
- `-ExitObservationOnly` が PowerShell 7、Windows PowerShell 5.1、bounded
  native Linux PowerShell container で成功する。
- exact freeze と独立 review の後、通常の PowerShell 7 / 5.1 full self-test
  が成功する。
- reviewed head と merge 後 `main` の hosted validation が Windows
  PowerShell 7、Windows PowerShell 5.1、Ubuntu、macOS で成功する。
- 各 bounded run の後に scanner、gate、target process が残らない。

## ローカル実装証跡

- production 変更前の test-first AST seal は false。対象 loop の direct
  `HasExited` read は3件だった。
- production 変更後の AST seal は true。direct read は1件、snapshot 参照は
  4件だった。
- PowerShell 7 `-ExitObservationOnly` は exit `0`、final marker 完全一致、
  stderr 0 byte。
- Windows PowerShell 5.1 `-ExitObservationOnly` は exit `0`、final marker
  完全一致、stderr 0 byte。
- cached Linux image
  `sha256:a52d8a7eeb3c925dd9ef2e77409d2d2ccb18556a59ec2e166265c595b9d60cfa`
  を network 無効、root/repository read-only、`no-new-privileges`、有限の
  CPU/memory/PID、45秒 watchdog で実行した。exit `0`、final marker 完全一致、
  stderr 0 byte、残 container 0。

## 対象外

- 30秒 process timeout、output limit、drain budget、Job Object、POSIX
  process-group cleanup は変更しない。
- caller-controlled `OS` environment value を platform 判定に使わない。
- Windows gate drain と immediate-spawn containment fixture を弱めない。
- source 変更の証拠として failed post-main job の rerun を使わず、新しい
  reviewed head を検証する。
