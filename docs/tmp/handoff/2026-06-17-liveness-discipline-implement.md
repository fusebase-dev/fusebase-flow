# Implement handoff — liveness-discipline (FR-27)

## Role bootstrap
You are the **AI Developer** under FuseBase Flow v3.27.0. Self-attest FR-01..FR-26 + IM.1..IM.18. Load-bearing: FR-03 (one task=one commit), FR-05 (stop at gate), FR-07 (worker-undisturbed), FR-13 (lint/typecheck per commit), FR-22 (comments — block below), FR-25 (module size). **Run synchronously; stop at gate; do NOT bump VERSION, push, or deploy.** (This ticket ADDS FR-27 — you are implementing the rule it describes; apply its spirit to your own work.)

## COMMENT POLICY (FR-22) — applies to all code you write
```
Write ONLY two kinds of comment; remove everything else.
1) TRIPWIRE — a constraint an editor could break unknowingly, not obvious from local code (≤1 line; ≤4 lines only for security/auth/concurrency/platform).
2) RETRIEVAL POINTER — a ≤1-line tag naming the external WHY-home, e.g. "(spec AC3)".
REMOVE: comments restating the code; rationale already in a decision/ticket/memory; changelog/history (it's in git).
Do NOT match surrounding comment density upward. Keep pointers — not duplicates.
```
At done, emit in chat: `comment-policy review: applied (FR-22)`.

## Mandatory reads
1. `FLOW_RULES.md` FR-01..FR-26 (stop at Amendment log) — and how FR-26 was added (the template for appending FR-27).
2. `docs/specs/liveness-discipline/spec.md` — LOCKED. Decisions D1–D7, Tasks T1–T5, ACs consolidated there. Authoritative. **Read the "honest enforcement model" + "qualified tooling claim" carefully — do NOT overstate the guarantee, do NOT add a verification hook or a blocking gate.**
3. The surfaces you edit (read each first): `FLOW_RULES.md` (FR table + amendment log), `hooks/local/lib/run-with-timeout.sh` (REUSE its core; the health-check sources its `ffhc_*` API — do NOT break it), `hooks/local/fusebase-flow-health-check.sh` (confirms the FFHC dependency), `flow-skills/role-discipline/SKILL.md` (§ Write-time discipline digest), `hooks/handlers/session_start.py:87-94`, `templates/handoff-implement.md`, `templates/handoff-deploy.md`, `README.md` (§ Skill catalog + Commands & capabilities), `docs/rail-mapping.md`.
4. `flow-skills/token-economy/SKILL.md` (the FR-26 skill — structural template for a new always-on rule's skill) + `flow-skills/task-delegation/SKILL.md:92-100` (BLOCKED-AT — cross-link) + `flow-skills/smoke-testing/SKILL.md:93-101` (record-then-read — cross-link).
5. `flow-skills/role-discipline/references/ai-developer.md`.

## Scope — T1–T5, one commit each. DEFER D3 (nudge), D4 (Python helper), D5 (template skeleton).

- **T1 (A) — FR-27 rule + skill.** Append the **FR-27** row to the `FLOW_RULES.md` FR table (existing FR-01..FR-26 rows BYTE-UNCHANGED) + an amendment-log entry, following exactly how FR-26 was added. Rule text (tighten to table style): *"Liveness — any long/silent background work (own probe/script/deploy/fetch-loop/browser-automation, sub-agent, or workflow) must be made observable BEFORE launch: bounded by a timeout/watchdog, OR completed in-turn, OR returned as `BLOCKED-AT-<gate>` + a record-then-read pointer. Never launch bare. No blocking gate (semantic — a hang vs a long-live run); enforced by `liveness-discipline` + `bounded-run.sh`."* Create `flow-skills/liveness-discipline/SKILL.md` (mirror the token-economy skill structure): frontmatter (name `liveness-discipline`; description with trigger phrases "background task hangs / agent sits idle / never resumes / silent long-running work"; `source_inspiration: conceptual-only`; `license_status: clean-room-original`; `risk_level: low`; `invocation: automatic`); body = the full protocol (never launch bare → ≥1 liveness guarantee; internal watchdog from the FIRST version; per-call timeouts; flush partial results; incremental progress logging; diagnose-a-hang by ACTIVITY/mtime not 0-byte existence; on-confirmed-hang recover: stop → robust re-run → clean residue → retry transient rate-limits); a compact `source hooks/local/lib/bounded-run.sh` example (D5 lives here); cross-links to task-delegation BLOCKED-AT + smoke-testing record-then-read; the **honest scope** note (bounds the monitored process; don't `&`-detach under the wrapper; deadline inside long scripts too); clean-room note.
- **T2 (B) — `hooks/local/lib/bounded-run.sh`.** REUSE run-with-timeout's core **without breaking the `ffhc_*` API** (either `source` run-with-timeout.sh from bounded-run, or extract a shared core both call — verify the health-check still works). ADD: a wall-clock deadline that emits a terminal **timeout line** (so a bounded job reaches completion/death, not a silent idle) + **incremental progress logging** to stderr. Keep it honest (monitored process only). `bash -n` clean; FR-25 <ceiling.
- **T3 (C) — delivery.** (a) ONE pointer row in `flow-skills/role-discipline/SKILL.md` § Write-time discipline digest (after the FR-26 row), scoped "all tool-using execution (every role)". (b) One liveness-reminder clause appended to the `session_start.py` bootstrap string (~:89-94), pointing to the digest/skill. (c) Promote the liveness / `BLOCKED-AT` clause from the parallel-only Tracks section (`handoff-implement.md:105`) and the "delegated sessions" qualifier (`handoff-deploy.md`) UP into the **Role-bootstrap Hard-invariants** so the MAIN session carries it.
- **T4 (E) — docs.** README § Skill catalog (FR-27/liveness-discipline row) + Commands & capabilities (add to the quality/discipline group) + the manual skill-count prose (31→32). `docs/rail-mapping.md`: FR-27 → enforcement = digest delivery + `bounded-run.sh`, explicitly "no gate; no hook verification (a hang is undetectable by construction)."
- **T5 — tests + reconcile + re-mirror.** `hooks/tests/`: AC3 (a) hang→timeout line within deadline (rc 124/137); (b) incremental progress emitted; (c) no-timeout-binary degrades per skip policy (not a false "bounded"); (d) ignored-SIGTERM child killed by `-k` SIGKILL grace; (e) FFHC API intact (health-check timeout tests still pass). AC4: implement-handoff template carries the liveness clause in the **Hard-invariants** (not only Tracks). AC6: existing health-check/run-with-timeout tests still pass. Wire into run-tests.sh. Then `bash hooks/local/mirror-skills.sh` (new 32nd skill → mirror + manifest). **Run `bash hooks/local/preflight.sh`; if it flags FR-range (FR-01..FR-27) or skill-count (32) drift in adapters from adding FR-27/the skill, run `bash hooks/local/sync-version-strings.sh` to reconcile the derived strings — do NOT bump VERSION (that's deploy).** Genuine tests, loud asserts, no false-green.

## FR-07 / hard rules
APPEND FR-27 only — existing FR-01..FR-26 rows BYTE-UNCHANGED; the 3 deploy-policy rule semantics + `ratchet-governance.yml` UNCHANGED. Do NOT break the `ffhc_*` API. Do NOT add a blocking gate or a verification hook (the spec's honest model — a hang is undetectable by construction; attestation theatre is forbidden). Do NOT bump VERSION / push / deploy.

## Per-commit pre-attestation
```
☐ preflight 0/0  ☐ worker-undisturbed unchanged  ☐ one task scope  ☐ no TODO/FIXME/WIP
☐ FR-22 comments in any code  ☐ FR-25 <ceiling  ☐ no blocking gate / no verification-theatre added
☐ existing FR-01..FR-26 rows + 3 deploy-policy semantics + ratchet UNCHANGED  ☐ ffhc_* API intact  ☐ commit cites the task
```

## Gate (stop, report, HALT)
preflight 0/0 · `bash -n hooks/local/lib/bounded-run.sh` · run-tests PASS incl. new tests + the existing health-check/run-with-timeout tests (AC6 no-regression) · check-module-size --all exit 0 · mirror 0 drift (new skill mirrored + manifest) · FR-07 clean (FR-01..FR-26 rows + 3 deploy policies + ratchet unchanged). Emit `comment-policy review: applied (FR-22)`. Produce the gate report; HALT. A Codex impl review runs after the gate.

## Return
Gate report: per-task SHAs (T1–T5), AC3 evidence (the hang→timeout-line proof + the FFHC-intact proof), AC4 (handoff Hard-invariant clause), AC6 (health-check no-regression), gate numbers, FR-07 confirmation (existing rows + policies + ratchet + ffhc_* API unchanged), and the dogfood marker.
