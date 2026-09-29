# .env 保護 hook（Bash 経由）の誤検知を解消（2026-09-29）

PR #143 で、グローバル `settings.json` の hook が stdin から入力を読むよう直した。その結果、Bash 経由の .env 保護 hook が実際に動くようになり、正規表現 `(>|>>|tee|sed|cp).*\.env` が語の一部にも反応して誤検知することが分かった。

## 何が起きていたか

単語の区切りを見ていないため、次のコマンドが止められていた（実測）:

- `sed -n '1,20p' src/config.ts | grep process.env`（`process.env` の `.env` に反応）
- `git diff > /tmp/d.txt; grep -c process.env /tmp/d.txt`
- `npx mcp-inspector --env-file .envrc`（`mcp` の中の `cp` に反応）
- `grep -n "used" README.md | grep .env`（`used` の中の `sed` に反応）

## 判断事項

### 新しい判定式

```
(>|(^|[^[:alnum:]_.-])(tee|sed|cp)([[:space:]]|$))(.*[^[:alnum:]_.])?\.env
```

- `tee` / `sed` / `cp` は独立した語のときだけ一致させる（直前が語の文字・ドット・ハイフンでなく、直後が空白か行末）。`/bin/cp` のようなパス指定は一致する
- `.env` は、直前が語の文字・ドットでないときだけ一致させる（ファイル名 `.env*` の形）。`process.env` は一致しない
- 演算子の直後に `.env` が来る形（`>.env`・`cp .env.local`）も一致させる。区切り文字が演算子側に吸収されるため、後半を省略可能なグループ `(.*[^[:alnum:]_.])?` にしている
- `.env.sample` を含むコマンドは、従来どおり除外する

### 意図的に変わった範囲

- `app.env` のように、ドットの前に名前が付くファイルは対象外になった。`process.env` と字面で区別できないため
- `cat .env > x` のように、演算子より前に `.env` が来る読み取りは、従来どおり対象外。読み取りは組織配布の設定と、グローバル CLAUDE.md の Security 規則で扱う
- `.envrc`（direnv の設定）は、secret を含みうるため引き続き対象にしている

### 組織配布の設定との関係

組織配布の managed settings がある環境では、`.env` を含む Bash コマンドは permission の段階で拒否される。PreToolUse hook はその前に実行されるが、どちらでも止まるので、この環境での hook は二段目の防御にあたる。managed settings がない環境（公開ミラーを使う場合など）では、この hook が唯一の防御になるため、誤検知の少ない判定にしておく意味がある。

## 検証

- 両方向のテスト 19 件がすべて期待どおり
  - 通す 8 件: 上の誤検知 4 件、`node -e "…process.env…" > out.txt`、`ls -la`、`cp x .env.sample`、`git status`
  - 止める 11 件: `> .env`、`>.env`、`> '.env'`、`> ".env"`、`>> .env.local`、`sed -i … config/.env`、`/bin/cp .env.local x`、`cp .env.production …`、`tee … .env-probe`、`tee -a .env`、`sed … > .env`
- 実機での確認
  - `tee /dev/null # .env-probe` は、新しい hook のメッセージでブロックされた
  - 旧版の誤検知だったコマンド 2 件は、hook を通過した。拒否したのは permission の段階で、hook のメッセージは出なかった
