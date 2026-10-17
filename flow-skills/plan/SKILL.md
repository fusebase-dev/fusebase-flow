---
name: plan
description: Load when you plan. Turns the operator's feedback into backlog items, then phases, slices and tasks with globs and estimates. Planner only.
---

# Plan

The planner (the operator's main session, or an agent with the planner profile) runs this skill. It writes `backlog.md` and `phases.md`. Builders never load it.

**6.0.0-m1, by hand until the scripts land:** `policies/evidence-classes.yml` does not exist yet, so the trivial-tier lists and the minimum evidence class are judged by the planner; no slicer prints glob breadth and no check flags a risk or criterion edit. Commit the documents as `docs(flow): plan <what>` (the 5.11 `commit-msg` rejects a bare `plan:`).

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

No backlog item is needed when every staged path matches the docs, test or copy lists in `policies/evidence-classes.yml` as committed at HEAD, or the diff is formatting only. The subject still carries one `T<n>`. Never trivial: deleting a test, adding a skip to a test, any edit to the four documents, any code extension.

## Commit

A `plan:` commit stages only the four documents, `state/flags/*.tsv` and `state/gate/*.txt`.

## When planning goes wrong

- More than about 12 criteria, several deploys, or two natural halves: split the item.
- Investigation shows the item is wrong (the behaviour is intended, the bug is elsewhere, the feature exists): set its status to `dropped`, the commit message saying in one paragraph of what was found. Never quietly fix something else instead.
- Two rounds of questions widen the gap: ask the operator to restate the goal in three sentences.
