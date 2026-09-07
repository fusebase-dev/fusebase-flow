#!/usr/bin/env bash
# Fusebase Flow — health-check verdict/exit contract tests (hook-manifest-verify).
# Retargeted (T8) to the NEW hook-layer-integrity CRITICAL (manifest verify, D4)
# that replaced the run-tests critical, plus the OPTIONAL --run-hook-tests deep run
# (D5). Bounded-execution / knob-surfacing / marker-migration coverage that is
# independent of the critical change is preserved.
#
# COST DISCIPLINE (D14.4): a MSYS engine run spawns ~10 processes (~4-5s). The old
# ~35-scenario file was a dominant chunk of the 7-8 min suite. This retarget keeps a
# LEAN, focused engine-scenario set + a GOLDEN fixture (stamp ONCE, cp per scenario)
# + --no-upstream + tight FFHC_* knobs, so the phase stays cheap. Deep marker/install
# coverage (ws6 c/d/e) drives extracted functions with NO engine run.
#
# Output contract (parsed by run-tests.sh, mirrors test-module-size.sh):
#   "PASS: health-check-timeout <name>" / "FAIL: health-check-timeout <name>";
#   exit code = number of failed fixtures. Standalone OK too.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

HT_ONLY=""
case "$#" in
  0) ;;
  1)
    if [ "$1" = "--list" ]; then
      printf '%s\n' ac5 t57
      exit 0
    fi
    printf 'unknown or incomplete selector: %s\n' "$1" >&2
    exit 2
    ;;
  2)
    if [ "$1" = "--only" ] && { [ "$2" = "ac5" ] || [ "$2" = "t57" ]; }; then
      HT_ONLY="$2"
    else
      printf 'unknown selector: %s %s\n' "$1" "$2" >&2
      exit 2
    fi
    ;;
  *)
    printf 'conflicting selectors\n' >&2
    exit 2
    ;;
esac

TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-hc-timeout.$$"
mkdir -p "$TMP_BASE"

# S1 (cli-0298-compatibility): the engine now probes `fusebase --version` and a CLI outside
# the reviewed range / absent from PATH is PARTIAL_UNVERIFIED (exit 4). Every HEALTHY/0
# baseline below therefore needs a compatible CLI present. Put an in-range stub FIRST on PATH
# so these scenarios keep testing what they are about (timeouts, manifest integrity, marker
# migration) and not the CLI-version gate — which test-cli-version-gate.sh owns.
# TRIPWIRE: prepend, never replace PATH — python3/git/timeout must stay reachable.
mkdir -p "$TMP_BASE/_clibin"
printf '#!/usr/bin/env bash\necho 0.29.8\n' > "$TMP_BASE/_clibin/fusebase"
chmod +x "$TMP_BASE/_clibin/fusebase"
export PATH="$TMP_BASE/_clibin:$PATH"
cleanup() {
  case "$TMP_BASE" in
    /tmp/fusebase-flow-hc-timeout.*|*/tmp/fusebase-flow-hc-timeout.*|*/Temp/fusebase-flow-hc-timeout.*)
      rm -rf "$TMP_BASE" ;;
  esac
}
trap cleanup EXIT

pass_count=0
fail_count=0
# TRIPWIRE (C4 / F-A2): the reason goes on the SAME stdout line as the FAIL marker — the shape
# every run_shell_phase test uses. run-tests.sh prints and rows ONLY lines matching
# `^(PASS|FAIL): health-check-timeout `, so a reason written to stderr instead reached neither the
# composed log nor state/audit/hook-test-results.md and the FAIL was undiagnosable. Newlines are
# flattened for the same reason: a continuation line would not match the parse and be dropped.
ht_fail() {
  fail_count=$((fail_count + 1))
  local why="${2:-}"
  [ -z "$why" ] || why=" ($(printf '%s' "$why" | tr '\n\r\t' '   '))"
  echo "FAIL: health-check-timeout $1$why"
  return 1
}
ht_pass() { pass_count=$((pass_count + 1)); echo "PASS: health-check-timeout $1"; }

# ---- golden fixture (built ONCE; every scenario cp -R's it) -------------------
GOLDEN="$TMP_BASE/_golden"
build_golden() {
  local dir="$GOLDEN"
  mkdir -p "$dir/hooks/local/lib" "$dir/hooks/tests" "$dir/audit" \
           "$dir/.claude/skills/fusebase-flow-health-check" "$dir/.claude/agents" \
           "$dir/hooks/local/fusebase-flow-overlays" \
           "$dir/hooks/shared" "$dir/policies" "$dir/state/approvals"
  cp hooks/local/fusebase-flow-health-check.sh "$dir/hooks/local/"
  cp hooks/local/lib/run-with-timeout.sh hooks/local/lib/hook-integrity-check.sh \
     hooks/local/lib/hook_manifest.py hooks/local/lib/health-stage-progress.sh "$dir/hooks/local/lib/"
  # S1 (cli-0298-compatibility): the engine sources these two. Without cli-version-check.sh
  # every scenario inherits a spurious "CLI version: UNVERIFIED" critical (exit 4) and without
  # health-recommendations.sh the Recommendations block is empty — both would make the
  # scenarios below measure a missing lib instead of what they exist to test.
  cp hooks/local/lib/cli-version-check.sh hooks/local/lib/health-recommendations.sh \
     "$dir/hooks/local/lib/"
  # M9: the approval-collection path must be LIVE in the fixture, or the exit-status half
  # of the staleness contract cannot be asserted at all — the engine silently skips
  # section 0 when the lib is absent, and the shared loader/policy are what it imports.
  # These land BEFORE the one-time stamp so the manifest still MATCHes (they are covered
  # assets: hooks/shared/*.py + hooks/local/lib/*).  state/approvals/ ships EMPTY here;
  # each scenario installs the artifact it needs.
  cp hooks/local/lib/active-approvals.sh "$dir/hooks/local/lib/"
  cp hooks/shared/__init__.py hooks/shared/approval_artifact.py \
     hooks/shared/policy_loader.py hooks/shared/audit_logger.py "$dir/hooks/shared/"
  cp policies/approval-policy.yml "$dir/policies/"
  cp hooks/local/verify-hook-manifest.sh hooks/local/stamp-hook-manifest.sh "$dir/hooks/local/"
  cp VERSION "$dir/VERSION"
  printf '# AGENTS\n\n## Fusebase Flow — workflow lifecycle overlay\n' > "$dir/AGENTS.md"
  : > "$dir/.claude/skills/fusebase-flow-health-check/SKILL.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/hooks/local/post-fusebase-update.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/hooks/local/preflight.sh"
  printf '#!/usr/bin/env bash\necho "[run-tests] 1/1 PASS"\nexit 0\n' > "$dir/hooks/tests/run-tests.sh"
  printf '#!/usr/bin/env bash\nprintf %%s "{\\"verdict\\": \\"HEALTHY\\", \\"findings\\": []}"\nexit 0\n' > "$dir/hooks/local/check-cli-flow-conflicts.sh"
  # MSYS fast-path deep-run components (D14 v4): PASS stubs so --run-hook-tests takes
  # the fast path in the fixture. run_hook_tests.py is invoked as `python3 <file>`.
  printf '#!/usr/bin/env python3\nprint("PASS: stub-fixture")\n' > "$dir/hooks/tests/run_hook_tests.py"
  printf '#!/usr/bin/env bash\necho "PASS: git-smoke stub"\nexit 0\n' > "$dir/hooks/tests/test-git-hooks-smoke.sh"
  printf '#!/usr/bin/env bash\necho "PASS: hook-manifest stub"\nexit 0\n' > "$dir/hooks/tests/test-hook-manifest.sh"
  chmod +x "$dir/hooks/local/post-fusebase-update.sh" "$dir/hooks/local/preflight.sh" \
           "$dir/hooks/tests/run-tests.sh" "$dir/hooks/local/check-cli-flow-conflicts.sh" \
           "$dir/hooks/tests/run_hook_tests.py" "$dir/hooks/tests/test-git-hooks-smoke.sh" "$dir/hooks/tests/test-hook-manifest.sh"
  ( cd "$dir" && bash hooks/local/stamp-hook-manifest.sh >/dev/null 2>&1 )   # ONE stamp
}
fx() { rm -rf "$1"; cp -R "$GOLDEN" "$1"; }   # per-scenario clone of the golden fixture
hc_stamp() { ( cd "$1" && bash hooks/local/stamp-hook-manifest.sh >/dev/null 2>&1 ); }

run_hc() {  # $1=dir; rest=args/env already exported by caller
  local dir="$1"; shift
  local out rc
  out="$(cd "$dir" && "$@" bash hooks/local/fusebase-flow-health-check.sh --no-upstream 2>&1)"; rc=$?
  printf '%s\nEXIT=%s\n' "$out" "$rc"
}

# ===== Manifest-verify CRITICAL (D4) — the retargeted core =====================

# MV0 (baseline): a matching manifest => HEALTHY/0; integrity line names file count.
mv_baseline_healthy() {
  local D="$TMP_BASE/mv-baseline"; fx "$D"
  local OUT; OUT="$(run_hc "$D" env FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || { ht_fail "mv-baseline-healthy" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "mv-baseline-healthy" "$OUT"; return; }
  echo "$OUT" | grep -qi "hook layer integrity: .* files match release" || { ht_fail "mv-baseline-healthy (no integrity OK line)" "$OUT"; return; }
  # The artifact-free check-count line; ht_m9_aged_warn_verdict_neutral asserts a stale
  # warning does not move it (M9 warnings live outside every count).
  MV_BASELINE_LOCAL_STATE="$(echo "$OUT" | grep -o '^Local state ([0-9]* checks):' | head -1)"
  ht_pass "mv-baseline-healthy (D4): matching manifest => HEALTHY/0, integrity critical reports files-match"
}

# MV-a: verify-hook-manifest.sh hangs => bounded timeout => UNVERIFIED/exit 4.
mv_verify_timeout() {
  local D="$TMP_BASE/mv-verify-timeout"; fx "$D"
  printf '#!/usr/bin/env bash\nsleep 30\n' > "$D/hooks/local/verify-hook-manifest.sh"; chmod +x "$D/hooks/local/verify-hook-manifest.sh"
  local OUT; OUT="$(run_hc "$D" env FFHC_MANIFEST_TIMEOUT=1 FFHC_TIMEOUT_KILL_GRACE=1)"
  echo "$OUT" | grep -q "Verdict: PARTIAL_UNVERIFIED" || { ht_fail "mv-verify-timeout" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=4$" || { ht_fail "mv-verify-timeout" "$OUT"; return; }
  echo "$OUT" | grep -qi "hook layer integrity: UNVERIFIED" || { ht_fail "mv-verify-timeout (no UNVERIFIED integrity item)" "$OUT"; return; }
  ht_pass "mv-verify-timeout (T8a): verify timeout => hook layer integrity UNVERIFIED => PARTIAL_UNVERIFIED/exit 4, never 0"
}

# MV-b: absent manifest => verifier rc 4 => engine exit 4 (SF8), "manifest absent".
mv_absent_manifest() {
  local D="$TMP_BASE/mv-absent"; fx "$D"
  rm -f "$D/audit/hook-layer-manifest.json"
  local OUT; OUT="$(run_hc "$D" env FFHC_MANIFEST_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: PARTIAL_UNVERIFIED" || { ht_fail "mv-absent" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=4$" || { ht_fail "mv-absent" "$OUT"; return; }
  echo "$OUT" | grep -qi "manifest absent" || { ht_fail "mv-absent (no 'manifest absent')" "$OUT"; return; }
  ht_pass "mv-absent (T8b): absent manifest => standalone verifier rc 4 => engine PARTIAL_UNVERIFIED/exit 4 (SF8: never rc 3)"
}

# MV-c: corrupt self-hash => verifier rc 2 => BROKEN/exit 2.
mv_corrupt_selfhash() {
  local D="$TMP_BASE/mv-corrupt"; fx "$D"
  python3 - "$D/audit/hook-layer-manifest.json" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
d["manifest_self_sha256"] = "0" * 64
p.write_text(json.dumps(d, indent=2) + "\n")
PY
  local OUT; OUT="$(run_hc "$D" env FFHC_MANIFEST_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "mv-corrupt" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "mv-corrupt" "$OUT"; return; }
  echo "$OUT" | grep -qi "hook layer integrity: BROKEN" || { ht_fail "mv-corrupt (no BROKEN integrity item)" "$OUT"; return; }
  ht_pass "mv-corrupt (T8c): corrupt manifest self-hash => verifier rc 2 => BROKEN/exit 2"
}

# MV-d: covered-file tamper => verifier rc 1 => FLOW_LAYER_DRIFT/exit 1, names file.
mv_covered_tamper() {
  local D="$TMP_BASE/mv-tamper"; fx "$D"
  printf '\n# tamper\n' >> "$D/hooks/tests/run-tests.sh"   # covered file, not run without --run-hook-tests
  local OUT; OUT="$(run_hc "$D" env FFHC_MANIFEST_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: FLOW_LAYER_DRIFT" || { ht_fail "mv-tamper" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=1$" || { ht_fail "mv-tamper" "$OUT"; return; }
  echo "$OUT" | grep -qi "FLOW_LAYER_DRIFT — .*run-tests.sh" || { ht_fail "mv-tamper (drift does not name the file)" "$OUT"; return; }
  ht_pass "mv-tamper (T8d): covered-file tamper => verifier rc 1 => FLOW_LAYER_DRIFT/exit 1, names the drifted file"
}

# MV-e: --fast skips the integrity critical => PARTIAL_UNVERIFIED/exit 4, never 0.
mv_fast_partial() {
  local D="$TMP_BASE/mv-fast"; fx "$D"
  local OUT; OUT="$(cd "$D" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 bash hooks/local/fusebase-flow-health-check.sh --fast 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "^EXIT=4$" || { ht_fail "mv-fast" "$OUT"; return; }
  echo "$OUT" | grep -qi "not a full health verdict" || { ht_fail "mv-fast" "$OUT"; return; }
  echo "$OUT" | grep -qi "preflight: clean" || { ht_fail "mv-fast (preflight not kept)" "$OUT"; return; }
  ht_pass "mv-fast (T8e): --fast skips the integrity critical => exit 4 + 'not a full verdict', keeps preflight (--skip-hook-tests aliases it)"
}

# MV-adaptive: --run-hook-tests is PLATFORM-ADAPTIVE (D14 v4). Verdict UNAFFECTED on
# pass (HEALTHY/0). On MSYS it takes the FAST diagnostic path; on POSIX the FULL suite.
mv_deeprun_adaptive_pass() {
  # shellcheck source=/dev/null
  . hooks/local/lib/run-with-timeout.sh
  local D="$TMP_BASE/mv-deeprun-adaptive"; fx "$D"
  local OUT; OUT="$(cd "$D" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 FFHC_TESTS_TIMEOUT=15 bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || { ht_fail "mv-deeprun-adaptive-pass" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "mv-deeprun-adaptive-pass" "$OUT"; return; }
  if ffhc_is_msys; then
    echo "$OUT" | grep -qi "run-hook-tests (MSYS fast diagnostic)" || { ht_fail "mv-deeprun-adaptive-pass (MSYS did not take the fast path)" "$OUT"; return; }
    ht_pass "mv-deeprun-adaptive-pass (D14 v4): MSYS --run-hook-tests => FAST diagnostic path, HEALTHY/0 (verdict unaffected)"
  else
    echo "$OUT" | grep -qi "run-hook-tests: .* (full suite)" || { ht_fail "mv-deeprun-adaptive-pass (POSIX did not take the full path)" "$OUT"; return; }
    ht_pass "mv-deeprun-adaptive-pass (D14 v4): POSIX --run-hook-tests => FULL suite, HEALTHY/0"
  fi
}

# MV-full-optin: --run-hook-tests-full forces the FULL run-tests.sh even on MSYS.
mv_deeprun_full_optin() {
  local D="$TMP_BASE/mv-deeprun-full"; fx "$D"
  local OUT; OUT="$(cd "$D" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 FFHC_TESTS_TIMEOUT=15 bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests-full 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || { ht_fail "mv-deeprun-full-optin" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "mv-deeprun-full-optin" "$OUT"; return; }
  echo "$OUT" | grep -qi "run-hook-tests: \[run-tests\] 1/1 PASS (full suite)" || { ht_fail "mv-deeprun-full-optin (did not force the full suite)" "$OUT"; return; }
  ht_pass "mv-deeprun-full-optin (D14 v4): --run-hook-tests-full forces the FULL run-tests.sh even on MSYS => HEALTHY/0 + full-suite line (FFHC_RUN_HOOK_TESTS_FULL=1 equivalent)"
}

# MV-fail: a forced-FAIL deep run => BROKEN/exit 2, on whichever path the platform takes
# (MSYS fast: a failing fast component; POSIX full: a failing run-tests.sh).
mv_deeprun_fail() {
  # shellcheck source=/dev/null
  . hooks/local/lib/run-with-timeout.sh
  local D="$TMP_BASE/mv-deeprun-fail"; fx "$D"
  if ffhc_is_msys; then
    printf '#!/usr/bin/env python3\nprint("FAIL: broken-fixture")\nimport sys; sys.exit(1)\n' > "$D/hooks/tests/run_hook_tests.py"
  else
    printf '#!/usr/bin/env bash\necho "FAIL: 07_x.json (desc) -> expected=deny got=allow"\nexit 1\n' > "$D/hooks/tests/run-tests.sh"; chmod +x "$D/hooks/tests/run-tests.sh"
  fi
  hc_stamp "$D"
  local OUT; OUT="$(cd "$D" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 FFHC_TESTS_TIMEOUT=10 bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "mv-deeprun-fail" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "mv-deeprun-fail" "$OUT"; return; }
  echo "$OUT" | grep -qi "run-hook-tests.*FAILURE" || { ht_fail "mv-deeprun-fail (no failure item)" "$OUT"; return; }
  ht_pass "mv-deeprun-fail (T8g/v4): forced-FAIL deep run => LOCAL_BROKEN => BROKEN/exit 2 (MSYS fast path OR POSIX full path)"
}

# MV-full-timeout: a full-path deep-run timeout => verdict UNAFFECTED (HEALTHY/0) + NOTE.
mv_deeprun_full_timeout() {
  local D="$TMP_BASE/mv-deeprun-full-timeout"; fx "$D"
  printf '#!/usr/bin/env bash\nsleep 30\n' > "$D/hooks/tests/run-tests.sh"; chmod +x "$D/hooks/tests/run-tests.sh"
  hc_stamp "$D"   # re-stamp so the sleeping stub is the manifest baseline (MATCH)
  local OUT; OUT="$(cd "$D" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 FFHC_TESTS_TIMEOUT=1 FFHC_TIMEOUT_KILL_GRACE=1 bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests-full 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || { ht_fail "mv-deeprun-full-timeout" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "mv-deeprun-full-timeout" "$OUT"; return; }
  echo "$OUT" | grep -qi "run-hook-tests: NOTE" || { ht_fail "mv-deeprun-full-timeout (no deep-run NOTE)" "$OUT"; return; }
  ht_pass "mv-deeprun-full-timeout (D5): full deep-run timeout => verdict UNAFFECTED (HEALTHY/0) + visible note"
}

mv_deeprun_unit_full_rc_contract() {
  local OUT
  OUT="$(env ROOT="$ROOT" bash <<'BASH'
set -uo pipefail
. "$ROOT/hooks/local/lib/run-with-timeout.sh"
. "$ROOT/hooks/local/lib/hook-integrity-check.sh"
FFHC_TESTS_TIMEOUT=1
ffhc_run_bounded() { :; }

LOCAL_OK=(); LOCAL_BROKEN=(); DEEP_RUN_NOTES=()
FFHC_LAST_OUT='[run-tests] 1/1 PASS'; FFHC_LAST_RC=143
FFHC_LAST_TIMED_OUT=0; FFHC_LAST_SKIPPED=0
_ffhc_deep_run_full
printf 'rc143 ok=%s broken=%s notes=%s\n' "${#LOCAL_OK[@]}" "${#LOCAL_BROKEN[@]}" "${#DEEP_RUN_NOTES[@]}"

LOCAL_OK=(); LOCAL_BROKEN=(); DEEP_RUN_NOTES=()
FFHC_LAST_OUT='[run-tests] 1/1 PASS'; FFHC_LAST_RC=0
FFHC_LAST_TIMED_OUT=0; FFHC_LAST_SKIPPED=0
_ffhc_deep_run_full
printf 'rc0 ok=%s broken=%s notes=%s\n' "${#LOCAL_OK[@]}" "${#LOCAL_BROKEN[@]}" "${#DEEP_RUN_NOTES[@]}"
BASH
)"
  echo "$OUT" | grep -q '^rc143 ok=0 broken=1 notes=0$' || { ht_fail "mv-deeprun-unit-full-rc-contract (strict PASS + rc=143 must be LOCAL_BROKEN)" "$OUT"; return; }
  echo "$OUT" | grep -q '^rc0 ok=1 broken=0 notes=0$' || { ht_fail "mv-deeprun-unit-full-rc-contract (strict PASS + rc=0 positive control)" "$OUT"; return; }
  ht_pass "mv-deeprun-unit-full-rc-contract (A2): strict PASS requires rc=0; rc=143 => LOCAL_BROKEN, rc=0 => LOCAL_OK"
}

mv_deeprun_unit_fast_rc_contract() {
  local OUT
  OUT="$(env ROOT="$ROOT" bash <<'BASH'
set -uo pipefail
. "$ROOT/hooks/local/lib/hook-integrity-check.sh"
FFHC_TESTS_TIMEOUT=1
ffhc_run_bounded() {
  case "$FFHC_CASE" in
    rc143) FFHC_LAST_OUT='PASS: x'; FFHC_LAST_RC=143 ;;
    empty) FFHC_LAST_OUT=''; FFHC_LAST_RC=0 ;;
    pass)  FFHC_LAST_OUT='PASS: x'; FFHC_LAST_RC=0 ;;
  esac
  FFHC_LAST_TIMED_OUT=0; FFHC_LAST_SKIPPED=0
}
for FFHC_CASE in rc143 empty pass; do
  LOCAL_OK=(); LOCAL_BROKEN=(); DEEP_RUN_NOTES=()
  _ffhc_deep_run_fast
  printf '%s ok=%s broken=%s notes=%s\n' "$FFHC_CASE" "${#LOCAL_OK[@]}" "${#LOCAL_BROKEN[@]}" "${#DEEP_RUN_NOTES[@]}"
done
BASH
)"
  echo "$OUT" | grep -q '^rc143 ok=0 broken=1 notes=0$' || { ht_fail "mv-deeprun-unit-fast-rc-contract (PASS row + rc=143 must be LOCAL_BROKEN)" "$OUT"; return; }
  echo "$OUT" | grep -q '^empty ok=0 broken=1 notes=0$' || { ht_fail "mv-deeprun-unit-fast-rc-contract (empty + rc=0 must be LOCAL_BROKEN)" "$OUT"; return; }
  echo "$OUT" | grep -q '^pass ok=1 broken=0 notes=0$' || { ht_fail "mv-deeprun-unit-fast-rc-contract (PASS row + rc=0 positive control)" "$OUT"; return; }
  ht_pass "mv-deeprun-unit-fast-rc-contract (A2): nested helper rejects rc!=0 and 0/0; PASS + rc=0 => LOCAL_OK"
}

# ---- Retained bounded-execution coverage (cheap, distinct paths) --------------

# HT6 (AC6): no timeout binary => bounded ops SKIPPED (not run unbounded) =>
# PARTIAL_UNVERIFIED/exit 4, no hang. The anti-hang safety property.
ht6_no_timeout_bin() {
  local D="$TMP_BASE/ht6-no-timeout-bin"; fx "$D"
  local OUT; OUT="$(run_hc "$D" env FFHC_FORCE_NO_TIMEOUT=1)"
  echo "$OUT" | grep -q "Verdict: PARTIAL_UNVERIFIED" || { ht_fail "ht6-no-timeout-bin" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=4$" || { ht_fail "ht6-no-timeout-bin" "$OUT"; return; }
  echo "$OUT" | grep -qi "no timeout binary" || { ht_fail "ht6-no-timeout-bin" "$OUT"; return; }
  ht_pass "ht6-no-timeout-bin (AC6): no timeout/gtimeout => bounded ops skipped => PARTIAL_UNVERIFIED/exit 4 (no hang)"
}

# WS4: --fast PARTIAL surfaces the knob NAMES + current effective VALUES; platform
# defaults applied (MSYS 60/120, POSIX 30/60).
ht_ws4_knob_surfacing() {
  local D="$TMP_BASE/ws4-msys-defaults"; fx "$D"
  # shellcheck source=/dev/null
  . hooks/local/lib/run-with-timeout.sh
  local exp_pre exp_tests plat
  if ffhc_is_msys; then exp_pre=60; exp_tests=120; plat="MSYS/Git-Bash"; else exp_pre=30; exp_tests=60; plat="POSIX"; fi
  local OUT; OUT="$(cd "$D" && env -u FFHC_PREFLIGHT_TIMEOUT -u FFHC_TESTS_TIMEOUT -u FFHC_FETCH_TIMEOUT -u FFHC_CONFLICT_TIMEOUT bash hooks/local/fusebase-flow-health-check.sh --fast 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "^EXIT=4$" || { ht_fail "ws4-knob-surfacing" "$OUT"; return; }
  echo "$OUT" | grep -q "Current effective timeout budgets" || { ht_fail "ws4-knob-surfacing (no knob-values recommendation)" "$OUT"; return; }
  echo "$OUT" | grep -qF "FFHC_PREFLIGHT_TIMEOUT=${exp_pre}s" || { ht_fail "ws4-knob-surfacing (preflight default != ${exp_pre}s for $plat)" "$OUT"; return; }
  echo "$OUT" | grep -qF "FFHC_TESTS_TIMEOUT=${exp_tests}s" || { ht_fail "ws4-knob-surfacing (tests default != ${exp_tests}s for $plat)" "$OUT"; return; }
  ht_pass "ws4-knob-surfacing (WS4): $plat defaults (preflight ${exp_pre}s / tests ${exp_tests}s) + knob names+values surfaced in the PARTIAL recommendation"
}

# ---- WS6: BACKWARD-COMPATIBLE dual-marker migration + install hygiene (NO engine) -
ht_ws6_preflight_dual_accept() {
  local D="$TMP_BASE/ws6-preflight"
  rm -rf "$D"; mkdir -p "$D"
  cp hooks/local/preflight.sh "$D/preflight.sh"
  local ere
  ere="$(grep -oE 'grep -qE "\^## Fuse\[bB\]ase Flow[^"]*workflow lifecycle overlay"' "$D/preflight.sh" | head -1 | sed -E 's/^grep -qE "//; s/"$//')"
  [ -n "$ere" ] || { ht_fail "ws6-preflight-dual-accept (could not extract the real §5e ERE from preflight.sh — predicate regressed?)" "$(grep -n 'lifecycle overlay' "$D/preflight.sh")"; return; }
  printf '# AGENTS\n\n## Fusebase Flow — workflow lifecycle overlay\n' > "$D/agents-old.md"
  printf '# AGENTS\n\n## FuseBase Flow — workflow lifecycle overlay\n' > "$D/agents-new.md"
  printf '# AGENTS\n\n## Unrelated heading\n' > "$D/agents-none.md"
  grep -qE "$ere" "$D/agents-old.md" || { ht_fail "ws6-preflight-dual-accept (OLD rejected by the REAL §5e ERE)" "ere=$ere"; return; }
  grep -qE "$ere" "$D/agents-new.md" || { ht_fail "ws6-preflight-dual-accept (NEW rejected by the REAL §5e ERE)" "ere=$ere"; return; }
  if grep -qE "$ere" "$D/agents-none.md"; then ht_fail "ws6-preflight-dual-accept (REAL §5e ERE matched a non-marker heading)" "ere=$ere"; return; fi
  ht_pass "ws6-preflight-dual-accept (WS6): the REAL §5e ERE from preflight.sh accepts OLD+NEW markers, rejects a non-marker heading"
}

ht_ws6_migrate_idempotent() {
  local D="$TMP_BASE/ws6-migrate"
  rm -rf "$D"; mkdir -p "$D"
  local F="$D/agents.md"
  printf '# proj\n\n## Fusebase Flow — workflow lifecycle overlay\n\nbody\n' > "$F"
  # shellcheck source=/dev/null
  eval "$(awk '/^ff_migrate_marker\(\) \{/{p=1} p{print} p&&/^}/{exit}' hooks/local/post-fusebase-update.sh)"
  ff_migrate_marker "$F" "## Fusebase Flow — workflow lifecycle overlay" "## FuseBase Flow — workflow lifecycle overlay" || { ht_fail "ws6-migrate-idempotent (first migrate returned nonzero)" "$(cat "$F")"; return; }
  grep -qF "## FuseBase Flow — workflow lifecycle overlay" "$F" || { ht_fail "ws6-migrate-idempotent (NEW marker absent after migrate)" "$(cat "$F")"; return; }
  grep -qF "## Fusebase Flow — workflow lifecycle overlay" "$F" && { ht_fail "ws6-migrate-idempotent (OLD marker survived)" "$(cat "$F")"; return; }
  [ "$(grep -cF "## FuseBase Flow — workflow lifecycle overlay" "$F")" -eq 1 ] || { ht_fail "ws6-migrate-idempotent (double NEW marker)" "$(cat "$F")"; return; }
  local BEFORE; BEFORE="$(cat "$F")"
  ff_migrate_marker "$F" "## Fusebase Flow — workflow lifecycle overlay" "## FuseBase Flow — workflow lifecycle overlay" && { ht_fail "ws6-migrate-idempotent (2nd migrate claimed a rewrite on an already-NEW file)" ""; return; }
  [ "$(cat "$F")" = "$BEFORE" ] || { ht_fail "ws6-migrate-idempotent (2nd migrate changed the file)" "$(cat "$F")"; return; }
  ht_pass "ws6-migrate-idempotent (WS6): post-fusebase-update ff_migrate_marker rewrites OLD->NEW once, idempotent"
}

ht_ws6_install_append_idempotent() {
  local D="$TMP_BASE/ws6-append"
  rm -rf "$D"; mkdir -p "$D/overlays"
  local TMPL="$D/overlays/agents-md-overlay.md"
  cp hooks/local/fusebase-flow-overlays/agents-md-overlay.md "$TMPL"
  local REPORT="$D/report.txt"; : > "$REPORT"
  # shellcheck source=/dev/null
  eval "$(awk '/^append_overlay\(\) \{/{p=1} p{print} p&&/^}/{exit}' install.sh)"
  command -v append_overlay >/dev/null 2>&1 || { ht_fail "ws6-install-append (could not source append_overlay from install.sh — function regressed/renamed?)" ""; return; }
  local newm="## FuseBase Flow — workflow lifecycle overlay" oldm="## Fusebase Flow — workflow lifecycle overlay"
  local F="$D/AGENTS.md"
  printf '# fresh proj\n' > "$F"
  append_overlay "$F" "$TMPL" "$newm" "$oldm" >/dev/null 2>&1
  [ "$(grep -cE "^## Fuse[bB]ase Flow — workflow lifecycle overlay" "$F")" -eq 1 ] || { ht_fail "ws6-install-append (fresh append not exactly 1 marker)" "$(cat "$F")"; return; }
  append_overlay "$F" "$TMPL" "$newm" "$oldm" >/dev/null 2>&1
  [ "$(grep -cE "^## Fuse[bB]ase Flow — workflow lifecycle overlay" "$F")" -eq 1 ] || { ht_fail "ws6-install-append (DOUBLE-append on 2nd run — real guard regressed)" "$(cat "$F")"; return; }
  printf '# legacy proj\n\n## Fusebase Flow — workflow lifecycle overlay\n' > "$F"
  append_overlay "$F" "$TMPL" "$newm" "$oldm" >/dev/null 2>&1
  [ "$(grep -cE "^## Fuse[bB]ase Flow — workflow lifecycle overlay" "$F")" -eq 1 ] || { ht_fail "ws6-install-append (re-appended onto OLD-marker legacy tree — real OLD-marker guard regressed)" "$(cat "$F")"; return; }
  ht_pass "ws6-install-append-idempotent (WS6): the REAL install.sh append_overlay runs once on a fresh file, no double-append, dual-marker guard skips a legacy tree"
}

# ---- M9: stale-approval visibility (verdict-neutral) --------------------------

# <dir> <filename> <action> <created-days-ago|none> <expires-days-from-now> [json array]
# TRIPWIRE (MSYS): the artifact path crosses into a WINDOWS python, which cannot resolve an
# MSYS "/tmp/..." path — hand it the native form or the file lands nowhere and the scenario
# passes for the wrong reason.
m9_artifact() {
  local d="$1" f="$2"; shift 2
  local nat; nat="$( cd "$d" && { pwd -W 2>/dev/null || pwd; } )"
  MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$nat/$f" "$@" <<'PY'
import datetime, json, sys
path, action, created, expires = sys.argv[1:5]
extra = sys.argv[5] if len(sys.argv) > 5 else ""
now = datetime.datetime.now(datetime.timezone.utc)
FMT = "%Y-%m-%dT%H:%M:%SZ"
d = {"schema_version": 2, "action": action, "scope": "m9-test",
     "expires_at": (now + datetime.timedelta(days=float(expires))).strftime(FMT)}
if created != "none":
    d["created_at"] = (now - datetime.timedelta(days=float(created))).strftime(FMT)
if action == "protected_path_edit":
    d["paths"] = json.loads(extra) if extra else ["policies/protected-paths.yml"]
else:
    d["deferred_checks"] = json.loads(extra) if extra else []
with open(path, "w", encoding="utf-8", newline="\n") as fh:
    fh.write(json.dumps(d, indent=2) + "\n")
PY
}

# Discriminator (RED at 85b97dd): an AGED still-active protected_path_edit is merely LISTED
# today. After M9 it draws an explicit warning naming path + age + expiry, while the verdict,
# the 'Local state (N checks)' count, and the exit code stay exactly as the artifact-free
# baseline. HEALTHY/0 is itself the verdict-neutrality proof: an entry in LOCAL_DRIFT,
# LOCAL_BROKEN, LOCAL_UNVERIFIED or LOCAL_DEFERRED moves the verdict off HEALTHY by
# precedence, so it could not survive this assertion.
ht_m9_aged_warn_verdict_neutral() {
  local D="$TMP_BASE/m9-aged"; fx "$D"
  m9_artifact "$D/state/approvals" "protected_path_edit-legacy-20260401.json" \
    protected_path_edit 94 365 '["config/deploy.yml","policies/protected-paths.yml"]'
  local OUT; OUT="$(run_hc "$D" env FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10)"
  local f=""
  echo "$OUT" | grep -q "Approval age warnings (1" || f="$f [no APPROVAL_WARNINGS block — the aged artifact is only listed]"
  echo "$OUT" | grep -q "^  ! protected_path_edit-legacy-20260401.json: age=94d" || f="$f [warning missing or does not carry the age]"
  echo "$OUT" | grep -q "^  ! .*expires=2" || f="$f [warning does not name the expiry]"
  echo "$OUT" | grep -q "^  ! .*protected paths: config/deploy.yml" || f="$f [warning does not name the protected path(s)]"
  echo "$OUT" | grep -q "Active approval artifacts (1)" || f="$f [the artifact stopped being reported as active — a warning must invalidate nothing]"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || f="$f [verdict moved: the warning entered a verdict array]"
  echo "$OUT" | grep -q "^EXIT=0$" || f="$f [exit status moved off 0]"
  echo "$OUT" | grep -qE "^  (✗|⚠|\?|⊘) .*age=94d" && f="$f [the warning was ALSO recorded as drift/broken/unverified/deferred]"
  if [ -n "${MV_BASELINE_LOCAL_STATE:-}" ]; then
    echo "$OUT" | grep -qF "$MV_BASELINE_LOCAL_STATE" || f="$f [the 'Local state (N checks)' count changed vs the artifact-free baseline: $MV_BASELINE_LOCAL_STATE]"
  fi
  if [ -z "$f" ]; then
    ht_pass "m9-aged-warn-verdict-neutral (M9): aged active protected_path_edit => explicit warning with path+age+expiry, still ACTIVE, verdict/count/exit unchanged (HEALTHY/0)"
  else
    ht_fail "m9-aged-warn-verdict-neutral" "$f
$OUT"
  fi
}

# Negative controls in ONE engine run (cost discipline D14.4): a FRESH protected_path_edit
# must not warn; an AGED health_check_deferral must not warn (it authorizes no protected
# path); and EXCEPTION_IN_EFFECT must still classify off that same deferral — the
# classification the array contract exists to protect.
ht_m9_negative_controls() {
  local D="$TMP_BASE/m9-negative"; fx "$D"
  printf '# proj\n\nno overlay marker here\n' > "$D/CLAUDE.md"   # => claude_md_overlay drift
  m9_artifact "$D/state/approvals" "protected_path_edit-fresh-20260730.json" \
    protected_path_edit 0 1 '["config/deploy.yml"]'
  m9_artifact "$D/state/approvals" "health_check_deferral-old-20260401.json" \
    health_check_deferral 94 365 '["claude_md_overlay"]'
  local OUT; OUT="$(run_hc "$D" env FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10)"
  local f=""
  echo "$OUT" | grep -q "Approval age warnings" && f="$f [a fresh approval and/or an aged DEFERRAL produced a staleness warning]"
  echo "$OUT" | grep -q "Verdict: EXCEPTION_IN_EFFECT" || f="$f [EXCEPTION_IN_EFFECT stopped classifying — the deferral path regressed]"
  echo "$OUT" | grep -q "^EXIT=3$" || f="$f [EXCEPTION_IN_EFFECT exit is no longer 3]"
  echo "$OUT" | grep -q "Active approval artifacts (2)" || f="$f [both artifacts should still be reported active]"
  echo "$OUT" | grep -q "⊘ CLAUDE.md overlay block: MISSING" || f="$f [the deferred item was not reclassified to LOCAL_DEFERRED]"
  if [ -z "$f" ]; then
    ht_pass "m9-negative-controls (M9): fresh approval => no warning, aged health_check_deferral => no warning, EXCEPTION_IN_EFFECT still classifies (exit 3)"
  else
    ht_fail "m9-negative-controls" "$f
$OUT"
  fi
}

# Unit-level (NO engine run): the array contract itself. A missing created_at is
# unknown-age -> warns; an EXPIRED artifact is neither active nor warned; ARTIFACT_NOTES
# stays exactly one line per artifact and carries no age text (overloading it is what
# would break EXCEPTION_IN_EFFECT classification); and a LOWERED local threshold is honored.
ht_m9_unit_array_contract() {
  local D="$TMP_BASE/m9-unit"; rm -rf "$D"; mkdir -p "$D/state/approvals" "$D/policies"
  # The SHIPPED base policy, not an empty dir: without it local_override_may_relax is absent, the
  # tighten-only layer never runs, and every local threshold merges plainly — the 'lowered' and
  # 'broken' scenarios below would then assert nothing about tighten-only at all.
  cp "$ROOT/policies/approval-policy.yml" "$D/policies/"
  m9_artifact "$D/state/approvals" "protected_path_edit-nocreated-20260401.json" \
    protected_path_edit none 365 '["config/deploy.yml"]'
  m9_artifact "$D/state/approvals" "protected_path_edit-expired-20260401.json" \
    protected_path_edit 94 -1 '["config/deploy.yml"]'
  m9_artifact "$D/state/approvals" "protected_path_edit-twodays-20260728.json" \
    protected_path_edit 2 365 '["config/deploy.yml"]'
  local OUT
  OUT="$(env ROOT="$ROOT" D="$D" bash <<'BASH'
set -uo pipefail
. "$ROOT/hooks/local/lib/active-approvals.sh"
report() {   # <label>
  ACTIVE_ARTIFACTS=(); ARTIFACT_NOTES=(); DEFERRED_CHECKS=(); DEFERRED_BY_ARTIFACT=()
  APPROVAL_WARNINGS=(); APPROVAL_POLICY_ERRORS=()
  ffhc_collect_active_approvals
  printf '%s active=%s notes=%s warns=%s policyerr=%s\n' "$1" "${#ACTIVE_ARTIFACTS[@]}" \
    "${#ARTIFACT_NOTES[@]}" "${#APPROVAL_WARNINGS[@]}" "${#APPROVAL_POLICY_ERRORS[@]}"
  for x in "${ARTIFACT_NOTES[@]}"; do printf '%s NOTE %s\n' "$1" "$x"; done
  for x in "${APPROVAL_WARNINGS[@]}"; do printf '%s WARN %s\n' "$1" "$x"; done
  for x in "${APPROVAL_POLICY_ERRORS[@]}"; do printf '%s POLICYERR %s\n' "$1" "$x"; done
}
cd "$D"
report default
printf 'stale_approval_warn_after_days: 1\n' > policies/approval-policy.local.yml
report lowered
# FAIL CLOSED: a local override the tighten-only validation REJECTS makes the merged policy
# unreadable, so acceptance strictness is unknown. Reporting a configuration error and NO active
# artifact is the only honest outcome; substituting strict=false + the shipped threshold is what
# let a file enabling strict_approvals disable its own strict mode.
printf 'strict_approvals: true\nstale_approval_warn_after_days: 30\n' > policies/approval-policy.local.yml
report broken
rm -f policies/approval-policy.local.yml state/approvals/*.json
report noartifacts-brokenpolicy-control
printf 'strict_approvals: true\nstale_approval_warn_after_days: 30\n' > policies/approval-policy.local.yml
report noartifacts-brokenpolicy
BASH
)"
  local f=""
  echo "$OUT" | grep -q '^default active=2 notes=2 warns=1 policyerr=0$' || f="$f [default threshold: expected 2 active / 2 notes / 1 warn / 0 policy errors]"
  echo "$OUT" | grep -q '^default WARN protected_path_edit-nocreated-20260401.json: age=unknown (no created_at); threshold=7d; expires=2' || f="$f [missing created_at did not produce an age=unknown warning naming the threshold+expiry]"
  echo "$OUT" | grep -q 'WARN protected_path_edit-expired-' && f="$f [an EXPIRED artifact was warned about — it authorizes nothing]"
  echo "$OUT" | grep -q 'NOTE protected_path_edit-expired-' && f="$f [an EXPIRED artifact was reported ACTIVE]"
  echo "$OUT" | grep -qE '^default NOTE [^ ]+\.json: paths=1 status=(active|legacy-no-expiry) expires=[^ ]+ scope="m9-test"$' || f="$f [ARTIFACT_NOTES shape changed — the note must stay one line of status text]"
  echo "$OUT" | grep -E '^default NOTE ' | grep -qE 'age=|STALE_WARN' && f="$f [age text leaked into ARTIFACT_NOTES — that is the overload M9 forbids]"
  echo "$OUT" | grep -q '^lowered active=2 notes=2 warns=2 policyerr=0$' || f="$f [a LOWERED local threshold (1d) was not honored: the 2-day-old artifact should also warn]"
  echo "$OUT" | grep -q '^lowered WARN protected_path_edit-twodays-20260728.json: age=2d; threshold=1d;' || f="$f [the lowered-threshold warning does not report the local threshold]"
  echo "$OUT" | grep -q '^broken active=0 notes=0 warns=0 policyerr=1$' || f="$f [FAIL-OPEN: a REJECTED local override (strict_approvals: true + a raised threshold) was swallowed — expected 0 active / 1 configuration error, got: $(echo "$OUT" | grep '^broken active=' || echo none)]"
  echo "$OUT" | grep -q '^broken POLICYERR approval-policy did not load: .*stale_approval_warn_after_days' || f="$f [the configuration error does not name approval-policy and the offending key]"
  echo "$OUT" | grep -q '^noartifacts-brokenpolicy-control active=0 notes=0 warns=0 policyerr=0$' || f="$f [PRECONDITION: an empty approvals dir with a VALID policy must report no policy error]"
  echo "$OUT" | grep -q '^noartifacts-brokenpolicy active=0 notes=0 warns=0 policyerr=1$' || f="$f [a broken policy went unreported when no artifact was on disk — the probe must not depend on the artifact loop running]"
  if [ -z "$f" ]; then
    ht_pass "m9-unit-array-contract (M9): unknown-age warns, expired neither active nor warned, ARTIFACT_NOTES stays one status-only line, lowered local threshold honored, an unloadable policy reports a configuration error and activates nothing (with or without artifacts on disk)"
  else
    ht_fail "m9-unit-array-contract" "$f
$OUT"
  fi
}

# T25: force the historical ambiguous state where `kill -0` keeps saying alive after the
# bounded wrapper published completion. The done record must win, preserve rc, and reap promptly.
ht_t25_msys_completion_reap() {
  # shellcheck source=/dev/null
  . hooks/local/lib/run-with-timeout.sh
  ffhc_detect_timeout
  if [ -z "$FFHC_TIMEOUT_BIN" ]; then
    ht_pass "t25-msys-completion-reap [SKIP - no timeout binary]"
    return
  fi
  local D="$TMP_BASE/t25-reap" pid rc started elapsed f="" i
  mkdir -p "$D"
  ( printf '7\n' > "$D/done"; exit 7 ) & pid=$!
  i=0
  while [ ! -s "$D/done" ] && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
  kill() {
    if [ "${1:-}" = "-0" ] && [ "${2:-}" = "$pid" ]; then return 0; fi
    builtin kill "$@"
  }
  started=$SECONDS
  ffhc_msys_wait_reap "$pid" 3 "" "" "$D/done"; rc=$?
  elapsed=$((SECONDS - started))
  unset -f kill
  [ "$rc" -eq 7 ] || f="$f [completed child rc changed: $rc]"
  [ "$elapsed" -lt 3 ] || f="$f [completion record ignored for ${elapsed}s]"

  for i in 0 7 0 7 0; do
    ffhc_run_bounded 5 bash -c "exit $i"
    [ "$FFHC_LAST_RC" -eq "$i" ] || f="$f [bounded exit $i became $FFHC_LAST_RC]"
  done
  printf '#!/usr/bin/env bash\nprintf "%%s" "$$" > "$D/child.pid"\ntrap "" TERM\nwhile :; do sleep 1; done\n' > "$D/hang.sh"
  FFHC_TIMEOUT_KILL_GRACE=1 ffhc_run_bounded 1 bash "$D/hang.sh"
  ffhc_timed_out "$FFHC_LAST_RC" || f="$f [timeout rc was $FFHC_LAST_RC]"
  pid="$(cat "$D/child.pid" 2>/dev/null || true)"
  [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null || f="$f [timed-out child $pid still alive]"
  if [ -z "$f" ]; then
    ht_pass "t25-msys-completion-reap (done record beats ambiguous kill-0; rc/timeout/cleanup preserved)"
  else
    ht_fail "t25-msys-completion-reap" "$f"
  fi
}

ht_t57_stage_progress() {
  local D="$TMP_BASE/t57-stage-progress"; fx "$D"
  printf '#!/usr/bin/env bash\nsleep 30\nexit 7\n' > "$D/hooks/local/preflight.sh"
  chmod +x "$D/hooks/local/preflight.sh"
  hc_stamp "$D"

  local pid seen=0 i=0 rc started elapsed pre_elapsed failure="" stage
  started=$SECONDS
  (
    cd "$D" || exit 99
    FFHC_PREFLIGHT_TIMEOUT=1 FFHC_TIMEOUT_KILL_GRACE=1 \
      FFHC_MANIFEST_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 \
      bash hooks/local/fusebase-flow-health-check.sh --no-upstream \
      >t57.stdout 2>t57.stderr
    printf '%s' "$?" > t57.rc
  ) & pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 100 ]; do
    if grep -q '^\[health-check\] START stage=preflight budget=1s$' "$D/t57.stderr" 2>/dev/null; then
      seen=1
      break
    fi
    sleep 0.1
    i=$((i + 1))
  done
  wait "$pid" 2>/dev/null
  elapsed=$((SECONDS - started))
  rc="$(cat "$D/t57.rc" 2>/dev/null || echo missing)"

  [ "$seen" -eq 1 ] || failure="$failure [no live preflight START before process exit]"
  grep -qE '^\[health-check\] END stage=preflight elapsed=[0-9]+s child_rc=(124|137) budget=1s$' "$D/t57.stderr" \
    || failure="$failure [no budgeted timeout END for preflight]"
  pre_elapsed="$(sed -n 's/^\[health-check\] END stage=preflight elapsed=\([0-9][0-9]*\)s .*/\1/p' "$D/t57.stderr")"
  [ -n "$pre_elapsed" ] && [ "$pre_elapsed" -le 5 ] 2>/dev/null \
    || failure="$failure [preflight exceeded 1s budget + kill/scheduling grace: ${pre_elapsed:-missing}s]"
  [ "$rc" = "4" ] || failure="$failure [health rc=$rc, expected 4]"
  grep -q '^Verdict: PARTIAL_UNVERIFIED$' "$D/t57.stdout" \
    || failure="$failure [missing PARTIAL_UNVERIFIED stdout verdict]"
  grep -q '^\[health-check\] ' "$D/t57.stdout" \
    && failure="$failure [progress leaked into stdout]"
  for stage in active-approvals local-inventory preflight hook-layer-integrity cli-flow-conflicts cli-version partial-upgrade upstream-comparison verdict-analysis recommendations report-output; do
    [ "$(grep -c "^\[health-check\] START stage=$stage " "$D/t57.stderr")" -eq 1 ] \
      && [ "$(grep -c "^\[health-check\] END stage=$stage " "$D/t57.stderr")" -eq 1 ] \
      || failure="$failure [$stage lacks one START/END pair]"
  done
  if [ -z "$failure" ]; then
    ht_pass "t57-stage-progress (live START; timeout END rc 124/137 within ${pre_elapsed}s; PARTIAL_UNVERIFIED/4; stdout unchanged; wall ${elapsed}s)"
  else
    ht_fail "t57-stage-progress" "$failure stderr=$(tr '\n' '|' < "$D/t57.stderr") stdout=$(tr '\n' '|' < "$D/t57.stdout")"
  fi
}

# ---- run everything ----------------------------------------------------------

# The synchronized AC5 fixture is isolated so this default phase stays below the source ceiling.
# shellcheck source=health-check-heartbeat.sh
. "$ROOT/hooks/tests/health-check-heartbeat.sh"

if [ "$HT_ONLY" = "ac5" ]; then
  ht_ac5_heartbeat
  ht_ac5_optins
  echo "[test-health-check-timeout] SCOPED ac5 $pass_count/$((pass_count + fail_count)) PASS"
  exit "$fail_count"
fi

if [ "$HT_ONLY" = "t57" ]; then
  build_golden
  ht_t57_stage_progress
  echo "[test-health-check-timeout] SCOPED t57 $pass_count/$((pass_count + fail_count)) PASS"
  exit "$fail_count"
fi

build_golden
mv_baseline_healthy
mv_verify_timeout
mv_absent_manifest
mv_corrupt_selfhash
mv_covered_tamper
mv_fast_partial
mv_deeprun_adaptive_pass
mv_deeprun_full_optin
mv_deeprun_fail
mv_deeprun_full_timeout
mv_deeprun_unit_full_rc_contract
mv_deeprun_unit_fast_rc_contract
ht6_no_timeout_bin
ht_ws4_knob_surfacing
ht_ws6_preflight_dual_accept
ht_ws6_migrate_idempotent
ht_ws6_install_append_idempotent
ht_m9_aged_warn_verdict_neutral
ht_m9_negative_controls
ht_m9_unit_array_contract
ht_t25_msys_completion_reap
ht_ac5_heartbeat
ht_ac5_optins

echo "[test-health-check-timeout] $pass_count/$((pass_count + fail_count)) PASS"
exit "$fail_count"
