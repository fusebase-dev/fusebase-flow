# Implement handoff — ceremony-efficiency-middle-lane (Phase 1)

## Role bootstrap (read this BEFORE any other reads)
You are operating as the **AI Developer** under FuseBase Flow v3.21.1.
Self-attest per `FLOW_RULES.md` § Self-attestation (FR-01..FR-26), naming AI Developer + the IM.1..IM.18 role-discipline section.
Load-bearing FRs: FR-03 (one task = one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-10 (reproduce before fix), FR-13 (lint+typecheck per commit), FR-22 (comment policy), FR-23 (doc budget), FR-25 (module-size), FR-26 (token-efficient execution).
Refusal phrasing: "I can't do that under FR-XX (<rule>). Here's the compliant path: <alternative>."

## Mandatory pre-execution reads (in order)
1. `FLOW_RULES.md` — FR-01..FR-26 (stop at `## Amendment log`)
2. `AGENTS.md` (project-specific section; worker-undisturbed paths)
3. `docs/specs/ceremony-efficiency-middle-lane/spec.md` — LOCKED spec (decisions D1..D7 inline; ACs)
4. `docs/specs/ceremony-efficiency-middle-lane/tasks.md` — T18..T23 (Phase 1)
5. `docs/specs/ceremony-efficiency-middle-lane/verification-gate.md` — gate you must satisfy
6. `flow-skills/token-economy/SKILL.md` + `hooks/local/token-waste-audit.py` — the substrate/discipline you REUSE (do not reinvent)
7. `flow-skills/role-discipline/references/ai-developer.md` — IM.1..IM.18 don't-list
8. `policies/protected-paths.yml` — worker-undisturbed

## Ticket header
| Field | Value |
|---|---|
| Slug | `ceremony-efficiency-middle-lane` |
| Status | ready for AI Developer (Phase 1 only) |
| Source spec | `docs/specs/ceremony-efficiency-middle-lane/spec.md` (LOCKED) |
| Decisions locked | D1..D7 (Phase 1 cites **D5, D7**) |
| Task range (this handoff) | **T18..T22** (STOP at gate T22) |
| Decision letter prefix | `D` |
| T-counter going in | T17; first task T18 |
| Last shipped slice | delegation-residuals (deploy `af1d5af`, v3.21.1) |

## Scope of THIS handoff = Phase 1 only (solves PR-2 + PR-3)
- **T18** A3 `prevents:` annotation scheme + scoped annotations (D5).
- **T19** `flow-skills/find-wasted-effort/SKILL.md` (read-only, 6 rules — rule 4 CUT, rule 7 cross-session-scoped) (D7).
- **T20** `hooks/local/find-wasted-effort.py` (read-only analyzer; report → `state/audit/`; NO writes/prune) (D7).
- **T21** command + provider mirrors + skill-count (31st) + CHANGELOG/release-notes + plugin manifest (D7).
- **T22** verification gate → produce gate report → **HALT.**
**Out of scope here:** Phase 2 (audit writes) and Phase 3 (Middle Lane / `middle_deploy` / FR-21 three-tier) — do NOT touch deploy policies or FR-21 rule rows.

## Pre-cached identifiers
| Identifier | Value | Why |
|---|---|---|
| Reuse substrate | `hooks/local/token-waste-audit.py`, `flow-skills/token-economy/` | A2 mirrors its structure + FP-header + `state/audit/` convention |
| Report output dir | `state/audit/` (gitignored) | read-only audit report lands here |
| Annotation taxonomy home | `policies/ratchet-governance.yml` (new) | A3 taxonomy + coverage map |
| Skill count | 30 → **31** (find-wasted-effort is the 31st canonical) | verify against `flow-skills/` count before sweeping adapters |

## Production state going in
v3.21.1, FR-01..FR-26, 30 canonical skills, `main` @ `896572d` (this spec finalized). `/token-waste-audit` shipped (v3.20.0). No `find-wasted-effort` / `prevents:` / `middle_deploy` anywhere (greps clean).

## Frontend / UI brief
N/A (framework/CLI artifacts only).

## Worker-undisturbed posture
| Posture | Paths |
|---|---|
| Zero diff | `FLOW_RULES.md` FR rule rows (Phase 1 adds NO rule); `policies/approval-policy.yml`, `required-artifacts.yml`, `command-policy.yml` (deploy authority = Phase 3); existing `flow-skills/*` except new `find-wasted-effort/` |
| Bounded-additive | `templates/`, `workflows/` (annotation comments, T18); adapter docs (skill-count, T21); `.claude/skills/` + `.agents/skills/` (mirror new skill) |

## Module-size (FR-25)
`hooks/local/find-wasted-effort.py` (T20): keep < 800-line ceiling. If it approaches, extract per-rule evaluators into `hooks/local/find_wasted_effort/` along the per-rule seam (in-scope, not creep). Size precedent: `token-waste-audit.py` ~270 lines.

## Stop at gate
Per FR-05, stop at **T22**. Do NOT run deploy (T23). Produce the gate report (`templates/gate-report.md`; fields per `policies/gate-contracts.yml: gate_report`), paste to operator, then **halt**.

## Per-output state announcement (every reply)
```
📍 Phase: Implement
🎯 Ticket: ceremony-efficiency-middle-lane (Phase 1)
✅ Completed: T18..T<n-1> (<SHAs>)
📍 Current: T<n>
⏭️ Next: <next task OR "stopping at gate T22; reporting">
```

## Per-commit pre-attestation
```
T<n> pre-commit check:
☐ Lint/preflight clean   ☐ Worker-undisturbed unchanged   ☐ One task scope
☐ No TODO/FIXME/WIP   ☐ Comments tripwire+pointer only (FR-22)
☐ Module size OK (FR-25)   ☐ Analyzer read-only (no writes/prune)   ☐ Commit cites T<n>
```

## Notes / context (PO-authored)
- **Why A2 is not redundant with `/token-waste-audit`:** different axis — token-waste-audit = tokens-per-rule (transcripts); find-wasted-effort = process-per-outcome ceremony (Flow artifacts on disk). REUSE its discipline + output convention; do NOT duplicate its detection.
- **Rule 4 is CUT** (already shipped in token-waste-audit's v3.21.0 cross-session aggregate) — point at that output, don't re-implement. **Rule 7** scoped to the cross-session ceremony layer only (avoid duplicating FR-26's execution-layer polling signature).
- **Read-only is load-bearing for Phase 1** (D4): NO memory writes, NO overlay edits, NO prune/remove recommendations — those are Phase 2 (T24), gated on per-rule FP fixtures.
- Naming is fixed (`/find-wasted-effort`, not `/ceremony-audit`) — repo memory `find-wasted-effort-command-name`; keep jargon in the description, not the command name.
- Deploy (T23) is the framework release pattern (VERSION bump + commit + push + tag + GitHub release), per `workflows/greenlight-deploy.md` — operator drafts the deploy handoff after the gate.
