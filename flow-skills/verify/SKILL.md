---
name: verify
description: Load when a slice or a phase reaches verification. DONE check, review and skeptic briefs, evidence rows, live-run and flaky rules, gate rounds. Planner only.
---

# Verify

The planner runs this skill. Reviewers, skeptics and the verdict writer run as `reader` (Read, Glob, Grep only) and receive only the briefs at the end of this file.

## A slice

1. Run `python hooks/local/gate.py <slice>`. It runs the DONE check (`done.py`), the four flags (`checks.py`) and the evidence-row validator (`validate_evidence.py`), and writes `state/gate/<slice>.txt`; exit 1 is a failed check, 3 `BLOCKED-AT-gate-budget`.
2. DONE check failed (a task with no commit whose subject carries exactly its `T<n>` and whose diff touches its globs, or a missing or disagreeing `state/returns/<slice>.json`): send the slice back to build with its open tasks. Review never starts on PARTIAL work.
3. Review: dispatch one `reader` with the output of `python hooks/local/slice.py <slice> --brief review`. It carries the flag rows and the gate output inline. On Codex the reader runs as `bounded_run 900 reader -- codex exec -s read-only --output-schema <schema.json> -o state/returns/<slice>-<role>.json "<brief>"` (Codex: unproven).
4. Record the return in the ledger: `review <slice> result=PASS|FAIL agent=<reader agent id>`, FAIL when a finding goes back to build. Rule every flag: write `upheld` or `rejected` in the `ruling` column of `state/flags/<slice>.tsv`; a re-run keeps it and any column you add, and a flag that stops firing stays, marked `[stale]`. `python hooks/local/checks.py --precision` counts them. Flags never block. Two holds exist, each released by your ruling: a rubric "yes" on a risk-tagged item, and the DONE send-back.

## A phase gate

- Starts only when every slice in the phase is DONE.
- One verdict writer and two skeptics, all `reader`, per phase gate, never per slice. Each returns typed. A reader cannot write, so you record the verdict in the ledger with the verdict agent's id.
- FAIL stays FAIL. Never relabel a row.

## Rounds

- `gate_rounds` (default 2) lives in `policies/approval-policy.yml`. `gate.py` counts rounds from the `verdict <slice|phase>` and `review <slice>` records in the ledger; you keep no count by hand.
- A round is one verdict dispatch after the gate script passes. A script failure costs no round.
- Review rounds share the limit and keep their own counter.
- A local override may lower the limit, never raise it. Raising it is a protected-policy edit the operator approves.
- At the limit: `BLOCKED-AT-gate-budget`. Draft the numbered carry-over list, security, privacy, data-loss and owner-answer contradictions first; the operator closes. An unattended run closes only when the operator authorized that beforehand.

## Evidence rows

- `evidence.md`: one row per criterion id with its status (`PASS`, `FAIL: <why>` or `BLOCKED-AT-<reason>`, the policy's `row_status`; a run that hit its deadline is a FAIL), the capture's path, sha256 and size, and the run log path. A test-id row cites `<file path>::<test name>` and a TAP log in the run directory. The builder writes rows as claims. The validator hashes captures in place and checks run logs and test ids. The verdict comes from the reader's return, recorded by you.
- The minimum evidence class follows from the paths the task touched (`policies/evidence-classes.yml`); the risk tag may raise it, never lower it. `auth`, `data` and `production` need live evidence; the rest unit or smoke.
- Flow defines no capture folder: captures and diagnostics stay where the test tool writes them, and `state/runs/<phase>/index.tsv` holds one line per run: `run_id`, `started`, `dir`, `rc`, tab-separated. The run log is the tool's own: the live runner's run-directory `README.md` (`| Time (UTC) | Row | Record |`), a TAP log for test-id rows. Attempts, the contract commit and the rows run under each commit go in the run log. Never commit screenshots or raw run output; the row cites the path.

## Live evidence

S<n> below means one live row of `evidence.md`.

- A live row passes only when the operator-visible outcome happens on the deployed surface and its ground-truth diagnostic (log, request dump, DB row, response body, job trace) shows no hidden error. Exit code 0, a hash, a running service or an auth check are supporting checks, never a pass.
- Interactive UI: complete the real primary action (submit, save, send, authenticate, search or filter). A render or screenshot alone is a probe.
- Run the named harness, or the script written for this live run; a weaker manual or static check never replaces it. If it cannot run, the row is `FAIL` and its `Note` says why (operator smoke pending), never PASS.
- Before a browser run, fix one user flow (route, start state, action, expected result), the viewport, stable or accessible locators, unique test data and who cleans it up, the auth plan, the backend diagnostic, and external side effects (sandbox, approval or forbidden).
- Never assert counts or empty states for data the run did not create.
- Check browser and backend: an error on either surface is FAIL. Read the diagnostic after the action, waiting for logs written after exit. The CLI's log skills (`remote-logs`, `dev-debug-logs`) give the diagnostics.
- A type or iteration error: get the full traceback first. A failure: list three candidate causes, then one probe that tells them apart. Add one adversarial probe: what would still be broken if the static checks passed?
- End to end not feasible: `PENDING-OPERATOR-SMOKE` with the missing prerequisite and the exact steps for the operator. Never PASS.
- Record, then read: let the run finish and read its records once. No durable record is an observability-gap finding; do not compensate by watching. Diff screenshots by script; view the ones it flags and always the one a verdict rests on.
- Before the phase closes, delete the test data this item created and keep shared fixtures; redact or delete any capture that recorded operator-session content (a redacted capture's row cites its new sha256 and size); clean up external side effects, or record each one kept on purpose with its approval. Keep the evidence the rows cite; `git status` shows no stray artifact.

### Flaky-result semantics (FAIL-then-PASS is not PASS)

A smoke S<n> that FAILs and then PASSes on retry is **FLAKY**, not PASS. Retrying until green
launders a real defect (race, ordering dependency, state leak, async timing) into a false-green ship.

- Record every attempt in the run log: `S<n> attempt 1: FAIL <observed>; attempt 2: PASS` —
  never overwrite or omit the first result.
- FLAKY resolves only when the first failure is **reproduced-or-explained**:
  - **Reproduced:** same conditions re-trigger the failure → real bug. Route to
    Sub-mode C (below) (deterministic-system branch); the S<n>
    verdict is FAIL.
  - **Explained:** a named, evidenced external cause (deploy-propagation delay confirmed in the
    platform log; cold-start timeout visible in `remote-logs`) with the ground-truth diagnostic
    ATTACHED in the tool's native output, cited by an evidence row with path, sha256 and size;
    then 3/3 clean under the same conditions after the cause clears before any PASS (matches Sub-mode C (below)
    Explained-external). "Probably a network blip" with no diagnostic is not an explanation.
- Until one of those holds, report `S<n>: FLAKY (unresolved)` — it counts as FAIL against the
  smoke threshold and blocks DONE like any FAIL.
- Reproduction mechanics and the deterministic-vs-model-variance verdict split live in
  Sub-mode C (below).

### Live-run discipline (reruns, waits, evidence standard)

- **Freeze the standard per gate.** Before the first live run, commit pending smoke-contract edits and record the contract's commit (`git log -1 --format=%H -- backlog.md`) in the run log. A mid-gate tightening applies to rows not yet run and to the next gate: commit it and record the new contract commit in the run log with the rows run under each commit. Re-prove an already-PASSed row only when the tightening shows its evidence missed its own pass criterion, and name those rows in the run log.
- **Run past a failure.** After a FAIL, run every remaining independent S<n>. A row that needs state or data another row creates is dependent: if that row failed, record `S<n>: BLOCKED-BY S<k>` (not-PASS against the threshold); never run it on missing setup.
- **Audit waits once.** After the first timing failure, check every harness wait in one pass and correct all short waits together — never one wait per live launch. A wait on the operator-visible outcome is short only when stricter than the product's latency criterion (with no stated criterion, never) and is raised at most to that criterion, never past it; a wait on harness setup is short when below the setup latency the ground-truth diagnostic recorded (log or network timestamps). Short waits on product-finding rows (next bullet) are corrected in the same pass, raised at most to the criterion; the row stays a product finding on its recorded latency.
- **Harness wait vs product failure.** The product's own latency criterion (the item's criterion or S<n> pass criterion) stays binding. A timing FAIL is harness-only ONLY with the recorded latency ATTACHED showing the harness wait was stricter than that criterion and the latency above the wait but within the product's stated criterion, or showing the wait timed something explicitly outside its scope (harness setup, not the operator-visible outcome); with no stated criterion only a wait on harness setup qualifies. Then correct the wait per the audit and keep the original FAIL in the evidence. Naming an infrastructure cause (cold start, platform or dev-environment latency) is never enough. A recorded latency over the criterion is a product finding whatever the wait was, as is any timing FAIL without that evidence: Sub-mode C (below) applies, an external cause clears it only under the Explained-external conditions (§ Flaky-result "Explained"), the original FAIL stays, and product timeouts and retries are never lengthened.
- **Fakes need real timing.** A stub or fake service the harness controls runs with a latency mode set from measured real latency; an instant fake never exercises the harness waits.
- **Rerun after a fix.** Rerun the failed and BLOCKED-BY rows, then one whole S1..Sn run on the final deploy; the reported ratio comes from that whole run, where a row still `FLAKY (unresolved)` counts as FAIL. A rerun after a change that targets that row's failure verifies the fix (a wait change counts only through the harness-only evidence above); FAIL-then-PASS with no such change stays FLAKY.

### Sub-mode C — Reproducibility before fix

1. Operator reports single observed failure ("the system did X").
2. Classify the system under test FIRST — the verdict rules differ:
   - **DETERMINISTIC app code:** ordinary application/backend/UI logic — same inputs are supposed
     to give same outputs. Async timing, job ordering, and shared state make the *reproduction
     rate* vary, not the bug's reality.
   - **LLM / agent behavior:** the failure is in model output or agent-path choice, where
     run-to-run variance is inherent.
3. For the reproducing test or probe, reproduce 3 times under the same conditions. Verdicts:

   | System type | 3/3 | 1/3 or 2/3 | 0/3 |
   |---|---|---|---|
   | Deterministic app code | Systemic → a new backlog item | **REAL bug** — intermittent ≠ nonexistent. Route to flaky/race investigation: capture `dev-debug-logs` (local) or `remote-logs` (deployed) evidence from a failing run; hunt ordering/timing/state-leak causes. NEVER no-op close. Sole escape — Explained-external (mirrors § Flaky-result "Explained" above): a NAMED external cause (third-party outage, deploy-propagation delay, cold start) with the ground-truth diagnostic ATTACHED to the ticket evidence; then 3/3 clean under the same conditions after the cause clears before any PASS/close. Bare "couldn't reproduce twice" with no attached diagnostic = REAL bug. | Not reproduced — record exact attempted conditions; vary ONE plausible condition (data state, timing, concurrency) for one more round before recommending close |
   | LLM / agent behavior | Systemic → a new backlog item (prompt/tooling/guard) | Model variance — document and recommend no-op close | Close as no-op-needed with attempts documented |

   A partial reproduction of deterministic code is the most-laundered bug class: "couldn't
   reproduce twice" reads as noise but is a race/state bug waiting for a client.
4. Record the attempts in the run log with commands, inputs and observed outputs.

## Briefs

`python hooks/local/slice.py <slice|phase> --brief review|skeptic|verdict` prints these blocks with the slice's or phase's data filled in. A brief carries no Flow rule text and states no expected verdict.

```text
REVIEW BRIEF
Slice <slice> at <sha>. Below: the backlog item's criterion and answers, the task globs, the reference project, the gate output and the flag rows.
For each changed function or branch, look for a reachable defect: empty, zero, one or maximum inputs and off-by-one; a failing call that is swallowed or half-applied; shared state, check-then-act windows and retries that apply twice; external input used unvalidated; resources not released on every path.
For tests: changed production behaviour with no test; an assertion that never compares output with the expected value; assertions on a mock instead of the changed logic; only the happy path where the diff added error or edge branches.
If code was moved out of a file to keep it under the size ceiling: does the new file's name state one responsibility?
Severity. BLOCKER: a defect reachable on a production path; any test gap above on changed production behaviour; moved code in a file whose name states no responsibility (utils2, helpers2, misc, extra, more). Other findings, including those cases only in test or dev scaffolding and a named but weak seam: HIGH a serious correctness or security risk, MEDIUM a bounded functional defect, LOW an improvement. A grade never replaces BLOCKER for the cases above. For a missing test, name the case; do not write it.
Answer two questions, one line of evidence each:
(a) Does the diff add a feature the criterion does not ask for?
(b) Is the diff further from the reference project's pattern than the task requires?
Return JSON: {"findings": [{"file", "line", "input", "wrong_outcome", "expected", "severity": "BLOCKER|HIGH|MEDIUM|LOW", "class": "security|privacy|data-loss|owner-answer|other"}], "rubric": {"a": "yes|no", "a_evidence", "b": "yes|no", "b_evidence"}, "examined": ["<suspect path>: <why it holds>", "<suspect path>: <why it holds>"]}
```

```text
SKEPTIC BRIEF
Phase <phase> at <sha>. Below: each criterion with its evidence row, capture path and digest, run log and the gate output.
For each row: did it run on a real input; was the observed output compared with the expected one; could a reader reproduce the run from the row alone?
Return JSON: {"rows": [{"criterion", "holds": "yes|no", "evidence": "<one line>"}], "other_findings": []}
```

```text
VERDICT BRIEF
Phase <phase> at <sha>. Below: each criterion with its evidence row, capture path and digest, run log, the gate output and both skeptic returns.
Decide each row from its capture and run log.
Return JSON: {"rows": [{"criterion", "status": "PASS|FAIL", "evidence": "<one line>"}]}
```
