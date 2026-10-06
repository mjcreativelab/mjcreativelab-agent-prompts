# 役割別モデル配分: 設計・指示 = Opus / 実装 = Sonnet / 監視・レビュー = Fable（2026-10-02）

グローバル CLAUDE.md に「Claude モデルの役割分担」を追加し、`smart-issue-plan` と `smart-issue-resolve` の役割別エージェントを、設計役と plan-editor は `opus`、開発者は `sonnet`、レビュー役・独立 QA・セキュリティ監査は `fable` に固定した。Issue #142 の「レビュー役は包括ラウンドのみ opus、以降は sonnet」という配分は置き換えた。Workflow 経由で `fable` が解決されるかと、コスト・品質への影響はまだ実測していない（採取項目は `docs/empirical-tuning/review-loop-speedup.md` の同日節）。

## 配分

| 役割（`agent()` の label） | 変更前 | 変更後 |
|---|---|---|
| 設計役（`architect:design`）・plan-editor | opus / max | 変更なし |
| 開発者（`dev:implement` / `dev:qa-fix-*` / `dev:arch-fix` / `dev:fix-r*`、雛形 D） | opus / max | sonnet / high |
| 設計整合レビュー（`architect:review`） | opus / max | fable / max |
| 独立 QA（`qa:*`、雛形 E） | sonnet / high | fable / high |
| claude 系レビュワー・Breaker・Judge バッチ | 包括ラウンド opus、以降 sonnet（high） | 全ラウンド fable / high |
| 雛形 C（codex 敵対）の監査役・Breaker | sonnet / high | fable / high |
| probe-cleanup | sonnet / low | 変更なし |

オーケストレーター（メインセッション）はユーザーのセッション設定で動くため、SKILL.md / README には「Opus 推奨」と書いた。

## 自分で判断した事項

- **対象スキル**: 「プラン系」は `smart-issue-plan`、「実装系」は `smart-issue-resolve` と解釈した。`smart-spec-to-pr` は両スキルを連鎖させるだけで、エージェントのモデル指定を持たないため変更していない
- **独立 QA は監視役として Fable にした**: QA は開発者の自己申告を信用せずにテストと受け入れ基準を検証する、自動コミット前の最終ゲートなので「監視」にあたる
- **設計役の「兼任」を分けた**: 変更前は設計役が実装後の設計整合レビューも担っていた。設計（`architect:design`）は Opus のまま、レビュー（`architect:review`）は Fable にし、役割表では「設計レビュー役」として別行にした。プロンプト本文は変えていない
- **開発者の effort を max から high に下げた**: Sonnet 5.5 は effort が再較正されており、公式ガイドが `max` を「評価で品質向上が確認できた場合のみ」としている（Issue #142 で雛形 C の Sonnet 役を high にしたのと同じ根拠）。Fable 役の effort は、指針がないため各役の値を据え置いた
- **抑制ノート（`RESTRAINT_NOTE`）の付与範囲を「probe-cleanup 以外の全 `agent()`」にした**: 変更前のルールは「opus 役に付け、sonnet 役には付けない」だった。モデル基準のままだと、開発者 5 箇所から外し、QA と雛形 C に足す必要がある。ノートの目的は上位モデル（opus / fable）の過剰処理の抑制で、内容は sonnet にも無害なので、付与範囲を役割で決めることにした。結果として QA（雛形 A・B・E）と雛形 C の 2 役に追加し、開発者のノートは残した。cr / cra は全エージェントが opus でノート付きのため、新ルールと矛盾しない
- **Codex / Cursor / Gemini への振り分けは変えていない**: 今回の配分は Claude Code の責任範囲内でのモデル選択の規約として書いた。閉じた実装タスクを Codex に振るルールはそのまま

## 検討した代替案

| 案 | 採らなかった理由 |
|---|---|
| レビュー役を「包括ラウンドは fable、以降は sonnet」にする | 「監視・レビューは Fable」という指示に反する。コストが問題になったら `reviewModel` の 1 行で戻せる |
| 抑制ノートをモデル基準（opus / fable の役だけ）にする | 開発者 5 箇所からの削除が増えるうえ、Workflow 内での Sonnet のサブエージェント起動を止める手段も失う |
| Fable を使えない環境向けに、モデルを `args` で差し替えられるようにする | 依頼の範囲を超える。README に「Fable を利用できるアカウント・環境が必要」と前提を書くにとどめた |

## やらないこと

- `code-reviewer` / `code-reviewer-adversarial` の雛形（opus のまま）、`security-auditor`、`memory-dream` の claude 系レビュワー、`~/.claude/agents/*.md`（`model` 指定なし。メインセッションのモデルを継承する）は対象外。グローバル CLAUDE.md の配分に揃えるかは別途判断する
- `fable` を使えない環境での自動フォールバック。その環境ではレビュー役・QA の起動が失敗し、既存の agent-failed → degrade 経路に入ると想定している（未確認）

## 検証

- Agent ツールで `model: "fable"` のサブエージェントを起動し、transcript のモデルメタが `claude-fable-5-1` であることを確認した（Claude Code v2.1.284）。Workflow の `agent()` に `model: 'fable'` を渡す経路は実測していない
- 雛形のモデル指定数を grep で数え、計画と一致した。resolve は opus 1（設計役）/ sonnet 6（開発者 5 + probe-cleanup）/ fable 8 + `reviewModel` 3、plan は opus 1（plan-editor）+ `reviewModel` 3
- 抑制ノートは resolve で定義 5・適用 15、plan で定義 1・適用 4。適用されていないのは probe-cleanup だけ
- 両スキルの雛形の js ブロック（resolve 5・plan 1）を `node --check` で構文検査し、すべて通過した
- 旧配分の記述（`Opus→Sonnet`・`独立 Sonnet`・`包括ラウンドのみ Opus` など）が両スキルとプロジェクト CLAUDE.md に残っていないことを grep で確認した
- `~/.claude/CLAUDE.md` と `dotfiles/claude/CLAUDE.md` は、パスを正規化した diff で一致した

## リスク

- **コスト**: レビュー役は全ラウンド・並列で Fable になる（包括ラウンドは 3 体 + Judge バッチ）。総トークンと時間は次回の dogfooding で過去の節と比べる
- **Fable のデュアルユース向け安全策**: Breaker（特にレンズ S と雛形 C の監査役）は攻撃シナリオと反例テストを書く。拒否や中断が出ると `breakerDegraded` / `auditFailed` / agent-failed として現れる
- **標準モードの採用判定**: 標準モードには Judge 段がなく、Sonnet の開発者がレビュー指摘の採用・不採用を判定する。採るべき指摘を捨てていないかは、不採用率の変化で確認する
