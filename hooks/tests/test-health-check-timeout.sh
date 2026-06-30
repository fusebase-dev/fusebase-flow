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

# ---- HT5b (AC-B3): --skip-hook-tests is an exact alias for --fast (Windows
# escape) — same exit 4, same 'not a full verdict', same hook-test skip. ----
ht5b() {
  local D="$TMP_BASE/ht5b-skip-hook-tests"
  setup_hc_fixture "$D"
  printf '#!/usr/bin/env bash\necho "FAIL: should-not-run"\nexit 9\n' > "$D/hooks/tests/run-tests.sh"; chmod +x "$D/hooks/tests/run-tests.sh"
  local OUT; OUT="$(cd "$D" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 bash hooks/local/fusebase-flow-health-check.sh --skip-hook-tests 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "^EXIT=4$" || { ht_fail "ht5b-skip-hook-tests-alias" "$OUT"; return; }
  echo "$OUT" | grep -qi "not a full health verdict" || { ht_fail "ht5b-skip-hook-tests-alias" "$OUT"; return; }
  echo "$OUT" | grep -qi "preflight: clean" || { ht_fail "ht5b-skip-hook-tests-alias" "$OUT"; return; }
  if echo "$OUT" | grep -q "FAIL: should-not-run"; then ht_fail "ht5b-skip-hook-tests-alias" "$OUT"; return; fi
  ht_pass "ht5b-skip-hook-tests-alias (AC-B3): --skip-hook-tests == --fast (exit 4, not-a-full-verdict, keeps preflight, skips hook tests)"
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

# ---- HT9 (Codex round-2 A1 / AC4b / H6): run-tests rc=0 reporting "0/0 PASS" —
# the prefix matches but ZERO tests ran (total==0). A summary that confirms a
# pass of nothing must NOT read HEALTHY => BROKEN/2. ----
ht9() {
  local HT9="$TMP_BASE/ht9-zero-zero-pass"
  setup_hc_fixture "$HT9"
  printf '#!/usr/bin/env bash\necho "[run-tests] 0/0 PASS"\nexit 0\n' > "$HT9/hooks/tests/run-tests.sh"; chmod +x "$HT9/hooks/tests/run-tests.sh"
  local OUT; OUT="$(run_hc "$HT9" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "HT9-zero-zero-pass" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "HT9-zero-zero-pass" "$OUT"; return; }
  if echo "$OUT" | grep -q "Verdict: HEALTHY"; then ht_fail "HT9-zero-zero-pass" "$OUT"; return; fi
  ht_pass "HT9-zero-zero-pass (Codex round-2 A1 / H6): run-tests '0/0 PASS' (total==0) => BROKEN / exit 2, never HEALTHY"
}

# ---- HT10 (Codex round-2 A1 / AC4b / H6): run-tests rc=0 reporting "1/2 PASS" —
# passed != total, i.e. a real failure the summary undercounts. Must NOT read
# HEALTHY => BROKEN/2. ----
ht10() {
  local HT10="$TMP_BASE/ht10-passed-lt-total"
  setup_hc_fixture "$HT10"
  printf '#!/usr/bin/env bash\necho "[run-tests] 1/2 PASS"\nexit 0\n' > "$HT10/hooks/tests/run-tests.sh"; chmod +x "$HT10/hooks/tests/run-tests.sh"
  local OUT; OUT="$(run_hc "$HT10" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "HT10-passed-lt-total" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "HT10-passed-lt-total" "$OUT"; return; }
  if echo "$OUT" | grep -q "Verdict: HEALTHY"; then ht_fail "HT10-passed-lt-total" "$OUT"; return; fi
  ht_pass "HT10-passed-lt-total (Codex round-2 A1 / H6): run-tests '1/2 PASS' (passed!=total) => BROKEN / exit 2, never HEALTHY"
}

# ---- HT11 (Codex round-2 A1 / AC4b / H6): run-tests rc=0 reporting "1/1 PASS but
# not really" — counts look clean but trailing suffix text means the summary is
# garbled/spoofed and cannot be trusted. Must NOT read HEALTHY => BROKEN/2. ----
ht11() {
  local HT11="$TMP_BASE/ht11-pass-suffix"
  setup_hc_fixture "$HT11"
  printf '#!/usr/bin/env bash\necho "[run-tests] 1/1 PASS but not really"\nexit 0\n' > "$HT11/hooks/tests/run-tests.sh"; chmod +x "$HT11/hooks/tests/run-tests.sh"
  local OUT; OUT="$(run_hc "$HT11" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "HT11-pass-suffix" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "HT11-pass-suffix" "$OUT"; return; }
  if echo "$OUT" | grep -q "Verdict: HEALTHY"; then ht_fail "HT11-pass-suffix" "$OUT"; return; fi
  ht_pass "HT11-pass-suffix (Codex round-2 A1 / H6): run-tests '1/1 PASS but not really' (trailing suffix) => BROKEN / exit 2, never HEALTHY"
}

# ---- HT12 (Codex round-2 A1 regression guard): the genuine clean "N/N PASS" path
# with N>1 (passed==total>0, no suffix) must STILL => HEALTHY/0. The count
# validation must not over-reject the legitimate summary. ----
ht12() {
  local HT12="$TMP_BASE/ht12-clean-pass-n"
  setup_hc_fixture "$HT12"
  printf '#!/usr/bin/env bash\necho "[run-tests] 3/3 PASS"\nexit 0\n' > "$HT12/hooks/tests/run-tests.sh"; chmod +x "$HT12/hooks/tests/run-tests.sh"
  local OUT; OUT="$(cd "$HT12" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 FFHC_TESTS_TIMEOUT=10 bash hooks/local/fusebase-flow-health-check.sh --no-upstream 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || { ht_fail "HT12-clean-pass-n" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "HT12-clean-pass-n" "$OUT"; return; }
  echo "$OUT" | grep -q "hook tests: \[run-tests\] 3/3 PASS" || { ht_fail "HT12-clean-pass-n" "$OUT"; return; }
  ht_pass "HT12-clean-pass-n (Codex round-2 A1 regression guard): clean '3/3 PASS' (N>1, passed==total>0, no suffix) => HEALTHY / exit 0"
}

# ---- PASS-classifier spoof table (Codex round-3 A1+A2) -----------------------
# The run-tests PASS summary is the one signal that flips the engine to HEALTHY/0,
# so the parser kept yielding new spoof edges. These fixtures LOCK the whole Codex
# table so the classifier stops regressing. Each asserts the exact verdict + exit.
#
# Two shared drivers stub run-tests to emit a crafted summary, then run the REAL
# engine with criticals fast and upstream off, isolating the PASS-line classifier.

# hc_broken_pass <name> <printf-emitted-output>: stub run-tests to print the given
# output (rc 0) and assert the engine => BROKEN / exit 2 (never HEALTHY). The
# payload is a printf format string (use \n for newlines, %% for literal %).
hc_broken_pass() {  # $1=name  $2=printf-format-for-run-tests-stdout
  local name="$1" payload="$2"
  local D="$TMP_BASE/$name"
  setup_hc_fixture "$D"
  { printf '#!/usr/bin/env bash\n'; printf 'printf '\''%s'\''\n' "$payload"; printf 'exit 0\n'; } > "$D/hooks/tests/run-tests.sh"
  chmod +x "$D/hooks/tests/run-tests.sh"
  local OUT; OUT="$(run_hc "$D" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "$name" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "$name" "$OUT"; return; }
  if echo "$OUT" | grep -q "Verdict: HEALTHY"; then ht_fail "$name" "$OUT"; return; fi
  ht_pass "$name (spoof => BROKEN/2)"
}

# hc_healthy_pass <name> <printf-emitted-output>: stub run-tests to print the given
# output (rc 0) and assert the engine => HEALTHY / exit 0 (the genuine clean path
# must NOT be over-rejected). Upstream off + criticals fast so the only variable
# is the PASS summary.
hc_healthy_pass() {  # $1=name  $2=printf-format-for-run-tests-stdout
  local name="$1" payload="$2"
  local D="$TMP_BASE/$name"
  setup_hc_fixture "$D"
  { printf '#!/usr/bin/env bash\n'; printf 'printf '\''%s'\''\n' "$payload"; printf 'exit 0\n'; } > "$D/hooks/tests/run-tests.sh"
  chmod +x "$D/hooks/tests/run-tests.sh"
  local OUT; OUT="$(cd "$D" && FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 FFHC_TESTS_TIMEOUT=10 bash hooks/local/fusebase-flow-health-check.sh --no-upstream 2>&1; echo "EXIT=$?")"
  echo "$OUT" | grep -q "Verdict: HEALTHY" || { ht_fail "$name" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=0$" || { ht_fail "$name" "$OUT"; return; }
  ht_pass "$name (clean => HEALTHY/0)"
}

# A2: two strict PASS summaries — tail -1 used to collapse them to the last clean
# line => false HEALTHY. Now ambiguous => BROKEN with the duplicate message.
ht_dup_pass() {
  local D="$TMP_BASE/spoof-two-pass-lines"
  setup_hc_fixture "$D"
  printf '#!/usr/bin/env bash\necho "[run-tests] 1/1 PASS"\necho "[run-tests] 1/1 PASS"\nexit 0\n' > "$D/hooks/tests/run-tests.sh"
  chmod +x "$D/hooks/tests/run-tests.sh"
  local OUT; OUT="$(run_hc "$D" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "spoof-two-pass-lines" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "spoof-two-pass-lines" "$OUT"; return; }
  echo "$OUT" | grep -qi "ambiguous/duplicate hook-test summary" || { ht_fail "spoof-two-pass-lines" "$OUT"; return; }
  if echo "$OUT" | grep -q "Verdict: HEALTHY"; then ht_fail "spoof-two-pass-lines" "$OUT"; return; fi
  ht_pass "spoof-two-pass-lines (Codex r3 A2): two 'N/N PASS' summaries => BROKEN/2 'ambiguous/duplicate', never HEALTHY"
}

# A2 variant: a clean PASS summary AND a later FAIL: line => the FAIL path wins
# (genuine failure), never HEALTHY.
ht_pass_then_fail() {
  local D="$TMP_BASE/spoof-pass-then-fail"
  setup_hc_fixture "$D"
  printf '#!/usr/bin/env bash\necho "[run-tests] 1/1 PASS"\necho "FAIL: 07_pretend_test.json (desc) -> expected=x got=y"\nexit 1\n' > "$D/hooks/tests/run-tests.sh"
  chmod +x "$D/hooks/tests/run-tests.sh"
  local OUT; OUT="$(run_hc "$D" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "spoof-pass-then-fail" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "spoof-pass-then-fail" "$OUT"; return; }
  if echo "$OUT" | grep -q "Verdict: HEALTHY"; then ht_fail "spoof-pass-then-fail" "$OUT"; return; fi
  ht_pass "spoof-pass-then-fail (Codex r3 A2): clean PASS summary + later FAIL: => BROKEN/2, never HEALTHY"
}

# ---- B2 defense (D-B2 / AC-B2), RED-then-GREEN ------------------------------
# The narrowed reclassification at fusebase-flow-health-check.sh:406. A run-tests
# harness that exits on a SIGNAL/timeout rc (124, or 128+sig) with no FAIL: and no
# strict N/N PASS is INCONCLUSIVE => PARTIAL_UNVERIFIED/exit 4 (advisory), NOT a
# false BROKEN. Pre-fix RED: rc!=0 + no FAIL: => BROKEN/2 unconditionally. A GENUINE
# crash rc (1..123/125..127) still => BROKEN/2 (the narrowing must not over-reach).

# B2 #1 (GREEN target): signal rc 143 (128+SIGTERM), no FAIL:, no PASS => INCONCLUSIVE.
ht_b2_signal_inconclusive() {
  local D="$TMP_BASE/b2-signal-inconclusive"
  setup_hc_fixture "$D"
  printf '#!/usr/bin/env bash\necho "partial output, no summary" >&2\nexit 143\n' > "$D/hooks/tests/run-tests.sh"; chmod +x "$D/hooks/tests/run-tests.sh"
  local OUT; OUT="$(run_hc "$D" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: PARTIAL_UNVERIFIED" || { ht_fail "b2-signal-inconclusive" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=4$" || { ht_fail "b2-signal-inconclusive" "$OUT"; return; }
  echo "$OUT" | grep -qi "HOOK_TESTS_INCONCLUSIVE" || { ht_fail "b2-signal-inconclusive" "$OUT"; return; }
  if echo "$OUT" | grep -q "Verdict: BROKEN"; then ht_fail "b2-signal-inconclusive" "$OUT"; return; fi
  ht_pass "b2-signal-inconclusive (AC-B2): signal rc=143 + no FAIL: + no PASS => HOOK_TESTS_INCONCLUSIVE/PARTIAL_UNVERIFIED/exit 4, never BROKEN"
}

# B2 #2 (regression guard): a GENUINE crash rc 3 (NOT a signal rc) STAYS BROKEN/2.
ht_b2_genuine_crash_broken() {
  local D="$TMP_BASE/b2-genuine-crash-broken"
  setup_hc_fixture "$D"
  printf '#!/usr/bin/env bash\necho "boom: cp failed" >&2\nexit 3\n' > "$D/hooks/tests/run-tests.sh"; chmod +x "$D/hooks/tests/run-tests.sh"
  local OUT; OUT="$(run_hc "$D" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "b2-genuine-crash-broken" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "b2-genuine-crash-broken" "$OUT"; return; }
  echo "$OUT" | grep -qi "harness exited rc=3" || { ht_fail "b2-genuine-crash-broken" "$OUT"; return; }
  if echo "$OUT" | grep -q "HOOK_TESTS_INCONCLUSIVE"; then ht_fail "b2-genuine-crash-broken" "$OUT"; return; fi
  ht_pass "b2-genuine-crash-broken (AC-B2 guard): genuine crash rc=3 (non-signal) STAYS BROKEN/exit 2, NOT downgraded to INCONCLUSIVE"
}

# B2 #3 (Codex BLOCKER / AC-B2): a crash-AFTER-PASS — run-tests prints a strict
# "N/N PASS" then exits on a SIGNAL rc (143 = 128+SIGTERM) with no FAIL:. The
# INCONCLUSIVE branch requires NO strict PASS; with a real PASS line present this
# is a harness that confirmed a pass then died on a signal => genuine breakage =>
# BROKEN/exit 2, NOT downgraded to INCONCLUSIVE. RED on the pre-fix predicate
# (which omitted the no-strict-PASS guard and masked this as INCONCLUSIVE/exit 4).
ht_b2_pass_then_signal_broken() {
  local D="$TMP_BASE/b2-pass-then-signal-broken"
  setup_hc_fixture "$D"
  printf '#!/usr/bin/env bash\necho "[run-tests] 1/1 PASS"\nexit 143\n' > "$D/hooks/tests/run-tests.sh"; chmod +x "$D/hooks/tests/run-tests.sh"
  local OUT; OUT="$(run_hc "$D" env FFHC_TESTS_TIMEOUT=10)"
  echo "$OUT" | grep -q "Verdict: BROKEN" || { ht_fail "b2-pass-then-signal-broken" "$OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=2$" || { ht_fail "b2-pass-then-signal-broken" "$OUT"; return; }
  if echo "$OUT" | grep -q "HOOK_TESTS_INCONCLUSIVE"; then ht_fail "b2-pass-then-signal-broken" "$OUT"; return; fi
  if echo "$OUT" | grep -q "Verdict: PARTIAL_UNVERIFIED"; then ht_fail "b2-pass-then-signal-broken" "$OUT"; return; fi
  ht_pass "b2-pass-then-signal-broken (Codex BLOCKER / AC-B2): strict 'N/N PASS' + signal rc=143 + no FAIL: => BROKEN/exit 2, NOT INCONCLUSIVE (no-strict-PASS guard)"
}

ht1; ht2; ht3; ht4; ht5; ht5b; ht6; ht7; ht8; ht9; ht10; ht11; ht12

# --- Codex round-3 spoof table, BROKEN/2 rows ---
hc_broken_pass "spoof-zero-zero"          '[run-tests] 0/0 PASS\n'
hc_broken_pass "spoof-passed-lt-total"    '[run-tests] 1/2 PASS\n'
hc_broken_pass "spoof-passed-gt-total"    '[run-tests] 2/1 PASS\n'
hc_broken_pass "spoof-leading-zero"       '[run-tests] 01/01 PASS\n'
hc_broken_pass "spoof-passed-word"        '[run-tests] 1/1 PASSED\n'
hc_broken_pass "spoof-pass-extra"         '[run-tests] 1/1 PASS extra\n'
hc_broken_pass "spoof-leading-whitespace" ' [run-tests] 1/1 PASS\n'
hc_broken_pass "spoof-midline-embedded"   'preamble [run-tests] 1/1 PASS trailing\n'
ht_dup_pass
ht_pass_then_fail

# --- B2 defense RED-then-GREEN (D-B2 / AC-B2) ---
ht_b2_signal_inconclusive
ht_b2_genuine_crash_broken
ht_b2_pass_then_signal_broken

# --- Codex round-3 spoof table, HEALTHY/0 (genuine clean) rows ---
hc_healthy_pass "clean-three-three"       '[run-tests] 3/3 PASS\n'
hc_healthy_pass "clean-trailing-space"    '[run-tests] 1/1 PASS \n'
hc_healthy_pass "clean-trailing-tab"      '[run-tests] 1/1 PASS\t\n'
hc_healthy_pass "clean-very-large-equal"  '[run-tests] 999/999 PASS\n'

echo "[test-health-check-timeout] $pass_count/$((pass_count + fail_count)) PASS"
exit "$fail_count"
