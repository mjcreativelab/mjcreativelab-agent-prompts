# skill-safety-check hook を機能させる（2026-09-29）

`.claude/hooks/skill-safety-check.sh` は、`npx skills add` の後に新しく入った SKILL.md を調べ、危険なパターンを警告する PostToolUse hook。`/claude-code-update-review` で、一度も動いていなかったことが分かった。

## 何が起きていたか

- プロジェクトの `.claude/settings.json` がなく、hook がどこにも登録されていなかった
- 登録されていたとしても、`find ~/.claude/skills` は symlink をたどらない。npx skills は実体を `.agents/skills/` に置き、`~/.claude/skills/` には symlink を張る。そのため、新しく入ったスキルを 1 件も検出できなかった（実測: `~/.claude/skills` の npx 配置 26 件はすべて symlink）
- インラインシェルの検出パターン `^\s*!\s+\S` は、実際の構文 `` !`コマンド` `` と一致しなかった
- 警告メッセージの改行を `"\n"` の文字列で連結し、`printf '%s'` で出していたため、`\n` がそのまま表示されていた

## 判断事項

- **走査先**: `~/.agents/skills`・`~/.claude/skills` と、プロジェクトの `.agents/skills`・`.claude/skills` の 4 か所にした。`find -L` は使わない。`.claude/skills` 側は symlink なので、既定の `find` なら同じスキルを 2 回数えずに済む。プロジェクトのパスは `$CLAUDE_PROJECT_DIR`（なければ `$PWD`）を基準にする
- **「新しく入った」の判定**: 従来どおり「2 分以内に更新された」（`-mmin -2`）で判定する。npx skills が配置したファイルは、mtime がインストール時刻になっていることを確認した
- **登録先**: プロジェクトの `.claude/settings.json`（チーム共有）に、PostToolUse の Bash matcher として登録した。登録以外の設定（permissions の deny など）は加えていない。このリポジトリには、プロジェクト固有の secret ファイルがないため
- **警告メッセージ**: スキル名に加えて実際のファイルパスを表示する（`$HOME` は `~` に置き換える）

## 検証

- 再現テスト 9 件がすべて合格した（一時プロジェクトに、危険な SKILL.md と問題のない SKILL.md、npx skills と同じ symlink 配置を用意）。確認した内容は次のとおり
  - `npx skills add` で警告が出る
  - 危険なほうだけを検出する
  - `` !`cmd` `` と `curl | sh` を検出する
  - symlink による重複がない
  - `~` 置換が /bin/bash 3.2 で動く
  - 改行が正しく出る
  - 関係ないコマンドでは何も出ない
- 登録の実動作: 一時プロジェクトで `claude -p` に `echo npx skills add …` だけを実行させ、`PostToolUse:Bash` の hook が発火して警告を返すことを確認した
- `bash -n` と settings.json の JSON 妥当性を確認した
