# Implement handoff — approval-binding-and-upgrade-classification

## Role bootstrap (read this BEFORE any other reads)

You are operating as the **AI Developer** under Fusebase Flow v4.6.1.

**Self-attest** per `FLOW_RULES.md` § Self-attestation (FR-01..FR-27), naming AI Developer as the role and the IM.1..IM.18 role-discipline section.

**Hard invariants** are the FR rules in the `FLOW_RULES.md` table. Load-bearing here: FR-03 (one task = one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-10 (reproducibility before fix), FR-13 (lint+typecheck per commit). **Liveness (FR-27)** — never launch long/silent work bare; bound it (`source hooks/local/lib/bounded-run.sh`), complete in-turn, or return `BLOCKED-AT-<gate>`. **Write-time discipline (FR-24)** — apply the `role-discipline` § Write-time discipline digest on every write: FR-23, FR-09, FR-18, FR-22, FR-25, FR-26. Read them in `FLOW_RULES.md` / the cited skills; do not work from paraphrase.

**Refusal phrasing:**

> "I can't do that under FR-XX (<rule name>). Here's the path that complies: <alternative>."

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md` — FR-01..FR-27 (stop at `## Amendment log`)
2. `AGENTS.md` — project-specific section, worker-undisturbed paths, project invariants
3. `docs/specs/approval-binding-and-upgrade-classification/spec.md`
4. `docs/specs/approval-binding-and-upgrade-classification/decisions.md` — K1..K17, all LOCKED
5. `docs/specs/approval-binding-and-upgrade-classification/tasks.md` — T1..T16
6. `docs/specs/approval-binding-and-upgrade-classification/verification-gate.md`
7. `policies/protected-paths.yml`
8. `flow-skills/role-discipline/references/ai-developer.md` — IM.1..IM.18
9. `flow-skills/comment-policy/SKILL.md`, `flow-skills/module-size-discipline/SKILL.md`

---

## Ticket header

| Field | Value |
|---|---|
| **Slug** | `approval-binding-and-upgrade-classification` |
| **Status** | ready for AI Developer |
| **Source spec** | `docs/specs/approval-binding-and-upgrade-classification/spec.md` |
| **Decisions locked** | `K1..K17` |
| **Task range (this handoff)** | `T1..T15` (stop at gate; do NOT run T16) |
| **Decision letter prefix** | `K` |
| **T-counter going in** | `T0`; first task is `T1` |
| **Lane** | Full (FR-21) |
| **Branch** | `fix/msys-v3307-hardening` (current) — do not switch |

---

## Pre-cached identifiers

| Identifier | Value | Why pre-cached |
|---|---|---|
| Full gate command | `bash hooks/local/preflight.sh && bash hooks/tests/run-tests.sh && python3 hooks/tests/run_hook_tests.py --compare-subprocess && bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code audit/hook-layer-manifest.json && bash hooks/local/verify-hook-manifest.sh` | From `.github/workflows/fusebase-flow-verify.yml:53-67` — do not re-derive |
| Single shell test | `bash hooks/tests/test-<name>.sh` | — |
| Test tag registry | `FF_TAGS` array in `hooks/tests/run-tests.sh` (~line 50) | New test files MUST be registered here or they never run |
| Handler fixture count | `EXPECTED_HANDLER_FIXTURES = 21` in `hooks/tests/run_hook_tests.py` | Bump when T6 adds fixtures, or the release gate fails |
| Manifest restamp | `bash hooks/local/stamp-hook-manifest.sh` | Required in the SAME commit as any covered-path change |
| Covered paths (this ticket) | `hooks/local/approve-local.sh`, `hooks/shared/command_policy.py`, `hooks/shared/path_policy.py`, `hooks/shared/policy_loader.py` are all in `audit/hook-layer-manifest.json` | Every commit touching them restamps |
| Mirror regeneration | `bash hooks/local/mirror-skills.sh && bash hooks/local/mirror-agents.sh` | Required in the same commit as any `flow-skills/**` or `agents/**` edit |
| FR-07 cycle | `bash hooks/local/write-bootstrap-approval.sh` → `git commit` → `bash hooks/local/write-bootstrap-approval.sh --consume` | Every commit in this ticket touches `fusebase_flow_internals` |
| Module-size check | `bash hooks/local/check-module-size.sh --all` | FR-25 ceiling 800 |
| Current line counts | `command_policy.py` 165 · `path_policy.py` 316 · `policy_loader.py` 152 | Verified at HEAD `1eb53a1`; T3/T10 must not grow these past their stated seams |

---

## Production state going in

| Fact | Value |
|---|---|
| HEAD | `1eb53a1` on `fix/msys-v3307-hardening` |
| `VERSION` | `4.6.1` |
| Hook-layer manifest | 121 assets, `audit/hook-layer-manifest.json` |
| Gate state | assumed green at HEAD — **run the full gate BEFORE T1** and record the baseline; a pre-existing red is not yours to inherit silently |
| Working tree | many untracked `docs/tmp/handoff/**` files present; leave them alone, never `git add -A` (denied by policy anyway) |

---

## Frontend / UI implementation brief

| Field | Value |
|---|---|
| Selected design direction | K12 — internal developer CLI, diagnostic-precision target |
| Product identity / target user | The operator of a Flow-installed repo, at the moment they are blocked by a gate or running an upgrade |
| Routes / screens / workflows in scope | Two text surfaces only: (1) the FR-12 denial message emitted by `pre_tool_use` / `permission_request`; (2) the `upgrade.sh` conflict report |
| Components or files in scope | T6's shared denial formatter; T12's report renderer in `managed_content_manifest.py` |
| Data types and fields | `Verdict` (K17), `required_actions: list[str]`, the ten K9 classification states |
| API/helper surfaces | one formatter per surface — no inline `echo`/f-string message construction scattered across handlers |
| Applicable conventions | `flow-skills/communication` Mode A (operator-facing chat/CLI): concrete, brief, scannable. **Not** Mode B — these are read by a human under time pressure |
| Stable test selectors | N/A (no DOM). Assert on stable **reason tokens** (e.g. `ACTION_MISMATCH`) in the audit-log `extra`, not on prose wording — prose may be reworded without breaking tests |
| Trust-critical real interactions | The denial message must state the **real** failure reason. A generic "no artifact found" when the artifact was present-but-expired is the specific defect AC14 exists to kill |
| Brand/source assets | N/A |
| Explicit non-goals | No colour/ANSI dependence (MSYS/Windows consoles vary — see `docs/problem-catalog/` MSYS entries); no emoji in hook stderr; no interactive prompts inside `pre_tool_use` (it is non-interactive by contract); do not redesign any other CLI surface in this repo |

**UX acceptance restated (AC14):** ≤8 lines, ordered — what was blocked → every required action → the specific per-artifact failure reason → one exact resolving command. **AC15:** safe classification groups collapse to counts; `consumer-only` / `changed-by-both` / dirty-deleted / `unknown-base` paths are enumerated in full and never elided behind "N files"; backup dir named; exact resume command last.

---

## Tracks

Three arcs. Parallel-safe **only** at arc granularity, and only after T2 lands.

1. **Validator arc (T3..T9)** — strictly serial; T3–T7 all edit `hooks/shared/command_policy.py`.
2. **Cross-carrier arc (T10)** — independent after T2.
3. **Upgrade arc (T11→T12→T13)** — serial within itself, independent of the other two.

T14 (docs/mirrors) requires all three. T15 (gate) serializes after T14.

**Recommendation: run everything serially T1→T14.** The arcs share `hooks/tests/run-tests.sh` (`FF_TAGS` registration) and `audit/hook-layer-manifest.json` (restamped every commit), so concurrent commits will collide on those two files even across "independent" arcs. Parallelism here buys little and risks a dirty manifest.

If you do delegate, inline the **Write-time discipline digest**, the **Comment policy (FR-22) Delegation push block** below, and the **Delegation contract push block** (`task-delegation` §3) into the sub-agent prompt — a sub-agent inherits none of them.

---

## Comment policy (FR-22) — applies to all code written under this handoff

```
COMMENT POLICY (FR-22) — applies to all code you write:
Write ONLY two kinds of comment; remove everything else.
1) TRIPWIRE — a constraint an editor could break unknowingly, not obvious from local code (≤1 line; ≤4 lines only for security/auth/concurrency/platform).
2) RETRIEVAL POINTER — a ≤1-line tag naming the external WHY-home, e.g. "(decision K6)" or "backlog 156".
REMOVE: comments that restate what the code does; rationale already recorded in a decision/ticket/memory; changelog/history (it's in git).
Do NOT match surrounding comment density upward. Keep pointers — they are not duplicates.
```

**Tripwires this ticket specifically wants** (security/platform class, so up to 4 lines each — these are exactly the constraints a future editor would break unknowingly):

| Location | Tripwire content |
|---|---|
| `approval_artifact.parse_expiry` | expiry is parsed, never string-compared — lexicographic compare was the original defect (decision K1) |
| `approval_artifact.Verdict` | verdict is state only; mode resolution lives in `is_acceptable` (decision K17) |
| `command_digest` helper | whitespace-collapse only; any further normalization widens what an artifact authorizes (decision K6) |
| `command_policy` regex handling | `re.error` denies, never skips — skipping silently disables the rule (decision K4) |
| `upgrade.sh` base-refresh step | new base installs AFTER apply; reordering makes the classifier single-shot (decision K13) |
| `path_policy` bootstrap block | digest/operation/exact-path checks are unchanged and additional to the shared expiry check (decision K17) |

After code passes, emit `comment-policy review: applied (FR-22)` in chat.

---

## Worker-undisturbed posture

| Posture | Paths |
|---|---|
| **Edited by design** (FR-07 bootstrap approval per commit) | `hooks/shared/**`, `hooks/handlers/**`, `hooks/local/**`, `policies/**`, `audit/**`, `flow-skills/**` + their `.claude/skills/**` / `.agents/skills/**` mirrors |
| **Zero diff expected** | `hooks/git/**`, `templates/**`, `.claude/settings.json.example` (K11 defers consumption — no PostToolUse wiring is added) |

Every commit: mint → commit → `--consume`. **Never `--no-verify`** — it is a hard deny in `policies/command-policy.yml:35-37` and bypassing it is an IM-rule violation, not a shortcut.

---

## Stop at gate

Per FR-05, stop at **T15**. Do NOT run T16. Do NOT deploy. Do NOT bump `VERSION`. Produce the gate report per `verification-gate.md` and halt.

---

## Per-output state announcement (every chat reply)

```
---
📍 Phase: Implement
🎯 Ticket: approval-binding-and-upgrade-classification
✅ Completed: T1..T<n-1> (<SHAs>)
📍 Current: T<n> (<task name>)
⏭️ Next: <next task OR "stopping at gate; reporting">
```

## Per-commit pre-attestation

```
T<n> pre-commit check:
☐ Lint clean
☐ Typecheck clean
☐ Full or scoped test phase for this task's tag passes
☐ Hook-layer manifest restamped and staged (if a covered path changed)
☐ Mirrors regenerated and staged (if flow-skills/** or agents/** changed)
☐ One task scope (no bundling)
☐ No TODO/FIXME/WIP markers
☐ Comments: tripwire + pointer only (FR-22)
☐ Module size (FR-25): check-module-size.sh clean; no gated file grew past ceiling
☐ FR-07 bootstrap approval minted for this changeset
☐ Commit message cites T<n>
```

Any check fails → STOP and fix before commit. No "fix in the next commit".

---

## Gate report contract (at T15)

Produce from `templates/gate-report.md`; required fields per `policies/gate-contracts.yml: gate_report`. The gate run is **unscoped** — no `FF_ONLY` — and may cite only `state/audit/hook-test-results.md`, never `hook-test-results-scoped.md`. Exempt from the delegated chat-return budget; never truncate evidence.

Paste the report back, then **halt**.

---

## Notes / context (PO-authored)

**Where this came from.** A consumer project upgraded 4.5.0 → 4.6.1, and the upgrade silently reverted their local hardening of the approval gate. Their report was adversarially validated before they sent it; a Codex review then confirmed all four of their claims against this repo and found fourteen adjacent defects they had missed; a Fable review of the resulting plan found two BLOCKERs in my first draft. The plan you are executing is the third pass. Treat the file:line citations as verified — but if one is wrong, say so rather than working around it.

**The two things most likely to go wrong.**

1. **T13's base synthesis is load-bearing and easy to under-build.** If you skip it, every path classifies `unknown-base`, K9 preserves all of them, and the upgrade appears to succeed while installing nothing. S4's control-file assertion exists precisely to catch that. A green run that preserved everything is a FAIL.
2. **T12 rewrites the apply loop, it does not extend it.** Today's engine does whole-directory `cp -R`. Per-file apply is the change. If you find yourself adding a special case to the directory copy, stop — you are building the wrong thing.

**The self-hosting trap.** You are editing the hooks that gate your own commits. Fable walked this and found no ordering deadlock — `git commit` matches no command rule, `write-bootstrap-approval.sh` is independent of `approve-local.sh`, and pre-commit runs working-tree code so a broken `path_policy` is self-recoverable. But note one live hazard: after T4, a syntactically invalid `policies/command-policy.yml` will deny **every** Bash command in this tree. The escape hatch is the **Edit tool** (separate path-policy gate). Never `--no-verify`.

**On FR-10.** Several defects here are already reproduced — the Codex report carries file:line proof for each. You do not need to re-reproduce those. You DO need to reproduce anything you discover that is not in the plan, before fixing it, and file it rather than silently widening scope (FR-11 / IM don't-list).

**On scope discipline.** The Codex review listed fourteen adjacent defects; the spec's § Out of scope deliberately excludes several (single-use consumption, authenticated authorship, ticket binding as security, a validator plugin seam). If you think one of those is load-bearing for a task, **stop and say so** — do not implement it. File anything else you find in `docs/backlog/`.

**Related prior art — read before T14's problem-catalog entry:** `docs/problem-catalog/security-check-fail-open-class/problem.md` (the v3.30.5 sweep that missed this carrier) and `docs/problem-catalog/live-enforcement-inertness/problem.md` (green tests, inert enforcement). T14(a2)'s lesson is the *recurrence*, not the defect — cross-link, do not restate (FR-23).
