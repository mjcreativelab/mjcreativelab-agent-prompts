# smart-issue-resolve

GitHub Issue ID を受け取り、Issue を読み込んでブランチを作成・チェックアウトし、役割別エージェントのオーケストレーションで実装するスキル。メインセッションはオーケストレーター（対話・進行制御）に徹し、実装・レビューは model / effort を固定した専任エージェントが担う。

## 使い方

```
/smart-issue-resolve #134
/smart-issue-resolve #134 -p テストも書いて
/smart-issue-resolve #134 --worktree              # または -wt（現在の作業ツリーを変更せず git worktree で作業）
/smart-issue-resolve #134 --codex-review-loop     # または -cdxrl
/smart-issue-resolve #134 --codex-advs-review-loop # または -cdxarl（敵対的レビュー・Judge=Codex）
/smart-issue-resolve #134 --claude-review-loop     # または -cldrl（Fable。包括ラウンドは観点3グループ並列）
/smart-issue-resolve #134 --claude-adv-review-loop # または -cldarl（敵対的レビュー・独立 Breaker×Judge。Fable）
```

または「Issue #134 やって」「#42 に取り掛かる」と伝える。

## オプション

| オプション        | 説明                                     |
| ----------------- | ---------------------------------------- |
| `-p <プロンプト>` | 作業に関する追加指示（実装方針・制約等） |
| `--worktree`（`-wt`） | 現在の作業ツリーを変更せず、git worktree に分離した作業ディレクトリでブランチ作成から実装まで行う。worktree の作成とセッション切り替えは Claude Code の EnterWorktree ツールに任せる（`git worktree add` は使わない）。ディレクトリは `.claude/worktrees/<ブランチ名の "/" を "+" に置換した値>`、ブランチはツールが付ける自動生成名を規約どおりの名前へリネームする。未コミット変更があっても stash せず現在の作業ツリーに残したまま着手できる。完了後もセッションは worktree に留まる（`ExitWorktree` は本スキルからは呼ばない。ただしセッション終了時に keep / remove を尋ねられ、remove を選ぶと worktree ディレクトリ**とそのブランチ**が削除される — 作業を残すなら keep）。マージ後のクリーンアップとしての worktree・ブランチ削除は `/smart-git-sync` に任せる。作業ファイル（context.md / impl-notes.md / diff.md 等）は `/tmp` ではなく worktree 内の `.smart-issue-work/resolve-issue-<番号>/` に置かれ、端末の再起動でも失われない（`info/exclude` 登録済みでレビュー対象 diff を汚さず、worktree 削除時に中身ごと消える） |
| `--codex-review-loop`（`-cdxrl`） | 実装後に Codex 標準レビューループを実施し、収束後にコミット・PR 作成まで自動で行う（Claude Code + Codex プラグイン環境、または Codex CLI ホスト〔本 skill 自体を Codex CLI が実行している場合〕で `codex exec` が使える環境が前提） |
| `--codex-advs-review-loop`（`-cdxarl`） | Breaker（独立 Fable）× Codex=Judge の敵対的レビューループ。収束後の自動コミット・PR は標準と同じ |
| `--claude-review-loop`（`-cldrl`） | レビュワーエージェント（Fable。包括ラウンドのみ観点を G1/G2/G3 の 3 グループに分割し並列起動、以降は単発 1 体）による標準レビューループ（Codex 不要）。収束後の自動コミット・PR は codex 系と同じ |
| `--claude-adv-review-loop`（`-cldarl`） | 独立エージェントの Breaker × Judge（Fable）による敵対的レビューループ（Codex 不要）。収束後の自動コミット・PR は同上 |

> 複数指定時は adversarial > standard。モード同格で codex 系と claude 系が競合した場合は codex を優先する（別系統モデルの独立性がより高い）。認証・個人情報・決済などセキュリティ影響を検出した場合は、フラグ未指定でも敵対的レビューを自動発動する（Codex 不在環境では claude 系で代替。このときレビューは実施するが、コミット・PR の自動実行は行わない）。旧 `-codex-loop` は `--codex-review-loop` にリネームされ、使用できなくなった。

## 役割とモデル

| 役割 | model / effort | 責務 |
|------|----------------|------|
| オーケストレーター | メインセッション（Opus 推奨） | Issue 読取り・計画確認・ブランチ操作・context.md 作成・Workflow 起動・ループ制御・コミット/PR |
| 設計役 | opus / max | 計画が無い/粗い場合の設計方針確定 |
| 設計レビュー役 | fable / max | 実装後の設計整合・保守性・可用性レビュー |
| 開発者 | sonnet / high | 実装（調査→ベースライン→実装→動作確認）とレビュー指摘の採用判定・修正（レビュイー） |
| 独立 QA | fable / high | 自己申告に依存しないテスト・lint の独立実行、受け入れ基準検証、自動コミット前の最終ゲート |
| レビュワー / Judge（claude 系）・Breaker（両系統の敵対） | fable / high（codex 敵対 Breaker〔雛形 C〕も同じ） | コンテキスト隔離での diff レビュー / 裁定 / 反例生成（Breaker は codex 敵対モードでも使う。包括ラウンドのみ claude 標準レビュワーは観点を G1/G2/G3 の 3 グループに、claude 敵対 Breaker は攻撃観点を S/C/O の 3 レンズに分割して並列起動し以降は単発 1 体、Judge は反例を ≤4 件/バッチに分割し並列裁定） |
| セキュリティ監査役 | fable / high | セキュリティ自動発動時に STRIDE・認可・データフロー観点を敵対的レビューへ注入（claude 系はレンズ S の Breaker に統合・codex 系は独立エージェント） |
| レビュワー / Judge（codex 系） | Codex（別系統モデル） | Claude Code ホストは `codex:rescue` 経由、Codex CLI ホストは `codex exec` の独立セッションでレビュー・裁定 |

model はエイリアス指定（環境で利用可能な最新の同系統モデルに解決）。effort を指定できるのは Workflow ツールの `agent()` のみのため、エージェント起動はすべて Workflow ツールで行う。

## フロー

1. Issue を読み取り、内容を把握する
2. 既存の実装計画（`/smart-issue-plan` が作成したコメント or `[実装計画]` Issue）があれば参照し、計画記録の分析時点 SHA と最新デフォルトブランチの差分から陳腐化を検出する（古ければ計画更新を提案）
3. 作業ツリーの状態を確認する（未コミット変更は識別可能なメッセージ付きで stash。`--worktree`/`-wt` 指定時は現在の作業ツリーに触れないため stash 不要）
4. Issue に基づいたブランチを作成・チェックアウトする（`--worktree`/`-wt` 指定時は EnterWorktree で worktree の作成とセッション切り替えを一括して行い、自動生成されたブランチ名を規約どおりの名前にリネームする。既存ブランチを使う場合は worktree 内で checkout し、不要になった自動生成ブランチを削除する）
5. プロジェクト固有基準を収集し、作業ディレクトリに context.md（要件・計画・テスト方針・基準）を書き出す（worktree 内で作業している場合は worktree 内の `.smart-issue-work/resolve-issue-<番号>/`、メイン作業ツリーでは OS の一時領域）
6. 実装 Workflow を起動する: 設計役（計画が無い/粗い場合）→ 開発者（ベースライン→実装→動作確認）→ 独立 QA（不合格なら開発者が修正、最大 2 回）→ 設計レビュー役の事後レビュー（設計整合・保守性・可用性）→ 反映 → QA 再確認
7. レビューループ指定時（またはセキュリティ自動発動時）はレビューループへ。それ以外は変更サマリを提示して `/smart-commit` の使用を提案する（勝手にコミット・push しない）

## レビューループ（codex 系 / claude 系）

いずれのフラグでも、採用すべき指摘がなくなるまで「レビュー取得 → 妥当性判定（過剰対応チェック） → 修正 → テスト再実行」をループする（3 ラウンドごとに続行/打ち切り/中止をユーザーに確認）。**返ってきた指摘を採用するか（過剰対応でないか）の判定は、どのモードでもレビュイーの開発者エージェントが行う**。

- **codex 標準（`-cdxrl`）**: Codex（Claude Code ホストは `codex:rescue` 経由、Codex CLI ホスト＝本 skill 自体を Codex CLI が実行している場合は `codex exec` の独立セッション）が単独で diff をレビューする
- **codex 敵対（`-cdxarl`）**: Breaker（独立 Fable エージェント。実装文脈から隔離）× Codex=Judge（真の欠陥かノイズかを裁定）の二者構造。Workflow が使えない環境ではメインセッションが Breaker を代行する（従来動作）
- **claude 標準（`-cldrl`）**: レビュワーエージェント（Fable / effort high。全ラウンド共通）が diff をレビューする（観点は codex 標準と同一・union 不変）。包括ラウンド（初回セット round 1）のみ、観点を G1（仕様充足 / バグ / テストカバレッジ）/ G2（回帰 / データ整合性・性能 / 実装レベルの危険箇所）/ G3（運用・保守・可用性 / アーキテクチャ境界 / プロジェクト固有基準）の 3 グループに分割した並列レビュワーとして起動し、差分スコープのラウンド 2+ と確認ラウンドは単発 1 体（全 9 観点横断）で実施する（敵対 Breaker のレンズ分割と同型。一部グループ失敗は `reviewerDegraded` フラグで伝播）
- **claude 敵対（`-cldarl`）**: Breaker × Judge を**別々の**エージェントが担う（モデルは全ラウンド Fable）。Breaker は包括ラウンドのみ攻撃観点を S（セキュリティ）/ C（正確性・データ）/ O（運用・保守）の 3 レンズに分割した並列エージェント（各 effort high。観点の union は従来の単一 Breaker と同一）として起動し、以降のラウンドは単発 1 体（全攻撃観点横断）で実施する。Judge は全レンズの反例を ≤4 件/バッチに分割し並列裁定（effort high。単一 Judge が多数シナリオの照合で無進捗ウォッチドッグにストールするのを防ぐ）。収束は dry-twice（「High/Medium 採用 0」のクリーンなラウンドが連続 2 回。Low のみの採用はクリーン扱い＝重大度フロア）。ラウンド 2 以降は直前ラウンドの採用修正差分に重点付けする（差分スコープ化）。裁定基準は codex Judge と同等。独立性はコンテキスト隔離 + 役割分離で担保（別系統モデルではないため、認証・決済・データスキーマ・外部 API などの重要変更には codex 系を推奨）
- **セキュリティ自動発動**: 認証・個人情報・決済などセキュリティ影響を Issue や変更ファイルから検出したら、フラグ未指定でも敵対的レビューを自動で有効化する（発動理由を明示。Codex 不在なら claude 系で代替）。ただしこの自動発動のみのケースでは**コミット・PR は自動実行せず**、従来の完了案内に切り替える（外部副作用の自動化は明示オプトイン時のみ）
- claude 系は 1 セット（最大 3 ラウンド）を 1 つの Workflow で実行し、3 ラウンドごとの続行確認はセット間にオーケストレーターが行う（サブエージェントはユーザーに質問できないため）
- claude 系のレビュー役（レビュワー / Breaker / Judge）は diff を各自で `git diff` せず、作業ディレクトリのレビュー正本 `diff.md` を読む（生成はセット起動前がオーケストレーター、ラウンド境界が開発者エージェント）。プロンプトに埋め込んだ期待スタンプ（対象ラウンド）と一致しない・ファイルが無い場合は自前の git 取得へフォールバックする（鮮度ガード）。リポジトリ実コードとの照合は従来どおり必須で、**独立 QA は diff.md に依存せず自分で git を実行する**
- 敵対モードの裁定「仕様未定」（仕様が曖昧で要確認の指摘）は、対話できないエージェントに握り潰させず、オーケストレーターが AskUserQuestion でユーザーに確認して確定内容を context.md に反映する
- 収束後の自動コミット・PR（フラグ明示時のみ）の前に、**独立 QA の最終ゲート**を通す（不合格なら自動コミットを中止して相談）。`smart-commit` / `smart-pr` は `disable-model-invocation` のため、コミット・push は `git`、PR 作成は GitHub MCP（不在時は `gh`）で直接実行する。機密ファイル警告・pre-commit hook・behind 時のマージ確認などの安全系は維持する
- 自動作成する PR のタイトル・本文は `smart-pr` と同じ形式にする（タイトル: `<type>(<scope>): <日本語説明>` 70 文字以内、本文: `assets/pr-template.md` の標準構成 / 簡易構成を変更の性質で選択）。テンプレートは `smart-pr` の同名ファイルの複製（スキル間ファイル参照ができないための意図的な二重化）
- PR 本文に `🤖 Codex レビュー済み（…）` / `🤖 Claude レビュー済み（…）` / `🤖 Claude 敵対的レビュー済み（Breaker×Judge=独立 Fable…）` を記載する（標準構成なら `## 備考`、簡易構成なら `## レビュアー向け補足`）
- レビュー取得経路（`codex:rescue` / `codex exec`）が使えない環境では Claude がレビュー・裁定を代行せず、従来の完了案内（コミット・PR は手動）にフォールバックする（レビュー済み表記なし）。ただしセキュリティ自動発動のケースに限り claude 敵対レビューで代替する。claude 系が使えない（Workflow なし）場合も同様に代行せずフォールバックする
- 実装とは独立に敵対的レビューだけ行いたい場合は `/code-reviewer-adversarial` を直接使う
- claude 系レビューのレビュワー・Breaker・Judge プロンプトは `code-reviewer`（`--isolated`）・`code-reviewer-adversarial`（`--claude-judge`）へも移植されている（`smart-issue-plan` の `sip-plan-review-set` も同骨格の変種）。観点・裁定基準を変えるときは CLAUDE.md「スキル改修時の注意」の同期対象一覧（4 スキル）をすべて同期する

## 関連スキル

- `/smart-issue-plan` — 実装計画のみ作成する。計画を先に立てたいときに使う
- `/smart-commit` — 本スキル完了後のコミット作成（レビューループのフラグ明示時は自動で git/gh 直呼びに切り替わるため、手動起動は非フラグ時の経路）
- `/smart-pr` — PR の作成・更新（同上）
- `/code-reviewer-adversarial` — 実装から独立して敵対的レビューだけ回したいときに直接使う
- `/codex:adversarial-review` — Codex 単独の敵対レビューをコード diff に単発でかけたいときに直接使う（Codex プラグイン付属。対象は git diff のみで計画テキストは対象外。本スキルのループには `disable-model-invocation` のため組み込めない）
- `/smart-git-sync` — `--worktree`/`-wt` で作った worktree がマージ済みになったあと、ブランチと紐づく worktree をまとめて削除するときに使う

## 推奨: 新規セッションで実行する

このスキルは **新規セッションで実行する** ことを推奨する。

- Issue の読み取り → ブランチ作成 → 実装まで一貫して行うため、クリーンなコンテキストで開始するのが効率的
- **新しいタスクに取り掛かるとき、新規セッションで `/smart-issue-resolve #123` を実行するのがベスト**

## 前提条件

- **git** — ブランチ作成・チェックアウトに使用
- **GitHub MCP サーバー** — Issue の読み取りに必須（[GitHub MCP plugin](https://github.com/anthropics/claude-code-plugins/tree/main/github)）
- **EnterWorktree ツール（Claude Code 本体機能）** — `--worktree`/`-wt` 使用時に必須。worktree の作成もこのツールに任せる（手動 `git worktree add` は upstream tracking の設定で共有 `.git/config` へ書き込み、sandbox を有効にしたプロジェクトで失敗するという報告があるため使わない。ただし worktree 作成時の checkout が `Operation not permitted` で拒否される症状はこの経路変更では解消しない）。利用できない環境（他エージェント）・`EnterWorktree` が失敗した場合は通常のブランチ作成にフォールグレードする。既に linked worktree 内にいるセッションではフォールグレードせず、メイン作業ツリーへ戻ってからの再実行を促して停止する（他 Issue の作業ツリーを変更しないため）
- **Workflow ツール（Claude Code 本体機能）** — 役割別エージェントのオーケストレーションと claude 系レビューループに必須。model / effort の明示指定（設計役 = opus/max、開発者 = sonnet/high、レビュワー・Breaker・Judge・独立 QA = fable/high 等）は Workflow の `agent()` でのみ可能。model はエイリアス指定のため、開発者の `sonnet` を Sonnet 5.5 に解決させるには **Claude Code v2.1.284 以上**が必要（それ未満では Sonnet 5 で動く）。レビュー役・QA は `fable` を使うため、Fable を利用できるアカウント・環境が必要。利用できない環境ではメインセッションの単一セッション実装に degrade する（claude 系レビューループは利用不可）
- **Codex プラグイン（`codex:rescue` スキル）または Codex CLI（`codex exec`）** — `--codex-review-loop` / `--codex-advs-review-loop` 使用時に必須（Claude Code ホストは `codex:rescue` スキル、本 skill 自体を Codex CLI が実行している場合は `codex exec` が使えること。後者はホストのコマンドサンドボックス内では起動できないため、サンドボックス外での昇格実行の承認が必要）。セキュリティ自動発動時は第一候補（不在なら claude 系で代替）
- **git + GitHub MCP（または gh）** — レビューループ収束後の自動コミット・PR 作成に使用（コミット・push は git、PR 作成は GitHub MCP を優先。`smart-commit` / `smart-pr` は `disable-model-invocation` のため自動呼び出し不可。手動起動は従来どおり可能）
- **AskUserQuestion** — Issue 番号未指定時の確認、およびレビューループ 3 ラウンドごとの続行/打ち切り/中止の確認に使用（Claude Code 拡張。他エージェントではテキスト確認にフォールバック）
