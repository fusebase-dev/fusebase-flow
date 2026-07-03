#!/usr/bin/env bash
# Fusebase Flow — hook test runner
# Pipes each fixture into its target handler and checks the response.
#
# ## Gate scoping (FF_ONLY / FF_LIST) — process rule
#   FF_ONLY="tag1,tag2" runs ONLY the named phases (implement-loop iteration speed).
#   FF_ONLY is IMPLEMENT-LOOP ONLY: the FINAL pre-commit / pre-deploy gate MUST be a
#   full UNSCOPED run, and a gate report may cite ONLY state/audit/hook-test-results.md
#   — never hook-test-results-scoped.md. A scoped run is fail-closed by construction:
#   its summary line is deliberately NOT the strict "[run-tests] N/N PASS" shape, so
#   ffhc_run_tests_pass_ok / ffhc_count_pass_lines read it as NOT a clean full pass, and
#   its results go to hook-test-results-scoped.md (the full-gate file is never touched).
#   FF_LIST=1 prints the canonical tag list (RUN/SKIP) and exits 0 without running.
#   Unknown or empty selection => exit 2 (never a "scoped to nothing" green). Canonical
#   home for this rule: this header + flow-skills/validation-and-qa/SKILL.md (sub-mode A).

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TESTS_DIR="$ROOT/hooks/tests/fixtures"
HANDLERS_DIR="$ROOT/hooks/handlers"

python_bin="${PYTHON:-python3}"

if ! command -v "$python_bin" >/dev/null 2>&1; then
    echo "[run-tests] $python_bin not found; install Python 3.10+." >&2
    exit 1
fi

# Bounded-run engine (WS2-core strict-scoped reap): each heavy phase runs under
# ffhc_run_bounded (tempfile capture + the recorded-child taskkill), so an MSYS
# native grandchild can't hold a $(...) pipe open past the deadline and freeze the
# harness. Reads FFHC_LAST_OUT / FFHC_LAST_RC after each call.
. "$ROOT/hooks/local/lib/run-with-timeout.sh"
ffhc_detect_timeout

# Per-phase heavy-run bound. Generous default (the recovery phase copies a skill tree
# + drives the health engine — minutes on MSYS); operator-overridable.
FF_PHASE_TIMEOUT="${FF_PHASE_TIMEOUT:-600}"

# --- FF_ONLY scoped-gate parse (implement-loop iteration speed) ---------------------
# Canonical phase tags, in run order. This list is the FF_LIST discovery source and the
# FF_ONLY validation set; add a tag here (and its guard) when a phase is added.
FF_TAGS=(fixtures module-size health-check-timeout newline-preserve baseline-merge \
  sync-allowlist policy-state bootstrap-baseline-hop fr22-delivery po-verifiable-boot \
  liveness codex-parity cli-0259 secret-scan-staged bootstrap-exception trusted-enforcer \
  hook-install-rc msys-tree-cleanup ws5-upgrade ff-only cli-flow-recovery)

declare -A FF_SEL=()      # selected tags (populated only when scoped)
FF_SCOPED=0               # 1 iff FF_ONLY is a non-empty selection
if [ -n "${FF_ONLY:-}" ]; then
  # Split on commas; trim surrounding whitespace per tag. A bogus or all-blank
  # selection => exit 2 (never a silent "scoped to nothing" green).
  IFS=',' read -r -a _ff_req <<< "$FF_ONLY"
  declare -A _ff_valid=(); for t in "${FF_TAGS[@]}"; do _ff_valid[$t]=1; done
  for raw in "${_ff_req[@]}"; do
    tag="${raw#"${raw%%[![:space:]]*}"}"; tag="${tag%"${tag##*[![:space:]]}"}"   # trim
    [ -z "$tag" ] && continue
    if [ -z "${_ff_valid[$tag]:-}" ]; then
      echo "[run-tests] ERROR: FF_ONLY unknown tag '$tag' (valid: ${FF_TAGS[*]})" >&2
      exit 2
    fi
    FF_SEL[$tag]=1
  done
  if [ "${#FF_SEL[@]}" -eq 0 ]; then
    echo "[run-tests] ERROR: FF_ONLY selected no valid tags (was '$FF_ONLY')" >&2
    exit 2
  fi
  FF_SCOPED=1
fi

# FF_LIST=1: print the canonical tags with RUN/SKIP markers and exit 0 (no run).
if [ "${FF_LIST:-0}" = "1" ]; then
  for t in "${FF_TAGS[@]}"; do
    if [ "$FF_SCOPED" -eq 0 ] || [ -n "${FF_SEL[$t]:-}" ]; then echo "RUN  $t"; else echo "SKIP $t"; fi
  done
  exit 0
fi

# ff_selected TAG: 0 (run) when unscoped OR the tag is in the scoped selection.
ff_selected() { [ "$FF_SCOPED" -eq 0 ] || [ -n "${FF_SEL[$1]:-}" ]; }
# ff_skip_note TAG: emit the visible per-phase skip line (only ever called when scoped).
ff_skip_note() { echo "SKIP (FF_ONLY): $1"; }

# Scoped runs write to a SEPARATE results file so the full-gate hook-test-results.md is
# never clobbered by a subset run (the health engine / gate reports read only the full
# file). Unscoped => the canonical full-gate file, byte-behavior-unchanged.
if [ "$FF_SCOPED" -eq 1 ]; then
  RESULTS_FILE="$ROOT/state/audit/hook-test-results-scoped.md"
else
  RESULTS_FILE="$ROOT/state/audit/hook-test-results.md"
fi

# EXIT-trap reaper (WS3): if the harness is signaled while a bounded phase is still in
# flight, taskkill ONLY that phase's own recorded child winpid — FFHC_LAST_WINPID, set
# live at launch by the T1 capture — strict-scoped, never a broad taskkill (depends on
# WS2-core). It passes FFHC_LAST_CHILD_PID too (T12), so the trap gets the SAME PID-reuse
# re-verify guard as the deadline path (ffhc_msys_taskkill_winpid re-checks the winpid
# still maps to our child before killing). The lib + run_bounded_phase CLEAR both the
# instant a phase returns (its child is already reaped by then), so a normal exit reaps
# nothing and a stale/reused winpid is never swept. The reap is a no-op off-MSYS.
FFHC_LAST_WINPID=""
FFHC_LAST_CHILD_PID=""
_ff_exit_reap() {
    ffhc_is_msys || return 0
    [ -n "$FFHC_LAST_WINPID" ] && ffhc_msys_taskkill_winpid "$FFHC_LAST_WINPID" "$FFHC_LAST_CHILD_PID"
}
trap _ff_exit_reap EXIT

# progress <phase>: flush a starting marker to stderr BEFORE the (possibly multi-min)
# phase runs, so a slow phase is visibly progressing, never mistakable for a freeze.
progress() { printf '[run-tests] starting %s\n' "$1" >&2; }

# run_bounded_phase <label> CMD...: flush progress, run CMD under ffhc_run_bounded
# (tempfile capture + T1 strict-scoped reap; FFHC_LAST_WINPID tracks the in-flight
# child for the EXIT-trap), exposing FFHC_LAST_OUT / FFHC_LAST_RC to the caller. Clears
# FFHC_LAST_WINPID on return so the EXIT-trap never reaps a completed phase's dead winpid.
run_bounded_phase() {
    local label="$1"; shift
    progress "$label"
    ffhc_run_bounded "$FF_PHASE_TIMEOUT" "$@"
    FFHC_LAST_WINPID=""; FFHC_LAST_CHILD_PID=""   # phase returned => child reaped; no stale sweep on exit
}

pass=0
fail=0
total=0
report_rows=""

mkdir -p "$(dirname "$RESULTS_FILE")"

# Loud scoped banner: a subset run is NEVER a full gate — make that impossible to miss.
if [ "$FF_SCOPED" -eq 1 ]; then
  {
    echo "============================================================"
    echo "  SCOPED RUN — FF_ONLY=${FF_ONLY}"
    echo "  This is a SUBSET, not a full gate. Results -> ${RESULTS_FILE#"$ROOT/"}"
    echo "  The final pre-commit/pre-deploy gate MUST be a full unscoped run."
    echo "============================================================"
  } >&2
fi

if ff_selected fixtures; then
progress "fixture handler tests"
for fixture in "$TESTS_DIR"/*.json; do
    [ -f "$fixture" ] || continue
    total=$((total + 1))
    name="$(basename "$fixture")"

    # Extract metadata via python (simpler than jq for portability).
    meta="$("$python_bin" - "$fixture" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data.get("_test", ""))
print(data.get("_handler", ""))
print(data.get("_expected_decision", ""))
print(data.get("_expected_rule_id", ""))
print(data.get("_expected_rule_id_contains", ""))
PY
)"
    test_name="$(echo "$meta" | sed -n '1p')"
    handler="$(echo "$meta" | sed -n '2p')"
    expected_decision="$(echo "$meta" | sed -n '3p')"
    expected_rule_id="$(echo "$meta" | sed -n '4p')"
    expected_rule_contains="$(echo "$meta" | sed -n '5p')"

    if [ -z "$handler" ]; then
        echo "[run-tests] $name SKIP — no _handler set"
        continue
    fi

    # Run handler with the fixture as stdin; capture stdout + exit code. Bounded via
    # ffhc_run_bounded_stdin_stdout (tempfile capture + T1 strict-scoped reap; stderr
    # dropped to preserve the ORIGINAL 2>/dev/null stdout-only capture the JSON parse
    # relies on) so a hung handler (or an MSYS native grandchild holding a $(...) pipe)
    # can't freeze the loop past the deadline. TRIPWIRE: the STDIN variant — a
    # backgrounded child's fd 0 otherwise defaults to /dev/null and the `< "$fixture"`
    # never reaches the handler (empty stdin => wrong `allow` on deny-fixtures on MSYS).
    # FFHC_LAST_OUT holds stdout only; the '{' parse below is unchanged.
    ffhc_run_bounded_stdin_stdout "$FF_PHASE_TIMEOUT" "$python_bin" "$HANDLERS_DIR/$handler" < "$fixture"
    output="$FFHC_LAST_OUT"
    exit_code=$FFHC_LAST_RC

    # Parse decision and rule_id from JSON stdout.
    actual="$("$python_bin" - <<PY
import json, sys
out = json.loads('''$output''') if '''$output'''.strip().startswith("{") else {}
print(out.get("decision", ""))
print(out.get("rule_id", "") or "")
PY
)"
    actual_decision="$(echo "$actual" | sed -n '1p')"
    actual_rule_id="$(echo "$actual" | sed -n '2p')"

    ok=1
    detail=""
    if [ -n "$expected_decision" ] && [ "$expected_decision" != "$actual_decision" ]; then
        ok=0
        detail="$detail expected=$expected_decision got=$actual_decision"
    fi
    if [ -n "$expected_rule_id" ] && [ "$expected_rule_id" != "$actual_rule_id" ]; then
        ok=0
        detail="$detail expected_rule=$expected_rule_id got=$actual_rule_id"
    fi
    if [ -n "$expected_rule_contains" ]; then
        if [[ "$actual_rule_id" != *"$expected_rule_contains"* ]]; then
            ok=0
            detail="$detail expected_rule_contains=$expected_rule_contains got=$actual_rule_id"
        fi
    fi

    if [ $ok -eq 1 ]; then
        pass=$((pass + 1))
        echo "PASS: $name  ($test_name) -> decision=$actual_decision"
        report_rows="$report_rows| $name | $test_name | PASS | decision=$actual_decision rule=$actual_rule_id |"$'\n'
    else
        fail=$((fail + 1))
        echo "FAIL: $name  ($test_name) ->$detail"
        report_rows="$report_rows| $name | $test_name | FAIL |$detail (raw=$output) |"$'\n'
    fi
done
FFHC_LAST_WINPID=""; FFHC_LAST_CHILD_PID=""   # fixture loop done — clear the last handler's ids before the trap window
else
    ff_skip_note fixtures
fi

# Phase 2 — FR-25 module-size ratchet scenarios (shell-level; not handler fixtures).
MS_TEST="$ROOT/hooks/tests/test-module-size.sh"
if ! ff_selected module-size; then
    ff_skip_note module-size
elif [ -f "$MS_TEST" ]; then
    run_bounded_phase "module-size ratchet" bash "$MS_TEST"
    ms_out="$FFHC_LAST_OUT"; ms_fail=$FFHC_LAST_RC
    echo "$ms_out" | grep -E '^(PASS|FAIL): module-size' || true
    ms_pass="$(echo "$ms_out" | grep -c '^PASS: module-size')"
    ms_failed="$(echo "$ms_out" | grep -c '^FAIL: module-size')"
    total=$((total + ms_pass + ms_failed))
    pass=$((pass + ms_pass))
    fail=$((fail + ms_failed))
    while IFS= read -r line; do
        name="${line#*: module-size }"
        result="${line%%:*}"
        report_rows="$report_rows| test-module-size.sh | $name | $result | exit-code scenario |"$'\n'
    done < <(echo "$ms_out" | grep -E '^(PASS|FAIL): module-size')
    # Crash guard: a non-zero exit with zero parsed FAIL lines means the scenario
    # script died before running (mktemp/cp/syntax) — count it, don't go green.
    if [ "$ms_fail" -ne 0 ] && [ "$ms_failed" -eq 0 ]; then
        total=$((total + 1))
        fail=$((fail + 1))
        echo "FAIL: test-module-size.sh crashed (exit $ms_fail) before reporting scenarios"
        report_rows="$report_rows| test-module-size.sh | (harness) | FAIL | crashed with exit $ms_fail, no scenario output |"$'\n'
    fi
fi

# Phase 3 — health-check bounded-execution + verdict/exit contract scenarios
# (shell-level; spec docs/specs/health-check-fast-timeout). Same parse contract
# as Phase 2: count "PASS:/FAIL: health-check-timeout <name>" lines; a non-zero
# exit with zero parsed FAIL lines means the script crashed before reporting.
HT_TEST="$ROOT/hooks/tests/test-health-check-timeout.sh"
if ! ff_selected health-check-timeout; then
    ff_skip_note health-check-timeout
elif [ -f "$HT_TEST" ]; then
    run_bounded_phase "health-check-timeout scenarios" bash "$HT_TEST"
    ht_out="$FFHC_LAST_OUT"; ht_rc=$FFHC_LAST_RC
    echo "$ht_out" | grep -E '^(PASS|FAIL): health-check-timeout' || true
    ht_pass="$(echo "$ht_out" | grep -c '^PASS: health-check-timeout')"
    ht_failed="$(echo "$ht_out" | grep -c '^FAIL: health-check-timeout')"
    total=$((total + ht_pass + ht_failed))
    pass=$((pass + ht_pass))
    fail=$((fail + ht_failed))
    while IFS= read -r line; do
        name="${line#*: health-check-timeout }"
        result="${line%%:*}"
        report_rows="$report_rows| test-health-check-timeout.sh | $name | $result | timeout/verdict scenario |"$'\n'
    done < <(echo "$ht_out" | grep -E '^(PASS|FAIL): health-check-timeout')
    if [ "$ht_rc" -ne 0 ] && [ "$ht_failed" -eq 0 ]; then
        total=$((total + 1))
        fail=$((fail + 1))
        echo "FAIL: test-health-check-timeout.sh crashed (exit $ht_rc) before reporting scenarios"
        report_rows="$report_rows| test-health-check-timeout.sh | (harness) | FAIL | crashed with exit $ht_rc, no scenario output |"$'\n'
    fi
fi

# Phases 4-7 — upgrade-tooling-hardening shell scenarios (v3.24.x). Same parse
# contract as Phase 2/3: count "PASS:/FAIL: <tag> <name>" lines; a non-zero exit
# with zero parsed FAIL lines means the script crashed before reporting. One loop
# over (script, tag) pairs keeps run-tests under the FR-25 ceiling.
run_shell_phase() { # run_shell_phase <test-script> <tag>
    local script="$ROOT/hooks/tests/$1" tag="$2"
    ff_selected "$tag" || { ff_skip_note "$tag"; return 0; }
    [ -f "$script" ] || return 0
    local out rc p f
    run_bounded_phase "$tag" bash "$script"
    out="$FFHC_LAST_OUT"; rc=$FFHC_LAST_RC
    echo "$out" | grep -E "^(PASS|FAIL): $tag " || true
    p="$(echo "$out" | grep -c "^PASS: $tag ")"
    f="$(echo "$out" | grep -c "^FAIL: $tag ")"
    total=$((total + p + f)); pass=$((pass + p)); fail=$((fail + f))
    while IFS= read -r line; do
        name="${line#*: $tag }"; result="${line%%:*}"
        report_rows="$report_rows| $1 | $name | $result | shell scenario |"$'\n'
    done < <(echo "$out" | grep -E "^(PASS|FAIL): $tag ")
    if [ "$rc" -ne 0 ] && [ "$f" -eq 0 ]; then
        total=$((total + 1)); fail=$((fail + 1))
        echo "FAIL: $1 crashed (exit $rc) before reporting scenarios"
        report_rows="$report_rows| $1 | (harness) | FAIL | crashed with exit $rc, no scenario output |"$'\n'
    fi
}
run_shell_phase test-newline-preserve.sh     "newline-preserve"
run_shell_phase test-baseline-merge.sh       "baseline-merge"
run_shell_phase test-sync-allowlist.sh       "sync-allowlist"
run_shell_phase test-policy-state-preserve.sh "policy-state"
run_shell_phase test-bootstrap-baseline-hop.sh "bootstrap-baseline-hop"
run_shell_phase test-fr22-delivery-guarantee.sh "fr22-delivery"
run_shell_phase test-po-verifiable-boot.sh     "po-verifiable-boot"
run_shell_phase test-liveness-bounded-run.sh   "liveness"
run_shell_phase test-codex-prompt-parity.sh    "codex-parity"
run_shell_phase test-cli-0259-compat.sh        "cli-0259"
run_shell_phase test-secret-scan-staged.sh     "secret-scan-staged"
run_shell_phase test-bootstrap-exception.sh    "bootstrap-exception"
run_shell_phase test-trusted-enforcer.sh       "trusted-enforcer"
run_shell_phase test-hook-install-rc.sh        "hook-install-rc"
run_shell_phase test-msys-tree-cleanup.sh      "msys-tree-cleanup"
run_shell_phase test-ws5-upgrade-bounded.sh    "ws5-upgrade"
run_shell_phase test-ff-only.sh                "ff-only"

# Exit-code phase — all-or-nothing shell tests that fail-fast (set -e + fail()→exit)
# and don't emit the run_shell_phase "PASS: <tag> <name>" contract. One row per test;
# PASS iff exit 0. test-cli-flow-recovery.sh is heavy (copies the skill tree + drives
# the health engine — minutes) and was UNBOUNDED, so it hung the whole harness on
# MSYS (the universal run-tests-never-completes defect). Now bounded via
# ffhc_run_bounded_stdout at FF_CLI_RECOVERY_TIMEOUT (default 240s) with an
# FF_SKIP_CLI_RECOVERY=1 opt-out; a timeout (rc 124/137) is reported INCONCLUSIVE —
# counted as a non-pass so the suite never goes silently green on a bound-hit.
run_exitcode_phase() { # run_exitcode_phase <test-script> <tag> <label>
    local script="$ROOT/hooks/tests/$1" tag="$2" label="$3"
    ff_selected "$tag" || { ff_skip_note "$tag"; return 0; }
    [ -f "$script" ] || return 0
    total=$((total + 1))
    if [ "${FF_SKIP_CLI_RECOVERY:-0}" = "1" ]; then
        # Operator opt-out of the heavy phase. Not a pass (keeps the count honest) —
        # a visible INCONCLUSIVE row, never a silent green.
        fail=$((fail + 1)); echo "INCONCLUSIVE: $label (skipped via FF_SKIP_CLI_RECOVERY=1)"
        report_rows="$report_rows| $1 | $label | INCONCLUSIVE | skipped (FF_SKIP_CLI_RECOVERY=1) |"$'\n'
        return 0
    fi
    progress "$label"
    ffhc_run_bounded_stdout "${FF_CLI_RECOVERY_TIMEOUT:-240}" bash "$script"
    local rc=$FFHC_LAST_RC
    FFHC_LAST_WINPID=""; FFHC_LAST_CHILD_PID=""   # phase returned => child reaped; no stale sweep on exit
    if [ "$rc" -eq 0 ]; then
        pass=$((pass + 1)); echo "PASS: $label (exit 0)"
        report_rows="$report_rows| $1 | $label | PASS | exit 0 |"$'\n'
    elif ffhc_timed_out "$rc"; then
        # Bound-hit on a loaded/slow host: INCONCLUSIVE, not FAIL and NOT silent-green.
        fail=$((fail + 1)); echo "INCONCLUSIVE: $label (bounded timeout rc $rc at ${FF_CLI_RECOVERY_TIMEOUT:-240}s — re-run on a quiet host or FF_SKIP_CLI_RECOVERY=1)"
        report_rows="$report_rows| $1 | $label | INCONCLUSIVE | bounded timeout rc $rc |"$'\n'
    else
        fail=$((fail + 1)); echo "FAIL: $label (exit $rc)"
        report_rows="$report_rows| $1 | $label | FAIL | exit $rc |"$'\n'
    fi
}
run_exitcode_phase test-cli-flow-recovery.sh "cli-flow-recovery" "cli-flow-recovery (0.25.9 model)"

# Write report. Unscoped => byte-identical to today. Scoped => a distinct title +
# an FF_ONLY banner line so the scoped file can never be mistaken for a full-gate report.
{
    if [ "$FF_SCOPED" -eq 1 ]; then
        echo "# Hook test results — SCOPED (FF_ONLY=${FF_ONLY})"
        echo
        echo "SUBSET RUN — not a full gate. The final pre-commit/pre-deploy gate must be a full unscoped run."
        echo
    else
        echo "# Hook test results"
        echo
    fi
    echo "Run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "Total: $total — PASS: $pass — FAIL: $fail"
    echo
    echo "| Fixture | Test | Result | Detail |"
    echo "|---|---|---|---|"
    echo -n "$report_rows"
} > "$RESULTS_FILE"

echo
# Summary line. Unscoped => the strict "[run-tests] N/N PASS" shape that
# ffhc_run_tests_pass_ok / ffhc_count_pass_lines accept as a clean full pass.
# Scoped => a DELIBERATELY non-strict form (trailing "(SCOPED …)") so those
# classifiers read it as NOT a clean full pass (fail-closed by construction).
if [ "$FF_SCOPED" -eq 1 ]; then
    echo "[run-tests] $pass/$total PASS (SCOPED FF_ONLY=${FF_ONLY} — subset, not a full gate)"
else
    echo "[run-tests] $pass/$total PASS"
fi
echo "[run-tests] report written: $RESULTS_FILE"

exit $fail
