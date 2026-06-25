# Implement handoff — fr22-delivery-guarantee (Phase 1)

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.26.0. Self-attest FR-01..FR-26 + IM.1..IM.18. Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-13 (lint/typecheck per commit), FR-22 (comments — see the push block below), FR-23 (doc budget), FR-25 (module size). **Run synchronously; stop at the gate; do NOT bump version, push, or deploy.**

## COMMENT POLICY (FR-22) — applies to all code you write (dogfood: this ticket is about this rule)
```
Write ONLY two kinds of comment; remove everything else.
1) TRIPWIRE — a constraint an editor could break unknowingly, not obvious from local code (≤1 line; ≤4 lines only for security/auth/concurrency/platform).
2) RETRIEVAL POINTER — a ≤1-line tag naming the external WHY-home, e.g. "(decision D1)" or "backlog 156".
REMOVE: comments that restate what the code does; rationale already recorded in a decision/ticket/memory; changelog/history (it's in git).
Do NOT match surrounding comment density upward. Keep pointers — they are not duplicates.
```
And after your code passes, emit the literal marker in chat: `comment-policy review: applied (FR-22)` (or `comment-policy review: N/A (FR-22; no code diff)` for a no-source task). This ticket creates that very signal — so honoring it here is the first test.

## Mandatory reads
1. `FLOW_RULES.md` FR-01..FR-26 (stop at Amendment log).
2. `docs/specs/fr22-delivery-guarantee/spec.md` — the LOCKED spec. **Decisions (D1–D5), Tasks (T1–T7), and Acceptance criteria are consolidated there** (FR-23 — no separate decisions/tasks/gate files for this contained framework change). Authoritative.
3. `policies/protected-paths.yml` — check whether `policies/**` / `hooks/handlers/**` are worker-undisturbed here (see FR-07 note below).
4. The surfaces you edit (read each before editing): `templates/handoff-implement.md`, `flow-skills/role-discipline/SKILL.md` (§ Write-time discipline digest), `flow-skills/comment-policy/SKILL.md`, `docs/comment-policy.md`, `policies/required-artifacts.yml`, `hooks/handlers/stop.py`, `policies/comment-policy.yml`.
5. `flow-skills/role-discipline/references/ai-developer.md`.

## Scope — Phase 1 only (A–E + tests). DEFER F (Phase 2). One commit per task (FR-03).

- **T1 (A) — `templates/handoff-implement.md`: present-by-construction FR-22 block.** Replace the "remember to inline" prose (~line 105) with a **literal, non-optional section** that renders the actual comment-policy Delegation push block text (the block above) inline in the template, so every authored handoff carries it by construction. Keep the existing per-commit FR-22 checklist line (~:146) — terse (D4). Also add the review-marker reminder (emit `comment-policy review: applied (FR-22)` at done).
- **T2 (B) — `flow-skills/role-discipline/SKILL.md` § Write-time discipline digest.** Carry the **full two-kinds FR-22 rule** (tripwire + retrieval pointer; remove WHAT-restate/recorded-elsewhere/changelog; don't match density upward) instead of a bare "FR-22 comments" pointer, AND an explicit line: "this digest does NOT auto-propagate to sub-agents — when delegating code-writing, inline the comment-policy Delegation push block." Read the current digest first; amend minimally; keep it Mode-B terse.
- **T3 (D) — distinction doc.** In `flow-skills/comment-policy/SKILL.md` (a short subsection) + `docs/comment-policy.md`: state explicitly — **gating on comment CONTENT is forbidden (semantic, not pattern-matchable); artifact-level checks (handoff-contains-block, review-ran signal) are ENCOURAGED.** Do **NOT** touch the `FLOW_RULES.md` FR-22 rule row (FR-07).
- **T4 (C) — review-ran signal (WARN, per D1).** `policies/required-artifacts.yml`: add `signal_definitions: comment_policy_review_applied` ("transcript contains 'comment-policy review: applied (FR-22)' or 'comment-policy review: N/A (FR-22; no code diff)'"). Add it to `before_done_claim` as a **non-blocking / warn** signal — recommended NOT required: introduce a `recommended:` list (parallel to `required:`) whose missing signals emit a warning but do NOT deny. `hooks/handlers/stop.py`: detect the marker in `_signals_from_transcript`, and process the `recommended` list separately (emit a warn-level note via `emit(...)`/stderr; never add to the blocking `missing` set). Records that the review RAN — never inspects comment content (FR-22-safe). Keep existing signals/gates unchanged.
- **T5 (E) — `policies/comment-policy.yml` carve-out clarity (opt-in preserved, per D3).** Keep all globs commented (opt-in posture, mirrors protected-paths). Tighten the commented starter set + add a clearer "derive at Specify via `references/audit-prompt.md`" trigger line. Do NOT ship active broad defaults. No gate.
- **T7 — tests + re-mirror.** Add to `hooks/tests/`: (a) AC1 — assert `templates/handoff-implement.md` contains the FR-22 block text; (b) AC3 RED-then-GREEN — a transcript with each marker → `comment_policy_review_applied` detected; without → not detected AND stop still ALLOWS (recommended-missing does not block). Wire into `run-tests.sh`. Then re-mirror: `bash hooks/local/mirror-skills.sh` (comment-policy + role-discipline are canonical → mirrors + manifest update). RED-then-GREEN must be genuine (loud asserts; no false-green).

## FR-07 / protected paths
Check `policies/protected-paths.yml`. If `policies/**` or `hooks/handlers/**` are worker-undisturbed AND Flow hooks are wired here, author the required protected-path approval artifact in `state/approvals/` before editing (or confirm hooks are unwired/opt-in — settings.json absent). EITHER WAY: do NOT diff the `FLOW_RULES.md` FR rule rows, the 3 deploy-policy rule semantics (`approval-policy.yml` / `protected-paths.yml` / `command-policy.yml` rule content), or `ratchet-governance.yml`. You ARE adding to `required-artifacts.yml` and `comment-policy.yml` (not in that protected-3) and `stop.py` — those are in-scope edits.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ worker-undisturbed unchanged  ☐ one task scope  ☐ no TODO/FIXME/WIP
☐ FR-22 comments (tripwire+pointer only) in any code you write  ☐ FR-25 <ceiling
☐ FLOW_RULES FR rows / 3 deploy-policy semantics / ratchet-governance UNCHANGED
☐ commit cites the task
```

## Gate (stop, report, HALT)
preflight 0/0 · `python -m py_compile hooks/handlers/stop.py` · run-tests PASS incl. the new tests · check-module-size --all exit 0 (stop.py under ceiling) · mirror 0 drift (comment-policy + role-discipline mirrors byte-identical to canonical + manifest) · FR-07 clean (the 4 protected surfaces unchanged) · FR-22 row in FLOW_RULES unchanged. Produce the gate report; HALT. A Codex impl review runs after the gate. Emit `comment-policy review: applied (FR-22)` for your own diff.

## Return
The gate report: per-task SHAs (T1–T5, T7), the AC1 + AC3-RED-then-GREEN evidence, gate numbers, FR-07 confirmation (4 protected surfaces unchanged + protected-path handling), and the dogfood marker.
