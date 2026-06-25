# Backlog — fr27-prelaunch-nudge (FR-27 follow-up / D3)

**Status:** parked
**Source:** deferred from `liveness-discipline` (FR-27 shipped v3.28.0, hash `8cacb80`); design review (Codex 2026-06-17) flagged the naive form as a blocker, not a nudge.
**Lane (when picked up):** Full (PreToolUse decision-path change + allow-with-warning channel + tests).

## What D3 is
A **warn-only `pre_tool_use` pre-launch nudge**: when an agent is about to launch a long/silent background task *without* a liveness guarantee (no `bounded-run` wrapper / no in-turn completion / no `BLOCKED-AT`), surface a one-line reminder pointing at `flow-skills/liveness-discipline` + `hooks/local/lib/bounded-run.sh`. It is the third delivery tier FR-27 deliberately deferred — present-by-construction delivery (digest + session_start + handoff Hard-invariants) shipped in v3.28.0 without it.

## Why it was deferred (not shipped with FR-27)
`pre_tool_use._output_decision()` maps a **non-allow / non-deny** decision to the Claude `ask` outcome — which is **interactive / blocking-ish**. So a naive "warn" would **block**, not nudge — recreating exactly the premature-kill / approval-fatigue failure FR-27's honest model avoids (the same FR-26 precedent: a real hang vs a legitimate long-but-live run is semantic; never train a premature kill).

## Prerequisites this ticket MUST add before D3 is buildable
1. **Allow-with-warning channel (load-bearing).** The handler must emit `allow` **plus** a warning text / supplemental audit event — never a `block` / `ask`. Ship a test that PROVES the decision is `allow` (rc 0), not a block, on a no-wrapper background launch. Without this proof the ticket must not land.
2. **Background-launch detection that doesn't over-fire.** Detect a genuine long/silent background launch (e.g. `&`-detach, a known long-runner) without firing on every Bash call. Heuristic stays warn-only; a false positive costs one stderr line, never a block.
3. **Honest-model guard.** The nudge must never claim to VERIFY the protocol or detect a hang (structurally impossible — see the spec's enforcement model). It is a present-at-launch reminder only.

## Boundary (unchanged from FR-27)
- **No blocking gate, no verification hook** — a hang is undetectable by construction; the nudge is allow + warning only.
- The bounded-run tooling claim stays **qualified** (bounds the monitored process; does not kill `&`-detached grandchildren or prove host re-invocation).
- No FR rule-row edit; no deploy-policy / `ratchet-governance.yml` change.

## Smaller sibling follow-ups (noted, separate tickets)
- **D4 — Python watchdog helper.** Shell path shipped first (`bounded-run.sh`); Python tooling currently has **no shared timeout helper**. A parallel Python `bounded_run` for Python-launched long work. Smaller scope than D3.
- **D5 — `templates/bounded-script.sh` skeleton.** A copy-paste bounded-script template. The compact example currently lives inside `flow-skills/liveness-discipline/SKILL.md`; D5 would extract it to a template file. Smallest of the three.

## Relation to shipped work
- FR-27 shipped v3.28.0 (hash `8cacb80`): the rule + `flow-skills/liveness-discipline` skill + `hooks/local/lib/bounded-run.sh` structural helper + 3-tier present-by-construction delivery (digest row + `session_start` reminder + handoff Hard-invariants).
- Parent spec: `docs/specs/liveness-discipline/spec.md` (D3/D4/D5 marked DEFERRED there).
