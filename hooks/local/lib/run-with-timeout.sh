#!/usr/bin/env bash
# Fusebase Flow — timeout core sourced by bounded-run.sh (6.0 core: lines 32-69 of the 5.11 file; owner decision 4).
# Contract: ffhc_detect_timeout sets FFHC_TIMEOUT_BIN; run_with_timeout SECS CMD (rc 124 timeout, 137 killed after grace, else the command rc); ffhc_timed_out RC.

# Detect a usable timeout binary. GNU coreutils ships `timeout` (Linux, Git-Bash);
# macOS commonly ships only `gtimeout` (from coreutils via Homebrew). Sets the
# module-global FFHC_TIMEOUT_BIN to the binary name, or "" when neither exists.
# FFHC_FORCE_NO_TIMEOUT=1 forces the no-binary path (testability + an operator
# escape to exercise the degraded behavior on a host that does have timeout).
ffhc_detect_timeout() {
  if [ "${FFHC_FORCE_NO_TIMEOUT:-0}" = "1" ]; then
    FFHC_TIMEOUT_BIN=""
  elif command -v timeout >/dev/null 2>&1; then
    FFHC_TIMEOUT_BIN="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    FFHC_TIMEOUT_BIN="gtimeout"
  else
    FFHC_TIMEOUT_BIN=""
  fi
}

# Timeout-induced rc: 124 = GNU-timeout's "duration elapsed"; 137 = 128+SIGKILL, the
# rc when `-k <grace>` SIGKILLs a child that ignored the initial TERM. Both must read
# as a timeout so a hung-then-SIGKILLed critical is UNVERIFIED, not a spurious other
# state. Accepted limitation: a wrapped command's OWN legit exit 124/137 (e.g. it
# self-SIGKILLs) is also treated as a timeout — acceptable for these read-only criticals.
ffhc_timed_out() {
  [ "${1:-}" = "124" ] || [ "${1:-}" = "137" ]
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
