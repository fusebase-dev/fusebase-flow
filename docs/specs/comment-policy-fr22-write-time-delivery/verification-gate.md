# Verification gate — FR-22 write-time delivery

**Linked spec:** `docs/specs/comment-policy-fr22-write-time-delivery/spec.md`
**Linked tasks:** `docs/specs/comment-policy-fr22-write-time-delivery/tasks.md`
**Gate task:** T7
**Pass threshold:** V1–V6 all PASS (V7 PASS if operator elects the behavioral check). This gate adopts the downstream field report's pre-agreed V1–V7 validation contract verbatim, mapped to ACs.

## Acceptance-criterion → task mapping

| AC | Implemented in | Verification (V-row) |
|---|---|---|
| AC1 write-time delivery | T1 (+T6 optional) | V1 |
| AC2 false claim corrected | T3 | V2 |
| AC3 mirror reached load surface | T5 | V3 |
| AC4 audit prompt reachable + re-pointed | T2, T4 | V4 |
| AC5 no forbidden enforcement | (negative — all tasks) | V5 |
| AC6 no regression | T5, T8 | V6 |
| AC7 behavioral proof | T1 path | V7 (ran 2026-06-06 → NEGATIVE for delegation path → drove W4) |
| AC8 sub-agent push (A/B) | T7 | V8 |

## Validation contract (V1–V7 — the "did it actually work" checks)

| # | Gap being closed | Pass criterion | How to test |
|---|---|---|---|
| **V1** | No write-time carrier (root cause) | FR-22's rule body reaches a fresh code-writing agent's context via an auto-load path — not "go read FLOW_RULES.md". | (a) Primary: confirm `flow-skills/comment-policy/SKILL.md` exists with code-writing-trigger frontmatter and carries the tripwire/pointer/remove-list/density-override body; confirm it is description-matchable. (b) Secondary (T6 included): run `python hooks/handlers/session_start.py` on a fresh event and grep `context_summary` for the FR-22 reminder line. Both must pass. |
| **V2** | False "already loaded" claim | `role-discipline/SKILL.md` no longer claims the rules are loaded at bootstrap; carries the AI-Dev load directive. | Diff `flow-skills/role-discipline/SKILL.md:50` before/after; grep that "already loaded as part of session bootstrap" is gone and the comment-policy load directive is present in the AI-Developer section. |
| **V3** | Mirror reached the load surface | Carrier skill + `references/audit-prompt.md` exist in canonical `flow-skills/` and are byte-identical in `.claude/skills/` + `.agents/skills/` (the two skill-mirror surfaces). | `diff -r flow-skills/comment-policy .claude/skills/comment-policy` (and `.agents/skills/`) → no differences; canonical-count = 25 everywhere. |
| **V4** | Audit prompt unreachable in consumers | The prompt ships with the delivered skill; FR-22 + `comment-policy.yml` point to the reachable path, not undelivered `docs/comment-policy.md`. | Confirm `flow-skills/comment-policy/references/audit-prompt.md` present; grep `FLOW_RULES.md:68` + `policies/comment-policy.yml` reference the skill path. |
| **V5** | Forbidden enforcement | No regex/lint/gate comment-matcher added. | Inspect `git diff` on `hooks/**` + `policies/**` for any comment regex/lint matcher → none. Enforcement remains write-time rule + `code-review`. |
| **V6** | Regression | preflight 0/0; tests green; health HEALTHY; FR-01..FR-21 byte-unchanged; VERSION bumped; mirror counts consistent. | `bash hooks/local/preflight.sh`; `run-tests`; `bash hooks/local/fusebase-flow-health-check.sh`; `git diff` review of FLOW_RULES.md (only FR-22 pointer line changed). |
| **V7** | Behavioral proof — pull path | A fresh sub-agent, not primed about FR-22, writes tripwire+pointer-only comments on a throwaway code task. | **RAN 2026-06-06 → NEGATIVE.** Unprimed `general-purpose` sub-agent wrote `C:\tmp\v7-comment-test\utils.ts` with ~49 comment lines (~90% removable per FR-22) — default JSDoc-heavy, indistinguishable from un-Flowed output; one genuine tripwire (clock guard) = engineering instinct, not skill evidence. CLAUDE.md context was present (agent emitted a Flow state-footer) yet the `comment-policy` skill did not load/apply. Conclusion: **pull (auto-load) does not reach a delegated sub-agent** → drove W4. |
| **V8** | Behavioral proof — push path (A/B) | Same code task, but the Delegation push block is **inlined** into the sub-agent's prompt → output is tripwire+pointer-lean. | Re-run the V7 task on a fresh sub-agent **with** the push block prepended; compare comment density to V7. PASS = clear A/B delta (push lean vs pull heavy). Run by PO at T8 for independence. |

## Required gate-report fields (per `policies/gate-contracts.yml`)

| Field | Format |
|---|---|
| Implementation summary | 1–3 sentences |
| Per-task SHAs | `T<n>: <sha> <subject>` for T1..T6 (+T8 release SHA) |
| Test counts | `before / after / delta` (preflight checks; run-tests) |
| Lint status | `clean` / `<n> warnings` |
| Worker-undisturbed git diff | engine scripts: `empty diff ✓`; `FLOW_RULES.md` FR-01..FR-21 rows: `empty diff ✓` |
| Mirror parity | `flow-skills/comment-policy` == `.claude/skills/comment-policy` (+ `.agents/skills/`) ✓; canonical count 24→25 ✓ |
| Self-attestation | "Operating as AI Developer..." phrase; attestation range FR-01..FR-22 intact |

## Lint / typecheck / test commands

| Layer | Command |
|---|---|
| Preflight (structure) | `bash hooks/local/preflight.sh` |
| Tests | `run-tests` (per `AGENTS.md` project-specific section) |
| Health | `bash hooks/local/fusebase-flow-health-check.sh` |
| Skill frontmatter | validated by preflight + `skill-authoring` contract |

## Worker-undisturbed paths (this ticket)

- Engine scripts synced by `fusebase update` (the 3 engine scripts + VERSION sync logic) — empty diff (VERSION value changes at T8; the sync logic does not).
- `FLOW_RULES.md` FR-01..FR-21 rows + implications — empty diff. **Only** FR-22's audit-prompt pointer phrase (`:68`) is edited (T4).
- `flow-skills/role-discipline/SKILL.md` — bounded-additive: only the `:50` reference row is corrected and the AI-Developer section gains one directive line; refusal phrasing + other role sections empty diff.
- `hooks/handlers/session_start.py` — empty diff unless T6 elected; if elected, only one `summary_lines.append(...)` line added, no logic/regex change.

## Probes (post-release — framework has no runtime surface)

| ID | Probe | Pass criterion | Evidence |
|---|---|---|---|
| G-M | `preflight.sh` post-edit | exit 0; 0 missing / 0 drift | transcript |
| G-N | `fusebase-flow-health-check` | `HEALTHY` | transcript |
| G-O | mirror parity | `diff -r` canonical vs `.claude/skills/` + `.agents/skills/` for comment-policy → identical | diff output |
| G-P | FR-01..FR-21 intact | `git diff FLOW_RULES.md` shows only FR-22 pointer line | diff excerpt |
| G-Q | spec flip + ledger | spec DRAFT→DONE + `docs/changes/` entry in single release commit | `git log` |

## Version bump

Old: `3.10.0` · New: `3.11.0` (operator-confirmable) · Reason: adds a canonical skill (24→25) + completes FR-22 delivery. Treat as 3.10.1 only if operator classifies it a pure fix.

## Rollback procedure

If any probe fails:
1. `git revert <release hash>`.
2. Re-run `preflight.sh` + health → confirm restored to 3.10.0 state.
3. File a follow-up backlog ticket; spec stays DRAFT until resolved.

## Cross-artifact consistency check (mandatory before approving release)

```
☐ Worker-undisturbed — engine scripts + FR-01..FR-21 rows: empty diff
☐ Mixed-fleet — additive skill; older-mirror consumers unaffected until re-mirror
☐ Migration — none (skill add + text edits + mirror)
☐ No forbidden enforcement — no comment regex/lint gate added (AC5/V5)
☐ Quality bar — preflight 0/0, tests green, health HEALTHY

Cross-artifact:
☐ Every AC1..AC7 exercised in ≥1 task
☐ Every locked decision W1/W2/W3 cited in ≥1 task
☐ Mirror count 24→25 reflected in CLAUDE.md / AGENTS.md / docs
☐ All T-task SHAs filled
☐ No TODO/FIXME/WIP in diff
☐ Spec status still DRAFT (flips to DONE at T8)
```

If ANY item fails, redirect AI Developer. Do NOT bypass.
