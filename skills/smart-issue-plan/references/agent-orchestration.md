# エージェントオーケストレーション（計画レビュー用 Workflow スクリプト雛形）

smart-issue-plan の **claude 系計画レビューループ**を担う役割別エージェントの起動手順と Workflow スクリプト雛形。SKILL.md の「claude 系レビューループ」節から参照される。**Claude Code の Workflow ツール前提**（利用できない環境の degradation は SKILL.md を参照）。

> 計画作成（手順 4 探索・手順 5 作成）はオーケストレーター（メインセッション）が従来どおり担う。本ファイルの雛形が起動するのは**確定した初期計画を対象にしたレビューループの 1 セット**のみ。計画作成のオーケストレーション化ではない。

## 前提とゲート

- 起動前に `{作業Dir}/context.md` と `{作業Dir}/plan.md` が両方存在すること（SKILL.md の claude 系レビューループ節で作成）。どちらか無ければ Workflow を起動せず、作成に戻る
- スクリプトはこのファイルの雛形を**そのまま** `script` に渡し、可変値はすべて `args` で渡す（スクリプト本文を書き換えない。プロンプト文はスクリプトに内蔵済み）
- `args` は JSON 値として渡す（文字列化した JSON を渡さない）。ただし呼び出し経路によっては文字列（`typeof args === 'string'`）で着弾する環境があるため、雛形は meta 直後に正規化シム（`args = typeof args === 'string' ? JSON.parse(args) : (args || {})`）を持つ。文字列・オブジェクトどちらで届いても本文のトップレベル `args.` 参照が機能する
- Workflow スクリプト内では `Date.now()` / `Math.random()` / 引数なし `new Date()` は使えない（雛形は使用していない）
- **進捗の可視化**: IDE 拡張では `/workflows` の進捗表示が使えないため、`log()` で開始日時・進捗・ラウンド結果を可視化する。時刻の取得は 2 系統（スクリプト自身は時刻を生成できない）:
  - **開始日時**: オーケストレーターが起動直前に `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` を実測し、`args.startedAt` として渡す（省略可）。スクリプトは冒頭の開始ログに使う。**ログ表示専用で、`agent()` のプロンプトへは埋め込まない**（resume 時に `agent()` の (prompt, opts) キャッシュ一致を保つため）
  - **途中経過の時刻**: 各 `agent()` はプロンプト末尾の共通指示（`TAIL_NOTE`）で `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` を実行し、結果を構造化出力の `nowJst`（共通フィールド。`NOW_JST_FIELD`）として返す。スクリプトは完了ログ（`log(`[YYYY-MM-DD hh:mm:ss JST] ...`)`）に使うほか、直近値を `lastJst` に保持して次のラウンド開始・judge 起動などの開始ログに使う（`parallel()` バッチは各結果の `nowJst` の最大値を完了時刻とする）
  - **ラウンド結果**: 各レビューラウンドの終了時に、指摘 / 裁定の内訳（真の欠陥・仕様未定・除外件数）と各指摘のタイトル・重大度、plan-editor の採用 / 不採用を `log()` で出力する（件数上限つき）。新しい `agent()` 呼び出しを追加する場合もこの規約に従う
- **プロンプトは英語・出力は日本語**: `agent()` に渡すプロンプト本文・スキーマ `description` は英語で記述する（指示追従の精度向上）。ユーザーが読む内容 — 構造化出力の中身・引き継ぎファイル（plan.md / breaker-round-*.md 等）・`log()` 文字列・`meta`・カテゴリ enum 値（`真の欠陥` / `仕様未定` / `低優先度` / `ノイズ`）— は日本語のまま（`TAIL_NOTE` が日本語出力を指示する）
- ツール結果に返る `scriptPath` を控えておくと、同じ雛形の再起動（レビューセット続行など）は `{scriptPath, args}` で再送できる。中断・失敗からの再開は `resumeFromRunId` を使う

## 作業ディレクトリと引き継ぎファイル

作業ディレクトリはオーケストレーターが作成する（配置ルールの詳細は SKILL.md の claude 系「準備」手順 1）。linked worktree の中にいる場合は `{worktreeパス}/.smart-issue-work/plan-issue-<番号>/`（端末の再起動でも失われず、worktree 削除時に中身ごと消える。`.smart-issue-work/` は `info/exclude` に登録する）、メイン作業ツリーの場合は `mktemp -d "${TMPDIR:-/tmp}/sip-issue-<番号>.XXXXXX"`。いずれもスキル側で削除手順は持たない。`context.md` と `plan.md` は以下の書式で書き出す:

`context.md`:

```markdown
# smart-issue-plan コンテキスト（Issue #<番号>）

## Issue 要件
- タイトル: <タイトル>
- 要件・受け入れ基準: <要約（箇条書き）>
- ラベル: <ラベル一覧>

## 追加指示（-p）
<{プロンプト}。無ければ「なし」。仕様未定のユーザー確認で確定した内容もここへ追記する>

## プロジェクト固有基準
<SKILL.md「レビュー基準の収集」で収集した規約・レビュー基準の要点。無ければ「なし」>
```

`plan.md`: オーケストレーターが確定した初期計画の**全文**（[assets/plan-template.md](../assets/plan-template.md) の構成）。plan-editor がこのファイルを直接編集し、レビュワー / Breaker / Judge はこのファイルを読む。収束後にオーケストレーターがこのファイルを読んで投稿する。

エージェント間の引き継ぎファイル（すべて `{作業Dir}` 配下）:

| ファイル | 書き手 | 読み手 |
|---|---|---|
| `context.md` | オーケストレーター | 全エージェント |
| `plan.md` | オーケストレーター（初期）・plan-editor（修正） | 全エージェント・オーケストレーター（収束後の投稿） |
| `security-audit.md` | Breaker レンズ S（監査ラウンド） | Breaker |
| `breaker-round-<N>-<lens>.md` | Breaker（レンズ S/C/O ごとに別ファイル。単発ラウンドは `-all`） | Judge |

## 雛形: 計画レビューセット（sip-plan-review-set）

1 セット = 最大 3 ラウンド。「レビュー（標準: レビュワー / 敵対: Breaker→Judge）→ plan-editor の採用判定・計画修正」を収束（High/Medium 採用 0 のクリーンが連続 2 回）まで回して返る。収束時は最終 QA を回さず、オーケストレーターがそのまま `plan.md` を投稿する（計画にはテスト対象コードが無いため）。3 ラウンドごとの続行確認はオーケストレーターがセット間に行う。

`args`: `{ workDir, issueNumber, mode, startRound, priorSummary, cleanStreak, securityAudit, securityReason, startedAt }`
（`mode`: `'standard' | 'adversarial'`。`startRound`: 通算ラウンドの開始値（1, 4, 7, …）。`priorSummary`: 前セットまでの経緯要約（初回は空文字）。`cleanStreak`: 連続クリーンラウンド数の引き継ぎ値（初回は 0 / 省略可。前セットが `cleanStreak: 1` で 3 ラウンド上限に達した場合、続行セットへ渡すと round 1 が差分スコープ解除の確認ラウンドになり dry-twice 収束がセット境界を跨いで機能する）。`securityAudit`: セキュリティ自動発動時の初回セットのみ true。`securityReason`: 自動発動の理由〔検出したシグナル〕。監査役プロンプトに埋め込まれるため `securityAudit: true` のときは必ず渡す。`startedAt`: 起動直前にオーケストレーターが `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` で実測した開始日時〔開始ログ表示専用・省略可。継続セットの再起動でも再実測して渡す。`agent()` プロンプトへは埋め込まれないため resume のキャッシュ一致に影響しない〕）

```js
export const meta = {
  name: 'sip-plan-review-set',
  description: 'smart-issue-plan claude 系計画レビューループ 1 セット（最大 3 ラウンド）',
  phases: [
    { title: 'Review', detail: '包括ラウンド（初回セット round 1）は Breaker レンズ S/C/O（敵対）/ レビュワー観点グループ G1/G2/G3（標準）の並列、以降のラウンドは単発 1 体（全観点横断）。敵対は続けて Judge バッチ並列裁定。レンズ S は初回セット round 1 でセキュリティ監査を内蔵。モデルは全ラウンド fable' },
    { title: 'Edit', detail: 'plan-editor による採用判定・計画修正' },
  ],
}

// args は文字列で届く環境があるため正規化する（トップレベルの args. 参照を機能させる防御シム）
args = typeof args === 'string' ? JSON.parse(args) : (args || {})

const ctx = args.workDir + '/context.md'
const plan = args.workDir + '/plan.md'
const target = `The review target is the body of the implementation plan ${plan}. Check the files, functions, and configs the plan mentions against the real code in the repository, and also verify the correctness of its stated assumptions (依拠した前提).`

const NOW_JST_FIELD = { type: 'string', description: "Completion time in JST: the verbatim output of `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'`" }
const TAIL_NOTE = "Output language: write all output content (structured output fields and any files you write) in Japanese; keep code identifiers, file paths, and commands as-is. Finally, run `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S'` and put its verbatim output into nowJst."
const RESTRAINT_NOTE = "Execution discipline: complete this role yourself with your own tool calls — do not launch subagents (Agent/Task tools), even to verify or double-check your own work, and do not add verification passes beyond the steps above. Deliver what was asked, at the scope intended, and stop short of actions clearly beyond it. Match the length of your output and any files you write to what the task needs: cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate."
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
          basis: { type: 'string', description: 'Primary evidence such as file path and line numbers, or the relevant part of the plan' },
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
  required: ['adopted', 'rejected', 'nowJst'],
  properties: {
    adopted: {
      type: 'array',
      items: { type: 'object', required: ['title', 'action', 'severity'], properties: { title: { type: 'string' }, action: { type: 'string' }, severity: { type: 'string', enum: ['High', 'Medium', 'Low'], description: 'Copy the severity of the original finding being adopted (used for the convergence severity floor)' } } },
    },
    rejected: {
      type: 'array',
      items: { type: 'object', required: ['title', 'reason'], properties: { title: { type: 'string' }, reason: { type: 'string' } } },
    },
    notes: { type: 'string' },
    nowJst: NOW_JST_FIELD,
  },
}

const BREAK_SCHEMA = {
  type: 'object',
  required: ['scenarios', 'nowJst'],
  properties: {
    scenarios: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'scenario', 'unaddressed'],
        properties: {
          title: { type: 'string' },
          scenario: { type: 'string', description: 'The attack scenario, threat, or missing control against the design' },
          unaddressed: { type: 'string', description: 'Which step / assumption of the plan fails to address it' },
          evidence: { type: 'string', description: 'Evidence such as file path, line, or the relevant part of the plan' },
        },
      },
    },
    nowJst: NOW_JST_FIELD,
  },
}

// レンズ S（セキュリティ）専用スキーマ。監査ラウンドでは security-audit.md を書き出したか（auditWritten）も返す
const BREAK_S_SCHEMA = {
  type: 'object',
  required: ['scenarios', 'nowJst'],
  properties: {
    scenarios: BREAK_SCHEMA.properties.scenarios,
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
    aspects: `- Security: STRIDE (spoofing, tampering, repudiation, information disclosure, DoS, elevation of privilege), trust boundaries, missing authorization, PII / secret exposure, injection surfaces (if ${args.workDir}/security-audit.md exists, always consult it and reflect its threats and attack scenarios)
- Security-related project-specific standards (if provided in context.md, include their violations as attack scenarios)` },
  { id: 'C', token: 'corr', label: 'Correctness/Data',
    aspects: `- Spec: unmet acceptance criteria, contract violations, backward-compatibility breakage, version skew / schema drift
- Data integrity & performance: transaction boundaries, atomicity, idempotency (double execution), broken concurrent updates, partial failure, reentrancy, irreversible state changes, N+1 or excessive I/O, computational complexity
- Architecture: layer-responsibility violations, boundary intrusion` },
  { id: 'O', token: 'ops', label: 'Ops/Maintainability',
    aspects: `- Operations, maintainability, availability: missing observability, fragile deploy / rollback, excessive coupling, missing timeouts / retries, behavior on failure or dependency degradation, resource exhaustion, single points of failure
- Quality-gate gaps and insufficient test-coverage planning
- Project-specific standards (if provided in context.md, include their violations as attack scenarios)` },
]

// 単発 Breaker（差分スコープのラウンド 2+ / dry-twice 確認ラウンド用）。aspects は LENSES の結合で生成し、観点 union の不変を構造的に保証する（Issue #113: 分割並列は包括ラウンド限定）
const LENS_ALL = { id: 'ALL', token: 'all', label: 'All aspects', solo: true, aspects: LENSES.map((l) => l.aspects).join('\n') }

// 差分スコープ化: ラウンド 1（初回セット）は計画全体の包括レビュー、以降は直前ラウンドで plan-editor が反映した計画修正が触れた計画節＋影響領域を重点対象にする（重点付けであり抑制ではない。レビュー対象は計画全体を維持）
const fixDelta = (i) => {
  if (args.startRound === 1 && i === 0) return ''
  const last = records[records.length - 1]
  const adoptedItems = (last && last.adoptedItems) || []
  const deltaList = adoptedItems.length
    ? adoptedItems.map((a) => `- ${a.title}: ${a.action}`).join('\n')
    : '(Plan fixes adopted in earlier sets — see "Prior rounds" above.)'
  return `\n## Delta scope (focus of this round)\nIn the previous round, the plan-editor adopted and applied the plan fixes below. Focus on the plan sections / assumptions they touched and their affected areas (dependent later steps, related plan sections), and hunt first for inconsistencies or broken steps newly introduced by these fixes:\n${deltaList}\nThis is prioritization, not restriction: still report obvious critical defects outside this scope. However, limit exhaustive re-scanning of the whole plan to this focus area; avoid wasteful wide-area exploration.\nDo not demand further elaboration of the text these fixes added (more detail, more caveats, or longer enumerations); raise a finding against newly added text only when it is factually wrong, contradicts another part of the plan, or breaks a step.\n`
}

// 標準レビュワーの観点グループ分割（G1/G2/G3）。union = 現行の全 9 観点（内容の追加・削除・改変なし）。Breaker のレンズ分割（S/C/O）と同型で、標準モードのレビュワーを 3 グループの並列エージェントにする。グループの意味的対応は計画レビュー用（sir とは観点内容が異なる）
const REVIEWER_GROUPS = [
  { id: 'g1', label: 'Feasibility/Steps/Tests',
    aspects: `- Feasibility: do the plan steps actually work on the current codebase? Verify against the code that the files, functions, and configs the plan mentions exist, and that its stated assumptions (依拠した前提) are correct.
- Step validity: is the ordering / granularity of the steps free of impossibilities and inverted dependencies?
- Test coverage: is the plan's testing designed to cover happy path, error path, and boundary values of new / changed logic?` },
  { id: 'g2', label: 'Impact/Risks/Data-Performance',
    aspects: `- Missing impact: are there files / modules the change ripples into that the plan's impact scope omits?
- Overlooked risks: are there migration, backward-compatibility, or quality-gate (tests, lint, CI) impacts the plan does not address?
- Data integrity & performance: does the plan lack consideration of transaction boundaries, atomicity, idempotency (double-execution prevention), concurrent-update consistency, N+1, unnecessary full scans, excessive round trips, or computational complexity?` },
  { id: 'g3', label: 'Ops-Maintainability/Architecture/Project-standards',
    aspects: `- Operations, maintainability, availability: does the plan lack design for observability (logs / metrics / alerts), deploy / rollback, config management, maintainability (coupling, testability, change ripple), or availability (degradation on failure, timeouts / retries, resource limits, single points of failure)?
- Architecture boundaries: does the plan avoid layer-responsibility violations and boundary intrusion?
- Conformance to project-specific standards (only if provided in context.md)` },
]

// 単発レビュワー（差分スコープのラウンド 2+ / dry-twice 確認ラウンド用）。aspects は REVIEWER_GROUPS の結合で生成し、観点 union の不変を構造的に保証する（Issue #113: 分割並列は包括ラウンド限定）
const REVIEWER_ALL = { id: 'all', label: 'All aspects', solo: true, aspects: REVIEWER_GROUPS.map((g) => g.aspects).join('\n') }

const reviewerGroupPrompt = (round, group, delta) => `You are a reviewer of the implementation plan for GitHub Issue #${args.issueNumber}${group.solo ? '' : ` (aspect group ${group.id}: ${group.label})`}. From an independent position uninvolved in creating the plan, check it against the real code in the repository and report only defects of the plan, ${group.solo ? 'covering all aspects' : 'focusing on the aspects of your group'}.
## Input
1. Read ${ctx} (Issue requirements, extra instructions, project-specific standards).
2. ${target} (round ${round})
${prior()}${delta}
## Review aspects${group.solo ? ' (cover all 9 aspects)' : ` (focus on group ${group.id}; the other groups are covered by other reviewers — do not chase them)`}
${group.aspects}
## Constraints
- Limit findings to defects of the plan (style, formatting, and taste are out of scope).
- Report only defects that would change what the implementer builds (behavior, design decisions, step ordering, scope). Details an implementer can settle with ordinary judgment — test function naming, renaming instructions, docstring / comment wording, completeness of file or line-number enumerations — go to dismissed as 低優先度, not items. Exception: treat such completeness as in scope when it is itself the Issue's deliverable (e.g. documentation-revision Issues whose acceptance criteria enumerate update targets).
- Attach evidence (primary sources such as file path and line numbers, or the relevant part of the plan) and severity to each finding.
- Do not modify the plan or the code (review only). Do not commit.
- If there are no findings, return an empty items array.
${RESTRAINT_NOTE} ${TAIL_NOTE}`

// レンズ別 Breaker プロンプト。プロンプト本体は共通で、攻撃観点だけレンズ定義（lens.aspects）に差し替える。
// レンズ S かつ isAuditRound（securityAudit 初回セット round 1）のときは、監査役を統合して STRIDE 監査 → security-audit.md 書き出し → セキュリティ break を 1 エージェントで実施する（独立の前段監査スロットを消す）
const breakerLensPrompt = (round, lens, delta, isAuditRound) => `You are a Breaker${lens.solo ? '' : ` (lens ${lens.id}: ${lens.label})`}. Do not merely read the implementation plan for GitHub Issue #${args.issueNumber} — break it. Enumerate concrete attack scenarios, threats, and missing controls the design must withstand, ${lens.solo ? 'covering all attack aspects' : 'focusing on the aspects of your lens'}. Stay independent of the plan's creation, and default to skepticism: treat steps that only consider the happy path as real weaknesses, and grant no credit to "we will handle it later" assumptions or partial mitigations. The plan has no testable code, so do not write probe tests (attack via scenarios).
## Input
1. Read ${ctx} (Issue requirements, extra instructions, project-specific standards).
2. ${target} (round ${round})
${prior()}${delta}${isAuditRound ? `\n## Security audit (perform in this round, before breaking)\nFrom the STRIDE, authentication / authorization, data flow, secrets, and PII perspectives, enumerate the threats this plan must address and the attack scenarios to verify, write them to ${args.workDir}/security-audit.md, then break using the security aspects below. Reason for auto-activation: ${args.securityReason}. Set auditWritten to true if you wrote security-audit.md; if you could not, set it to false and still proceed to break with the built-in security aspects.\n` : ''}## Attack aspects${lens.solo ? ' (cover all)' : ` (focus on lens ${lens.id}; the other lenses are covered by other Breakers — do not chase them)`}
${lens.aspects}
## Output
- Write the attack-scenario list (scenario, the plan step / assumption that fails to address it, evidence) to ${args.workDir}/breaker-round-${round}-${lens.token}.md (one file per lens, to avoid concurrent overwrite between parallel lenses).
- Return the same content in the structured output scenarios. Always attach unaddressed (which step / assumption of the plan fails to address it) to each scenario${isAuditRound ? ', and whether you wrote security-audit.md in auditWritten' : ''}.
Constraints: attack only weaknesses that would change what the implementer builds (behavior, design decisions, step ordering, scope) — do not raise wording precision, naming, or enumeration-completeness nitpicks as scenarios (unless such completeness is itself the Issue's deliverable). Do not modify the plan or the code (writing security-audit.md is allowed). Do not commit. ${RESTRAINT_NOTE} ${TAIL_NOTE}`

const judgeBatchPrompt = (round, batch, batchNum, batchTotal) => `You are the Judge (adjudicator). Another agent (the Breaker) generated attack scenarios against the design; adjudicate them by checking them against the real code in the repository and the plan body. Do not defer to the Breaker — judge independently. You were involved in neither the plan's creation nor the scenario generation. This is batch ${batchNum}/${batchTotal} of the round-${round} attack scenarios.
## Input
1. Read ${ctx} (Issue requirements, extra instructions, project-specific standards).
2. ${target} (round ${round})
3. The attack scenarios to adjudicate in this batch (handle no others):
${JSON.stringify(batch, null, 2)}
${prior()}
## Adjudication task
Check each scenario against the real code and the plan body, and classify it into exactly one of these 4 categories (use these exact Japanese values for category):
- 真の欠陥 (true defect): the plan should address it but its steps / assumptions have a gap or error, worth fixing (spec violation, security, backward compatibility, operations / maintainability / availability, data-integrity / performance, missing test coverage, architecture violation, or project-specific-standard violation).
- 仕様未定 (spec undecided): the requirements / spec are ambiguous and the Breaker made an arbitrary assumption (needs spec confirmation).
- 低優先度 (low priority): valid but low severity; not worth the cost of reflecting into the plan.
- ノイズ (noise): unfalsifiable, a misunderstanding, off the mark, or already addressed by the plan (excluded).
## Scoped verification (keep moving steadily)
- Adjudicate only the inline batch above. Do not read or handle other batches or the other entries of ${args.workDir}/breaker-round-${round}-*.md (per-lens Breaker output).
- Limit verification to the files / lines and plan sections pointed to by each scenario's evidence. If a scenario has no evidence, limit verification to the plan body and the places its scenario text names. In either case, do not run unrelated wide-area greps or cross-service exploration.
- Keep tool calls progressing steadily within ~3 minutes (do not stall on a single exploration).
- Do not independently hunt for plan defects the Breaker missed in this batch (avoids duplication across batches).
## Constraints
- Limit findings to defects of the plan (style, formatting, and taste are out of scope).
- Classify as 真の欠陥 only scenarios that can answer all 4 of: (1) what happens at implementation time, (2) why that plan step / assumption is vulnerable, (3) the expected impact, (4) how to fix the plan to reduce the risk. Concerns that cannot answer them go to 低優先度 or ノイズ.
- Prefer a few strong, defensible findings over many weak ones.
- Findings that would not change what the implementer builds (naming, wording, docstring content, enumeration completeness) are at most 低優先度 even if technically valid — unless that completeness is itself the Issue's deliverable.
- Do not modify the plan or the code (adjudication only). Do not commit.
- Put only 真の欠陥 and 仕様未定 into items (set category); leave 低優先度 / ノイズ in dismissed with count and title only.
${RESTRAINT_NOTE} ${TAIL_NOTE}`

const editPrompt = (round, items) => `You are the author (reviewee) of the implementation plan for GitHub Issue #${args.issueNumber}. Judge the round-${round} review findings and apply them to the plan ${plan}:
${JSON.stringify(items, null, 2)}
1. Read ${ctx} and ${plan} to restore the plan's context.
2. Classify each finding as 採用 (adopt) or 不採用 (reject), copying each adopted finding's severity into the structured output:
   - Adopt: findings that correctly identify, with evidence, an error, gap, or risk in the plan.
   - Reject: invalid, would cause over-engineering, or out of the Issue scope (record the reason in one line). Even findings the Judge classified as 真の欠陥 may be rejected if addressing them would be overcorrection.
   - Low-severity findings: reject by default (the plan is guidance for an implementer with judgment, not a contract). Adopt one only when leaving it would actively mislead the implementer, and apply it as a minimal edit — do not add new sections or grow the plan's structure for it.
3. Apply the adopted findings to ${plan} (edit the plan body; do not modify implementation code).
4. Keep the plan structure (per [assets/plan-template.md](../assets/plan-template.md)) after the edits.
Constraints: do not modify implementation code. Do not commit or push. Do not water down findings by reinterpreting or summarizing them (your decision is only the adopt / reject classification with explicit reasons). ${RESTRAINT_NOTE} ${TAIL_NOTE}`

// セキュリティ監査はレンズ S の Breaker に統合済み（securityAudit 初回セット round 1 で STRIDE 監査 → security-audit.md 書き出し → セキュリティ break を 1 エージェントで実施）。独立の前段監査スロットは持たない。auditFailed はレンズ S が監査を書き出せなかった場合に立てる
let auditFailed = false

let converged = false
let status = 'ok'
let judgeDegraded = false
let breakerDegraded = false
let reviewerDegraded = false
let cleanStreak = args.cleanStreak || 0
const specQuestions = []

log(`${ts(lastJst)}計画レビューセット開始（mode=${args.mode}・round ${args.startRound}〜${args.startRound + 2}）`)

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
  log(`${ts(lastJst)}計画レビューラウンド ${round}（${args.mode}）開始${isConfirmRound ? '（確認ラウンド: 連続クリーン確認・差分スコープ解除）' : ''} — ${launchDesc}を起動`)
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
    if (okLenses.length < lenses.length) { breakerDegraded = true; log(`breaker r${round}: ${lenses.length - okLenses.length}/${lenses.length} レンズ失敗（部分シナリオで続行・未探索の観点あり）`) }
    if (isAuditRound) {
      const sIdx = lenses.findIndex((l) => l.id === 'S')
      const sResult = sIdx >= 0 ? lensResults[sIdx] : null
      if (sResult === null || sResult.auditWritten === false) { auditFailed = true; log(`レンズ S の監査書き出しに失敗（内蔵セキュリティ観点のみで続行）`) }
    }
    const breakerTimes = okLenses.map((r) => r.nowJst).filter(Boolean).sort()
    if (breakerTimes.length) { lastJst = breakerTimes[breakerTimes.length - 1]; log(`[${lastJst} JST] breaker r${round} 完了（${okLenses.length}/${lenses.length} レンズ・シナリオ${okLenses.reduce((n, r) => n + (r.scenarios || []).length, 0)}件）`) }
    const scen = okLenses.flatMap((r) => r.scenarios || [])
    const BATCH = 4
    const batches = []
    for (let b = 0; b < scen.length; b += BATCH) batches.push(scen.slice(b, b + BATCH))
    if (batches.length > 0) log(`${ts(lastJst)}judge r${round} 起動（シナリオ${scen.length}件・${batches.length}バッチ並列）`)
    const batchResults = batches.length === 0 ? [] : await parallel(batches.map((batch, bi) => () =>
      agent(judgeBatchPrompt(round, batch, bi + 1, batches.length),
        { label: `judge:r${round}-b${bi + 1}`, phase: 'Review', model: reviewModel, effort: 'high', schema: FINDINGS_SCHEMA })))
    const ok = batchResults.filter(Boolean)
    if (batches.length > 0 && ok.length === 0) { status = 'agent-failed'; break }
    if (ok.length < batches.length) { judgeDegraded = true; log(`judge r${round}: ${batches.length - ok.length}/${batches.length} バッチ失敗（部分裁定で続行・未裁定のシナリオあり）`) }
    const judgeTimes = ok.map((r) => r.nowJst).filter(Boolean).sort()
    if (judgeTimes.length) { lastJst = judgeTimes[judgeTimes.length - 1]; log(`[${lastJst} JST] judge r${round} 完了（${ok.length}/${batches.length} バッチ）`) }
    findings = { items: ok.flatMap((r) => r.items || []), dismissed: ok.flatMap((r) => r.dismissed || []) }
  } else {
    // 包括ラウンドは標準レビュワーを観点別グループ（G1/G2/G3）に分割しフラット parallel で同時起動、以降は単発レビュワー（REVIEWER_ALL）1 体。union = 現行 9 観点で内容は不変。Judge 段は無く各グループの items を単純結合する（グループ間の重複指摘は plan-editor の採用判定で統合。敵対レンズ重複と同じ扱い）。一部グループ失敗は reviewerDegraded で伝播
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
    const fix = await agent(editPrompt(round, trueDefects), { label: `plan-editor:r${round}`, phase: 'Edit', model: 'opus', effort: 'max', schema: FIX_SCHEMA })
    if (fix === null) { status = 'agent-failed'; break }
    lastJst = fix.nowJst || lastJst
    const adoptedMajor = fix.adopted.filter((a) => a.severity !== 'Low').length
    log(`[${fix.nowJst} JST] plan-editor r${round} 完了（採用${fix.adopted.length}件〔High/Medium ${adoptedMajor}・Low ${fix.adopted.length - adoptedMajor}〕・不採用${fix.rejected.length}件）`)
    for (const a of fix.adopted.slice(0, 10)) log(`- 採用: ${a.title}`)
    if (fix.adopted.length > 10) log(`- 採用: …他${fix.adopted.length - 10}件`)
    for (const rj of fix.rejected.slice(0, 5)) log(`- 不採用: ${rj.title}（${rj.reason}）`)
    if (fix.rejected.length > 5) log(`- 不採用: …他${fix.rejected.length - 5}件`)
    records.push({ round, findings: findings.items.length, adopted: fix.adopted.length, adoptedMajor, rejected: fix.rejected, dismissed: (findings.dismissed || []).length, adoptedItems: fix.adopted })
    // 重大度フロア: High/Medium の採用が 0 ならクリーン（Low のみの採用は計画へ反映済みのままクリーン扱い）
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

// 仕様未定は確認ラウンド（未変更コードの再レビュー）等で同一項目が再収集されうるため、返却前に title で重複排除する（確認ラウンドで新規に見つかった仕様確認は保持し、完全な重複のみ除く）
const uniqueSpecQuestions = specQuestions.filter((q, i) => specQuestions.findIndex((o) => o.title === q.title) === i)
return { converged, status, records, specQuestions: uniqueSpecQuestions, auditFailed, judgeDegraded, breakerDegraded, reviewerDegraded, cleanStreak }
```

返却の扱い:

- `converged: true` → まず `specQuestions` が空であることを確認する（非空なら下記の `specQuestions` 処理を先に行い、仕様確定で修正が生じたら未収束として次セットへ回す）。空なら収束確定 → オーケストレーターが `{作業Dir}/plan.md` を読んで投稿する（計画レビューのため最終 QA は回さない）。`judgeDegraded: true` のときは未裁定のシナリオが残るため、投稿前にユーザーへ確認する（下記 `judgeDegraded`）
- `converged: false` かつ `status: 'ok'`（3 ラウンド消化）→ 上限チェック: `records` の残指摘を要約提示して AskUserQuestion（続行 / 打ち切り / 中止）。続行なら `startRound` を +3、`priorSummary` に経緯要約を入れ、**返却の `cleanStreak` も次セットの `args` に引き継いで**同じ scriptPath で再起動する（`startedAt` は再実測して渡す。`cleanStreak: 1` を引き継ぐと次セット round 1 が差分スコープ解除の確認ラウンドになり dry-twice 収束がセット境界を跨いで機能する）。打ち切りなら未収束のまま投稿（表記は「未収束で打ち切り」）
- `specQuestions` が空でない → 裁定「仕様未定」の項目。オーケストレーターが AskUserQuestion でユーザーに仕様を確認し、確定内容を `{作業Dir}/context.md`（追加指示）へ追記する。修正が必要になった場合は未収束として扱い、次セットで plan-editor が `plan.md` へ反映する
- `auditFailed: true` → レンズ S の Breaker がセキュリティ監査（`security-audit.md` の書き出し）を完了できず、内蔵のセキュリティ観点のみで break された（監査の欠落）。完了報告に明記する
- `breakerDegraded: true` → 一部の Breaker レンズ（S/C/O のいずれか）が失敗し、その観点の攻撃シナリオが生成されないまま収束扱いになった。未探索の攻撃観点が残る。計画レビューは最終 QA を持たずバックストップできないため、完了報告に明記し `plan.md` 投稿前にユーザーへ確認する（`auditFailed` / `judgeDegraded` と同型の劣化伝播）
- `reviewerDegraded: true` → 標準モードで一部のレビュワー観点グループ（G1/G2/G3 のいずれか）が失敗し、その観点の指摘が生成されないまま収束扱いになった。未探索のレビュー観点が残る。計画レビューは最終 QA を持たずバックストップできないため、完了報告に明記し `plan.md` 投稿前にユーザーへ確認する（`breakerDegraded` と同型の劣化伝播）
- `judgeDegraded: true` → 一部の Judge バッチが失敗し、その攻撃シナリオ（最大 4 件/バッチ）が未裁定のまま収束扱いになった。計画レビューは最終 QA を持たず未裁定の欠陥をバックストップできないため、完了報告に明記し `plan.md` 投稿前にユーザーへ確認する（`auditFailed` と同型の劣化伝播）
- `status: 'agent-failed'` → 1 回だけ `resumeFromRunId` で再開、それでも失敗なら SKILL.md の「フォールバック（claude 系）」へ

## 完了報告への反映

オーケストレーターは Workflow の返却を集約し、完了報告に含める:

- レビューループ: 各ラウンドのモード・指摘数・採用数（High/Medium 内訳 = `adoptedMajor`）・不採用理由（`records`）
- `specQuestions` でユーザーに確認した仕様と、その反映
- `auditFailed: true` の場合はその旨
- `breakerDegraded: true` の場合は一部の攻撃レンズ（S/C/O）が未探索である旨（失敗レンズ数はログ参照）
- `reviewerDegraded: true` の場合は一部のレビュワー観点グループ（G1/G2/G3）が未探索である旨（失敗グループ数はログ参照）
- `judgeDegraded: true` の場合は一部の攻撃シナリオが未裁定である旨（失敗バッチ数はログ参照）

## 同期ノート

本ファイルの計画レビューセット雛形（`sip-plan-review-set`）は、`smart-issue-resolve/references/agent-orchestration.md` の**雛形 B（`sir-claude-review-set`）の計画レビュー用移植**である。次の**構造**を同期する（片方を変えたら両方更新すること）:

- セット制御: `startRound` / `priorSummary` / `cleanStreak` / `records`（`adoptedItems` を含む）/ `history()` / `prior()` の経緯引き継ぎ
- **dry-twice 収束判定（重大度フロア。Issue #134）**: 「レビュー指摘 0 件」「`category: '仕様未定'` を除いた真の欠陥 0 件」「**High/Medium の採用 0 件**（`FIX_SCHEMA.adopted[].severity` の echo で判定。Low のみの採用は反映しつつクリーン扱い＝軽微修正で収束をリセットしない）」を統一的に「クリーン」とし、連続 2 回（`cleanStreak >= 2`）で収束する（3 ラウンド 1 セット）。1 回目クリーン後の確認ラウンドは差分スコープを解除（`delta = ''`）した fresh エージェントで再検証し、`cleanStreak` を `args`／返却で引き継いでセット境界を跨いで成立させる。`records[].adoptedMajor` に High/Medium 採用数を保持する
- null ガード（各 `agent()` 返却の null 判定と `status: 'agent-failed'`）・`auditFailed` / `breakerDegraded` / `reviewerDegraded` フラグ・`specQuestions` の返却経路・セキュリティ自動発動の注入（`securityAudit` / `securityReason`）
- 敵対モード Judge のバッチ並列化: Breaker 出力を ≤4 件/バッチに分割し `parallel` で並列裁定する（`judgeBatchPrompt` / `effort: 'high'`〔Issue #111 で max 化 → ≤4 件/バッチの有界作業量に max は過剰として Issue #113 で high へ戻した〕 / evidence 限定照合。全バッチ失敗のみ `agent-failed`、一部失敗は部分裁定で続行し `judgeDegraded` フラグで伝播）。Breaker のフィールド名だけ意図的に異なる（resolve = `counterexamples`、plan = `scenarios`）
- **Breaker のレンズ分割並列化（包括ラウンド限定）**: 攻撃観点を S/C/O の 3 レンズに分割し `LENSES` 定義 + フラット `parallel` で同時起動する（union = 現行 Breaker の全観点で内容は不変。一部レンズ失敗は `breakerDegraded` で伝播。レンズごとに `breaker-round-<N>-<lens>.md` を書き並列上書き競合を避ける）。分割は包括ラウンド〔初回セット round 1〕限定で、差分スコープのラウンド 2+・確認ラウンド・継続セットは単発 Breaker（`LENS_ALL` = `LENSES` の aspects 結合で union 不変を構造的に保証）1 体で実施する（Issue #113）
- **標準レビュワーのグループ分割並列化（包括ラウンド限定）**: 標準モードのレビュワーを観点別グループ G1/G2/G3 の 3 グループに分割し `REVIEWER_GROUPS` 定義 + フラット `parallel` で同時起動する（union = 現行の全 9 観点で内容は不変。Judge 段は無く各グループの `items` を単純結合し、グループ間の重複指摘は plan-editor の採用判定で統合する。一部グループ失敗は `reviewerDegraded` で伝播。観点内容は計画用のため sir とは文言が異なる）。分割は包括ラウンド〔初回セット round 1〕限定で、以降は単発レビュワー（`REVIEWER_ALL` = `REVIEWER_GROUPS` の aspects 結合で union 不変を構造的に保証）1 体で実施する（Issue #113）
- **役割別モデル配分（設計・指示 = opus / 監視・レビュー = fable）**: 標準レビュワー・Breaker・Judge バッチのモデルは `reviewModel` = `'fable'` で、包括ラウンドと以降のラウンドを区別しない（Issue #142 の「包括ラウンドのみ opus・以降は sonnet」配分を置き換えた。切り戻しのレバーは `reviewModel` の 1 行）。plan-editor は計画（設計）の編集役として `'opus'` / `'max'`。effort は役割ごとに据え置く（Judge バッチ `'high'`〔上記の Issue #113 戻し〕・発見役〔レビュワー / Breaker〕`'high'`〔Issue #134 で `'max'` から降格 — Opus 5 プロンプトガイド「レビュー精度は低 effort でも維持され、effort が主なコスト・時間レバー」〕）。resolve 側の実装役（開発者 = `'sonnet'`）と独立 QA（`'fable'`）は plan 側に対応する役が無く、構造同期の対象外
- **セキュリティ監査役のレンズ S 統合**: `securityAudit` 初回セット round 1 でレンズ S が STRIDE 監査 → `security-audit.md` 書き出し → break を 1 エージェントで実施する（独立の前段監査スロットは削除。`auditWritten` フラグで「監査のみ失敗」を `auditFailed` として区別）
- **差分スコープ化**: `records[].adoptedItems` に採用計画修正の title/action を保持し、ラウンド 2+ の Breaker/レビュワーを直前ラウンドで plan-editor が反映した計画修正が触れた計画節＋影響領域に重点付けする `fixDelta()`。ラウンド 1 は計画全体の包括レビュー。差分スコープの指示には「前ラウンドの追記文への、さらなる詳細要求の禁止（事実誤り・矛盾・手順破綻のみ指摘可）」を含む（自己増殖チェーンの抑制。Issue #134）
- **軽微指摘フィルタ + Low 採用規律（Issue #134）**: レビュワー / Breaker / Judge に「実装者が通常の判断で埋められる詳細（テスト関数名・改名指示・docstring / コメント文言・ファイル / 行番号列挙の完全性）は items / シナリオにせず 低優先度」を明示（列挙の完全性が Issue の成果物そのものであるドキュメント改訂系 Issue は除く）。plan-editor は Low を原則不採用（採用時も最小編集で計画構造を太らせない）
- **プロンプトの英語化 + 進捗ログ規約（Issue #122）**: `agent()` プロンプト・スキーマ description は英語、出力内容・`log()`・カテゴリ enum 値は日本語。`TAIL_NOTE` による日本語出力 + `nowJst`（`%Y-%m-%d %H:%M:%S`）指示、`args.startedAt` の開始ログ、`lastJst` 導出のラウンド開始 / judge 起動ログ、ラウンド終了時の指摘・採用内訳ログ（件数上限つき）
- **Opus 抑制ノート（`RESTRAINT_NOTE`）**: probe-cleanup（resolve のみ）を除く全 `agent()` のプロンプト末尾（`TAIL_NOTE` の直前）に共通の英語抑制ノート（サブエージェント起動・委任の禁止／手順に無い追加検証パスの禁止／依頼スコープの維持／出力・書き出しファイルの簡潔化。Opus 5 プロンプトガイド準拠）を付す（本雛形は全 `agent()` に付く。主目的は上位モデル〔opus / fable〕の過剰処理の抑制）

同期しないもの（**意図的に異なる**）:

- **レビュー対象**: resolve = git diff（実装コード）、plan = 計画テキスト（`plan.md`）
- **レビュイー**: resolve = 開発者（コード修正）、plan = plan-editor（`plan.md` 編集）
- **レビュー観点の内容**: plan は計画用（実現可能性・影響範囲の抜け・手順の妥当性など）で、diff 用の観点とは文言が異なる（分割後もレンズ S/C/O・標準レビュワーのグループ G1/G2/G3 の各 `aspects` は plan 用文言のまま。グループ分割の粒度〔3 観点/グループ〕は sir と構造同期）
- **差分スコープの読み替え**: resolve は「採用修正が触れたファイル・領域とその波及」、plan は「plan-editor の採用計画修正が触れた計画節＋影響領域」に読み替える
- **コード専用機構は持ち込まない**: resolve 側にあるコード検証用の仕組み（反例テストのファイル・そのテスト実行・probe 命名の不変条件・独立 QA / 最終 QA フェーズ・反例テストの後始末エージェント・FIX の「テスト通過」フラグ・BREAK の反例検証ステータス）は本ファイルには**一切含めない**。BREAK スキーマは反例検証ステータスの代わりに `unaddressed`（対処できていない計画の手順・前提）を持つ。収束後は最終 QA を回さず、オーケストレーターがそのまま計画を投稿する
- **diff 正本ファイル化（`diff.md`）も持ち込まない**: resolve 雛形 B の「`{作業Dir}/diff.md`（`assets/gen-diff.sh` で生成）をレビュー役が Read する / 期待スタンプ（`diffRound`）による鮮度ガード / fix エージェントがラウンド境界で再生成する」機構はコード専用（Issue #115）。plan はレビュー対象が `plan.md` で既にファイル正本のため、レビュー役はそのまま `plan.md` を読む（重複する git 取得が存在しないので削減余地がない）
- **claude / codex 系の非対称**: plan は claude 系のみ（codex 経路を持たない）。resolve 側の雛形 C（`sir-codex-breaker`）は Codex 利用制限中のためレンズ分割せず単発のまま残る。この非対称は resolve 側同期ノートで管理する
