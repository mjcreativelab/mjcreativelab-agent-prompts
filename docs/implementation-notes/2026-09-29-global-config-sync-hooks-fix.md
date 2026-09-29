# グローバル設定の hook 修正とミラー同期の漏洩対策（2026-09-29）

`/claude-code-update-review`（Claude Code v2.1.284 時点）のレビューで見つかった問題を直し、`dotfiles/claude/` ミラーを実機に揃えた。あわせて、ミラーへの非公開情報の混入経路を `global-config-pull` / `global-config-push` の両スキルで塞いだ。

## 何が起きていたか

- `settings.json` の hook 5 件（.env 保護 2 件・main 保護・破壊的 git 保護・AGENTS.md symlink）が、環境変数 `$TOOL_INPUT` から入力を読んでいた。Claude Code はこの変数を渡さないため、5 件とも常に素通りしていた
  - 根拠は 3 つ。実機で `echo 'hook-probe: git branch -D …'` がブロックされなかった。hook を再現実行すると `TOOL_INPUT` を与えたときだけ exit 2 になった。公式ドキュメントに「command hook の入力は stdin の JSON のみ」と明記されている
- ミラーの `settings.json` が実機より古く、hook 1 件・allow 4 件・`modelSettings` などが欠けていた

## 判断事項

### hook は stdin + jq で読む（5 件）

Slack DM の hook と同じ方式に揃えた。入力を取り出す行だけを変え、判定条件は元のままにした。

### main 保護・破壊的 git 保護は「拒否」ではなく「確認プロンプト」（`permissionDecision: "ask"`）

hook を直すと、今までガードが無効だったために通っていた次の手順がすべて止まる:

- `/auto-release`: main 上で `git push origin v<X.Y.Z>` を実行する
- `smart-commit` / `smart-pr` の「main にコミット」特例
- `/smart-git-sync`: 承認後に `git branch -D` を実行する
- CLAUDE.md の復旧手順 `git reset --hard <merge-sha>`

いずれもユーザーの承認を前提にした手順なので、止めるのではなく確認を求める形にした（ユーザーが選択）。.env 保護の 2 件は拒否（exit 2）のまま。auto モードでも確認プロンプトが出ることは、ユーザーが実機で確認した。

- 却下案 1: 拒否のまま。上の 4 手順が Claude から実行できなくなる
- 却下案 2: 手順ごとに例外パターンを足す。例外条件の保守が必要になる

### AGENTS.md の symlink hook は、既存の AGENTS.md を削除しない

元の実装は、AGENTS.md が通常ファイルのときに `rm -f` してから symlink に置き換えていた。hook が無効だったため、一度も動いたことがない。v2.1.277 から Claude Code は、CLAUDE.md がない場所では AGENTS.md を直接読む。そのため AGENTS.md だけを持つリポジトリで `/init` が CLAUDE.md を書くと、チームの AGENTS.md が消えてしまう。AGENTS.md がない場合だけ symlink を作る形に変えた。

### 非公開の指示本文は `~/.claude/private/` に置き、CLAUDE.md から `@` import する

ユーザーの決定により、CLAUDE.md の Security 節のうち社内ガイドに由来する部分と、その詳細を書いた参照ファイルは、公開ミラーに載せない。

- 採用案: 本文を `~/.claude/private/` に移し、CLAUDE.md には `@~/.claude/private/<ファイル>.md` の 1 行だけを残す。`private/` は pull / push の同期対象外にする。CLAUDE.md の実機とミラーが同じ内容になるので、push で本文が消えることもない。user スコープの CLAUDE.md からの import は確認ダイアログなしで起動時に読み込まれる（公式ドキュメント）
- 却下案: CLAUDE.md の中に `<!-- sync:private -->` の範囲を置き、pull で取り除き、push で実機側の範囲を差し戻す。両スキルにテキスト処理が増えて壊れやすい

副作用: 詳細を書いた参照ファイルは、これまで `~/.claude/rules/` にあったため毎セッション自動で読み込まれていた。`private/` に移ったことで、CLAUDE.md に書かれた「セキュリティ作業のときだけ読む」という本来の意図どおりになった。

### pull / push スキルの漏洩対策

- pull の rsync で `hooks/.logs/`（hook の実行ログ）を除外する。今回の pull では 107 件がミラーにコピーされていた
- `~/.claude` に増えた実行時状態 8 項目（`bridge-spawn`・`daemon`・`daemon.log`・`feedback`・`gh-pr-status-cache.json`・`jobs`・`seed-admin`・`state`）と `private/` を、除外リストと手順 5 の探索パターンに加えた
- 除外ファイル（`.config-sync-exclude`）がないとき、pull はサニタイズを黙って飛ばしていた。今回、非公開 marketplace がミラーに入りかけた。今後は marketplace 一覧を示してユーザーに確認し、確認が済むまで先へ進めない。push にも、除外ファイルがないとマージで非公開 marketplace が消えることを明記した

## 検証

- hook 5 件の再現実行: 22 件すべて期待どおり（拒否・ask・素通り・symlink の作成と保持）
- 実機での確認
  - .env（Bash）の拒否が発火した
  - AGENTS.md の symlink が作られた
  - 破壊的 git 保護が ask を返し、確認プロンプトが表示された
  - Write 経由の .env 保護は、組織配布の permission 設定が先に止めるため、実機では単独で確認できない（二段目の防御）
- import の読み込み: ツールを無効にしたヘッドレスセッションが、import 先にしかない一文を逐語で引用した。`private/` に移した参照ファイルの見出しは「なし」と答えた
- pull の再実行: SKILL.md のコードブロックを抜き出して実行した
  - `bash -n` は OK、実行も exit 0
  - 社内ガイド由来の語句、参照ファイル名、非公開 marketplace 名、`/Users/`、`hooks/.logs` の残存は、いずれも 0 件

## 未対応（別途判断）

- .env 保護（Bash）の正規表現に単語境界がなく、誤ってブロックすることを実測で確認した。次の 4 パターンが該当する:
  - `sed … | grep process.env`
  - リダイレクトの後に `process.env` を検索するコマンド
  - `mcp` を含むコマンドと `.envrc`（`mcp` の中の `cp` に一致する）
  - `used` を含むコマンドと `.env`（`used` の中の `sed` に一致する）
- `~/.claude/rules/` 配下はすべて毎セッション自動で読み込まれる。そのため、グローバル CLAUDE.md の「Opus / Sonnet のときだけ読む」という条件付き読み込みは効いていない
- `.claude/hooks/skill-safety-check.sh` はどの settings にも登録されていない。登録しても、symlink（npx skills の配置）をたどらないため検出できない
