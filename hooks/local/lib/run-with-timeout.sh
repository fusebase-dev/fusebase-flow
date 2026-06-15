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
#     rc 137  => the wrapped command ignored TERM and was SIGKILLed after the -k
#                grace (128+9) — also a timeout-induced kill
#     other   => the wrapped command's OWN rc, preserved (NOT squashed to 0/1)
#   ffhc_timed_out RC    => returns 0 (true) iff RC is timeout-induced (124 or 137)
#   ffhc_run_tests_pass_ok LINE  => 0 iff LINE is a strict clean "N/N PASS" summary
#                                   (counts [1-9][0-9]*, passed==total; rejects
#                                   leading-zero counts like 01/01 — Codex r3 A1)
#   ffhc_count_pass_lines OUT    => count of strict "N/N PASS" summary lines in OUT
#   ffhc_select_pass_line OUT    => echoes the SINGLE strict PASS summary line or ""
#                                   (empty unless EXACTLY one — NO tail -1; >=2 PASS
#                                   summaries are the ambiguous/duplicate spoof, r3 A2)
#   ffhc_pass_line_broken_msg RC OUT => LOCAL_BROKEN message for the empty-PASS case
#                                   (re-derives duplicate-vs-none from OUT; subshell-safe)

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

# ffhc_run_tests_pass_ok <pass-line>: classify a run-tests summary line. Returns 0
# (OK) ONLY when the line is STRICTLY "[run-tests] N/N PASS" (nothing but optional
# trailing whitespace after PASS) with passed==total AND total>0. Returns 1 for a
# trailing suffix (e.g. "1/1 PASS but not really"), zero tests ("0/0 PASS"), a
# real undercount ("1/2 PASS"), or leading-zero counts ("01/01 PASS"). A prefix
# match alone is NOT proof of a clean run (Codex round-2 A1): the engine must
# record OK only on a genuine all-pass summary.
#
# Counts are matched [1-9][0-9]* (NOT [0-9]+): a leading zero ("01/01", "0/0",
# "00") is a malformed/spoofed summary, never a clean run. [1-9][0-9]* already
# excludes total==0, so the prior numeric total>0 guard is redundant; passed==total
# is still checked numerically (Codex round-3 A1: "01/01 PASS" normalized 01==01
# and read HEALTHY — the regex must reject the leading zero before any numeric cmp).
ffhc_run_tests_pass_ok() {
  local cnt
  cnt=$(echo "$1" | sed -nE 's|^\[run-tests\] ([1-9][0-9]*)/([1-9][0-9]*) PASS[[:space:]]*$|\1 \2|p')
  [ -n "$cnt" ] && [ "${cnt% *}" -eq "${cnt#* }" ]
}

# ffhc_count_pass_lines <raw-run-tests-output>: echo the number of STRICT run-tests
# PASS summary lines in the output. "Strict" = the full anchored "[run-tests] N/N
# PASS" shape (only trailing whitespace) — the same shape ffhc_run_tests_pass_ok
# demands; a malformed line (suffix, mid-line, leading whitespace) is NOT a PASS
# summary. Used by both selection and the BROKEN-message classifier so the count
# rule lives in one place (no cross-subshell global — Codex round-3 A2).
ffhc_count_pass_lines() {
  echo "$1" | grep -cE "^\[run-tests\] [0-9]+/[0-9]+ PASS[[:space:]]*$"
}

# ffhc_select_pass_line <raw-run-tests-output>: echo the SINGLE strict run-tests
# PASS summary line, or "" when the output does not contain EXACTLY one (zero, or
# two+ which is the ambiguous/duplicate spoof). Replaces the engine's
# `grep ... | tail -1` (Codex round-3 A2): tail -1 hid a second PASS summary, so
# two summaries collapsed to the last clean line and read HEALTHY. The reason for
# an empty result is re-derived by ffhc_pass_line_broken_msg from the same raw
# output (NOT a shared global — this runs in a command-substitution subshell).
ffhc_select_pass_line() {
  [ "$(ffhc_count_pass_lines "$1")" -eq 1 ] && echo "$1" | grep -E "^\[run-tests\] [0-9]+/[0-9]+ PASS[[:space:]]*$"
}

# ffhc_pass_line_broken_msg <rc> <raw-run-tests-output>: the LOCAL_BROKEN message
# for the no-single-PASS-line case. Re-derives the reason from the raw output
# (>=2 strict PASS summaries => the ambiguous/duplicate spoof, Codex round-3 A2;
# else unparseable/no summary) so it works inside the engine even though the
# selection ran in a subshell. Kept in the lib (not inlined) so the engine branch
# stays one line under the FR-25 800-line ceiling.
ffhc_pass_line_broken_msg() {
  if [ "$(ffhc_count_pass_lines "${2:-}")" -ge 2 ]; then
    echo "hook tests: ambiguous/duplicate hook-test summary — cannot confirm pass (>=2 'N/N PASS' summaries; run 'bash hooks/tests/run-tests.sh' to inspect)"
  else
    echo "hook tests: harness exited rc=${1:-?} but printed no parsable 'N/N PASS' line and no FAIL: — output is unparseable, cannot confirm pass (run 'bash hooks/tests/run-tests.sh' to inspect)"
  fi
}
