# Spec — write-time-discipline-delivery (FR-24)

**Status:** DONE — shipped v3.15.0 (FR-24 write-time discipline delivery; release notes `docs/release-notes/v3.15.0.md`). Status reconciled 2026-06-14 (was LOCKED 2026-06-08; deploy never flipped it).
**Lands in:** framework v3.15.0
**Tier:** 4 (cross-cutting: new always-on rule + role-discipline + handoff + hook + multi-surface) per FR-23
**Lane:** Full

## Problem

The rules that govern *what an agent writes into artifacts* — FR-09 (Mode B), FR-18 (supersede), FR-22 (comments), FR-23 (documentation budget) — only reduce context cost if they are **in the writing agent's context at write time**. Today their delivery is unreliable:

- FR-22 / FR-23 carriers are **description-matched** skills (on-demand) → an operator-launched AI-Developer chat grinding a fix chain never trips the match, so the rule never enters context. (Reported by consumer **WorkHub Managed**: `repository.ts` accreted ~1,255 comment lines *after* the v3.14.2 upgrade.)
- They are deliberately **not gates** (tripwire-vs-restate is semantic, not regex-able) — correct, but it leaves no firing trigger in the loop.
- Per-skill `mandatory_load` was already evaluated + **rejected** (decisions: `comment-policy-fr22-write-time-delivery`, Option D) — a 3rd always-on skill taxes every session including non-writing roles, self-contradictory for context-economy rules.

This is a **class** problem (FR-22 is one symptom; FR-23 — the documentation rule — has the same hole), so it needs one systemic delivery mechanism, not per-rule patches.

## Decision (operator-locked)

Add **FR-24 (write-time discipline delivery)** + a single always-on, **role-scoped Write-time discipline digest** that delivers the whole class in-context to writing roles only.

- Digest = a **pointer index** (one line + skill pointer per rule), NOT a duplicate of the bodies (honors FR-23).
- Home: `role-discipline` (already `mandatory_load`, role-scoped) → writing-role sections. Non-writing sessions don't carry depth.
- Reinforced where the always-on mechanism can't reach: `templates/handoff-implement.md` (sub-agent path) + `hooks/handlers/session_start.py` reminder.
- Members: FR-09, FR-18, FR-22, FR-23. New write-time rules register one line.
- **Audience principle codified:** dev artifacts (comments, specs, decisions, tasks, handoffs, business-logic *index*) are AI-consumed → optimize for AI only. Human-facing surface (README, CONTRIBUTING/SECURITY/LICENSE/PUBLISHING, AGENTS/CLAUDE/GEMINI onboarding, translated READMEs, opt-in `business-logic.md` narrative) stays human-readable — out of scope.

`comment-policy` stays description-matched (full body + audit prompt + delegation push-block); `mandatory_load` NOT used (rejected as above).

## Acceptance criteria

- AC1: `FLOW_RULES.md` has FR-24 row + implication; title/status/amendment updated.
- AC2: `role-discipline` has an always-on `## Write-time discipline digest (FR-24)` section (pointer index: FR-09/18/22/23 + sources + audience boundary + sub-agent note).
- AC3: role-discipline writing-role sections point to the digest; the stale FR-22 pull-directive (`:161`) and the `:50` row are replaced with the digest reference.
- AC4: `handoff-implement` hard-invariant broadened from FR-22-only to the digest (FR-09/18/22/23); delegation push-block references the digest.
- AC5: `session_start.py` reminder broadened from FR-22-only to the write-time set (FR-24).
- AC6: FR range bumped repo-wide via `sync-version-strings.sh` (FR-01..FR-24); version v3.15.0.
- AC7: preflight 0/0; run-tests **16/16**; mirrors regenerated; no FR-23 duplication introduced (digest is pointers, not bodies).

## Non-goals

- No new skill (digest lives in existing role-discipline). No `mandatory_load` change. No regex/lint comment gate. Not retroactive (existing files cleaned via Lightweight passes downstream).

## Rollback

`git revert <SHA>` — single commit; markdown/py text only; no schema/data/policy-gate change. Tag `v3.15.0`.
