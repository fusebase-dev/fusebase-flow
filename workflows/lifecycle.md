# Lifecycle: plan, build, verify, ship

The planner (the operator's main session) runs every step; builders build one slice each; readers review and judge. Rules: `FLOW_RULES.md`. The four documents live in `docs/flow/`, copied from `templates/`.

**6.0.0-m4.** The six scripts are in `hooks/local/`.

## 1. Plan (skill `plan`)

- Feedback becomes items in `backlog.md`: one criterion or test id, inputs, a risk tag (`none`, `auth`, `data`, `prod`), a status. The owner's answers go under `## Answers`, verbatim.
- Items become phases, slices and tasks in `phases.md`: task id, item, globs, estimate in minutes and files, the reference project.
- Commit the four documents alone, as `plan: <what>`.

## 2. Build (skill `dispatch`)

- One slice per builder: the output of `python hooks/local/slice.py <slice>`, the builder push block and the writing card, inlined.
- A builder commits one task per commit with one `T<n>` in the subject. The git hooks run the secret scan, protected paths, module size, the evidence validator (on a commit that stages evidence rows or `state/runs/`), lint and typecheck, and the subject check.
- Before its turn ends a builder writes `state/returns/<slice>.json`. It is a claim.
- Long or silent commands run under `bounded_run`. `python hooks/local/reader.py --once` (scheduled by `install --register-reader`; `--watch` in a terminal) writes `state/status.line`: running or idle, silence alerts, reader last seen.

## 3. Verify (skill `verify`)

- `python hooks/local/gate.py <slice>` runs the DONE check (`done.py`), the four flags (`checks.py`) and the evidence-row validator (`validate_evidence.py`) and writes `state/gate/<slice>.txt`. A DONE failure sends the slice back to build.
- Review: one reader with `python hooks/local/slice.py <slice> --brief review`. Phase gate: one verdict reader and two skeptic readers, never per slice. `gate.py` counts the verdict records in the ledger against `gate_rounds` (default 2) and returns `BLOCKED-AT-gate-budget` at the limit.
- Evidence: one row per criterion in `docs/flow/evidence/P<n>.md`. The minimum class follows from the paths the task touched, and the risk tag may raise it, never lower it: `auth`, `data` and `prod` need live evidence, the rest unit or smoke. The validator hashes each capture, checks its size and dates, and reads the run log for a finding behind a PASS row.

## 4. Ship (skill `ship`)

- Present the exact deploy command and its side effects in chat; production needs the operator's `approve deploy now`. Then mint with `bash hooks/local/approve-local.sh` and deploy from the main session.
- Run the live rows; write the deploy record in the ledger and one line in `state/deploys/<env>.jsonl`.
- An item is `done` only when `python hooks/local/validate_evidence.py <phase>` passes its row. One commit: ledger, deploy line, evidence rows, backlog status, as `ship: <what>`.

## Installing Flow

`python <core>/maintainer/flow.py install --target <project> --providers claude,codex` copies the core, the provider mirrors and the three git hooks, and leaves them uncommitted. Committing them touches protected paths: stage them by name, run `FF_BOOTSTRAP_TTL_MIN=30 bash hooks/local/write-bootstrap-approval.sh`, commit with a `flow:` subject (`flow: install Fusebase Flow <version>`; it passes only on Flow's own files, the four documents and Flow's marked blocks), then run it with `--consume`. Re-running the install is the upgrade within 6.0; `--register-reader` also schedules the reader every 5 minutes, and `--wire-hooks` merges the two tool handlers into `.claude/settings.json` and `.codex/hooks.json`. `flow.py health --target <project>` checks an install, read-only.

`commit-msg` takes exactly one `T<n>`, a task of `phases.md` at HEAD once it has tasks; `plan:` and `ship:` only on the files their skills name; a merge by git's state. A commit outside the trivial tier (`plan` skill) needs its task's backlog item.
