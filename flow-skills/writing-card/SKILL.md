---
name: writing-card
description: Load before you write code, a document or a chat answer. Seven habits that keep text short, replaceable and cheap to read.
---

# Writing card

1. Chat answers are short and concrete: the answer first, then ids, paths and SHAs; a table only for three or more comparable rows.
2. Replace, do not append: edit the stale part in place, and git keeps the history. Rewrite a whole file only when its structure changed.
3. Comments only for a constraint the code does not show (one line) and a pointer to where the reason lives, such as `(B12)`. Never restate what the code does, and never match a file's comment density.
4. Read your slice, not the backlog. Read the whole file before you edit against its invariants or close verification on it.
5. Do not re-read a file already in your context unless it may have changed: your own edit, a hook or formatter, another agent, a git operation, a failed edit or a compaction.
6. After two failures of the same approach (same action, same inputs), change the approach; never a third identical try. Not strikes: a reproduction trial (verify), a rerun after a real change, a bounded retry of an external failure, a delegate re-dispatch inside the retry envelope (dispatch § Delegate liveness).
7. Scope the first run of a command with large output: a tail, a grep, a limit, or a report file you read once.
