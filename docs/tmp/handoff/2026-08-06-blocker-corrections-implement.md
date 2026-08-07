# Correction handoff — the 8 BLOCKERs from the DO-NOT-SHIP review

Attest as **AI Developer** under Fusebase Flow v4.7.1. Read
`flow-skills/role-discipline/references/ai-developer.md` and `flow-skills/communication/SKILL.md`
— a delegated session inherits no auto-load.

**Branch** `fix/msys-v3307-hardening`. **Base HEAD** `b3ca22f`. Stop at the gate. Do **NOT** bump
VERSION, tag, push, or deploy. **You are the only session on this branch** — verify with
`git status --short` + `git log --oneline -1` before starting; if HEAD differs or the tree is
dirty beyond untracked `docs/wasted-code/`, STOP and report.

**Full findings:** `docs/specs/backlog-triage-execution/implementation-review.md`.

## Write-time discipline (inlined — not inherited)

| Rule | At write time |
|---|---|
| FR-22 | Tripwire + ≤1-line WHY pointer only. Emit `comment-policy review: applied (FR-22)` per diff |
| FR-25 | `test-cli-flow-recovery.sh` is at 953 — may shrink, never grow. Extract rather than grow any baselined file |
| FR-03 | One coherent commit per group below. Subject: `docs\|chore\|build\|ci\|style\|revert\|merge\|flow` prefix or a T-number |
| FR-13 | `bash -n` everything touched; pre-commit must pass; never `--no-verify` |

Restamp **both** manifests in the same commit as any manifest-collected change.

---

## Group A — T4 sentinel (6 BLOCKERs + 1 test BLOCKER). Commit as `T4a`.

The review's core objection: **the sentinel can act on recycled identities, fail open, miss the
real leak topology, and kill unverified pids.** Every fix below must fail CLOSED.

**B1 — `hooks/tests/run-tests.sh:118`.** `_ff_exit_reap` stops/clears the sentinel *before*
invoking the known-insufficient `taskkill //T`. On any EXIT path that does run, the stronger
cleanup is disabled. **Fix the ordering** so an in-flight sentinel is never cleared before cleanup
completes. Test **both** arms: FIFO-nap active, and nap forced off.

**B2 — `orphan-sentinel.sh:45` + `run-with-timeout.sh:503-508`.** The identity record is only
PID/WinPID/PGID — all recyclable. **Capture a fuller tuple** (add at minimum a start token /
creation time and the executable identity; PPID or SID if available on MSYS) and **fail closed**
when any identity field is missing or does not match at kill time.

**B3 — `orphan-sentinel.sh:52`.** The own-group / harness-group guards **fail open** when either
PGID lookup returns empty. Invert: an empty or unparsable lookup must kill **nothing**. The
comment claims "never an ancestor" — either implement an ancestry check or delete the claim (a
claim wider than the code is the defect class this repo keeps shipping).

**B4 — `orphan-sentinel.sh:56`.** Cleanup returns early unless the recorded group leader is still
alive — but the leaked topology T3 recorded has the leader **dead** with descendants surviving.
**That is the case the sentinel exists for.** Reap by group membership, not leader liveness.

**B5 — `orphan-sentinel.sh:72`.** The native sweep enumerates current PGID members and `taskkill`s
each WinPID with no revalidation against the captured identity. Either remove the sweep or
revalidate every target. Group joiners and PID reuse are collateral risk —
`bounded-run-msys-collateral-kill` is the catalogued precedent.

**B6 — `run-with-timeout.sh:553`.** The child is launched **before** its identity record exists,
and the state write is truncate-then-printf, not atomic. A signal in that window leaves an empty
or partial file; the sentinel then sees "nothing in flight" and the original leak returns. **Make
publication atomic** (write temp + rename) and close the launch-to-record window. The current test
waits until the grandchild exists and never exercises this.

**B7 — `test-run-tests-signal-reap.sh:219` (and 72, 205, 224-225, 293, 314, 335).** Teardown sends
`kill -9` to recorded numeric PIDs after a 25s sleep, with no identity check — the gate itself can
kill an unrelated recycled PID. **Remove every PID-only kill from the test.**

**Discriminators to ADD** (the review: 4 of the current 8 rows are controls that passed pre-fix,
and off-MSYS skips increment PASS — so "8/8" overstates coverage):
- signal arriving during the launch-to-record window;
- dead group leader with surviving descendants;
- PID/group reuse;
- failed PGID lookup ⇒ nothing killed;
- sentinel-wrapper death;
- normal-run output byte comparison (the claim "byte-identical" is currently unproven);
- harness's **own** exit status is 143/130 — the current row records the enclosing `timeout`'s
  status, which can pass independently of the fix.

**Also:** an off-MSYS skip must NOT count as PASS. Report skips separately.

---

## Group B — T9 install document (2 BLOCKERs). Commit as `T9a`.

**B8 — `docs/install-fusebase-cli-project.md:164`.** It states the plugin directories are never
copied, but `hooks/local/lib/managed_content_manifest.py:38-41` still lists three plugin entries,
so the upgrade engine owns and can overwrite them. **Reconcile document and code** — either remove
them from the consumer managed/upgrade set, or correct the document. Do not leave the contradiction.

**B9 — `hooks/local/preflight.sh:335`.** It compares *any* existing consumer plugin's version to
Flow's `VERSION` with no `name == fusebase-flow` guard. The guide targets repos that may already
have their own `.codex-plugin/plugin.json`, so following it can produce an immediate false error.
**Scope the parity check to Flow-owned manifests.**

`preflight.sh` and `managed_content_manifest.py` are consumer-facing engine files — treat this as a
Full-lane change and prove the negative case (a consumer plugin with a different name/version does
not trip preflight).

---

## Group C — evidence and instrumentation hygiene. Commit as `T2a`.

- `state/audit/run-tests-signal-reap/…/summary.md` **still asserts the trap-based conclusion** that
  the README corrected. Fix it; retained evidence that contradicts the ticket misdirects the next
  investigator.
- `cli-flow-recovery-profile.sh:28` — ambient `FFCP_TRACE_FILE` can point at an arbitrary existing
  path which `ffcp_init` truncates. **Constrain trace destinations under the audit root.**
- `:155` — trace append failures are unguarded under the parent's `set -e`, so a disk-full can
  abort before the PASS/FAIL bytes. **Make every trace failure inert.**
- `:129` — the allowlist records values verbatim; a secret in `FF_ONLY` is written to the trace.
  **Redact values**, and record behavior-changing `FFCP_*` overrides.
- Update **both** problem-catalog entries (`run-tests-never-completes-msys`,
  `bounded-run-msys-collateral-kill`) — T4 named them as targets and did not touch them.

---

## Verify before stopping

```
bash -n <each shell file touched>
FF_ONLY=signal-reap,cli-flow-profile,command-policy,install-doc bash hooks/tests/run-tests.sh
bash hooks/local/check-module-size.sh --staged
bash hooks/local/stamp-hook-manifest.sh && bash hooks/local/stamp-managed-content-manifest.sh
```

Scoped runs are **not** release evidence — say so. Do **not** run the full suite. Clean up every
probe process and temp fixture and verify none survive: leaked processes are the defect you are
fixing.

## Report

Per group: commit SHA, files, which BLOCKER each change closes, the new discriminators and their
red-before/green-after, module-size result, and anything you could not do. If a fix turns out to
need a design decision, STOP and report rather than improvising.
