# Problem: server-side API rate-limit/529/drop mid-task is a SERVER issue — retry, don't treat as failure

**Slug:** `transient-subagent-retry-discipline`
**Filed:** 2026-07-03
**Severity:** medium
**Status:** resolved (discipline captured)
**Filed by:** PO per FR-15 (operator "update docs for the future")

## Symptom

During the autonomous roadmap run, delegated ai-developer / deploy / Codex-companion sessions occasionally DIED mid-task on a server-side transient (API rate-limit / 529 / connection drop). Treating that death as a real failure would abandon intact WIP; passively waiting on the auto-completion notification would idle silently.

## Reproduction

| Step | Action | Observed |
|---|---|---|
| 1 | Delegate a multi-step task to a subagent/Codex | runs |
| 2 | Server returns 529 / rate-limit / drops the connection mid-turn | subagent dies; WIP on disk intact |
| 3 | Retry immediately (or wait ~1 min, retry until it starts); resume via SendMessage from WIP | completes |

Reproduces: intermittent (server-load dependent — see FR-10)

## Root cause

The failure is on the SERVER side (API rate-limit / 529 / connection drop), not in the task. The auto-completion notification is unreliable (codex-companion sometimes flushes only a preview before "Turn completed"), so passive waiting idles silently while the work is actually dead or done.

## Why it matters

- A transient death mistaken for a real failure abandons intact, resumable WIP.
- Passive waiting on an unreliable completion ping burns wall-clock with the agent idle.

## Mitigation / workaround

1. On a server transient: RETRY immediately; if it repeats, wait ~1 min and retry until it starts.
2. Resume a dead ai-developer/deploy agent via SendMessage from its intact WIP.
3. Proactively POLL subagent/Codex liveness every ~15-90s via git-progress/process/file-growth — do NOT rely solely on the auto-completion notification.
4. Before trusting any agent's output, verify final git state: clean linear history, 0 mirror drift, consumed FR-07 approvals.

## Permanent fix

| Status | Detail |
|---|---|
| Shipped | discipline already codified in FR-27 (zero-trust subagent liveness) + `flow-skills/liveness-discipline`; captured here for recurrence · release v3.30.5 (`180f4a1`) · 2026-07-03 |

## Recurrence triggers (so future sessions recognize this)

Future sessions hitting these signals should load this entry:

- A delegated subagent/Codex returns 529 / rate-limit / connection-drop mid-task
- The completion notification arrives but the transcript is a 0-byte or preview-only flush
- An autonomous multi-agent roadmap run with long-running delegated slices

## Guardrail (the lesson)

Never treat a transient death as a real failure — retry (immediately, then ~1 min backoff until it starts); resume from intact WIP via SendMessage; proactively poll liveness (git/process/file-growth, not the completion ping); verify final git state (clean linear history, 0 mirror drift, consumed FR-07 approvals) before trusting any agent.

## Related

- `flow-skills/liveness-discipline/SKILL.md` — FR-27 zero-trust subagent liveness (the canonical home)
- `MEMORY.md` [retry-failed-subagents-and-poll-liveness] · [subagent-deploy-run-synchronously]

## Audit log

| Date | Event | Source |
|---|---|---|
| 2026-07-03 | filed + resolved | release v3.30.5 (`180f4a1`) |
