#!/usr/bin/env bash
# Fusebase Flow — liveness-discipline bounded-run helper (FR-27).
# spec: docs/specs/liveness-discipline/spec.md (AC3). skill: flow-skills/liveness-discipline.
#
# WHY: a long/silent background launch that HANGS emits no completion event, so the
# agent is never re-invoked and idles silently. This wrapper bounds the MONITORED
# process to a wall-clock deadline, emits a heartbeat while it runs, and ALWAYS
# prints a terminal line (completion or a "bounded-run: TIMEOUT" line) so the job
# reaches completion-or-death instead of a 0-byte silent idle.
#
# REUSE-NOT-DUPLICATE: the bounded-execution core (timeout/gtimeout detection, the
# -k kill grace, rc-124/137 timeout classification, the no-binary skip policy) is
# sourced from run-with-timeout.sh. That file's ffhc_* API is the contract the
# health-check engine sources directly — this helper MUST NOT modify it (FR-07).
#
# HONEST SCOPE (D7 — do not overstate): this bounds the monitored process only. It
# does NOT kill an `&`-detached grandchild or an uninterruptible OS wait, and does
# NOT prove the host re-invokes the agent. Don't `&`-detach under the wrapper; put
# a deadline INSIDE long scripts too. See the skill for the full protocol.

# Source the shared core (ffhc_detect_timeout / run_with_timeout / ffhc_timed_out).
# Resolve via BASH_SOURCE so it works wherever the lib dir is copied.
# shellcheck source=run-with-timeout.sh
. "$(dirname "${BASH_SOURCE[0]}")/run-with-timeout.sh"

# bounded_run DEADLINE_SECS LABEL -- CMD [ARGS...]
#   Runs CMD bounded to DEADLINE_SECS via the sourced run_with_timeout core, with a
#   stderr heartbeat every BOUNDED_RUN_HEARTBEAT_SECS (default 10) so a live-but-slow
#   job can't masquerade as a hang. ALWAYS emits a terminal stderr line:
#     "bounded-run: TIMEOUT after <secs>s — <label> (rc <rc>)"  on a timeout-induced kill, OR
#     "bounded-run: done — <label> (rc <rc>, <secs>s)"          on normal completion.
#   Returns the wrapped command's own rc; 124 on deadline-elapsed; 137 when the child
#   ignored SIGTERM and was SIGKILLed after run_with_timeout's -k grace.
#   No-timeout-binary policy is inherited from the core (see below) — never a false
#   "bounded": with no binary and BOUNDED_RUN_ALLOW_UNBOUNDED!=1 the run is SKIPPED
#   (terminal "SKIPPED (no timeout binary)" line, sentinel rc 125), so a slow op can
#   never silently hang the caller.
bounded_run() {
  local deadline="$1" label="$2"; shift 2
  [ "${1:-}" = "--" ] && shift   # tolerate the readability "--" separator

  local hb="${BOUNDED_RUN_HEARTBEAT_SECS:-10}"
  ffhc_detect_timeout

  # No-binary policy (mirrors ffhc_run_bounded H5): SKIP rather than run unbounded,
  # so the absence of `timeout` can never reintroduce a silent unbounded wait. An
  # operator can opt into an unbounded run with BOUNDED_RUN_ALLOW_UNBOUNDED=1.
  if [ -z "${FFHC_TIMEOUT_BIN:-}" ] && [ "${BOUNDED_RUN_ALLOW_UNBOUNDED:-0}" != "1" ]; then
    echo "bounded-run: SKIPPED (no timeout binary) — $label" >&2
    return 125
  fi

  # Heartbeat child: incremental progress to stderr while CMD runs. It is internal
  # plumbing fully owned and reaped by this function (the `kill` below) — NOT user
  # `&`-detached work, so it does not contradict the don't-detach rule. Bounded by
  # its own (deadline + grace) cap so it can never outlive a wrapper that died.
  local hb_pid=""
  if [ "$hb" -gt 0 ] 2>/dev/null; then
    _bounded_run_heartbeat "$hb" "$deadline" "$label" &
    hb_pid=$!
  fi

  local start rc end elapsed
  start=$(date +%s)
  if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
    run_with_timeout "$deadline" "$@"; rc=$?
  else
    "$@"; rc=$?   # BOUNDED_RUN_ALLOW_UNBOUNDED=1 path (operator opt-in)
  fi
  end=$(date +%s); elapsed=$((end - start))

  # Reap the heartbeat (it is ours; never leave it running past the monitored proc).
  if [ -n "$hb_pid" ]; then
    kill "$hb_pid" 2>/dev/null
    wait "$hb_pid" 2>/dev/null
  fi

  # Terminal line — guaranteed on EVERY path so the job reaches completion-or-death.
  if ffhc_timed_out "$rc"; then
    echo "bounded-run: TIMEOUT after ${deadline}s — $label (rc $rc)" >&2
  else
    echo "bounded-run: done — $label (rc $rc, ${elapsed}s)" >&2
  fi
  return "$rc"
}

# Heartbeat loop: print one progress line per interval until the (deadline + a small
# grace) cap, then exit. Capped so a parent that vanished without reaping us still
# self-terminates instead of becoming the very orphan this rule warns against.
_bounded_run_heartbeat() {
  local interval="$1" deadline="$2" label="$3"
  local waited=0 cap=$((deadline + 5))
  while [ "$waited" -lt "$cap" ]; do
    sleep "$interval"
    waited=$((waited + interval))
    echo "bounded-run: still running (${waited}s/${deadline}s) — $label" >&2
  done
}
