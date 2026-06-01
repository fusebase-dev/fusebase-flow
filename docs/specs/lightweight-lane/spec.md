# Spec — lightweight-lane

**Status:** DONE
**Created:** 2026-06-01
**Closed:** 2026-06-01
**Linked decisions:** L1..L9
**Deploy hash:** N/A — framework/template change
**Source:** operator proposal `paperclip+hermes-v1/docs/fusebase-flow-proposals/2026-06-01-lightweight-lane-for-trivial-changes.md` (production experience)

## Problem

Fusebase Flow applies the **same full lifecycle to every change** regardless of size or risk: Specify → Clarify → Plan → Decisions → Tasks → Verify(gate) → Implement → review → Deploy (DP.1 approval artifact + DP.6 magic phrase + deploy handoff), plus a two-agent build-then-deploy split. For a genuinely trivial, reversible change this is disproportionate. A measured one-line edit took ~10–16 min wall-clock with **~98% of the effort in process/build/verify/approval and ~2% in the change**. Second-order costs: (1) approval fatigue dilutes the signal of approvals that matter; (2) extra steps (redundant rebuild from the two-agent split) add risk the change itself doesn't carry.

Root cause: the lifecycle is calibrated for uncertain/risky work and there is **no tier below it**. The only existing concession — the `requirements-specification` skip-clarify gate — skips *clarify* only; it still drafts the spec and runs the rest of the chain.

## Why now

Operator directive (2026-06-01): "update Fusebase Flow so it doesn't do paperwork where it's not necessary." Filed from production use with a worked example.

## In scope

- **L1** New always-on rule **FR-21 — ceremony proportional to change size**: authorizes a two-tier model, defines the safety floor kept in both lanes, and the mid-flight promotion rule.
- **L2** New skill `lightweight-lane` — single source of truth for the **eligibility gate** (6 conditions), the **change-note** artifact, the **one-pass** build→verify→deploy procedure, and **mid-flight promotion**.
- **L3** `change_tier: full | lightweight` recorded at classification (in the change-note for LL; in spec.md for Full). Telemetry: tier + any promotion logged in a minimal ledger.
- **L4** New template `templates/change-note.md` (problem · change · verification · rollback · tier · SHA) — usable inline in the commit body or as `docs/changes/<date>-<slug>.md`.
- **L5** Lightweight deploy approval: replace DP.1 JSON artifact + DP.6 magic phrase with **one explicit plain operator go-ahead** for LL-eligible changes. No separate deploy session.
- **L6** One agent pass for LL (build→verify→deploy in a single run; no redundant rebuild).
- **L7** Tier-aware skills: `requirements-specification` (classify + skip-ceremony), `implementation-planning` / `validation-and-qa` / `release-deploy-reporting` (LL mode), `role-discipline` (LL discipline + promotion in PO/IM/DP), both agents.
- **L8** Tier-aware policies (opt-in hook layer): `approval-policy.yml` + `required-artifacts.yml` accept a lightweight deploy path without weakening the Full lane.
- **L9** Docs: AGENTS/CLAUDE/GEMINI overlays, README, eight-phase-flow workflow, FR range + version sweep; VERSION 3.7.0; CHANGELOG; release notes; plugin manifests.

## Out of scope

- Removing or weakening any safety control (live-proof, deploy go-ahead, FR-07, rollback, one-commit) — these are retained in both lanes.
- Auto-deploy / removing the human from the deploy loop — never.
- Touching `paperclip+hermes-v1` or any downstream project (reference only).
- Changing the Full lane's behavior for risky/uncertain work.

## Eligibility gate (a change is Lightweight-eligible iff ALL hold)

1. **Small implementation, single coherent concern** — modest code, no large/multi-part build; a handful of files is fine. Test = *no large implementation **and** no real architectural decisions*, not a hard file count.
2. **Reversible** — `git revert`/restore-backup undoes it; no DB schema/data migration; no hard-to-remove new dependency.
3. **Clear, mechanically-verifiable acceptance** — a defined outcome (1–few sentences) checkable by a gate/probe/measurement.
4. **No new security surface** — no authz/permission/protected-path/secret-handling change.
5. **No cross-cutting / public-contract change needing a decision** — no new API/route/manifest requiring an architectural choice (a routine in-place SKIP-upgrade deploy is fine); no broad refactor.
6. **Root cause already understood** — not a Phase-1 diagnostic (unknown-cause investigation always uses Full).

If **any** fails, or it's a large feature you'd want to audit before the next thing ships, or there is genuine doubt → **Full lane**. Fail-safe: when unsure, escalate up.

## What the Lightweight Lane keeps / drops

**Keeps (the actual risk controls):** live verification/proof · explicit operator deploy go-ahead · FR-07 worker-undisturbed/protected-path check · a documented one-line rollback · one commit per change + SHA recorded.

**Drops (planning/traceability overhead, not safety):** separate spec/decisions/tasks/verification-gate/two handoff docs/DP.1 artifact · the DP.6 magic phrase · the build-then-deploy two-agent split (→ no redundant rebuild) · the long-form gate report.

## Mid-flight promotion (hard rule)

If an LL change turns out non-trivial — touches more than a couple files, surfaces a risk, needs a real decision, or the "one-line" fix reveals a deeper bug — **STOP and promote to Full lane.** Promotion is logged in the ledger (telemetry).

## Acceptance criteria

1. **AC1 (L1)** — `FLOW_RULES.md` has FR-21 (ceremony proportional to change size) with what/why/enforcement; self-attestation range updated to `FR-01..FR-21` across all live-attestation surfaces; amendment-log entry added.
2. **AC2 (L2)** — `skills/lightweight-lane/SKILL.md` exists and is the single source of the eligibility gate, change-note, one-pass procedure, and promotion; mirrored to provider sets; health auto-discovers it (count 23→24).
3. **AC3 (L4)** — `templates/change-note.md` exists (problem · change · verification · rollback · tier · SHA).
4. **AC4 (L5/L6)** — for an LL-eligible change the agent runs build→verify→deploy in ONE pass and accepts a plain operator go-ahead (no DP.6 magic phrase, no hand-authored DP.1 JSON, no separate deploy session). The explicit go-ahead is still required (never auto-deploy).
5. **AC5 (L7)** — `requirements-specification` classifies tier (skip-clarify generalized to a lane-classification gate referencing `lightweight-lane`); `validation-and-qa` has an LL verification mode (live-proof kept, 1–3 line report, the 3-question empirical test still applied to the acceptance criterion); `release-deploy-reporting` has an LL mode; `role-discipline` PO/IM/DP carry the LL discipline + promotion; both agents reference the LL path.
6. **AC6 (L8)** — opt-in hook layer is tier-aware: a lightweight deploy is gated by a single one-command stamp (`approve-local.sh lightweight_deploy <slug>`) OR the full `production_deploy` artifact; the Full lane's `production_deploy` requirement is unchanged. (Hooks are opt-in/off by default since v3.6.0; in the default setup the chat go-ahead is the gate.)
7. **AC7 (L3)** — tier + any promotion are recorded (minimal ledger `docs/changes/index.md` and/or the change-note header).
8. **AC8 (L9)** — AGENTS/CLAUDE/GEMINI overlays + README document the two lanes; eight-phase-flow workflow references the lightweight lane and a `workflows/lightweight-lane.md` exists; VERSION 3.7.0; CHANGELOG + `docs/release-notes/v3.7.md`; plugin manifests bumped; skill count 23→24 updated in docs.
9. **AC9** — preflight 0/0; run-tests PASS (+ a tier-aware deploy-gate assertion); recovery sim PASS; health HEALTHY (24 skills); mirror drift 0; plugin validate clean; FR range + version strings consistent; no competitor names; `internal/`+`repo-polish` untracked.

## Risks

- **Misuse / over-broad LL** → the eligibility gate is conjunctive (ALL 6) + fail-safe-up + mandatory mid-flight promotion; classification and promotion are logged for audit. The line is "does this need design/decisions or carry real risk?" not "does it feel small?"
- **Weakening the deploy gate** → only the *ceremony* (magic phrase, hand-authored JSON, separate session) is dropped; an explicit human go-ahead, live-proof, protected-path check, and rollback are all retained. Hook-wired projects keep a machine-checkable one-command stamp.
- **FR range / version sweep error** → context-anchored replacement (only the live attestation phrasing), re-mirror, and a full grep verification; historical FR references untouched.

## Clarify summary

| Q | Answer | Date |
|---|---|---|
| Scope | Implement the full proposal (tiered lane) | 2026-06-01 |
| Touch downstream project? | No — reference only | 2026-06-01 |
| LL deploy gate when hooks wired? | One-command stamp accepted alongside `production_deploy`; chat go-ahead is the gate when hooks off (default). Recommended; revisitable. | 2026-06-01 |

## Close-out (2026-06-01)

All AC met; verification gate green.

| AC | Evidence |
|---|---|
| AC1 (L1) | FR-21 in `FLOW_RULES.md` (title + range FR-01..FR-21, rule row, implication, amendment log); FR range swept across 31 live-attestation surfaces |
| AC2 (L2) | `skills/lightweight-lane/SKILL.md` (single source of gate + change-note + one-pass + promotion); mirrored (48 skill files = 24×2); health auto-discovers 24 |
| AC3 (L4) | `templates/change-note.md` (problem · change · verified · rollback · tier · SHA) |
| AC4 (L5/L6) | one build→verify→deploy pass in `agents/ai-developer` + `workflows/lightweight-lane.md`; DP.12 plain go-ahead replaces DP.1/DP.6; explicit go-ahead still required (never auto-deploy) |
| AC5 (L7) | `requirements-specification` (lane classification), `validation-and-qa` (sub-mode E live-proof), `release-deploy-reporting` (LL mode), `role-discipline` (PO.16/IM.18/DP.12), both agents |
| AC6 (L8) | `approval-policy.yml` `lightweight_deploy`; `required-artifacts.yml` any_of + optional_when_lightweight; `stop.py` tier-aware; fixtures 15 (allow) + 16 (deny w/o rollback) PASS; Full lane unchanged |
| AC7 (L3) | `docs/changes/index.md` ledger; change-note carries `change_tier` |
| AC8 (L9) | `workflows/lightweight-lane.md` + eight-phase lane selection; overlays + README two-lane docs (24 skills); VERSION 3.7.0; CHANGELOG + `docs/release-notes/v3.7.md`; plugin manifests 3.7.0 |
| AC9 | preflight 0/0 · run-tests 16/16 · recovery sim PASS · health HEALTHY (24) · mirror drift 0 · plugin validate clean · no competitor names · internal/+repo-polish untracked |

## Related

- `docs/specs/lightweight-lane/decisions.md`
- `docs/release-notes/v3.7.md`
- source proposal (verified, this session)
