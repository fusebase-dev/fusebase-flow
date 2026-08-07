# Implementation review — 2026-08-06 (Codex gpt-5.6-sol, xhigh)

**Verdict: `DO-NOT-SHIP`.** Reviewed `cd094ed..b0b33b3`. 8 BLOCKERs, concentrated in T4.
Nothing was gated or released. The full unscoped gate was deliberately NOT run — gating code
the review rejects would waste ~2h and produce evidence for a tree that must change.

## Findings

1. BLOCKER | hooks/tests/run-tests.sh:118 | `_ff_exit_reap` stops and clears the sentinel before invoking the known-insufficient Win32 tree kill | On any EXIT path that actually runs—including the documented FIFO-nap fallback—the stronger cleanup is disabled and descendants can leak | verified from call order at lines 118–121, `_ff_sentinel_stop` at 149–155, and T3’s recorded `taskkill //T` failure.

2. BLOCKER | hooks/tests/lib/orphan-sentinel.sh:45 | the “identity tuple” is only PID, WinPID, and PGID; no start token, PPID, SID, Windows creation token, parent identity, or executable identity is captured | PID+PGID+WinPID can all be recycled, so lines 64/70 can signal an unrelated process group; this directly violates the locked S2 tuple | verified against the three-field state writer at `run-with-timeout.sh:503-508` and S2’s required identity fields.

3. BLOCKER | hooks/tests/lib/orphan-sentinel.sh:52 | the own/harness-group checks fail open when either PGID lookup is empty, and no ancestor or descendant relationship is checked | A lookup failure removes the caller-group guard; the comment “never an ancestor” has no implementing logic | verified by the conditional harness comparison at line 54 and absence of any PPID/SID/ancestry validation.

4. BLOCKER | hooks/tests/lib/orphan-sentinel.sh:56 | cleanup requires the recorded group leader to remain alive | A process group can retain leaking descendants after its leader exits—the exact MSYS topology T3 demonstrated—yet the sentinel returns without killing anything | verified from the early `alive "$cpid" || return` and R3’s wrapper-dead/descendants-alive evidence.

5. BLOCKER | hooks/tests/lib/orphan-sentinel.sh:72 | the native sweep enumerates every current member of the PGID and `taskkill`s each WinPID without captured-identity revalidation | Group joiners or group/PID reuse can be collateral-killed; these are explicitly “unverified pids” despite the commit’s opposite claim | verified from `ps … '$3==g {print $4}'` followed directly by `taskkill //PID`.

6. BLOCKER | hooks/local/lib/run-with-timeout.sh:553 | the child is launched before its identity record exists, and the state write is truncate-then-printf rather than atomic | A TERM/INT during WinPID/PGID capture leaves an empty or partial state file; the sentinel sees a dead harness with “nothing in flight” and recreates the original orphan leak | verified from launch at 542–553, external identity probes at 556/565, state write at 566, and sentinel empty-state handling at 87–97. The test waits until the grandchild exists and never exercises this window.

7. BLOCKER | hooks/tests/test-run-tests-signal-reap.sh:219 | test teardown sleeps 25 seconds after the target PIDs die, then sends `kill -9` to the old numeric PIDs without identity checks | A reused PID can cause the gate itself to kill an unrelated process; similar unverified kills occur at lines 72, 205, 224–225, 293, 314, and 335 | verified by tracing every test kill path.

8. MAJOR | hooks/tests/test-run-tests-signal-reap.sh:275 | `signal-exit-status` records the enclosing GNU `timeout` status after signaling its group, not the harness’s status | 143/130 can pass independently of sentinel behavior; the production code installs no TERM/INT handler that establishes the claimed harness exit contract | verified from the subshell/timeout wrapper at 279–295 and the T3→T4 test rewrite.

9. MAJOR | hooks/tests/test-run-tests-signal-reap.sh:33 | four of eight rows are controls that passed pre-fix, while off-MSYS “skip” increments PASS | “8/8” materially overstates discriminating coverage | verified by T3’s committed 4/8 report and the final control definitions: sibling TERM, sibling INT, normal exit, PID mismatch.

10. MAJOR | hooks/tests/run-tests.sh:145 | the sentinel is externally capped at six hours and identified only by PID when stopped | It can outlive the run after harness-PID reuse, become uncapped if the timeout wrapper dies, or have `_ff_sentinel_stop` signal a recycled wrapper PID | verified from the external cap, PID-only `kill` at line 152, and absence of harness/sentinel start-token checks.

11. MAJOR | hooks/local/lib/run-with-timeout.sh:495 | “DEFAULT-INERT” is false: PGID capture is unconditional and uses external `cat` plus `awk` for every bounded call | Normal behavior/timing changes for the health and upgrade engines even when no sentinel state exists; on MSYS this adds costly spawns | verified from unconditional lines 564–566 and the actual implementation at 499–502.

12. MAJOR | hooks/tests/run-tests.sh:124 | S2’s required cleanup diagnostic was not implemented | The sentinel is launched with stdout/stderr discarded and emits no signal, identity, result, or next-action diagnostic, so failures are silent | verified from launch redirection at 145–146 and the sentinel’s absence of diagnostic output.

13. MAJOR | state/audit/run-tests-signal-reap/1b28ee296d00982629129ea01edf28686a080dc7/summary.md:41 | retained evidence still says the trap is viable and prescribes a trap-based fix | It contradicts the final README and can misdirect the next investigator—the precise failure `15f4126` was meant to correct | verified against `docs/backlog/harness-kill-leaves-orphan-children/README.md:48-59`.

14. MAJOR | hooks/tests/test-run-tests-signal-reap.sh:48 | evidence is keyed only by HEAD and written to one fixed `topology.tsv`, without dirty-tree identity or a unique run ID | Concurrent sessions at the same parent SHA can truncate/interleave evidence, and T4’s pre-commit 8/8 trace is labeled with parent `15f4126`, not the code it tested | verified from lines 48–51/147–148 and the absence of any retained artifact under final commit `6deb143` or `b0b33b3`.

15. MAJOR | docs/problem-catalog/run-tests-never-completes-msys/problem.md:28 | T4 did not update either required problem-catalog owner | The final catalog still says the external-signal residual is open and points only to T3, demonstrating a half-applied T4 target set | verified from commit `6deb143`’s changed-file list and final lines 28–38.

16. MAJOR | hooks/tests/lib/cli-flow-recovery-profile.sh:28 | ambient `FFCP_TRACE_FILE` can choose an arbitrary existing path, which `ffcp_init` truncates | Instrumentation can mutate unrelated files and introduce shared state, violating P1 and the claim that non-allowlisted environment names are not read | verified from lines 28, 109–117.

17. MAJOR | hooks/tests/lib/cli-flow-recovery-profile.sh:155 | trace append failures are not neutralized | Under the parent’s `set -e`, a disk-full/permission failure after successful initialization can abort before the original PASS/FAIL bytes, so instrumentation changes verdict behavior | verified from the unguarded append in `ffcp_event` and the harness’s `set -euo pipefail`.

18. MAJOR | hooks/tests/lib/cli-flow-recovery-profile.sh:140 | only completed interval rows exist; no explicit scenario/substep start event is emitted | G1 and S3A require named start and completion events, and later stall semantics cannot reset at actual starts from this schema | verified from `ffcp_event`, `ffcp_substep`, and `pass`/`fail`; every row is written only after the interval.

19. MAJOR | hooks/tests/lib/cli-flow-recovery-profile.sh:129 | exact-name allowlisting does not redact values and omits behavior-changing `FFCP_*` controls | A secret placed in allowed `FF_ONLY` is recorded verbatim, while trace-path overrides affect behavior without provenance | verified from indirect value expansion at 129–133 and the redaction test, which tests only non-allowlisted names.

20. BLOCKER | docs/install-fusebase-cli-project.md:164 | plugin directories are documented as “never copied,” but the upgrade engine still owns them | A consumer’s plugin manifests can later be copied or overwritten by Flow; this contradicts the installation contract | verified from `hooks/local/lib/managed_content_manifest.py:38-41` and the managed manifest’s three plugin entries.

21. BLOCKER | hooks/local/preflight.sh:335 | preflight compares any existing consumer plugin’s version to Flow’s `VERSION` | The guide specifically targets projects that may already have `.codex-plugin/plugin.json`; following it can immediately produce a false preflight error | verified from unconditional existence-based checks at 335–352, with no `name == fusebase-flow` guard.

22. MAJOR | hooks/tests/test-install-fusebase-cli-project-doc.sh:6 | the T9 discriminator is static and explicitly does not run an install | It cannot prove shell destination semantics, collisions, recovery, or successful mirror regeneration, contrary to S1’s required scratch install for both shells | verified from lines 6–11 and the source-set-only comparison at 64–80.

23. MAJOR | hooks/tests/fixtures/corpus/command-gate-semantic-corpus.json:86 | boolean `should_gate` values are assigned to commands whose behavior is unknowable without environment/files, while contested cases are fixed to false | This silently locks D2/policy choices despite the ticket saying `NO IMPLEMENTABLE DECISION` | verified with DC-02/DC-07..14, AB-01..07, and explicitly contested TN-24/TN-26.

24. MAJOR | hooks/tests/test-command-policy.sh:435 | the corpus driver exercises only core `evaluate()` | S4 required handler parity per case; neither handler is run or recorded by the corpus matrix | verified from the sole evaluate call at line 497 and absence of handler fields in the corpus contract.

25. MAJOR | docs/tmp/handoff.md:10 | G0’s replacement `Next` contract is false and now stale | It names T1, G0, and T2 instead of exactly T2, and still points at pre-T1 HEAD after T1–T5 landed; session initiation can repeat completed work | verified from lines 4–12 against S0’s replacement-field table.

26. MAJOR | docs/backlog/gate-bounds-lack-headroom/README.md:3 | T1 updated the index but left multiple ticket owners at contradictory statuses | Future sessions opening individual tickets see `parked` while the index/plan says active or not planned; affected owners include gate bounds, architect sub-agent, role path, FR22/FR27 follow-ups, repair trust root, and install-existing | verified by comparing each README status line with `docs/backlog/index.md:12-24,33`.

27. MINOR | hooks/tests/lib/orphan-sentinel.sh:2 | the 22-line header duplicates T3 history and rationale already stored in the ticket/evidence | It violates FR-22’s tripwire-plus-pointer rule and increases future context cost; commit `6deb143` claimed comment-policy review applied | verified semantically against the comment policy and the linked README.

## Required before the gate

1. Replace the three-field sentinel record with the complete locked POSIX/Windows identity tuple and fail closed on every missing identity or group value.
2. Eliminate the launch-to-record race using a supervisor/handshake or equivalent design that owns the child before the harness becomes kill-vulnerable; make state publication atomic.
3. Fix EXIT ordering so an in-flight sentinel is never cleared before cleanup; test both FIFO-nap-active and forced-fallback arms.
4. Remove the unverified native PGID sweep or capture and revalidate every target; remove all PID-only cleanup kills from the regression test.
5. Add real discriminators for early signal, dead group leader with surviving descendants, PID/group reuse, failed PGID lookup, sentinel-wrapper death, normal-output byte comparison, diagnostics, and direct harness 143/130 status.
6. Persist unique-run, exact-tree evidence with full HEAD plus dirty/diff identity; correct the retained summary and both problem-catalog entries.
7. Constrain trace destinations under the designated audit root, make all trace failures inert, redact sensitive values, record every behavior-changing override, and emit explicit start/completion events.
8. Remove publisher plugin directories from the consumer managed/upgrade set and scope preflight parity checks to Flow-owned manifests; then execute scratch Bash and PowerShell installs.
9. Convert corpus verdicts that depend on files/environment/operator policy to explicit `unknown`/decision-dependent cases, obtain the D1/D2 locks, and record both handler outcomes per case.
10. Supersede the active handoff and synchronize every affected ticket README with the authoritative index.
11. Restamp/reverify manifests, rerun FR-25 and mirror checks, then run unscoped Windows/MSYS and Linux gates on one exact committed SHA with committed defaults.

## What I could NOT verify

- I could not execute Git-Bash/MSYS probes: this sandbox rejects Bash startup with `CreateFileMapping … Win32 error 5`.
- I therefore could not independently reproduce the FIFO trap timing, the claimed 8/8 run, or a full unscoped Windows gate.
- I could not run the Linux `ubuntu:24.04` gate here.
- The T3/T4 evidence is gitignored, fixed-name, and not bound to the tested dirty tree, so its process measurements cannot be independently reconstructed from the branch alone.
- The unrelated untracked `docs/wasted-code/` directory was excluded and left untouched.

---
Phase: Verify
Ticket: backlog-triage-execution
Next: correct the blockers before starting the final gate.
