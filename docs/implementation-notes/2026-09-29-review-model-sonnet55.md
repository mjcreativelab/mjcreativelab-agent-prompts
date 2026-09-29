# 実装ノート: レビュー役のモデル再配分（包括ラウンドのみ opus・以降は Sonnet 5.5）

- 日付: 2026-09-29（JST）
- Issue: #142
- 対象: `skills/smart-issue-resolve/references/agent-orchestration.md`（雛形 B `sir-claude-review-set`・雛形 C `sir-codex-breaker`）・`skills/smart-issue-plan/references/agent-orchestration.md`（`sip-plan-review-set`）+ 両 SKILL.md / README / CLAUDE.md マスター同期ノート / 実測台帳

## 背景

Claude Sonnet 5.5 の公式ガイド（https://claude.dev/blog/building-with-claude-sonnet-5-5/ ）は、「繰り返し実行する定義の明確なエージェント作業（調査・レビュー・下書き）」と「要件との照合」を Sonnet 5.5、「慎重な判断を要する複雑な作業」を Opus 5.5 に振り分ける選定表を示した。レビュー雛形は Issue #111 でレビュー役を一律 opus 化しており、Issue #134 の実測では時間の支配要因がラウンド数（6〜18 ラウンド）だった。繰り返し回る差分スコープ・確認ラウンドはガイドの Sonnet 適性に該当するため、モデル配分を見直した（根拠の詳細と採取予定は [docs/empirical-tuning/review-loop-speedup.md](../empirical-tuning/review-loop-speedup.md) の Issue #142 節）。

## 仕様に明記されていなかったため判断した事項

1. **モデル切り替えは既存の `comprehensive` フラグに追従させる**: `const reviewModel = comprehensive ? 'opus' : 'sonnet'` をラウンド冒頭で 1 回決め、レビュワー / Breaker / Judge の 3 箇所で使う。#113 の「包括ラウンド = 分割並列」と同じ境界なので、新しい分岐軸を増やさない
2. **Judge もレビュワーと同じ規則（包括ラウンドのみ opus）**: Judge が `dismissed` にした反例は fix / plan-editor に届かない。opus の fix は Judge の「採りすぎ」は不採用にできるが、「捨てすぎ」は取り戻せない（取り戻せるのは確認ラウンドのみ）。反例が集中する包括ラウンドの裁定は opus を維持した
3. **sip も resolve と同期した**: ガイドの適性条件 "a clear spec and a way to check the result" は、実行検証（テスト・probe）を持たない計画レビューには resolve ほど当てはまらない。そのため「sip は opus 維持」も選択肢として提示し、ユーザーが推奨案（同期）を選択した。構造同期ルール（resolve 雛形 B ↔ sip）とも一致する
4. **雛形 C の sonnet 役（監査役・Breaker）は effort max → high**: CLI 更新でリポジトリ変更なしに Sonnet 5.5 の max へ切り替わるため、ガイドの「max は評価で品質向上が確認できた場合のみ」に従い、発見役を high とする Issue #134 と揃えた
5. **`RESTRAINT_NOTE` はレビュー役のプロンプトに残す**: プロンプト関数がラウンド共通のため、sonnet ラウンドにも付く。内容（サブエージェント禁止・過剰検証禁止・スコープ維持・簡潔な出力）は sonnet にも無害なので、ラウンドでプロンプトを分岐させず、規約文言（「opus 役のみ」）の方を更新した
6. **起動ログにモデルを表示する**: ラウンド開始ログの起動内訳に `（opus）` / `（sonnet）` を付けた。IDE では `log()` が唯一の進捗表示で、dogfooding でモデル配分を確認する手段にもなるため
7. **レビュー済み表記を `Opus→Sonnet` に更新**: dry-twice 収束は最低 2 ラウンドかかり、ラウンド 2 は必ず sonnet になる。そのため、収束したループは常に両モデルを経由する
8. **対象外**: `code-reviewer` / `code-reviewer-adversarial`（単発の包括レビューのみで反復ラウンドを持たず、ガイドの「繰り返し実行」に該当しない）、memory-dream の claude 系レビュワー（sonnet / max。smart-issue 系ではないため本 Issue の範囲外。CLI 更新で Sonnet 5.5 の max になる点は別途判断）

## トレードオフ

- **採用（包括ラウンドのみ opus）** vs 却下（全レビュー役を sonnet）: 全 sonnet はコスト最小だが、recall の要である包括ラウンドと計画レビューの設計判断まで下げることになる。Sonnet 5.5 の recall を示す実測も評価もない（#111 Phase C の比較はモデルと分割並列の効果が交絡し、しかも 5.5 以前の値）ため却下した
- **採用（包括ラウンドのみ opus）** vs 却下（全 opus 維持）: ガイドは反復レビューを明示的に Sonnet 側に置いており、ロングループでは単発ラウンドがレビュー体数の大半を占める（例: 12 ラウンドの標準ループでは 14 体中 11 体）。トークン単価の差（半額）がそのまま効く
- **リスク**: モデルが変わると見落とす箇所も変わるため、確認ラウンドの追加検出が増えてラウンド数が伸びる可能性がある。台帳の採取予定に明記し、劣化時は `reviewModel` を `'opus'` 固定に戻すだけで切り戻せる

## 前提（利用者への影響）

- `sonnet` エイリアスが Sonnet 5.5 に解決されるのは Claude Code v2.1.284 以降。未満では Sonnet 5 で動き、#111 以前に近い状態になる。両 README の前提条件と resolve SKILL.md の役割表注記に明記した
- 実装時点のホストは v2.1.280 で、直近 7 日の transcript の sonnet 呼び出しはすべて `claude-sonnet-5`（808 件）だった

## 検証

- 両 orchestration ファイルの全 js ブロック（resolve 5 + sip 1）を `node --check` で構文検証し、すべて OK
- 使い捨てハーネス（`agent()` / `parallel()` スタブで雛形を実行し、各 `agent()` の model / effort を記録）で次を確認した
  - 雛形 B 標準: r1 のレビュワー g1/g2/g3 = opus、r2-all・r3-all（確認ラウンド）= sonnet、dev:fix = opus / max、qa:final = sonnet
  - 雛形 B 敵対: r1 の breaker sec/corr/ops・judge = opus、r2-all の breaker・judge = sonnet、r3-all = sonnet
  - 継続セット（startRound=4）: 全ラウンド sonnet
  - sip 標準 / 敵対: 雛形 B と同じ配分（plan-editor = opus / max）
  - 雛形 C: security:audit・breaker = sonnet / high
- 実際の Workflow 実行（実モデルでの dogfooding）は未実施。CLI v2.1.284 以上で実施し、台帳の採取項目を記録する
