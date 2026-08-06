# Implement handoff — T3, T4, T5

Attest as **AI Developer** under Fusebase Flow v4.7.1 (FR-01..FR-27 + IM.1..IM.18). Read
`flow-skills/role-discipline/references/ai-developer.md` and `flow-skills/communication/SKILL.md`
— a delegated session inherits no auto-load.

**Branch** `fix/msys-v3307-hardening`. **Base HEAD** `685ed77`. Stop at the gate. Do **NOT** bump
VERSION, tag, push, or deploy.

**Authoritative contract:** `docs/specs/backlog-triage-execution/execution-plan.md` §2 (evidence
register + labels), §3 (P1–P10), §6 (task table), §7 (gates G2/G3/G4).

## Write-time discipline (inlined — you do NOT inherit it)

| Rule | At write time |
|---|---|
| FR-22 | Comments: tripwire + ≤1-line WHY pointer only. Emit `comment-policy review: applied (FR-22)` after each diff |
| FR-25 | Ratchet. `hooks/tests/test-cli-flow-recovery.sh` is at **953**; it may shrink, never grow. Extract to a new file rather than growing a baselined one |
| FR-09/18 | Mode B artifacts; replace stale content, never stack old+new |
| FR-03 | One task = one commit. Subject prefix `docs\|chore\|build\|ci\|style\|revert\|merge\|flow` or cite a T-number |
| FR-13 | `bash -n` everything touched; pre-commit must pass; never `--no-verify` |

Restamp **both** manifests in the same commit as any manifest-collected change.

---

## T3 — S2 red arm (reproduction and evidence ONLY; no fix)

**Targets:** new `hooks/tests/test-run-tests-signal-reap.sh`; evidence under
`state/audit/run-tests-signal-reap/<full-head>/`; `docs/backlog/harness-kill-leaves-orphan-children/README.md`; the two platform problem-catalog entries.

**Gate G2:** if the leak does **not** reproduce, mark S2 `BLOCKED-AT-reproduction` and STOP. Do
not patch an unreproduced defect.

### What is VERIFIED (do not re-derive)
- `hooks/tests/run-tests.sh` installs `trap _ff_exit_reap EXIT` only — no TERM/INT handler.
- `FFHC_USE_JOB_OBJECT` defaults to **0** in `hooks/local/lib/run-with-timeout.sh`, and the
  harness never sets it — so the `KILL_ON_JOB_CLOSE` Job Object fence has **never run** in this
  gate. This is the `live-enforcement-inertness` class: a control present, tested, and inert.
- Field observation: a gate killed by an outer `timeout` left three `test-cli-flow-recovery.sh`
  processes alive **38 minutes** later, one *spawned after* the parent died.

### What is UNVERIFIED (E9 — you must settle it)
The bounded phase may be **backgrounded and polled** by the harness rather than run in the
foreground. If so, the "bash defers the EXIT trap behind a foreground command" theory is wrong.
**Establish the actual topology before choosing any mechanism.**

### Build a miniature reproduction
Do **not** use the real 26-minute phase. Construct a small bounded phase (a sleep-like child with
its own grandchild) driven through the same `ffhc_run_bounded*` path, killed by an outer
`timeout` mid-flight. Record and retain, as files:
- full process topology before the kill and at +5s/+30s after (PID, PPID, Windows PID, command
  line) for the harness, the phase child, and its grandchild;
- which of them survive;
- the exact signal sequence observed (TERM, `-k` grace, KILL) and the harness's exit status;
- the same for **SIGINT** (operator Ctrl-C is the more common real case).

Include a **control**: an unrelated sibling `bash`/`sleep` started independently must be present
in every capture, so a later fix can be shown not to kill it.

The test emits `PASS: signal-reap <name>` / `FAIL: signal-reap <name>`; exit = fail count. Register
tag `signal-reap` in `FF_TAGS` + a `run_shell_phase` line, but **leave it unwired as a required
green gate** — at T3 it is expected to fail. State that in the file header.

Update the backlog ticket and cross-link `bounded-run-msys-collateral-kill` and
`run-tests-never-completes-msys` with what the topology showed.

---

## T4 — S2 fix (only after T3 reproduces)

**Targets:** `hooks/tests/run-tests.sh`; the existing scoped identity/timeout helper **only where
T3 proves it is needed**; the T3 test wired green; both catalog entries.

Design the mechanism from T3's evidence, not from any theory in this handoff. If T3 shows the
trap cannot run in time, a trap is not the answer — say so and use what the evidence supports
(child-side parent-death detection, the existing Job Object fence, or a supervisor).

**Required semantics.**
- Cleanup deadline: reuse the existing `FFHC_TIMEOUT_KILL_GRACE` (default 5s). Do not introduce a
  second grace constant.
- Identity revalidation before any kill — recorded bash PID, Windows PID and command line must
  still match. A PID-reuse mismatch must kill **nothing**.
- Signal-correct exit status: 143 for TERM, 130 for INT (or restore the default disposition and
  re-signal).
- Tear down any helper/heartbeat process you started.

**Control set — all must hold, and the failures matter as much as the passes.**
1. Target child **and grandchild** gone within grace.
2. Caller shell survives.
3. A **same-executable** sibling outside the target tree survives (not just any sibling).
4. PID-reuse mismatch simulation → no kill.
5. Normal exit performs **no** kill (behaviour byte-identical to today).
6. Stable across repeated runs.

**Collateral-kill history is real** — `docs/problem-catalog/bounded-run-msys-collateral-kill/problem.md`
records over-broad MSYS tree termination that killed unrelated sessions. Never widen to a bare
`taskkill //T` on an ancestor.

---

## T5 — FR-06 command-gate semantic corpus (NO parser patch)

**Targets:** `docs/backlog/command-gate-shell-evasion/README.md`; new
`hooks/tests/fixtures/command-gate-semantic-corpus.json`; `hooks/tests/test-command-policy.sh`.

**P8: corpus and decision record ONLY.** You are explicitly **not** authorized to change
`policies/command-policy.yml` or any matching logic. The roadmap forbids shipping a partial shell
parser, and three prior narrow fixes each opened another hole.

Build a corpus of command strings with, for each: the raw string, whether it *should* be gated,
which rule ought to match, and the evasion class (quote-splitting, dynamic construction,
whitespace, path form, comment/heredoc, encoding). Include **true negatives** that must NOT gate
(`docker run --rm image`, `npm rm pkg`, `git rm x`, `charm`).

Wire it into `test-command-policy.sh` as a **reporting** matrix: it records current behaviour per
case (gated / not gated) and asserts only that the corpus parses and every entry has a verdict.
It must **not** fail the build for cases the shipped regex misses — those are the documented gap,
and turning them red now would force exactly the rushed parser patch that is forbidden.

Record in the ticket: the counts by class, which cases the current rules already catch, and the
two decisions an operator must lock before any parser work (false-positive tolerance, and whether
a conservative deny is acceptable).

---

## Verify before stopping

```
bash -n <each shell file touched>
FF_ONLY=signal-reap,command-policy bash hooks/tests/run-tests.sh     # scoped, label it as such
bash hooks/local/check-module-size.sh --staged
bash hooks/local/stamp-hook-manifest.sh && bash hooks/local/stamp-managed-content-manifest.sh
```

Do **not** run the full suite (`cli-flow-recovery` alone is ~26 min and its bound is a known open
defect). Scoped runs are not release evidence — say so when you report them.

## Report back

Per task: T-number, commit SHA, files, discriminator evidence (red before / green after, or for
T3 the retained topology), module-size result, and anything you could not do. If T3 fails to
reproduce → `BLOCKED-AT-reproduction`, stop, report. A transient provider error is a dispatch
failure, not a task verdict — retry it.
