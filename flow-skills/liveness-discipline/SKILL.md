---
name: liveness-discipline
description: Use when launching any long or silent work that could hang — your own probe/script/deploy/fetch-loop/browser-automation, a sub-agent, or a workflow — or when the operator says "the background task hangs", "the agent sits idle", "it never resumes", "is it still running?", or a turn ended waiting on something that never came back. Delivers FR-27's never-launch-bare protocol: bounded/watchdog wrapper, in-turn completion, or BLOCKED-AT return; how to diagnose a suspected hang by activity not 0-byte existence; how to recover. Do NOT use to justify a blocking gate or a hook that claims to verify the protocol (a hang is undetectable by construction), and do NOT use for delegated sub-agent turn-completion alone (task-delegation owns that slice — cross-linked here).
source_inspiration: conceptual-only
license_status: clean-room-original
fusebase_flow_version: "3.28"
risk_level: low
invocation: automatic
expected_outputs:
  - every backgrounded/long/silent launch carries at least one liveness guarantee (bounded wrapper + incremental logging, in-turn completion, or BLOCKED-AT) before it runs
  - a suspected hang is diagnosed by activity/mtime/last-progress, not by 0-byte existence, then recovered (stop -> robust re-run -> clean residue)
related_workflows:
  - greenlight-implement.md
  - greenlight-deploy.md
  - smoke-verification.md
hook_dependencies:
  - none
---

# Liveness Discipline (FR-27)

## The failure (why this rule exists)

A long/silent command (probe, test script, deploy, fetch loop, browser automation), a sub-agent, or a harness-auto-backgrounded workflow that **HANGS** emits **no completion event**. The host therefore never re-invokes the agent, which idles indefinitely while appearing "done" — until a human asks "is it still running?". The hang→no-event→idle failure is **invisible by construction**: there is no elapsed-time/idle event in the hook schema, and a call that never returns can never fire a post-call hook. So this rule is **not** enforced by a gate or a verification hook — a Stop-time "watchdog: applied" signal would be attestation theatre. Enforcement = **safe-default tooling** (`hooks/local/lib/bounded-run.sh`) + **present-by-construction delivery** (this skill in context at launch time).

## Guardrail (the rule's floor)

**Quality/safety floor unchanged.** Never launch bare — but a liveness guarantee is the floor, not a license to kill a slow-but-progressing job. A bounded deadline is sized for the work, never so tight it trains premature kills (the FR-26 "budget gate trains truncation" lesson, inverse). Diagnose before you kill.

## Protocol — never launch bare → attach ≥1 liveness guarantee

Before launching ANY long/silent work, attach at least one of these. In preference order:

| # | Guarantee | When | How |
|---|---|---|---|
| 1 | **Complete in-turn** | the work fits the current turn | run foreground with a hard timeout; do not background it at all |
| 2 | **Bounded wrapper + incremental logging** | the work is genuinely long and you must background it | `source hooks/local/lib/bounded-run.sh` + one `bounded_run` call (below); the wrapper emits a terminal timeout line so the job reaches completion-or-death, never a silent idle |
| 3 | **`BLOCKED-AT-<gate>` + record-then-read pointer** | the remaining wait is UNBOUNDED (human approval gate, external event with no ETA) | return the explicit `BLOCKED-AT-<gate>` verdict + what "cleared" looks like + a pointer to where reality is recorded; the orchestrator re-dispatches when the gate clears (`flow-skills/task-delegation` Blocked-return rule) |

Mandatory regardless of which guarantee you pick:

- **Internal watchdog from the FIRST version** — put the deadline in at authoring time, not after it hangs once. Retrofitting a timeout after the first idle is too late.
- **Per-call timeouts** — every individual fetch/RPC/subprocess inside a loop carries its own timeout, not just the outer wrapper.
- **Always flush partial results** — write durable facts AS THEY OCCUR (skeleton first, rows as earned) so a kill at the deadline still leaves evidence (`flow-skills/task-delegation` progress ledger, `flow-skills/smoke-testing` record-then-read).
- **Incremental progress logging to stderr** — a job that prints "still working: step 3/8" cannot masquerade as a hang, and `bounded_run` does this for you.

## Compact bounded-run example (D5 — the copy-paste skeleton)

`bounded_run <deadline-secs> <progress-label> -- <cmd> [args...]` sources the shared core from `run-with-timeout.sh` (so the `ffhc_*` health-check API is untouched), bounds the MONITORED process to the deadline, logs a heartbeat to stderr every interval, and ALWAYS emits a terminal line — either the command's completion or a `bounded-run: TIMEOUT` line — so the job reaches completion-or-death instead of a silent idle.

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(git rev-parse --show-toplevel)/hooks/local/lib/bounded-run.sh"

# Bound a slow re-verify probe to 120s; heartbeat to stderr; terminal line guaranteed.
bounded_run 120 "re-verify probe" -- ./scripts/reverify.sh --target "$URL"
rc=$?
# rc 124 = deadline elapsed; rc 137 = ignored SIGTERM, SIGKILLed after the -k grace.
# On timeout the wrapper already printed the terminal "bounded-run: TIMEOUT" line —
# surface it, flush partial results, then diagnose (do not blind-retry).
```

**Honest scope (D7 — do not overstate).** `bounded_run` bounds the **monitored** process only. It does **NOT**:

- kill a grandchild you `&`-detached or `Start-Process`'d out from under it — **so don't detach under the wrapper**; keep the work in the monitored process tree;
- interrupt an uninterruptible OS wait;
- *prove* the host re-invokes you — it ensures the process reaches completion/death so a host that surfaces background completion has an event to deliver, and so a 0-byte silent idle becomes a visible timeout line.

Therefore: **put a deadline INSIDE long scripts too** (an event-loop-blocked `setTimeout` won't fire; an inner fetch needs its own timeout), don't `&`-detach under the wrapper, and always flush partial results.

## Diagnose a suspected hang (activity, not existence)

A slow-but-progressing job is NOT a hang. Distinguish before you kill:

- Check **activity**: last log line, output file **mtime**, byte growth, last progress marker — NOT mere "the file exists" (a 0-byte file proves nothing) and NOT "the process is listed".
- **Slow but progressing** (mtime advancing, new log lines, byte count climbing) → let it run; widen the deadline if the work legitimately needs it.
- **Stalled** (no activity past the expected interval, no heartbeat, deadline elapsed) → confirmed hang; recover.

## Recover from a confirmed hang

1. **Stop** the stalled process (the wrapper's timeout line means it already terminated; otherwise terminate it).
2. **Re-run the robust version** — the same launch with a deadline + incremental logging attached (never blind-retry the bare launch; that's the two-strike anti-pattern, FR-26).
3. **Clean residue** — partial files, locks, half-written state from the killed run.
4. **Retry only transient rate-limits** with bounded, labeled backoff; a structural hang is not a rate-limit and re-attempting it unchanged is forbidden.

## Cross-links (reuse, do not duplicate)

| Slice | Canonical home | Relationship |
|---|---|---|
| Delegated sub-agent turn-completion + `BLOCKED-AT` | `flow-skills/task-delegation/SKILL.md` (turn-completion / Blocked-return) | FR-27 is the GENERAL rule (covers the agent's own work too); task-delegation keeps the sub-agent slice — cross-linked, not narrowed (D6) |
| Record-then-read / observability-gap finding | `flow-skills/smoke-testing/SKILL.md` § Verification cost discipline | the prescribed remedy for "how do I know it finished?" — read durable evidence once after the run; no durable surface = an observability-gap finding, not agent-side polling |
| Don't poll while it runs | `flow-skills/token-economy/SKILL.md` (record-then-read row) | agent-side watching costs tokens linear with wall-clock; bound + log + read records instead |

## Anti-patterns

- Launching a background probe/deploy/fetch-loop with no timeout, then ending the turn "running in background — I'll resume when it completes" (you won't — the host never re-invokes a hung call).
- Adding a hook or Stop-time signal that claims to VERIFY this protocol or detect a hang — structurally impossible; it would be attestation theatre (the inert-lever anti-pattern).
- A blocking gate on background launches — the failure is semantic (real hang vs legitimate long-live run); a gate trains premature kills (intelligence damage).
- `&`-detaching under `bounded_run` and assuming the deadline still bounds the detached grandchild (it does not).
- Diagnosing a hang by "the output file exists" (0-byte existence proves nothing) instead of by activity/mtime/last-progress.
- Blind-retrying the same bare launch after it hung (two-strike, FR-26) instead of re-running the robust, bounded, logged version.
- Re-pasting this protocol into every handoff — it lives here; handoffs carry the promoted Hard-invariant clause + a pointer (FR-23/FR-24).

## Clean-room note

Original Fusebase Flow content. Designed after reviewing public AI coding workflow patterns; no third-party code, prompts, skill files, or hook scripts are copied. The bounded-run tooling reuses Fusebase Flow's own `run-with-timeout.sh` core (not a third-party watchdog). See `docs/source-map.md`.
