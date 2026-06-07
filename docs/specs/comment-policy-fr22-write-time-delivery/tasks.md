# Tasks — FR-22 write-time delivery

**T-counter going in:** ticket-local (T1..T9). Global T-numbers are assigned at the implement-handoff (last known global handoff range: `T10..T17`). Numbers below are ticket-local placeholders.
**Task range:** T1..T9
**Gate task:** T8 (final — supersedes the interim T1–T6 gate)
**Release task:** T9 (framework "deploy" = release commit; no runtime/probe surface)
**Linked spec:** `docs/specs/comment-policy-fr22-write-time-delivery/spec.md`
**Linked decisions:** `docs/specs/comment-policy-fr22-write-time-delivery/decisions.md`
**Status:** DONE — T1–T7 implemented (final gate PASSED: V1–V6 + A/B V8); T9 released as v3.11.0 (release commit). **W4 added 2026-06-06 after V7** (delegated sub-agent over-commented → pull insufficient): T7 (sub-agent push) → T8 (final gate incl. A/B V8) → T9 (release).

## Task chain

| T# | Track | Scope | Cites | Depends on | SHA | Status |
|---|---|---|---|---|---|---|
| T1 | skill | author `flow-skills/comment-policy/SKILL.md` (frontmatter + FR-22 write-time body) | W1 | — | `4e86d84` | done |
| T2 | skill | add `flow-skills/comment-policy/references/audit-prompt.md` (generalized prompt) | W3 | T1 | `5d23339` | done |
| T3 | skill | correct `role-discipline/SKILL.md:50` false claim + add AI-Dev load directive | W2 | — | `9fdcb32` | done |
| T4 | rules | re-point FR-22 (`FLOW_RULES.md:68`) + `comment-policy.yml:19` to the delivered reference | W3 | T2 | `0cd7a46` | done |
| T5 | mirror | re-mirror canonical→providers; bump "24 canonical"→"25" (live: CLAUDE.md/AGENTS.md + overlays) | W1 | T1,T2,T3,T4 | `978a703` | done |
| T6 | hook | one-line FR-22 reminder in `session_start.py` `context_summary` | W1 | — | `c680001` | done |
| T7 | skill | sub-agent **push**: Delegation push block in `comment-policy` + mandatory clause in `task-delegation` + reminder in `handoff-implement`; re-mirror | W4 | T1 | (implement) | done |
| T8 | — | final verification gate (no commit; report only) incl. **A/B V8** (re-run V7 with the push) | — | T1..T7 | — | done (V1–V6 PASS + V8 A/B PASS; PO-accepted 2026-06-06) |
| T9 | release | VERSION 3.10.0→3.11.0, `docs/release-notes/v3.11.0.md`, README count fix, spec DRAFT→DONE | — | T8 | (release commit) | done |

## Per-task detail

### T1. Author the carrier skill
**Track:** skill · **Cites:** W1 · **Acceptance:** AC1
**Scope:** new `flow-skills/comment-policy/SKILL.md`. Frontmatter `name: comment-policy`, `description:` engineered to **description-match on code-writing** ("Use when writing/implementing code, adding or editing comments, before committing a code diff … Do NOT use for prose/docs edits or non-code tickets"). Body carries FR-22's write-time rule verbatim-aligned with `FLOW_RULES.md:68`: the two comment kinds (tripwire ≤1 line default / ≤~4 for security-auth-concurrency-platform; retrieval pointer ≤1 line), the remove-list (WHAT-restate / recorded-elsewhere→pointer / changelog→git), the **density-override** clause, the **storage≠retrieval** pointer-preservation subtlety, and the carve-out pointer to `policies/comment-policy.yml`.
**Files:** `flow-skills/comment-policy/SKILL.md`
**Authored via:** `skill-authoring` (clean-room; frontmatter contract).
**Worker-undisturbed:** no engine-script or FR-01..FR-21 change.

### T2. Bundle the audit prompt with the skill
**Track:** skill · **Cites:** W3 · **Acceptance:** AC4
**Scope:** `flow-skills/comment-policy/references/audit-prompt.md` = the generalized independent-audit prompt currently in `docs/comment-policy.md:45-77`. This is the consumer-reachable copy (rides the skill mirror). `docs/comment-policy.md` stays as framework-dev rationale.
**Files:** `flow-skills/comment-policy/references/audit-prompt.md`
**Depends on:** T1 (skill dir exists).

### T3. Correct the false "already loaded" claim
**Track:** skill · **Cites:** W2 · **Acceptance:** AC2
**Scope:** edit `flow-skills/role-discipline/SKILL.md:50` — replace `"already loaded as part of session bootstrap"` with an accurate statement (`existence-checked at bootstrap; not injected — read on demand`) and add to the **AI Developer** section a one-line directive: *before writing code, load `flow-skills/comment-policy` (FR-22 is not auto-injected).*
**Files:** `flow-skills/role-discipline/SKILL.md`
**Worker-undisturbed:** other role sections + refusal phrasing unchanged.

### T4. Re-point the rule + config to the reachable reference
**Track:** rules · **Cites:** W3 · **Acceptance:** AC4
**Scope:** in `FLOW_RULES.md:68` and `policies/comment-policy.yml:19`, change "run the audit prompt in `docs/comment-policy.md`" → the delivered `flow-skills/comment-policy/references/audit-prompt.md` (keep a secondary mention of `docs/comment-policy.md` as the framework-dev rationale home). **FR-22 semantics unchanged** — only the pointer path.
**Files:** `FLOW_RULES.md`, `policies/comment-policy.yml`
**Depends on:** T2.
**Worker-undisturbed:** FR-01..FR-21 rows byte-unchanged; only FR-22's pointer phrase edited.

### T5. Re-mirror + canonical-count sweep
**Track:** mirror · **Cites:** W1 · **Acceptance:** AC3, AC6
**Scope:** run `hooks/local/mirror-skills.sh` (canonical→`.claude/skills/`,`.agents/skills/` — the two skill-mirror surfaces); grep-sweep "24 canonical" / "(24 …skills total)" → 25 across `CLAUDE.md`, `AGENTS.md`, overlays; run version-string sync. Verify byte-identical mirror of the new skill.
**Files:** `.claude/skills/comment-policy/**`, `.agents/skills/comment-policy/**`, `CLAUDE.md`, `AGENTS.md`, `hooks/local/fusebase-flow-overlays/*.md` (count refs)
**Depends on:** T1–T4.

### T6. Secondary hook reminder (included per operator)
**Track:** hook · **Cites:** W1 · **Acceptance:** AC1 (secondary)
**Scope:** append one line to `session_start.py` `context_summary` ("FR-22 code-comment policy in force when writing code — load flow-skills/comment-policy"). A belt for hook-on full-session starts; opt-in + no-sub-agent-reach is acknowledged, so this is explicitly NOT the primary carrier (T1 is). One `summary_lines.append(...)`; no logic/regex change.
**Files:** `hooks/handlers/session_start.py` (+ any hook mirror, if hooks are mirrored)
**Gate note:** must NOT become a regex/enforcement gate (AC5/V5) — it is a static reminder string only.

### T7. Sub-agent push (W4)
**Track:** skill · **Cites:** W4 · **Acceptance:** AC8
**Scope (push, not pull — V7 showed pull doesn't reach a delegated sub-agent):**
1. `flow-skills/comment-policy/SKILL.md` — add a **"Delegation push block"** section: a compact (~5-line) verbatim-inline tripwire+pointer summary with a "paste this into any code-writing sub-agent's prompt" instruction. Inlines the rule text (not "load the skill").
2. `flow-skills/task-delegation/SKILL.md` — add a **mandatory clause**: when delegating a code-writing / implementation slice, the delegating prompt MUST carry the Delegation push block. Read-only/triage delegation exempt (no code written).
3. `templates/handoff-implement.md` — one-line reminder in the Tracks/delegation area.
4. Re-mirror (`mirror-skills.sh`) → `.claude/` + `.agents/`; verify parity.
**Files:** `flow-skills/comment-policy/SKILL.md`, `flow-skills/task-delegation/SKILL.md`, `templates/handoff-implement.md`, mirrors.
**Worker-undisturbed:** engine scripts + FR-01..FR-21 + other role/skill sections unchanged. **Dogfood** — the push block is the only addition; no other comments.

### T8. Final verification gate
No code change. Gate report per `verification-gate.md` for T1–T7: per-task SHAs, worker-undisturbed diff, mirror parity, V1–V6, and **A/B V8** — re-run the V7 code task on a delegated sub-agent **with** the Delegation push block inlined; PASS = comment output is tripwire+pointer-lean where V7 (no push) was JSDoc-heavy. Supersedes the interim T1–T6 gate. Wait for explicit release handoff; do not proceed to T9 on initiative.

### T9. Release
**Procedure:** framework release (no runtime deploy).
1. Final worker-undisturbed re-check (engine scripts, FR-01..FR-21).
2. `VERSION` 3.10.0 → 3.11.0 (operator-confirmable; minor — adds a canonical skill).
3. `docs/release-notes/v3.11.0.md` (Full-lane record — **not** the `docs/changes/` Lightweight ledger).
4. README count fix (24→25, +`comment-policy` catalog row).
5. Spec DRAFT → DONE + Deploy hash = release SHA.
6. Re-run `preflight.sh` + `fusebase-flow-health-check`; confirm HEALTHY 0/0 (25 skills).
**Approval:** explicit operator go-ahead (framework release; no production runtime surface, so no DP.1 artifact / DP.6 magic phrase — operator confirms the version bump). See `docs/handoff/2026-06-06-…-deploy.md`.

## Parallelism diagram

```
T1 ─┬─ T2 ─┐
    │       ├─ T4 ─┐
T3 ─┼───────┘      ├─ T5 ─→ [interim gate ✓]
    │              │
T6 ─┴──────────────┘
                    └─→ T7 (sub-agent push) ─→ T8 (final gate · A/B V8) ─→ T9 (release)
```

## Task chain audit

| Constitution invariant | Affirmed in tasks |
|---|---|
| Worker-undisturbed | T1–T4 + T7 declare empty diff on engine scripts + FR-01..FR-21 rows; T4 edits only FR-22's pointer phrase |
| Mixed-fleet | additive skill; older-mirror consumers unaffected until re-mirror (T5/T7 note) |
| Migration approach | no migration (skill add + text edits + mirror) |
| No forbidden enforcement (AC5) | T6 bounded to a reminder; T7 push is inline prompt text, never a regex/lint gate |
| Root-failure-mode closed (FR-20) | T7 push addresses the delegated-sub-agent path that V7 showed pull misses |
