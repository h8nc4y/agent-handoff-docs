# tracked worktree content drift の堅牢化

## 分類と目的

Class M のセキュリティ不具合修正である。private-marker scanner が最初の
snapshot を取得した後、tracked regular worktree file が同じバイト長の別内容へ
atomic replacement された場合に、古い bytes を根拠として成功報告しないようにする。

## 影響と範囲

現状の読後確認は reparse、type、length の変化を拒否する一方、最終報告前の
再確認は Git index metadata だけを対象にしている。そのため、同じ長さの
worktree replacement により、成功報告が古い内容を表す可能性がある。

修正対象は Git-index mode と working-tree fallback mode の双方で保持する
regular-worktree snapshot である。index-only と missing-worktree の scan target
には再確認すべき regular worktree path がないため対象外とする。

## 設計

1. regular worktree の各 snapshot について、repository-relative path と最初の
   bytes を保持する。
2. 最終報告の直前に、初回取得と同じ fail-closed traversal で各 path を再読する。
3. 最終 bytes と最初の snapshot を byte-for-byte で比較する。
4. 最終境界での missing、reparse、type、size、read、bytes の変化は、path や
   内容を含めない固定理由 `integrity: worktree-content-drift` に統一する。
5. 決定的な同期処理は regression test が使う disposable scanner copy にだけ
   注入し、production code へ delay や test hook を追加しない。

## 受入条件

- snapshot 取得後の同長 atomic replacement が exit `2` と
  `integrity: worktree-content-drift` になる。
- failure output に path と synthetic sentinel を含めない。
- 既存の clean、staged-only、worktree-only、missing-worktree、reparse、
  index-drift の挙動を維持する。
- PowerShell 7 と Windows PowerShell 5.1 の readiness、PowerShell 7 の
  full synthetic suite、repository scan、encoding/whitespace check、Gitleaks、
  Semgrep が成功する。

## 非目標

この境界が保証するのは初回と最終の観測時点での一致である。最終再読後まで
filesystem compare-and-swap semantics を保証するものではない。

## 検証記録

2026-07-28 に Git-index mode と fallback mode の targeted regression を実行し、
いずれも exit `2`、固定理由あり、path と sentinel の反射なしを確認した。
PowerShell 7 と Windows PowerShell 5.1 の readiness と repository scan、
PowerShell 7 の full synthetic suite、strict text hygiene、Gitleaks の
directory/history scan、Semgrep `p/default`、`git diff --check` は成功した。
hosted cross-platform validation は pull request 実行まで未確認である。
