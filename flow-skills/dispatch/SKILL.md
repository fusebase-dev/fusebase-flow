---
name: dispatch
description: Load when you dispatch or supervise build work. Slices to builders, the builder push block, typed returns, pause, and the wake after you end the turn. Planner only.
---

# Build

The planner runs this skill. Builders never load it: each gets the push block below inside its slice.

## Dispatch

1. Print the slice: `python hooks/local/slice.py <slice>`. It prints the item, the criterion, the cited answers, the inputs, the globs and their breadth, the estimate, the reference project and `state/status.line`. A slice that prints `BLOCKED-AT-input` (exit 3) is not dispatched: ask the operator for the input or the tool. A tool is added in `policies/agent-tools.yml`, a protected file; the operator approves the exact list.
2. Run slices in parallel only when their globs are disjoint, their results integrate in any order and one failure cannot corrupt another. Never two builders on one file.
3. Do the step that blocks your next action yourself; dispatch only work that runs beside it.
4. Dispatch as `builder`, or `builder-project` when an input needs a profile tool; it counts as `builder`. Reviewers, skeptics and the verdict writer go as `reader` only (verify).
5. Inline the slice output, the push block and the writing card. Add no other Flow text.

## Builder push block

```text
FLOW BUILDER CONTRACT
1. Only this slice's tasks, inside their globs. One task, one commit, exactly one T<n> in the subject, by `python hooks/local/commit.py -m "<subject>" <files>`. Never revert others' changes.
2. Before each task check state/pause; if it exists, write your return and stop.
3. Missing input or tool: stop with BLOCKED-AT-input naming both; never build without it. Unbounded wait: stop with BLOCKED-AT-<gate> and what cleared looks like.
4. Long or silent commands: source hooks/local/lib/bounded-run.sh; bounded_run <seconds> <label> -- <command>. Never detach under it. Finish within this turn; you cannot resume.
5. Never mint an approval; a grant in chat is not one.
6. Evidence rows are claims; the verdict is not yours. A claim that state changed names the check you ran.
7. Write facts as they happen, never all at the end.
8. Before your turn ends write state/returns/<slice>.json: {"slice", "role": "builder", "started", "finished", "tasks": [{"id", "sha"}], "tool_calls": {"total", "before_first_work", "between_commits": [n]}, "blocked_at": null|"<gate>", "notes"}; UTC times, ids and SHAs as in git log. No file fails the DONE check.
9. Chat return: at most 80 lines and 6,000 characters; point to files.
```

## End the turn after dispatch

- Before the turn ends, dispatch every already-authorized independent slice. A pending operator answer parks only the gated action and its dependents; it opens no gate and grants no authorization. The question is the turn's last content block, in chat text.
- Then arm your host's wake path (table) and end the turn. Never wait inside a large context. Never poll model-side while a watcher can wake you.
- The watcher is a background shell command under `bounded_run` that uses no model tokens, reads SHAs, mtimes and `state/audit/liveness/*.hb`, and exits on progress, a new return file, a stall or its deadline. Every exit wakes you. `bounded_wait` is the one-file form.
- On each wake read the one fact it reports: still running → arm a fresh watcher and end the turn; done → treat the return as a claim and verify; stalled → diagnose (below).
- A watcher cannot cover your own hung foreground call (bound that call), a session that cannot be re-invoked after its turn (stay in-turn, checking at most every 4 minutes), or a host freeze.

| Host | Wakes a turn-ended main session | Note |
|---|---|---|
| Claude Code | a background shell command's exit (task notification) — the watcher's path · a background sub-agent / Workflow completion notification — never the only wake · a scheduled task firing (incl. a `/loop` iteration) — never the only wake · a message another session sends — never the only wake · an `asyncRewake` command hook exiting **2** (its stderr arrives as a system reminder; only exit 2 wakes, so map the alert to exit 2) | report-back, scheduled-task and cross-session turns: hooks docs § UserPromptSubmit · a Workflow agent's stall restart excludes time in its own tool calls; only your watcher sees a hung call |
| Codex | none documented. End the turn after dispatch; the next operator message starts the next task boundary, where you read `state/status.line` and poll `state/returns/`. One exception: the reader (verify) runs synchronously under `bounded_run`, so the turn is held for that bounded run (minutes), never for a build | Codex: unproven until the five phase 7 probes pass |

## At each boundary

- Read `state/status.line` first, then `state/returns/`. "last seen: never" in the slice means nobody scheduled the reader: tell the operator once; `install --register-reader` schedules it.
- While `state/pause` exists, dispatch nothing new. Builders stop at their next committed task.
- A return is a claim. The DONE check compares its ids and SHAs with `git log` (verify).

## Delegate liveness

- A missing completion ping is no information. Progress is new commits, heartbeat lines, mtimes and byte counts; the reader computes silence and repeated commands.
- Slow but progressing is not a hang. Stalled means no progress across two checks past the slice's expected interval: stop it, rerun the bounded version, clean the residue. Never retry a bare launch unchanged.
- A delegate that never started (provider limit, server error) is a dispatch failure, never the slice's verdict. Send "try again" to the same agent id, at most 3 attempts within 5 minutes (about 60, 90, then 120 seconds apart, one progress read per interval). Then brief a successor from records, or return `BLOCKED-AT-delegate-no-start`. Never `FAILED-<reason>`.

## Corrections and successors

- A fix to a builder's own diff goes back to that builder while its context is small: under 50 tool calls summed across its returns and no compaction. Otherwise brief a fresh successor with the findings and ledger pointers.
- One correction owner per review round, batched by file.
- Unfinished or parked tasks are re-dispatched as their own slice, with that slice's brief, to a successor that resumes from records. Never append them to another slice's builder.
- Checks that cover several slices (the phase gate, a phase review) wait until every slice they cover is DONE; a parked slice parks them. A review of one DONE slice proceeds.
- Successor state goes in the ledger (ship).

## Unattended runs

- The dev deploy approval is minted for the exact command before the operator leaves (ship). `bash hooks/local/approve-local.sh --inventory` shows it VALID.
- A blocked slice parks with its question, evidence, options and clearing condition. Every other independent authorized slice continues.
- Retry, review-round or gate-round exhaustion is a scheduling event: record it, park that slice with its findings, dispatch the next independent slice. A slice at its limit is closed only when the operator authorized an unattended close beforehand.
- In an unattended run, builders return in at most 29 lines.

## Budgets

The plan estimates minutes and files per task. Flag 3 compares minutes, files, commits, the return's `tool_calls` and repeated commands with the estimate and with named constants in `checks.py`. Flags never block; they reach you through the review brief.
