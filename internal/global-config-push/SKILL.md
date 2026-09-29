---
name: global-config-push
description: リポジトリの dotfiles/claude/ からグローバル Claude 設定（~/.claude/ の CLAUDE.md・settings.json・statusline-command.sh・rules/・hooks/・agents/・commands/・keybindings.json・.mcp.json）へ反映する。「設定を反映する」「グローバル設定を push して」と言ったら起動。既存ファイルはバックアップ後に上書き。
disable-model-invocation: true
metadata:
  internal: true
---

# Global Config Push

`dotfiles/claude/` の設定ファイルを `~/.claude/` に反映（コピー）する。

## 同期対象

pull（global-config-pull）と同一。ミラー側に存在するものだけを反映する:

- ファイル: `CLAUDE.md`・`settings.json`・`statusline-command.sh`・`keybindings.json`・`.mcp.json`
- ディレクトリ: `rules/`・`hooks/`・`agents/`・`commands/`

push は追加・上書きのみ行い、`~/.claude/` 側にしかないファイルは削除しない（ローカル限定ファイルの保護。削除の反映＝ミラー同期は pull 側のみ）。`~/.claude/private/`（公開しない指示本文。CLAUDE.md から `@` import する）はミラーに無いため push も触らない。CLAUDE.md を上書きしても import 行は残り、本文は `private/` 側に残る。

`settings.json` だけは単純コピーではなく**マージ**で反映する（手順 3）。pull 側がミラー作成時に (a) `$HOME` を `~` へ正規化し、(b) `~/.claude/.config-sync-exclude` に列挙した非公開 marketplace のエントリを除去しているため、そのまま上書きすると live の絶対パスが `~` リテラルに化け、社内 marketplace の設定が消えるため。除外ファイルが無いとマージで保持する対象が空になり、live の非公開 marketplace が消える。無い場合は push の前に pull 手順 3 と同じ確認を行い、除外ファイルを作る。

## 手順

リポジトリルートで実行する。

1. **差分確認（反映前に必ず実施）:**
   ```bash
   for f in CLAUDE.md settings.json statusline-command.sh keybindings.json .mcp.json; do
     [ -f dotfiles/claude/"$f" ] && { echo "--- $f"; diff dotfiles/claude/"$f" ~/.claude/"$f"; }
   done
   for d in rules hooks agents commands; do
     [ -d dotfiles/claude/"$d" ] && { echo "--- $d/"; diff -r dotfiles/claude/"$d" ~/.claude/"$d"; }
   done
   ```
   差分サマリを日本語で提示し、ユーザーに反映の意思を確認する（`AskUserQuestion` を使う）。

2. **バックアップ:**
   ```bash
   TS=$(date +%Y%m%d%H%M%S)
   for f in CLAUDE.md settings.json statusline-command.sh keybindings.json .mcp.json; do
     [ -f ~/.claude/"$f" ] && cp ~/.claude/"$f" ~/.claude/"$f".bak.${TS}
   done
   for d in rules hooks agents commands; do
     [ -d ~/.claude/"$d" ] && cp -R ~/.claude/"$d" ~/.claude/"$d".bak.${TS}
   done
   ```

3. **コピー実行（追加・上書きのみ。削除はしない）:**
   ```bash
   for f in CLAUDE.md statusline-command.sh keybindings.json .mcp.json; do
     [ -f dotfiles/claude/"$f" ] && cp dotfiles/claude/"$f" ~/.claude/"$f"
   done
   for d in rules hooks agents commands; do
     [ -d dotfiles/claude/"$d" ] && { mkdir -p ~/.claude/"$d" && cp -R dotfiles/claude/"$d"/. ~/.claude/"$d"/; }
   done
   chmod +x ~/.claude/hooks/*.sh ~/.claude/statusline-command.sh 2>/dev/null || true
   ```

   `settings.json` は **`~` の展開 + 非公開 marketplace の保持**を行ってから反映する（`jq` が必要。live 側が無い初回はミラーをそのまま置く）:
   ```bash
   MIRROR=dotfiles/claude/settings.json
   if [ -f "$MIRROR" ]; then
     TMP="${TMPDIR:-/tmp}/settings-push.json"
     sed "s|\"~/|\"${HOME}/|g" "$MIRROR" > "$TMP"
     if [ -f ~/.claude/settings.json ]; then
       EXCLUDE=~/.claude/.config-sync-exclude
       MPS=$([ -f "$EXCLUDE" ] && grep -vE '^[[:space:]]*(#|$)' "$EXCLUDE" | jq -R . | jq -s . || echo '[]')
       jq -s --argjson mps "$MPS" '
         .[0] as $mirror | .[1] as $live
         | $mirror
         | .enabledPlugins = (($mirror.enabledPlugins // {}) + (($live.enabledPlugins // {}) | with_entries((.key | split("@") | last) as $m | select(($mps | index($m)) != null))))
         | .extraKnownMarketplaces = (($mirror.extraKnownMarketplaces // {}) + (($live.extraKnownMarketplaces // {}) | with_entries(.key as $k | select(($mps | index($k)) != null))))
       ' "$TMP" ~/.claude/settings.json > "${TMP}.merged" && mv "${TMP}.merged" "$TMP"
     fi
     jq -e . "$TMP" >/dev/null && cp "$TMP" ~/.claude/settings.json
   fi
   ```
   `jq -e .` の妥当性チェックを通ったものだけ反映する（壊れた JSON で live 設定を潰さない）。`jq` が無い環境では**このステップを飛ばし**、settings.json は反映せずその旨を報告する（単純コピーで代替しない）。

4. **確認:**
   ```bash
   for f in CLAUDE.md statusline-command.sh keybindings.json .mcp.json; do
     [ -f dotfiles/claude/"$f" ] && { diff dotfiles/claude/"$f" ~/.claude/"$f" >/dev/null && echo "$f: OK" || echo "$f: 差分あり（要確認）"; }
   done
   for d in rules hooks agents commands; do
     [ -d dotfiles/claude/"$d" ] && { echo "--- $d/"; diff -r dotfiles/claude/"$d" ~/.claude/"$d"; }
   done
   # settings.json はマージ反映のため一致しないのが正常。ミラー側の内容が live に入ったかを確認する
   jq -e . ~/.claude/settings.json >/dev/null && echo "settings.json: 妥当な JSON"
   echo "live のみに残る非公開 marketplace: $(jq -r '.extraKnownMarketplaces | keys | join(",")' ~/.claude/settings.json)"
   grep -c '"~/' ~/.claude/settings.json | sed 's/^/live に残る ~ リテラル: /'
   ```
   結果を日本語で報告する。バックアップパスも提示すること。ディレクトリの diff で `Only in ~/.claude/...` が出た場合は、ミラー対象外（ローカル限定）のファイルを示すだけなので、ミラー側ファイルが一致していれば反映は成功と判断してよい。`settings.json` は**マージ反映のためミラーと一致しないのが正常**で、確認すべきは「妥当な JSON であること」「非公開 marketplace が live に残っていること」「`~` リテラルが 0 件であること」の 3 点。
