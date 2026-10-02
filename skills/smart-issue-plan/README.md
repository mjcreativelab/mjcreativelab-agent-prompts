# smart-issue-plan

GitHub Issue の実装計画を作成・更新するスキル。

## 使い方

```
/smart-issue-plan #123
/smart-issue-plan #123 -p パフォーマンスを重視して
/smart-issue-plan #123 --codex-review-loop   # または -cdxrl
/smart-issue-plan #123 --codex-advs-review-loop   # または -cdxarl（敵対的レビュー）
/smart-issue-plan #123 --claude-review-loop   # または -cldrl（Codex 不要）
/smart-issue-plan #123 --claude-adv-review-loop   # または -cldarl（Codex 不要・敵対的レビュー）
```

または「計画立てて」「#123 の実装計画」と伝える。

## オプション

| オプション        | 説明                                       |
| ----------------- | ------------------------------------------ |
| `-p <プロンプト>` | 計画の観点・制約に関する追加指示を渡す     |
| `--codex-review-loop`（`-cdxrl`） | 投稿前に Codex 標準レビューループを実施し、収束後は承認ゲートなしで自動投稿する（Claude Code + Codex プラグイン環境、または Codex CLI ホスト〔本 skill 自体を Codex CLI が実行している場合〕で `codex exec` が使える環境が前提） |
| `--codex-advs-review-loop`（`-cdxarl`） | 投稿前に Claude=Breaker × Codex=Judge の敵対的レビューループを実施する。収束後の自動投稿は標準と同じ |
| `--claude-review-loop`（`-cldrl`） | 投稿前にレビュワーエージェント（Fable。包括ラウンドのみ観点を G1/G2/G3 の 3 グループに分割し並列起動、以降は単発 1 体）による標準計画レビューループを実施する（Codex 不要・Claude Code の Workflow ツール前提）。収束後の自動投稿は codex 系と同じ |
| `--claude-adv-review-loop`（`-cldarl`） | 投稿前に独立エージェントの Breaker × Judge（Fable）による敵対的計画レビューループを実施する（Codex 不要・Workflow ツール前提） |

> 認証・個人情報・決済などセキュリティ影響を検出した場合は、フラグ未指定でも敵対的レビューを自動発動する（このときレビューは実施するが、投稿前の承認ゲートは維持する。Codex 不在環境では claude 系で代替する）。旧 `-codex-loop` は `--codex-review-loop` にリネームされ、使用できなくなった。

> 本スキルに `--worktree`（`-wt`）は無い（ブランチも作らず作業ツリーも変更しないため）。ただし `/smart-issue-resolve --worktree` が作った worktree の中でこのスキルを実行した場合は、作業ファイル（context.md / plan.md）を `/tmp` ではなく worktree 内の `.smart-issue-work/plan-issue-<番号>/` に置く（端末の再起動でも失われず、worktree 削除時に中身ごと消える）。メイン作業ツリーで実行した場合は従来どおり OS の一時領域を使う。

## レビューループ（codex 系 / claude 系）

いずれのフラグでも、採用すべき指摘がなくなるまで「レビュー取得 → 妥当性判定（過剰対応チェック） → 修正」をループしてから投稿する（3 ラウンドごとに続行/打ち切り/中止をユーザーに確認）。**返ってきた指摘を採用するか（過剰対応でないか）の判定は、どのモード・系統でもレビュイーが行う**（codex 系はオーケストレーター、claude 系は plan-editor エージェント）。計画レビューはコードの検証を伴わないため、収束後は最終 QA を回さずそのまま投稿する。

**codex 系**（別系統モデル Codex による独立レビュー）:

- **標準（`--codex-review-loop` / `-cdxrl`）**: Codex（Claude Code ホストは `codex:rescue` 経由、Codex CLI ホスト＝本 skill 自体を Codex CLI が実行している場合は `codex exec` の独立セッション）が単独で計画とコードを照合してレビューする
- **敵対的（`--codex-advs-review-loop` / `-cdxarl`）**: Claude=Breaker（設計への攻撃シナリオ・脅威・欠落コントロールの列挙）× Codex=Judge（真の欠陥かノイズかを裁定）の二者構造。計画にはテスト対象のコードがないため、反例テストの代わりに攻撃シナリオを用いる。`code-reviewer-adversarial` スキルは `disable-model-invocation` のため直接委譲できないので、その二者構造をループ内にインライン再現している

**claude 系**（Codex 不要・Claude Code の Workflow ツールで起動する独立エージェント。レビュー役は全ラウンド Fable・plan-editor は Opus。コンテキスト隔離 + 役割分離で独立性を担保）:

- **標準（`--claude-review-loop` / `-cldrl`）**: レビュワーエージェント（Fable / effort high。全ラウンド共通）が計画をレビューする（観点は codex 標準と同一・union 不変）。包括ラウンド（初回セット round 1）のみ、観点を G1（実現可能性 / 手順の妥当性 / テストカバレッジ）/ G2（影響範囲の抜け / リスクの見落とし / データ整合性・性能）/ G3（運用・保守・可用性 / アーキテクチャ境界 / プロジェクト固有基準）の 3 グループに分割した並列レビュワーとして起動し、差分スコープのラウンド 2+ と確認ラウンドは単発 1 体（全 9 観点横断）で実施する（一部グループ失敗は `reviewerDegraded` フラグで伝播）
- **敵対的（`--claude-adv-review-loop` / `-cldarl`）**: Breaker（effort high。包括ラウンドのみ攻撃観点を S/C/O の 3 レンズに分割し並列起動 — union は従来の単一 Breaker と同一。以降のラウンドは単発 1 体〔全攻撃観点横断〕）× Judge（別エージェント / effort high。全レンズの攻撃シナリオを ≤4 件/バッチに分割し並列裁定）の二者構造（モデルはどちらも全ラウンド Fable）。収束は dry-twice（「High/Medium 採用 0」のクリーンなラウンドが連続 2 回。Low のみの採用はクリーン扱い＝重大度フロア）。ラウンド 2 以降は直前ラウンドの採用計画修正が触れた計画節＋影響領域に重点付けする（差分スコープ化）。裁定基準は codex Judge と同等（4 分類・「4 点に答えられるものだけを真の欠陥とする」防御基準）
- 別系統モデルの独立性はないため、認証・決済・データスキーマ・外部 API 変更などの重要変更には codex 系を推奨する

共通:

- **セキュリティ自動発動**: 認証・個人情報・決済などセキュリティ影響を Issue や計画から検出したら、フラグ未指定でも敵対的レビューを自動で有効化する（発動理由を明示）。系統はフラグ明示ならその系統、未指定なら codex 系のレビュー取得経路（`codex:rescue` / `codex exec`）が利用可能時は codex・不能時は claude にフォールバックする。ただしこの自動発動のみのケースでは**投稿前の承認ゲートを維持する**（外部投稿の自動化は明示オプトイン時のみ）
- 収束後の自動投稿（フラグ明示時のみ）はプレビュー承認をスキップする
- 投稿本文の末尾に `🤖 Codex レビュー済み（標準…）` / `🤖 Codex 敵対的レビュー済み（Breaker×Judge…）` / `🤖 Claude レビュー済み（標準…）` / `🤖 Claude 敵対的レビュー済み（Breaker×Judge=独立 Fable…）` を記載する
- レビューが使えない環境（codex 系は `codex:rescue` / `codex exec` いずれも不能、claude 系は Workflow ツール不能）では Claude がレビュー・裁定を代行せず、通常フロー（承認ゲートあり）にフォールバックする（レビュー済み表記なし）

## 動作モード

- **新規作成**: Issue に計画がなければ、コードベースを探索して実装計画を作成する
- **更新**: 既存の計画コメント/Issue がある場合は、現在のコード状態と照合して更新する

計画には **分析時点の commit SHA と依拠した前提**（データ契約・参照ブロック等）を記録するため、後から `/smart-issue-resolve` 側で計画の陳腐化を機械的に検出できる。

計画の出力先は Issue コメント（デフォルト）または新規 Issue「[実装計画]」から選択できる。

## 推奨: 新規セッションで実行する

このスキルは **作業セッションとは別の新規セッションで実行する** ことを推奨する。

- 作業セッションにはコード探索・編集・試行錯誤の履歴が大量に蓄積されており、スキル実行時にそのコンテキストがすべてトークンとして消費される
- 新規セッションなら、スキルが必要な情報（Issue 内容、コードベース探索結果）だけを読み込むため、トークン効率が圧倒的に良い
- **計画作成は実装前に行うため、新規セッションで `/smart-issue-plan` を実行するのがベスト**

## 前提条件

- **git** — 分析時点 SHA の記録（`git rev-parse`）と更新モードでの変更点特定（`git log`）に使用（git が使えない環境では SHA は「未記録」となり、更新モードの差分検出が制限される）
- **GitHub MCP サーバー** — Issue の読み取り・計画コメント投稿に必須（[GitHub MCP plugin](https://github.com/anthropics/claude-code-plugins/tree/main/github)）
- **Codex プラグイン（`codex:rescue` スキル）または Codex CLI（`codex exec`）** — `--codex-review-loop` / `--codex-advs-review-loop` 使用時のみ必須（Claude Code ホストは `codex:rescue` スキル、本 skill 自体を Codex CLI が実行している場合は `codex exec` が使えること。後者はホストのコマンドサンドボックス内では起動できないため、サンドボックス外での昇格実行の承認が必要）。セキュリティ自動発動時は codex 系優先だが、不在なら claude 系（Workflow）へフォールバックする
- **Workflow ツール** — `--claude-review-loop` / `--claude-adv-review-loop` 使用時、および Codex 不在でのセキュリティ自動発動時に必須（Claude Code 固有。利用できない環境では claude 系レビューは実施されず通常フローへ degrade する）。レビュー役の model は `fable`（エイリアス指定で最新の Fable に解決される）のため、Fable を利用できるアカウント・環境が必要
- **AskUserQuestion** — Issue 番号・要件の確認と、レビューループ 3 ラウンドごとの続行確認・仕様未定の確認に使用（Claude Code 拡張。他エージェントではテキスト確認にフォールバック）
