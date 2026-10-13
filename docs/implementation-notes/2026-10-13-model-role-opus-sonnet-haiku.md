# 役割別モデル配分: オーケストレーター・設計・監視・レビュー = Opus / 通常作業 = Sonnet / 後始末 = Haiku（2026-10-13）

グローバル CLAUDE.md の構成（通常 = sonnet・advisor = opus・サブエージェント = haiku）に合わせ、`smart-issue-plan` / `smart-issue-resolve` の監視・レビュー役を Fable から Opus に変え、機械的な後始末（probe-cleanup）だけを Haiku にした。2026-10-02 の「監視・レビュー = Fable」配分（[2026-10-02-model-role-assignment.md](2026-10-02-model-role-assignment.md)）を置き換える。この配分は作者のマシンでは動かない（`CLAUDE_CODE_SUBAGENT_MODEL_FORCE` により全役割が Haiku になる）ため、実行時の挙動は未検証。

## 配分

| 役割（`agent()` の label） | 変更前 | 変更後 |
|---|---|---|
| claude 系レビュワー・Breaker・Judge バッチ（`reviewModel`） | fable / high | opus / high |
| 雛形 C の監査役・Breaker、セキュリティ監査役 | fable / high | opus / high |
| 独立 QA（`qa:*`、雛形 A・B・E） | fable / high | opus / high |
| 設計整合レビュー（`architect:review`） | fable / max | opus / max |
| probe-cleanup | sonnet / low | haiku（`effort` は指定しない） |
| 設計役（`architect:design`）・plan-editor | opus / max | 変更なし |
| 開発者（`dev:*`） | sonnet / high | 変更なし |

オーケストレーター（メインセッション）は元から「Opus 推奨」のままで、変更していない。

## 自分で判断した事項

- **設計役と plan-editor は opus のまま**: 依頼の分類（オーケストレーター・監視・レビュワー / 通常作業 / サブエージェント）のどれにも当たらないため確認した。ユーザーが「opus のまま」を選んだ。設計・指示はオーケストレーターと同格として扱った
- **「サブエージェント = haiku」は probe-cleanup だけに適用した**: 雛形の `agent()` はすべて Workflow のサブエージェントだが、機械的な後始末で Haiku が務まるのは probe-cleanup（残存した `.breaker-probe.` ファイルの削除）だけ。他の役を Haiku にすると、依頼の「監視・レビュー = Opus」「通常作業 = Sonnet」と矛盾する
- **probe-cleanup の `effort` を外した**: 作者のグローバル設定の記述では、CLI は Haiku を effort 非対応として扱う。非対応のモデルに指定を渡し続けるより省略を選んだ。省略したときの挙動は未実測
- **QA を sonnet に戻さなかった**: Fable 配分の前は QA が sonnet だったが、依頼が「監視 = Opus」なので opus にした。自動コミット前の最終ゲートでもある
- **`code-reviewer` / `code-reviewer-adversarial` は変更していない**: レビュー役がすでに opus で、新しい配分と一致する
- **グローバル CLAUDE.md の 1 行を更新した**: 「スキル内の役割別モデル指定（`opus` / `sonnet` / `fable`）」は、この変更で `haiku` に変わるため古くなる。`~/.claude/CLAUDE.md` と `dotfiles/claude/CLAUDE.md` を同じ内容で直し、パスを正規化した diff で一致を確認した

## 検討した代替案

| 案 | 採らなかった理由 |
|---|---|
| 設計役・plan-editor も sonnet にする | 設計・指示の質が下流のすべてを決める。依頼の範囲外で、コスト削減の効果も限定的（起動は 1 回） |
| 後始末だけでなく開発者の fix も haiku にする | 「通常作業 = Sonnet」に反する。fix はレビュー指摘の採用判定を含む |
| `args` でモデルを差し替え可能にする | 依頼の範囲を超える。切り戻しは `reviewModel` の 1 行で足りる |

## やらないこと

- `settings.json` の `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` は触らない。これを外さない限り、作者のマシンで新配分は動かない
- `smart-spec-to-pr` は変更していない。両スキルを連鎖させるだけで、モデル指定を持たない

## 検証

- 雛形の `model:` 指定を grep で数えた。resolve は opus 9 + `reviewModel`、sonnet 5、haiku 1。plan は opus 1（plan-editor）+ `reviewModel`
- `skills/` 配下に `fable` が残るのは、置き換え履歴を書いた resolve 725 行目と plan 422 行目の 2 行だけ
- 両スキルの雛形の js ブロック（resolve 5・plan 1）を `node --check` で構文検査し、すべて通過した
- `~/.claude/CLAUDE.md` と `dotfiles/claude/CLAUDE.md` は、パスを正規化した diff で一致した
- 実行時の挙動（Workflow `agent()` が `model: 'opus'` / `'haiku'` を解決すること、Haiku への `effort` 省略）は未実測。`docs/empirical-tuning/review-loop-speedup.md` の同日節に採取項目を書いた

## リスク

- **コスト**: Fable より安いが、QA が sonnet → opus、レビュー役が全ラウンド opus（Fable 配分の前は包括ラウンド後は sonnet だった）。総トークンは台帳の #134 節と比較する
- **Haiku の後始末の失敗**: probe-cleanup が失敗すると `.breaker-probe.` ファイルが作業ツリーに残ったまま、後続の独立 QA（opus）に進む。QA プロンプト（雛形 B・E）は `.breaker-probe.` の残存を issues として報告する指示を持つため、素通りはしない
