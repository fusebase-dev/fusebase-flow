# Implement handoff — approval-binding-and-upgrade-classification (corrections round T17..T29)

## Role bootstrap (read this BEFORE any other reads)

You are operating as the **AI Developer** under Fusebase Flow v4.6.1.

**Self-attest** per `FLOW_RULES.md` § Self-attestation (FR-01..FR-27), naming AI Developer as the role and the IM.1..IM.18 role-discipline section.

**Hard invariants:** FR-03 (one task = one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-10 (reproducibility before fix), FR-13 (lint+typecheck per commit), FR-27 (liveness), FR-24 (write-time digest: FR-23/09/18/22/25/26). You are a delegated sub-agent — you inherit **no** auto-loaded skills and **not** the always-on digest. Read them yourself.

**Refusal phrasing:**

> "I can't do that under FR-XX (<rule name>). Here's the path that complies: <alternative>."

---

## Why this round exists

The first round (T1..T14, `1eb53a1..808db35`) shipped with a green 649/649 gate. An adversarial implementation review then found **7 BLOCKERs and 6 MAJORs**, including a **live gate bypass**. The green suite did not establish the contract — the same lesson recorded in `docs/problem-catalog/live-enforcement-inertness/problem.md`.

**Read the review first:** `docs/tmp/handoff/2026-07-28-approval-binding-codex-impl-review.md`.

The single most important consequence: **a passing test is not evidence here.** Every task in this round must add an assertion that goes **RED against the current code**. `verification-gate.md` § Regression discriminators names that assertion for each defect — it is a contract, not a suggestion.

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md` — FR-01..FR-27 (stop at `## Amendment log`)
2. `AGENTS.md` — project-specific section
3. `docs/tmp/handoff/2026-07-28-approval-binding-codex-impl-review.md` — the findings
4. `docs/specs/approval-binding-and-upgrade-classification/decisions.md` — **K1..K21**; note **K6 is REVISED** and K18..K21 are new
5. `docs/specs/approval-binding-and-upgrade-classification/tasks.md` — § Corrections round (T17..T29)
6. `docs/specs/approval-binding-and-upgrade-classification/verification-gate.md` — AC20..AC27, revised AC3/AC9/AC11, and § Regression discriminators
7. `docs/specs/approval-binding-and-upgrade-classification/spec.md`
8. `policies/protected-paths.yml`
9. `flow-skills/role-discipline/references/ai-developer.md`, `flow-skills/comment-policy/SKILL.md`, `flow-skills/module-size-discipline/SKILL.md`

---

## Ticket header

| Field | Value |
|---|---|
| **Slug** | `approval-binding-and-upgrade-classification` |
| **Status** | ready for AI Developer — corrections round |
| **Task range (this handoff)** | `T17..T29`, then re-run the gate `T15` |
| **Decisions locked** | `K1..K21` (K6 revised) |
| **Do NOT run** | `T16` (deploy), `VERSION` bump |
| **Branch** | `fix/msys-v3307-hardening` |
| **First round** | `308ea68..808db35` — do not revert; correct forward |

---

## Pre-cached identifiers

| Identifier | Value |
|---|---|
| Full gate (unscoped) | `bash hooks/local/preflight.sh && bash hooks/tests/run-tests.sh && python3 hooks/tests/run_hook_tests.py --compare-subprocess && bash hooks/local/stamp-hook-manifest.sh && git diff --exit-code audit/hook-layer-manifest.json && bash hooks/local/verify-hook-manifest.sh` |
| Baseline to beat | 649/649 PASS at `808db35`; after this round expect ≥ 649 + new discriminators |
| Test tag registry | `FF_TAGS` in `hooks/tests/run-tests.sh` |
| Handler fixture count | `EXPECTED_HANDLER_FIXTURES` in `hooks/tests/run_hook_tests.py` — currently 23; bump if T29 adds fixtures |
| Manifests | `bash hooks/local/stamp-hook-manifest.sh` · `bash hooks/local/stamp-managed-content-manifest.sh` — restamp in the SAME commit as any covered change |
| FR-07 cycle | `bash hooks/local/write-bootstrap-approval.sh` → commit → `--consume` |
| Module sizes now | `command_policy.py` 305 · `approval_artifact.py` 264 · `path_policy.py` 330 · `managed_content_manifest.py` 464 · `upgrade.sh` 770 (ceiling 800 — **`upgrade.sh` has only 30 lines of headroom**; T25 must extract into the Python module, not grow the shell) |

---

## The confirmed bypass — verify it before you fix it (FR-10)

`hooks/shared/command_policy.py:198-200` does `if display in verdicts: continue`. The `fusebase deploy` rule uses `any_of: [production_deploy, lightweight_deploy]` with display name `production_deploy`. Satisfy it with a **`lightweight_deploy`** artifact and `verdicts["production_deploy"]` is set — so the *separate* `git push origin main` rule, which genuinely requires `production_deploy`, is skipped.

```
fusebase deploy && git push origin main    +    lightweight_deploy artifact only    →    ALLOW
```

Reproduce that first. It is T19's discriminator and the single most important assertion in this round.

---

## Frontend / UI implementation brief

| Field | Value |
|---|---|
| Surfaces in scope | Same two internal CLI surfaces as round 1: the FR-12 denial message and the upgrade conflict/abort report |
| Changes required | **Denial message (T20, T22):** render the **complete** required-action set with per-action status, not only unsatisfied ones — the serial-denial UX AC14 was written to prevent reappeared through the rendering path. The resolving invocation must include `--command '<safely quoted blocked command>'` so the copy-paste path mints a *bound* artifact. Still ≤8 lines. **Abort report (T25, T27):** a fail-closed abort must state why it aborted, that nothing was written, and the one command that proceeds safely — never suggest `--unsafe-legacy-copy` |
| Constraint | No ANSI/colour, no emoji in hook stderr (MSYS console variance). Assert on stable tokens, not prose |
| Non-goals | Do not redesign either surface; these are targeted content corrections |

---

## Comment policy (FR-22)

```
COMMENT POLICY (FR-22) — applies to all code you write:
Write ONLY two kinds of comment; remove everything else.
1) TRIPWIRE — a constraint an editor could break unknowingly, not obvious from local code (≤1 line; ≤4 lines only for security/auth/concurrency/platform).
2) RETRIEVAL POINTER — a ≤1-line tag naming the external WHY-home, e.g. "(decision K18)" or "backlog 156".
REMOVE: comments that restate what the code does; rationale already recorded in a decision/ticket/memory; changelog/history (it's in git).
Do NOT match surrounding comment density upward. Keep pointers — they are not duplicates.
```

**Tripwires this round specifically wants:**

| Location | Content |
|---|---|
| `command_policy.py` requirement loop | requirements are per-rule; de-duplicating by display action reopens the `any_of` bypass (decision K18) |
| `approval_artifact` digest helper | strip only — collapsing interior whitespace collides quoted arguments (decision K6, revised) |
| `approve-local.sh` command gating | `--command` is mandatory for command-gated actions; an unbound artifact is replayable (decision K19) |
| `upgrade.sh` classifier guard | fail closed — the legacy copy path is the pre-4.7.0 overwrite behaviour (decision K20) |
| `preflight.sh` base recovery | never restamp from the working tree; that records consumer edits as upstream base (decision K20) |

Emit `comment-policy review: applied (FR-22)` after your code passes.

---

## Worker-undisturbed posture

| Posture | Paths |
|---|---|
| Edited by design (FR-07 approval per commit) | `hooks/shared/**`, `hooks/handlers/**`, `hooks/local/**`, `policies/**`, `audit/**`, `flow-skills/**` + mirrors |
| Ratified, bounded | `hooks/git/pre-commit` (import closure only — see gate § Ratified deviations D1), `.github/workflows/fusebase-flow-verify.yml` (D2) |
| Zero diff expected | `templates/**`, `.claude/settings.json.example` |

**Never `--no-verify`.**

---

## Stop at gate

After T29, re-run **T15** (unscoped full gate) and produce the gate report. Do **NOT** run T16, do **NOT** deploy, do **NOT** bump `VERSION`.

---

## Per-commit pre-attestation

```
T<n> pre-commit check:
☐ Discriminator written FIRST and observed RED against pre-fix code
☐ Lint / syntax clean
☐ Relevant test phase passes after the fix
☐ Manifests restamped and staged (if covered paths changed)
☐ Mirrors regenerated and staged (if flow-skills/** or agents/** changed)
☐ One task scope (no bundling)
☐ No TODO/FIXME/WIP markers
☐ Comments: tripwire + pointer only (FR-22)
☐ Module size (FR-25) clean — watch upgrade.sh (770/800)
☐ FR-07 bootstrap approval minted for this changeset
☐ Commit message cites T<n>
```

---

## State announcement (every reply)

```
---
📍 Phase: Implement (corrections round)
🎯 Ticket: approval-binding-and-upgrade-classification
✅ Completed: T17..T<n-1> (<SHAs>)
📍 Current: T<n>
⏭️ Next: <next task OR "re-running gate T15">
```

---

## Notes / context (PO-authored)

**Correct forward, never revert.** The first round is committed and mostly right. The K9 classifier core, the per-file apply loop, the shared `approval_artifact` judge, and the schema work all survived review. What failed is the safety boundary *around* the core: convenience paths that quietly restore destructive behaviour, and a rendering/dedup layer that undid two guarantees the loop had correctly established.

**Write the failing test first.** For every task, the discriminator in `verification-gate.md` § Regression discriminators must be observed RED before the fix and GREEN after. The review found several round-1 tests that would also pass against the *old* code — fixtures 22/23 carry no artifact, so first-match and all-match both deny them. That is the failure mode to avoid: a test that asserts the outcome without constraining the mechanism.

**K6 changed under you.** T5 shipped `collapse_whitespace`. The decision now says `.strip()` only, on evidence of a real collision. `tasks.md` T5's stale wording was already superseded. Do not re-derive the old behaviour.

**Two findings are deliberately NOT fixed** (locked K21): quote-fragmentation evasion (`fusebase de'pl'oy`) and dynamically-constructed commands. T28 ships the `rm` pattern fix, truthful documentation of the limitation, and a backlog ticket. Do **not** attempt shell parsing — a half-parser fails in both directions. If you think this is wrong, say so; do not build it.

**Scope stays closed.** Still excluded: single-use consumption, authenticated authorship, ticket-binding-as-security, a validator plugin seam. The review confirmed none leaked in round 1 — keep it that way.

**`upgrade.sh` is at 770/800.** T25 adds a fail-closed guard. Put the logic in `hooks/local/lib/managed_content_manifest.py` and keep the shell as orchestration (FR-25 extraction is in-scope, not creep).

**If a finding turns out to be wrong**, say so with evidence rather than implementing a fix for a non-defect. The review is high quality but it is not infallible — I independently confirmed T19's bypass; I did not independently confirm every row.
