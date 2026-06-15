#!/usr/bin/env bash
# Fusebase Flow — health-check bounded-execution + verdict/exit contract tests.
# Spec: docs/specs/health-check-fast-timeout/spec.md (the LOCKED verdict/exit
# contract, decisions H1-H6, AC1-AC8). Extracted from test-cli-flow-recovery.sh
# per FR-25 (responsibility seam: this is the timeout/verdict concern, distinct
# from CLI-vs-Flow recovery) so neither file grows past its size budget.
#
# No real network and no real slow sub-scripts: each test builds a minimal
# scratch project whose sub-scripts are STUBS (sleep to force a timeout against a
# 1s budget, or exit a crafted rc) and runs the REAL engine against them.
# Stubbing keeps these deterministic and fast (vs the real preflight/run-tests
# which take tens of seconds — those time out on impaired hosts, which is the
# whole point of this ticket).
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

# require <name> <condition-rc> <message>: record PASS/FAIL for one assertion.
# A failed assertion aborts the current fixture (returns 1) but NOT the suite, so
# remaining fixtures still run and the exit code reflects the failure count.
ht_fail() { fail_count=$((fail_count + 1)); echo "FAIL: health-check-timeout $1"; [ -n "${2:-}" ] && echo "$2" >&2; return 1; }
ht_pass() { pass_count=$((pass_count + 1)); echo "PASS: health-check-timeout $1"; }

# ---- shared fixture builders ------------------------------------------------
# Build a minimal scratch project the engine can run against with a clean
# baseline (proper AGENTS.md overlay marker + instant-OK stub sub-scripts) so
# each test isolates ONE variable. The engine resolves its lib via BASH_SOURCE
# so we copy lib/ alongside it. Per-test, overwrite the relevant stub.
hc_stub_ok_subscripts() {  # $1=dir — preflight OK, run-tests PASS, conflict HEALTHY
  local dir="$1"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/hooks/local/preflight.sh"
  printf '#!/usr/bin/env bash\necho "[run-tests] 1/1 PASS"\nexit 0\n' > "$dir/hooks/tests/run-tests.sh"
  printf '#!/usr/bin/env bash\nprintf %%s "{\\"verdict\\": \\"HEALTHY\\", \\"findings\\": []}"\nexit 0\n' > "$dir/hooks/local/check-cli-flow-conflicts.sh"
  chmod +x "$dir/hooks/local/preflight.sh" "$dir/hooks/tests/run-tests.sh" "$dir/hooks/local/check-cli-flow-conflicts.sh"
}
setup_hc_fixture() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir/hooks/local/lib" "$dir/hooks/tests" "$dir/.claude/skills/fusebase-flow-health-check" "$dir/.claude/agents"
  cp hooks/local/fusebase-flow-health-check.sh "$dir/hooks/local/"
  cp hooks/local/lib/run-with-timeout.sh "$dir/hooks/local/lib/"
  cp VERSION "$dir/VERSION"
  # Clean baseline so the inventory section adds no unrelated drift/broken items.
  printf '# AGENTS\n\n## Fusebase Flow — workflow lifecycle overlay\n' > "$dir/AGENTS.md"
  : > "$dir/.claude/skills/fusebase-flow-health-check/SKILL.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/hooks/local/post-fusebase-update.sh"
  mkdir -p "$dir/hooks/local/fusebase-flow-overlays"
  chmod +x "$dir/hooks/local/post-fusebase-update.sh"
  hc_stub_ok_subscripts "$dir"
}

# Run the engine in a fixture dir with extra env; echo "EXIT=<rc>" + the report.
run_hc() {  # $1=dir; rest=args/env already exported by caller
  local dir="$1"; shift
  local out rc
  out="$(cd "$dir" && "$@" bash hooks/local/fusebase-flow-health-check.sh 2>&1)"; rc=$?
  printf '%s\nEXIT=%s\n' "$out" "$rc"
}

# ---- HT1 (AC1): upstream git fetch unreachable => bounded + "upstream not
# verified" NOTE, and upstream alone does NOT force exit 4 (it's optional). ----
ht1() {
  local HT1="$TMP_BASE/ht1-fetch-timeout"
  setup_hc_fixture "$HT1"   # criticals are instant-OK from the baseline
  # Fake an upstream clone + a `git` stub on PATH whose `fetch` hangs.
  mkdir -p "$HT1/.fusebase-flow-source/.git" "$HT1/stubbin"
  cat > "$HT1/stubbin/git" <<'GITSTUB'
#!/usr/bin/env bash
case "$*" in
  *fetch*) sleep 30 ;;                       # network hang -> must be bounded
  *rev-parse\ --show-toplevel*) pwd ;;
  *rev-parse\ --is-shallow-repository*) echo "false" ;;
  *rev-parse\ HEAD*) echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" ;;
  *rev-parse\ origin/main*) echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" ;;
  *show\ origin/main:VERSION*) cat VERSION 2>/dev/null ;;
  *) exit 0 ;;
esac
GITSTUB
  chmod +x "$HT1/stubbin/git"
  local OUT; OUT="$(run_hc "$HT1" env "PATH=$HT1/stubbin:$PATH" FFHC_FETCH_TIMEOUT=1)"
  echo "$OUT" | grep -q "upstream not verified" || { ht_fail "HT1-fetch-timeout-bounded" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "HT1-fetch-timeout-bounded" "$OUT"; return; }
  ht_pass "HT1-fetch-timeout-bounded (AC1): fetch timeout bounded + 'upstream not verified'; upstream alone does NOT force exit 4 (exit 0)"
}

# ---- HT2 (AC2): a CRITICAL check (preflight) times out => PARTIAL_UNVERIFIED
# exit 4, never 0; the report names the unverified check. ----
ht2() {
  local HT2="$TMP_BASE/ht2-critical-timeout"
  setup_hc_fixture "$HT2"
  printf '#!/usr/bin/env bash\nsleep 30\n' > "$HT2/hooks/local/preflight.sh"; chmod +x "$HT2/hooks/local/preflight.sh"   # hangs -> timeout
  local OUT; OUT="$(run_hc "$HT2" env FFHC_PREFLIGHT_TIMEOUT=1)"
  echo "$OUT" | grep -q "Verdict: PARTIAL_UNVERIFIED" || { ht_fail "HT2-critical-timeout" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=4$" || { ht_fail "HT2-critical-timeout" "$OUT"; return; }
  echo "$OUT" | grep -qi "preflight: UNVERIFIED" || { ht_fail "HT2-critical-timeout" "$OUT"; return; }
  ht_pass "HT2-critical-timeout (AC2): critical (preflight) timeout => PARTIAL_UNVERIFIED / exit 4, names the unverified check"
}

# ---- HT3 (AC4a): a real preflight FAILURE still => BROKEN/2 even with timeouts
# in place (a completed critical that fails is breakage, not unverified). ----
ht3() {
  local HT3="$TMP_BASE/ht3-preflight-fail"
  setup_hc_fixture "$HT3"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$HT3/hooks/local/preflight.sh"; chmod +x "$HT3/hooks/local/preflight.sh"   # completes, fails
  local OUT; OUT="$(run_hc "$HT3" env FFHC_PREFLIGHT_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "HT3-preflight-fail" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "HT3-preflight-fail" "$OUT"; return; }
  ht_pass "HT3-preflight-fail (AC4a): a completed preflight failure => BROKEN / exit 2 (not UNVERIFIED) even with timeouts in place"
}

# ---- HT4 (AC4b / H6): a run-tests harness CRASH (rc!=0, no FAIL:) => BROKEN/2,
# NOT HEALTHY (the pre-existing '|| true' false-HEALTHY). ----
ht4() {
  local HT4="$TMP_BASE/ht4-harness-crash"
  setup_hc_fixture "$HT4"
  printf '#!/usr/bin/env bash\necho "boom: mktemp failed" >&2\nexit 3\n' > "$HT4/hooks/tests/run-tests.sh"; chmod +x "$HT4/hooks/tests/run-tests.sh"   # rc!=0, no FAIL:
  local OUT; OUT="$(run_hc "$HT4" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "HT4-harness-crash" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "HT4-harness-crash" "$OUT"; return; }
  echo "$OUT" | grep -qi "harness exited rc=" || { ht_fail "HT4-harness-crash" "$OUT"; return; }
  ht_pass "HT4-harness-crash (AC4b / H6): run-tests harness crash (rc!=0, no FAIL:) => BROKEN / exit 2, not HEALTHY"
}

# ---- HT5 (AC4c / AC5): --fast => exit 4 + 'not a full verdict', never 0; keeps
# preflight. ----
ht5() {
  local HT5="$TMP_BASE/ht5-fast"
  setup_hc_fixture "$HT5"
  # run-tests would PASS, but --fast must skip it; make it emit a tripwire if run.
  printf '#!/usr/bin/env bash\necho "FAIL: should-not-run"\nexit 9\n' > "$HT5/hooks/tests/run-tests.sh"; chmod +x "$HT5/hooks/tests/run-tests.sh"
  local OUT; OUT="$(cd "$HT5" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 bash hooks/local/fusebase-flow-health-check.sh --fast 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "^EXIT=4$" || { ht_fail "HT5-fast" "$OUT"; return; }
  echo "$OUT" | grep -qi "not a full health verdict" || { ht_fail "HT5-fast" "$OUT"; return; }
  echo "$OUT" | grep -qi "preflight: clean" || { ht_fail "HT5-fast" "$OUT"; return; }
  if echo "$OUT" | grep -q "FAIL: should-not-run"; then ht_fail "HT5-fast" "$OUT"; return; fi
  ht_pass "HT5-fast (AC4c / AC5): --fast => exit 4 + 'not a full verdict' + keeps preflight + skips hook tests"
}

# ---- HT6 (AC6): neither timeout nor gtimeout present => engine still returns (no
# hang, no crash) with PARTIAL_UNVERIFIED (bounded ops skipped). ----
ht6() {
  local HT6="$TMP_BASE/ht6-no-timeout-bin"
  setup_hc_fixture "$HT6"   # baseline OK stubs; the variable here is the missing timeout binary
  # Force the no-timeout-binary path deterministically (FFHC_FORCE_NO_TIMEOUT) so
  # the test doesn't depend on tearing apart PATH. The bounded criticals must be
  # SKIPPED (not run unbounded) => PARTIAL_UNVERIFIED, no hang.
  local OUT; OUT="$(run_hc "$HT6" env FFHC_FORCE_NO_TIMEOUT=1)"
  echo "$OUT" | grep -q "Verdict: PARTIAL_UNVERIFIED" || { ht_fail "HT6-no-timeout-bin" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=4$" || { ht_fail "HT6-no-timeout-bin" "$OUT"; return; }
  echo "$OUT" | grep -qi "no timeout binary" || { ht_fail "HT6-no-timeout-bin" "$OUT"; return; }
  ht_pass "HT6-no-timeout-bin (AC6): no timeout/gtimeout => bounded ops skipped => PARTIAL_UNVERIFIED / exit 4 (no hang)"
}

# ---- HT7 (AC6 escape hatch): no timeout binary BUT FFHC_ALLOW_UNBOUNDED=1 => run
# the (fast-stub) criticals unbounded => HEALTHY/0 (opt-in, never the default). ----
ht7() {
  local HT7="$TMP_BASE/ht7-no-timeout-unbounded"
  setup_hc_fixture "$HT7"
  local OUT; OUT="$(cd "$HT7" && FFHC_FORCE_NO_TIMEOUT=1 FFHC_ALLOW_UNBOUNDED=1 bash hooks/local/fusebase-flow-health-check.sh --no-upstream 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || { ht_fail "HT7-no-timeout-unbounded" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "HT7-no-timeout-unbounded" "$OUT"; return; }
  ht_pass "HT7-no-timeout-unbounded (AC6): FFHC_ALLOW_UNBOUNDED=1 opt-in runs criticals unbounded => HEALTHY/0 (never the default)"
}

# ---- HT8 (Codex A1 / AC4b / H6): run-tests rc=0 with garbled output — NO
# parsable "N/N PASS" line AND NO FAIL: line => BROKEN/2, NEVER HEALTHY. A check
# that exits clean but never CONFIRMS a pass must not read full health (the
# residual false-HEALTHY the run-tests parsing left open). The real "N/N PASS"
# path (HT7 / the baseline stub) still records OK. ----
ht8() {
  local HT8="$TMP_BASE/ht8-rc0-no-pass-no-fail"
  setup_hc_fixture "$HT8"
  # rc=0, prints chatter but neither "[run-tests] N/N PASS" nor "FAIL:".
  printf '#!/usr/bin/env bash\necho "some unrelated chatter"\nexit 0\n' > "$HT8/hooks/tests/run-tests.sh"; chmod +x "$HT8/hooks/tests/run-tests.sh"
  local OUT; OUT="$(run_hc "$HT8" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "HT8-rc0-no-pass-no-fail" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "HT8-rc0-no-pass-no-fail" "$OUT"; return; }
  echo "$OUT" | grep -qi "no parsable 'N/N PASS' line" || { ht_fail "HT8-rc0-no-pass-no-fail" "$OUT"; return; }
  if echo "$OUT" | grep -q "Verdict: HEALTHY"; then ht_fail "HT8-rc0-no-pass-no-fail" "$OUT"; return; fi
  ht_pass "HT8-rc0-no-pass-no-fail (Codex A1 / H6): run-tests rc=0 + no PASS + no FAIL => BROKEN / exit 2, never HEALTHY"
}

ht1; ht2; ht3; ht4; ht5; ht6; ht7; ht8

echo "[test-health-check-timeout] $pass_count/$((pass_count + fail_count)) PASS"
exit "$fail_count"
