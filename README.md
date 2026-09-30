# mjcreativelab-agent-prompts

Claude Code / Codex / Cursor / Gemini など各種エージェント用のスキル集。`skills/<skill>/` を正本として monorepo で管理し、[vercel-labs/skills](https://github.com/vercel-labs/skills) の **`npx skills`** で配布する（クロスツール・単一経路）。

> **v2.0.x で配布経路を `npx skills` に一本化**しました（v2.0.0 で旧 marketplace 撤去、v2.0.1 で skill を npx 標準探索位置 `skills/` へ配置）。旧 Claude Code marketplace（`/plugin install ...@mjcreativelab-agent-plugins`）と旧 Codex 単一プラグイン配布は廃止しています（最終タグ: marketplace 系は各 `<package>@<semver>`、旧 Codex は `mjcreativelab-claude-plugins@1.0.0`）。下記 `npx skills` へ移行してください。

## スキル一覧

各スキルの説明・使用例・前提条件は `skills/<skill>/README.md` を参照（npx install 時にスキルと一緒に配布される）。

| グループ | スキル |
|-----------|------|
| Git ワークフロー | [smart-issue-resolve](skills/smart-issue-resolve/), [smart-issue-plan](skills/smart-issue-plan/), [smart-spec-to-pr](skills/smart-spec-to-pr/), [smart-commit](skills/smart-commit/), [smart-pr](skills/smart-pr/), [smart-review](skills/smart-review/), [smart-review-apply](skills/smart-review-apply/), [smart-git-sync](skills/smart-git-sync/) |
| スキル品質改善・環境構成レビュー | [skill-improver](skills/skill-improver/), [empirical-prompt-tuning](skills/empirical-prompt-tuning/), [claude-code-update-review](skills/claude-code-update-review/) |
| コード開発ライフサイクル | [software-architect](skills/software-architect/), [code-reviewer](skills/code-reviewer/), [code-reviewer-adversarial](skills/code-reviewer-adversarial/), [security-auditor](skills/security-auditor/), [branch-visualize](skills/branch-visualize/), [structure-visualize](skills/structure-visualize/), [tech-doc-structuring](skills/tech-doc-structuring/) |
| ドキュメント作成 | [human-facing-doc-writing](skills/human-facing-doc-writing/) |
| 事業企画 | [business-ideation](skills/business-ideation/) |
| デザイン | [game-ui-design](skills/game-ui-design/) |
| システムメンテナンス | [disk-space-cleanup](skills/disk-space-cleanup/) |
| エージェント記憶管理 | [memory-dream](skills/memory-dream/), [agents-md-improver](skills/agents-md-improver/), [agents-md-revise](skills/agents-md-revise/) |

コード開発ライフサイクル系は `/software-architect` → 実装 → `/code-reviewer` → `/security-auditor` の流れで組み合わせて使うことを想定。

## インストール（`npx skills`）

skill 単位にクロスツール install できる。skill は `.agents/skills/<skill>/` に配置され、各エージェント（Claude Code / Codex / Cursor / Gemini CLI / GitHub Copilot ほか）へ展開される。

```bash
# 利用可能な skill 一覧
npx skills add mjcreativelab/mjcreativelab-agent-prompts --list

# 推奨: グローバル install（最新を追従）
npx skills add mjcreativelab/mjcreativelab-agent-prompts --skill smart-commit -g

# エージェント指定（例: Codex）
npx skills add mjcreativelab/mjcreativelab-agent-prompts --skill smart-commit -a codex -g

# 全 skill を一括（zsh は '*' をクォート）
npx skills add mjcreativelab/mjcreativelab-agent-prompts --skill '*' -g

# 特定バージョンに固定したい場合は末尾に #v<X.Y.Z> を付ける（zsh はソースを引用符で囲む）
npx skills add 'mjcreativelab/mjcreativelab-agent-prompts#v<X.Y.Z>' --skill smart-commit -g

# 更新確認 / 取り込み（global）
npx skills check
npx skills update
```

- 推奨は **グローバル install（`-g`）**。プロジェクト install は `npx skills update` の対象外になる場合があるため、更新は再 add で取り込む。
- **バージョンを固定したい場合**は fragment 構文 `#v<X.Y.Z>` でタグ pin する（例: `'mjcreativelab/mjcreativelab-agent-prompts#v<X.Y.Z>'`）。タグ無しは default branch（最新）追従。**`@<名前>` は ref ではなく skill フィルタ**（`owner/repo@smart-commit` = `--skill smart-commit` 相当）。
- pin した install は lock に ref が記録され、`npx skills update` も pin に従う（タグ pin は据え置き）。新しいタグへ上げるときは `#v<新タグ>` で再 add する。
- 内部 skill `auto-release`（本リポジトリ専用のリリース用）は `internal/` 配下にあり配布対象外（リモート探索・`--skill '*'` のいずれにも含まれない）。

## ライセンス

[MIT](LICENSE)
