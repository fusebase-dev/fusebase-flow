#!/usr/bin/env bash
# Fusebase Flow — hook-layer integrity + deep-run helpers (health-check lib).
#
# PROVENANCE:
#   Extracted from fusebase-flow-health-check.sh per FR-25 (the engine is at the
#   803-line ceiling — new logic must live in a sourced lib, like active-approvals.sh).
#   Sourced by the engine; the functions populate LOCAL_OK / LOCAL_BROKEN /
#   LOCAL_UNVERIFIED / DEEP_RUN_NOTES and call record_drift in the CALLER's scope.
#
# Two functions:
#   ffhc_hook_manifest_verify   the CRITICAL — bounded manifest verify + D4 mapping.
#   ffhc_hook_tests_deep_run    the OPTIONAL --run-hook-tests deep diagnostic (D5) —
#                               runs the FULL run-tests.sh suite; FAIL/crash => BROKEN,
#                               timeout/skip => NOTE only (never forces exit 4).
#
# Relies on run-with-timeout.sh (already sourced by the engine): ffhc_run_bounded,
# ffhc_run_bounded_stdout, ffhc_select_pass_line, ffhc_run_tests_pass_ok, and the
# FFHC_LAST_* globals.

# --- JSON parse helpers (verify --json output) --------------------------------------
# python3 is a framework runtime dep; the engine already parses the conflict reporter
# JSON with it. Each helper runs once per health-check invocation.
_ffhc_manifest_summary() {  # <json> -> "<listed>\t<flow_version>"
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("0\t"); sys.exit(0)
c = d.get("counts", {}) or {}
print(str(c.get("listed", 0)) + "\t" + str(d.get("flow_version", "") or ""))
' 2>/dev/null
}

_ffhc_manifest_drift_paths() {  # <json> -> "p1, p2, ... +N more" (first 5)
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
fs = [f.get("path", "?") for f in d.get("files", []) or []]
s = ", ".join(fs[:5])
if len(fs) > 5:
    s += " +%d more" % (len(fs) - 5)
print(s)
' 2>/dev/null
}

# ffhc_hook_manifest_verify: the run-tests CRITICAL is replaced by manifest verify
# (D4). Bounded via ffhc_run_bounded_stdout at FFHC_MANIFEST_TIMEOUT; wraps the SCRIPT
# (a bash function can't be wrapped by run_with_timeout). D4 mapping:
#   MATCH(0)  -> LOCAL_OK           ABSENT(4) -> LOCAL_UNVERIFIED ("manifest absent")
#   DRIFT(1)  -> record_drift        BROKEN(2) -> LOCAL_BROKEN
#   timeout/skip -> LOCAL_UNVERIFIED  other rc  -> LOCAL_BROKEN (fail closed)
# --fast skips this critical => UNVERIFIED by design => exit 4 (never 0).
ffhc_hook_manifest_verify() {
  if [ "${OPT_FAST:-0}" -eq 1 ]; then
    LOCAL_UNVERIFIED+=("hook layer integrity: UNVERIFIED — skipped by --fast (fast mode is NOT a full health verdict; drop --fast for a full run)")
    return 0
  fi
  local verifier="$ROOT/hooks/local/verify-hook-manifest.sh"
  if [ ! -f "$verifier" ]; then
    LOCAL_UNVERIFIED+=("hook layer integrity: UNVERIFIED — verify-hook-manifest.sh missing (pre-upgrade install; run 'bash hooks/local/upgrade.sh')")
    return 0
  fi
  ffhc_run_bounded_stdout "$FFHC_MANIFEST_TIMEOUT" bash "$verifier" --json
  local out="$FFHC_LAST_OUT" rc="$FFHC_LAST_RC"
  local timed_out="$FFHC_LAST_TIMED_OUT" skipped="$FFHC_LAST_SKIPPED"
  FFHC_LAST_WINPID=""; FFHC_LAST_CHILD_PID=""
  if [ "$timed_out" -eq 1 ]; then
    LOCAL_UNVERIFIED+=("hook layer integrity: UNVERIFIED — verify timed out after ${FFHC_MANIFEST_TIMEOUT}s (raise FFHC_MANIFEST_TIMEOUT or run 'bash hooks/local/verify-hook-manifest.sh')")
    return 0
  elif [ "$skipped" -eq 1 ]; then
    LOCAL_UNVERIFIED+=("hook layer integrity: UNVERIFIED — skipped (no timeout binary; install coreutils or set FFHC_ALLOW_UNBOUNDED=1)")
    return 0
  fi
  case "$rc" in
    0)
      local summary n ver
      summary="$(_ffhc_manifest_summary "$out")"
      n="${summary%%$'\t'*}"; ver="${summary#*$'\t'}"
      LOCAL_OK+=("hook layer integrity: ${n:-?} files match release ${ver:-?}") ;;
    1)
      local paths; paths="$(_ffhc_manifest_drift_paths "$out")"
      record_drift "hook_layer_manifest" "hook layer integrity: FLOW_LAYER_DRIFT — ${paths:-covered files drifted} (recover: 'bash hooks/local/upgrade.sh' or 'git checkout -- <file>')" ;;
    2)
      LOCAL_BROKEN+=("hook layer integrity: BROKEN — manifest corrupt or self-hash mismatch (run 'bash hooks/local/verify-hook-manifest.sh')") ;;
    4)
      LOCAL_UNVERIFIED+=("hook layer integrity: manifest absent (pre-upgrade install; run 'bash hooks/local/upgrade.sh')") ;;
    *)
      LOCAL_BROKEN+=("hook layer integrity: BROKEN — unexpected verifier rc=$rc (failing closed; run 'bash hooks/local/verify-hook-manifest.sh')") ;;
  esac
}

# ffhc_hook_tests_deep_run: OPTIONAL deep diagnostic (D5), gated by OPT_RUN_HOOK_TESTS.
# Runs the FULL bash hooks/tests/run-tests.sh (D5/D7 — no tier). Outcome mapping:
#   strict N/N PASS -> LOCAL_OK        observed FAIL / crash -> LOCAL_BROKEN
#   timeout / skip / INCONCLUSIVE -> NOTE only (an optional check NEVER forces exit 4).
# Bounded at FFHC_TESTS_TIMEOUT (defaults unchanged). Flag-independent of --fast (D5).
ffhc_hook_tests_deep_run() {
  [ "${OPT_RUN_HOOK_TESTS:-0}" -eq 1 ] || return 0
  if [ ! -x "$ROOT/hooks/tests/run-tests.sh" ]; then
    DEEP_RUN_NOTES+=("--run-hook-tests: NOTE — run-tests.sh not present/executable (optional deep run; verdict unaffected)")
    return 0
  fi
  ffhc_run_bounded "$FFHC_TESTS_TIMEOUT" bash hooks/tests/run-tests.sh
  local out="$FFHC_LAST_OUT" rc="$FFHC_LAST_RC"
  local timed_out="$FFHC_LAST_TIMED_OUT" skipped="$FFHC_LAST_SKIPPED"
  FFHC_LAST_WINPID=""; FFHC_LAST_CHILD_PID=""
  local pass_line fails
  pass_line="$(ffhc_select_pass_line "$out")"
  fails="$(echo "$out" | grep -E '^FAIL:' || true)"
  if [ "$timed_out" -eq 1 ] && [ -z "$fails" ]; then
    DEEP_RUN_NOTES+=("--run-hook-tests: NOTE — full suite timed out after ${FFHC_TESTS_TIMEOUT}s (optional deep run; verdict unaffected; raise FFHC_TESTS_TIMEOUT or run 'bash hooks/tests/run-tests.sh')")
  elif [ "$skipped" -eq 1 ]; then
    DEEP_RUN_NOTES+=("--run-hook-tests: NOTE — skipped (no timeout binary; optional deep run; verdict unaffected)")
  elif [ -n "$fails" ]; then
    LOCAL_BROKEN+=("--run-hook-tests: hook-test FAILURE(s) observed — $(echo "$fails" | head -3 | tr '\n' ';') (run 'bash hooks/tests/run-tests.sh' to inspect)")
  elif [ -n "$pass_line" ] && ffhc_run_tests_pass_ok "$pass_line"; then
    LOCAL_OK+=("--run-hook-tests: $pass_line (full suite)")
  elif echo "$out" | grep -qE '^INCONCLUSIVE:'; then
    DEEP_RUN_NOTES+=("--run-hook-tests: NOTE — full suite reported INCONCLUSIVE row(s) (bounded phase timeout / FF_SKIP_CLI_RECOVERY; optional deep run; verdict unaffected)")
  elif [ "$rc" -ne 0 ]; then
    LOCAL_BROKEN+=("--run-hook-tests: harness exited rc=$rc with no parsable result — crashed before reporting (run 'bash hooks/tests/run-tests.sh' to inspect)")
  else
    DEEP_RUN_NOTES+=("--run-hook-tests: NOTE — completed but no strict 'N/N PASS' summary parsed (optional deep run; verdict unaffected)")
  fi
}
