---
description: Run a Fusebase Flow health check. Reports overlay status, upstream drift, and — if drift is recoverable — offers to run `bash hooks/local/post-fusebase-update.sh` after explicit operator confirmation in chat. Diagnosis is always read-only; recovery executes only on affirmative reply (`yes` / `run it` / `fix it` / `proceed`).
---

# /fusebase-health — Fusebase Flow health check

Trigger the `fusebase-flow-health-check` skill to inspect overlay state and report.

## Your job (main agent)

1. Invoke the `fusebase-flow-health-check` skill.

   The skill's procedure:
   - Reads `hooks/local/fusebase-flow-health-check.sh` to confirm the engine is present.
   - Runs the engine via `bash hooks/local/fusebase-flow-health-check.sh` (read-only).
   - Parses the structured report and surfaces it to the operator in Mode A (tabular).
   - If drift is detected and recoverable (`FUSEBASE_UPDATE_AFTERMATH` or recoverable `DRIFTED`), **offers** to run recovery in-chat with a yes/no confirmation. Executes `bash hooks/local/post-fusebase-update.sh` only on affirmative reply.

2. After the skill reports, halt — UNLESS:
   - Verdict is recoverable AND operator replies affirmatively (`yes`, `run it`, `fix it`, `proceed`, etc.) → run recovery + re-check + report new verdict
   - Verdict is `EXCEPTION_IN_EFFECT` → surface listed artifacts, do NOT offer recovery (recovery doesn't fix this)
   - Verdict is `BROKEN` → surface LOCAL_BROKEN items, do NOT offer recovery

## Constraints

- This slash command is a **shortcut** for the description-matched `fusebase-flow-health-check` skill. Operators can also trigger the same flow by saying any of:
  - "Is Fusebase Flow healthy?"
  - "Check Fusebase Flow"
  - "Did fusebase update break anything?"
  - "Fusebase Flow status"
- The skill's diagnosis phase is **read-only**. Recovery executes only after explicit operator confirmation in chat (per PO.5 — don't lock decisions on the operator's behalf).
- If the operator types `/fusebase-health` in a fresh session, the agent reads the skill instructions from `.claude/skills/fusebase-flow-health-check/SKILL.md` (Claude Code) or `.agents/skills/fusebase-flow-health-check/SKILL.md` (Codex) and follows the same procedure.

## Output expectation

The skill produces a structured report similar to:

```
Fusebase Flow health check — <timestamp>

Local state:
  ✓ / ✗ / ⚠ per check

Active approval artifacts (if any):
  • <filename>: paths=N expires=<ISO8601> scope="..."

Upstream:
  in sync OR newer (with commits enumerated)

Verdict: HEALTHY | EXCEPTION_IN_EFFECT | FUSEBASE_UPDATE_AFTERMATH | DRIFTED | BROKEN

Recommendations:
  • <action items>
```

Verdict guide for the agent:

- `HEALTHY` (exit 0) — no action needed.
- `EXCEPTION_IN_EFFECT` (exit 3) — drift attributable to active approval artifact(s) in `state/approvals/`. Do NOT recommend recovery; recommend reviewing/clearing the artifact.
- `FUSEBASE_UPDATE_AFTERMATH` (exit 1) — the canonical `fusebase update` aftermath. Offer recovery in chat: *"Run recovery now? Reply `yes` to proceed."* Execute on affirmative.
- `DRIFTED` (exit 1) — drift detected but doesn't match a known pattern. Recommend manual investigation; recovery script as optional fallback (still requires confirmation).
- `BROKEN` (exit 2) — genuine failure NOT attributable to operator-authored exceptions. Recommend manually inspecting LOCAL_BROKEN items.
