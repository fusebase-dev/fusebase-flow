# Spec — fr22-delivery-guarantee

**Status:** DONE — shipped in **FuseBase Flow v3.27.0** (release commit `53e9437`, tag `v3.27.0`, 2026-06-17). **Phase 1 (A–E)** shipped; **Phase 2 (F) DEFERRED** to backlog ticket `fr22-predelegation-hook` per design review. Feature commits `b7b2d87..35d9a82`.
**Created:** 2026-06-16
**Baseline:** FuseBase Flow v3.26.0
**Source:** Consumer report — "FR-22 (comment-policy) hardening has no delivery guarantee — it failed even though every lever 'exists'." Verbose changelog/ticket-history comments shipped during a long autonomous multi-agent build (delegated ai-developer sub-agents + Codex reviews); the removable class FR-22 names.
**Lane:** Full (multi-surface framework change; affects every delegated/multi-agent build).
**Design review:** Codex 2026-06-16 → **RESCOPE**. Phase 1 confirmed FR-22-safe + FR-07-clean → ship. Phase 2/F **deferred**: the decisive finding — a delegation-tool PreToolUse hook is **inert under the shipped matchers** (`.claude/settings.json.example` / `.codex/hooks.json.example` match Bash/Edit/Write only, not Task/Agent), so F as written would *recreate the mandatory-but-undelivered failure it fixes*; and its "code-writing delegation" heuristic over-fires on research/Explore delegations and misses code delegations using other tool names / dynamic prompts. F needs host-matcher coverage + explicit delegation markers + warn-only telemetry first → its own ticket. Decisions D1–D5 folded below.

## Problem (grounded against the repo)

FR-22 is **mandatory in prose, undelivered in practice, unverifiable by its own design.** It holds for short single-context tasks and fails in long, delegated, multi-agent builds — exactly where it matters most. Verified:

1. **The write-time carrier doesn't structurally reach sub-agents.** `flow-skills/comment-policy/SKILL.md:82-93` ships the rule as a "Delegation push block — paste this block into its prompt." The implement-handoff template instructs inlining it (`templates/handoff-implement.md:105`) and the per-commit checklist has an FR-22 line (`:146`) — but it is a **"remember-to-inline" instruction, not a present-by-construction block**. In a long run the PO-authored handoff omits it (the reporter's Wave RA/RB handoffs cited FR-03/10/13/25, not FR-22) and the sub-agent never sees the rule.
2. **Nothing verifies the handoff carries the block.** No pre-delegation / PreToolUse check inspects a code-writing delegation for the FR-22 block. `pre_tool_use.py` handles Bash-like + Edit-like tools only — the Task/Agent (sub-agent launch) tool is not intercepted.
3. **The review backstop is loop-invisible.** `stop.py` (`hooks/handlers/stop.py:48-57`) + `required-artifacts.yml` track `lint_clean`, `typecheck_clean`, `gate_report`, `deploy_hash`, live-user cleanup — **no** "comment-policy review applied" signal. The loop cannot tell whether comment hygiene ran.
4. **The "no gate" rule chilled the SAFE automation too.** The skill + `policies/comment-policy.yml` correctly forbid a **content** gate (tripwire-vs-restate is semantic). But that prohibition was over-generalized into building nothing — including artifact-level checks (handoff-contains-block, review-ran-signal) that inspect *process artifacts*, not comment semantics, and are fully FR-22-safe.
5. **The carve-out boundary ships undefined.** `policies/comment-policy.yml:24-36` ships `trust_critical_globs` fully commented out (deliberate opt-in, mirroring `protected-paths.yml`) — but every project then lacks the "where multi-line tripwires are legitimately OK" boundary, making the semantic call fuzzier at review.

**Meta-point:** "mandatory" without a delivery guarantee or a permitted enforcement point is operationally "optional with extra words." The fix is not more rules — it is making the existing rule **present-by-construction** (handoff template) and **verifiable at the artifact level** (handoff-contains-block + review-ran signal), never at the comment-content level.

## What works — DO NOT regress

- **FR-22's no-content-gate is correct and stays.** Distinguishing a tripwire from a WHAT-restate is semantic; a regex/lint gate would train agents to write worse comments to satisfy it. Every fix here is artifact-level (process), never comment-content matching.
- The two-kinds rule (tripwire + retrieval pointer), the "don't match density upward" clause, and "pointer ≠ duplicate" are load-bearing — preserve verbatim.
- `comment-policy.yml`'s opt-in posture (local-override-replaces-default, like `protected-paths.yml`) — keep the posture; only reduce fuzziness.

## In scope

### Phase 1 — present-by-construction + visibility (content / config / signal; low-risk)
- **A — handoff template, present-by-construction block.** `templates/handoff-implement.md`: replace the "remember to inline" prose with a **literal, non-optional section** carrying the actual FR-22 Delegation push block text (single source: reference the skill block, but render the block inline so it is present in every authored handoff). The PO fills the handoff; the block is there by construction, not by memory.
- **B — write-time digest carries the full rule + non-propagation note.** `flow-skills/role-discipline/SKILL.md` § Write-time discipline digest: carry the **full two-kinds rule** for FR-22 (not just "FR-22 comments: tripwire+pointer") **and** an explicit line: "this digest does NOT auto-propagate to sub-agents — when delegating code-writing, inline the comment-policy Delegation push block." (Read the current digest first; amend minimally.)
- **C — review-ran behavioral signal.** Add `comment_policy_review_applied` to `policies/required-artifacts.yml: signal_definitions` (a transcript marker the agent emits, e.g. the literal phrase "comment-policy review: applied (FR-22)") and require it in `before_done_claim`; add detection to `stop.py: _signals_from_transcript`. Records that the review **ran** — never what the comments say (FR-22-safe). Same class as `lint_clean_marker`. **(deny-vs-warn + lightweight carve-out → design-review decision D1.)**
- **D — document the artifact-vs-content distinction.** `flow-skills/comment-policy/SKILL.md` + `docs/comment-policy.md`: state explicitly that **gating on comment content is forbidden, but artifact-level checks (handoff-contains-block, review-ran-signal) are encouraged.** This stops maintainers/agents from conflating the two and building nothing. **NOT** in the `FLOW_RULES.md` FR-22 rule row (FR-07 — see Constraints).
- **E — reduce carve-out fuzziness (light).** `policies/comment-policy.yml`: keep the opt-in posture; add a clearer "derive at Specify via `references/audit-prompt.md`" trigger and a tighter starter set of commented defaults so the boundary is one uncomment away. No gate. **(ship-defaults-vs-keep-opt-in → design-review decision D3.)**

### Phase 2 — pre-delegation artifact check — **DEFERRED to follow-up ticket `fr22-predelegation-hook`**
- **F (NOT in this ticket).** A pre-delegation PreToolUse check that a code-writing sub-agent launch carries the FR-22 block. Concept is FR-22-safe (inspects prompt/handoff text, not comment semantics) — but design review found it **inert as written** and the heuristic fuzzy. Prerequisites the follow-up ticket MUST add before F is buildable: (1) **host-matcher coverage** — `.claude/settings.json.example` + `.codex/hooks.json.example` + settings-merge defaults + hook-coverage docs must invoke PreToolUse for the delegation tool(s), else the handler never runs; (2) **explicit delegation markers**, not generic keywords — fire only on a `docs/tmp/handoff/*-implement.md` reference OR a structured `Role boundary: code-edit` field; never on words like "implementation"/"codebase"; (3) **warn-only default** + telemetry; allow when the prompt or referenced handoff already contains the FR-22 block marker; (4) config in `policies/comment-policy.yml` (not `required-artifacts.yml`). Until those land, F would recreate the mandatory-but-undelivered failure this ticket fixes.

## Out of scope / non-goals
- Any regex/lint gate on comment **content** (forbidden by FR-22, permanently).
- Editing the `FLOW_RULES.md` FR-22 rule row (FR-07).
- Retroactively cleaning existing over-commented files (separate Lightweight pass, FR-21).
- Changing the two-kinds rule semantics.

## Constraints (FR-07 worker-undisturbed)
- **No diff** to: `FLOW_RULES.md` FR rule rows (the FR-22 clarification goes in the skill + `docs/comment-policy.md`, never the row); the 3 deploy policies' rule semantics (`approval-policy.yml`, `protected-paths.yml`, `command-policy.yml`); `ratchet-governance.yml`.
- **Editable:** `comment-policy.yml`, `required-artifacts.yml`, `pre_tool_use.py`, `stop.py`, the handoff template, the comment-policy + role-discipline skills, `docs/comment-policy.md`.
- comment-policy + role-discipline are canonical skills → re-mirror after edits (preflight checks drift). Keep `.claude/skills` + `.agents/skills` mirrors in sync.

## Decisions (LOCKED — design review folded)
- **D1 (signal C):** **warn**, not deny. Applies to **every** Implement-done claim (not only when delegation occurred). Two marker phrases the agent emits: `comment-policy review: applied (FR-22)` (code diff present) and `comment-policy review: N/A (FR-22; no code diff)` (no-code ticket). Detection accepts either; absence → warn (not block). No lightweight carve-out (warn is already non-blocking). Rationale: deny would over-block compliant tasks that did the review but missed an exact phrase, and "applied" is inaccurate for no-code tickets — warn + N/A marker ends the loop's blindness without a false floor.
- **D2 (hook F):** **DEFER** (see Phase 2). If/when built: explicit delegation markers + handoff reference only, warn-only default, config in `comment-policy.yml`, host-matcher coverage first.
- **D3 (E):** **keep opt-in.** Improve commented starter defaults + the "derive at Specify via `references/audit-prompt.md`" trigger; do **not** ship active broad defaults (they'd weaken review semantics). The boundary is one uncomment away, posture unchanged (mirrors `protected-paths.yml`).
- **D4:** **acceptable layering** if terse. A (handoff block) / B (digest) / C (review-ran signal) each cover a distinct failure point; keep the existing per-commit FR-22 line (`:146`) short. No consolidation.
- **D5:** Phase 1 (A–E) is **FR-22-safe + FR-07-clean** (confirmed). F is clean only after the host-matcher/config rewrite → deferred.

## Implementation note (FR-07 / protected paths)
Editing `policies/*.yml` and `hooks/handlers/**` may be gated by `policies/protected-paths.yml` when Flow hooks are wired. The AI Developer must check `protected-paths.yml` and, if those paths are protected, author the required protected-path approval artifact (`state/approvals/`) before editing — or confirm hooks are unwired (opt-in) in this repo. Either way: do NOT diff the FR rule rows, the 3 deploy-policy rule semantics, or `ratchet-governance.yml`.

## Acceptance criteria
- **AC1 (A)** A freshly-authored implement handoff from the template contains the FR-22 Delegation push-block text by construction (not a "remember to inline" line). A test asserts the template contains the block.
- **AC2 (B)** The role-discipline write-time digest carries the full two-kinds FR-22 rule + the explicit "does not propagate to sub-agents — inline it" note.
- **AC3 (C)** `stop.py` detects `comment_policy_review_applied` from either marker (`comment-policy review: applied (FR-22)` OR `comment-policy review: N/A (FR-22; no code diff)`); `before_done_claim` includes it as **warn** (per D1); a test proves the signal fires on each marker and is absent without it (RED-then-GREEN); existing signals unaffected; on_missing for the entry does not hard-block.
- **AC4 (D)** The comment-policy skill + `docs/comment-policy.md` state the content-gate-forbidden / artifact-check-encouraged distinction. `FLOW_RULES.md` FR-22 row unchanged (FR-07).
- **AC5 (E)** Per D3 — opt-in posture preserved; clearer derivation trigger + tightened commented starter set present; no active broad defaults; still no gate.
- **AC6 (F)** — **DEFERRED** to `fr22-predelegation-hook` (not asserted in this ticket).
- **AC7 (gate)** preflight 0/0; run-tests PASS incl. the new tests; check-module-size --all exit 0 (stop.py under ceiling); mirror 0 drift; FR-07 clean; FR-22 row unchanged; clean-room note intact.

## Tasks
- **T1 (A)** handoff-implement template present-by-construction FR-22 block.
- **T2 (B)** role-discipline write-time digest amendment (full two-kinds rule + non-propagation note).
- **T3 (D)** comment-policy skill + docs/comment-policy.md artifact-vs-content distinction doc.
- **T4 (C)** required-artifacts.yml signal (warn) + two marker phrases + stop.py detection.
- **T5 (E)** comment-policy.yml carve-out clarity (opt-in preserved, per D3).
- **T6 (F)** — **DEFERRED** to follow-up ticket `fr22-predelegation-hook`.
- **T7** tests (AC1 template-contains-block, AC3 signal RED-GREEN both markers) + re-mirror skills.

## Risks
- **F false-positives** (the biggest): a pre-delegation gate that misfires on research/non-code delegations disrupts legitimate work — hence warn-default + careful heuristic + a non-code-delegation test. Design review must pressure-test the heuristic.
- **C over-blocking:** a hard-deny review-ran signal could block compliant single-context tasks that did the review inline without emitting the exact marker — hence the marker convention must be cheap to emit and D1 weighs deny-vs-warn.
- **Layering noise:** multiple FR-22 reminders (A+B+existing :146) — keep each terse; D4.
