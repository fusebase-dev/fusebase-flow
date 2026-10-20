---
name: plan
description: Load when you plan. Turns the operator's feedback into backlog items, then phases, slices and tasks with globs and estimates. Planner only.
---

# Plan

The planner (the operator's main session, or an agent with the planner profile) runs this skill. It writes `backlog.md` and `phases.md`. Builders never load it.

Commit the documents as `plan: <what>`; `commit-msg` takes `plan:` only on the files under Commit below. Declare the project's class globs and trivial-tier lists in `policies/evidence-classes.yml`, a protected file.

A protected Flow file (`policies/*.yml`, say) is edited on the operator's go-ahead in chat for the files it names: before the edit, run `FF_BOOTSTRAP_TTL_MIN=30 bash hooks/local/write-bootstrap-approval.sh --paths <file>...`; edit; commit exactly those files under a task's `T<n>`; then run the script with `--consume`. The commit spends the approval, which lasts 30 minutes at most.

## Read first

- `docs/north-star.md` when it exists: say so when work does not serve it. Never create the file.
- The ledger's first line and `state/status.line`.

## Backlog items

One item per piece of operator feedback in `backlog.md`: `B<n>`, the source slice, one acceptance criterion or a test id, the inputs, a risk tag and a status. The operator's answers live in the item.

- For logic, prefer a failing test as the criterion; a test-id row is valid evidence (verify).
- The cause unknown: a diagnostic item whose criterion is the named root cause with its evidence; the fix is a second item.
- Inputs: name each input and the kind of tool that reads it; `policies/agent-tools.yml` maps kinds to tools. An input no profile can read is a question now, never a build-time fallback.
- Risk tag: `auth`, `data` or `production` need live evidence. The evidence class follows from the paths a task touches (`policies/evidence-classes.yml`); the tag may raise it, never lower it. A change to an item's risk or criterion line inside its own slice window is flagged.
- A related concern outside the item becomes a new item, never a silent expansion.
- Work carried from Flow 5.x or another plan: one item per evidence row it needs, each with its own criterion or test id; a 5.x task list's gate, review or close step is not a task: the gate is your step (verify).

## Questions

Ask each unclear point in chat text: one question, two or three options, one marked (Recommended). Record the operator's answer in the item. Never settle an answer on the operator's behalf.

## Phases, slices, tasks

In `phases.md`:

- Each phase names its reference project: for a FuseBase app, the cookbook blueprint for the domain or one reference project. Simplest means no further from the reference than the task requires.
- A slice is what one builder finishes in one turn, planned at about 50 tool calls or fewer. Split larger work into sequential slices that resume from records, never below one independently verifiable task. The size is a planning split, never truncation: a builder past it finishes its slice, and the next slice starts fresh.
- A task has a `T<n>` unique across the file, the item it serves, the directories or globs it may touch (as narrow as is true; the slicer prints their breadth) and an estimate in minutes and files. Test paths are estimated separately.
- Every task names its target files. A target over the module-size ceiling, or one the task would push over it, gets an extraction along a named responsibility seam, or an exemption the operator approves.
- Slices with disjoint globs can run in parallel.
- Each phase has one housekeeping task for trivial commits.

## Trivial tier

No backlog item is needed when every staged path matches the docs, test or copy lists in `policies/evidence-classes.yml` as committed at HEAD, or the diff is formatting only. The subject still carries one `T<n>`. Never trivial: deleting a test, adding a skip to a test, any edit to the four documents, a code extension under the docs or copy list. `commit-msg` checks all of this, resolving the `T<n>` in `phases.md` at HEAD.

## Commit

A `plan:` commit stages only the four documents, `state/flags/*.tsv` and `state/gate/*.txt`.

## When planning goes wrong

- More than about 12 criteria, several deploys, or two natural halves: split the item.
- Investigation shows the item is wrong (the behaviour is intended, the bug is elsewhere, the feature exists): set its status to `dropped`, the commit message saying in one paragraph of what was found. Never quietly fix something else instead.
- Two rounds of questions widen the gap: ask the operator to restate the goal in three sentences.
