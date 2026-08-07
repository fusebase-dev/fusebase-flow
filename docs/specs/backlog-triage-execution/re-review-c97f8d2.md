# Re-review of the corrected tip — 2026-08-07 (Codex gpt-5.6-sol, xhigh)

Reviewed `b0b33b3..c97f8d2`. **Verdict: `STILL-DO-NOT-SHIP`** — 3 CLOSED, 3 PARTIAL, 2 NOT CLOSED.
The full unscoped gate was NOT run: two blockers remain open.

VERDICT: STILL-DO-NOT-SHIP

## Blocker closure

| # | Status | file:line verified | note |
|---:|---|---|---|
| 1 | CLOSED | `hooks/tests/run-tests.sh:140-145` | `_ff_reap_in_flight` now precedes `taskkill` and `_ff_sentinel_stop`. The inconclusive test row is not closure evidence; the shipped ordering is. |
| 2 | PARTIAL | `hooks/tests/lib/orphan-reap.sh:18-25,120-134,230-266`; `hooks/tests/lib/orphan-sentinel.sh:30-50` | A leader start token is cached, materially improving reuse protection. The locked tuple—child start/PPID/SID/executable plus Windows creation/parent/executable identity—is still absent. Native members have no captured identity. |
| 3 | CLOSED | `hooks/tests/lib/orphan-reap.sh:137-155,203-217` | Empty/unparseable own or harness PGIDs refuse the kill. `ffor_is_ancestor` is implemented correctly: absent snapshot, unresolved living link, and 32-hop exhaustion all return “unsafe/refuse”; only a proven chain end returns safe. No direct ancestor discriminator exists. |
| 4 | PARTIAL | `hooks/tests/lib/orphan-reap.sh:219-235`; `hooks/tests/lib/orphan-sentinel.sh:30-50` | `ffor_reap` no longer requires a live leader, but needs a previously cached leader token. The state record does not contain that token; if the leader dies before the sentinel’s one-second poll resolves it, cleanup still has no usable identity. |
| 5 | NOT CLOSED | `hooks/tests/lib/orphan-reap.sh:237-266` | The delayed group SIGKILL is unconditionally issued without revalidation. The native sweep captures WinPID/PGID from a fresh snapshot and then “revalidates” against that same snapshot—not against pre-kill captured identity. |
| 6 | NOT CLOSED | `hooks/local/lib/run-with-timeout.sh:513-526,570-592`; `hooks/tests/lib/orphan-reap.sh:104-117` | Child launch still precedes the first record. Append+terminator detects some tears but is not atomic; append failures are ignored. A torn first append leaves no complete record, and a later tear can make the reader select an older complete record. |
| 7 | PARTIAL | `hooks/tests/lib/signal-reap-fixture.sh:14-40`; `hooks/tests/test-run-tests-signal-reap.sh:145-162` | Direct PID teardown now uses start-token verification. The delayed `kill -KILL -"$HARNESS_PGID"` still acts on an unrevalidated numeric group after sleeping for the grace period. |
| 8 | CLOSED | `hooks/local/lib/managed_content_manifest.py:38-55`; `hooks/local/upgrade.sh:323-355`; `hooks/local/preflight.sh:335-369`; `hooks/local/lib/partial-upgrade-check.sh:50-69` | Plugin directories are outside both managed sets, including the legacy fallback. Plugin and marketplace parity checks now require `name == fusebase-flow`. |

## The B6 deviation

It is not crash-safe.

`printf >>` plus `END` is tear-detecting, not atomic publication. Regular-file append does not guarantee the complete logical record under interruption, I/O failure, or filesystem failure. `ffor_state_read` ignores an incomplete tail, which means:

- A torn first PID append produces “nothing in flight.”
- A torn later append leaves the previous complete record authoritative.
- A failed clear or append can expose a stale record because all write failures are swallowed.
- The launch-to-first-append window remains at `run-with-timeout.sh:570-575`; it was shortened, not closed.

The performance rationale is substantially true: the harness has approximately 46 bounded phases, and two rename-backed publications per phase would mean roughly 92 additional MSYS `mv` spawns. That explains avoiding naïve per-publication `mv`; it does not make append atomic. A persistent supervisor/handshake or equivalent ownership mechanism is still required.

The `launch-window-signal-still-reaps` test only delays the WinPID probe after the first append (`test-run-tests-signal-reap.sh:285-303`). It does not interrupt, tear, or fail the first append.

## The re-scoped row — legitimate or moved goalpost

Legitimate scope correction, not a moved goalpost: the harness-side EXIT path is best-effort inside the outer `-k` grace; the out-of-band sentinel is the intended guarantee. A trap killed before `ffor_reap` returns cannot honestly prove or disprove the ordering.

But the row is not green—it is inconclusive—and therefore cannot be cited as closure evidence. A deterministic call-order discriminator is still missing.

The SIGINT analysis is only half acceptable:

- Correct: adding `trap … INT` alone cannot deliver 130 while the FIFO `read -t` defers trap handling.
- Unproven: that it would necessarily “make things worse”; the evidence only establishes that it does not solve the contract.
- Not acceptable: treating INT=130 as a non-finding. It remains locked at `execution-plan.md:122-136,250`. `test-run-tests-signal-reap.sh:471` parks it as inconclusive, while `run-tests.sh:355-376` ignores inconclusive shell-test rows. That is an open acceptance failure capable of disappearing inside a green full-gate total.

## Coverage honesty — discriminators vs controls

Of the reported 19 PASS rows:

| Class | Count | Rows |
|---|---:|---|
| Genuine pre-`91f8748` discriminators | 4 | `launch-window-signal-still-reaps`; `failed-pgid-lookup-kills-nothing`; `group-identity-mismatch-kills-nothing`; `dead-leader-descendants-reaped` |
| Explicitly labelled controls | 8 | The eight `[CONTROL]` rows |
| Labelled discriminator but would pass `b0b33b3` behavior | 7 | TERM child; TERM grandchild; INT cleanup; sentinel wrapper survival; sentinel exit; TERM default exit status; normal-output byte comparison |

Therefore: **4 discriminators, 15 controls**. The EXIT-path row and INT exit-status row are outside the 19 because both were inconclusive.

The old `b0b33b3` test already exercised and passed TERM child/grandchild, INT cleanup, sibling survival, normal exit, and PID mismatch. The wrapper-death rows follow the old sentinel’s already-working live-leader path; TERM=143 is default signal behavior; output equality is unaffected by the correction.

## New defects introduced

- `orphan-reap.sh:239-266` worsens the collateral window by issuing group SIGKILL unconditionally after the grace period, then sweeping native members without captured per-member identity.
- `cli-flow-recovery-profile.sh:142-175` performs lexical containment only. A symlink beneath `state/audit` can redirect `: > "$FFCP_TRACE_FILE"` outside the audit root. Tests cover direct outside paths and `..`, not symlinks.
- `cli-flow-recovery-profile.sh:60-64` claims “number plus optional unit,” but `[0-9]*` accepts any lowercase alphanumeric value beginning with a digit. Such a secret-shaped value is recorded verbatim.
- No new semantic defect was found in `preflight.sh`, `managed_content_manifest.py`, `upgrade.sh`, or `partial-upgrade-check.sh` for plugin ownership. Their behavioral coverage remains incomplete: no PowerShell scratch install and no real upgrade transition is executed.
- Both manifests are fresh at `c97f8d2`: hook manifest `MATCH` with 146 assets; managed-content manifest `MATCH` with 294 assets.
- No FR-25 violation: direct `module_size.py --all` and `--worktree` returned 0; the largest touched unbaselined source is `upgrade.sh` at 794 lines.

## Findings

1. **BLOCKER | `hooks/local/lib/run-with-timeout.sh:513-526,570-575` | B6 still has launch-before-publication and non-atomic state |** A SIGKILL or failed/torn first append leaves the sentinel with no complete record. **Verified:** traced launch, first append, state parser, and the test’s delayed-probe seam.

2. **BLOCKER | `hooks/tests/lib/orphan-reap.sh:18-25,120-134,230-266` | Locked identity tuple remains unimplemented |** Leader start time alone cannot authenticate child identity, Windows identity, or individual native survivors. **Verified:** compared every captured/revalidated field with `execution-plan.md:127-129`.

3. **BLOCKER | `hooks/tests/lib/orphan-reap.sh:239-266` | Group and native kills retain TOCTOU/collateral exposure |** The group can disappear or change during the grace period; the unconditional SIGKILL and same-snapshot native checks can hit joiners or recycled members. **Verified:** followed TERM → grace loop → unconditional KILL → native sweep.

4. **BLOCKER | `hooks/tests/test-run-tests-signal-reap.sh:145-162` | The regression gate still contains an identity-unchecked delayed group kill |** The test can kill a recycled unrelated group five seconds after its initial check. **Verified:** enumerated every current kill site and distinguished verified PID kills from numeric group kills.

5. **BLOCKER | `hooks/tests/test-run-tests-signal-reap.sh:434-471`; `hooks/tests/run-tests.sh:355-376` | INT=130 is unimplemented and hidden from gate totals |** The locked AC remains red, but the test emits inconclusive and exits zero; the parent parser counts only PASS/FAIL. **Verified:** compared the test and parser with `execution-plan.md:130-131,250`.

6. **BLOCKER | `hooks/tests/test-run-tests-signal-reap.sh:212-518` | Coverage is still materially overstated |** Only 4/19 PASS rows discriminate `b0b33b3`; seven rows labelled discriminator are controls in fact. **Verified:** compared the current rows with the behaviors and rows present at `b0b33b3`.

7. **MAJOR | `hooks/tests/lib/cli-flow-recovery-profile.sh:142-175` | Trace containment follows symlinks |** An accepted lexical path under `state/audit` can truncate an external target. **Verified:** inspected path validation and open/truncate sequence; no canonical-path or no-follow check exists.

8. **MAJOR | `hooks/tests/lib/cli-flow-recovery-profile.sh:60-64` | Redaction predicate leaks digit-prefixed alphanumeric values |** Allowlisted environment values such as a digit-prefixed token can be persisted verbatim. **Verified:** evaluated the shell glob branches; the test uses only a letter-prefixed decoy.

9. **MAJOR | `hooks/tests/test-install-fusebase-cli-project-doc.sh:155-200` | AC14 remains only partially exercised |** The correction checks the managed list and Bash preflight output, but still does not execute both documented Bash and PowerShell scratch installs/upgrades. **Verified:** read the complete new plugin test section.

## Required before the full gate

1. Replace B6 with a handshake/supervisor design that owns the child before the harness is kill-vulnerable and publishes records atomically or equivalently.
2. Capture and revalidate the full locked POSIX and Windows identity tuple, including each native kill target.
3. Revalidate group identity immediately before SIGKILL; remove the same-snapshot native “revalidation.”
4. Make all test cleanup—including delayed group kills—identity-bound at signal time.
5. Implement INT=130 or formally reopen/change the locked contract; until then, INT must be a gate non-pass.
6. Make shell-phase `INCONCLUSIVE` rows enter the gate total as non-passes.
7. Add discriminators for torn/failed first publication, sentinel cache miss with a dead leader, ancestor refusal, group reuse during grace, native-member reuse, and symlinked trace destinations.
8. Execute real Bash and PowerShell scratch install/upgrade scenarios.
9. Restamp and reverify both manifests and rerun FR-25 after corrections.
10. Run Windows/MSYS and Linux full unscoped gates on one exact committed SHA, with committed defaults and no skip/timeout override.

## What I could NOT verify

- Git Bash execution failed locally with `CreateFileMapping … Win32 error 5`; I could not independently reproduce the claimed 19/19 run or execute shell syntax/scoped tests.
- I could not run the full unscoped Windows/MSYS gate or Linux `ubuntu:24.04` gate.
- The current `state/audit/hook-test-results.md` belongs to `88f7286`, not `c97f8d2`.
- The reported 1568s/1813s `cli-flow-recovery` runs have no retained raw logs, so I could not independently verify those timings. The committed gate still enforces 900s at `run-tests.sh:455`.
- The untracked `docs/wasted-code/` directory was excluded and left untouched.

---
Phase: Verify  
Ticket: backlog-triage-execution  
Next: correct the open/partial blockers before starting the full unscoped gate.
