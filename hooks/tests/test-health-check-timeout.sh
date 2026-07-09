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

TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-hc-timeout.$$"
mkdir -p "$TMP_BASE"
cleanup() {
  case "$TMP_BASE" in
    /tmp/fusebase-flow-hc-timeout.*|*/tmp/fusebase-flow-hc-timeout.*|*/Temp/fusebase-flow-hc-timeout.*)
      rm -rf "$TMP_BASE" ;;
  esac
}
trap cleanup EXIT

pass_count=0
fail_count=0
ht_fail() { fail_count=$((fail_count + 1)); echo "FAIL: health-check-timeout $1"; [ -n "${2:-}" ] && echo "$2" >&2; return 1; }
ht_pass() { pass_count=$((pass_count + 1)); echo "PASS: health-check-timeout $1"; }

# ---- golden fixture (built ONCE; every scenario cp -R's it) -------------------
GOLDEN="$TMP_BASE/_golden"
build_golden() {
  local dir="$GOLDEN"
  mkdir -p "$dir/hooks/local/lib" "$dir/hooks/tests" "$dir/audit" \
           "$dir/.claude/skills/fusebase-flow-health-check" "$dir/.claude/agents" \
           "$dir/hooks/local/fusebase-flow-overlays"
  cp hooks/local/fusebase-flow-health-check.sh "$dir/hooks/local/"
  cp hooks/local/lib/run-with-timeout.sh hooks/local/lib/hook-integrity-check.sh \
     hooks/local/lib/hook_manifest.py "$dir/hooks/local/lib/"
  cp hooks/local/verify-hook-manifest.sh hooks/local/stamp-hook-manifest.sh "$dir/hooks/local/"
  cp VERSION "$dir/VERSION"
  printf '# AGENTS\n\n## Fusebase Flow — workflow lifecycle overlay\n' > "$dir/AGENTS.md"
  : > "$dir/.claude/skills/fusebase-flow-health-check/SKILL.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/hooks/local/post-fusebase-update.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/hooks/local/preflight.sh"
  printf '#!/usr/bin/env bash\necho "[run-tests] 1/1 PASS"\nexit 0\n' > "$dir/hooks/tests/run-tests.sh"
  printf '#!/usr/bin/env bash\nprintf %%s "{\\"verdict\\": \\"HEALTHY\\", \\"findings\\": []}"\nexit 0\n' > "$dir/hooks/local/check-cli-flow-conflicts.sh"
  chmod +x "$dir/hooks/local/post-fusebase-update.sh" "$dir/hooks/local/preflight.sh" \
           "$dir/hooks/tests/run-tests.sh" "$dir/hooks/local/check-cli-flow-conflicts.sh"
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

build_golden

# ===== Manifest-verify CRITICAL (D4) — the retargeted core =====================

# MV0 (baseline): a matching manifest => HEALTHY/0; integrity line names file count.
mv_baseline_healthy() {
  local D="$TMP_BASE/mv-baseline"; fx "$D"
  local OUT; OUT="$(run_hc "$D" env FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || { ht_fail "mv-baseline-healthy" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "mv-baseline-healthy" "$OUT"; return; }
  echo "$OUT" | grep -qi "hook layer integrity: .* files match release" || { ht_fail "mv-baseline-healthy (no integrity OK line)" "$OUT"; return; }
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

# MV-f: --run-hook-tests deep run TIMEOUT => verdict UNAFFECTED (HEALTHY/0) + note.
mv_deeprun_timeout_note() {
  local D="$TMP_BASE/mv-deeprun-timeout"; fx "$D"
  printf '#!/usr/bin/env bash\nsleep 30\n' > "$D/hooks/tests/run-tests.sh"; chmod +x "$D/hooks/tests/run-tests.sh"
  hc_stamp "$D"   # re-stamp so the sleeping stub is the manifest baseline (MATCH)
  local OUT; OUT="$(cd "$D" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 FFHC_TESTS_TIMEOUT=1 FFHC_TIMEOUT_KILL_GRACE=1 bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || { ht_fail "mv-deeprun-timeout" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "mv-deeprun-timeout" "$OUT"; return; }
  echo "$OUT" | grep -qi "run-hook-tests: NOTE" || { ht_fail "mv-deeprun-timeout (no deep-run NOTE)" "$OUT"; return; }
  ht_pass "mv-deeprun-timeout (T8f): --run-hook-tests deep-run timeout => verdict UNAFFECTED (HEALTHY/0) + visible note"
}

# MV-g: --run-hook-tests with a FAILING suite stub => BROKEN/exit 2.
mv_deeprun_fail_broken() {
  local D="$TMP_BASE/mv-deeprun-fail"; fx "$D"
  printf '#!/usr/bin/env bash\necho "FAIL: 07_x.json (desc) -> expected=deny got=allow"\nexit 1\n' > "$D/hooks/tests/run-tests.sh"; chmod +x "$D/hooks/tests/run-tests.sh"
  hc_stamp "$D"
  local OUT; OUT="$(cd "$D" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 FFHC_TESTS_TIMEOUT=10 bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "mv-deeprun-fail" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "mv-deeprun-fail" "$OUT"; return; }
  echo "$OUT" | grep -qi "run-hook-tests: hook-test FAILURE" || { ht_fail "mv-deeprun-fail (no failure item)" "$OUT"; return; }
  ht_pass "mv-deeprun-fail (T8g): --run-hook-tests observed FAIL => LOCAL_BROKEN => BROKEN/exit 2"
}

# MV-deeprun-pass: --run-hook-tests with a passing suite stub => HEALTHY/0 + OK line.
mv_deeprun_pass() {
  local D="$TMP_BASE/mv-deeprun-pass"; fx "$D"   # golden run-tests stub already emits "[run-tests] 1/1 PASS"
  local OUT; OUT="$(cd "$D" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 FFHC_TESTS_TIMEOUT=10 bash hooks/local/fusebase-flow-health-check.sh --no-upstream --run-hook-tests 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || { ht_fail "mv-deeprun-pass" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "mv-deeprun-pass" "$OUT"; return; }
  echo "$OUT" | grep -qi "run-hook-tests: \[run-tests\] 1/1 PASS (full suite)" || { ht_fail "mv-deeprun-pass (no full-suite OK line)" "$OUT"; return; }
  ht_pass "mv-deeprun-pass (D5): --run-hook-tests passing full suite => HEALTHY/0 + LOCAL_OK deep-run line"
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

# ---- run everything ----------------------------------------------------------
mv_baseline_healthy
mv_verify_timeout
mv_absent_manifest
mv_corrupt_selfhash
mv_covered_tamper
mv_fast_partial
mv_deeprun_timeout_note
mv_deeprun_fail_broken
mv_deeprun_pass
ht6_no_timeout_bin
ht_ws4_knob_surfacing
ht_ws6_preflight_dual_accept
ht_ws6_migrate_idempotent
ht_ws6_install_append_idempotent

echo "[test-health-check-timeout] $pass_count/$((pass_count + fail_count)) PASS"
exit "$fail_count"
