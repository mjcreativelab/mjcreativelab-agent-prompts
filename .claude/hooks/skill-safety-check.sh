#!/bin/bash
# PostToolUse hook: npx skills add 後に SKILL.md を安全チェックする

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# npx skills add / install コマンドのみ処理
echo "$CMD" | grep -qE 'npx skills (add|install)' || exit 0

# 直近 2 分以内に作成・更新された SKILL.md を検索する。npx skills の実体は .agents/skills に置かれ、
# .claude/skills 側は symlink になる（find は symlink をたどらないため重複しない）。グローバルとプロジェクトの両方を見る
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
NEWLY_ADDED=$(find ~/.agents/skills ~/.claude/skills "$PROJECT_DIR/.agents/skills" "$PROJECT_DIR/.claude/skills" \
  -name 'SKILL.md' -type f -mmin -2 2>/dev/null | sort -u)
[ -z "$NEWLY_ADDED" ] && exit 0

FINDINGS=""

while IFS= read -r f; do
  [ -f "$f" ] || continue
  ISSUES=""

  # 動的コンテキスト注入（!`コマンド`。スキル読み込み時にシェルが実行される）
  grep -qE '!`[^`]+`' "$f" 2>/dev/null \
    && ISSUES="${ISSUES}\n  - 動的コンテキスト注入（!\`コマンド\`）"

  # 危険なコマンドパターン
  grep -qE 'rm[[:space:]]+-rf' "$f" 2>/dev/null \
    && ISSUES="${ISSUES}\n  - rm -rf"
  grep -qE 'curl[[:space:]]+.+[[:space:]]*\|[[:space:]]*(ba)?sh' "$f" 2>/dev/null \
    && ISSUES="${ISSUES}\n  - curl パイプ実行"
  grep -qE 'wget[[:space:]]+.+[[:space:]]*\|[[:space:]]*(ba)?sh' "$f" 2>/dev/null \
    && ISSUES="${ISSUES}\n  - wget パイプ実行"
  grep -qiE 'base64[[:space:]]+(-d|--decode)' "$f" 2>/dev/null \
    && ISSUES="${ISSUES}\n  - Base64 デコード実行"
  grep -qE 'eval[[:space:]]+\$' "$f" 2>/dev/null \
    && ISSUES="${ISSUES}\n  - eval インジェクション"
  grep -qE '>[[:space:]]*/dev/tcp/' "$f" 2>/dev/null \
    && ISSUES="${ISSUES}\n  - /dev/tcp バックドア"
  grep -qE '[[:space:]]sudo[[:space:]]' "$f" 2>/dev/null \
    && ISSUES="${ISSUES}\n  - sudo 実行"

  # 機密環境変数の外部送信
  grep -qE 'curl[^#]*\$\{?(ANTHROPIC|API_KEY|TOKEN|SECRET|PASSWORD|PRIVATE_KEY)\}?' "$f" 2>/dev/null \
    && ISSUES="${ISSUES}\n  - 機密環境変数の外部送信の可能性"

  if [ -n "$ISSUES" ]; then
    NAME=$(basename "$(dirname "$f")")
    FINDINGS="${FINDINGS}\n⚠️  ${NAME}（${f/#$HOME/~}）:${ISSUES}"
  fi
done <<< "$NEWLY_ADDED"

if [ -n "$FINDINGS" ]; then
  MSG=$(printf '🔒 スキル安全チェック警告\n\n危険なパターンを検出しました:%b\n\n確認: 上記パスの SKILL.md を開いて内容を確認する\n削除: npx skills remove <name>' "$FINDINGS")
  jq -n --arg msg "$MSG" '{"systemMessage": $msg}'
fi
