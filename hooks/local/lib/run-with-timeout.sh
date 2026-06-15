#!/usr/bin/env bash
# Fusebase Flow — bounded-execution helper (sourced by the health-check engine).
#
# PROVENANCE:
#   Extracted from fusebase-flow-health-check.sh per FR-25 (module-size ratchet)
#   so the engine stays under the 800-line ceiling. Lives at hooks/local/lib/ —
#   outside the FuseBase CLI refresh manifest, so it survives `fusebase update`.
#
# PURPOSE:
#   Bound the engine's slow, verdict-affecting operations (preflight, run-tests,
#   conflict reporter, upstream git fetch) so a network-impaired or large-repo
#   host can't make the read-only diagnostic appear to hang.
#
# CONTRACT (relied on by the engine's verdict logic — do not change silently):
#   FFHC_TIMEOUT_BIN     — set by ffhc_detect_timeout: "timeout" | "gtimeout" | "" (none)
#   run_with_timeout SECS CMD...
#     rc 124  => the wrapped command timed out (the timeout binary's own signal rc)
#     other   => the wrapped command's OWN rc, preserved (NOT squashed to 0/1)
#   ffhc_timed_out RC    => returns 0 (true) iff RC == 124

# Detect a usable timeout binary. GNU coreutils ships `timeout` (Linux, Git-Bash);
# macOS commonly ships only `gtimeout` (from coreutils via Homebrew). Sets the
# module-global FFHC_TIMEOUT_BIN to the binary name, or "" when neither exists.
ffhc_detect_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    FFHC_TIMEOUT_BIN="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    FFHC_TIMEOUT_BIN="gtimeout"
  else
    FFHC_TIMEOUT_BIN=""
  fi
}

# rc 124 is the GNU-timeout convention for "killed because the duration elapsed".
ffhc_timed_out() {
  [ "${1:-}" = "124" ]
}

# run_with_timeout SECS CMD [ARGS...]
#   Runs CMD bounded to SECS via the detected timeout binary with a -k grace
#   window (a follow-up KILL if the command ignores the initial TERM). Returns
#   124 on timeout; otherwise the wrapped command's own exit code is preserved.
#   Caller MUST have run ffhc_detect_timeout and confirmed FFHC_TIMEOUT_BIN is
#   non-empty (no-binary handling is a verdict decision the engine owns, not this
#   helper — H5).
run_with_timeout() {
  local secs="$1"; shift
  local grace="${FFHC_TIMEOUT_KILL_GRACE:-5s}"
  "$FFHC_TIMEOUT_BIN" -k "$grace" "$secs" "$@"
}

# ffhc_run_bounded SECS CMD [ARGS...]
#   Runs CMD per the no-binary policy and records the result in module-globals
#   the engine reads. Captures combined stdout+stderr so callers can parse it.
#     FFHC_LAST_OUT       — captured combined output ("" when skipped)
#     FFHC_LAST_RC        — wrapped command's own rc (124 on timeout; 125 sentinel when skipped)
#     FFHC_LAST_TIMED_OUT — 1 iff the run hit the timeout (rc 124), else 0
#     FFHC_LAST_SKIPPED   — 1 iff the run was skipped because no timeout binary exists, else 0
#   Policy (H5): if no timeout binary AND FFHC_ALLOW_UNBOUNDED!=1 => SKIP (no run,
#   sentinel rc 125, FFHC_LAST_SKIPPED=1) so a slow op can never hang the engine;
#   FFHC_ALLOW_UNBOUNDED=1 opts into an unbounded run instead.
ffhc_run_bounded() {
  local secs="$1"; shift
  FFHC_LAST_OUT=""; FFHC_LAST_RC=0; FFHC_LAST_TIMED_OUT=0; FFHC_LAST_SKIPPED=0
  if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
    FFHC_LAST_OUT="$(run_with_timeout "$secs" "$@" 2>&1)"; FFHC_LAST_RC=$?
    ffhc_timed_out "$FFHC_LAST_RC" && FFHC_LAST_TIMED_OUT=1
  elif [ "${FFHC_ALLOW_UNBOUNDED:-0}" = "1" ]; then
    FFHC_LAST_OUT="$("$@" 2>&1)"; FFHC_LAST_RC=$?
  else
    FFHC_LAST_RC=125; FFHC_LAST_SKIPPED=1
  fi
}
