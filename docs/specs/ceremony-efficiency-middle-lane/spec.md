# Spec — ceremony-efficiency-middle-lane

**Status:** LOCKED (decisions resolved on operator finalize directive 2026-06-13; ready for implementation-planning). Any single decision reversible on request.
**Created:** 2026-06-12 · **Re-grounded:** 2026-06-13 from a stale v3.11.1 draft to the live baseline.
**Baseline:** FuseBase Flow **v3.21.1**, rules FR-01..FR-26.
**Linked decisions:** D1..D7 (LOCKED, below).
**Deploy hash:** N/A — framework/template change.
**Source:** consumer proposal `paperclip+hermes-v1` 2026-06-12/13 (controlled A/B from production). Naming decision: repo memory `find-wasted-effort-command-name`.
**Reviews folded:** (1) Codex independent → SHIP-WITH-CHANGES; (2) 5-lens verification → deploy-authority enforcement mechanisms; (3) 6-area re-grounding vs everything shipped v3.12→v3.21.1.

## Problems (as originally reported) → solutions

The proposal exists to solve three structural problems. Each is mapped to the one ask that solves it, and to what already shipped (so we build on it, not duplicate it).

| # | Problem (reported) | What already shipped (does NOT fully solve it) | Solution (this spec) |
|---|---|---|---|
| **PR-1** | The build→gate→**separate Deploy session** split is paid on **every substantial change**, even when the gate stop changes no outcome (a second full context rebuild each round). | v3.17.0 context-floor cut per-session cost ~30%; v3.18.0 `dp1_waiver` dropped deploy confirmations 3→2. **Both kept the two-session split** — the number of sessions is unchanged for substantial work. | **A1 — Middle Lane:** a third lane (one delegated build→verify→deploy session) for substantial-but-understood changes. |
| **PR-2** | **Ceremony ratchets** — incidents ADD steps; success never removes them; **no role owns pruning.** | Nothing. FR-25 is a line-count ratchet (unrelated); no incident-provenance taxonomy exists. | **A3 — ratchet governance:** every ceremony element carries `prevents: <incident-class>`; un-annotated + never-fired = a PO-owned *review* candidate. |
| **PR-3** | Consumers **can't diagnose** outcome-neutral ceremony — no instrument separates safety-bearing from waste. | v3.20.0 shipped `/token-waste-audit` + FR-26 + `token-economy` skill — but on a **different axis** (tokens-per-rule, from transcripts). | **A2 — `/find-wasted-effort`:** the process-per-outcome (ceremony) sibling, reusing the shipped audit's substrate + discipline. |

## Evidence (n=2 — a hypothesis, not a validated ratio)

One consumer, one day: two engine-defect fixes through FULL ceremony vs one equal-rigor fix through a single-session pass. Same safety substance in all three (adversarial plan review, RED-first reproduction, live proof, documented rollback).

| Measure | Heavy round (per round, ×2) | Light control |
|---|---|---|
| Wall time | ~2.5 h | ~30 min |
| Sub-agent contexts | 2 (build + deploy), each re-loading rules | 1 |
| Full-suite executions | 6 (one/commit) | 2 (baseline + end) |
| Gate-stop decision value (n=2) | none in these 2 clean rounds — PO approved every deviation (**see caveat**; NOT proof gate stops are worthless) | n/a |

> ⚠️ **Caveat.** n=2, one consumer, one day. A clean window is **not** proof; a gate stop can be low-frequency/high-severity. The ~40% outcome-neutral / ~60% safety-bearing split is an **n=2 observation, not a validated ratio.** **A2 exists precisely to replace this anecdote with measured, cross-project evidence** before A1's risky machinery is built (see Implementation order).

## A1 — Middle Lane (solves PR-1)

A third lane, **extending FR-21's existing two-tier model** (D1), classification-first:
- **Lightweight** (exists): trivial/reversible/known-cause → one pass, change-note only.
- **MIDDLE (new):** substantial change, root cause understood AND design passed adversarial review → **ONE delegated build→verify→deploy session** under hardened conditional deploy authority (below). Artifact = one **round-file** (D6). Full suite at baseline+end; scoped gates per commit.
- **Full** (exists): genuine mid-build design risk → unfamiliar subsystem, irreversible/migration, security surface, or builder must stop and ask.

**Eligibility = the existing FR-21 Lightweight gate, one notch stricter.** Do NOT re-derive it — reference `flow-skills/lightweight-lane/SKILL.md` (the 6 conjunctive conditions). Hard no-go (⇒ Full): auth/permissions/secrets · schema/data migration · any irreversible step · new/changed public contract · unknown root cause · unresolved adversarial-review findings · the change *is* deploy-authority/policy itself.

**Prior art it builds on (do not re-invent):**
- v3.18.0 **`dp1_waiver`** (`policies/approval-policy.yml:44-52`) is the working "builder self-stamps, operator's typed phrase gates" precedent — `middle_deploy` is a **stricter sibling** of it.
- v3.17.0 already cut per-session floor ~30%, so A1's win is **fewer sessions**, not cheaper ones. The honest thesis: *one session instead of two for substantial-but-understood work.*
- The v3.18.0 integration-debloat spec deferred a third lane ("waiver suffices"). A1's justification for overruling that: the waiver **kept the two-session split + full Deploy handoff + per-deploy DP.6** — so it never removed the second context rebuild, which is exactly PR-1.

**Conditional deploy authority (the blocker — each property bound to a mechanism).** A round-file pre-authorization is a *narrow, operator-authored, expiring, round-bound* exception, never a substitute for a real-time human deploy decision. The 5-lens + re-grounding reviews proved the current repo mechanisms defeat a properties-only statement:
1. **Operator-authored, by mechanism.** Today `hooks/local/approve-local.sh:64` sets `approved_by` from the build shell `$USER`, and `approval_authors` (`approval-policy.yml:101-105`) is **dead config — no hook reads it** (`command_policy.py` checks only filename + `expires_at`). So "deny the AI-Developer author" requires **building new author/role enforcement that does not exist for any action today** — plus a trustworthy operator signal the builder can't emit (retain a **DP.6-style typed phrase** for `middle_deploy`; do NOT drop it the way Lightweight does). The builder authors plan/result only — **never** the preauth or the allowed-deviation list.
2. **Distinct policy path** — `middle_deploy` (D2) in `approval-policy.yml` + `required-artifacts.yml` (the `any_of` slot, `required-artifacts.yml:66-71`) + `command-policy.yml`, with hook tests. Not `production_deploy`/`lightweight_deploy`.
3. **Pre-enumerated bounds the builder cannot widen.** Baseline suite fail-set **machine-captured before edits** (not builder-typed), immutable in the round-file; end set must **exact-match**; deviations listed in advance **by the operator**. Any unlisted deviation / new fail / gate miss ⇒ **automatic STOP→Full**. Widening the list = an unlisted deviation.
4. **Short, round-bound expiry.** Minutes-scale TTL (mode-aware TTL already exists, `approval-policy.yml:9-13` — config, not code), **not** the 90-day `direct_to_main` default. Artifact carries round-file id + baseline-fail-set hash; deploy gate verifies the bound round matches.
5. **Hooks-off ⇒ Middle deploy authority UNAVAILABLE (the common case).** Hooks ship off and the default clone has **no `settings.json`**, so hooks-off is the **default**, making every machine guarantee above vacuous unless the operator opts in. With hooks off, Middle's deploy **falls back to a real-time Full-lane DP.6 decision.** The builder is never the sole attestor.

## A2 — `/find-wasted-effort` (solves PR-3)

The **process-per-outcome** ceremony audit — the sibling of the shipped **tokens-per-rule** `/token-waste-audit` (FR-26). Different axis, different inputs (Flow artifacts on disk vs transcripts), **shared discipline.** It is **not** standalone-with-no-sibling (the original draft's premise was stale): it **reuses the shipped substrate** — the candidate/false-positive header, read-only-first posture, and gitignored `state/audit/<date>.md` output convention from `hooks/local/token-waste-audit.py` / `flow-skills/token-economy`.

Inputs (already on disk): gate reports, deploy reports, handoffs, approval artifacts, git log, round structure.

Detection rules (each emits **confirmed / dismissed / inconclusive** with required contrary-evidence):
1. **Unused gate stops** — N rounds where the gate approved every deviation ⇒ *suggest* Middle eligibility for that class, **only if** no blocked-gate counterexample exists in the window.
2. **Per-commit full-suite habit** — runs ≫ 2/round, identical fail-sets ⇒ recommend baseline+end.
3. **Artifact duplication** — same rule/evidence blocks in ≥3 round artifacts ⇒ pointers + round-file shape (exclude intentional self-bootstrapping).
4. ~~Context-rebuild overhead~~ — **CUT as net-new**: already shipped in `/token-waste-audit`'s v3.21.0 cross-session aggregate (re-grounding). `/find-wasted-effort` **points at that output** rather than re-implementing the signature.
5. **Lane misclassification** — small diff + zero design decisions but Full ceremony ⇒ recommend Lightweight/Middle (inconclusive on ambiguity; never auto-reclassify).
6. **Ratchet inventory** — element with no `prevents:` (A3) AND no firing in the window ⇒ **review candidate** (never "remove").
7. **Watch-vs-read waste (cross-session ceremony layer only)** — re-scoped so it does **not** duplicate FR-26's execution-layer record-then-read/polling signature.

Output: Mode-A report; **P2 ships read-only** (no writes/overlay/prune); proposed-memory + overlay edits only at **P3**, after per-rule false-positive fixtures exist.

## A3 — Ratchet governance (solves PR-2)

Annotate ceremony elements in templates/workflows with `prevents: <incident-class>` (e.g. `prevents: false-green deploy` on the live-proof step). Rare-but-severe controls tag `prevents: catastrophic-low-frequency` → **harder** to prune. This is the missing answer to "no role owns pruning": the **PO owns subtraction**, fed by `/find-wasted-effort` rule 6. **Pruning is never automatic** — an un-annotated, non-firing element is a *review candidate* only; removal needs named incident-class, severity, window, negative examples, and operator confirmation. (Coverage scoped per D5.)

## Non-negotiables (retained in EVERY lane)
Adversarial plan review for engine-class changes · RED-first reproduction · live proof of freshly-changed paths · rollback line · ground-truth-named claims.

## Decisions (D1–D7, LOCKED)
| # | Decision | Re-grounding note |
|---|---|---|
| D1 | **Extend FR-21 to three-tier** (not a new FR). | FR-21 is still strictly two-tier at v3.21.1; this is net-new. |
| D2 | **New `middle_deploy` path + security-permissions-review.** | Bigger than a config knob: `approval_authors` is **dead config**; author/role enforcement must be **built**. Model on the v3.18.0 waiver. |
| D3 | **PO owns classification; AI Developer promotes upward only; mid-build miss = STOP→Full.** | — |
| D4 | **Phase it: P1 = lane → P2 = audit read-only → P3 = audit writes/prune.** | — |
| D5 | **Scope A3 annotation** to rule-6-read + deploy/gate controls first; expand later. | — |
| D6 | **New `templates/round-file.md`** (don't overload `change-note.md`). | — |
| D7 | **`/find-wasted-effort` reuses the SHIPPED FR-26/token-economy discipline** (confirmed/dismissed/inconclusive, FP header, `state/audit/` output); tune per rule. | Original "no token-waste-audit here / standalone" premise was FALSE — corrected. |

## Implementation order (safe sequencing — all three ship)

Front-load the cheap, reversible, no-deploy-risk wins; let them produce the evidence that earns the risky lane. **All three asks are committed; this is order, not de-scoping.**

1. **Phase 1 (low risk):** A3 `prevents:` annotations + A2 `/find-wasted-effort` **read-only**. Ships via the Lightweight lane. Solves PR-2 + PR-3; begins measuring PR-1 across projects.
2. **Phase 2:** A2 write phase (proposed-memory) once per-rule FP fixtures exist.
3. **Phase 3 (the lift):** A1 Middle Lane — FR-21 three-tier + the `middle_deploy` enforcement **code** + round-file + security-permissions-review. Ships via the **Full** lane (AC7). Gated on: A2 evidence beyond n=2 that the second-session rebuild is genuinely outcome-neutral for a change class, AND the `middle_deploy` design passing security review.

## Acceptance criteria
- **AC1** Middle Lane = FR-21 three-tier extension + skill, referencing the existing eligibility gate (one notch stricter), with the hardened non-gameable conditional-deploy properties and PO-owned upward-only promotion — no non-negotiable weakened.
- **AC2** `/find-wasted-effort` ships **read-only (P2)**: 6 active rules (rule 4 cut) each emitting confirmed/dismissed/inconclusive with per-rule FP fixtures; reuses the shipped `state/audit/` output + FP-header convention; **no writes until P3**.
- **AC3** `prevents:` annotation on the scoped set (D5), `catastrophic-low-frequency` available; audit states its coverage.
- **AC4** `middle_deploy` wired into approval/required-artifacts/command policies **with new author-role enforcement code** (today none exists), a DP.6 typed phrase, minutes-scale round-bound TTL, machine-captured immutable baseline, operator-authored non-widenable bounds, **hooks-off ⇒ fall back to Full DP.6**; security-permissions-review clean.
- **AC5** Docs + sweep: AGENTS/CLAUDE/GEMINI overlays, README, eight-phase-flow workflow, FR-range + version strings, CHANGELOG, release notes, plugin manifests.
- **AC6** Standard gate: preflight 0/0; run-tests PASS (+ Middle-lane fixtures); recovery sim PASS; health HEALTHY; mirror drift 0; plugin valid; `internal/`+`repo-polish` untracked.
- **AC7** **A1 ships via the Full lane** (it changes deploy authority) — do NOT dogfood conditional deploy on its own ticket. `/find-wasted-effort` (read-only) run once against this repo as the first consumer.

## Out of scope
- Removing/weakening any non-negotiable, FR-07, deploy go-ahead, one-commit, rollback.
- Auto-deploy / removing the human from the deploy loop — conditional authority is operator-pre-authorized, expiring, round-bound, hooks-on-only.
- Re-implementing `/token-waste-audit` (FR-26) — A2 reuses it.
- Touching `paperclip+hermes-v1` or any downstream project.

## Notes
- Re-grounded against the live framework (6-area investigation): A1/A3 are genuine gaps; A2 is a genuine gap on the ceremony axis (its "standalone" premise was corrected). Nothing here was on the roadmap/backlog.
- Naming rationale: repo memory `find-wasted-effort-command-name`.
