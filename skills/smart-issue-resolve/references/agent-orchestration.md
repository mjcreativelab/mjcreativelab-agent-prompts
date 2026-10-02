# エージェントオーケストレーション（Workflow スクリプト雛形）

smart-issue-resolve の実装・レビューを担う役割別エージェントの起動手順と Workflow スクリプト雛形。SKILL.md の手順 6 以降から参照される。**Claude Code の Workflow ツール前提**（利用できない環境の degradation は SKILL.md を参照）。

## 前提とゲート

- 起動前に `{作業Dir}/context.md` が存在すること（SKILL.md 手順 6 で作成）。存在しなければ Workflow を起動せず、context.md の作成に戻る
- 雛形 B（claude 系レビューセット）は**新規セットの起動ごと**（初回セット・継続セットとも）、起動直前にオーケストレーターが `{作業Dir}/diff.md` を生成すること（下記「レビュー正本 diff.md」）。ただし `resumeFromRunId` による**同一セットの再開では生成しない**（再開後のスクリプトは中断時点の期待スタンプを保持しているため、`startRound` で作り直すとスタンプが巻き戻り、残りラウンドのレビュー役が不要にフォールバックする）。生成に失敗した場合も起動自体は可能だが、全レビュー役が自前の git 取得へフォールバックする（＝従来動作）ため、その旨を完了報告に明記する
- スクリプトはこのファイルの雛形を**そのまま** `script` に渡し、可変値はすべて `args` で渡す（スクリプト本文を書き換えない。プロンプト文はスクリプトに内蔵済み）
- `args` は JSON 値として渡す（文字列化した JSON を渡さない）。ただし呼び出し経路によっては文字列（`typeof args === 'string'`）で着弾する環境があるため、各雛形は meta 直後に正規化シム（`args = typeof args === 'string' ? JSON.parse(args) : (args || {})`）を持つ。文字列・オブジェクトどちらで届いても本文のトップレベル `args.` 参照が機能する
- Workflow スクリプト内では `Date.now()` / `Math.random()` / 引数なし `new Date()` は使えない（雛形は使用していない）
- **進捗の可視化**: IDE 拡張では `/workflows` の進捗表示が使えないため、`log()` で開始日時・進捗・ラウンド結果を可視化する。時刻の取得は 2 系統（スクリプト自身は時刻を生成できない）:
  - **開始日時**: オーケストレーターが起動直前に `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` を実測し、`args.startedAt` として渡す（全雛形共通・省略可）。スクリプトは冒頭の開始ログに使う。**ログ表示専用で、`agent()` のプロンプトへは埋め込まない**（resume 時に `agent()` の (prompt, opts) キャッシュ一致を保つため）
  - **途中経過の時刻**: 各 `agent()` はプロンプト末尾の共通指示（`TAIL_NOTE`）で `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` を実行し、結果を構造化出力の `nowJst`（共通フィールド。`NOW_JST_FIELD`）として返す。スクリプトは完了ログ（`log(`[YYYY-MM-DD hh:mm:ss JST] ...`)`）に使うほか、直近値を `lastJst` に保持して次のラウンド開始・judge 起動などの開始ログに使う（`parallel()` バッチは各結果の `nowJst` の最大値を完了時刻とする）
  - **ラウンド結果**: 各レビューラウンドの終了時に、指摘 / 裁定の内訳（真の欠陥・仕様未定・除外件数）と各指摘のタイトル・重大度、fix の採用 / 不採用を `log()` で出力する（件数上限つき）。新しい `agent()` 呼び出しを追加する場合もこの規約に従う
- **プロンプトは英語・出力は日本語**: `agent()` に渡すプロンプト本文・スキーマ `description` は英語で記述する（指示追従の精度向上）。ユーザーが読む内容 — 構造化出力の中身・引き継ぎファイル（design.md / impl-notes.md / breaker-round-*.md 等）・`log()` 文字列・`meta`・カテゴリ enum 値（`真の欠陥` / `仕様未定` / `低優先度` / `ノイズ`）— は日本語のまま（`TAIL_NOTE` が日本語出力を指示する）
- ツール結果に返る `scriptPath` を控えておくと、同じ雛形の再起動（レビューセット続行など）は `{scriptPath, args}` で再送できる。中断・失敗からの再開は `resumeFromRunId` を使う

## 作業ディレクトリと context.md

作業ディレクトリはオーケストレーターが作成する（配置ルールの詳細は SKILL.md 手順 6-2）。linked worktree の中にいる場合は `{worktreeパス}/.smart-issue-work/resolve-issue-<番号>/`（端末の再起動でも失われず、worktree 削除時に中身ごと消える。`.smart-issue-work/` は `info/exclude` に登録してレビュー対象 diff を汚さない）、メイン作業ツリーの場合は `mktemp -d "${TMPDIR:-/tmp}/sir-issue-<番号>.XXXXXX"`。いずれもスキル側で削除手順は持たない。`context.md` は以下の書式で書き出す:

```markdown
# smart-issue-resolve コンテキスト（Issue #<番号>）

## Issue 要件
- タイトル: <タイトル>
- 要件・受け入れ基準: <要約（箇条書き）>
- ラベル: <ラベル一覧>

## 実装計画（あれば）
<実装手順・影響範囲・リスク・分析時点 SHA・依拠した前提の要約。無ければ「なし」>

## 追加指示（-p）
<{プロンプト}。無ければ「なし」>

## ブランチ / diff 基準
- 作業ブランチ: <ブランチ名>
- デフォルトブランチ: <名前>（diff 基準は origin/<名前>...HEAD + 未コミットの working tree 変更）

## テスト方針
<関連テストのスコープ・実行コマンド。テストが特定できない場合は、ユーザーと合意済みの手動確認方針>

## プロジェクト固有基準
<SKILL.md 手順 6-1 で収集した規約・レビュー基準の要点。無ければ「なし」>
```

エージェント間の引き継ぎファイル（すべて `{作業Dir}` 配下）:

| ファイル | 書き手 | 読み手 |
|---|---|---|
| `context.md` | オーケストレーター | 全エージェント |
| `gen-diff.sh` | オーケストレーター（本スキルの `assets/gen-diff.sh` をコピー） | 開発者（雛形 B の fix が再生成に実行する） |
| `diff.md` | オーケストレーター（雛形 B の各セット起動前）/ 開発者（雛形 B のラウンド境界） | 雛形 B のレビュワー・Breaker・Judge（**独立 QA は読まない**） |
| `design.md` | 設計役 | 開発者・設計レビュー役（事後レビュー） |
| `impl-notes.md` | 開発者 | 開発者（修正時）・オーケストレーター |
| `security-audit.md` | Breaker レンズ S（claude 系・監査ラウンド）/ セキュリティ監査役（codex 系） | Breaker |
| `breaker-round-<N>[-<lens>].md` | Breaker（claude 系はレンズ別に `-<lens>` 付き〔包括ラウンド。単発ラウンドは `-all`〕・codex 系は単一） | Judge（codex 系では Codex） |
| `findings-round-<N>.md` | オーケストレーター（標準: Codex の指摘全件 / 敵対: 裁定の真の欠陥 + ユーザー確認済みの仕様未定。要約・取捨選択をしない） | 開発者（雛形 D） |

### レビュー正本 diff.md（雛形 B 専用）

雛形 B のレビュー役（レビュワー・Breaker・Judge）は diff を自分で取得せず `{作業Dir}/diff.md` を Read する（各エージェントが `git diff` / `git status` を重複実行しないため）。生成は本スキルの `assets/gen-diff.sh` で行う。オーケストレーターは作業ディレクトリ作成時に `{作業Dir}/gen-diff.sh` へコピーしておく（fix エージェントは `{作業Dir}` しか知らないため、スキル本体のパスに依存させない）:

```bash
bash {作業Dir}/gen-diff.sh origin/<デフォルトブランチ> <対象ラウンド>
```

出力先はスクリプト自身のディレクトリ（＝ `{作業Dir}/diff.md`）で固定。書式は `gen-diff.sh` が単一情報源で、ヘッダ（`対象ラウンド` / ブランチ / 差分基準 / HEAD SHA）+ 変更ファイル一覧（コミット済み `--stat` / 未コミット `--stat` / 未追跡ファイル名）+ `===== BEGIN/END COMMITTED DIFF =====` と `===== BEGIN/END UNCOMMITTED DIFF =====` の 2 ブロックからなる（diff 本文はコードフェンスで囲まない。diff 中の 3 連バッククォートで入れ子が破綻するため）。

- **生成責務**: 新規セットの起動直前（初回・継続）はオーケストレーターが `<対象ラウンド>` = `startRound` で生成する。セット内のラウンド境界は `dev:fix-r<N>` エージェントが修正・テスト・反例テスト整理を終えた最終ステップとして `<対象ラウンド>` = `N + 1` で再生成する（プロンプトに内蔵）。**`resumeFromRunId` による同一セットの再開では生成しない**: 再開後のスクリプトは中断時点の `diffRound`（ラウンド進行に応じて前進済み）を保持しており、直前の `dev:fix` が再生成に成功していれば diff.md はすでにその値で一致している。ここで `startRound` で作り直すとスタンプだけが巻き戻り、再生成しなければ起きなかったフォールバックを残りラウンド全員に発生させる（再生成しない場合に diff.md が stale / 不在なら従来どおりスタンプ不一致でフォールバックするため、安全側は保たれる）
- **鮮度ガード**: 雛形 B は `diffRound`（diff.md が持つはずのスタンプ）を追跡し、各レビュー役のプロンプトに期待値として埋め込む。`dev:fix-r<N>` を起動したら自己申告によらず無条件に `diffRound = N + 1` へ進めるため、再生成漏れは次ラウンドでスタンプ不一致となり、レビュー役が自前の git 取得へフォールバックする（安全側に倒れる）。クリーンラウンド（fix 非実行）ではスタンプを進めないため、確認ラウンドで誤検知しない。`FIX_SCHEMA` の `diffRegenerated` は観測用のログで、判定権はスタンプ側にある
- **セット跨ぎ**: 継続セットでもオーケストレーターが必ず再生成する。前セット末尾がクリーンラウンドだと fix 由来のスタンプが新しい `startRound` に届かず、再生成しないと継続セット round 1 が必ずフォールバックになる
- **QA は非依存**: 独立 QA（雛形 B の最終 QA・雛形 A の QA・雛形 E）は開発者の自己申告を信用しない役割のため、diff.md を使わず自分で git を実行する。雛形 A（実装フェーズ）・雛形 C / D も従来どおり diff.md を使わない
- **実コード照合は不変**: diff.md は「どこを見るか」の入力にすぎない。レビュー役が該当ファイルを Read し周辺を grep して実コードと照合する義務は従来どおり（未追跡ファイルの内容と、生成後に作られた `.breaker-probe.` 反例テストはスナップショットに含まれないため、必ず直接読む）
- スクリプトは読み取り専用の git のみを使い（インデックス・作業ツリーを変更しない ＝ レビュー対象を汚さない）、base ref を検証してから一時ファイル経由で `mv` する（途中失敗で「新しいスタンプ付きの不完全な diff.md」を残さない）。ref を解決できなければ非ゼロ終了し、既存の diff.md はそのまま残す

## 雛形 A: 実装フェーズ（sir-implement）

設計（条件付き）→ 実装 → 独立 QA（不合格なら開発者修正、最大 2 回）→ 設計整合・保守可用性レビュー → 反映 → QA 再確認。

`args`: `{ workDir, issueNumber, defaultBranch, needDesign, startedAt }`（`startedAt`: 起動直前にオーケストレーターが `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` で実測した開始日時。開始ログ表示専用・省略可）

```js
export const meta = {
  name: 'sir-implement',
  description: 'smart-issue-resolve 実装フェーズ（設計→実装→独立QA→設計整合・保守可用性レビュー）',
  phases: [
    { title: 'Design', detail: '設計方針の確定（計画が無い/粗い場合のみ）' },
    { title: 'Implement', detail: 'Sonnet 開発エージェントによる実装' },
    { title: 'QA', detail: '独立エージェントによるテスト・受け入れ基準検証' },
    { title: 'ArchReview', detail: '設計整合・保守性・可用性レビューと反映' },
  ],
}

// args は文字列で届く環境があるため正規化する（トップレベルの args. 参照を機能させる防御シム）
args = typeof args === 'string' ? JSON.parse(args) : (args || {})

const ctx = args.workDir + '/context.md'
const notes = args.workDir + '/impl-notes.md'

const NOW_JST_FIELD = { type: 'string', description: "Completion time in JST: the verbatim output of `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'`" }
const TAIL_NOTE = "Output language: write all output content (structured output fields and any files you write) in Japanese; keep code identifiers, file paths, and commands as-is. Finally, run `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` and put its verbatim output into nowJst."
const ts = (t) => (t ? `[${t} JST] ` : '')
let lastJst = args.startedAt || ''

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['items', 'nowJst'],
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'severity', 'basis', 'detail'],
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['High', 'Medium', 'Low'] },
          basis: { type: 'string', description: 'Primary evidence such as file path and line numbers' },
          detail: { type: 'string' },
        },
      },
    },
    nowJst: NOW_JST_FIELD,
  },
}

const FIX_SCHEMA = {
  type: 'object',
  required: ['adopted', 'rejected', 'testsPassed', 'nowJst'],
  properties: {
    adopted: {
      type: 'array',
      items: { type: 'object', required: ['title', 'action'], properties: { title: { type: 'string' }, action: { type: 'string' } } },
    },
    rejected: {
      type: 'array',
      items: { type: 'object', required: ['title', 'reason'], properties: { title: { type: 'string' }, reason: { type: 'string' } } },
    },
    testsPassed: { type: 'boolean' },
    notes: { type: 'string' },
    nowJst: NOW_JST_FIELD,
  },
}

const QA_SCHEMA = {
  type: 'object',
  required: ['pass', 'executed', 'issues', 'nowJst'],
  properties: {
    pass: { type: 'boolean' },
    executed: { type: 'string', description: 'Commands executed for tests / lint and a result summary' },
    issues: {
      type: 'array',
      items: { type: 'object', required: ['title', 'detail'], properties: { title: { type: 'string' }, detail: { type: 'string' } } },
    },
    nowJst: NOW_JST_FIELD,
  },
}

const IMPL_SCHEMA = {
  type: 'object',
  required: ['changedFiles', 'summary', 'testResults', 'nowJst'],
  properties: {
    changedFiles: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    testResults: { type: 'string' },
    nowJst: NOW_JST_FIELD,
  },
}

const DESIGN_SCHEMA = {
  type: 'object',
  required: ['summary', 'nowJst'],
  properties: {
    summary: { type: 'string', description: 'Gist of design.md (within 10 lines)' },
    nowJst: NOW_JST_FIELD,
  },
}

const RESTRAINT_NOTE = "Execution discipline: complete this role yourself with your own tool calls — do not launch subagents (Agent/Task tools), even to verify or double-check your own work, and do not add verification passes beyond the steps above. Deliver what was asked, at the scope intended, and stop short of actions clearly beyond it. Match the length of your output and any files you write to what the task needs: cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate."

const qaPrompt = (extra) => `You are an independent QA agent. Do not trust the developer's self-report; run the verification yourself.
1. Read ${ctx} (test policy, acceptance criteria, diff base).
2. Inspect the changes: git diff origin/${args.defaultBranch}...HEAD, plus uncommitted changes visible via git status / git diff.
3. Following the test policy in context.md, run the relevant-scope tests and lint yourself (if the policy is manual verification, perform it as far as possible).
4. Verify each acceptance criterion of the Issue, one by one, against the code and execution results.
5. If any throwaway test whose filename contains .breaker-probe. remains in the change set, report it in issues.
Constraints: do not modify code or files. Do not commit or push. ${extra}
Verdict: set pass=true only when all tests pass and the acceptance criteria are met. Put the executed commands and a result summary into executed, and list problems in issues. ${RESTRAINT_NOTE} ${TAIL_NOTE}`

const logQaIssues = (qaResult) => {
  if (qaResult.pass) return
  for (const it of qaResult.issues.slice(0, 5)) log(`- QA指摘: ${it.title}`)
  if (qaResult.issues.length > 5) log(`- QA指摘: …他${qaResult.issues.length - 5}件`)
}

log(`${ts(lastJst)}実装フェーズ開始: Issue #${args.issueNumber}`)

let design = null
if (args.needDesign) {
  design = await agent(`You are the designer (software architect). Do not start implementing.
1. Read ${ctx} (Issue requirements, acceptance criteria, project-specific standards).
2. Investigate the relevant code (entry points, dependency graph, existing patterns, boundary conditions) and settle a design approach that satisfies the requirements.
3. Write the following sections to ${args.workDir}/design.md: 方針 / 変更対象ファイル / データ・依存の流れ / リスク / テスト方針 / 未確定事項.
Constraints: do not modify code. Do not commit or push. Do not unilaterally settle specs you cannot decide — list them under 未確定事項.
Final output: put the gist of design.md (within 10 lines) into summary. ${RESTRAINT_NOTE} ${TAIL_NOTE}`,
    { label: 'architect:design', phase: 'Design', model: 'opus', effort: 'max', schema: DESIGN_SCHEMA })
  if (design === null) return { status: 'agent-failed', at: 'design' }
  lastJst = design.nowJst || lastJst
  log(`[${design.nowJst} JST] Design 完了`)
}

const impl = await agent(`You are the developer implementing GitHub Issue #${args.issueNumber}.
1. Read ${ctx}${args.needDesign ? `, then follow the design approach in ${args.workDir}/design.md. Where it lists 未確定事項 (open questions), pick the minimal reasonable interpretation and record your decision in impl-notes.md` : ''}.
2. Fill the gaps the plan / design does not cover with your own codebase investigation (entry points, dependency graph, existing patterns, quality gates such as lint / type checks).
3. Before implementing, run the relevant-scope tests once per the test policy in context.md and record the baseline (pre-existing failures).
4. Implement per the Issue requirements, acceptance criteria, and extra instructions. Keep the scope limited to what the Issue (and the plan / design) covers.
5. Re-run the same test scope and confirm no existing tests broke and the new requirements are met.
6. Write to ${notes}: 変更ファイル / 要件対応（受け入れ基準ごと） / 自分で判断した事項 / テスト結果（ベースライン比較）.
Constraints: do not commit or push. Do not mix in changes unrelated to the Issue. ${RESTRAINT_NOTE} ${TAIL_NOTE}`,
  { label: 'dev:implement', phase: 'Implement', model: 'sonnet', effort: 'high', schema: IMPL_SCHEMA })
if (impl === null) return { status: 'agent-failed', at: 'implement' }
lastJst = impl.nowJst || lastJst
log(`[${impl.nowJst} JST] Implement 完了`)

let qa = await agent(qaPrompt(''), { label: 'qa:verify', phase: 'QA', model: 'fable', effort: 'high', schema: QA_SCHEMA })
if (qa === null) return { status: 'agent-failed', at: 'qa' }
lastJst = qa.nowJst || lastJst
log(`[${qa.nowJst} JST] QA 完了（pass=${qa.pass}${qa.pass ? '' : `・指摘${qa.issues.length}件`}）`)
logQaIssues(qa)

let qaFixRounds = 0
while (!qa.pass && qaFixRounds < 2) {
  qaFixRounds++
  log(`${ts(lastJst)}QA修正${qaFixRounds}回目 開始`)
  const fix = await agent(`You are the developer who implemented Issue #${args.issueNumber}. Independent QA returned these findings:
${JSON.stringify(qa.issues, null, 2)}
1. Read ${ctx} and ${notes} to restore the implementation context.
2. Verify each finding and fix it (if you judge one to be a QA false positive, record the reason in rejected).
3. Re-run the relevant-scope tests.
4. Update ${notes}.
Constraints: do not commit or push. ${RESTRAINT_NOTE} ${TAIL_NOTE}`,
    { label: 'dev:qa-fix-' + qaFixRounds, phase: 'QA', model: 'sonnet', effort: 'high', schema: FIX_SCHEMA })
  if (fix === null) return { status: 'agent-failed', at: 'qa-fix' }
  lastJst = fix.nowJst || lastJst
  log(`[${fix.nowJst} JST] QA修正${qaFixRounds}回目 完了（採用${fix.adopted.length}件）`)
  qa = await agent(qaPrompt('This is re-verification after the developer addressed the previous QA findings.'), { label: 'qa:re-verify-' + qaFixRounds, phase: 'QA', model: 'fable', effort: 'high', schema: QA_SCHEMA })
  if (qa === null) return { status: 'agent-failed', at: 'qa' }
  lastJst = qa.nowJst || lastJst
  log(`[${qa.nowJst} JST] QA再検証${qaFixRounds}回目 完了（pass=${qa.pass}${qa.pass ? '' : `・指摘${qa.issues.length}件`}）`)
  logQaIssues(qa)
}
if (!qa.pass) return { status: 'qa-failed', impl, qa }

const arch = await agent(`You are the designer. Review the completed change for design conformance, maintainability, and availability.
1. Read ${ctx}${args.needDesign ? ` and also check against the design approach in ${args.workDir}/design.md` : ''}.
2. Inspect git diff origin/${args.defaultBranch}...HEAD and the uncommitted changes.
3. Report only defects worth fixing, from these aspects:
   - Design conformance: deviation from the design approach, the implementation plan, or the existing architecture (layer responsibilities, dependency direction)
   - Maintainability: excessive coupling, reduced testability, wide change ripple, unnecessary abstraction
   - Availability / operations: missing timeouts / retries, behavior on failure or dependency degradation, resource exhaustion, missing observability (logs / metrics), fragile deploy / rollback
Constraints: do not modify code. Do not commit or push. Readability, naming, and style are out of scope. Attach evidence (file, line) and severity to each finding. If there are no findings, return an empty items array. ${RESTRAINT_NOTE} ${TAIL_NOTE}`,
  { label: 'architect:review', phase: 'ArchReview', model: 'fable', effort: 'max', schema: FINDINGS_SCHEMA })
if (arch === null) return { status: 'agent-failed', at: 'arch-review' }
lastJst = arch.nowJst || lastJst
log(`[${arch.nowJst} JST] ArchReview 完了（指摘${arch.items.length}件）`)
for (const it of arch.items.slice(0, 10)) log(`- [${it.severity}] ${it.title}`)
if (arch.items.length > 10) log(`- …他${arch.items.length - 10}件`)

let archFix = null
if (arch.items.length > 0) {
  archFix = await agent(`You are the developer (reviewee) who implemented Issue #${args.issueNumber}. Judge and apply the designer's review findings:
${JSON.stringify(arch.items, null, 2)}
1. Read ${ctx} and ${notes}, then classify each finding as 採用 (adopt) or 不採用 (reject):
   - Adopt: findings that correctly identify, with evidence, an unmet spec, a bug, a regression risk, or a design / maintainability / availability defect.
   - Reject: invalid, would cause over-engineering, or out of the Issue's scope (record the reason in one line).
2. Fix the adopted findings and re-run the relevant-scope tests.
3. Update ${notes}.
Constraints: do not commit or push. ${RESTRAINT_NOTE} ${TAIL_NOTE}`,
    { label: 'dev:arch-fix', phase: 'ArchReview', model: 'sonnet', effort: 'high', schema: FIX_SCHEMA })
  if (archFix === null) return { status: 'agent-failed', at: 'arch-fix' }
  lastJst = archFix.nowJst || lastJst
  log(`[${archFix.nowJst} JST] ArchFix 完了（採用${archFix.adopted.length}件・不採用${archFix.rejected.length}件）`)
  if (archFix.adopted.length > 0) {
    qa = await agent(qaPrompt('This is re-verification after the design-conformance review was applied.'), { label: 'qa:post-arch', phase: 'ArchReview', model: 'fable', effort: 'high', schema: QA_SCHEMA })
    if (qa === null) return { status: 'agent-failed', at: 'qa' }
    lastJst = qa.nowJst || lastJst
    log(`[${qa.nowJst} JST] QA(post-arch) 完了（pass=${qa.pass}${qa.pass ? '' : `・指摘${qa.issues.length}件`}）`)
    logQaIssues(qa)
    if (!qa.pass) return { status: 'qa-failed', impl, qa, archFix }
  }
}

return { status: 'ok', impl, qa, designed: design !== null, archFindings: arch.items.length, archFix }
```

返却の扱い: `status: 'ok'` → レビューモードの確定へ。`'qa-failed'` → QA の `issues` を提示してユーザーに相談。`'agent-failed'` → 1 回だけ `resumeFromRunId` で再開を試み、それでも失敗なら degradation（SKILL.md 手順 6）。

## 雛形 B: claude 系レビューセット（sir-claude-review-set）

1 セット = 最大 3 ラウンド。「レビュー（標準: レビュワー / 敵対: Breaker→Judge）→ 開発者の採用判定・修正・テスト」を収束（High/Medium 採用 0 のクリーンが連続 2 回）まで回し、収束時はセット内で最終 QA まで実施して返る。3 ラウンドごとの続行確認はオーケストレーターがセット間に行う。

`args`: `{ workDir, issueNumber, branch, defaultBranch, mode, startRound, priorSummary, cleanStreak, securityAudit, securityReason, startedAt }`
（`mode`: `'standard' | 'adversarial'`。`startRound`: 通算ラウンドの開始値（1, 4, 7, …）。`priorSummary`: 前セットまでの経緯要約（初回は空文字。継続セットでは**前セット最終ラウンドの採用修正内容〔title/action〕も含める** — 差分スコープをセット跨ぎで連続させるため）。`cleanStreak`: 連続クリーンラウンド数の引き継ぎ値（初回は 0 / 省略可。前セットが `cleanStreak: 1` で 3 ラウンド上限に達した場合、続行セットへ渡すと round 1 が差分スコープ解除の確認ラウンドになり dry-twice 収束がセット境界を跨いで機能する）。`securityAudit`: セキュリティ自動発動時の初回セットのみ true。`securityReason`: 自動発動の理由〔検出したシグナル〕。レンズ S の Breaker プロンプト（監査統合ラウンド）に埋め込まれるため `securityAudit: true` のときは必ず渡す。`startedAt`: 起動直前にオーケストレーターが `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` で実測した開始日時〔開始ログ表示専用・省略可。継続セットの再起動でも再実測して渡す。`agent()` プロンプトへは埋め込まれないため resume のキャッシュ一致に影響しない〕）

```js
export const meta = {
  name: 'sir-claude-review-set',
  description: 'smart-issue-resolve claude 系レビューループ 1 セット（最大 3 ラウンド + 収束時の最終 QA）',
  phases: [
    { title: 'Review', detail: '包括ラウンド（初回セット round 1）は Breaker レンズ S/C/O（敵対）/ レビュワー観点グループ G1/G2/G3（標準）の並列、以降のラウンドは単発 1 体（全観点横断）。敵対は続けて Judge バッチ並列裁定。レンズ S は初回セット round 1 でセキュリティ監査を内蔵。モデルは全ラウンド fable' },
    { title: 'Fix', detail: '開発者エージェントによる採用判定・修正・テスト' },
    { title: 'FinalQA', detail: '収束時の独立最終検証' },
  ],
}

// args は文字列で届く環境があるため正規化する（トップレベルの args. 参照を機能させる防御シム）
args = typeof args === 'string' ? JSON.parse(args) : (args || {})

const ctx = args.workDir + '/context.md'
const notes = args.workDir + '/impl-notes.md'
const diffPath = args.workDir + '/diff.md'

// diff 正本の鮮度ガード用スタンプ期待値。オーケストレーターがセット起動前に startRound で生成し、dev:fix を起動するたびに +1 する
// （エージェントの自己申告に依存しない fail-safe。再生成漏れは次ラウンドで不一致となり、各レビュー役が自前の git 取得へフォールバックする）
let diffRound = args.startRound

const diffNote = (expected, targeted) => `The review target is the entire change on branch ${args.branch}; its diff is provided as the canonical file ${diffPath} (a snapshot of the committed diff origin/${args.defaultBranch}...HEAD plus uncommitted working-tree changes). Read it with the Read tool; do not re-fetch the diff with git yourself.
- Freshness check: the header field 対象ラウンド (target round) must be ${expected}.
- Fallback: only when the file is missing, the target round differs from ${expected}, or the previous round's adopted fixes are clearly not reflected, fetch the diff yourself with git diff origin/${args.defaultBranch}...HEAD plus git status / git diff HEAD (local ${args.defaultBranch} can be stale — always use origin/${args.defaultBranch} as the base; use git diff HEAD, not bare git diff, so staged changes are not dropped = the same range as the canonical diff.md).
- How to read: ${targeted ? 'read the header and the changed-file list (--stat) first; afterwards read only the spots pointed to by the evidence of the counterexamples in your batch, using offset (do not read the whole file — adjudication only needs evidence-scoped verification)' : 'the file is long, so if Read truncates it, advance offset until you have read all of it'}.
- Not included in the snapshot: contents of untracked files, and files created after generation (e.g. the Breaker probe tests named with .breaker-probe.). Read those directly from the repository.
- diff.md is only an input telling you where to look. The basis for judgment is the real code in the repository; reading the relevant files and grepping their surroundings remains mandatory (do not judge from diff excerpts alone).`

const NOW_JST_FIELD = { type: 'string', description: "Completion time in JST: the verbatim output of `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'`" }
const TAIL_NOTE = "Output language: write all output content (structured output fields and any files you write) in Japanese; keep code identifiers, file paths, and commands as-is. Finally, run `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` and put its verbatim output into nowJst."
const ts = (t) => (t ? `[${t} JST] ` : '')
let lastJst = args.startedAt || ''

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['items', 'nowJst'],
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'severity', 'basis', 'detail'],
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['High', 'Medium', 'Low'] },
          category: { type: 'string', enum: ['真の欠陥', '仕様未定'], description: 'Set only by the Judge in adversarial mode' },
          basis: { type: 'string', description: 'Primary evidence such as file path and line numbers' },
          detail: { type: 'string' },
        },
      },
    },
    dismissed: {
      type: 'array',
      items: { type: 'object', required: ['title', 'category'], properties: { title: { type: 'string' }, category: { type: 'string', enum: ['低優先度', 'ノイズ'] } } },
      description: 'Not adopted (keep only count and title for auditability)',
    },
    nowJst: NOW_JST_FIELD,
  },
}

const FIX_SCHEMA = {
  type: 'object',
  required: ['adopted', 'rejected', 'testsPassed', 'diffRegenerated', 'nowJst'],
  properties: {
    adopted: {
      type: 'array',
      items: { type: 'object', required: ['title', 'action', 'severity'], properties: { title: { type: 'string' }, action: { type: 'string' }, severity: { type: 'string', enum: ['High', 'Medium', 'Low'], description: 'Copy the severity of the original finding being adopted (used for the convergence severity floor)' } } },
    },
    rejected: {
      type: 'array',
      items: { type: 'object', required: ['title', 'reason'], properties: { title: { type: 'string' }, reason: { type: 'string' } } },
    },
    testsPassed: { type: 'boolean' },
    diffRegenerated: { type: 'boolean', description: 'Whether regenerating the canonical review diff.md (gen-diff.sh) succeeded. The freshness guard is enforced by the script-side stamp, so this does not change behavior, but it propagates to diffDegraded in the return value as an observability signal (required — do not omit it just because it is not used for the decision)' },
    notes: { type: 'string' },
    nowJst: NOW_JST_FIELD,
  },
}

const QA_SCHEMA = {
  type: 'object',
  required: ['pass', 'executed', 'issues', 'nowJst'],
  properties: {
    pass: { type: 'boolean' },
    executed: { type: 'string' },
    issues: {
      type: 'array',
      items: { type: 'object', required: ['title', 'detail'], properties: { title: { type: 'string' }, detail: { type: 'string' } } },
    },
    nowJst: NOW_JST_FIELD,
  },
}

const BREAK_SCHEMA = {
  type: 'object',
  required: ['counterexamples', 'nowJst'],
  properties: {
    counterexamples: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'scenario', 'verified'],
        properties: {
          title: { type: 'string' },
          scenario: { type: 'string', description: 'The counterexample, attack scenario, or invariant violation' },
          verified: { type: 'string', enum: ['fail', 'UNVERIFIED'], description: 'fail = verified by a probe test / UNVERIFIED = hypothesis that could not be verified by execution' },
          evidence: { type: 'string', description: 'File path, line, test execution results, etc.' },
        },
      },
    },
    nowJst: NOW_JST_FIELD,
  },
}

// レンズ S（セキュリティ）専用スキーマ。監査ラウンドでは security-audit.md を書き出したか（auditWritten）も返す
const BREAK_S_SCHEMA = {
  type: 'object',
  required: ['counterexamples', 'nowJst'],
  properties: {
    counterexamples: BREAK_SCHEMA.properties.counterexamples,
    auditWritten: { type: 'boolean', description: 'Whether security-audit.md was written in the security-audit round (set only by lens S in the audit round)' },
    nowJst: NOW_JST_FIELD,
  },
}

const records = []
const priorSummary = args.priorSummary || ''
const history = () => records.map((r) => `Round ${r.round}: ${r.findings} findings / ${r.adopted} adopted`).join('\n')
const prior = () => (priorSummary || history()) ? `\n## Prior rounds\n${priorSummary}${priorSummary && history() ? '\n' : ''}${history()}\n` : ''

// 攻撃観点のレンズ分割（S/C/O）。union = 現行 Breaker の全観点（内容の追加・削除・改変なし）。レンズ S は監査役を統合
const LENSES = [
  { id: 'S', token: 'sec', label: 'Security',
    aspects: `- Security: authorization bypass, injection, secret leakage, TOCTOU, PII exposure, confused deputy (if ${args.workDir}/security-audit.md exists, always consult it and reflect its threats and attack scenarios)
- Security-related project-specific standards (if provided in context.md, include their violations as attack scenarios)` },
  { id: 'C', token: 'corr', label: 'Correctness/Data',
    aspects: `- Spec: unmet acceptance criteria, contract violations, backward-compatibility breakage, version skew / schema drift
- Regression: breaking existing behavior or callers
- Data integrity & performance: transaction boundaries, atomicity, idempotency (double execution), broken concurrent updates, partial failure, reentrancy, irreversible state changes, N+1 or excessive I/O, computational complexity
- Architecture: layer-responsibility violations, boundary intrusion, unverified execution paths` },
  { id: 'O', token: 'ops', label: 'Ops/Maintainability',
    aspects: `- Operations, maintainability, availability: missing observability, fragile deploy / rollback, excessive coupling, missing timeouts / retries, behavior on failure or dependency degradation, resource exhaustion, single points of failure
- Project-specific standards (if provided in context.md, include their violations as attack scenarios)` },
]

// 単発 Breaker（差分スコープのラウンド 2+ / dry-twice 確認ラウンド用）。aspects は LENSES の結合で生成し、観点 union の不変を構造的に保証する（Issue #113: 分割並列は包括ラウンド限定）
const LENS_ALL = { id: 'ALL', token: 'all', label: 'All aspects', solo: true, aspects: LENSES.map((l) => l.aspects).join('\n') }

// 差分スコープ化: ラウンド 1（初回セット）は全 diff 包括レビュー、以降は直前ラウンドの採用修正差分を重点対象にする（重点付けであり抑制ではない。diff 基準は全体維持）
const fixDelta = (i) => {
  if (args.startRound === 1 && i === 0) return ''
  const last = records[records.length - 1]
  const adoptedItems = (last && last.adoptedItems) || []
  const deltaList = adoptedItems.length
    ? adoptedItems.map((a) => `- ${a.title}: ${a.action}`).join('\n')
    : '(Fixes adopted in earlier sets — see "Prior rounds" above.)'
  return `\n## Delta scope (focus of this round)\nThe previous round adopted the fixes below. Focus on the files / areas they touched and their ripple (callers, dependencies), and hunt first for regressions or inconsistencies newly introduced by these fixes:\n${deltaList}\nThis is prioritization, not restriction: still report obvious critical defects outside this scope. However, limit exhaustive re-reading of unrelated files and new probe-test creation to this focus area; avoid wasteful wide-area exploration.\nDo not demand further hardening or polish of the code these fixes added; raise a finding against a fix only when it introduces an actual defect (a regression, a broken contract, a failed edge case), not because more could be done.\n`
}

// 標準レビュワーの観点グループ分割（G1/G2/G3）。union = 現行の全 9 観点（内容の追加・削除・改変なし）。Breaker のレンズ分割（S/C/O）と同型で、標準モードのレビュワーを 3 グループの並列エージェントにする
const REVIEWER_GROUPS = [
  { id: 'g1', label: 'Spec/Bugs/Tests',
    aspects: `- Spec fulfillment: does the change satisfy the Issue requirements and acceptance criteria?
- Bugs: logic errors, edge cases, boundary conditions, missing error handling
- Test coverage: verification coverage of new / changed logic (happy path, error path, boundary values)` },
  { id: 'g2', label: 'Regression/Data-Performance/Hotspots',
    aspects: `- Regression risk: changes that break existing behavior, tests, or callers
- Data integrity & performance: transaction boundaries, atomicity, idempotency, concurrent-update consistency; N+1, excessive I/O, computational complexity
- Implementation-level hotspots: injection, committed secrets, missing authorization, vulnerable dependencies` },
  { id: 'g3', label: 'Ops-Maintainability/Architecture/Project-standards',
    aspects: `- Operations, maintainability, availability: missing observability; deploy / rollback and config management; excessive coupling and testability; timeouts, retries, degradation on failure, resource exhaustion, single points of failure
- Architecture boundaries: layer-responsibility violations, boundary intrusion
- Conformance to project-specific standards (only if provided in context.md)` },
]

// 単発レビュワー（差分スコープのラウンド 2+ / dry-twice 確認ラウンド用）。aspects は REVIEWER_GROUPS の結合で生成し、観点 union の不変を構造的に保証する（Issue #113: 分割並列は包括ラウンド限定）
const REVIEWER_ALL = { id: 'all', label: 'All aspects', solo: true, aspects: REVIEWER_GROUPS.map((g) => g.aspects).join('\n') }

const RESTRAINT_NOTE = "Execution discipline: complete this role yourself with your own tool calls — do not launch subagents (Agent/Task tools), even to verify or double-check your own work, and do not add verification passes beyond the steps above. Deliver what was asked, at the scope intended, and stop short of actions clearly beyond it. Match the length of your output and any files you write to what the task needs: cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate."

const reviewerGroupPrompt = (round, group, delta) => `You are a reviewer of the implementation for GitHub Issue #${args.issueNumber}${group.solo ? '' : ` (aspect group ${group.id}: ${group.label})`}. From an independent position uninvolved in the implementation, report only defects worth fixing, ${group.solo ? 'covering all aspects' : 'focusing on the aspects of your group'}.
## Input
1. Read ${ctx} (Issue requirements, implementation plan, project-specific standards).
2. Review target (round ${round}):
${diffNote(diffRound)}
${prior()}${delta}
## Review aspects${group.solo ? ' (cover all 9 aspects)' : ` (focus on group ${group.id}; the other groups are covered by other reviewers — do not chase them)`}
${group.aspects}
## Constraints
- Readability, naming, and style are out of scope (only defects worth fixing).
- Report only defects that would change runtime behavior, a contract, or a design decision. Polish an implementer can settle with ordinary judgment — identifier or test naming, comment / docstring / log-message wording, documentation-enumeration completeness — goes to dismissed as 低優先度, not items. Exception: treat such wording or completeness as in scope when it is itself the Issue's deliverable (e.g. documentation-revision Issues).
- Attach evidence (primary sources such as file path and line numbers) and severity to each finding.
- Do not modify code or files (review only). Do not commit.
- If there are no findings, return an empty items array.
${RESTRAINT_NOTE} ${TAIL_NOTE}`

// レンズ別 Breaker プロンプト。プロンプト本体は共通で、攻撃観点だけレンズ定義（lens.aspects）に差し替える。
// レンズ S かつ isAuditRound（securityAudit 初回セット round 1）のときは、監査役を統合して STRIDE 監査 → security-audit.md 書き出し → セキュリティ break を 1 エージェントで実施する（独立の前段監査スロットを消す）
const breakerLensPrompt = (round, lens, delta, isAuditRound) => `You are a Breaker${lens.solo ? '' : ` (lens ${lens.id}: ${lens.label})`}. Do not merely read the implementation for GitHub Issue #${args.issueNumber} — break it. Enumerate counterexamples, attack scenarios, and invariant violations, ${lens.solo ? 'covering all attack aspects' : 'focusing on the aspects of your lens'}. Stay independent of the implementation, and default to skepticism: treat implementations that only hold on the happy path as real weaknesses, and grant no credit to good intentions, partial fixes, or promises of follow-up work.
## Input
1. Read ${ctx} (Issue requirements, implementation plan, project-specific standards).
2. Review target (round ${round}):
${diffNote(diffRound)}
${prior()}${delta}${isAuditRound ? `\n## Security audit (perform in this round, before breaking)\nFrom the STRIDE, authentication / authorization, data flow, secrets, and PII perspectives, enumerate the threats to this change and the attack scenarios to verify, write them to ${args.workDir}/security-audit.md, then break using the security aspects below. Reason for auto-activation: ${args.securityReason}. Set auditWritten to true if you wrote security-audit.md; if you could not, set it to false and still proceed to break with the built-in security aspects.\n` : ''}## Attack aspects${lens.solo ? ' (cover all)' : ` (focus on lens ${lens.id}; the other lenses are covered by other Breakers — do not chase them)`}
${lens.aspects}
## Probe tests
- Where possible, write each hypothesis as a minimal failing test and verify it by running it within the test scope in context.md. Prefix the test filename with the lens token \`${lens.token}-\` and keep \`.breaker-probe.\` as a substring (e.g. \`${lens.token}-foo.breaker-probe.test.ts\`). Never insert the token inside \`.breaker-probe.\` (as in \`.breaker-probe-xxx.\`) — cleanup and QA detect probes by substring-matching \`.breaker-probe.\`, so do not break it.
${lens.solo ? '' : `- All lenses test concurrently in the same worktree, so run only your own probes (\`${lens.token}-*.breaker-probe.\`). If a hypothesis cannot be run because of test-runner contention, mark it verified: UNVERIFIED (the Judge treats it conservatively).\n`}- Discard hypotheses whose test passes, and delete those probe tests yourself before finishing. Report hypotheses whose test fails as verified counterexamples (verified: fail) and leave the test in the tree (the developer later converts adopted ones into regular regression tests and deletes rejected ones).
- Mark hypotheses that cannot be verified by execution as verified: UNVERIFIED.
## Output
- Write the counterexample list (scenario, evidence, test execution results) to ${args.workDir}/breaker-round-${round}-${lens.token}.md (one file per lens, to avoid concurrent overwrite between parallel lenses).
- Return the same content in the structured output counterexamples${isAuditRound ? ', and whether you wrote security-audit.md in auditWritten' : ''}.
Constraints: attack only weaknesses that would change runtime behavior, a contract, or a design decision — do not raise naming, comment / docstring wording, or documentation-completeness nitpicks as counterexamples (unless such wording or completeness is itself the Issue's deliverable). No code changes other than probe tests (writing security-audit.md is allowed). Do not commit. ${RESTRAINT_NOTE} ${TAIL_NOTE}`

const judgeBatchPrompt = (round, batch, batchNum, batchTotal) => `You are the Judge (adjudicator). Another agent (the Breaker) generated counterexamples / attack scenarios; adjudicate them by checking them against the real code in the repository. Do not defer to the Breaker — judge independently. You were involved in neither the implementation nor the counterexample generation. This is batch ${batchNum}/${batchTotal} of the round-${round} counterexamples.
## Input
1. Read ${ctx} (Issue requirements, implementation plan, project-specific standards).
2. Review target (round ${round}):
${diffNote(diffRound, true)}
3. The counterexamples to adjudicate in this batch (handle no others):
${JSON.stringify(batch, null, 2)}
${prior()}
## Adjudication task
Check each counterexample against the real code and classify it into exactly one of these 4 categories (use these exact Japanese values for category):
- 真の欠陥 (true defect): valid as a spec violation, security issue, regression, operations / maintainability / availability problem, data-integrity / performance problem, missing test coverage, architecture violation, or project-specific-standard violation — worth fixing.
- 仕様未定 (spec undecided): the spec is ambiguous and the Breaker made an arbitrary assumption (needs spec confirmation).
- 低優先度 (low priority): valid but low severity; not worth the fix cost.
- ノイズ (noise): unfalsifiable, a misunderstanding, or off the mark (excluded).
## Scoped verification (keep moving steadily)
- Adjudicate only the inline batch above. Do not read or handle other batches or the other entries of ${args.workDir}/breaker-round-${round}-*.md (per-lens Breaker output).
- Limit verification to the files / lines pointed to by each counterexample's evidence. If a counterexample has no evidence, limit verification to the diff's changed range and the places its scenario names. In either case, do not run unrelated wide-area greps or cross-service exploration.
- Keep tool calls progressing steadily within ~3 minutes (do not stall on a single exploration).
- Do not independently hunt for defects the Breaker missed in this batch (avoids duplication across batches).
## Constraints
- Readability, naming, and style are out of scope.
- Classify as 真の欠陥 only counterexamples that can answer all 4 of: (1) what happens, (2) why that code path is vulnerable, (3) the expected impact, (4) a concrete mitigation. Concerns that cannot answer them go to 低優先度 or ノイズ.
- Prefer a few strong, defensible findings over many weak ones.
- Counterexamples that would not change runtime behavior, a contract, or a design decision (naming, comment / docstring wording, documentation completeness) are at most 低優先度 even if technically valid — unless that wording or completeness is itself the Issue's deliverable.
- Do not modify code or files (adjudication only). Do not commit.
- Put only 真の欠陥 and 仕様未定 into items (set category); leave 低優先度 / ノイズ in dismissed with count and title only.
${RESTRAINT_NOTE} ${TAIL_NOTE}`

const fixPrompt = (round, items) => `You are the developer (reviewee) who implemented GitHub Issue #${args.issueNumber}. Judge and apply the round-${round} review findings:
${JSON.stringify(items, null, 2)}
1. Read ${ctx} and ${notes} to restore the implementation context.
2. Classify each finding as 採用 (adopt) or 不採用 (reject), copying each adopted finding's severity into the structured output:
   - Adopt: findings that correctly identify, with evidence, an unmet spec, a bug, a regression risk, or an implementation-level hotspot.
   - Reject: invalid, would cause over-engineering, or out of the Issue scope (record the reason in one line). Even findings the Judge classified as 真の欠陥 may be rejected if fixing them would be overcorrection.
   - Low-severity findings: adopt one only when the fix is local to the finding's immediate site and carries no regression risk; otherwise reject with the reason. Keep each Low fix minimal — do not refactor or expand scope around it.
3. Fix the adopted findings and re-run the relevant-scope tests (do not leave them broken).
4. Clean up the probe tests containing .breaker-probe.: convert the ones corresponding to adopted defects into regular regression tests (rename / relocate); delete the rest.
5. Update ${notes}.
6. Final step (only after fixes, tests, and probe-test cleanup are all done): regenerate the canonical review diff for the next round:
   bash ${args.workDir}/gen-diff.sh origin/${args.defaultBranch} ${round + 1}
   Set diffRegenerated to true on success, or false if the script is missing / exits non-zero (when false, next-round reviewers fall back to fetching the diff via git themselves). Do not hand-edit diff.md.
Constraints: do not commit or push. Do not water down findings by reinterpreting or summarizing them (your decision is only the adopt / reject classification with explicit reasons). ${RESTRAINT_NOTE} ${TAIL_NOTE}`

const qaPrompt = () => `You are an independent QA agent performing the final verification after review-loop convergence, before commit.
1. Read ${ctx} (test policy, acceptance criteria, diff base).
2. Inspect the changes: git diff origin/${args.defaultBranch}...HEAD, plus uncommitted changes via git status / git diff HEAD (use git diff HEAD, not bare git diff, so staged changes are not dropped. Do not use the developer-generated ${diffPath} — independent verification does not trust self-reports, so fetch the diff yourself).
3. Following the test policy in context.md, run the relevant-scope tests and lint yourself.
4. Verify each acceptance criterion of the Issue, one by one.
5. If any file containing .breaker-probe. remains in the change set, report it in issues.
Constraints: do not modify code or files. Do not commit.
Verdict: set pass=true only when all tests pass and the acceptance criteria are met. ${RESTRAINT_NOTE} ${TAIL_NOTE}`

// セキュリティ監査はレンズ S の Breaker に統合済み（securityAudit 初回セット round 1 で STRIDE 監査 → security-audit.md 書き出し → セキュリティ break を 1 エージェントで実施）。独立の前段監査スロットは持たない。auditFailed はレンズ S が監査を書き出せなかった場合に立てる
let auditFailed = false

let converged = false
let status = 'ok'
let judgeDegraded = false
let breakerDegraded = false
let reviewerDegraded = false
let diffDegraded = false
let cleanStreak = args.cleanStreak || 0
const specQuestions = []

log(`${ts(lastJst)}レビューセット開始（mode=${args.mode}・round ${args.startRound}〜${args.startRound + 2}）`)

for (let i = 0; i < 3; i++) {
  const round = args.startRound + i
  // dry-twice: 前ラウンドがクリーン（指摘0/採用0）だった直後は確認ラウンド。差分スコープを解除しフルスコープで見直す（揺らぎ由来の見逃しを拾う）
  const isConfirmRound = cleanStreak === 1
  const delta = isConfirmRound ? '' : fixDelta(i)
  // 分割並列は包括ラウンド（初回セット round 1）限定。差分スコープのラウンド 2+・確認ラウンド・継続セットは単発 1 体（全観点横断）で実施する（Issue #113: トークン・ストール露出の抑制）
  const comprehensive = args.startRound === 1 && i === 0 && !isConfirmRound
  // レビュー役（レビュワー / Breaker / Judge）のモデル。監視・レビューは Fable が担うため、包括ラウンドと以降のラウンドで区別せず全ラウンド fable
  const reviewModel = 'fable'
  const launchDesc = args.mode === 'adversarial'
    ? `Breaker ${comprehensive ? '3 レンズ（S/C/O）並列' : '単発 1 体'}（${reviewModel}）`
    : `レビュワー ${comprehensive ? '3 グループ（G1/G2/G3）並列' : '単発 1 体'}（${reviewModel}）`
  log(`${ts(lastJst)}レビューラウンド ${round}（${args.mode}）開始${isConfirmRound ? '（確認ラウンド: 連続クリーン確認・差分スコープ解除）' : ''} — ${launchDesc}を起動`)
  let findings = null
  if (args.mode === 'adversarial') {
    // 包括ラウンドは Breaker を観点別レンズ（S/C/O）に分割しフラット parallel で同時起動、以降は単発 Breaker（LENS_ALL）1 体。レンズ S は securityAudit 初回セット round 1 のとき監査を内蔵実施する（前段の独立監査スロットを消す）
    const isAuditRound = !!args.securityAudit && i === 0
    const lenses = comprehensive ? LENSES : [LENS_ALL]
    const lensResults = await parallel(lenses.map((lens) => () =>
      agent(breakerLensPrompt(round, lens, delta, isAuditRound && lens.id === 'S'),
        { label: `breaker:r${round}-${lens.token}`, phase: 'Review', model: reviewModel, effort: 'high',
          schema: (isAuditRound && lens.id === 'S') ? BREAK_S_SCHEMA : BREAK_SCHEMA })))
    const okLenses = lensResults.filter(Boolean)
    if (okLenses.length === 0) { status = 'agent-failed'; break }
    if (okLenses.length < lenses.length) { breakerDegraded = true; log(`breaker r${round}: ${lenses.length - okLenses.length}/${lenses.length} レンズ失敗（部分反例で続行・未探索の観点あり）`) }
    if (isAuditRound) {
      const sIdx = lenses.findIndex((l) => l.id === 'S')
      const sResult = sIdx >= 0 ? lensResults[sIdx] : null
      if (sResult === null || sResult.auditWritten === false) { auditFailed = true; log(`レンズ S の監査書き出しに失敗（内蔵セキュリティ観点のみで続行）`) }
    }
    const breakerTimes = okLenses.map((r) => r.nowJst).filter(Boolean).sort()
    if (breakerTimes.length) { lastJst = breakerTimes[breakerTimes.length - 1]; log(`[${lastJst} JST] breaker r${round} 完了（${okLenses.length}/${lenses.length} レンズ・反例${okLenses.reduce((n, r) => n + (r.counterexamples || []).length, 0)}件）`) }
    const scen = okLenses.flatMap((r) => r.counterexamples || [])
    const BATCH = 4
    const batches = []
    for (let b = 0; b < scen.length; b += BATCH) batches.push(scen.slice(b, b + BATCH))
    if (batches.length > 0) log(`${ts(lastJst)}judge r${round} 起動（反例${scen.length}件・${batches.length}バッチ並列）`)
    const batchResults = batches.length === 0 ? [] : await parallel(batches.map((batch, bi) => () =>
      agent(judgeBatchPrompt(round, batch, bi + 1, batches.length),
        { label: `judge:r${round}-b${bi + 1}`, phase: 'Review', model: reviewModel, effort: 'high', schema: FINDINGS_SCHEMA })))
    const ok = batchResults.filter(Boolean)
    if (batches.length > 0 && ok.length === 0) { status = 'agent-failed'; break }
    if (ok.length < batches.length) { judgeDegraded = true; log(`judge r${round}: ${batches.length - ok.length}/${batches.length} バッチ失敗（部分裁定で続行・未裁定の反例あり）`) }
    const judgeTimes = ok.map((r) => r.nowJst).filter(Boolean).sort()
    if (judgeTimes.length) { lastJst = judgeTimes[judgeTimes.length - 1]; log(`[${lastJst} JST] judge r${round} 完了（${ok.length}/${batches.length} バッチ）`) }
    findings = { items: ok.flatMap((r) => r.items || []), dismissed: ok.flatMap((r) => r.dismissed || []) }
  } else {
    // 包括ラウンドは標準レビュワーを観点別グループ（G1/G2/G3）に分割しフラット parallel で同時起動、以降は単発レビュワー（REVIEWER_ALL）1 体。union = 現行 9 観点で内容は不変。Judge 段は無く各グループの items を単純結合する（グループ間の重複指摘は fix の採用判定で統合。敵対レンズ重複と同じ扱い）。一部グループ失敗は reviewerDegraded で伝播
    const groups = comprehensive ? REVIEWER_GROUPS : [REVIEWER_ALL]
    const groupResults = await parallel(groups.map((group) => () =>
      agent(reviewerGroupPrompt(round, group, delta),
        { label: `reviewer:r${round}-${group.id}`, phase: 'Review', model: reviewModel, effort: 'high', schema: FINDINGS_SCHEMA })))
    const okGroups = groupResults.filter(Boolean)
    if (okGroups.length === 0) { status = 'agent-failed'; break }
    if (okGroups.length < groups.length) { reviewerDegraded = true; log(`reviewer r${round}: ${groups.length - okGroups.length}/${groups.length} グループ失敗（部分レビューで続行・未探索の観点あり）`) }
    const reviewerTimes = okGroups.map((r) => r.nowJst).filter(Boolean).sort()
    if (reviewerTimes.length) { lastJst = reviewerTimes[reviewerTimes.length - 1]; log(`[${lastJst} JST] reviewer r${round} 完了（${okGroups.length}/${groups.length} グループ・指摘${okGroups.reduce((n, r) => n + (r.items || []).length, 0)}件）`) }
    findings = { items: okGroups.flatMap((r) => r.items || []), dismissed: okGroups.flatMap((r) => r.dismissed || []) }
  }
  if (findings === null) { status = 'agent-failed'; break }
  // クリーン判定（重大度フロア）: 「指摘0件」「真の欠陥0件（仕様未定のみ）」「High/Medium の採用0件」を統一的に「クリーン」とし、連続 2 回（cleanStreak >= 2）で収束する。Low のみの採用はクリーンを保つ（軽微修正で収束をリセットしない）。1 回目クリーンでは即 break せず確認ラウンドへ進む
  const specItems = findings.items.filter((it) => it.category === '仕様未定')
  specQuestions.push(...specItems)
  const trueDefects = findings.items.filter((it) => it.category !== '仕様未定')
  // ラウンド結果の可視化: 指摘の内訳と各タイトルを log で出す（件数上限つき）
  log(`${ts(lastJst)}ラウンド ${round} レビュー結果: ${args.mode === 'adversarial' ? `真の欠陥${trueDefects.length}件・仕様未定${specItems.length}件・除外${(findings.dismissed || []).length}件` : `指摘${findings.items.length}件・除外${(findings.dismissed || []).length}件`}`)
  for (const it of findings.items.slice(0, 10)) log(`- [${it.severity || '-'}] ${it.title}${it.category === '仕様未定' ? '〔仕様未定〕' : ''}`)
  if (findings.items.length > 10) log(`- …他${findings.items.length - 10}件`)
  let clean = false
  if (findings.items.length === 0 || trueDefects.length === 0) {
    records.push({ round, findings: findings.items.length, adopted: 0, rejected: [], dismissed: (findings.dismissed || []).length })
    clean = true
  } else {
    const fix = await agent(fixPrompt(round, trueDefects), { label: `dev:fix-r${round}`, phase: 'Fix', model: 'sonnet', effort: 'high', schema: FIX_SCHEMA })
    // fix を起動した時点で diff.md は次ラウンド用に再生成されているべき。成否・自己申告によらず期待スタンプを進める
    // （再生成漏れは次ラウンドでスタンプ不一致となり、各レビュー役が自前の git 取得へフォールバックする ＝ 安全側）
    diffRound = round + 1
    if (fix === null) { status = 'agent-failed'; break }
    lastJst = fix.nowJst || lastJst
    const adoptedMajor = fix.adopted.filter((a) => a.severity !== 'Low').length
    log(`[${fix.nowJst} JST] dev fix r${round} 完了（採用${fix.adopted.length}件〔High/Medium ${adoptedMajor}・Low ${fix.adopted.length - adoptedMajor}〕・不採用${fix.rejected.length}件${fix.testsPassed ? '' : '・テスト失敗'}）`)
    for (const a of fix.adopted.slice(0, 10)) log(`- 採用: ${a.title}`)
    if (fix.adopted.length > 10) log(`- 採用: …他${fix.adopted.length - 10}件`)
    for (const rj of fix.rejected.slice(0, 5)) log(`- 不採用: ${rj.title}（${rj.reason}）`)
    if (fix.rejected.length > 5) log(`- 不採用: …他${fix.rejected.length - 5}件`)
    if (fix.diffRegenerated === false) { diffDegraded = true; log(`dev fix r${round}: diff.md の再生成に失敗（次ラウンドのレビュー役は自前の git 取得へフォールバックする）`) }
    records.push({ round, findings: findings.items.length, adopted: fix.adopted.length, adoptedMajor, rejected: fix.rejected, dismissed: (findings.dismissed || []).length, adoptedItems: fix.adopted })
    if (!fix.testsPassed) { status = 'tests-failing'; break }
    // 重大度フロア: High/Medium の採用が 0 ならクリーン（Low のみの採用は修正・テスト済みのままクリーン扱い）
    if (adoptedMajor === 0) clean = true
  }
  if (clean) {
    cleanStreak++
    if (cleanStreak >= 2) { converged = true; log(`${ts(lastJst)}ラウンド ${round}: クリーン（連続 2 回）→ 収束`); break }
    log(`${ts(lastJst)}ラウンド ${round}: クリーン（連続 ${cleanStreak} 回）。差分スコープを解除した確認ラウンドで再検証する`)
  } else {
    cleanStreak = 0
  }
}

let finalQa = null
if (converged) {
  if (args.mode === 'adversarial') {
    await agent(`If any files whose names contain .breaker-probe. remain in the current change set (check via git status / git diff), delete them all. Regression tests for adopted defects were already renamed by the developer, so any file still containing .breaker-probe. in its name is throwaway by definition. Make no other changes. If none remain, do nothing. Do not commit or push. Output language: Japanese.`,
      { label: 'dev:probe-cleanup', phase: 'FinalQA', model: 'sonnet', effort: 'low' })
  }
  finalQa = await agent(qaPrompt(), { label: 'qa:final', phase: 'FinalQA', model: 'fable', effort: 'high', schema: QA_SCHEMA })
  if (finalQa === null) { status = 'agent-failed' } else {
    lastJst = finalQa.nowJst || lastJst
    log(`[${finalQa.nowJst} JST] FinalQA 完了（pass=${finalQa.pass}${finalQa.pass ? '' : `・指摘${finalQa.issues.length}件`}）`)
    for (const it of (finalQa.pass ? [] : finalQa.issues.slice(0, 5))) log(`- QA指摘: ${it.title}`)
  }
}

// 仕様未定は確認ラウンド（未変更コードの再レビュー）等で同一項目が再収集されうるため、返却前に title で重複排除する（確認ラウンドで新規に見つかった仕様確認は保持し、完全な重複のみ除く）
const uniqueSpecQuestions = specQuestions.filter((q, i) => specQuestions.findIndex((o) => o.title === q.title) === i)
return { converged, status, records, finalQa, specQuestions: uniqueSpecQuestions, auditFailed, judgeDegraded, breakerDegraded, reviewerDegraded, diffDegraded, cleanStreak }
```

返却の扱い:

- `converged: true` → まず `specQuestions` が空であることを確認する（非空なら下記の `specQuestions` 処理を先に行い、仕様確定で修正が生じたら未収束として次セットへ回す。この経路ではコミットしない）。空なら `finalQa.pass` を確認して「収束後のコミット・PR 作成」へ（`pass: false` なら自動コミットを中止し issues を提示して相談）。加えて `judgeDegraded: true` のときは未裁定の反例が残るため、収束していても自動コミット前にユーザーへ確認する（下記 `judgeDegraded`）
- `converged: false` かつ `status: 'ok'`（3 ラウンド消化）→ 上限チェック: `records` の残指摘を要約提示して AskUserQuestion（続行 / 打ち切り / 中止）。続行なら `startRound` を +3、`priorSummary` に経緯要約 + **前セット最終ラウンドの採用修正内容（`records` 末尾の `adoptedItems` の title/action）** を入れ、**返却の `cleanStreak` も次セットの `args` に引き継いで**同じ scriptPath で再起動する（`startedAt` は再実測して渡す。差分スコープをセット跨ぎで連続させる。`cleanStreak: 1` を引き継ぐと次セット round 1 が差分スコープ解除の確認ラウンドになり dry-twice 収束がセット境界を跨いで機能する）
- `specQuestions` が空でない → 裁定「仕様未定」の項目。オーケストレーターが AskUserQuestion でユーザーに仕様を確認し、確定内容を `{作業Dir}/context.md`（追加指示）へ追記する。修正が必要になった場合は未収束として扱い、次セット（または開発者修正 1 回 + 再収束確認）へ進む
- `auditFailed: true` → レンズ S の Breaker がセキュリティ監査（`security-audit.md` の書き出し）を完了できず、内蔵のセキュリティ観点のみで break された（監査の欠落）。完了報告に明記する
- `breakerDegraded: true` → 一部の Breaker レンズ（S/C/O のいずれか）が失敗し、その観点の反例が生成されないまま収束扱いになった。未探索の攻撃観点が残り、`finalQa`（テスト・受け入れ基準の検証）は当該クラスの欠陥をバックストップしない。完了報告に明記し、自動コミット前にユーザーへ確認する（`auditFailed` / `judgeDegraded` と同型の劣化伝播）
- `reviewerDegraded: true` → 標準モードで一部のレビュワー観点グループ（G1/G2/G3 のいずれか）が失敗し、その観点の指摘が生成されないまま収束扱いになった。未探索のレビュー観点が残り、`finalQa`（テスト・受け入れ基準の検証）は当該クラスの欠陥をバックストップしない。完了報告に明記し、自動コミット前にユーザーへ確認する（`breakerDegraded` と同型の劣化伝播）
- `judgeDegraded: true` → 一部の Judge バッチが失敗し、その反例（最大 4 件/バッチ）が未裁定のまま収束扱いになった。`finalQa` はテスト・受け入れ基準の検証で、敵対レビューが対象とする設計・保守・可用性クラスの未裁定欠陥はバックストップしない。完了報告に明記し、自動コミット前にユーザーへ確認する（`auditFailed` と同型の劣化伝播）
- `diffDegraded: true` → 開発者エージェントがレビュー正本 `diff.md` の再生成に失敗し、以降のラウンドのレビュー役が自前の git 取得へフォールバックした。トークン最適化の劣化であり走査範囲・レビュー品質は従来動作に戻るだけなので、他の `*Degraded` と違って自動コミットは止めない。完了報告に明記する（`docs/empirical-tuning/review-loop-speedup.md` のフォールバック発生回数の採取源でもある）
- `status: 'tests-failing'` → テストが壊れたままなので状況を提示して相談（そのまま次セットへ進まない）
- `status: 'agent-failed'` → 1 回だけ `resumeFromRunId` で再開（**再開前に diff.md を作り直さない** — 上記「レビュー正本 diff.md」の生成責務）、それでも失敗なら「フォールバック」（claude 系）へ。`converged: true` で `finalQa` が取得できなかった場合は、雛形 E を単発起動して最終 QA を補完する（QA 未実施のまま自動コミットしない）

> **同期ノート**: 雛形 B（`sir-claude-review-set`）の構造は `smart-issue-plan/references/agent-orchestration.md` の計画レビューセット雛形（`sip-plan-review-set`）へ移植済み。次を**両者で同期する**（片方の構造を変えたら両方更新すること）:
> - セット制御（`startRound` / `priorSummary` / `cleanStreak` / `records`）・収束判定・null ガード・`auditFailed` / `specQuestions` / `judgeDegraded` / `breakerDegraded` / `reviewerDegraded` の経路
> - 敵対モード Judge のバッチ並列化（Breaker 出力を ≤4 件/バッチに分割し `parallel` で並列裁定・`effort: 'high'`〔Issue #111 で max 化 → ≤4 件/バッチの有界作業量に max は過剰として Issue #113 で high へ戻した〕・evidence 限定照合・一部バッチ失敗は `judgeDegraded` フラグで伝播）
> - **Breaker のレンズ分割並列化（包括ラウンド限定）**（攻撃観点を S/C/O の 3 レンズに分割し `LENSES` 定義 + フラット `parallel` で同時起動。union = 現行 Breaker の全観点で内容は不変。一部レンズ失敗は `breakerDegraded` で伝播。分割は包括ラウンド〔初回セット round 1〕限定で、差分スコープのラウンド 2+・確認ラウンド・継続セットは単発 Breaker〔`LENS_ALL` = `LENSES` の aspects 結合で union 不変を構造的に保証・probe トークン `all-`〕1 体で実施する — Issue #113）
> - **標準レビュワーのグループ分割並列化（包括ラウンド限定）**（標準モードのレビュワーを観点別グループ G1/G2/G3 の 3 グループに分割し `REVIEWER_GROUPS` 定義 + フラット `parallel` で同時起動。union = 現行の全 9 観点で内容は不変。Judge 段は無く各グループの `items` を単純結合し、グループ間の重複指摘は fix / plan-editor の採用判定で統合する〔敵対レンズ重複と同じ扱い〕。一部グループ失敗は `reviewerDegraded` で伝播。分割は包括ラウンド〔初回セット round 1〕限定で、以降は単発レビュワー〔`REVIEWER_ALL` = `REVIEWER_GROUPS` の aspects 結合で union 不変を構造的に保証〕1 体で実施する — Issue #113）
> - **dry-twice 収束判定（重大度フロア。Issue #134）**（「指摘 0 / 真の欠陥 0〔仕様未定のみ〕/ **High/Medium の採用 0**〔`FIX_SCHEMA.adopted[].severity` の echo で判定。Low のみの採用は修正・テスト済みのままクリーン扱い＝軽微修正で収束をリセットしない。`records[].adoptedMajor` に High/Medium 採用数を保持〕」を統一的に「クリーン」とし、連続 2 回〔`cleanStreak >= 2`〕で収束する。1 回目クリーン後の確認ラウンドは差分スコープを解除〔`delta = ''`〕した fresh エージェントで再検証する。`cleanStreak` を `args` と返却で引き継ぎ、`cleanStreak: 1` のまま 3 ラウンド上限に達したケースはセット境界を跨いで連続 2 クリーンを成立させる）
> - **役割別モデル配分（設計・指示 = opus / 実装 = sonnet / 監視・レビュー = fable）**（標準レビュワー・Breaker・Judge バッチのモデルは `reviewModel` = `'fable'` で、包括ラウンドと以降のラウンドを区別しない〔Issue #142 の「包括ラウンドのみ opus・以降は sonnet」配分を置き換えた。切り戻しのレバーは `reviewModel` の 1 行〕。独立 QA〔`qa:*`〕と設計整合レビュー〔`architect:review`〕も監視・レビュー役として `'fable'`、開発者〔`dev:implement` / `dev:qa-fix-*` / `dev:arch-fix` / `dev:fix-r*`〕は指示に従う実装役として `'sonnet'`、設計〔`architect:design`〕は `'opus'`、probe-cleanup は `'sonnet'` / `'low'` のまま。effort は役割ごとに据え置く〔Judge バッチ `'high'`＝上記の Issue #113 戻し、発見役〈レビュワー / Breaker〉`'high'`＝Issue #134 で `'max'` から降格 — Opus 5 プロンプトガイド「レビュー精度は低 effort でも維持され、effort が主なコスト・時間レバー」、`architect:review` `'max'`〕。開発者だけは sonnet 化に合わせて `'max'` → `'high'`〔Sonnet 5.5 は effort が再較正されており、公式ガイドが `max` を「評価で品質向上が確認できた場合のみ」とするため〕。plan 側の plan-editor は設計・指示役として `'opus'` / `'max'`）
> - **セキュリティ監査役のレンズ S 統合**（`securityAudit` 初回セット round 1 でレンズ S が STRIDE 監査 → `security-audit.md` 書き出し → break を 1 エージェントで実施。独立の前段監査スロットは削除。`auditWritten` フラグで「監査のみ失敗」を `auditFailed` として区別）
> - **差分スコープ化**（`records[].adoptedItems` に採用修正の title/action を保持し、ラウンド 2+ の Breaker/レビュワーを直前ラウンドの修正差分とその波及に重点付けする `fixDelta()`。ラウンド 1 は全 diff 包括レビュー。diff 基準は全体維持で重点付けであり抑制ではない。差分スコープの指示には「前ラウンドの採用修正が追加したコードへの、さらなる強化・磨き込み要求の禁止〔回帰・契約破壊・エッジケース失敗など実欠陥のみ指摘可〕」を含む — 自己増殖チェーンの抑制。Issue #134）
> - **軽微指摘フィルタ + Low 採用規律（Issue #134）**（レビュワー / Breaker / Judge に「実行時挙動・契約・設計判断を変えない指摘〔識別子 / テスト命名・コメント / docstring / ログ文言・ドキュメント列挙の完全性〕は items / 反例にせず 低優先度」を明示〔文言・列挙の完全性が Issue の成果物そのものであるドキュメント改訂系 Issue は除く〕。fix / plan-editor の Low 採用規律は resolve = 「局所・無リスクの場合のみ採用・最小修正」/ plan = 「原則不採用・採用時も最小編集」と意図的に非対称 — コードの Low 修正は安価で回帰テストに守られるが、計画の Low 反映は計画を太らせ次ラウンドの攻撃面になるため）
> - **プロンプトの英語化 + 進捗ログ規約（Issue #122）**（`agent()` プロンプト・スキーマ description は英語、出力内容・`log()`・カテゴリ enum 値は日本語。`TAIL_NOTE` による日本語出力 + `nowJst`〔`%Y-%m-%d %H:%M:%S`〕指示、`args.startedAt` の開始ログ、`lastJst` 導出のラウンド開始 / judge 起動ログ、ラウンド終了時の指摘・採用内訳ログ〔件数上限つき〕）
> - **Opus 抑制ノート（`RESTRAINT_NOTE`）**（Opus 5 プロンプトガイド準拠）: probe-cleanup〔`sonnet` / `low` の機械的な後始末〕を除く全 `agent()` のプロンプト末尾（`TAIL_NOTE` の直前）に共通の英語抑制ノートを付す — サブエージェント起動・委任の禁止（検証目的含む。自分のツールコールで完結）／手順に無い追加検証パスの禁止／依頼スコープの維持／出力・書き出しファイルの簡潔化（filler・冗長サマリ・boilerplate の禁止）。主目的は上位モデル〔opus / fable〕の過剰処理〔サブエージェント多量起動・冗長出力〕の抑制。内容は sonnet の開発者役にも無害なため、付与範囲はモデルではなく役割で決める（fable の QA・雛形 C の監査役 / Breaker にも付く）
>
> plan 側はレビュー対象が計画テキスト（diff ではない）で、コード検証用の機構（反例テスト・probe 命名の不変条件・QA / 最終 QA・probe 後始末等）を持たない点が意図的に異なる（差分スコープは「plan-editor の採用計画修正が触れた計画節＋影響領域」に読み替える。Breaker のフィールド名は resolve = `counterexamples` / plan = `scenarios`）。
>
> **probe 命名の不変条件（resolve のみ・硬い制約）**: レンズ Breaker は反例テストを同一ワークツリーに書くため、レンズ固有トークン（`sec-` / `corr-` / `ops-`、単発ラウンドは `all-`）を **`.breaker-probe.` の外側（前方セグメント）** に付け、`.breaker-probe.` を部分文字列として必ず保持する（例: `sec-foo.breaker-probe.test.ts`）。probe-cleanup・QA・fix は `.breaker-probe.` のサブストリング一致で検出するため、トークンを `.breaker-probe.` の**間へ挟む**（`.breaker-probe-sec.`）と検出漏れ→使い捨てテスト残留を招く。
>
> **diff 正本ファイル化は雛形 B 専用（sip へ持ち込まない）**: `{作業Dir}/diff.md`（`assets/gen-diff.sh` で生成）・スタンプによる鮮度ガード（`diffRound`）・fix エージェントのラウンド境界での再生成は、レビュー対象が git diff であることに依存する**コード専用機構**である。plan 側はレビュー対象が `plan.md` で既にファイル正本のため移植しない（sip 側の同期ノート「同期しないもの」に記載済み）。単体スキル `code-reviewer` / `code-reviewer-adversarial` は `{作業Dir}` 機構を持たないため対象外（Issue #115）。
>
> **claude / codex 系の非対称**: 雛形 C（`sir-codex-breaker`）の Breaker はレンズ分割せず単発のまま（Codex 利用制限中のため本 Issue では現状維持）。claude 系だけがレンズ分割・差分スコープ化・diff 正本ファイル化される非対称を許容する。
>
> また、雛形 B の `reviewerGroupPrompt` / `breakerLensPrompt` / `judgeBatchPrompt`（レビュー観点・攻撃観点・4 分類裁定基準）と雛形 C（`sir-codex-breaker`）の Breaker プロンプトは、単体スキル `code-reviewer`（`--isolated` の単発隔離レビュー）・`code-reviewer-adversarial`（`--claude-judge` の Breaker×Judge）へも移植済み。攻撃観点（レンズの union で表現される内容）・裁定基準を変更したら、これら単体スキルの `references/agent-orchestration.md` も**英語表現のまま**同期する（レンズ分割・差分スコープ・バッチ並列化は resolve/plan 間の構造同期で、攻撃観点・裁定基準の内容を変えないため単体スキルへの内容同期は不要。cra の Judge バッチ並列化 + miss-finder 分離は cra 側で別途実装）。マスターの同期対象一覧は CLAUDE.md「スキル改修時の注意」を参照。

## 雛形 C: codex 敵対モードの Breaker（sir-codex-breaker）

codex 敵対モード（--codex-advs-review-loop / セキュリティ自動発動）のラウンドで、Judge（Codex）に渡す反例を独立 Fable エージェント（監視・レビュー役）が生成する。1 ラウンド 1 起動。監査役・Breaker の effort は `high`（発見役を high とする Issue #134 と揃える）。

`args`: `{ workDir, issueNumber, branch, defaultBranch, round, priorSummary, securityAudit, securityReason, startedAt }`（`securityAudit` はセキュリティ自動発動時のラウンド 1 のみ true。`securityReason`: 自動発動の理由〔検出したシグナル〕。監査役プロンプトに埋め込まれるため `securityAudit: true` のときは必ず渡す。`startedAt`: 起動直前に実測した開始日時〔開始ログ表示専用・省略可〕）

```js
export const meta = {
  name: 'sir-codex-breaker',
  description: 'codex 敵対モードの Breaker（独立 Fable）1 ラウンド分',
  phases: [
    { title: 'Audit', detail: 'セキュリティ監査観点の注入（自動発動時・ラウンド 1 のみ）' },
    { title: 'Break', detail: '反例・攻撃シナリオ生成と反例テスト実行' },
  ],
}

// args は文字列で届く環境があるため正規化する（トップレベルの args. 参照を機能させる防御シム）
args = typeof args === 'string' ? JSON.parse(args) : (args || {})

const ctx = args.workDir + '/context.md'
const diffNote = `The review target is the entire change on the current branch ${args.branch} (git diff origin/${args.defaultBranch}...HEAD plus uncommitted changes visible via git status / git diff). Local ${args.defaultBranch} can be stale — always diff against origin/${args.defaultBranch}.`

const NOW_JST_FIELD = { type: 'string', description: "Completion time in JST: the verbatim output of `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'`" }
const TAIL_NOTE = "Output language: write all output content (structured output fields and any files you write) in Japanese; keep code identifiers, file paths, and commands as-is. Finally, run `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` and put its verbatim output into nowJst."
const ts = (t) => (t ? `[${t} JST] ` : '')
let lastJst = args.startedAt || ''

const BREAK_SCHEMA = {
  type: 'object',
  required: ['counterexamples', 'nowJst'],
  properties: {
    counterexamples: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'scenario', 'verified'],
        properties: {
          title: { type: 'string' },
          scenario: { type: 'string' },
          verified: { type: 'string', enum: ['fail', 'UNVERIFIED'] },
          evidence: { type: 'string' },
        },
      },
    },
    nowJst: NOW_JST_FIELD,
  },
}

const AUDIT_SCHEMA = {
  type: 'object',
  required: ['summary', 'nowJst'],
  properties: {
    summary: { type: 'string', description: 'Gist of the attack scenarios (within 15 lines)' },
    nowJst: NOW_JST_FIELD,
  },
}

const RESTRAINT_NOTE = "Execution discipline: complete this role yourself with your own tool calls — do not launch subagents (Agent/Task tools), even to verify or double-check your own work, and do not add verification passes beyond the steps above. Deliver what was asked, at the scope intended, and stop short of actions clearly beyond it. Match the length of your output and any files you write to what the task needs: cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate."

log(`${ts(lastJst)}Breaker ラウンド ${args.round} 開始${args.securityAudit ? '（セキュリティ監査つき）' : ''}`)

let auditNote = ''
let auditFailed = false
if (args.securityAudit) {
  const audit = await agent(`You are a security auditor. Ahead of the adversarial review of the implementation, provide attack-scenario perspectives.
1. Read ${ctx}.
2. ${diffNote}
3. From the STRIDE, authentication / authorization, data flow, secrets, and PII perspectives, enumerate the threats to this change and the attack scenarios that should be verified.
4. Write them to ${args.workDir}/security-audit.md.
Reason for auto-activation: ${args.securityReason}
Constraints: do not modify repository source files (writing security-audit.md is allowed). Do not commit or push. Final output: put the gist of the attack scenarios (within 15 lines) into summary. ${RESTRAINT_NOTE} ${TAIL_NOTE}`,
    { label: 'security:audit', phase: 'Audit', model: 'fable', effort: 'high', schema: AUDIT_SCHEMA })
  if (audit) {
    auditNote = `\n## Security-audit perspectives (must be reflected in your attack scenarios)\n${audit.summary}\nDetails: ${args.workDir}/security-audit.md\n`
    lastJst = audit.nowJst || lastJst
    log(`[${audit.nowJst} JST] セキュリティ監査 完了`)
  } else {
    auditFailed = true
  }
}

const breaker = await agent(`You are a Breaker. Do not merely read the implementation for GitHub Issue #${args.issueNumber} — break it. Enumerate counterexamples, attack scenarios, and invariant violations. Stay independent of the implementation, and default to skepticism: treat implementations that only hold on the happy path as real weaknesses, and grant no credit to good intentions, partial fixes, or promises of follow-up work.
## Input
1. Read ${ctx} (Issue requirements, implementation plan, project-specific standards).
2. ${diffNote} (round ${args.round})
${args.priorSummary ? `\n## Prior rounds\n${args.priorSummary}\n` : ''}${auditNote}
## Attack aspects (cover all)
- Security: authorization bypass, injection, secret leakage, TOCTOU, PII exposure, confused deputy (if ${args.workDir}/security-audit.md exists, always consult it and reflect its threats and attack scenarios)
- Spec: unmet acceptance criteria, contract violations, backward-compatibility breakage, version skew / schema drift
- Regression: breaking existing behavior or callers
- Operations, maintainability, availability: missing observability, fragile deploy / rollback, excessive coupling, missing timeouts / retries, behavior on failure or dependency degradation, resource exhaustion, single points of failure
- Data integrity & performance: transaction boundaries, atomicity, idempotency (double execution), broken concurrent updates, partial failure, reentrancy, irreversible state changes, N+1 or excessive I/O, computational complexity
- Architecture: layer-responsibility violations, boundary intrusion, unverified execution paths
- Project-specific standards (if provided in context.md, include their violations as attack scenarios)
## Probe tests
- Where possible, write each hypothesis as a minimal failing test and verify it by running it within the test scope in context.md. The test filename must contain .breaker-probe.
- Discard hypotheses whose test passes, and delete those probe tests yourself before finishing. Report hypotheses whose test fails as verified counterexamples (verified: fail) and leave the test in the tree.
- Mark hypotheses that cannot be verified by execution as verified: UNVERIFIED.
## Output
- Write the counterexample list (scenario, evidence, test execution results) to ${args.workDir}/breaker-round-${args.round}.md.
- Return the same content in the structured output counterexamples.
Constraints: no code changes other than probe tests. Do not commit. ${RESTRAINT_NOTE} ${TAIL_NOTE}`,
  { label: 'breaker:r' + args.round, phase: 'Break', model: 'fable', effort: 'high', schema: BREAK_SCHEMA })
if (breaker === null) return { status: 'agent-failed' }
lastJst = breaker.nowJst || lastJst
log(`[${breaker.nowJst} JST] breaker r${args.round} 完了（反例${breaker.counterexamples.length}件）`)
for (const c of breaker.counterexamples.slice(0, 10)) log(`- [${c.verified}] ${c.title}`)
if (breaker.counterexamples.length > 10) log(`- …他${breaker.counterexamples.length - 10}件`)

return { status: 'ok', counterexamples: breaker.counterexamples, breakerFile: args.workDir + '/breaker-round-' + args.round + '.md', auditFailed }
```

返却の `counterexamples`（と `breakerFile` の内容）を [../assets/codex-judge-prompt.md](../assets/codex-judge-prompt.md) の「4. Breaker の反例リスト」に埋めて `codex:rescue` を呼ぶ。

## 雛形 D: 開発者の採用判定・修正（sir-dev-fix）

codex 系ラウンドで、Codex のレビュー結果を開発者エージェントが判定・反映する。起動前にオーケストレーターがレビュー結果を `{作業Dir}/findings-round-<N>.md` に書き出しておく（標準モード: Codex の指摘全件、敵対モード: 裁定の真の欠陥 + ユーザー確認で仕様が確定した項目。いずれも要約・取捨選択・再解釈をしない。物理ゲート: このファイルが無ければ起動しない）。

`args`: `{ workDir, issueNumber, round, startedAt }`（`startedAt`: 起動直前に実測した開始日時〔開始ログ表示専用・省略可〕）

```js
export const meta = {
  name: 'sir-dev-fix',
  description: 'レビュー指摘の採用判定と修正（開発者エージェント・codex 系ラウンド用）',
  phases: [{ title: 'Fix', detail: '採用 / 不採用の判定・修正・テスト再実行' }],
}

// args は文字列で届く環境があるため正規化する（トップレベルの args. 参照を機能させる防御シム）
args = typeof args === 'string' ? JSON.parse(args) : (args || {})

const ctx = args.workDir + '/context.md'
const notes = args.workDir + '/impl-notes.md'

const NOW_JST_FIELD = { type: 'string', description: "Completion time in JST: the verbatim output of `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'`" }
const TAIL_NOTE = "Output language: write all output content (structured output fields and any files you write) in Japanese; keep code identifiers, file paths, and commands as-is. Finally, run `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` and put its verbatim output into nowJst."
const ts = (t) => (t ? `[${t} JST] ` : '')

const FIX_SCHEMA = {
  type: 'object',
  required: ['adopted', 'rejected', 'testsPassed', 'nowJst'],
  properties: {
    adopted: {
      type: 'array',
      items: { type: 'object', required: ['title', 'action'], properties: { title: { type: 'string' }, action: { type: 'string' } } },
    },
    rejected: {
      type: 'array',
      items: { type: 'object', required: ['title', 'reason'], properties: { title: { type: 'string' }, reason: { type: 'string' } } },
    },
    testsPassed: { type: 'boolean' },
    notes: { type: 'string' },
    nowJst: NOW_JST_FIELD,
  },
}

const RESTRAINT_NOTE = "Execution discipline: complete this role yourself with your own tool calls — do not launch subagents (Agent/Task tools), even to verify or double-check your own work, and do not add verification passes beyond the steps above. Deliver what was asked, at the scope intended, and stop short of actions clearly beyond it. Match the length of your output and any files you write to what the task needs: cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate."

log(`${ts(args.startedAt)}dev fix ラウンド ${args.round} 開始`)

const fix = await agent(`You are the developer (reviewee) who implemented GitHub Issue #${args.issueNumber}. Judge and apply the round-${args.round} review findings.
1. Read ${ctx} and ${notes} to restore the implementation context.
2. Classify each finding in ${args.workDir}/findings-round-${args.round}.md as 採用 (adopt) or 不採用 (reject):
   - Adopt: findings that correctly identify, with evidence, an unmet spec, a bug, a regression risk, or an implementation-level hotspot.
   - Reject: invalid, would cause over-engineering, or out of the Issue scope (record the reason in one line). Even findings the Judge classified as 真の欠陥 may be rejected if fixing them would be overcorrection.
3. Fix the adopted findings and re-run the relevant-scope tests per the test policy in context.md (do not leave them broken).
4. Clean up the probe tests containing .breaker-probe.: convert the ones corresponding to adopted defects into regular regression tests; delete the rest.
5. Update ${notes}.
Constraints: do not commit or push. Do not water down findings by reinterpreting or summarizing them (your decision is only the adopt / reject classification with explicit reasons). ${RESTRAINT_NOTE} ${TAIL_NOTE}`,
  { label: 'dev:fix-r' + args.round, phase: 'Fix', model: 'sonnet', effort: 'high', schema: FIX_SCHEMA })
if (fix === null) return { status: 'agent-failed' }
log(`[${fix.nowJst} JST] dev fix r${args.round} 完了（採用${fix.adopted.length}件・不採用${fix.rejected.length}件）`)
for (const a of fix.adopted.slice(0, 10)) log(`- 採用: ${a.title}`)
if (fix.adopted.length > 10) log(`- 採用: …他${fix.adopted.length - 10}件`)
for (const rj of fix.rejected.slice(0, 5)) log(`- 不採用: ${rj.title}（${rj.reason}）`)
if (fix.rejected.length > 5) log(`- 不採用: …他${fix.rejected.length - 5}件`)

return { status: 'ok', fix }
```

## 雛形 E: 収束後の最終 QA（sir-qa-final）

codex 系ループの収束（または打ち切りで完了処理を選択した）後、および claude 系で**打ち切り**を選択した（雛形 B の最終 QA が未実施の）場合に、自動コミット・PR の前に独立検証を行う。claude 系の収束時は雛形 B が内蔵実行するため不要。

`args`: `{ workDir, issueNumber, defaultBranch, startedAt }`（`startedAt`: 起動直前に実測した開始日時〔開始ログ表示専用・省略可〕）

```js
export const meta = {
  name: 'sir-qa-final',
  description: '自動コミット・PR 前の独立 QA 最終検証',
  phases: [{ title: 'FinalQA', detail: 'テスト・受け入れ基準・混入物の最終確認' }],
}

// args は文字列で届く環境があるため正規化する（トップレベルの args. 参照を機能させる防御シム）
args = typeof args === 'string' ? JSON.parse(args) : (args || {})

const ctx = args.workDir + '/context.md'

const NOW_JST_FIELD = { type: 'string', description: "Completion time in JST: the verbatim output of `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'`" }
const TAIL_NOTE = "Output language: write all output content (structured output fields and any files you write) in Japanese; keep code identifiers, file paths, and commands as-is. Finally, run `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` and put its verbatim output into nowJst."
const ts = (t) => (t ? `[${t} JST] ` : '')

const QA_SCHEMA = {
  type: 'object',
  required: ['pass', 'executed', 'issues', 'nowJst'],
  properties: {
    pass: { type: 'boolean' },
    executed: { type: 'string' },
    issues: {
      type: 'array',
      items: { type: 'object', required: ['title', 'detail'], properties: { title: { type: 'string' }, detail: { type: 'string' } } },
    },
    nowJst: NOW_JST_FIELD,
  },
}

const RESTRAINT_NOTE = "Execution discipline: complete this role yourself with your own tool calls — do not launch subagents (Agent/Task tools), even to verify or double-check your own work, and do not add verification passes beyond the steps above. Deliver what was asked, at the scope intended, and stop short of actions clearly beyond it. Match the length of your output and any files you write to what the task needs: cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate."

log(`${ts(args.startedAt)}最終 QA 開始`)

const qa = await agent(`You are an independent QA agent performing the final verification after the review loop, before commit.
1. Read ${ctx} (test policy, acceptance criteria, diff base).
2. Inspect the changes: git diff origin/${args.defaultBranch}...HEAD, plus uncommitted changes visible via git status / git diff.
3. Following the test policy in context.md, run the relevant-scope tests and lint yourself.
4. Verify each acceptance criterion of Issue #${args.issueNumber}, one by one, against the code and execution results.
5. If any file containing .breaker-probe. remains in the change set, report it in issues.
Constraints: do not modify code or files. Do not commit or push.
Verdict: set pass=true only when all tests pass and the acceptance criteria are met. ${RESTRAINT_NOTE} ${TAIL_NOTE}`,
  { label: 'qa:final', phase: 'FinalQA', model: 'fable', effort: 'high', schema: QA_SCHEMA })
if (qa === null) return { status: 'agent-failed' }
log(`[${qa.nowJst} JST] FinalQA 完了（pass=${qa.pass}${qa.pass ? '' : `・指摘${qa.issues.length}件`}）`)
for (const it of (qa.pass ? [] : qa.issues.slice(0, 5))) log(`- QA指摘: ${it.title}`)

return { status: 'ok', qa }
```

## 完了報告への反映

オーケストレーターは各 Workflow の返却を集約し、完了報告に含める:

- 実装フェーズ: 変更ファイル・要件対応（`impl`）、QA 結果（`qa.executed`）、設計整合レビューの指摘数と採用 / 不採用（`archFindings` / `archFix`）
- レビューループ: 各ラウンドのモード・指摘数・採用数・不採用理由（`records`）、最終 QA 結果（`finalQa`）
- `{作業Dir}/impl-notes.md` の「自分で判断した事項」はユーザーが把握すべき決定事項として完了報告で言及する
