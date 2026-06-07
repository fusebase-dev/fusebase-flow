# Implement handoff — comment-policy-fr22-write-time-delivery

> **Mode B.** PO-authored. Point an AI Developer session at this file. Self-bootstrapping in a fresh chat.

## Role bootstrap (read this BEFORE any other reads)

You are operating as the **AI Developer** under Fusebase Flow v3.10.0 (this ticket bumps it to 3.11.0 at the release task).

**Self-attest** per `FLOW_RULES.md` § Self-attestation (FR-01..FR-22), naming AI Developer as the role and the IM.1..IM.18 role-discipline section.

**Hard invariants** load-bearing here: FR-03 (one task = one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-09 (Mode B for files), FR-13 (lint/typecheck per commit), FR-18 (supersede, don't accumulate), and — **acutely, this is the rule the ticket is about — FR-22**: every comment you write in this ticket must itself be tripwire + pointer only. **Dogfood it.** A handoff that fixes FR-22 delivery while shipping over-commented files would be self-refuting.

**Refusal phrasing:** "I can't do that under FR-XX (<rule name>). Here's the path that complies: <alternative>."

---

## Mandatory pre-execution reads (in order)

1. `FLOW_RULES.md` — FR-01..FR-22 (especially FR-22 at `:31` + `:68`)
2. `AGENTS.md` — project-specific section + worker-undisturbed paths
3. `docs/specs/comment-policy-fr22-write-time-delivery/spec.md` — locked spec
4. `docs/specs/comment-policy-fr22-write-time-delivery/decisions.md` — W1/W2/W3 all LOCKED
5. `docs/specs/comment-policy-fr22-write-time-delivery/tasks.md` — T1..T8
6. `docs/specs/comment-policy-fr22-write-time-delivery/verification-gate.md` — V1..V7 gate
7. `flow-skills/skill-authoring/SKILL.md` — clean-room + frontmatter contract (needed for T1/T2)
8. `flow-skills/role-discipline/SKILL.md` — IM.1..IM.18 + the `:50` row you will correct (T3)
9. `docs/comment-policy.md` — source of the audit prompt you bundle (T2, lines 45-77)

---

## Ticket header

| Field | Value |
|---|---|
| **Slug** | `comment-policy-fr22-write-time-delivery` |
| **Status** | ready for AI Developer |
| **Source spec** | `docs/specs/comment-policy-fr22-write-time-delivery/spec.md` |
| **Decisions locked** | W1, W2, W3 (Pavel, 2026-06-06) |
| **Task range (this handoff)** | `T1..T6` + interim gate. **[Superseded note — W4 added 2026-06-06 after the V7 probe]:** the chain was renumbered (new T7 = sub-agent push, T8 = final gate, T9 = release). This handoff executed T1–T6 + the interim gate; for T7 onward see `tasks.md` and the deploy handoff. |
| **Decision letter prefix** | `W` |
| **T-counter going in** | ticket-local `T0`; first task is `T1`. (Global counter is fuzzy post-v3.10.0; these are ticket-local. Renumber to the global counter only if your local convention requires it.) |
| **Parent ticket** | `comment-policy-fr22` (FR-22 shipped v3.10.0) |
| **Lane** | Full |

---

## Pre-cached identifiers (verify with one read; do not re-derive)

| Identifier | Value | Note |
|---|---|---|
| Live canonical-count sites (bump 24→25) | `CLAUDE.md:110` `(24 canonical Fusebase Flow skills total.)` · `AGENTS.md:175` `(24 canonical skills total)` | **ONLY these two are live.** Do NOT edit `docs/release-notes/v3.*.md` — they are point-in-time records; rewriting them is the changelog anti-pattern FR-22 itself bans. |
| On-demand skill enumerations to extend | `CLAUDE.md` on-demand list (the `code-review`…`lightweight-lane` bullets) + `AGENTS.md:175` inline list | Add `comment-policy` as a **description-matched** entry. Do NOT add it to the mandatory always-loaded set (communication + role-discipline stay the only two). |
| Consumer-facing audit-prompt pointers (re-point, T4) | `FLOW_RULES.md:68` "run the audit prompt in `docs/comment-policy.md`" · `policies/comment-policy.yml:19` "run the independent-audit prompt in `docs/comment-policy.md`" | Re-point to `flow-skills/comment-policy/references/audit-prompt.md`; keep `docs/comment-policy.md` named as the rationale home. |
| Secondary `docs/comment-policy.md` mentions (leave as rationale refs) | `FLOW_RULES.md:31`, `FLOW_RULES.md:218` (amendment log — historical), `policies/comment-policy.yml:11` | Optional light touch only; not consumer-blocking. `:218` is historical amendment-log — leave it. |
| Mirror script | `hooks/local/mirror-skills.sh` | Canonical → `.claude/` `.agents/` `.codex/` |
| Gate scripts | `hooks/local/preflight.sh` · `hooks/local/fusebase-flow-health-check.sh` · `run-tests` (per AGENTS.md) | V6 |
| Audit-prompt source block | `docs/comment-policy.md:45-77` (the fenced `INDEPENDENT AUDIT` block) | Already generalized — copy verbatim into the skill reference (T2). |

No secrets, DB, or runtime IDs — framework repo, no API surface.

---

## Production state going in

`VERSION` = `3.10.0`. No runtime/deploy surface. 24 canonical skills. FR-22 present but write-time-undelivered (the gap this ticket closes). Clean working tree on `main`.

---

## Frontend / UI implementation brief

N/A — no user/operator-facing UI. Surfaces are skill files, a rule pointer, a config pointer, a hook line, and mirrors.

---

## Task execution notes (per task)

**T1 — author `flow-skills/comment-policy/SKILL.md`.** Frontmatter `name: comment-policy` + a trigger-oriented `description:` in the house style: *"Use when writing or editing code, adding/changing comments, or before committing a code diff — delivers FR-22's tripwire + retrieval-pointer comment policy at write time. Do NOT use for prose/doc edits, non-code tickets, or as a review gate (that's `code-review`)."* Body carries the FR-22 write-time rule aligned with `FLOW_RULES.md:68`: the two comment kinds (tripwire ≤1 line / ≤~4 for security-auth-concurrency-platform; pointer ≤1 line), the remove-list, the **density-override** clause, the **storage≠retrieval** pointer-preservation subtlety, the carve-out pointer to `policies/comment-policy.yml`, and a pointer to `references/audit-prompt.md`. Keep it tight and itself FR-22-compliant (dogfood — no WHAT-restating prose in your own examples' comments).

**T2 — `flow-skills/comment-policy/references/audit-prompt.md`.** Copy `docs/comment-policy.md:45-77` verbatim (it is already generalized — no plugin-specific clauses). This is the consumer-reachable copy; `docs/comment-policy.md` stays as the framework-dev rationale home (do not delete it).

**T3 — correct `flow-skills/role-discipline/SKILL.md:50`.** Replace `"already loaded as part of session bootstrap"` with an accurate statement (existence-checked at bootstrap; not injected — read on demand). Add to the **AI Developer** section one directive line: *before writing code, load `flow-skills/comment-policy` (FR-22 is not auto-injected).* FR-07/FR-18: every other row + role section + refusal phrasing must be byte-unchanged (supersede only the false row; do not accumulate a "NOTE: was previously…" line).

**T4 — re-point (see pre-cache table).** `FLOW_RULES.md:68` + `comment-policy.yml:19` → `flow-skills/comment-policy/references/audit-prompt.md`. **FR-22 semantics unchanged** — you are editing a path string, not the rule. FR-01..FR-21 rows: zero diff.

**T5 — mirror + counts.** Run `mirror-skills.sh`; verify `diff -r flow-skills/comment-policy .claude/skills/comment-policy` (and `.agents/`, `.codex/`) is clean. Bump the two live counts to 25; add `comment-policy` to both on-demand enumerations. Run version-string sync if the repo has it.

**T6 — `session_start.py` secondary reminder (INCLUDED).** Append exactly one `summary_lines.append(...)` line to `context_summary` (e.g. "FR-22 code-comment policy in force when writing code — load flow-skills/comment-policy"). No logic, no regex, no gate (V5). Mirror the hook if hooks are mirrored. This is a belt for hook-on full sessions; it is NOT the primary carrier (T1 is) and does not reach sub-agents.

**T7 — gate.** Produce the Mode B gate report per `verification-gate.md` (V1–V6 mandatory; V7 if you want the behavioral proof). Then **halt** — do not run T8. PO reviews and drafts the release handoff.

---

## Worker-undisturbed posture

| Posture | Paths |
|---|---|
| Zero diff expected | engine scripts synced by `fusebase update`; `FLOW_RULES.md` FR-01..FR-21 rows + implications; `docs/release-notes/**` (historical); `flow-skills/role-discipline/SKILL.md` outside the `:50` row + the one added AI-Dev directive line; other role sections + refusal phrasing |
| Bounded-additive expected | `flow-skills/comment-policy/**` (new dir); `.claude/skills/comment-policy/**` + `.agents/**` + `.codex/**` (mirrors); `CLAUDE.md`/`AGENTS.md` (count + one enum entry); `FLOW_RULES.md:68` + `comment-policy.yml` (pointer phrase only); `session_start.py` (one appended line) |

---

## Stop at gate

Per FR-05, stop at **T7**. Do NOT run the release task (T8) or bump VERSION. Report the gate, then wait for the release handoff.

---

## Per-output state announcement (every chat reply)

```
---
📍 Phase: Implement
🎯 Ticket: comment-policy-fr22-write-time-delivery
✅ Completed: T1..T<n-1> (<SHAs>)
📍 Current: T<n> (<task name>)
⏭️ Next: <next task OR "stopping at gate T7; reporting">
```

## Per-commit pre-attestation

```
T<n> pre-commit check:
☐ Lint/preflight clean
☐ Worker-undisturbed unchanged (engine scripts + FR-01..FR-21 + release-notes)
☐ One task scope (no bundling)
☐ No TODO/FIXME/WIP markers
☐ Comments: tripwire + pointer only (FR-22) — DOGFOOD; density not matched upward; pointers kept
☐ Commit message cites T<n>
→ Committing T<n>: <scope>
```

---

## Gate report contract (at T7)

Mode B report: per-task SHAs (T1..T6), test/preflight counts (before/after/delta), lint/typecheck status, literal worker-undisturbed `git diff` confirmation (engine scripts + FR-01..FR-21 + release-notes = no changes), mirror-parity proof (`diff -r` clean; count 24→25), and the V1–V6 (+V7) results. Paste back to operator, then **halt**.

---

## Notes / context (PO-authored)

- **Why this ticket exists:** field report from `WorkHub Managed` (v3.10.0 consumer) — a post-FR-22 sub-agent diff carried multi-line WHAT-restate/changelog comments because FR-22 never reached the writer's context. Verified in source: `session_start.py` existence-checks but never injects FLOW_RULES.md; no loaded carrier skill; `role-discipline:50` falsely claims the rules are "already loaded"; and the audit prompt lives in `docs/` which `upgrade.sh` does NOT ship to consumers.
- **The one trap:** do not turn any of this into a regex/lint comment gate. FR-22 explicitly forbids it (tripwire-vs-restate is semantic). V5 fails the gate if you add one.
- **Dogfood is the proof:** the strongest signal this ticket worked is that your own diff has near-zero non-tripwire/non-pointer comments. Write the skill and edits the way the skill tells you to.
- **Mixed-fleet:** additive — a consumer on an older mirror is unaffected until it re-mirrors; nothing is removed.
