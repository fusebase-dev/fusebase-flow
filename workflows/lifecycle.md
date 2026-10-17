# Lifecycle: plan, build, verify, ship

The planner (the operator's main session) runs every step; builders build one slice each; readers review and judge. Rules: `FLOW_RULES.md`. The four documents live in `docs/flow/`, copied from `templates/`.

**6.0.0-m2.** The six scripts (reader, slicer, DONE check, checks, validator, gate) have not landed. Every step marked *By hand* is the planner's until its script arrives with a re-install.

## 1. Plan (skill `plan`)

- Feedback becomes items in `backlog.md`: one criterion or test id, inputs, a risk tag (`none`, `auth`, `data`, `prod`), a status. The owner's answers go under `## Answers`, verbatim.
- Items become phases, slices and tasks in `phases.md`: task id, item, globs, estimate in minutes and files, the reference project.
- Commit the four documents alone. *By hand:* until `commit-msg` accepts `plan:`, use `docs(flow): plan <what>`.

## 2. Build (skill `dispatch`)

- One slice per builder: its tasks, the builder push block and the writing card, inlined. *By hand:* write the slice from the two documents (item, criterion, cited answers in full, inputs, globs, estimate, reference project).
- A builder commits one task per commit with one `T<n>` in the subject. The git hooks run the secret scan, protected paths, module size, lint and typecheck, and the subject check.
- Before its turn ends a builder writes `state/returns/<slice>.json`. It is a claim.
- Long or silent commands run under `bounded_run`. *By hand:* read `state/audit/liveness/*.hb` and `git log` for progress; there is no `state/status.line` yet.

## 3. Verify (skill `verify`)

- DONE check. *By hand:* every task id of the slice has a commit whose subject carries exactly that `T<n>` and whose diff touches its globs, and the return file names the same ids and SHAs. Otherwise send the slice back.
- Checks. *By hand:* files outside every task's globs, new dependencies or config, time and files against the estimate, duplicated blocks over 20 lines. Put them in the review brief.
- Review: one reader with the review brief. Phase gate: one verdict reader and two skeptic readers, never per slice. `gate_rounds` (default 2) caps the rounds. *By hand:* count the verdict records in the ledger.
- Evidence: one row per criterion in `docs/flow/evidence/P<n>.md`. The minimum class follows from the paths the task touched, and the risk tag may raise it, never lower it: `auth`, `data` and `prod` need live evidence, the rest unit or smoke. *By hand:* hash each capture, compare its size, and read the run log for a finding behind a PASS row.

## 4. Ship (skill `ship`)

- Present the exact deploy command and its side effects in chat; production needs the operator's `approve deploy now`. Then mint with `bash hooks/local/approve-local.sh` and deploy from the main session.
- Run the live rows; write the deploy record in the ledger and one line in `state/deploys/<env>.jsonl`.
- One commit: ledger, deploy line, evidence rows, backlog status. *By hand:* subject `docs(flow): ship <what>`.

## Installing Flow

`python <core>/maintainer/flow.py install --target <project> --providers claude,codex` copies the core, the provider mirrors and the three git hooks, and leaves them uncommitted. Committing them touches protected paths: stage them by name, run `FF_BOOTSTRAP_TTL_MIN=30 bash hooks/local/write-bootstrap-approval.sh`, commit, then run it with `--consume`. Re-running the install is the upgrade within 6.0.

`commit-msg` is still 5.11's: one `T<n>` in the subject, or a `docs:`/`chore:` prefix. Resolving `T<n>` in `phases.md`, the trivial tier and `plan:`/`ship:` arrive with the scripts.
