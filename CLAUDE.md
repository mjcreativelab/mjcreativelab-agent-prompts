# Agent Skills Monorepo

Claude Code / Codex / Cursor / Gemini など各種エージェント用のスキル集（skills, hooks, rules）の開発リポジトリ。`skills/<skill>/` を直接正本とし、[vercel-labs/skills](https://github.com/vercel-labs/skills) の **`npx skills`** で配布する（クロスツール単一経路。render 工程・中間正本・plugin マニフェストは持たない）。

> **v2.0.0 で配布を `npx skills` に一本化**。旧 Claude Code marketplace（`.claude-plugin/`）と旧 Codex 単一プラグイン配布は撤去済み。

## 標準ワークフロー

1. `skills/<skill>/` を直接編集（SKILL.md / assets / references）
2. `npx skills add ./ --list` で検出を確認（必要に応じてローカル install で動作確認）
3. PR 経由で main にマージ（`/smart-commit main にコミット` で直接コミット可）
4. `/auto-release` で repo-level `v<X.Y.Z>` タグを発行（GitHub Release 作成）

## Git / GitHub 運用

### ブランチ運用

- **main への直接コミットは禁止** — 必ず feature branch を作成し、PR 経由でマージする
- **すべての変更は PR を作成する** — レビューなしで main に直接 push しない
- Commit messages: 日本語 OK、conventional commits を推奨
- コミット・push の直前に `git branch --show-current` で想定ブランチにいるか確認する（並行セッションや手動操作でチェックアウトが切り替わっていることがある）
- 並行セッションの未コミット変更が作業ツリーに残っていることがある。コミットは対象ファイルの明示パス指定で行う（`git add -A` / `git add .` を使わない）

**特例**: `/smart-pr` や `/smart-commit` に `main にコミット` という引数が渡された場合は、main に直接コミット・push してよい。

### ブランチ命名規則

フォーマット: `{type}/issue-{番号}-{簡潔な説明}`

| prefix      | 用途                             |
| ----------- | -------------------------------- |
| `feature/`  | 新機能・機能追加                 |
| `fix/`      | バグ修正                         |
| `refactor/` | リファクタリング（機能変更なし） |
| `docs/`     | ドキュメントのみの変更           |
| `chore/`    | ビルド・CI・依存関係など雑務     |
| `test/`     | テストの追加・修正               |

ルール:
- **kebab-case**（小文字 + ハイフン区切り）を使う
- Issue に紐づく作業は必ず `issue-{番号}` を含める
- 説明部分は **英語・3〜5 語** 程度に収める
- マイルストーン分割がある場合は末尾に `-m{番号}` を付ける
- Issue に紐づかない繰り返し作業（chore/docs/refactor 等）は、末尾にタイムスタンプ `-YYYYMMDD` を付けて一意にする（例: `docs/update-readme-20260326`）

### PR / Issue 作成ルール

- PR・Issue 作成時は作成者を自動アサインする（GitHub MCP の `get_me` または `gh api user` で取得した GitHub ユーザー名を使用）
- GitHub MCP の `create_pull_request` は assignee 未対応のため、PR 作成後に `gh pr edit <番号> --add-assignee <ユーザー名>` で付与する
- Issue 作成時は内容に適した既存ラベルを付与する
- **Issue 作成は GitHub MCP ツール (`issue_write`) を使用する**（ラベル付与・アサインも同ツールで行う）
- GitHub MCP（plugin:github）のツールはセッション初期に未出現のことがある（接続は非同期。ToolSearch 0 件でも未導入と断定しない）。読み取り系は `gh` CLI で代替してよいが、Issue・PR の作成・更新は出現を待って MCP（`issue_write` 等）で行う
- コミット・PR で closing keyword（`Closes`/`Fixes`/`Resolves` + `#NN`）を意図的に使うのは問題ない（対象 Issue を完全に解決する PR で、独立した行として明記する場合）。避けるべきは、Issue に言及する説明文（背景・関連 Issue の言及など）が偶然 closing keyword のパターンと一致し、意図せず auto-close されること — 地の文では「Issue #NN」のような中立表現を使い、close / fix / resolve 系の語を Issue 番号に直接続けない
- PR が Issue を部分的にしか解決しない場合は closing keyword を使わず、マージ後に手動でクローズ判断する（実装済みでも Issue が open のまま残ることがあるため、Issue 着手前にマージ済み PR がその番号を参照していないか確認し、解決済みなら検証コメントを添えてクローズする。例: #69 / #72 は PR #73 で実装済みのまま open だった）

> 上記規則は `smart-commit` / `smart-issue-plan` / `smart-issue-resolve` / `smart-pr` の各 SKILL.md にも内蔵されている（`npx skills` 経由でインストールされた利用者がプロジェクト外ファイルを参照できないため）。本リポジトリで作業する際は CLAUDE.md（本セクション）が一次情報源。

## 記述ルール

- ファイルパスにユーザー名を含めない。ホームディレクトリは `/Users/<name>/` ではなく `~/` で表記する（SKILL.md・コメント・ドキュメント・コミットメッセージ・PR 本文のいずれも同様）
- **本リポジトリは public**。`dotfiles/claude/`（`~/.claude/` のミラー）に社内・非公開の情報（社内プロキシのホスト名、非公開リポジトリのパス、社内 plugin marketplace 名など）を入れない。ミラーを手で編集するときも同じ。`global-config-pull` はパス正規化・非公開 marketplace のサニタイズ・秘密情報チェックでこれを担保する（除外対象の marketplace 名はリポジトリに書かず、ローカル限定の `~/.claude/.config-sync-exclude` に置く）。公開しない指示本文は `~/.claude/private/` に置いて `~/.claude/CLAUDE.md` から `@` import する（`private/` は同期対象外で、ミラーには import 行だけが載る）
- 実装ノートは `docs/implementation-notes/YYYY-MM-DD-<タスクスラグ>.md` に作成し、変更と同じ PR でコミットする。ルート直下に `implementation-notes.md` を残さない（誤コミット防止のため .gitignore で除外済み）
- 設計スペックは `docs/specs/YYYY-MM-DD-<タスクスラグ>-design.md` にコミットする。`docs/superpowers/`（brainstorming / writing-plans の作業成果物置き場）は gitignore 対象のため恒久ドキュメントを置かない

## よく使うコマンド

```bash
# 個人設定（gitignore 対象）: .claude/settings.local.json にパーミッション allowlist など個人環境の設定を記述

# 注意: このホストの npx は mise 管理（素の PATH にない）。mise exec node -- npx skills ... で実行する

# npx skills が検出する skill 一覧（配布の確認）
npx skills add ./ --list

# ローカル install で動作確認（任意のディレクトリで）
npx skills add ./ --skill <skill-name>

# assets/ 内のシェルスクリプト構文チェック
bash -n skills/<skill-name>/assets/<name>.sh

# SKILL.md frontmatter 確認
head -5 skills/<skill-name>/SKILL.md

# ブラウザ操作 MCP が無い環境での HTML 見た目検証（スクリーンショット → PNG を Read で目視確認）
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars --window-size=1600,1000 --screenshot=<out.png> "file://<対象.html>"

# リリース（repo-level v<X.Y.Z> タグの発行 + GitHub Release）
/auto-release

# git pull が "unable to update local ref" で失敗した場合の復旧（マージ直後に発生することがある）
# 注意: reset --hard は未コミット変更を破棄する。実行前に git status --short で clean を確認すること
git update-ref refs/remotes/origin/main <merge-sha> && git reset --hard <merge-sha>

# 誤ったブランチに積んでしまった直近コミットの移し替え（未 push 前提・WIP は保持される。reset --hard は使わない）
git branch <new-branch> <commit-sha> && git reset --keep HEAD~1

# 作業ツリーに global-config-pull 由来などの無関係な未コミット変更が残っている状態で pull・ブランチ作成する場合
# git stash -u で退避 → pull --ff-only → checkout -b <branch> → stash pop → 自分のタスクのファイルだけ git add（-A にしない）

# Workflow 雛形（references/agent-orchestration.md の js ブロック）の構文チェック
# 正規表現・グロブ文字を含むため zsh 直打ちせず bash スクリプトファイル（または bash /dev/stdin）経由で実行する
CHECKDIR=$(mktemp -d) && awk -v dir="$CHECKDIR" '/^```js$/{f=1; n++; next} /^```$/{f=0} f{print > (dir "/block-" n ".js")}' skills/<skill>/references/agent-orchestration.md && for b in "$CHECKDIR"/block-*.js; do { echo 'void (async () => {'; sed 's/^export const meta/const meta/' "$b"; echo '})'; } > "$b.wrapped.js"; mise exec node -- node --check "$b.wrapped.js" && echo "OK: $(basename "$b")"; done
```

## リポジトリ構造

```
skills/                          # 配布 skill の正本（直接編集・npx 標準探索場所）
  # Git ワークフロー系
  smart-commit/                  # 差分を作業単位で分割コミット
  smart-pr/                      # PR 作成・更新の自動化
  smart-git-sync/                # ブランチ同期・整理
  smart-issue-resolve/           # Issue からブランチ作成〜実装（役割別エージェントのオーケストレーション + レビューループ）
  smart-issue-plan/              # Issue の実装計画を作成・更新
  smart-spec-to-pr/              # 要件明確化 → spec 承認 → Issue 起票 → 既存スキル連鎖 → PR 作成の薄い conductor（半自動ハンドオフ・デプロイはスコープ外）
  smart-review/                  # ローカル変更のセルフレビュー
  smart-review-apply/            # レビューフィードバックの適用
  # スキル品質改善・環境構成レビュー
  skill-improver/                # skill-creator 連携 + コンテキスト管理・静的チェック
  empirical-prompt-tuning/       # 新規 subagent 実行でプロンプト・skill を反復チューニング
  claude-code-update-review/     # Claude Code バージョンアップ後の構成レビュー
  # コード開発ライフサイクル支援
  software-architect/            # 要件・スペックから「あるべき設計」を言語化
  code-reviewer/                 # 仕様整合・設計適合・可読性の観点でレビュー
  code-reviewer-adversarial/     # Breaker (Claude) × Judge (Codex) の敵対的レビュー
  security-auditor/              # STRIDE・認可・データフロー等の設計セキュリティ監査
  branch-visualize/              # ブランチ差分の構成図可視化（Mermaid / D2 / HTML 自動選定）
  structure-visualize/           # 指定内容（インフラ構成 / ER / コンポーネント等）の構造を HTML 構成図で可視化
  tech-doc-structuring/          # ADR・技術文書の生成・整形（frontmatter + 固定見出し + 散文のハイブリッド構造。ADR は決定経緯 Deliberation の記録・外部ソース取得に対応）
  # ドキュメント作成
  human-facing-doc-writing/      # 人間が読む文書（Design doc・PR 本文・報告・議事録・手順書など）の新規作成と書き直し（結論を先頭に・代替案は表・定型節を埋めない）
  # 事業企画
  business-ideation/             # ビジネス・サービス案の発散→深掘り→評価（汎用・notes 正本方式）
  # デザイン
  game-ui-design/                # ゲーム UI（HUD / メニュー / コントローラーナビ / スタイル・モーション演出等）の設計観点
  # システムメンテナンス
  disk-space-cleanup/            # ディスク空き容量の確保（開発系キャッシュのスキャン→確認→削除）
  # エージェント記憶管理
  memory-dream/                  # 記憶階層の consolidation（重複・矛盾・陳腐化の除去。Dreams の手動再現）
  agents-md-improver/            # CLAUDE.md / AGENTS.md 等エージェント指示ファイルの監査・改善（品質レポート→承認後更新。公式 claude-md-management の移植）
  agents-md-revise/              # セッションの学びを CLAUDE.md / AGENTS.md 等へ反映（diff 提示→承認後追記。公式 claude-md-management の移植）
internal/                        # 内部 skill（npx 標準探索ルート外・配布対象外）
  auto-release/                  # repo-level タグ発行・GitHub Release（リポジトリ自身のリリース用）
  global-config-pull/            # ~/.claude/ → dotfiles/claude/ へ取り込む
  global-config-push/            # dotfiles/claude/ → ~/.claude/ へ反映する
dotfiles/                        # ホストマシンのグローバル設定（個人管理用・配布対象外）
  claude/                        # ~/.claude/ のミラー（同期対象・除外の正式リストは internal/global-config-pull/SKILL.md）
    CLAUDE.md                    # グローバル Claude Code 指示ファイル
    settings.json                # グローバル設定（hooks・permissions・statusLine・plugins 等）
    statusline-command.sh        # ステータスライン表示スクリプト
    rules/                       # 全セッションで自動的に読み込まれるユーザールール（ふるまい・開発判断ガイドライン）
    hooks/                       # settings.json の hooks から呼ばれるスクリプト（PreCompact 状態保存・Stop 検証チェック）
    agents/                      # カスタムエージェント定義（コンテキスト隔離監査用の code-reviewer / security-auditor）
    .mcp.json                    # グローバル MCP サーバー定義（秘密情報は置かない）
docs/                            # 設計・移行ドキュメント（migration-npx-skills.md、empirical-tuning/、implementation-notes/〔実装ノートのアーカイブ〕等）
.claude/                         # プロジェクト設定（チーム共有）
  settings.json                  # hooks の登録（PostToolUse: npx skills add 後の SKILL.md 安全チェック）
  hooks/skill-safety-check.sh    # 新しく入った SKILL.md の危険パターン検出（~/.agents/skills と プロジェクトの .agents/skills を走査）
```

`skills/<skill>/` が配布 skill の唯一の正本（直接編集）。skill 名はリポジトリ全体で一意。スキルの説明・使用例・前提条件は各 `skills/<skill>/README.md` に書く（npx install でスキルと一緒に配布される）。旧 `packages/`（グループ README）は per-skill README と重複・陳腐化したため v2.0.2 で解体済み。

### 配布の仕組み（単一正本・npx skills）

`skills/<skill>/` が skill の唯一の正本（generated な中間物・render 工程は無い）。配布は `npx skills`（[vercel-labs/skills](https://github.com/vercel-labs/skills)・git tree-SHA ベース）:

- `npx skills add 'mjcreativelab/mjcreativelab-agent-prompts#v<X.Y.Z>' --skill <name> -g` で各エージェントへ install。skill は `.agents/skills/<skill>/` に配置され Claude Code / Codex / Cursor / Gemini CLI / GitHub Copilot 等へ展開される。
- frontmatter は逐語コピーされる（`allowed-tools` 等は標準仕様、`argument-hint` / `disable-model-invocation` は Claude 拡張で他エージェントは無視）。

注意点:

- 内部 skill（リポジトリ自身の運用用。例: `auto-release`）は **`internal/<skill>/` に置く**（npx の標準探索ルート外のため、リモート探索にも `--skill '*'` にも含まれない）。保険として frontmatter に `metadata.internal: true` も付ける（標準ルートに置かれても `--list` から隠れる）。
  - **`skills/` や `.claude/skills/` には置かない**: どちらも npx リモート探索の優先ルートで、internal flag があっても `--skill '*'` で install されてしまう（v2.0.1 では `skills/` に置いていた）。
  - ローカルでこのリポジトリ自身に internal skill（`/auto-release`・`/global-config-pull`・`/global-config-push`）を使う場合は `npx skills add ./internal/<skill> --skill <skill> -g` で global install して呼ぶ（skill 改修時は同コマンドで再 add）。`internal/` は探索ルート外のため、リポジトリに置くだけではスラッシュコマンドとして認識されない。
- 配布先に symlink を作らない。skill 内のサポートファイル参照は `${CLAUDE_SKILL_DIR}` ではなく SKILL.md からの相対パスを基本にすると各エージェントで解決しやすい。
- npx のデフォルト探索は浅い（全階層走査は `--full-depth`）。
- **`@` は ref ではなく skill フィルタ**: `owner/repo@X` の `@X` は `--skill X` 相当（CLI v1.5.9 の source-parser で確認）。バージョン pin は fragment 構文 **`owner/repo#v<X.Y.Z>`**（zsh ではソース全体を引用符で囲む。`#ref@skill` の複合も可）。`#ref` は探索・install に効き、lock（skills-lock.json）に `ref` が記録され `npx skills update` も pin に従う。ただし blob fast path（skills.sh download API）が ref を渡さない既知問題があり（[vercel-labs/skills#1123](https://github.com/vercel-labs/skills/pull/1123) で修正中）、ref の中身の権威確認は `git ls-tree -r origin/<ref> --name-only` で行う。
- 新規 skill 追加時に同期スクリプト・マニフェストは不要（`skills/<skill>/` を直接追加するだけ）。

### タグ運用

- **repo-level `v<X.Y.Z>`**（SemVer）: `npx skills` の pin 用（例: `npx skills add '<repo>#v2.0.2' ...`。`@` ではなく `#`）。`/auto-release` が `skills/` 差分で判定・発行する。バージョンは git タグのみ（バージョンファイル・plugin.json なし）。
- 旧タグ（per-package `<package>@<semver>`・旧 codex `mjcreativelab-claude-plugins@1.0.0`）は不変で残る（履歴）。これらは廃止済みの旧配布経路のもの。

## スキルファイル形式

### ディレクトリ構造

skill は `<name>/SKILL.md` のディレクトリ構造が必須（フラットファイル配置では認識されない）。

```
<skill-name>/
├── SKILL.md          # メイン指示（必須・500行以下推奨）
├── assets/           # テンプレート・スクリプト（出力物の雛形、実行スクリプト）
└── references/       # 参照表・定義（対応表、ルール表など読み取り専用の情報）
```

SKILL.md からサポートファイルを参照して、必要な時だけ読み込むようにする:

```markdown
GitMoji と type の対応: [references/gitmoji-types.md](references/gitmoji-types.md)
```

> user-invocable な機能も `commands/` ではなく `skills/` に統一する（`disable-model-invocation: true` を付けた Skill として追加する）。frontmatter・引数パース・コンテキスト管理の規約を揃えるため。

### frontmatter

```yaml
---
name: my-skill                    # kebab-case、ディレクトリ名と一致させる（Agent Skills 標準）
description: スキルの説明           # 必須。自動読み込み判断・トリガー語に使用
argument-hint: "[issue-number]"    # オートコンプリートに表示するヒント（Claude 拡張）
disable-model-invocation: true     # true → ユーザーの /name でのみ起動（副作用のあるスキル向け・Claude 拡張）
allowed-tools: Read, Grep, Glob    # スキル実行中に許可なしで使えるツール（標準フィールド）
metadata:                          # 任意の拡張枠（標準フィールド）。例: internal: true で npx --list から隠す
  internal: true
---
```

`name` + `description` は必ず記載する（Agent Skills 標準の必須項目）。他はスキルの性質に応じて使用。`argument-hint` / `disable-model-invocation` は Claude 拡張で他エージェントは無視する。

### 文字列置換

SKILL.md 内で使用できる変数:

| 変数 | 用途 |
|------|------|
| `$ARGUMENTS` | スキル呼び出し時の引数全体 |
| `$ARGUMENTS[N]` / `$N` | N番目の引数（0始まり） |
| `${CLAUDE_SKILL_DIR}` | SKILL.md のあるディレクトリのパス（Claude Code 固有） |
| `${CLAUDE_SESSION_ID}` | セッションID |

`${CLAUDE_SKILL_DIR}` は Claude Code 固有で他エージェントでは解決されない。クロスツール配布する skill では SKILL.md からの相対パスを基本にする:

```bash
bash assets/git-sync.sh
```

### 動的コンテキスト注入

`` !`command` `` 構文でスキル読み込み前にシェルコマンドを実行し、結果を埋め込める:

```yaml
- PR diff: !`gh pr diff`
- Changed files: !`gh pr diff --name-only`
```

### クロスツール配布時の frontmatter / token 互換性

`npx skills` は frontmatter を逐語コピーする（正規化しない）。Agent Skills 標準仕様
（<https://agentskills.io/specification>）に沿うため、`name` / `description` は必須、
`allowed-tools` / `license` / `metadata` は標準フィールド。`argument-hint` /
`disable-model-invocation` は Claude 拡張で、他エージェントは**無視**する（reject しない）。

本文中の以下は Claude 固有で、他エージェントでは解決されない（graceful degradation 前提で書く）:

- tools: `AskUserQuestion`, `WebSearch`, `WebFetch`, `Skill`, `Agent`, `Task`
- 変数: `${CLAUDE_SKILL_DIR}`（他エージェントでは未解決。SKILL.md からの相対パスを基本にする）
- skill 参照: `codex:rescue` や `mcp__plugin_github_github__*`（エージェントごとに discovery 機構が異なる）

クロスツールで確実に動かしたい skill は、これらに依存しない表現を選ぶ。Claude 専用前提の
skill（例: `code-reviewer-adversarial` の Codex 連携）は、その旨を description に明記する。

## スキル改修時の注意

- SKILL.md は **500行以下**に保つ。大きなコンテンツは `assets/` または `references/` に切り出す
- GitHub API 操作は MCP ツールに統一する（`gh` CLI との混在を避ける）
- `SKILL.md` と同 skill の `README.md` を同時に更新すること。外部スクリプトがある場合はそれも更新
- スキルの動作が CLAUDE.md の Git/GitHub 運用規則と関連する場合、CLAUDE.md と整合性を保って更新すること（Git 規約はプラグイン外参照不可のため各 SKILL.md にも内蔵されている）
- シェルスクリプト改修後は `bash -n` で構文チェックすること
- SKILL.md にインラインで埋め込むシェルスクリプトに正規表現パターン（`^[[:space:]]` 等）が含まれる場合、zsh がグロブ展開してエラーになる。`bash /dev/stdin` または一時ファイル経由で実行する旨を明記すること
- 複数フェーズのスキルでは「後半を省略すると危険」ではなく「前半が本体」と記述する。escape hatch（スキップ条件）は最小限にし、フェーズ境界にゲート（前提確認）を設ける
- 他スキルに依存するスキルのテスト・レビュー時も、依存先を実際に Skill ツールで呼び出す。SKILL.md を Read して手動で手順を適用する方法では依存スキルの実行が省略され、正しい検証にならない
- 後続フェーズの手順が SKILL.md 内に見えていると、テキストのゲート指示だけではスキップを防げない。後続フェーズの詳細手順は `references/` に切り出し、前フェーズの出力ファイル存在チェックを物理ゲートにする
- スキルの手順に `rm -f` 等の破壊的コマンドを含めない。一時ファイルは OS の一時領域に任せること
- `-p` 等のオプション引数を持つスキルには「引数の解析」セクションを設ける（smart-commit の形式を参照）。同一グループ内で引数パースの書き方を統一すること
- スキル改修時は frontmatter を確認する: 副作用のあるスキルに `disable-model-invocation: true` があるか、`allowed-tools` が設定されているか、`description` に類似スキルとの差別化文言があるか
- **diagram-template.html の系譜**: branch-visualize と structure-visualize の `assets/diagram-template.html` は同系譜の fork（配色・グルーピングの意味論は意図的に異なるため逐語同期はしない）。レイアウトエンジン（レイヤリング・交差削減・ポート分散・ズーム/パン）とインタラクション（hover ハイライト・選択パネル）は逐語で同型のため、片方を修正したらもう片方にも該当するか確認する（areas モード・エリア枠・エッジルーティングは structure-visualize のみで該当なし）
- **structure-visualize テンプレートの検証**: `window.__SV_DEBUG__`（mode / nodes / boxes / size / edges）が恒久の検証ハンドル。改修時は使い捨てハーネス（DOM スタブ + 不変条件検査。再作成手順は `docs/implementation-notes/` の issue-94 / issue-98 ノート参照）で検証し、`SV_EDGE_GATE=1` の厳格モードで「エッジのノード交差 0」を維持する。現在 1005 行（800 行目安の超過は Issue #98 で許容済み）
- **structure-visualize ハーネスの作り方（#94 / #98 のハーネスは未コミット）**: フィクスチャは下流の生成済み HTML から `var GRAPH = ` 以降を波括弧バランスで抽出すると実データで検証できる（古い出力は JS オブジェクトリテラルなので `new Function` で読む）。areas 限定の変更は flow フィクスチャの `__SV_DEBUG__` バイト一致が非影響の最短証明。交差判定はテンプレートの `segHitsRect` を `pad=1` のまま移植してゲートと同値にする
- **エッジラベルも計測対象（#98 の受け入れ基準）**: レイアウトを動かすとラベルが動く。`getBBox()` の実寸で「非端点ノードへの重なり・ラベル同士の衝突・食い込み深さ」を before/after 比較する。件数だけ見ると増減を読み違える（かすり ≤3px と判読不能 >8px を分けて数える）
- **生成済み構成図 HTML は手で改変されていることがある**: 下流プロジェクトの `docs/structure-diagrams/*.html` を参考・不具合報告として渡されたら、現行テンプレートで同じ GRAPH を描き直して挙動差を実測してから前提を置く（prettier 整形済みで textual diff はノイズだらけになるため、`__SV_DEBUG__` の比較が速い）
- **クリック・ホバー等の挙動変更はスクリーンショットで検証できない**: テンプレートに検証用 `<script>` を注入し、`dispatchEvent` で合成イベントを発火 → DOM を assert し、結果を `<pre>` に書いて `--dump-dom` で回収する。マーカー文字列は注入したスクリプト本体にも現れるため取り出しは `head -1`
- **レビュープロンプトの二重化と同期（マスター）**: 敵対レビューの Breaker / Judge プロンプト（攻撃観点・4 分類裁定基準）と標準レビュー観点の骨格は、スキル間ファイル参照不可・Skill 合成不可の制約から意図的に複数スキルへ二重化している。次のいずれかを変更したら対応箇所をすべて同期すること（可読性を観点に含めるか等、各スキルの identity として意図的に異なる部分は除く）:
  - `smart-issue-resolve/references/agent-orchestration.md` — 雛形 B（`sir-claude-review-set`）の reviewerGroupPrompt（標準観点は `REVIEWER_GROUPS` の G1/G2/G3 に分割・union が従来の 9 観点） / breakerLensPrompt（攻撃観点は `LENSES` の S/C/O に分割・union が従来の全観点） / judgeBatchPrompt、雛形 C（`sir-codex-breaker`）の Breaker（レンズ分割せず単発のまま = claude/codex 非対称）
  - `smart-issue-plan/references/agent-orchestration.md` — `sip-plan-review-set`（計画テキスト用に適応した変種。レンズ分割・差分スコープ化は雛形 B と構造同期）
  - `code-reviewer/references/agent-orchestration.md` — `--isolated` の単発隔離レビュー（`cr-isolated-review`）
  - `code-reviewer-adversarial/references/agent-orchestration.md` — `--claude-judge` の Breaker×Judge（`cra-claude-judge`。Judge は ≤4 件/バッチ並列 + miss-finder〔見落とし探索〕分離。Breaker はレンズ分割しない）
  各 SKILL.md にも同期ノートを内蔵している（本項がマスター）。攻撃観点・レビュー観点の**内容**を変えるときは 4 スキルすべてを同期する。レンズ分割・差分スコープ化・Judge バッチ並列化・miss-finder 分離（Issue #107）、**標準レビュワーのグループ分割（`REVIEWER_GROUPS` の G1/G2/G3）・dry-twice 収束（連続 2 クリーンラウンド・`cleanStreak` 引き継ぎ）・レビュー役の opus 化（Issue #111）**、**分割並列の包括ラウンド限定化（初回セット round 1 のみ分割、以降は `REVIEWER_ALL` / `LENS_ALL`〔分割定義の aspects 結合で union 不変を構造的に保証〕の単発 1 体）・Judge バッチの effort high 戻し（Issue #113）**、**diff 正本ファイル化（レビュー役が `{作業Dir}/diff.md` を Read・生成は `assets/gen-diff.sh`・期待スタンプ `diffRound` の鮮度ガード・fix のラウンド境界再生成。Issue #115）**、**収束の重大度フロア + 軽微指摘フィルタ + 発見役 effort high（Issue #134。クリーン判定を「High/Medium 採用 0」に〔`FIX_SCHEMA.adopted[].severity` の echo・`records[].adoptedMajor`。Low のみの採用はクリーン維持〕、発見役・Judge への軽微指摘フィルタ〔実装の挙動・契約・設計判断を変えない細部（命名・文言・列挙完全性）は 低優先度。列挙の完全性が Issue の成果物そのものであるドキュメント改訂系 Issue は除く〕、fix / plan-editor の Low 採用規律〔resolve = 局所・無リスクのみ最小修正 / plan = 原則不採用の意図的非対称〕、差分スコープの「前ラウンド追記への詳細・強化要求禁止」、発見役〔レビュワー / Breaker〕の effort max → high〔fix / plan-editor は編集役のため max 維持〕。cr / cra は単発でループ収束を持たないため Issue #134 は適用外・effort も max 維持）**、**レビュー役のモデル配分（包括ラウンドのみ opus・以降の差分スコープ / 確認 / 継続ラウンドは sonnet。`comprehensive` に追従する `reviewModel` でレビュワー・Breaker・Judge バッチを切り替え〔Judge も同じ規則 — `dismissed` は fix / plan-editor に届かず誤棄却が無音の見落としになるため包括ラウンドは opus〕。resolve 雛形 C の sonnet 役〔監査役・Breaker〕は effort max → high。Sonnet 5.5 のモデル選定ガイド準拠・`sonnet` の 5.5 解決は Claude Code v2.1.284 以降。Issue #142）**は**構造**の変更で、内容同期の対象ではない（構造の同期対象は resolve 雛形 B ↔ sip の 2 者。**ただし diff 正本ファイル化は構造同期の例外＝ resolve 雛形 B 限定のコード専用機構で、sip〔レビュー対象が `plan.md` で既にファイル正本〕・cr / cra〔`{作業Dir}` 機構を持たない〕へは持ち込まない**。cra/cr は単発でグループ分割・dry-twice を持たず opus 化と Judge バッチ effort high〔cra のみ〕を適用〔Issue #142 のモデル配分は単発の包括レビューのみで反復ラウンドを持たないため適用外・opus のまま〕。probe 命名はレンズ固有トークン〔`sec-` / `corr-` / `ops-`・単発ラウンドは `all-`〕を `.breaker-probe.` の**前方外側**に付け、サブストリング `.breaker-probe.` を必ず保持する）。**言語規約（Issue #122）**: 4 スキル全雛形の `agent()` プロンプト・スキーマ description は**英語**で記述し、ユーザーが読む内容（構造化出力の中身・引き継ぎファイル・`log()`・`meta`・カテゴリ enum 値〔`真の欠陥` / `仕様未定` / `低優先度` / `ノイズ`〕）は**日本語**を維持する（プロンプト末尾の共通指示 `TAIL_NOTE` が日本語出力と `nowJst` を指示する）。攻撃観点・レビュー観点の内容同期も英語表現のまま行う。**Opus 抑制ノート**: 4 スキル全雛形で `model: 'opus'` の `agent()` プロンプト末尾（`TAIL_NOTE` 直前）に共通の英語抑制ノート `RESTRAINT_NOTE`（サブエージェント起動・委任の禁止／手順に無い追加検証パスの禁止／依頼スコープの維持／出力・書き出しファイルの簡潔化。[Prompting Claude Opus 5 ガイド](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)準拠）を付し〔resolve 雛形 B / sip の `reviewModel` で opus / sonnet を切り替えるレビュー役にも、プロンプトがラウンド共通のため sonnet ラウンドを含めて付く〕、sonnet 固定の役には付けない（Opus の過剰処理〔サブエージェント多量起動・冗長出力〕の抑制。文言を変えるときは 4 スキルすべてを同期する）。
- **PR 本文テンプレートの二重化と同期**: `smart-issue-resolve/assets/pr-template.md` は `smart-pr/assets/pr-template.md` の複製（スキル間ファイル参照不可のための意図的な二重化。冒頭コメントの参照先行のみ差異）。テンプレート本体と「標準構成 / 簡易構成の選択ルール」（`smart-pr` SKILL.md「7-N. タイトル・本文の生成」 ↔ `smart-issue-resolve` SKILL.md「収束後のコミット・PR 作成 → PR タイトル・本文」）はどちらかを変更したら両方を同期する。`smart-issue-resolve` 側のレビュー済み表記（`🤖 … レビュー済み`）の記載先指定は resolve 固有で同期対象外
- **smart-spec-to-pr のレビューループフラグ転送語彙（結合のみ）**: `smart-spec-to-pr` は `smart-issue-resolve` のレビューループフラグ名（`--claude-review-loop` / `-cldrl`・`--claude-adv-review-loop` / `-cldarl`・`--codex-review-loop` / `-cdxrl`・`--codex-advs-review-loop` / `-cdxarl`）を**転送語彙**として参照している（SKILL.md「引数の解析」・references/pipeline.md「Phase 3b」・README.md「オプション」の 3 箇所）。`smart-issue-resolve` 側でフラグ名を変更したら `smart-spec-to-pr` の転送語彙も更新すること。ただし優先順位・セキュリティ自動昇格の解決ロジックは複製していない（レビュープロンプト二重化のようなフル同期対象ではなく、**フラグ名の結合のみ**）
- **tech-doc-structuring の Deliberation（決定経緯）の分散**: 節名 `## Deliberation（決定に至る経緯）`・時系列ダイジェスト形式（`- YYYY-MM-DD 参加者: 要点と帰結`）・切り出し先命名 `NNNN-<スラグ>-deliberation.md` は SKILL.md・assets/adr-template.md・references/doc-types.md・restructuring-rules.md・deliberation-sources.md・README.md に分散して記載されている。いずれかを変更したら全ファイルを同期すること
- **Workflow サブエージェントは互いにコンテキストを共有できない**: 共有素材（context・diff）はインライン埋め込みでもファイル読みでも「エージェント数 × 内容」のトークンを消費する（渡し方では減らない。削減の主レバーはエージェント数 — Issue #113 の包括ラウンド限定化）。共有素材の受け渡しは `{作業Dir}`（実行単位の名前空間分離・レビュー対象 diff を汚さない・スキル側に削除手順を持たない）のファイル正本で行う（Issue #115 の diff.md 正本化はこの原則の適用）。`{作業Dir}` の配置は「いま操作している作業ツリー」で決まる: linked worktree の中なら `{worktreeパス}/.smart-issue-work/<resolve|plan>-issue-<番号>/`（`info/exclude` に `.smart-issue-work/` を登録して git から隠す。端末の再起動でも失われず、`/smart-git-sync` の `git worktree remove` で worktree ごと消える）、メイン作業ツリーなら従来どおり `mktemp -d` の OS 一時領域（作業ツリー外に置いて汚さない・削除は OS 任せ）。resolve / plan の 2 スキルで同じ規則を使うため、片方を変えたらもう片方も同期する。**worktree 内の置き場所を `.claude/` 配下にしない**（sandbox 有効プロジェクトは `.claude` を `denyWrite` にしているのが通例で作成・更新が `Operation not permitted` になる）。同じ環境では「書き込みは許可されるが既存ファイルの unlink は拒否される」ことがあるため、`{作業Dir}` 内のファイルを置き換えるスクリプト（`gen-diff.sh`）は `mv` 失敗時に切り詰め書き込みへ退避する
- レビュー雛形の速度・精度チューニングは `docs/empirical-tuning/review-loop-speedup.md` が実測台帳（#107 高速化 → #111 精度優先 → #113 再バランス → #115 diff 正本化 → #134 重大度フロア収束 → #142 レビュー役のモデル再配分の経緯・ストール実測・診断を記録）。雛形の性能特性を変える変更や dogfooding 実測はここへ追記する
- `smart-issue-resolve/references/agent-orchestration.md` は 5 雛形が 1 ファイルに共存し、共通 const（`TAIL_NOTE` / `RESTRAINT_NOTE` / `NOW_JST_FIELD` 等）・スキーマ定義が雛形間で逐語重複している。完全一致置換で編集する際は雛形固有の行（例: 雛形 A `const qaPrompt = (extra)` ↔ 雛形 B `const qaPrompt = ()`、fix プロンプトの手順番号差）でアンカーする。共通ノートを複数雛形へ展開したら、grep で定義数・適用数（opus 役のみ等の適用条件込み）を数えて漏れ・過剰適用を検証する
- Workflow ツールで雛形を起動・検証する際、`args` が JSON 文字列で届く環境がある（`typeof args === 'string'`。プローブで実測）。全雛形（resolve 雛形 A〜E・`sip-plan-review-set`・`cr-isolated-review`・`cra-claude-judge`）は meta 直後に正規化シム `args = typeof args === 'string' ? JSON.parse(args) : (args || {})` を内蔵済みのため、起動時に手動でシムを挿入する必要はない（文字列・オブジェクトどちらで届いても本文のトップレベル `args.` 参照が機能する）。「`args` は JSON 値として渡す（文字列化した JSON を渡さない）」契約は維持する
- **Workflow スクリプトは `Date.now()` / `Math.random()` / 引数なし `new Date()` を呼ぶとエラーになる**（resume の再現性を壊すため）。ステップ進行を時刻付きでログする必要がある場合（IDE 拡張は `/workflows` の進捗表示が使えず `log()` が唯一の可視化手段）は、スクリプト側で時刻を生成せず 2 系統で取得する（Issue #122）: (1) **開始日時**はオーケストレーターが起動直前に `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` を実測して `args.startedAt` で渡す（ログ表示専用。`agent()` プロンプトへ埋め込むと resume の (prompt, opts) キャッシュ一致が壊れるため埋め込まない）。(2) **途中経過**は各 `agent()` に「同フォーマットの時刻を実行し `nowJst` として返す」ようプロンプト末尾の共通指示（`TAIL_NOTE`）で指示して schema に持たせ、`agent()` 呼び出し直後に `log(`[${result.nowJst} JST] ...`)` するとともに、直近値を `lastJst` に保持して次のラウンド開始・judge 起動などの開始ログに使う（resolve/plan/code-reviewer/code-reviewer-adversarial の全雛形に実装済み。新しい `agent()` 呼び出しを追加する際も同じ規約に従う。`parallel()` バッチは各結果の `nowJst` の最大値を完了時刻としてログする）。各レビューラウンドの終了時には指摘 / 裁定・採用 / 不採用の内訳と各指摘タイトルを `log()` で出力する（件数上限つき）

## 新規スキル追加手順

1. `skills/<skill-name>/` ディレクトリを作成
2. `SKILL.md` を作成（frontmatter: `name`〔ディレクトリ名と一致〕 + `description`）
3. `skills/<skill-name>/README.md` を作成（スキルの説明・使用例・前提条件。npx install で配布される）
4. この `CLAUDE.md` のリポジトリ構造セクションとルート `README.md` のスキル一覧表にスキルを追記
5. `npx skills add ./ --list` で検出されることを確認
6. リリースは `/auto-release`（新 skill 追加 → マイナーバンプ）

## 変更履歴（パッケージ名・配布経路）

Git タグは変更不可 — 旧タグは旧名のまま残る。グループ（パッケージ）概念は v2.0.2 で解体済み（下記「配布経路の変更履歴」参照）。

### パッケージ名変更履歴

- `mjc-git-workflow` → `mjc-git-workflow-tools`（旧タグ: `mjc-git-workflow@1.1.4` まで）
- `mjc-claude-skill-tool` → `mjc-claude-improver-tools`（旧タグ: `mjc-claude-skill-tool@1.2.1` まで）
- `mjcreativelab-claude-plugins` → `mjcreativelab-agent-plugins`（リポジトリ名・旧 marketplace 名・旧 codex plugin 名を一括リネーム。旧 codex タグ: `mjcreativelab-claude-plugins@1.0.0` まで）
- `mjcreativelab-agent-plugins` → `mjcreativelab-agent-prompts`（リポジトリ名変更。npx 参照パスを更新）

### 配布経路の変更履歴

- ~v1.x: Claude Code marketplace（per-package `.claude-plugin/plugin.json` + `<package>@<semver>` タグ）+ 旧 Codex 単一プラグイン配布（ルート `skills/` + `.codex-plugin/`）。
- v2.0.0〜: `npx skills` 一本化（repo-level `v<X.Y.Z>` タグ）。marketplace・per-package plugin.json・per-package タグ運用は撤去。
- v2.0.2〜: `packages/`（グループ README）を解体。スキル説明は per-skill `skills/<skill>/README.md` に一本化、チューニング記録は `docs/empirical-tuning/` へ移設。内部 skill `auto-release` は `skills/` から `internal/` へ移設（リモート探索・`--skill '*'` からの除外）。
