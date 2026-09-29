---
name: smart-issue-resolve
description: >
  GitHub Issue ID を受け取り、Issue を読み込んでブランチを作成・チェックアウトし、実装に着手する。
  既存の実装計画（smart-issue-plan が作成したコメント or `[実装計画]` Issue）があれば参照する。
  実装は役割別エージェント（設計役・開発者=Opus・独立 QA）のオーケストレーションで行う
  （Claude Code の Workflow ツール前提。利用できない環境は単一セッション実装に degrade）。
  作業完了後に smart-commit の使用を提案する（勝手にコミット・push はしない）。
  ユーザーが「Issue やって」「#123 に取り掛かる」「/smart-issue-resolve #123」と言ったら起動する。
  smart-issue-plan（計画のみ作成）とは別物。実装まで踏み込むときに使う。
  --worktree（-wt）を付けると、現在の作業ツリーを変更せず git worktree（EnterWorktree）に分離した作業ディレクトリでブランチ作成から実装まで行う。
  --codex-review-loop（-cdxrl）を付けると実装後に Codex レビューループを実施し、収束後にコミット・PR 作成まで自動で行う。
  --codex-advs-review-loop（-cdxarl）は Breaker（独立 Sonnet）× Codex=Judge の敵対的レビューループを回す。
  --claude-review-loop（-cldrl）はレビュワーエージェント（包括ラウンドのみ Opus で観点を G1/G2/G3 の 3 グループに分割し並列起動、以降は Sonnet の単発 1 体）による標準レビューループ、
  --claude-adv-review-loop（-cldarl）は独立エージェントの Breaker × Judge（包括ラウンドのみ Opus・以降は Sonnet）による敵対的レビューループを回す（Codex 不要）。
  認証・個人情報・決済などセキュリティ影響を検出した場合は、フラグ未指定でも敵対的レビューを自動発動する（Codex 不在環境では claude 系で代替）。
disable-model-invocation: true
argument-hint: "#issue-number [-p 追加指示] [-wt|--worktree] [--codex-review-loop|-cdxrl] [--codex-advs-review-loop|-cdxarl] [--claude-review-loop|-cldrl] [--claude-adv-review-loop|-cldarl]"
allowed-tools: Read, Bash, Glob, Grep, Edit, Write, AskUserQuestion, Skill, Workflow, EnterWorktree
---

# Smart Issue Resolve

GitHub Issue を起点に、ブランチ作成 → 役割別エージェントによる実装 → 完了案内（レビューループ指定時は収束後のコミット・PR 作成）までを行う。

メインセッションは**オーケストレーター**として対話と進行制御に徹し、実装・レビューは model / effort を固定した専任エージェントが担う:

| 役割 | 実行主体 | model / effort | 責務 |
|------|---------|----------------|------|
| オーケストレーター | メインセッション | セッション設定 | 手順 1〜5 の対話、context.md の作成、claude 系レビューセット起動前の diff.md 生成、Workflow 起動、ループ制御と 3 ラウンドごとの確認、コミット・PR |
| 設計役 | Workflow エージェント | opus / max | 計画が無い・粗い場合の設計方針確定。実装後の設計整合・保守性・可用性レビューを兼任 |
| 開発者 | Workflow エージェント | opus / max | 手順 6 の実装フロー。レビュー指摘の採用 / 不採用判定と修正（レビュイー）。claude 系ではラウンド境界で diff.md を再生成 |
| 独立 QA | Workflow エージェント | sonnet / high | 開発者の自己申告に依存しないテスト・lint の独立実行と受け入れ基準検証。自動コミット前の最終ゲート（diff.md に依存せず自分で git を実行する） |
| レビュワー（claude 標準） | Workflow エージェント | opus / high（包括ラウンド）・sonnet / high（以降のラウンド） | diff レビュー（codex 標準と同一観点。包括ラウンド〔初回セット round 1〕のみ観点を G1/G2/G3 の 3 グループに分割し並列起動、以降のラウンドは単発 1 体〔全 9 観点横断〕。diff は正本ファイル `{作業Dir}/diff.md` を読む） |
| Breaker / Judge（敵対） | Workflow エージェント | opus / high（包括ラウンド）・sonnet / high（以降のラウンド。codex 系 Breaker〔雛形 C〕は全ラウンド sonnet / high） | 反例生成（Breaker・high。claude 系は包括ラウンドのみ攻撃観点を S/C/O の 3 レンズに分割し並列起動、以降は単発 1 体）と裁定（Judge・high。Breaker の反例を ≤4 件/バッチに分割し並列裁定）。コンテキスト隔離で実装文脈から独立（claude 系の diff は `{作業Dir}/diff.md` を読む） |
| セキュリティ監査役 | Workflow エージェント | opus / high（codex 系〔雛形 C〕のみ sonnet / high） | セキュリティ自動発動時に STRIDE・認可・データフローの観点を敵対的レビューへ注入（claude 系〔雛形 B〕はレンズ S の Breaker に統合され初回ラウンドで監査を内蔵実施・codex 系〔雛形 C〕は独立エージェント） |
| レビュワー / Judge（codex 系） | Claude Code ホストは codex:rescue、Codex CLI ホストは codex exec | -（別系統モデル） | Codex によるレビュー・裁定 |

- model はエイリアス指定（環境で利用可能な最新の同系統モデルに解決される。`sonnet` が Sonnet 5.5 に解決されるのは Claude Code v2.1.284 以降で、それ未満では Sonnet 5 になる）。レビュー役を包括ラウンドのみ Opus・以降の繰り返しラウンドを Sonnet とする配分は、Sonnet 5.5 のモデル選定ガイド（繰り返し実行する定義の明確なレビューは Sonnet、慎重な判断を要する複雑な作業は Opus）に基づく（Issue #142）。effort を明示指定できるのは Workflow ツールの `agent()` のみのため、エージェント起動はすべて **Workflow ツール**で行う（本スキルの指示による呼び出しは Workflow の明示オプトインに該当する）
- **Workflow ツールが使えない環境**（他エージェント・旧バージョン）では、オーケストレーションせずメインセッションが実装フローを直接実施する（従来動作への degradation。claude 系レビューループは利用不可 → フォールバック参照）

エージェントプロンプト・Workflow スクリプト雛形: [references/agent-orchestration.md](references/agent-orchestration.md)（雛形 A〜E。以下「雛形」はこのファイルを指す）

## 引数の解析

`$ARGUMENTS` を以下のルールで解析する:

- レビューループのフラグ（位置は問わない。該当トークンは除去する）:
  - `--codex-review-loop` または `-cdxrl` → `{レビューモード}` = `standard`、`{レビュー系統}` = `codex`
  - `--codex-advs-review-loop` または `-cdxarl` → `{レビューモード}` = `adversarial`、`{レビュー系統}` = `codex`
  - `--claude-review-loop` または `-cldrl` → `{レビューモード}` = `standard`、`{レビュー系統}` = `claude`
  - `--claude-adv-review-loop` または `-cldarl` → `{レビューモード}` = `adversarial`、`{レビュー系統}` = `claude`
  - 複数指定時: `adversarial` を優先し（より強いレビュー）、`{レビュー系統}` は adversarial 側のフラグに従う。モードが同格で系統だけ競合する場合（例: `-cdxrl -cldrl`）は `codex` を優先し（別系統モデルの独立性がより高い）、その旨を 1 行通知する
  - どれも無ければ `{レビューモード}` は `off`
  - いずれかのフラグが明示指定された場合は `{ループ明示}` = true を立てる（収束後のコミット・PR 自動実行の可否に使う）
  - 旧 `-codex-loop`（ハイフン 1 つ）を検出した場合は、`--codex-review-loop`（`-cdxrl`）／敵対的レビューなら `--codex-advs-review-loop`（`-cdxarl`）にリネームされた旨を案内して処理を止め、再指定を促す（旧フラグを Issue 番号の一部として解釈しない）
- worktree フラグ（位置は問わない。レビューループのフラグと同じパスで該当トークンを除去する。`-p` の前後分割より前に処理する — 後回しにすると `-p` の追加指示に紛れ込む）:
  - `--worktree` または `-wt` → `{worktree}` = true（現在の作業ツリーを変更せず、git worktree に分離した作業ディレクトリでブランチ作成から実装まで行う。詳細は手順 3・5）
  - 無ければ `{worktree}` = false（既定。従来どおり現在の作業ツリーで直接ブランチを作成する）
- `-p` より前の部分 → Issue 番号（`#` は除去）
- `-p` より後の部分 → `{プロンプト}`（実装方針・制約に関する追加指示）
- `-p` がない場合 → 残り全体を Issue 番号として扱い、`{プロンプト}` は空
- Issue 番号が未指定の場合 → AskUserQuestion で Issue 番号を確認する

例: `/smart-issue-resolve #42 -p テストも書いて` → Issue 番号: 42、プロンプト: 「テストも書いて」
例: `/smart-issue-resolve #42 --codex-review-loop` → レビューモード: standard、系統: codex
例: `/smart-issue-resolve #42 -cdxarl` → レビューモード: adversarial、系統: codex
例: `/smart-issue-resolve #42 -cldarl` → レビューモード: adversarial、系統: claude
例: `/smart-issue-resolve #42 -wt -cldrl` → worktree モードで着手し、claude 標準レビューループも実施

`{レビューモード}` が `off` でも、手順 6 の後にセキュリティ影響を検出した場合は `adversarial` に自動昇格する（「レビューモードの確定」参照）。

## ツール選択

GitHub API 操作には **GitHub MCP ツール**を優先する（`issue_read`, `search_issues`, `add_issue_comment` 等）。`gh` CLI との混在を避ける。コードベース探索には Glob, Grep, Read を使用する。エージェント起動には Workflow ツールを使用する（Agent ツールは effort を指定できないため使わない）。

## 手順

### 1. Issue の読み取り

引数から抽出した Issue 番号で `issue_read` を呼ぶ。以下に該当する場合は通知して終了:

- Issue が存在しない、またはクローズ済み
- Pull Request（`issue_read` の `pull_request` フィールドあり）— PR は本スキルの対象外
- Issue 本文が空でラベルも無い — 要件を判断できないため、ユーザーに内容を確認してから進める

コンテキストに残すのは **タイトル・本文（要件・受け入れ基準部分）・ラベル** のみ。他のフィールド（イベント履歴、関係の薄いコメント等）は破棄する。本文が長い場合は要件・受け入れ基準だけ抽出する。

### 2. 既存の実装計画の確認

smart-issue-plan が作成した計画があれば、実装前に参照する。

- Issue のコメントに「## 実装計画」を含むものがないか `issue_read` のコメント一覧から確認する
- `search_issues` で「[実装計画] <タイトルのキーワード>」を検索する

**レスポンスの絞り込み**（コンテキスト圧迫回避）:
- `issue_read` のコメント一覧からは、「## 実装計画」を含むコメント本文のみ保持する（他コメント・イベント履歴は破棄）
- `search_issues` の結果は各ヒットの URL・タイトル・作成日のみ保持する（本文は該当 Issue を開くときに再取得）

計画が見つかった場合は **実装手順・影響範囲・リスク・分析時点 SHA・依拠した前提** のセクションをコンテキストに残し、以降の実装で参照する。続いて以下の手順で計画の陳腐化を検出する。

**計画の陳腐化チェック**:

計画の「分析時点」欄に記録された SHA を基準に、計画が古くなっていないかを機械的に確認する。

1. **計画言及ファイルの抽出** — 「影響範囲」テーブルと「依拠した前提」に記載された **実ファイルパス／ディレクトリ** を対象にする。抽象モジュール名はそのまま使わず、対応するパスに読み替える
2. **比較基準は最新のデフォルトブランチ** — `git fetch` でリモート参照を更新し（作業ツリーには影響しない軽量操作）、デフォルトブランチ（`git symbolic-ref refs/remotes/origin/HEAD` で判別。例 `origin/main`）を基準にする。ローカル HEAD は実装者が別ブランチ・古い状態にいる可能性があるため使わない
3. **差分の確認**:
   - **SHA が記録され `git cat-file -e <記録SHA>` で解決できる場合** → `git log <記録SHA>..origin/<default> -- <計画言及ファイル>` を実行する。出力が **ある**（＝計画作成後に計画言及ファイルへ変更が入った）なら「計画が古い可能性あり」とみなし、`/smart-issue-plan #<番号>` での更新をデフォルトで提案する。出力が空なら計画は有効として実装に進む
   - **SHA が未記録、または解決できない（shallow clone 等）場合** → 従来のファイル存在チェック（計画言及ファイルが存在するか）を行ったうえで、「SHA 検証不能のため計画更新を推奨」と伝える（黙って最新扱いにしない）
4. 計画言及ファイルに触れない無関係なコミットでは陳腐化提案をしない — 着手スキルなので過剰な中断を避ける

`git` が使えない環境では本チェックをスキップしてよい（クロスツール配布の degradation）。

### 3. 作業ツリーの状態確認

現在のブランチ・未コミット変更・ローカルブランチ一覧を取得。

**`{worktree}` = true の場合** — 手順 5 で新規作成する worktree に新しいブランチを切るため、現在の作業ツリーには一切手を加えない。未コミット変更があってもそのまま現在の作業ツリーに残ればよく、stash は不要（本手順の stash 判定・退避フローは `{worktree}` = false のときのみ適用する）。現在どのブランチにいるかも worktree 作成には影響しないため確認を省略してよい。

**`{worktree}` = false の場合（既定）**:

- **未コミット変更あり** → ユーザーに通知、続行なら `git stash push -m "smart-issue-resolve: <元ブランチ名> の退避"` で **メッセージ付き** stash する（手順 5 の分岐判定に使う）
- **デフォルトブランチ以外にいる** → 別作業中の可能性をユーザーに確認

stash する場合は **元ブランチ名・変更内容の概要** をユーザーに提示し、「現 Issue の作業の続き」「無関係な作業の退避」のどちらかを確認してフラグを記録する（手順 5 の分岐に使う）。判別がつかない場合は「無関係な作業の退避」として扱う（誤って pop してマージ衝突を起こすリスクを避ける）。

### 4. ブランチ名の決定

プロジェクト側に独自のブランチ命名規則（CLAUDE.md・AGENTS.md・README 等で明示されている場合）があればそちらを優先する。規則がなければ以下のデフォルトを使う:

**フォーマット**: `{type}/issue-{番号}-{説明}`

| ラベル/内容 | type | 例 |
|-------------|------|----|
| bug | `fix` | `fix/issue-134-login-error` |
| feature / enhancement | `feature` | `feature/issue-42-add-oauth` |
| refactoring | `refactor` | `refactor/issue-78-extract-utils` |
| documentation | `docs` | `docs/issue-55-update-api-docs` |
| test | `test` | `test/issue-61-add-unit-tests` |
| その他 | `chore` | `chore/issue-99-update-deps` |

**ブランチ名のルール**:
- **kebab-case**（小文字 + ハイフン区切り）、ASCII 英数字 + ハイフン + スラッシュのみ（日本語・全角文字は使わない）
- `{説明}` は英語、3〜5 語以内
- 本スキルでは Issue 番号が引数で確定しているため `issue-{番号}` は必ず含める
- マイルストーン分割がある場合は末尾に `-m{番号}` を付ける（例: `feature/issue-42-add-oauth-m1`）

**既存ブランチの扱い**:
- 同じ Issue 番号のブランチがローカル・リモートに **1 件** 既存 → チェックアウトか新規作成かユーザーに確認する
- **複数件** 既存（マイルストーン分割等で `-m1` `-m2` に分かれている場合） → 一覧をユーザーに提示し、対象ブランチをチェックアウトするか新規作成するか選択させる

### 5. ブランチ作成・チェックアウト（または worktree 作成）

ユーザー承認後、デフォルトブランチを最新にする（`git fetch` でリモート参照を更新する — worktree モードの `EnterWorktree` は既定で `origin/<デフォルトブランチ>` から分岐するため、これを省くと古い参照のままブランチを作成してしまう）。デフォルトブランチは `git symbolic-ref refs/remotes/origin/HEAD` で取得する（`origin/main` / `origin/master` / `origin/develop` 等を自動判別）。取得できない場合はユーザーに確認する。

**`{worktree}` = false の場合（既定）** — 現在の作業ツリーでブランチを作成・チェックアウトする:

デフォルトブランチを最新にしてから新規ブランチを作成する。stash の復元は手順 3 で記録したフラグに基づいて分岐する:

- **現 Issue の作業の続き** → 新ブランチ上で `git stash pop`
- **無関係な作業の退避** → 新ブランチ上では pop せず stash に残す。「元のブランチに戻ってから `git stash list` / `git stash pop` で復元してください」と案内する

**`{worktree}` = true の場合** — 現在の作業ツリーには触れず、worktree の**作成とセッション切り替えを `EnterWorktree` に任せる**（`git worktree add` を自分で実行しない）。手動作成は upstream tracking の設定で共有 `.git/config` へ書き込むため、sandbox を有効にしたプロジェクトでは `unable to write upstream branch configuration` で失敗するという報告がある。`EnterWorktree` が作るブランチには upstream tracking が設定されない（実測確認済み）ため、この書き込みを起点にした失敗モードは踏まない。一方、**worktree 作成時のファイル展開（checkout）が `Operation not permitted` で拒否されて worktree ごとロールバックする、という報告への対処にはならない** — checkout は `EnterWorktree` 経由でも同じく実行されるため、この経路変更では解消しない（sandbox 有効環境での実挙動は未実測）。その場合は項目 4 のゲートで検出して `-wt` を諦める:

1. **入れ子の回避** — `git rev-parse --git-dir` と `git rev-parse --git-common-dir` の出力が**異なれば** linked worktree の中にいる（手順 6-2 と同じ判定）。その場合は**ここで停止する**（`{worktree}` = false へ倒さない — その worktree は別 Issue の作業ツリーでありうるため、そこでブランチを作成・stash するのは `-wt` の「現在の作業ツリーを変更しない」契約に反する）。「現在 linked worktree（`git rev-parse --show-toplevel` の値）の中にいるため worktree を作成できません。`ExitWorktree({ action: "keep" })` でメイン作業ツリーへ戻ってから再実行してください」とユーザーに伝えて終了する
2. **除外設定の登録（worktree 作成前）** — `EnterWorktree` は `.claude/worktrees/` を無視登録しないため、作成前に登録する（未登録のまま作成すると、そのディレクトリが現在の作業ツリーの `git status` に `??` として現れる）。`git rev-parse --show-toplevel` で作業ツリーのルート（`{ツリールート}`）を取得し、`git -C "{ツリールート}" check-ignore -q .claude/worktrees/`（**末尾のスラッシュ必須** — 無いとディレクトリ未作成の間は誤判定する）が失敗する（＝まだ無視されていない）場合、`$(git rev-parse --git-common-dir)/info/exclude` に `.claude/worktrees/` を追記する（`git rev-parse --git-common-dir` は main tree・linked worktree のどちらから実行しても常に共有 `.git` を指す絶対パス〔または main tree からの相対 `.git`〕を返す。linked worktree では `.git` はファイルであり直接パスを組み立てると失敗するため必須。リポジトリの追跡対象 `.gitignore` は変更しない・ローカル限定の除外）
3. **既存ブランチをチェックアウトする場合の事前確認** — `git worktree list --porcelain` に `branch refs/heads/<ブランチ名>` があれば、そのブランチは現在の作業ツリーか他の worktree で既にチェックアウト中で worktree 化できない。「既に別の作業ツリーでチェックアウト中のため worktree 化できません。`-wt` を外すか、そちらの作業ツリー側で作業してください」とユーザーに伝えて終了する（**worktree を作る前に判定する** — 作成後に判明すると空の worktree が残る）
4. **worktree の作成 + セッションの切り替え** — `EnterWorktree({ name: "<ブランチ名>" })` を呼ぶ。worktree ディレクトリ（`.claude/worktrees/<ブランチ名の "/" を "+" に置換した値>`）の作成とセッションの切り替えが 1 手で完結する。以降の手順（context.md 作成・Workflow 起動・レビューループ・コミット・PR）はすべてこの worktree 内で実行される
   - `name` に使えるのは「`/` 区切りの各セグメントが英数字・ドット・アンダースコア・ハイフンのみ、全体 64 文字以内」（手順 4 のブランチ名ルールを満たしていれば問題ない）
   - 分岐元は `worktree.baseRef` 設定に従う（既定 `fresh` = `origin/<デフォルトブランチ>`）。`head` に設定されたプロジェクトでは現在の HEAD から分岐するため、レビュー diff の基準（`origin/<デフォルトブランチ>...HEAD`）に Issue と無関係なコミットが混ざる。作成後に `git log --oneline origin/<デフォルトブランチ>..HEAD` が空であることを確認し、空でなければユーザーに伝えて判断を仰ぐ
   - 同名の worktree が既にある場合はエラーにならず**既存の worktree を再利用（resume）**して切り替わる（前回セッションのコミットが残っている可能性がある）。作り直したい場合はユーザーに確認する
   - **切り替えの確認（項目 5 以降のゲート）** — 呼び出し後に `git rev-parse --git-dir` と `git rev-parse --git-common-dir` が**異なること**（= linked worktree に切り替わっている）を確認する。同じ値なら切り替えが起きていないため、**項目 5 以降（`git branch -m` / `git checkout` / `git update-ref -d`）を実行しない** — メイン作業ツリーの current branch をリネーム・削除してしまう。`EnterWorktree` の呼び出し自体が失敗した場合（sandbox での checkout 拒否等）も同様に項目 5 へ進まず、いずれの場合も項目 7 と同じフォールグレード（手順 3 の未コミット変更確認・stash 判定を行ったうえで `{worktree}` = false 経路）に倒し、その旨をユーザーに伝える
5. **ブランチ名の調整** — `EnterWorktree` が作るブランチ名は `worktree-<name の "/" を "+" に置換した値>`（例: `fix/issue-140-x` → `worktree-fix+issue-140-x`）でプロジェクトの命名規則に合わない:
   - **新規ブランチの場合** → worktree 内で `git branch -m <ブランチ名>` を実行し、`git branch --show-current` が `<ブランチ名>` を返すことを確認する（sandbox 環境では `.git/config` への書き込みが拒否されリネームが部分的にしか通らない可能性があるという報告があるため、反映を確認してから先へ進む。想定と違えばユーザーに伝えて判断を仰ぐ）
   - **既存ブランチをチェックアウトする場合** → リネームせず worktree 内で `git checkout <ブランチ名>` に切り替える（`EnterWorktree` は新規ブランチしか作れないため、作成済み worktree 内の通常の checkout として扱う）。切り替え後、`git branch --show-current` が `<ブランチ名>` を返すことを確認してから、使われなくなった自動生成ブランチを `git update-ref -d refs/heads/worktree-<...>` で削除する（**確認は必須** — `update-ref` は plumbing で安全確認を持たず、checkout が失敗したまま実行すると current branch の ref を消して HEAD 不在にしてしまう〔実測確認済み〕。それでも `git branch -d` は squash merge 運用のリポジトリで "not fully merged" と拒否されることがあり、`git branch -D` は環境によって破壊的操作としてブロックされることがあるため、削除自体は plumbing コマンドで行う）
6. `EnterWorktree` で worktree に入った場合（項目 4・5 の経路）は、手順 3 で未コミット変更を検出していても stash・pop は行わない（元の作業ツリーにそのまま残る）
7. **フォールグレード**（`EnterWorktree` ツールが利用できない環境〔Claude Code 以外のホスト〕、または項目 4 のゲートで切り替え未成立・呼び出し失敗を検出した場合）では `{worktree}` を無視し、手順 3 の未コミット変更確認・stash 判定を行ったうえで `{worktree}` = false と同じ手順にフォールグレードする。フォールグレードした旨をユーザーに伝える（項目 1 の linked worktree 内セッションはこの経路に**含めない** — 停止する）

### 6. 作業の実行（オーケストレーション）

開発者エージェントはユーザーと対話できないため、**Issue 内容の不明点はこの時点までにオーケストレーターが解消しておく**（不明確なまま Workflow を起動しない）。

1. **レビュー基準・規約の収集** — プロジェクト固有のコーディング規約・レビュー基準を収集する（実装エージェントとレビューの両方に注入するため）。汎用観点だけではドメイン固有の欠陥（例: アーキテクチャ層責務・トランザクション/DB・性能・テストカバレッジ基準）を取りこぼす。ソース:
   - プロジェクトの CLAUDE.md / AGENTS.md に記載の規約
   - リポジトリ内のコーディングルール集を Glob で探索する（`**/rules/*.md`・`**/guidelines/*.md`・`docs/` 配下の規約など）。Issue・変更予定ファイルのドメインに関連するものだけを Read する（例: `ddd-*` / `*architecture*` / `db-*` / `api-*` / `performance*` / `test-coverage*` / `security*`）
   - 参照した実装計画（手順 2）の「依拠した前提」が指す基準
   - 見つからなければ「なし」として進める（degradation）
2. **作業ディレクトリの作成** — `{作業Dir}` を作成する。配置は**いま操作している作業ツリー**で分岐する（判定: `git rev-parse --git-dir` と `git rev-parse --git-common-dir` の出力が**異なれば** linked worktree にいる〔linked では前者が `<共有.git>/worktrees/<名前>`、後者が `<共有.git>`〕。メイン作業ツリーでは両方とも同じ値〔通常 `.git`〕を返す。`--show-toplevel` とメインルートの文字列比較は使わない — `/tmp` と `/private/tmp` のようなパス正規化差で誤判定し、静かに `/tmp` 配置へ戻ってしまう。`{worktreeパス}` 自体は `git rev-parse --show-toplevel` で取る）:
   - **linked worktree の中にいる場合**（`-wt` で作った / 既にその中にいるセッション） → `{worktreeパス}/.smart-issue-work/resolve-issue-<番号>/` を使う。`/tmp` と違い端末の再起動で作業ファイルが失われない。作成前に `git -C "{worktreeパス}" check-ignore -q .smart-issue-work/`（**末尾のスラッシュ必須** — 無いとディレクトリ未作成の間は誤判定する）が失敗する（＝まだ無視されていない）場合、`$(git rev-parse --git-common-dir)/info/exclude` に `.smart-issue-work/` を追記する（追跡対象の `.gitignore` は変更しない・ローカル限定の除外）。exclude 済みなら `git status` にも `gen-diff.sh` の未追跡ファイル一覧にも出ないためレビュー対象 diff を汚さず、`git worktree remove`（`--force` なし）も阻害せず worktree 削除時に中身ごと消える。既に同名ディレクトリが存在する場合（前回の中断・再起動等）は黙って再利用せず、再利用するか作り直すかユーザーに確認する（前セッションの `diff.md` が残るとラウンドスタンプの鮮度ガードが誤作動する）
   - **メイン作業ツリーの場合（既定）** → 従来どおり `mktemp -d "${TMPDIR:-/tmp}/sir-issue-<番号>.XXXXXX"` で作成する（OS の一時領域。メイン作業ツリーに置くと誰も掃除しないため、揮発領域のままにする）
   - いずれの場合もスキル側で削除手順は持たない（worktree 内は `/smart-git-sync` の worktree 削除に、`/tmp` は OS に任せる）。`{作業Dir}` はコードの worktree（`.claude/worktrees/<ブランチ名の "/" を "+" に置換した値>`）そのものとは別物で、混同しない
   - **worktree 内に置く場所を `.claude/` 配下にしない**（`.smart-issue-work/` を worktree 直下に置く理由）。sandbox を有効にしたプロジェクトは `.claude` を `denyWrite` に入れているのが通例で、`.claude/` 配下に作ると作成・更新が `Operation not permitted` で落ちる
   - **sandbox で作成・書き込みが拒否された場合はフォールバックする** — `mktemp -d "${TMPDIR:-/tmp}/sir-issue-<番号>.XXXXXX"`（それも拒否される隔離セッションではセッション scratchpad 配下）に作り直し、「作業ファイルは揮発領域にあるため端末再起動・セッション切替で失われる」旨をユーザーに伝える。また worktree 隔離セッションの Bash は `$TMPDIR` / `$PWD` / `$(...)` のようなパスに解決される展開を拒否することがある。その場合は `git rev-parse --git-common-dir` を単独で実行して値を得てから、`info/exclude` への追記や `-C` 指定にリテラル絶対パスを書く
   - **永続するのは「端末の再起動・セッション切替」に対してであって、worktree の削除に対してではない** — `-wt` で作った worktree は `EnterWorktree` が作成したものなので `ExitWorktree({ action: "remove" })` の対象になり、セッション終了時にも keep / remove を尋ねられる。remove で worktree ディレクトリ（とそのブランチ）が消えれば `{作業Dir}` も一緒に失われる（未コミットファイル・元ブランチに無いコミットが残っている場合は `discard_changes` を指定しない限りツール側が削除を拒否するが、その防御に頼らない）。これは意図した設計で、掃除が要らない代わりに進行中の作業ファイルも失われる。長時間のレビューループでは各セット終了時に WIP コミットを挟み、次ラウンド以降も必要な判断記録は `docs/implementation-notes/` などリポジトリ内の成果物に残させる

   あわせて本スキルの [assets/gen-diff.sh](assets/gen-diff.sh)（Claude Code では `${CLAUDE_SKILL_DIR}/assets/gen-diff.sh` が実体のパスに展開される）を `{作業Dir}/gen-diff.sh` へコピーする（claude 系レビューループのレビュー正本 `diff.md` の生成に使う。開発者エージェントは `{作業Dir}` しか知らないため、スキル本体のパスに依存させない。コピーできない環境ではレビュー役が自前の git 取得にフォールバックする）
3. **context.md の書き出し** — 雛形の書式で `{作業Dir}/context.md` を書く（Issue 要件・実装計画要約・`-p` 指示・ブランチ / diff 基準・テスト方針・プロジェクト固有基準）。テスト方針には関連スコープの実行コマンドを具体化して書く。テストが特定できない / フレームワークが不明な場合は、手動確認方針（再現手順・確認すべき画面や API レスポンス等）をユーザーに提示・合意してから書く
4. **ゲート** — `{作業Dir}/context.md` が存在しない場合は Workflow を起動しない（作成に戻る）
5. **実装 Workflow の起動** — 雛形 A（sir-implement）を起動する。Workflow の起動（雛形 A〜E 共通）では、起動直前に `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` を実測した開始日時を `startedAt` として `args` に含める（開始ログ表示用。グローバルルールの開始日時表示と同じ実測値を使い回してよい）。`needDesign` は「計画が無い、または計画の実装手順が具体ファイルに落ちていない」場合に true。内部フロー: 設計役（条件付き）→ 開発者 → 独立 QA（不合格なら開発者が修正、最大 2 回）→ 設計役の事後レビュー（設計整合・保守性・可用性）→ 開発者の採用判定・反映 → QA 再確認
6. **結果の扱い**:
   - `status: ok` → 「レビューモードの確定」へ
   - `status: qa-failed` → QA の指摘を提示してユーザーに相談する（勝手に次へ進まない）
   - `status: agent-failed` → 1 回だけ `resumeFromRunId` で再開を試み、それでも失敗なら degraded 実装に切り替える

**実装フロー**（開発者エージェントのプロンプトに内蔵。Workflow が使えない環境ではメインセッションがこの流れを直接実施する = degraded 実装）:

1. **計画の参照** — 手順 2 で取得した計画（と設計役の design.md）があれば、その実装手順・影響範囲を基準にする
2. **コードベース調査** — 計画がない場合、または計画が粗い場合は、エントリポイント・依存グラフ・既存パターン・境界条件（外部 API・DB スキーマ・lint / 型チェック設定など品質ゲートの制約）の観点で、Issue の要件に関連するファイル・モジュールを特定する（推測ではなく実際のコード構造に基づく）
3. **実装前のベースライン確認** — 関連領域のテストがあれば変更前に一度実行し、既存の失敗と今回の変更による失敗を切り分けられるようにする。全テスト実行は時間がかかるので、関連ディレクトリ・関連モジュールにスコープを絞る
4. **実装** — Issue の要件・受け入れ基準に沿って変更を加える。`-p` の指示も反映する
5. **動作確認** — 実装後に同じスコープのテストを再実行し、既存テストの壊れがないこと・新規要件を満たすことを確認する。手動確認方針を採用した場合は確認結果（実施内容と結果）を完了案内に含める

スコープは Issue 記載内容（と計画があればその範囲）に限定する。degraded 実装でも `{作業Dir}/impl-notes.md`（変更ファイル / 要件対応 / 判断事項 / テスト結果）を書く（レビューループの修正エージェントと完了報告が参照する）。

オーケストレーターがコンテキスト圧縮に遭って Issue 要件や進行状態を失った場合は、`{作業Dir}/context.md` と `impl-notes.md` を読み直して状態を復元してから再開する（誤った前提のまま続行しない）。

実装（Workflow または degraded 実装）が完了した時点で「レビューモードの確定（セキュリティ自動発動）」を評価する。`{レビューモード}` が `off` 以外に確定したらレビューループを実施し、収束（または打ち切りの選択）後は「収束後のコミット・PR 作成」または手順 7 へ。`off` のままなら手順 7 へ。

### 7. 完了案内

> レビューループを実施し、かつ `{ループ明示}` = true の場合は、この手順に代えて「収束後のコミット・PR 作成」の完了報告（PR URL・ループ記録を含む）を行う。セキュリティ自動発動のみでレビューを実施した（`{ループ明示}` = false）場合は、レビュー記録を添えたうえでこの通常の完了案内を行う（コミット・PR は自動実行しない）。

以下のサマリを提示する:

```
作業が完了しました。

## 変更サマリ
- 変更ファイル: <ファイル一覧>
- 実装した要件: <Issue の受け入れ基準に対する対応内容を箇条書きで>
- 動作確認: <開発者エージェントのテスト結果と、独立 QA が実行した検証（コマンドと結果）>
- 設計整合レビュー: <設計役の指摘数と採用 / 不採用（不採用理由）。指摘 0 件ならその旨>
- 作業ディレクトリ: <worktree のパス>（作業ファイル: <worktree のパス>/.smart-issue-work/resolve-issue-<番号>/ — worktree 削除時に一緒に消える）

次のステップ:
1. コミット → `/smart-commit`
2. PR 作成 → `/smart-pr`
```

`{作業Dir}/impl-notes.md` に開発者エージェントが記録した「自分で判断した事項」があれば、ユーザーが把握すべき決定事項として言及する。

「作業ディレクトリ」の行は `{worktree}` = true のときだけテンプレートに含める（false のときは行ごと省く）。`{worktree}` = true の場合、セッションは worktree 内に留まったまま完了する（`ExitWorktree` はユーザーから明示的な指示があるまで本スキルからは呼び出さない）。完了案内には worktree のパスに加えて、元の作業ツリーへ戻るには `ExitWorktree({ action: "keep" })` を使うか新規セッションを開始する旨を明記する。この worktree は `EnterWorktree` が作成したものなので、セッション終了時にも keep / remove を尋ねられる — 作業を残すには **keep** を選ぶ必要がある（remove は worktree ディレクトリ**とそのブランチ**を削除するため、`{作業Dir}` の作業ファイルに加えてローカルブランチも失われる。未コミット変更・元ブランチに無いコミットがある場合は `discard_changes` なしでは拒否される）旨も併記する。マージ後のクリーンアップとして worktree・ブランチを削除するのは `/smart-git-sync` に任せる（remove を選ぶとその前にブランチごと消える）。

degraded 実装（Workflow 不能）の場合は「独立 QA・設計整合レビューは未実施（Workflow 不能）」とサマリに明記し、動作確認欄にはメインセッションが実行したテスト / 手動確認の結果を書く（実行していない検証を記載しない）。

**勝手にコミット・push しない** — ユーザーの明示的指示を待つ（`{ループ明示}` = true の場合のみ、オプション指定を明示的オプトインとみなして「収束後のコミット・PR 作成」を行う。セキュリティ自動発動のみの場合はコミット・PR を自動実行しない）。

## レビューループ（codex 系 / claude 系）

`{レビューモード}` が `off` 以外の場合に実施する。目的は**実装文脈から独立したレビュー**。codex 系は別系統モデル（Codex）が、claude 系はコンテキスト隔離したエージェント（レビュー役〔レビュワー / Breaker / 敵対 Judge バッチ〕は effort high で、包括ラウンドのみ Opus・以降の繰り返しラウンドは Sonnet。開発者 fix は Opus / max。包括ラウンド〔初回セット round 1〕のみ標準レビュワーを G1/G2/G3・敵対 Breaker を S/C/O に分割して並列起動し、以降のラウンドは単発 1 体。敵対 Judge は Breaker 反例を ≤4 件/バッチに分割し並列裁定）がレビュー・裁定を担う。**実装側（オーケストレーター・開発者エージェント）がレビュー・裁定を模擬・代行してはならない**（唯一の例外: codex 敵対モードの degraded 環境における Breaker 代行。裁定者 Judge=Codex の独立性が保たれるため許容する）。

いずれのモード・系統でも、返ってきた指摘に対する **採用 / 不採用（過剰対応かどうか）の判定は、レビュイーである開発者エージェントが行う**（degraded 実装時はメインセッション。この不変則はモード・系統によらず変わらない）。

### レビューモードの確定（セキュリティ自動発動）

実装（Workflow または degraded 実装）が完了した時点で、対象がセキュアな実装を要するかを判定する。次のいずれかに該当すれば「セキュリティ影響あり」とみなす（判断に迷う場合はセキュア側に倒す）:

- Issue のラベル・タイトル・本文が、認証/認可・ログイン・パスワード・トークン/JWT・セッション・暗号/ハッシュ・個人情報(PII)・決済/課金・秘密情報/API キー・OAuth/SSO 等に言及している
- 変更ファイルが、認証・認可・暗号・セッション管理・決済・シークレット/環境変数の取り扱いに関わる

セキュリティ影響ありと判定し、かつ `{レビューモード}` が `off` または `standard` の場合、`{レビューモード}` を `adversarial` に昇格させ、発動理由（検出したシグナル）をユーザーに 1 行で明示する。`{レビュー系統}` は次のとおり決める:

- 系統フラグが明示されている → その系統のまま adversarial へ昇格
- フラグ未指定（`off` からの自動発動） → codex 系のレビュー取得経路（Claude Code ホストの `codex:rescue` / Codex CLI ホストの `codex exec`）のいずれかが利用可能なら `codex`、いずれも利用不能なら `claude`（Workflow 必須）。両方利用不能ならフォールバック参照

> `{ループ明示}` = false（フラグ未指定でセキュリティ検出により発動）の場合、レビューは実施するが **収束後のコミット・PR 自動実行は行わない**（手順 7 の通常完了案内に切り替える）。外部への副作用（push・PR）を伴う自動化は明示オプトイン時のみ。

セキュリティ自動発動時は、敵対的レビューの初回に STRIDE・認可・データフローの監査観点を Breaker に注入する。claude 系（雛形 B は `securityAudit: true`）では**レンズ S の Breaker が監査を内蔵実施**する（初回セット round 1 で STRIDE 監査 → `security-audit.md` 書き出し → セキュリティ break を 1 エージェントで実施。独立の前段監査スロットは持たない）。codex 系（雛形 C のラウンド 1 で同フラグ）は従来どおり独立のセキュリティ監査役エージェントが注入する。いずれも、上で明示した発動理由（検出したシグナル）を `securityReason` として Workflow の `args` に渡す（監査プロンプトに「自動発動の理由」として埋め込まれるため。渡し忘れると理由が `undefined` になる）。監査に失敗した場合（返却の `auditFailed: true`。claude 系はレンズ S が `security-audit.md` を書き出せなかった場合）は Breaker 内蔵のセキュリティ観点のみで続行し、その旨を完了報告に記す。

### ループ手順（共通骨格）

レビュー基準は手順 6-1 で context.md に収集済み（標準・敵対いずれの観点にも「プロジェクト固有基準」として注入される）。

1. **レビュー取得** — `{レビュー系統}` × `{レビューモード}` に応じてレビューを取得する（下記）。レビュー対象は現在ブランチの変更全体（`origin/<デフォルトブランチ>...HEAD` の diff + 未コミットの working tree 変更）
2. **妥当性判定（過剰対応チェック）** — 開発者エージェントが指摘を 1 件ずつ「採用 / 不採用」に分類する:
   - 採用: 仕様未充足・バグ・回帰リスク・実装レベルの危険箇所を根拠付きで正しく突いている指摘
   - 不採用: 妥当性がない、オーバーエンジニアリングを招く、Issue のスコープ外 — 理由を 1 行で記録する（敵対的モードで Judge が「真の欠陥」と裁定した指摘でも、修正が過剰対応になるなら不採用にしてよい）
3. **修正** — 開発者エージェントが採用指摘を実装に反映し、context.md のテスト方針と同じスコープでテストを再実行する（壊れたまま次ラウンドに進まない）
4. **収束判定** — 採用が 0 件ならループ終了（収束）。1 件以上なら手順 5（上限チェック）へ進む（**必ず上限チェックを経由する**。直接手順 1 へ戻らない）。収束・中止でループを抜けるときは、変更セットに残った `.breaker-probe.` ファイルを取り除く（不採用・却下となった反例テストは使い捨て。claude 系の収束時は雛形 B が内蔵実施する）。なお claude 系は雛形 B / `sip-plan-review-set` 内部で **dry-twice 方式**（「指摘 0 / High・Medium 採用 0」のクリーンなラウンドが**連続 2 回**で収束・Low のみの採用は修正しつつクリーン扱い〔重大度フロア。Issue #134〕・1 回目クリーン後は差分スコープを解除したフルスコープの確認ラウンド）を採るため、本手順の「採用 0 件で即収束」は codex 系向けの記述である
5. **上限チェック** — 現在のラウンド数（通算）を確認する:
   - **ラウンド数が 3 の倍数（3, 6, 9, …）に達していない** → ラウンドを +1 して手順 1 に戻る
   - **3 の倍数に達した** → 残りの指摘の要約を提示して AskUserQuestion で確認する:
     - **続行** → ラウンドを +1 して手順 1 に戻る（次の 3 の倍数ラウンドで再度この確認を行う）
     - **打ち切って完了処理へ** → 未収束のまま「収束後のコミット・PR 作成」または手順 7 へ（表記は「未収束で打ち切り」）
     - **中止** → コミット・PR 作成せず、従来の完了案内（手順 7）に切り替える

> claude 系（雛形 B / `sip-plan-review-set`）でセット末尾が `cleanStreak: 1`（クリーン 1 回のまま 3 ラウンド上限に到達）だった場合、残指摘が空でも未収束（連続クリーン確認待ち）として返る。続行時は返却の `cleanStreak` を次セットの `args` に必ず引き継ぎ、次セット round 1 を差分スコープ解除の確認ラウンドとして dry-twice をセット境界を跨いで成立させる（引き継がないと確認ラウンドが失われ収束が 1 クリーンに退化する）。

各ラウンドのモード・指摘数・採用数・不採用理由の要約を記録し、完了報告に含める。

**実行形態**:

- **claude 系** — 骨格 1〜4 の 1 セット（最大 3 ラウンド）を雛形 B（sir-claude-review-set）の Workflow 1 回で実行する（収束時はセット内で最終 QA まで実施して返る）。**新規セットを起動する直前に必ず `bash {作業Dir}/gen-diff.sh origin/<デフォルトブランチ> <startRound>` を実行してレビュー正本 `{作業Dir}/diff.md` を生成する**（初回セット・継続セットのいずれも。生成しないとそのセットの round 1 でレビュー役が全員 git フォールバックに落ちる。ただし `resumeFromRunId` による同一セットの再開では生成しない — 再開後のスクリプトは進行済みの期待スタンプを保持しており、作り直すとスタンプが巻き戻って残りラウンドが不要にフォールバックする）。オーケストレーターは返却（`converged` / `records` / `specQuestions` / `cleanStreak`）を受けて、上限チェック（AskUserQuestion）と裁定「仕様未定」のユーザー確認を行い、確定した仕様は context.md（追加指示）へ追記する（修正が必要になれば未収束として続行）。続行なら `startRound` を +3、`priorSummary` に経緯要約 + 前セット最終ラウンドの採用修正内容（`records` 末尾の `adoptedItems`）を入れ、**返却の `cleanStreak` も引き継いで**同じ scriptPath で再起動する（ラウンド 2 以降の差分スコープと dry-twice の連続クリーン判定をセット跨ぎで連続させるため。再起動前の diff.md 再生成と `startedAt` の再実測も忘れない）
- **codex 系** — オーケストレーターがラウンド単位で回す。レビュー・裁定の取得はホストで分岐する（**Claude Code ホスト**は Skill ツールで `codex:rescue` を呼ぶ従来どおりの経路、**Codex CLI ホスト**＝本 skill 自体を Codex CLI が実行している場合は `codex exec` で独立した新規セッションを起動する経路。詳細は下記「標準モード」「敵対的モード」）。敵対の Breaker は雛形 C、修正は雛形 D で行う。敵対の裁定に「仕様未定」が含まれる場合は、雛形 D に渡す前にオーケストレーターが AskUserQuestion でユーザーに仕様を確認し、確定内容を context.md（追加指示）へ追記する。雛形 D の起動前に、レビュー結果を `{作業Dir}/findings-round-<N>.md` に書き出す（標準: Codex の指摘全件、敵対: 裁定の真の欠陥 + 確定した仕様未定。要約・取捨選択をしない。物理ゲート: このファイルが無ければ起動しない）

#### 標準モード（codex 系: --codex-review-loop）

[assets/codex-review-prompt.md](assets/codex-review-prompt.md) のテンプレートを埋め、レビューを取得する:

- **Claude Code ホスト**（Skill ツールが使える）: Skill ツールで `codex:rescue` を呼び出す
- **Codex CLI ホスト**（本 skill 自体を Codex CLI が実行している。`codex:rescue` は Claude Code 専用のため存在しない）: `codex exec`（非対話・毎回新規セッション）を起動しテンプレートを渡す。起動手順（プロンプトの stdin リダイレクト・`-o` での出力回収・**ホストのサンドボックス外での昇格実行**）は [assets/codex-review-prompt.md](assets/codex-review-prompt.md) の「Codex CLI ホストでの補足」に必ず従う。実装を行っている現在のセッションとは独立した新規セッションでレビューを取得し、同一セッション内で自己レビューを完結させない（独立性が失われるため）

Codex が単独で diff をレビューし、指摘を返す。返った指摘は雛形 D（開発者エージェント。Workflow 不能な degraded 環境ではメインセッションが代行）で判定・反映する。

#### 敵対的モード（codex 系: --codex-advs-review-loop / セキュリティ自動発動）

Breaker（独立 Sonnet エージェント）× Codex=Judge の二者構造でレビューする:

1. **Breaker（雛形 C: sir-codex-breaker）** — 実装文脈から隔離された Sonnet（effort high）エージェントが、反例・攻撃シナリオ・不変条件違反を列挙する（攻撃観点・反例テストの規律はプロンプトに内蔵。反例テストは `.breaker-probe.` 命名の使い捨てとして扱う）。Workflow が使えない環境では、メインセッションが雛形 C の Breaker プロンプト（攻撃観点・反例テストの規律）を自身に適用して代行する（従来動作）
2. **Judge（Codex）** — [assets/codex-judge-prompt.md](assets/codex-judge-prompt.md) のテンプレートに Breaker の反例リストと反例テストの実行結果を埋め、レビューを取得する。**Claude Code ホスト**では Skill ツールで `codex:rescue` を呼び出す。**Codex CLI ホスト**（`codex:rescue` が存在しない）では `codex exec` を起動し、Breaker（雛形 C、または代行しているメインセッション）とは独立した新規セッションで裁定させる（起動手順は [assets/codex-review-prompt.md](assets/codex-review-prompt.md) の「Codex CLI ホストでの補足」に従う）。Codex は各反例を「真の欠陥 / 仕様未定 / 低優先度 / ノイズ」に裁定し、独立にも diff をレビューして追加の真の欠陥を挙げる
3. Judge が「真の欠陥」「仕様未定」に分類した指摘を、共通骨格の手順 2（雛形 D）に渡す

> **共犯化の回避**: Judge（Codex）の裁定を Claude が模擬・代行しない。裁定者（Codex）が別系統モデルであることが codex 系敵対レビューの核。

#### claude 系（--claude-review-loop / --claude-adv-review-loop）

雛形 B（sir-claude-review-set）で実行する。標準モードはレビュワーエージェント（effort high。包括ラウンドは Opus・以降のラウンドは Sonnet）が diff をレビューする（観点は codex 標準と同一・union は不変）。**包括ラウンド（初回セット round 1）のみ**、観点を **G1（仕様充足 / バグ / テストカバレッジ）/ G2（回帰 / データ整合性・性能 / 実装レベルの危険箇所）/ G3（運用・保守・可用性 / アーキテクチャ境界 / プロジェクト固有基準）の 3 グループに分割した並列レビュワー**として起動し、差分スコープのラウンド 2+ と確認ラウンドは**単発 1 体（全 9 観点横断）**で実施する（敵対 Breaker のレンズ分割と同型。グループ間の重複指摘は開発者の採用判定で統合する。一部グループ失敗は `reviewerDegraded` フラグで伝播。Issue #113: トークン・ストール露出の抑制）。敵対的モードは Breaker（effort high）× Judge（**別の**エージェント / effort high）の二者構造（モデルはどちらも包括ラウンドは Opus・以降のラウンドは Sonnet）で、Breaker は**包括ラウンドのみ**攻撃観点を **S（セキュリティ）/ C（正確性・データ）/ O（運用・保守）の 3 レンズに分割した並列エージェント**として起動し、以降のラウンドは単発 1 体（全攻撃観点横断）で実施する（観点の union は従来の単一 Breaker と同一で内容は不変。一部レンズ失敗は `breakerDegraded` フラグで伝播）。Judge は全レンズの反例を集約し ≤4 件/バッチに分割して並列に裁定する（各 Judge の作業量を有界にし、単一 Judge が多数シナリオの照合で無進捗ウォッチドッグにストールするのを防ぐ）。裁定基準は codex Judge と同等（4 分類・「4 点に答えられるものだけを真の欠陥とする」防御基準）。収束は **dry-twice**（「指摘 0 / High・Medium 採用 0」のクリーンなラウンドが連続 2 回で確定。Low のみの採用は修正・テスト済みのままクリーン扱い〔重大度フロア。Issue #134〕。1 回目クリーン後の確認ラウンドは差分スコープを解除したフルスコープで揺らぎ由来の見逃しを拾う）。ラウンド 2 以降の Breaker / レビュワーは直前ラウンドの採用修正差分とその波及範囲を重点対象にする（差分スコープ化。ラウンド 1 と確認ラウンドは全 diff の包括レビューで、重点付けであって抑制ではない。前ラウンドの採用修正が追加したコードへの、さらなる強化・磨き込み要求は指摘にしない）。レビュー指摘・裁定には**軽微指摘フィルタ**を適用する: 実行時挙動・契約・設計判断を変えない細部（識別子 / テスト命名・コメント / docstring / ログ文言・ドキュメント列挙の完全性）は items にせず低優先度として除外する（文言・列挙の完全性が Issue の成果物そのものであるドキュメント改訂系 Issue は対象内。開発者 fix は Low を局所・無リスクの場合のみ最小修正で採用。Issue #134）。

レビュー役（レビュワー / Breaker / Judge）は diff を自分で取得せず、レビュー正本 `{作業Dir}/diff.md` を Read する（各エージェントの `git diff` / `git status` 重複実行を排す。読む範囲はレビュワー / Breaker が全文、Judge は変更ファイル一覧 + 担当バッチの evidence が指す箇所のみ — Judge の有界作業量設計を崩さないため）。生成はオーケストレーター（**新規セットの起動前**・`<対象ラウンド>` = `startRound`。`resumeFromRunId` による同一セット再開時は生成しない）と開発者エージェント（ラウンド境界・`<対象ラウンド>` = 次ラウンド）が `gen-diff.sh` で行う。鮮度ガードとして各レビュープロンプトに期待スタンプ（`対象ラウンド`）を埋め込み、**不一致・ファイル不在・明らかな不整合のときだけ**自前の git 取得へフォールバックさせる（開発者の再生成漏れは安全側に倒れる。再生成失敗は返却の `diffDegraded` で伝播し、完了報告に明記する — 従来動作へ戻るだけなので自動コミットは止めない）。リポジトリ実コードとの照合（該当ファイルの Read・周辺 grep）は従来どおり必須で、diff の抜粋だけで判断させない。**独立 QA は diff.md を使わず自分で git を実行する**（レビュイーの生成物に最終ゲートを依存させない trust model の維持）。詳細は [references/agent-orchestration.md](references/agent-orchestration.md) の「レビュー正本 diff.md」。

> claude 系の独立性は**コンテキスト隔離 + 役割分離**で担保する（レビュワー・Breaker・Judge は実装文脈を持たない fresh エージェント）。codex 系のような別系統モデルの独立性はないため、認証・決済・データスキーマ・外部 API 変更などの重要変更には codex 系を推奨する。

> **同期ノート**: 雛形 B/C のレビュワー・Breaker・Judge プロンプト（レビュー観点・攻撃観点・4 分類裁定基準）は、単体スキル `code-reviewer`（`--isolated`）・`code-reviewer-adversarial`（`--claude-judge`）へ移植済み。観点・裁定基準を変更したら、それらの `references/agent-orchestration.md` も同期する（マスターの同期対象一覧は CLAUDE.md「スキル改修時の注意」。詳細は [references/agent-orchestration.md](references/agent-orchestration.md) の同期ノート）。雛形のエージェントプロンプト・スキーマ description は英語、ユーザーが読む内容（指摘内容・`log()`・カテゴリ enum 値）は日本語で記述する（Issue #122。同期時も英語表現のまま揃える）。Opus 役のプロンプト末尾には共通の英語抑制ノート `RESTRAINT_NOTE`（サブエージェント起動禁止・手順外の追加検証禁止・スコープ維持・出力簡潔化。Opus 5 プロンプトガイド準拠）を `TAIL_NOTE` の直前に付す（同期対象 4 スキルで共通）。

### 収束後のコミット・PR 作成

`{ループ明示}` = true の場合のみ実施する（セキュリティ自動発動のみで発動した場合は手順 7 に切り替える）。`smart-commit` / `smart-pr` は `disable-model-invocation` のため Skill ツールから自動呼び出しできない。ここではコミット・push を `git` で行い、PR 作成・作成者アサインは GitHub MCP（利用不能時は `gh`）で直接行う。プロジェクトの Git 規約に従う（conventional commit・closing keyword は対象 Issue を完全に解決する場合のみ意図的に使用・地の文での偶然の一致による意図しない auto-close は避ける・作成者を自動アサイン。プロジェクト独自規約があればそれを優先）:

1. **最終 QA ゲート** — 自動コミットの前に独立 QA で最終検証する（claude 系の収束時は雛形 B が内蔵実行。codex 系、および claude 系で打ち切りを選んだ場合は雛形 E を 1 回起動する — 起動前に、変更セットに残った `.breaker-probe.` ファイルを取り除いておく。Workflow 不能な degraded 環境では起動できないため省略し、その旨を完了報告に明記する）。`pass: false` なら自動コミット・PR を**中止**し、QA の指摘を提示してユーザーに相談する。claude モードで雛形 B の返却に `judgeDegraded: true`（敵対で未裁定の反例が残る）・`reviewerDegraded: true`（標準で未探索のレビュー観点グループが残る）・`breakerDegraded: true`（敵対で未探索の攻撃レンズが残る）のいずれかが立っている場合も、収束していても自動コミット前にユーザーへ確認する（[references/agent-orchestration.md](references/agent-orchestration.md) の「返却の扱い」参照）
2. **コミット** — 変更を Issue の作業単位でコミットする。コミット前に `git status` で、反例検証用テスト（`.breaker-probe.` を含むファイル。採用欠陥の回帰テスト化済みのものを除く）や一時成果物が変更セットに混ざっていないか確認する。機密ファイルの混入チェック・pre-commit hook 失敗への対応などの安全系確認は省略しない。`--no-verify` は使わない
3. **push・PR 作成** — feature ブランチを `git push -u origin HEAD` で push し（`EnterWorktree` が作るブランチには upstream tracking が設定されないため `-u` を付ける）、PR を作成する。作成者を自動アサインする。タイトル・本文は下記「PR タイトル・本文」に従い、レビュー済み表記を本文に記載する:
   - codex 標準・収束時: `🤖 Codex レビュー済み（標準, N ラウンド, 最終ラウンド採用指摘 0 件）`
   - codex 敵対・収束時: `🤖 Codex 敵対的レビュー済み（Breaker=独立 Sonnet×Judge=Codex, N ラウンド, 最終ラウンド採用指摘 0 件）`
   - claude 標準・収束時: `🤖 Claude レビュー済み（標準, Opus→Sonnet/effort high, N ラウンド, 最終ラウンド採用指摘 0 件）`
   - claude 敵対・収束時: `🤖 Claude 敵対的レビュー済み（Breaker×Judge=独立 Opus→Sonnet, N ラウンド, 最終ラウンド採用指摘 0 件）`
   - 打ち切り時: `🤖 <Codex|Claude> レビュー実施（<standard|adversarial>, N ラウンド, 未収束で打ち切り）`
   - 記載先: 標準構成なら `## 備考`、簡易構成なら `## レビュアー向け補足`
4. **完了報告** — PR URL・変更サマリ・ループ記録（系統, モード, ラウンド数, 各ラウンドの指摘数 / 採用数 / 不採用理由）・最終 QA 結果を提示して終了。`{worktree}` = true の場合は worktree のパスも併記し、元の作業ツリーへ戻るには `ExitWorktree({ action: "keep" })` か新規セッション開始が必要な旨を伝える（PR マージ後の worktree・ブランチ削除は `/smart-git-sync` に任せる）

behind 時のマージ確認・競合対応は履歴に影響するため、自動オプトインの対象外とし通常どおりユーザーに確認する。ユーザーが手動で `/smart-commit` `/smart-pr` を使う経路は従来どおり有効（自動実行時のみ git/gh 直呼びに切り替える）。

#### PR タイトル・本文

`smart-pr` と同じ形式で作成する（PR の見た目を経路によって変えない）。

**タイトル**: `<type>(<scope>): <日本語説明>` — 70 文字以内（`<type>` は feat/fix/docs/refactor/chore/test/perf/style/build/ci）

**本文**: [assets/pr-template.md](assets/pr-template.md) を使用し、変更の性質から構成を選ぶ:

| 構成 | 対象 | 内容 |
|------|------|------|
| **標準構成**（既定） | 機能実装・複数ファイルにまたがる変更・設計判断を含む変更 | 図・表で実装内容を可視化する: クラス / ファイル構成表、主要フローの mermaid シーケンス図（分岐は alt/else）、構成図（mermaid flowchart・任意）、設計判断表（採用した方針 / 未対応 follow-up）、受入条件 ↔ 検証の対応表 |
| **簡易構成** | chore / docs / typo / 依存更新・少量の変更など、レビュワー向けに細かい説明が不要な内容 | 概要・変更内容の箇条書きのみ。**図・表などの要素は不要** |

- 判断に迷う場合は「レビュワーがこの説明なしで diff を読めるか」で決める（読めるなら簡易構成でよい）
- 標準構成でも、各図表は説明価値がある場合のみ使う（埋めるための図表を作らない）
- プロジェクトに PULL_REQUEST_TEMPLATE（`.github/` 配下）がある場合はそのセクション構成を骨格にし、標準構成の図表を対応するセクションへ埋め込む
- 対象 Issue を完全に解決する場合のみ `## 関連 Issue` に `Closes #NN`（部分解決は `Refs #NN`）。他セクションの地の文で close/fix/resolve 系の語を Issue 番号に直接続けない
- 実装ノート・設計スペックを作成した場合は `## 概要` からリンクする
- GitHub MCP の `create_pull_request` に渡す `body` は**実改行**で渡す（`\n` リテラル禁止）

> **同期ノート**: [assets/pr-template.md](assets/pr-template.md) は `smart-pr` の同名ファイルの複製（スキル間ファイル参照ができないため意図的に二重化）。上記の構成選択ルールも `smart-pr` の「7-N. タイトル・本文の生成」と同内容。どちらかを変更したらもう一方も同期する。

### フォールバック

**codex 系（codex:rescue / codex exec が利用不能時）** — 以下のいずれかに該当する場合:

- **呼び出し不能** — レビュー取得の経路（Claude Code ホストの `codex:rescue` / Codex CLI ホストの `codex exec`）が使えない。具体的には: Claude Code ホストで Codex プラグイン未導入・Codex CLI 未設定により `codex:rescue` が呼び出せない、Codex CLI ホストで `codex` バイナリが未インストール・未認証・昇格実行が承認されない（ホストのサンドボックス内では `codex exec` は起動できない）などで `codex exec` の実行に失敗する、またはそれ以外のエージェント環境でいずれの経路も提供されない
- **復旧不能なハング** — 呼び出し済みのレビュー/裁定が返らず（silent death）、[assets/codex-review-prompt.md](assets/codex-review-prompt.md) の「運用ノート」に従った復旧（cancel → `--resume` 再投入）を 2 回試みても完了しない（ハング時は即フォールバックせず、必ず先に復旧を試みる。Codex CLI ホストの `codex exec` はジョブレジストリを持たない同期呼び出しのため、この複雑な復旧手順は対象外 — 同テンプレートの「Codex CLI ホストでの補足」の診断〔stdin リダイレクト漏れ・昇格の欠落・timeout 不足〕を確認して再実行し、解消しなければ「呼び出し不能」に倒す）

該当した場合:

- Claude 自身でレビュー・裁定を代行しない
- **セキュリティ自動発動のケース**（フラグ未指定で発動）では、Workflow が使えるなら `claude` 系の敵対的レビューに切り替えて実施する（従来の「未実施」より安全側。このケースでもコミット・PR は自動実行しない）。Workflow も使えない場合は「セキュリティ影響を検出したがレビュー未実施」と明示して手順 7 に切り替える
- **codex 系フラグが明示されているケース**では、勝手に claude 系へ切り替えない（ユーザーは別系統モデルのレビューを選んでいる）。「Codex レビュー未実施」と明示して従来の完了案内（手順 7）に切り替え、必要なら `-cldrl` / `-cldarl` での再実行を案内する（コミット・PR 作成の自動実行もしない）
- レビュー済み表記は付けない

**claude 系（Workflow 利用不能時）** — Workflow ツールが無い環境、または `agent()` が `resumeFromRunId` での再開後も失敗する場合:

- Claude 自身（メインセッション）でレビュー・裁定を代行しない
- 「Claude レビュー未実施」と明示して従来の完了案内（手順 7）に切り替える（コミット・PR 作成の自動実行もしない）。セキュリティ自動発動起点の場合は「セキュリティ影響を検出したがレビュー未実施」と明示する
- レビュー済み表記は付けない

## 注意事項

- `--no-verify` は使わない / force push はしない / push はしない（例外: `{ループ明示}` = true でレビューループが収束または打ち切りに至ったときのみ「収束後のコミット・PR 作成」で push・PR 作成を行う — オプション指定が明示的オプトイン。セキュリティ自動発動のみの場合は push・PR しない）
- コミット・push を行うのはオーケストレーターの「収束後のコミット・PR 作成」経路のみ。各エージェント（設計役・開発者・QA・レビュワー・Breaker・Judge・監査役）にはコミット・push をさせない（プロンプトに内蔵済み）
- Issue と関係のない変更を混ぜない（混ざった場合は smart-commit 側で分割する旨を案内する）
- 反例テスト（`.breaker-probe.` 命名）を最終的な変更セットに残さない（採用した欠陥の回帰テストは正規の命名・配置に変換する）
- `{worktree}` = true の場合、実装は元の作業ツリーとは別の git worktree（`.claude/worktrees/<ブランチ名の "/" を "+" に置換した値>`）で完結する。worktree の作成は `EnterWorktree` に任せ、`git worktree add` は使わない（手順 5）。`ExitWorktree` は本スキルからは呼び出さない（ユーザーが明示的に指示したときのみ実行するツールのため — 完了後もセッションは worktree に留まる）。worktree・ブランチの削除（マージ後のクリーンアップ）は `/smart-git-sync` に任せる
