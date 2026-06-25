# Spec — liveness-discipline (FR-27)

**Status:** DONE — shipped v3.28.0, deploy hash `8cacb80` (2026-06-17). Tag `v3.28.0`. Release: https://github.com/fusebase-dev/fusebase-flow/releases/tag/v3.28.0
**Deploy verification:** preflight 0/0 · run-tests 132/132 PASS · check-module-size --all 0 · mirror 0 drift (32 skills + agents) · plugin == VERSION == 3.28.0 · GEMINI.md = v3.28.0 · README badge 3.28.0 · adapters FR-01..FR-27 · FR-07 clean (FR-01..FR-26 rows + approval-policy + protected-paths + command-policy + ratchet-governance unchanged; FR-27 is an append; run-with-timeout.sh byte-unchanged, ffhc_* intact) · clean-room 0. Feature smoke (AC3): `bounded_run 2 sleep 30` → `bounded-run: TIMEOUT after 2s (rc 124)` + heartbeat; health-check timeout suite 26/26 PASS (no regression). Smoke evidence: `docs/tmp/handoff/2026-06-17-liveness-discipline-smoke/S1-bounded-run.md`.
**Created:** 2026-06-17
**Baseline:** FuseBase Flow v3.27.0
**Source:** Operator report — a project's AI developer launched a background re-verify probe that HUNG (no internal timeout; a fetch/cleanup stalled against a cold-start proxy). A hung process emits no completion event, so the agent was never re-invoked and sat idle until the operator nudged it ("is it all done?"). Operator wants the anti-hang protocol **hardwired and mandatory** in FuseBase Flow.
**Lane:** Full (new always-on FR rule + skill + structural tooling + delivery surfaces).
**Design review:** Codex 2026-06-17 → **RESCOPE** (core thesis validated: no hook can verify this hang class → structural tooling + present-by-construction delivery, no blocking gate; FR-27 + skill is the right shape; append-only FR-07 feasible — FR-26 was added the same way). Folded: **(HIGH)** DEFER the warn-only `pre_tool_use` nudge — `pre_tool_use._output_decision()` maps a non-allow/non-deny decision to Claude `ask` (interactive/blocking-ish), so a naive "warn" would block, not nudge; **(MED)** NARROW the "guarantee" — a bounded *monitored* wrapper prevents a silent unbounded wait, but does NOT kill detached grandchildren (`&`/`Start-Process`) or uninterruptible OS waits, and cannot *prove* the host re-invokes (it ensures the process reaches completion/death so a host that surfaces background completion has an event to deliver); **(MED)** PRESERVE the `ffhc_*` API — `fusebase-flow-health-check.sh` sources `run-with-timeout.sh` and calls `ffhc_*` directly, so ship a NEW helper reusing the core, do NOT rename in place; **(LOW)** AC1: FR-range auto-sweeps but some README skill-count prose is manual. Decisions D1–D7 locked below.

## Problem (grounded)
A long/silent foreground command (probe, test script, deploy, fetch loop, browser automation), a sub-agent, or a workflow that the harness AUTO-BACKGROUNDS will, if it HANGS, emit **no completion event** — so the agent is **never re-invoked** and idles indefinitely while appearing "done." The human is forced to ask "is it still running?" just to wake it.

The framework already names this failure — but only for one slice, and with no canonical home or delivery:
- `flow-skills/task-delegation/SKILL.md:92-100` carries the proven primitive (turn-completion: *"NEVER end the turn with 'running in background — I'll resume when it completes' — you won't"*; Blocked-return: unbounded wait → `BLOCKED-AT-<gate>` + pointer) — **but scoped to DELEGATED sub-agents only** (scope gate `:30-44`). The agent's OWN backgrounded probe/script/deploy/fetch-loop/browser-automation is uncovered.
- `flow-skills/smoke-testing/SKILL.md:93-101` (record-then-read + the observability-gap finding `:98`) is the right *remedy* but a different axis (watch-cost, not liveness).
- `hooks/local/lib/run-with-timeout.sh:9-12` already bounds the health-check's own slow ops so they "can't appear to hang" — **the exact anti-hang pattern, shipped, but applied only to the health-check engine.**
- Evidence of the gap: the protocol has been hand-retyped verbatim into 3 deploy handoffs + the `subagent-deploy-run-synchronously` memory, with **no canonical rule**. Ad-hoc = it gets skipped exactly where it matters (long, autonomous, multi-step runs).

## The honest enforcement model (load-bearing — read first)
**No hook can reliably VERIFY this protocol.** The hang→no-event→idle failure is invisible by construction: there is no elapsed-time/idle event in the hook schema; `post_tool_use` cannot fire for a call that never returns; `stop.py` only inspects self-authored claim phrases and auto-allows claim-less turns (`stop.py:149-152`); `pre_tool_use` drops the background flag and is Task-tool-blind. A Stop-time "watchdog: applied" signal would be **attestation theatre** — present-or-absent independent of real behavior — i.e. the inert-lever anti-pattern this session already learned (memory `enforcement-confirm-the-hook-actually-fires`).

Therefore enforcement = **(1) structural safe-by-default tooling** (a bounded/watchdog wrapper so a *sanctioned, monitored* background launch reaches completion-or-death instead of waiting silently forever) **+ (2) present-by-construction delivery** (the rule is in context at the moment work would be launched). The warn-only `pre_tool_use` nudge is **DEFERRED** (the host maps a non-allow/non-deny decision to an interactive `ask`, so it would block, not nudge — see D3).

**Qualified tooling claim (D7 — do not overstate):** the bounded wrapper prevents a *silent unbounded wait* for the **monitored** process — it does NOT guarantee killing a detached grandchild (`cmd &` / `Start-Process`) or an uninterruptible OS wait, and it does NOT *prove* the host re-invokes the agent. It ensures the process reaches completion/death so a host that surfaces background completion has an event to deliver, and so a 0-byte silent idle becomes a timeout line. The skill must teach: don't detach (`&`) under the wrapper; put a deadline INSIDE long scripts too (event-loop-blocked `setTimeout` won't fire); always flush partial results.

## What works — DO NOT regress / reuse not duplicate
- task-delegation turn-completion / `BLOCKED-AT` (the primitive to GENERALIZE, keep cross-linked for the sub-agent slice).
- smoke-testing record-then-read (the prescribed remedy) + observability-gap finding (the escape valve when no durable surface exists).
- `run-with-timeout.sh` bounded-execution core (timeout/gtimeout detection, `-k` kill-grace, rc-124/137 classification) — REUSE, don't re-derive.
- FR-26's **no-blocking-gate** posture: the failure is semantic (a real hang vs a legitimate long-but-live run); a gate would train premature kills (intelligence damage). Same here — no gate.

## In scope
### A — FR-27 rule + `liveness-discipline` skill (canonical body)
- Append **FR-27** to the `FLOW_RULES.md` FR table (new row only — existing FR-01..FR-26 rows UNCHANGED, FR-07): *"Any long/silent background work (the agent's own probe/script/deploy/fetch-loop/browser-automation, a sub-agent, or a workflow) must be made observable BEFORE launch — bounded by a timeout/watchdog, or completed in-turn, or returning `BLOCKED-AT-<gate>` + a record-then-read pointer. A task that cannot signal its own completion-or-death must never be launched bare. Quality/safety floor unchanged."*
- New canonical skill `flow-skills/liveness-discipline/SKILL.md` carrying the full protocol (operator's standing-rule content, rendered FuseBase-native): never launch bare → attach ≥1 liveness guarantee (foreground+hard-timeout when feasible; bounded wrapper + incremental logging for anything backgrounded; internal watchdog from the FIRST version, not after it hangs; per-call timeouts; always flush partial results); diagnose-a-suspected-hang (check ACTIVITY/mtime/last-progress, not 0-byte existence; slow-but-progressing vs stalled); on-confirmed-hang recover (stop → re-run robust version → clean residue → retry transient rate-limits). Cross-link task-delegation (`BLOCKED-AT`), smoke-testing (record-then-read / observability-gap), token-economy (don't poll). Clean-room note.

### B — structural safe-by-default tooling (the load-bearing arm)
- New helper `hooks/local/lib/bounded-run.sh` that **REUSES** `run-with-timeout.sh`'s core (timeout/gtimeout detection, `-k` kill-grace, rc-124/137 classification, skip-when-no-binary policy) **WITHOUT renaming or breaking the `ffhc_*` API** that `fusebase-flow-health-check.sh` sources (MED finding — preserve back-compat; either `source` run-with-timeout from bounded-run, or extract a shared core both call). ADD: a wall-clock **deadline** that emits a terminal **timeout line** so a bounded job reaches completion/death (not a silent idle) + **incremental progress logging** to stderr. Scripts become robust by `source hooks/local/lib/bounded-run.sh` + one call (established sourced-lib convention; survives `fusebase update`; FR-25-friendly). Watchdog + incremental-logging are greenfield (grep: zero `watchdog|heartbeat|liveness` prior art) — author them. **Honest scope (D7):** bounds the monitored process; does not chase detached grandchildren — the skill teaches "don't `&`-detach under the wrapper; deadline inside long scripts too."
- **(D5 — DEFERRED)** a `templates/bounded-script.sh` skeleton → put a compact copy-paste example IN the skill instead.
- **(D4 — DEFERRED)** a parallel Python watchdog helper → shell path first; note Python tooling has no shared timeout helper as a follow-up.

### C — present-by-construction delivery (3 tiers, mirroring FR-22/FR-26)
- **Tier 1 (always-on primary):** ONE pointer row in `flow-skills/role-discipline/SKILL.md` § Write-time discipline digest (after the FR-26 row, line ~247), scoped "all tool-using execution (every role)". This is the proven channel (FR-26 already rides it as an execution-time rule).
- **Tier 2 (host backstop):** one liveness-reminder clause appended to the `session_start.py` bootstrap string (`:87-94`), pointing to the digest/skill.
- **Tier 3 (handoff-carried):** promote the turn-completion/`BLOCKED-AT` clause from the parallel-only Tracks section (`templates/handoff-implement.md:105`) and the "delegated sessions" qualifier (`templates/handoff-deploy.md:25`) UP into the Role-bootstrap Hard-invariants so the MAIN session carries it (the FR-22 "not remember-to-inline" lesson). Optional pre-attestation checkbox.

### D — warn-only nudge **(D3 — DEFERRED)**
- A `pre_tool_use.py` background-launch-without-wrapper nudge is deferred: `_output_decision()` maps a non-allow/non-deny decision to Claude `ask` (interactive/blocking-ish), so a naive "warn" would block, not nudge. A follow-up ticket can ship it as **allow + warning text/audit** (never a block) with tests proving no block. Out of this ticket.

### E — docs
README § Skill catalog + Commands & capabilities (FR-27/liveness-discipline row); `docs/rail-mapping.md` (FR-27 → enforcement surfaces = digest delivery + bounded-run tooling, explicitly "no gate"); FLOW_RULES amendment-log entry. (sync-version-strings auto-derives the FR range + skill count — `:96`/`:104` — so the ~40 carriers sweep automatically.)

## Out of scope / non-goals
- A blocking gate on background launches (semantic failure; would train premature kills).
- Any hook claiming to VERIFY the protocol / detect a hang (structurally impossible — see the enforcement model).
- Re-pasting the protocol into every handoff (pointer + the promoted Hard-invariant clause; FR-23/26).

## Constraints (FR-07)
- **APPEND** FR-27 only — existing FR-01..FR-26 rows UNCHANGED; the 3 deploy-policy rule semantics + `ratchet-governance.yml` UNCHANGED.
- New skill → re-mirror (`mirror-skills.sh`). FR-25: helpers under ceiling.

## Decisions (LOCKED — design review folded)
- **D1:** **NEW FR-27 + skill** (not fold-in) — fold-in inherits a narrow trigger; the failure includes the main agent's own probes/deploy/fetch/browser work, which task-delegation (sub-agents only) can't reach.
- **D2:** skill name **`liveness-discipline`** (property-oriented house style; trigger phrases — "background task hangs", "agent sits idle", "never resumes" — go in the description).
- **D3:** **DEFER** the warn-only `pre_tool_use` nudge (host maps it to `ask`/block; needs an allow-with-warning path + tests → follow-up).
- **D4:** **DEFER** the Python watchdog helper (shell first).
- **D5:** **DEFER** the `templates/bounded-script.sh` skeleton (compact example lives in the skill).
- **D6:** **Keep `task-delegation` sub-agent-scoped**; FR-27 is the general rule, cross-linked (no duplication, no narrowing).
- **D7:** Honest model confirmed; tooling claim **qualified** (bounds the monitored process / prevents silent unbounded waits; does not kill detached grandchildren or prove host wake) — see the enforcement model.

## Acceptance criteria
- **AC1** FR-27 row appended to FLOW_RULES.md (existing FR-01..FR-26 rows byte-unchanged) + amendment-log entry; `sync-version-strings` auto-sweeps the live FR range (FR-01..FR-27) + the parenthesized canonical skill-count form; **the few manual prose carriers (README skill-count/catalog rows) are updated by hand** (sync doesn't rewrite those).
- **AC2** `flow-skills/liveness-discipline/SKILL.md` carries the full protocol + a compact bounded-run example (D5) + cross-links (task-delegation BLOCKED-AT, smoke-testing record-then-read); mirrors byte-identical; clean-room note present.
- **AC3 (structural — load-bearing)** `hooks/local/lib/bounded-run.sh` exists and REUSES run-with-timeout's core without breaking the `ffhc_*` API. Tests: (a) a deliberately-hanging command through the wrapper terminates with a timeout line within the deadline (rc 124/137) — the silent-unbounded-wait is structurally bounded; (b) incremental progress is emitted; (c) **no-timeout-binary** path degrades per the existing skip policy (not a false "bounded"); (d) **ignored-SIGTERM** child is still killed by the `-k` SIGKILL grace; (e) the health-check still passes (FFHC API intact). Honest: the test does NOT claim to kill a `&`-detached grandchild (the skill forbids detaching under the wrapper).
- **AC4 (delivery)** the FR-27 digest row, the session_start reminder line, and the promoted handoff Hard-invariant clause are present; a test asserts the implement-handoff template carries the liveness clause in the Role-bootstrap Hard-invariants (not only the Tracks section).
- **AC5 (honest model)** no shipped artifact claims hook-verification of the protocol; rail-mapping states "no gate; enforcement = safe-default tooling + present-by-construction delivery"; the tooling claim is qualified (monitored process, not detached descendants).
- **AC6 (no regression)** the existing health-check timeout behavior + its tests still pass (run-with-timeout/FFHC API unchanged).
- **AC7 (gate)** preflight 0/0; run-tests PASS incl. new tests; check-module-size --all exit 0; mirror 0 drift; FR-07 clean (FR-01..FR-26 rows + 3 deploy policies + ratchet unchanged).

## Tasks
- **T1 (A)** FR-27 row + amendment-log; `liveness-discipline` skill (with compact bounded-run example + cross-links).
- **T2 (B)** `hooks/local/lib/bounded-run.sh` — REUSE run-with-timeout core (preserve `ffhc_*` API) + deadline/timeout-line + incremental logging.
- **T3 (C)** role-discipline digest row + session_start reminder line + promote the liveness/BLOCKED-AT clause into the Role-bootstrap Hard-invariants of `templates/handoff-implement.md` (+ `handoff-deploy.md`).
- **T4 (E)** README (§ Skill catalog + Commands & capabilities + skill-count prose) + `docs/rail-mapping.md` (FR-27 → delivery + bounded-run; "no gate").
- **T5** tests (AC3 a–e bound/degrade/SIGTERM/FFHC-intact, AC4 handoff-carries-clause, AC6 health-check no-regression) + re-mirror skills.
- **DEFERRED (follow-up tickets):** D3 warn-only pre_tool_use nudge (`fr27-prelaunch-nudge`); D4 Python watchdog helper; D5 templates skeleton.

## Risks
- **Attestation theatre / inert lever** (the session's recurring trap): do NOT ship a hook that claims to verify; the structural bounded-run tooling must genuinely terminate a hang (AC3 proves it). This is the load-bearing check.
- **Always-on floor cost:** each FR adds permanent surface — keep FR-27's recurring footprint to ONE digest pointer line (body in the skill); cross-link, don't duplicate, task-delegation/smoke-testing.
- **Scope creep into a gate:** resist; semantic failure → no gate (FR-26 precedent).
