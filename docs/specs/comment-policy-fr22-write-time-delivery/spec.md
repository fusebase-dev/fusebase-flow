# Spec — FR-22 write-time delivery (close the enforcement-plumbing gap)

**Status:** DONE
**Created:** 2026-06-06
**Released:** 2026-06-06 (v3.11.0)
**Deploy hash:** _release commit — see release report / git log (set post-commit)_
**Lane:** Full (touches a mandatory always-loaded skill + an always-on rule's delivery + adds a canonical skill → mirror/count change; multi-surface)
**Linked decisions:** W1..W4
**Target version:** 3.11.0 (operator-confirmable)
**Parent ticket:** `docs/specs/comment-policy-fr22/spec.md` (FR-22 shipped v3.10.0 — DONE)
**Source:** downstream field report, project `WorkHub Managed` (v3.10.0 consumer), 2026-06-06.

## Problem

FR-22 shipped as **instruction** but not as **write-time delivery**. The rule body never reaches a code-*writing* agent's context at the moment it writes comments, so a v3.10.0 consumer's AI Developer sub-agent wrote default "explain-richly" comments — the exact density-ratchet FR-22 was authored to break. The breaker was never loaded.

Verified in this source (grounded, not relayed):

| Finding | Evidence | Status |
|---|---|---|
| FR-22 rule text is present + correct | `FLOW_RULES.md:31` (row) + `:68` (implication) | ✅ correct — not the problem |
| FR-22 is never injected into a fresh agent's context | `hooks/handlers/session_start.py:73-109` — `context_summary` = version banner + repo path + missing-file warnings + project-artifact list; no FR body is ever read or emitted. The hook only existence-checks FLOW_RULES.md (`:67`). | ✅ **core gap** |
| role-discipline falsely says the rules are "already loaded" | `flow-skills/role-discipline/SKILL.md:50` — `"already loaded as part of session bootstrap"`. Untrue: the hook existence-checks, it does not inject. The false claim suppresses the workaround (an agent trusts it, never opens the file). | ✅ gap |
| FR-22 has no loaded write-time carrier | No `flow-skills/comment-policy/` exists. FR-22's only homes are FLOW_RULES.md (not injected) + `code-review` (review-time, on-demand). Every *other* behavioral FR has a loaded skill (FR-08/09→communication, FR-16-20→role-discipline, FR-21→lightweight-lane, FR-20→zoom-out). | ✅ gap |
| The audit prompt that derives carve-outs is unreachable in consumers | `docs/comment-policy.md` exists in source but `upgrade.sh:35-37,114-118` deliberately does NOT copy `docs/` into consumers (U4). Yet FR-22 (`:68`) and `policies/comment-policy.yml:19` both instruct the consumer to "run the audit prompt in `docs/comment-policy.md`" — an unreachable path downstream. | ✅ **second delivery gap** |

This ticket closes the delivery gap. It does **not** change FR-22's semantics (tripwire/pointer definitions are correct and stay).

## Why now

A v3.10.0 consumer (`WorkHub Managed`) demonstrated the gap in production: a post-FR-22 diff (written 2026-06-06, after v3.10.0 shipped 2026-06-04) carried multi-line WHAT-restate / rationale / changelog comment blocks — a genuine FR-22 violation the loop could not see, because the rule was never in the writer's context. The downstream field report's "fix the framework first" request is the trigger.

## In scope

- **Write-time carrier** — a new skill `flow-skills/comment-policy/` that delivers FR-22's tripwire+pointer body into a code-writing agent's context.
- **Bundle the audit prompt** with the delivered skill so consumers can reach it (closes the unreachable-`docs/comment-policy.md` gap).
- **Correct the false "already loaded" claim** at `role-discipline/SKILL.md:50` and add an explicit AI-Developer load directive for the carrier (guaranteed trigger from the always-loaded role skill).
- **Sub-agent push (W4)** — a Delegation push block in `comment-policy` + a mandatory clause in `task-delegation` + a reminder in `handoff-implement`, so delegated code-writing sub-agents receive FR-22 **inline in their prompt** (push), since V7 proved they do not auto-load the skill (pull).
- **Re-point** FR-22 (`FLOW_RULES.md:68`) + `comment-policy.yml:19` from the undelivered `docs/comment-policy.md` to the delivered reference.
- **Mirror + counts** — re-mirror canonical → `.claude/` + `.agents/` (the skill-mirror surfaces; `.codex/` holds agents, not skills); update the "24 canonical skills" count to 25 across CLAUDE.md / AGENTS.md / overlays.
- **Release** — VERSION bump, change-ledger entry, spec DRAFT→DONE.
- A secondary one-line FR-22 reminder in `session_start.py` `context_summary` (T6, **included** per operator 2026-06-06 — belt for hook-on full-session starts; explicitly not relied on for sub-agent reach).

## Out of scope

- Changing FR-22's **semantics** (tripwire/pointer/carve-out definitions stay verbatim).
- Cleaning any existing over-commented files in any consumer (FR-22 is not-retroactive — that's a downstream Lightweight pass; comments strip from build output, no deploy).
- The `WorkHub Managed` project's own diff cleanup (downstream, separate).
- Any **regex/lint/gate** comment-matcher — explicitly forbidden by FR-22 and re-affirmed here as a non-negotiable (AC5).
- `docs/comment-policy.md` keeps existing as the framework-dev rationale home (not deleted — its audience is the framework maintainer).

## Acceptance criteria

1. **AC1 — write-time delivery (V1).** A fresh code-writing agent receives FR-22's tripwire+pointer body in-context via an auto-load path (the carrier skill), without being told "go read FLOW_RULES.md". Pass: the skill exists with code-writing-trigger frontmatter and carries the rule body; loading it surfaces the tripwire / pointer / remove-list / density-override clauses.
2. **AC2 — false claim corrected (V2).** `role-discipline/SKILL.md:50` no longer asserts the rules are "already loaded as part of session bootstrap"; it states they are existence-checked at bootstrap and carries an explicit AI-Developer directive to load `flow-skills/comment-policy` before writing code.
3. **AC3 — mirror reached the load surface (V3).** The carrier skill + its bundled audit-prompt reference exist in canonical `flow-skills/comment-policy/` AND are byte-identical in the auto-loaded provider skill mirrors (`.claude/skills/`, `.agents/skills/` — the two skill-mirror surfaces; `.codex/` is agents-only).
4. **AC4 — audit prompt reachable in consumers (V4 + new finding).** The independent-audit prompt ships *with the delivered skill* (e.g. `flow-skills/comment-policy/references/audit-prompt.md`), and FR-22 + `comment-policy.yml` point to that reachable location instead of the undelivered `docs/comment-policy.md`.
5. **AC5 — no forbidden enforcement (V5).** No regex/lint/gate comment-matcher is added in `hooks/` or `policies/`. Enforcement stays write-time (the rule) + review-time (`code-review`).
6. **AC6 — no regression (V6).** `preflight.sh` 0/0; `run-tests` green; `fusebase-flow-health-check` HEALTHY; FR-01..FR-21 text byte-unchanged; mirror counts consistent; VERSION bumped; self-attestation range still reads FR-01..FR-22.
7. **AC7 — behavioral proof (V7, gold standard).** A fresh sub-agent, not primed about FR-22, given a small code task, writes tripwire+pointer-only comments. Tests the loaded-skill path (the path that failed in WorkHub), not the SessionStart-hook path. **Result 2026-06-06: NEGATIVE for the delegated-sub-agent path** — the unprimed sub-agent over-commented (~90% removable); auto-load (pull) did not reach it. This surfaced the need for **W4 / AC8** (push).
8. **AC8 — sub-agent push (V8, A/B).** When the FR-22 policy is **inlined** into a delegated code-writing sub-agent's prompt (the Delegation push block from `task-delegation`), the sub-agent writes tripwire+pointer-lean comments — where the same task **without** the push (V7) produced JSDoc-heavy output. Pass = a visible A/B delta proving push delivers where pull did not.

## Constitution invariants verified

| Invariant | Status |
|---|---|
| Worker-undisturbed paths (`policies/protected-paths.yml`) | engine scripts + FR-01..FR-21 rows untouched; only FR-22's pointer line edited. Task chain declares empty diff on engine scripts. |
| Mixed-fleet considerations | additive — a consumer on an older mirror is unaffected until it re-mirrors; new skill is opt-in by description-match. No behavior removed. |
| Migration approach | no migration (skill addition + text edits + mirror). |
| Auth model | N/A (no runtime/auth surface). |
| Quality bar (lint/typecheck/tests) | preflight + run-tests + health gate; new skill validated by skill-authoring frontmatter check + preflight. |

## The mechanism (recommended design — see decisions.md W1)

```
code-writing agent (AI Developer or its sub-agent)
        │
        │  (1) description-match on "writing/implementing code, adding comments"
        ▼
flow-skills/comment-policy/SKILL.md ──── carries FR-22 body (tripwire+pointer, density-override, remove-list)
        │                          └───── references/audit-prompt.md  (delivered to consumers → closes W3 gap)
        ▲
        │  (2) explicit in-context load directive (guaranteed trigger, belt-and-suspenders)
flow-skills/role-discipline/SKILL.md (always-loaded)  ── AI-Developer section, replaces the false ":50 already-loaded" row
```

Belt (description-match) + suspenders (always-loaded role directive) closes the sub-agent-reach risk that the SessionStart hook cannot (hooks are opt-in and do not fire for Task sub-agents — the exact WorkHub failure mode).

## Risks

- **R1 — description-match may miss a code-writing sub-agent.** Mitigated by the always-loaded role-discipline directive (W2) + `handoff-implement` reminder + the V7 behavioral test as the empirical check.
- **R2 — +1 skill enlarges the matcher surface / canonical count.** Low: description is narrow (code-writing only); count update is mechanical (grep sweep task T5).
- **R3 — scattered "24 canonical" references.** Mitigated by a repo-wide grep sweep in T5; preflight/health catch a missed mirror.
- **R4 — new skill must pass clean-room + frontmatter.** Authored via `skill-authoring`; validated by preflight + health.

## Clarify summary

Three design questions raised as decisions W1–W3 (delivery mechanism / role-discipline fix / audit-prompt reachability). **All LOCKED by Pavel 2026-06-06** as recommended; operator additionally elected to include the secondary `session_start.py` reminder (T6). No spec-level ambiguities remain.

## Related

- `docs/specs/comment-policy-fr22-write-time-delivery/decisions.md`
- `docs/specs/comment-policy-fr22-write-time-delivery/tasks.md`
- `docs/specs/comment-policy-fr22-write-time-delivery/verification-gate.md`
- Parent: `docs/specs/comment-policy-fr22/spec.md`
- `FLOW_RULES.md:68` · `policies/comment-policy.yml` · `docs/comment-policy.md` · `hooks/handlers/session_start.py` · `flow-skills/role-discipline/SKILL.md:50` · `hooks/local/upgrade.sh:114-118`
