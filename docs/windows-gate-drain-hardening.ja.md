# Windows gate の drain 強化

## 分類と目的

本変更は Class M の信頼性・セキュリティ境界修正である。Windows launch
gate は target 側の stdout / stderr pipe が閉じない場合に fail closed
するが、child 終了後の drain 期限は parent helper の bounded drain 契約
から独立した固定 100 ms になっている。

目的は、通常の scheduler 遅延では byte-exact transport を維持しつつ、
descendant が保持する pipe によって owned Job が無期限に残らないように
することである。

## 根拠と影響

- merged-main run `30341569740` は、新しい worktree content-drift fixture
  より前に実行される最初の PowerShell 7 raw-transport regression で失敗した。
- 同一 tree の pull request run `30341015703` と、同一 merged tree の
  bounded なローカル PowerShell 7 再実行は成功した。
- worktree content-drift 変更より前の run `30144735948` にも、同一の
  raw-transport assertion 失敗がある。
- `Invoke-PrivateMarkerWindowsGateProxy` には pull request #2 で追加された
  100 ms の `Task.WaitAll` 期限が残っている。pull request #3 は hosted
  PowerShell 5.1 の検証範囲を変更したが、この gate 期限は変更していない。

失敗した assertion は bounded result の各 field を表示しないため、hosted
failure だけでは相違した field を断定できない。変更前後の失敗には 100 ms
drain と、最初の raw regression 専用の 5秒 outer timeout という、未修正の
timing 境界が2つあった。その後の高負荷ローカル実行では stdout / stderr の
期待 byte をすべて保持したまま `TimedOut=True`、exit `0` になった。これは
dual-bound evidence であり、過去の hosted run の field-level 原因を断定する
ものではない。したがって、再実行成功をもって解消とはせず、両境界の修正後挙動を
deterministic regression で固定する。

## 設計

1. `Invoke-PrivateMarkerBoundedProcess` に Windows gate 専用の明示的な
   output-drain budget を追加する。
2. その値と parent の `DrainTimeoutMilliseconds` の小さい方を effective
   budget とし、trusted gate payload に含める。
3. requested target を開始する前に payload の値を検証する。
4. 固定長 buffer の copy task 2本を effective budget の範囲だけ待つ。
5. 両 task が完了した場合は requested child の exit code と byte stream を
   そのまま返す。どちらかが残る場合は、切れた可能性がある出力を child の実結果
   として扱わず exit `125` を返す。
6. parent timeout、kill-on-close Job、出力上限、最終 cleanup deadline は
   変更しない。
7. targeted Windows timing probe 3件、すなわち最初の raw transport、
   delayed-within-budget、over-budget inherited-pipe に、既存 production
   default と同じ有限 30,000 ms を使う。production implementation/default
   と native Git fixture の独立 budget は変更しない。

既定の gate budget は 1,000 ms である。parent は 1–60,000 ms の範囲外を
拒否し、設定値と既存 drain budget の小さい方を payload に渡す。gate 側でも
requested child を構築する前に、同じ範囲の raw JSON integer だけを受理する。

## 受入条件

- 小さい synthetic stdin / stdout / stderr、EOF、非0 exit code を
  byte-exact に保持する。
- target 側 pipe を 100 ms 超かつ gate budget 未満だけ保持する synthetic
  descendant では、正確な bytes と requested child の exit code を返す。
- pipe を gate budget より長く保持する synthetic descendant では exit
  `125` を返し、owned Job が descendant を停止し、遅延 sentinel を書かない。
- 既存の immediate-spawn containment fixture は gate drain を 250 ms に固定
  する。1秒後の sentinel を production default と同じ期限で競合させず、
  明確に over-budget の証拠として維持する。
- timeout、output limit、tree stop、stream drain、total bounded return の
  契約を維持する。
- 失敗診断には bounded result flags、exit code、length、equality のみを出し、
  raw binary content を反映しない。
- targeted regression がローカル PowerShell 7 と Windows PowerShell 5.1
  で成功する。
- repository 全体の検証がローカルおよび hosted Windows / Ubuntu /
  macOS / Windows PowerShell 5.1 matrix で成功する。

## ローカル実装証跡

- 修正前の PowerShell 7 targeted run は exit `1`。300 ms holder は `125`
  を返して完了 sentinel に到達せず、不正 budget 5種はいずれも requested
  synthetic child を起動した。
- 修正後の PowerShell 7 targeted run は exit `0`、最終成功 marker あり、
  stderr 0 byte、scanner / gate の残 process 0。
- 修正後の Windows PowerShell 5.1 targeted run は exit `0`、最終成功 marker
  あり、stderr 0 byte、scanner / gate の残 process 0。
- PS5.1 timing fixture は `-EncodedCommand` の CLIXML framing が fixture 自身の
  transport を汚さないよう、BOMなし `-File` script を使う。
- 最終 explicit-override fixture は、300 ms の正常 holder に 2,000 ms の
  gate budget を指定する。超過 fixture は 5,000 ms を要求しつつ parent drain
  を 2,000 ms、pipe hold を 4,000 ms とし、effective parent cap と exit
  `125` cleanup を固定する。
- 最終 test budget 修正前の focused-review 再実行は exit `1`。最初の raw
  transport は `TimedOut=True`、exit `0`、stdout 12/12 exact、stderr 8/8
  exact、output limit false、tree stopped、streams drained だった。この実測が
  5,000 ms の test-only budget が短すぎる根拠である。
- 続く 10,000 ms の bounded attempt も exit `1`。`TimedOut=True`、exit `0`、
  stdout 0/12、stderr 0/8、output limit false、tree stopped、streams drained
  だった。host load 下では短い fixture 固有値が安定しなかったため、最終 attempt
  は first-raw、delayed、over-budget の timing probe 3件に、既存 production
  default と同じ有限 30,000 ms を test budget として使う。過去の hosted
  failure の field-level 原因は引き続き未確認である。

## hosted 検証記録

pull request #12 の head run `30350038650` は hosted job 4件すべてに成功し、Windows PowerShell 7 job は gate regression を含む full suite を実行した。
直後の post-merge run `30350539529` は Ubuntu job 1件が失敗したため、成功証拠には数えない。
pull request #13 の head run `30354157531`、post-main run `30354646900`、監査対象の main run `30496527183` は、その後いずれも4件すべてに成功し、Windows PowerShell 7 job は full suite を実行した。
これらの成功runは、過去の timing failure の field-level 原因を断定する根拠にはしない。

## 非目標

- 有限期限なしで待つこと。
- owned Windows Job より descendant を長生きさせること。
- POSIX process-group 挙動を変更すること。
- CI 再実行成功だけから、元の timing failure の field-level 原因を断定すること。
