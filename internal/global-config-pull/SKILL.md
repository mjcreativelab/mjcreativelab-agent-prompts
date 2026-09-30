---
name: global-config-pull
description: グローバル Claude 設定（~/.claude/ の CLAUDE.md・settings.json・statusline-command.sh・rules/・hooks/・agents/・commands/・keybindings.json・.mcp.json）をリポジトリの dotfiles/claude/ にコピーして取り込む。「設定を取り込む」「グローバル設定を pull して」と言ったら起動。
disable-model-invocation: true
metadata:
  internal: true
---

# Global Config Pull

`~/.claude/` の設定ファイルを `dotfiles/claude/` にコピーして Git 管理下に取り込む。

## 同期対象

**ファイル（存在するもののみ）:** `CLAUDE.md`・`settings.json`・`statusline-command.sh`・`keybindings.json`・`.mcp.json`

**ディレクトリ（存在するもののみ・ミラー同期＝ソース側での削除も反映）:**

| ディレクトリ | 内容 |
|---|---|
| `rules/` | 全セッションで自動的に読み込まれるユーザールール（`~/.claude/rules/*.md` はモデルを問わず毎回読み込まれる） |
| `hooks/` | settings.json の hooks から呼ばれるスクリプト |
| `agents/` | カスタムエージェント定義 |
| `commands/` | カスタムスラッシュコマンド（レガシー） |

**除外（同期しない）:**

- 秘密情報: `.credentials.json`・`remote-settings.json`（認証情報・リモート管理設定。リポジトリに置かない）・`.config-sync-exclude`（サニタイズ対象の marketplace 名を書くローカル限定ファイル。手順 3 参照）・`.zozo-guidelines-url`（ZOZO社の開発ガイドライン Confluence ページの実 URL。社内情報のためリポジトリに置かない。CLAUDE.md の「ZOZO社の開発ガイドライン準拠」ルールから参照される）
- 非公開の指示: `private/`（公開しない指示本文の置き場。`~/.claude/CLAUDE.md` から `@~/.claude/private/<ファイル>.md` で import するため、ミラーには import 行だけが載り本文は載らない）
- 配布物: `skills/`（npx skills / plugin marketplace の install 先。手書き設定ではなく各配布元リポジトリが正本）
- 状態・キャッシュ: `projects/`・`plugins/`・`backups/`・`cache/`・`chrome/`（Claude in Chrome の native host wrapper。CLI が自動生成しマシン固有の絶対パスとバージョンを埋め込む）・`debug/`・`downloads/`・`file-history/`・`ide/`・`paste-cache/`・`session-env/`・`sessions/`・`shell-snapshots/`・`tasks/`・`telemetry/`・`auto-resume/`・`security/`・`.cc-writes/`・`bridge-spawn/`・`daemon/`・`daemon.log`・`feedback/`・`jobs/`・`seed-admin/`・`state/`（バックグラウンドセッション・Remote Control・フィードバック下書き等の実行時状態）・`hooks/.logs/`（hook の実行ログ。手順 1 の rsync で除外）・`history.jsonl`・`stats-cache.json`・`gh-pr-status-cache.json`・`security_warnings_state_*.json`・`mcp-needs-auth-cache.json`・`.last-*`・`*.bak.*`・`.DS_Store`

**このリポジトリは public** のため、ミラーに社内・非公開の情報を出さない（手順 2 のパス正規化・手順 3 のサニタイズ・手順 4 の秘密情報チェック、および非公開の指示本文を `private/` に分けて同期しないことがその防波堤）。

## 手順

リポジトリルートで実行する。

1. **コピー実行**（存在チェック付き。ディレクトリは rsync でミラー同期）:
   ```bash
   for f in CLAUDE.md settings.json statusline-command.sh keybindings.json .mcp.json; do
     [ -f ~/.claude/"$f" ] && cp ~/.claude/"$f" dotfiles/claude/"$f"
   done
   for d in rules hooks agents commands; do
     [ -d ~/.claude/"$d" ] && rsync -a --delete --exclude '.DS_Store' --exclude '*.bak.*' --exclude '.logs' ~/.claude/"$d"/ dotfiles/claude/"$d"/
   done
   ```

2. **パス正規化（記述ルール準拠）:** 実体の設定には許可承認の蓄積などでユーザー名入りの絶対パスが混入するため、ミラーでは `~` 表記に正規化する:
   ```bash
   find dotfiles/claude -type f -exec sed -i '' "s|${HOME}|~|g" {} +
   grep -rn "/Users/" dotfiles/claude/ || echo "OK: ユーザー名パスなし"
   ```
   grep がヒットした場合は該当箇所を確認し、`~` 表記へ手動で直してから進める。

3. **サニタイズ（非公開 marketplace の除去）:** `settings.json` には社内・非公開の plugin marketplace 名やそのリポジトリパス（`extraKnownMarketplaces.<名前>.source.repo`）が入りうる。public リポジトリのミラーへ出さないため、除外対象を**ローカル限定ファイル** `~/.claude/.config-sync-exclude`（1 行 1 marketplace 名。`#` 始まりと空行は無視。marketplace 名自体を公開リポジトリに書かないためのローカル管理）に列挙し、ミラー側から取り除く。`jq` が必要:
   ```bash
   EXCLUDE=~/.claude/.config-sync-exclude
   if [ -f "$EXCLUDE" ]; then
     MPS=$(grep -vE '^[[:space:]]*(#|$)' "$EXCLUDE" | jq -R . | jq -s .)
     jq --argjson mps "$MPS" '
       (if has("enabledPlugins") then .enabledPlugins |= with_entries((.key | split("@") | last) as $m | select(($mps | index($m)) == null)) else . end)
       | (if has("extraKnownMarketplaces") then .extraKnownMarketplaces |= with_entries(.key as $k | select(($mps | index($k)) == null)) else . end)
     ' dotfiles/claude/settings.json > "${TMPDIR:-/tmp}/settings-sanitized.json" \
       && mv "${TMPDIR:-/tmp}/settings-sanitized.json" dotfiles/claude/settings.json
   else
     echo "除外ファイルなし: サニタイズ未実施。live の marketplace 一覧:"
     jq -r '.extraKnownMarketplaces // {} | keys[]' ~/.claude/settings.json
   fi
   ```
   除去されるのは `enabledPlugins` の `"<plugin>@<marketplace>"` エントリと `extraKnownMarketplaces` の同名キー。**live 側（`~/.claude/settings.json`）は変更しない**ため手元の動作に影響はなく、`global-config-push` は反映時に live の該当エントリを保持する（両スキルで対の実装。片方だけ変えない）。除外ファイルが無い場合は**サニタイズ未実施のまま先へ進めない**: 表示された marketplace 一覧に非公開のものがないかユーザーに確認し（`AskUserQuestion`）、あれば除外ファイルを作ってから本手順をやり直す。すべて公開なら、コメント行だけの除外ファイルを作って以後の確認を省く（除外ファイルは push のマージでも使われ、無いと live の非公開 marketplace が push で消える）。

4. **秘密情報チェック（Security ルール準拠）:** ミラーに実トークン・API キー等の値が混入していないか確認する:
   ```bash
   grep -rniE '(api[_-]?key|token|secret|password|credential)' dotfiles/claude/ || echo "OK: 秘密情報らしき語なし"
   ```
   ヒット行は必ず目視で判断する（キー名の参照・許可ルール・ドキュメント記述は問題ない。実際の値が入っていたら該当ファイルをミラーから外し、除外リストへの追加を検討する）。

5. **新しい同期候補の探索:** `~/.claude/` 直下に、同期対象にも既知の除外にも該当しない項目が増えていないか確認する（`sed` は `ls` が `-F` エイリアスの環境でも完全一致が効くよう末尾スラッシュを除去する）:
   ```bash
   ls -A ~/.claude | sed 's:/*$::' \
     | grep -vE '^(CLAUDE\.md|settings\.json|statusline-command\.sh|keybindings\.json|\.mcp\.json|rules|hooks|agents|commands)$' \
     | grep -vE '^(skills|projects|plugins|backups|cache|chrome|debug|downloads|file-history|ide|paste-cache|session-env|sessions|shell-snapshots|tasks|telemetry|auto-resume|security|\.cc-writes|private|bridge-spawn|daemon|daemon\.log|feedback|jobs|seed-admin|state|gh-pr-status-cache\.json|\.credentials\.json|remote-settings\.json|\.config-sync-exclude|\.zozo-guidelines-url|history\.jsonl|stats-cache\.json|mcp-needs-auth-cache\.json|\.DS_Store)$' \
     | grep -vE '^(security_warnings_state_.*|\.last-.*|.*\.bak\..*)$' \
     || echo "新しい同期候補なし"
   ```
   ヒットした項目は「手書きのグローバル設定か / 状態・キャッシュか」を判断し、設定なら本 SKILL.md と global-config-push の対象リストに追加してから再実行、状態・キャッシュなら両スキルの除外リストと本コマンドの除外パターンに追記する。

6. **差分確認:**
   ```bash
   git status --short dotfiles/claude/
   git diff dotfiles/claude/
   ```

7. 差分サマリをユーザーに日本語で報告する（変更なし／変更ありの場合は変更ファイル名と概要を示す）。

8. コミットはユーザーが明示的に依頼した場合のみ行う（`/smart-commit` を使う）。
