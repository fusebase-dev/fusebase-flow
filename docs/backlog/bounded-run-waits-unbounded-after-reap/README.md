# bounded-run-waits-unbounded-after-reap

**Status:** open — FILED, NOT FIXED. Deliberately not widened into shared infrastructure while
one consumer phase was repaired at its own layer
**Filed:** 2026-09-12, after `cli-flow-recovery-selectors` hung past a 180s bound in the
`v4.17.0` release run and was stopped only by the 1800s phase wall
**Surface:** `hooks/local/lib/run-with-timeout.sh:246` (`wait "$bpid"` after the polled loop),
reached from `ffhc_msys_wait_reap:207-245` via `_ffhc_tempfile_capture` and `ffhc_run_bounded`
**Severity:** medium — MSYS only; a bound that silently becomes unbounded, so the failure
presents as a slow/flaky phase rather than as a timeout

## The claim, and where it stops holding

`ffhc_run_bounded <secs>` promises the wrapped command is bounded at `secs`. On MSYS the wait is
`ffhc_msys_wait_reap`, whose **poll loop is correctly capped**: `cap=$(( secs + gsec + 2 ))` and
`[ "$waited" -ge "$cap" ] && { _ffhc_reap; break; }` (`:211`, `:235`, `:243`). The loop cannot
spin forever.

The unbounded step is the one **after** it:

```
246:  wait "$bpid"; local rc=$?
```

`wait` has no deadline. The bound therefore holds **only if `_ffhc_reap` actually killed the
child**. When it does not, this line blocks for as long as the child lives, and the caller sees
no timeout, no rc 124, and no diagnostic — just a call that has not returned.

Reap failure is not hypothetical; it is a documented, deliberate branch:

```
118:    [ "$now_winpid" = "$winpid" ] || return 0   # PID reuse / child gone => skip, no collateral
115:  command -v taskkill >/dev/null 2>&1 || return 0
120:  taskkill //F //T //PID "$winpid" >/dev/null 2>&1 || true
```

Each of those returns success while killing nothing: no `taskkill` on PATH, a winpid that no
longer maps to our child, or a `taskkill` that simply fails (its rc is discarded by `|| true`).
Declining to kill is the right call — the alternative is collateral damage to a reused pid — but
the caller is then left waiting forever on a child nobody stopped.

## Observed

`v4.17.0` release run (`34672166356`, MSYS job `103495446744`): `cli-flow-recovery-selectors`
invoked the wrapper with `FFCF_SELECTOR_TIMEOUT_SECS=180`. The bound did not fire. The phase was
killed by the 1800s phase wall at rc 124 with 2 of 11 rows scored. Prior green for that phase:
**57s** (`v4.16.6`). A re-run of the identical gate on the identical SHA was green with the phase
at **30s**, so the stall is intermittent, and every other phase in the red leg ran clean and
FASTER than the green baseline — there was no earlier kill, and on a fresh hosted VM there were
no inherited orphans (the first hypothesis, refuted by the phase table rather than defended).

## Scope decision (why this is filed, not fixed)

`ffhc_run_bounded` is shared by the health engine, the upgrade engine and many phases. A change
to its wait semantics — a hard second deadline, `wait -n` with a timer, or treating a failed reap
as a timeout — alters behaviour for every one of them, and the failure mode it addresses has been
observed once. The consumer that suffered it was repaired at ITS OWN layer instead:
`hooks/tests/test-cli-flow-recovery-selectors.sh` now bounds each case with a plain `timeout`
that does not depend on this reap succeeding, names a deadline as a distinct failure, and retains
the evidence.

## Changed under this ticket by T4 (2026-09-12) — read before touching `_ffhc_tempfile_capture`

`harness-kill-leaves-orphan-children` T4 edited the same function, one concern away from the
`wait "$bpid"` this ticket owns. Two facts a fixer here needs, not restated from that ticket:

- the in-flight record's **pgid field is now always `-`**; `FFHC_LAST_CHILD_PGID` and its
  `ffhc_pgid_of "$_bpid"` probe are gone, because that pid is this shell's own background job and
  its group is always OUR group. The reapable group is resolved from the live process table by the
  READER (`hooks/tests/lib/orphan-reap.sh: ffor_resolve_phase`).
- `ffor_group_gone` now exists in that library and answers "has this group no live member left",
  fail-closed. A fix here that wants to treat *reaped but still alive* as its own outcome has that
  oracle already; the shape this ticket asks for is a deadline, not a new probe.

## What a fix has to preserve

- The no-collateral rule at `:118`. A bound that kills a reused pid is worse than one that hangs.
- `FFHC_LAST_RC` semantics: a deadline must stay a true 124/137, and the existing
  rc0-on-kill normalisation (`:247-252`) must keep working.
- The default-inert cost promise — the fast poll ladder exists so ordinary callers add no forks.

The cheap shape, uncosted: after `_ffhc_reap` at the cap, stop trusting `wait`. Either bound the
final wait by polling `kill -0` to a second hard deadline and reporting 124 when the child
outlives it, or record "reaped but still alive" as its own outcome so the caller can decide.
Either way the promise becomes *this call returns by `cap`*, which is what every caller already
believes it says.
