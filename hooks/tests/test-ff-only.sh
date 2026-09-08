#!/usr/bin/env bash
# Fusebase Flow — FF_ONLY scoped-gate behavior test (F2, v3.30.6).
# Proves the scoped gate is a SUBSET that is FAIL-CLOSED by construction: it can
# never satisfy the health engine's strict "[run-tests] N/N PASS" classifier, it
# writes to a SEPARATE results file (the full-gate hook-test-results.md is never
# clobbered), a bogus/empty selection exits 2, and a scoped run with a real failure
# still exits non-zero.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: ff-only <name>" / "FAIL: ff-only <name>"; exit code = failure count.
#
# NON-RECURSION: this suite drives run-tests.sh as a SUBPROCESS scoped to a cheap,
# deterministic phase (newline-preserve) — never to `ff-only`, so it does not invoke
# itself. It is itself invoked by run-tests.sh under the `ff-only` tag.

set -uo pipefail

t32_only=0; t33_only=0; selection_only=0; t32_case=all
case "$#" in
  0) ;;
  2)
    [ "$1" = "--only" ] || exit 2
    case "$2" in t32) t32_only=1 ;; t33) t33_only=1 ;; selection) selection_only=1 ;; *) exit 2 ;; esac
    ;;
  3)
    [ "$1" = "--only" ] && [ "$2" = "t32" ] || exit 2
    case "$3" in full|both|liveness|failed|missing|core|helper) t32_only=1; t32_case="$3" ;; *) exit 2 ;; esac
    ;;
  *) exit 2 ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RT="$ROOT/hooks/tests/run-tests.sh"
FULL_RESULTS="$ROOT/state/audit/hook-test-results.md"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: ff-only $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: ff-only $1 (${2:-})"; }
finish() { echo "[test-ff-only] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$RT" ] || { bad "setup-run-tests-present" "missing $RT"; finish; }

# Source the strict PASS classifiers the health engine uses — the fail-closed proof.
. "$ROOT/hooks/local/lib/run-with-timeout.sh"

write_selection_bounds() {
    # These fixtures test dispatch/results; real timeout and process cleanup have their own phases.
    cat > "$1/hooks/local/lib/run-with-timeout.sh" <<'SH'
ffhc_detect_timeout() { FFHC_TIMEOUT_BIN=""; }
ffhc_is_msys() { return 1; }
ffhc_timed_out() { [ "${1:-}" = 124 ] || [ "${1:-}" = 137 ]; }
ffhc_run_bounded() {
  local capture
  capture="$(mktemp)" || { FFHC_LAST_OUT="capture setup failed"; FFHC_LAST_RC=125; return 0; }
  shift; "$@" > "$capture" 2>&1; FFHC_LAST_RC=$?
  FFHC_LAST_OUT="$(<"$capture")"; rm -f "$capture"
}
SH
}

if [ "$t32_only" -eq 0 ] && [ "$t33_only" -eq 0 ]; then

SELECTIONREPO="$(mktemp -d)"
trap 'rm -rf "$SELECTIONREPO"' EXIT
mkdir -p "$SELECTIONREPO/hooks/tests" "$SELECTIONREPO/hooks/local/lib" "$SELECTIONREPO/state/audit"
git init -q "$SELECTIONREPO"
write_selection_bounds "$SELECTIONREPO"
printf 'echo "PASS: newline-preserve selection-fixture"\n' > "$SELECTIONREPO/hooks/tests/test-newline-preserve.sh"
FULL_RESULTS="$SELECTIONREPO/state/audit/hook-test-results.md"
printf 'retained full result\n' > "$FULL_RESULTS"
cd "$SELECTIONREPO" || exit 1

# Canonical tag count (FF_LIST is the discovery source). A scoped run to ONE tag must
# skip (count - 1) phases — robust to future tag additions, no hardcoded 19/20.
# TRIPWIRE: clear FF_ONLY — an inherited outer scope makes FF_LIST report 1 tag, not all.
# TRIPWIRE: count RUN **and** SKIP rows. Counting RUN alone silently under-counted the moment
# a tag became opt-in/heavy (unscoped FF_LIST marks those SKIP) while a SCOPED run still emits
# a skip line for every non-selected tag — the two numbers stopped being the same number.
TAG_COUNT="$(FF_ONLY= FF_LIST=1 bash "$RT" 2>/dev/null | grep -cE '^(RUN|SKIP) ')"
if [ "$TAG_COUNT" -ge 2 ]; then
  ok "ff-list-tag-count ($TAG_COUNT canonical tags)"
else
  bad "ff-list-tag-count" "FF_LIST reported $TAG_COUNT tags (expected >= 2)"
fi

release_list="$(FF_ONLY= FF_FULL=0 FF_RELEASE=1 FF_LIST=1 bash "$RT" 2>/dev/null)"
release_count="$(printf '%s\n' "$release_list" | grep -c '^RUN  ')"
release_padded=$'\n'"$release_list"$'\n'
release_core=0; release_nonmember=0
case "$release_padded" in *$'\nRUN  cli-flow-recovery\n'*) release_core=1 ;; esac
case "$release_padded" in *$'\nSKIP newline-preserve\n'*) release_nonmember=1 ;; esac
if [ "$release_count" -eq 29 ] && [ "$release_core" -eq 1 ] && [ "$release_nonmember" -eq 1 ]; then
  ok "release-profile-is-explicit-29-tag-allowlist"
else
  bad "release-profile-is-explicit-29-tag-allowlist" "run_count=$release_count or boundary tags differ"
fi
FF_RELEASE=1 FF_ONLY=newline-preserve FF_LIST=1 bash "$RT" >/dev/null 2>&1; rp_scoped_rc=$?
FF_RELEASE=1 FF_FULL=1 FF_LIST=1 bash "$RT" >/dev/null 2>&1; rp_full_rc=$?
if [ "$rp_scoped_rc" -eq 2 ] && [ "$rp_full_rc" -eq 2 ]; then
  ok "release-profile-rejects-other-selection-modes"
else
  bad "release-profile-rejects-other-selection-modes" "FF_ONLY rc=$rp_scoped_rc FF_FULL rc=$rp_full_rc"
fi

# --- Scoped to a single cheap phase: exactly 1 `starting` marker, (count-1) SKIPs,
#     a scoped summary that the strict classifier REJECTS, and a scoped results file. ---
sc_out="$(FF_ONLY=newline-preserve bash "$RT" 2>/tmp/ff-only-sc.$$.err)"; sc_rc=$?
sc_err="$(cat /tmp/ff-only-sc.$$.err 2>/dev/null)"; rm -f "/tmp/ff-only-sc.$$.err"

starts="$(printf '%s\n' "$sc_err" | grep -c '^\[run-tests\] START tag=newline-preserve ')"
skips="$(printf '%s\n' "$sc_out" | grep -c '^SKIP (FF_ONLY):')"
want_skips=$((TAG_COUNT - 1))

[ "$starts" -eq 1 ] && ok "scoped-one-starting-marker" || bad "scoped-one-starting-marker" "got $starts starting markers (expected 1)"
[ "$skips" -eq "$want_skips" ] && ok "scoped-skip-count" || bad "scoped-skip-count" "got $skips SKIP lines (expected $want_skips = tags-1)"

# The scoped summary line carries the "(SCOPED FF_ONLY=" marker (loud, non-strict).
summary="$(printf '%s\n' "$sc_out" | grep -E '^\[run-tests\] [0-9]+/[0-9]+ PASS')"
printf '%s' "$summary" | grep -q '(SCOPED FF_ONLY=' \
  && ok "scoped-summary-marker" \
  || bad "scoped-summary-marker" "scoped summary missing '(SCOPED FF_ONLY=': [$summary]"

# THE FAIL-CLOSED PROOF: feeding the scoped output to the health engine's strict
# classifier yields ZERO PASS summary lines — a scoped run can NEVER read as a clean
# full pass. (ffhc_run_tests_pass_ok is the per-line gate; ffhc_count_pass_lines the counter.)
cpl="$(ffhc_count_pass_lines "$sc_out")"
[ "$cpl" -eq 0 ] && ok "scoped-fails-strict-classifier (ffhc_count_pass_lines=0)" \
  || bad "scoped-fails-strict-classifier" "ffhc_count_pass_lines=$cpl (expected 0 — scoped must never satisfy the strict N/N PASS gate)"
if ffhc_run_tests_pass_ok "$summary"; then
  bad "scoped-summary-rejected-by-pass-ok" "ffhc_run_tests_pass_ok accepted a scoped summary line"
else
  ok "scoped-summary-rejected-by-pass-ok"
fi

# --- Scoped run writes hook-test-results-scoped.md and leaves the full-gate file
#     hook-test-results.md UNTOUCHED (hash-compared before/after). ---
before_hash=""; [ -f "$FULL_RESULTS" ] && before_hash="$(sha256sum "$FULL_RESULTS" 2>/dev/null | cut -d' ' -f1)"
FF_ONLY=newline-preserve bash "$RT" >/dev/null 2>&1
after_hash=""; [ -f "$FULL_RESULTS" ] && after_hash="$(sha256sum "$FULL_RESULTS" 2>/dev/null | cut -d' ' -f1)"
if [ -f "$SELECTIONREPO/state/audit/hook-test-results-scoped.md" ]; then
  ok "scoped-results-file-written"
else
  bad "scoped-results-file-written" "hook-test-results-scoped.md not created by a scoped run"
fi
if [ "$before_hash" = "$after_hash" ]; then
  ok "full-results-file-untouched-by-scoped-run"
else
  bad "full-results-file-untouched-by-scoped-run" "hook-test-results.md changed across a scoped run (before=$before_hash after=$after_hash)"
fi

# --- Bogus tag => exit 2 (never a "scoped to nothing" green). ---
FF_ONLY=this-tag-does-not-exist bash "$RT" >/dev/null 2>&1; bg_rc=$?
[ "$bg_rc" -eq 2 ] && ok "bogus-tag-exit-2" || bad "bogus-tag-exit-2" "rc=$bg_rc (expected 2)"

# --- Whitespace-only / empty selection " , " => exit 2. ---
FF_ONLY=" , " bash "$RT" >/dev/null 2>&1; em_rc=$?
[ "$em_rc" -eq 2 ] && ok "empty-selection-exit-2" || bad "empty-selection-exit-2" "rc=$em_rc (expected 2)"

printf 'echo "FAIL: newline-preserve injected-failure"\nexit 1\n' > "$SELECTIONREPO/hooks/tests/test-newline-preserve.sh"
FF_ONLY=newline-preserve bash "$RT" >/dev/null 2>&1; inj_rc=$?
[ "$inj_rc" -ne 0 ] && ok "scoped-with-injected-failure-exits-nonzero (rc=$inj_rc)" \
  || bad "scoped-with-injected-failure-exits-nonzero" "scoped run with an injected failing fixture returned rc 0 (must be non-zero)"

cd "$ROOT" || exit 1
rm -rf "$SELECTIONREPO"
trap - EXIT

# --- emit_phase_diagnostics (C4/FR-27): a FAILING phase's stderr-only reason must reach BOTH the
#     harness's composed stderr and the results artifact. ffhc_run_bounded captures the phase's
#     streams into a tempfile, so a reason written outside the ^PASS:/^FAIL: contract reaches
#     neither surface unless the diagnostics replay runs — and that replay fires only when another
#     phase already fails, which is why removing it left the ordinary green suite green.
#     Driven in an ISOLATED fixture repo (its own .git => its own state/audit), with a SYNTHETIC
#     failing phase, so this is an always-running test and never touches the real results files.
#     Homed here because this file is the run-tests.sh harness-behavior suite. ---
DIAGREPO="$(mktemp -d)"
mkdir -p "$DIAGREPO/hooks/tests" "$DIAGREPO/hooks/local/lib"
cp "$RT" "$DIAGREPO/hooks/tests/run-tests.sh"
write_selection_bounds "$DIAGREPO"
( cd "$DIAGREPO" && git init -q )
DIAG_SENTINEL="FFDIAG-STDERR-ONLY-$$"
cat > "$DIAGREPO/hooks/tests/test-boot-size.sh" <<EOF
#!/usr/bin/env bash
# Synthetic failing phase: one contract FAIL line on stdout, the REASON on stderr only.
echo "FAIL: boot-size synthetic-diagnostics-probe"
echo "$DIAG_SENTINEL reason that only exists on stderr" >&2
exit 1
EOF
diag_err="$( ( cd "$DIAGREPO" && FF_ONLY=boot-size bash hooks/tests/run-tests.sh >/dev/null ) 2>&1 )"
diag_artifact="$DIAGREPO/state/audit/hook-test-results-scoped.md"
# TRIPWIRE (pipefail): match with `case`, never `producer | grep -q` — grep -q exits at the first
# match, the producer takes SIGPIPE, and the pipeline then reports 141 even on a match.
case "$diag_err" in
  *"$DIAG_SENTINEL"*) ok "phase-diagnostics-reach-composed-stderr" ;;
  *) bad "phase-diagnostics-reach-composed-stderr" "the failing phase's stderr-only reason was dropped from the harness stderr" ;;
esac
case "$diag_err" in
  *"diagnostics (unparsed phase output"*) ok "phase-diagnostics-block-labelled" ;;
  *) bad "phase-diagnostics-block-labelled" "no diagnostics block header on stderr" ;;
esac
if [ -f "$diag_artifact" ] && grep -q "$DIAG_SENTINEL" "$diag_artifact" \
   && grep -q "^## Failure diagnostics" "$diag_artifact"; then
  ok "phase-diagnostics-reach-the-results-artifact"
else
  bad "phase-diagnostics-reach-the-results-artifact" "the reason is not recoverable from $diag_artifact alone"
fi
rm -rf "$DIAGREPO"

# Opt-in members must remain absent from required runs and reachable by name.
# TRIPWIRE: this drives the MECHANISM against a SYNTHETIC member injected into a copied runner,
# never against whichever diagnostic happens to exist. Asserting on a real member is why deleting
# one diagnostic would otherwise silently delete the tier's only coverage. If the copy cannot be
# patched, the rows go RED — a mechanism that could not be driven is not a mechanism that works.
OPTINREPO="$(mktemp -d)"
mkdir -p "$OPTINREPO/hooks/tests" "$OPTINREPO/hooks/local/lib"
write_selection_bounds "$OPTINREPO"
( cd "$OPTINREPO" && git init -q )
OPTIN_RT="$OPTINREPO/hooks/tests/run-tests.sh"
# Register `optin-probe` as a tag AND as the opt-in registry's only member, and give it a phase.
# TRIPWIRE: no multi-line sed replacement here — an embedded newline in an s/// replacement is
# not portable and silently produced an UNPATCHED copy. `i\` inserts the line instead.
# TRIPWIRE: the FF_TAGS anchor is PREFIX-AGNOSTIC (`.*cli-flow-recovery)$`). It used to pin the
# whole line, `  signal-reap cli-flow-recovery)`, so adding ANY tag ahead of signal-reap silently
# unpatched the copy and turned all four opt-in rows red with "could not inject" — which is
# exactly what registering release-tag-binding did. Anchor to the tail of the array, not to a
# neighbouring tag's name.
sed -e 's/^\(.*\)cli-flow-recovery)$/\1cli-flow-recovery optin-probe)/' \
    -e 's/^FF_OPTIN_TAGS=(.*)$/FF_OPTIN_TAGS=(optin-probe)/' \
    -e '/^run_shell_phase test-run-tests-signal-reap\.sh/i\run_shell_phase test-optin-probe.sh "optin-probe"' \
    "$RT" > "$OPTIN_RT"

patched=0
grep -q 'FF_OPTIN_TAGS=(optin-probe)' "$OPTIN_RT"   && grep -q 'run_shell_phase test-optin-probe.sh "optin-probe"' "$OPTIN_RT"   && grep -q 'cli-flow-recovery optin-probe)' "$OPTIN_RT" && patched=1
OPTIN_SENTINEL="$OPTINREPO/optin-probe-executed"
# Stub standing in for a real phase script: every OTHER phase script is absent from this fixture
# repo, so run-tests' `[ -f "$script" ]` guard no-ops them and only this one can run.
cat > "$OPTINREPO/hooks/tests/test-optin-probe.sh" <<EOF
#!/usr/bin/env bash
touch "$OPTIN_SENTINEL"
echo "PASS: optin-probe stub-executed"
EOF
if [ "$patched" -ne 1 ]; then
  bad "optin-listed-skip-when-unscoped"      "could not inject a synthetic opt-in member into the runner copy"
  bad "optin-listed-run-when-named"          "could not inject a synthetic opt-in member into the runner copy"
  bad "optin-phase-not-executed-by-default-run" "could not inject a synthetic opt-in member into the runner copy"
  bad "optin-phase-executes-when-named"      "could not inject a synthetic opt-in member into the runner copy"
else
  list_unscoped="$( cd "$OPTINREPO" && FF_ONLY= FF_LIST=1 bash hooks/tests/run-tests.sh 2>/dev/null )"
  list_named="$( cd "$OPTINREPO" && FF_ONLY=optin-probe FF_LIST=1 bash hooks/tests/run-tests.sh 2>/dev/null )"
  case "$list_unscoped" in
    *"SKIP optin-probe"*) ok "optin-listed-skip-when-unscoped" ;;
    *) bad "optin-listed-skip-when-unscoped" "unscoped FF_LIST does not mark the opt-in member SKIP" ;;
  esac
  case "$list_named" in
    *"RUN  optin-probe"*) ok "optin-listed-run-when-named" ;;
    *) bad "optin-listed-run-when-named" "FF_ONLY=optin-probe FF_LIST does not mark it RUN" ;;
  esac
  # Both arms proved by EXECUTION, not by the FF_LIST advertisement — a list that disagrees with
  # what runs is the exact failure this guards.
  ( cd "$OPTINREPO" && bash hooks/tests/run-tests.sh >/dev/null 2>&1 )
  if [ -f "$OPTIN_SENTINEL" ]; then
    bad "optin-phase-not-executed-by-default-run" "an UNSCOPED run executed the opt-in phase"
  else
    ok "optin-phase-not-executed-by-default-run"
  fi
  ( cd "$OPTINREPO" && FF_ONLY=optin-probe bash hooks/tests/run-tests.sh >/dev/null 2>&1 )
  if [ -f "$OPTIN_SENTINEL" ]; then
    ok "optin-phase-executes-when-named"
  else
    bad "optin-phase-executes-when-named" "FF_ONLY=optin-probe did not execute the phase"
  fi
fi
rm -rf "$OPTINREPO"

# --- Run tiers: fast local default vs full unscoped (architecture-review step 3) ---------------
# The fast default must be structurally NON-ATTESTING — it may not write the canonical
# hook-test-results.md and may not produce a summary the strict classifier accepts — while
# FF_FULL=1 (and CI) must still produce exactly the attesting shape.
# TRIPWIRE: every child invocation clears FF_ONLY and unsets GITHUB_ACTIONS/CI. Both are
# inherited, and either one silently turns the "default" arm into a full run — the arm would
# then pass while proving nothing.
TIERREPO="$(mktemp -d)"
mkdir -p "$TIERREPO/hooks/tests" "$TIERREPO/hooks/local/lib"
cp "$RT" "$TIERREPO/hooks/tests/run-tests.sh"
write_selection_bounds "$TIERREPO"
sed -i '/^    if \[ ! -f "\$script" \]; then$/,/^    fi$/c\    [ -f "$script" ] || return 0' "$TIERREPO/hooks/tests/run-tests.sh"
( cd "$TIERREPO" && git init -q )
HEAVY_SENTINEL="$TIERREPO/heavy-phase-executed"
printf 'print("PASS: stub-fixture")\n' > "$TIERREPO/hooks/tests/run_hook_tests.py"
printf '#!/usr/bin/env bash\necho "PASS: module-size stub"\n' > "$TIERREPO/hooks/tests/test-module-size.sh"
printf '#!/usr/bin/env bash\necho "PASS: health-check-timeout stub"\n' > "$TIERREPO/hooks/tests/test-health-check-timeout.sh"
printf '#!/usr/bin/env bash\necho "PASS: git-smoke stub"\n' > "$TIERREPO/hooks/tests/test-git-hooks-smoke.sh"
cat > "$TIERREPO/hooks/tests/test-newline-preserve.sh" <<EOF
#!/usr/bin/env bash
touch "$HEAVY_SENTINEL"
echo "PASS: newline-preserve stub"
EOF
tier_run() { ( cd "$TIERREPO" && env -u GITHUB_ACTIONS -u CI FF_ONLY= "$@" bash hooks/tests/run-tests.sh 2>/dev/null ); }

fast_out="$(tier_run FF_FULL=0)"
[ -f "$TIERREPO/state/audit/hook-test-results-fast.md" ] \
  && ok "fast-default-writes-the-fast-results-file" \
  || bad "fast-default-writes-the-fast-results-file" "hook-test-results-fast.md not created by the default run"
if [ -f "$TIERREPO/state/audit/hook-test-results.md" ]; then
  bad "fast-default-cannot-write-canonical-results-file" "the fast default wrote the attesting hook-test-results.md"
else
  ok "fast-default-cannot-write-canonical-results-file"
fi
fast_summary="$(printf '%s\n' "$fast_out" | grep -E '^\[run-tests\] [0-9]+/[0-9]+ PASS')"
if ffhc_run_tests_pass_ok "$fast_summary"; then
  bad "fast-default-summary-rejected-by-strict-classifier" "ffhc_run_tests_pass_ok accepted [$fast_summary]"
else
  ok "fast-default-summary-rejected-by-strict-classifier"
fi
[ "$(ffhc_count_pass_lines "$fast_out")" -eq 0 ] \
  && ok "fast-default-scores-zero-strict-pass-lines" \
  || bad "fast-default-scores-zero-strict-pass-lines" "ffhc_count_pass_lines != 0 on a fast-default run"
if [ -f "$HEAVY_SENTINEL" ]; then
  bad "heavy-phase-not-executed-by-default-run" "a heavy phase executed on the fast local default"
else
  ok "heavy-phase-not-executed-by-default-run"
fi

full_out="$(tier_run FF_FULL=1)"
[ -f "$HEAVY_SENTINEL" ] \
  && ok "heavy-phase-executes-under-ff-full" \
  || bad "heavy-phase-executes-under-ff-full" "FF_FULL=1 did not execute the heavy phase"
[ -f "$TIERREPO/state/audit/hook-test-results.md" ] \
  && ok "full-run-writes-the-canonical-results-file" \
  || bad "full-run-writes-the-canonical-results-file" "FF_FULL=1 did not write hook-test-results.md"
full_summary="$(printf '%s\n' "$full_out" | grep -E '^\[run-tests\] [0-9]+/[0-9]+ PASS')"
if ffhc_run_tests_pass_ok "$full_summary"; then
  ok "full-run-summary-accepted-by-strict-classifier"
else
  bad "full-run-summary-accepted-by-strict-classifier" "ffhc_run_tests_pass_ok rejected [$full_summary]"
fi

# CI must never inherit the local budget tier: the CI verify job on the tagged SHA is the
# release evidence, so it takes the full path with no flag to forget.
rm -f "$HEAVY_SENTINEL"
( cd "$TIERREPO" && env -u CI FF_ONLY= FF_FULL=0 GITHUB_ACTIONS=true bash hooks/tests/run-tests.sh >/dev/null 2>&1 )
[ -f "$HEAVY_SENTINEL" ] \
  && ok "ci-env-takes-the-full-path-without-a-flag" \
  || bad "ci-env-takes-the-full-path-without-a-flag" "GITHUB_ACTIONS=true did not force the full set"
rm -rf "$TIERREPO"
fi

[ "$selection_only" -eq 0 ] || finish

# (tasks.md T32)
if [ "$t33_only" -eq 0 ]; then
COMPREPO="$(mktemp -d)"
mkdir -p "$COMPREPO/hooks/tests" "$COMPREPO/hooks/local/lib"
cp "$RT" "$COMPREPO/hooks/tests/run-tests.sh"
sed -i '/^    if \[ ! -f "\$script" \]; then$/,/^    fi$/c\    [ -f "$script" ] || return 0' "$COMPREPO/hooks/tests/run-tests.sh"
cat > "$COMPREPO/hooks/local/lib/run-with-timeout.sh" <<'SH'
ffhc_detect_timeout() { FFHC_TIMEOUT_BIN=""; }
ffhc_is_msys() { return 1; }
ffhc_timed_out() { [ "${1:-}" = 124 ] || [ "${1:-}" = 137 ]; }
ffhc_run_bounded() {
  local capture
  capture="$(mktemp)" || { FFHC_LAST_OUT="capture setup failed"; FFHC_LAST_RC=125; return 0; }
  shift; "$@" > "$capture" 2>&1; FFHC_LAST_RC=$?
  FFHC_LAST_OUT="$(<"$capture")"; rm -f "$capture"
}
SH
( cd "$COMPREPO" && git init -q )
COMP_COUNT="$COMPREPO/health-count"
COMP_ARGS="$COMPREPO/liveness-args"
cat > "$COMPREPO/hooks/tests/run_hook_tests.py" <<'PY'
print("PASS: synthetic fixture")
PY
cat > "$COMPREPO/hooks/tests/test-module-size.sh" <<'SH'
#!/usr/bin/env bash
echo "PASS: module-size synthetic"
SH
cat > "$COMPREPO/hooks/tests/test-health-check-timeout.sh" <<'SH'
#!/usr/bin/env bash
n=0
[ ! -s "$FF_COMP_COUNT" ] || read -r n < "$FF_COMP_COUNT"
n=$((n + 1)); printf '%s\n' "$n" > "$FF_COMP_COUNT"
case "${FF_COMP_HEALTH_MODE:-pass}" in
  pass) echo "PASS: health-check-timeout synthetic-health"; exit 0 ;;
  fail) echo "FAIL: health-check-timeout synthetic-health"; exit 1 ;;
  empty) exit 0 ;;
  *) exit 2 ;;
esac
SH
cat > "$COMPREPO/hooks/tests/test-liveness-bounded-run.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-standalone}" >> "$FF_COMP_ARGS"
if [ "${1:-}" = "--core-only" ]; then
  echo "PASS: liveness synthetic-core"
  echo "[test-liveness-bounded-run] 1/1 PASS (CORE-ONLY — partial, non-attesting)"
  exit 0
fi
if [ ! -f hooks/tests/test-health-check-timeout.sh ]; then
  echo "FAIL: liveness ac6-health-check-timeout-no-regression"
  exit 1
fi
bash hooks/tests/test-health-check-timeout.sh >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "PASS: liveness ac6-health-check-timeout-no-regression"
else
  echo "FAIL: liveness ac6-health-check-timeout-no-regression"
fi
echo "PASS: liveness synthetic-core"
exit "$rc"
SH
chmod +x "$COMPREPO/hooks/tests/test-health-check-timeout.sh" "$COMPREPO/hooks/tests/test-liveness-bounded-run.sh"

comp_run() {
  local only="$1" full="$2" mode="${3:-pass}"
  : > "$COMP_COUNT"; : > "$COMP_ARGS"
  ( cd "$COMPREPO" && env -u CI -u GITHUB_ACTIONS \
      FF_COMP_COUNT="$COMP_COUNT" FF_COMP_ARGS="$COMP_ARGS" FF_COMP_HEALTH_MODE="$mode" \
      FF_ONLY="$only" FF_FULL="$full" FF_PHASE_TIMEOUT=30 FFHC_HEARTBEAT_SECS=0 \
      bash hooks/tests/run-tests.sh 2>&1 )
}
comp_count() { local n=0; [ ! -s "$COMP_COUNT" ] || read -r n < "$COMP_COUNT"; printf '%s' "$n"; }
t32_case_selected() { [ "$t32_case" = all ] || [ "$t32_case" = "$1" ]; }

if t32_case_selected full; then
comp_out="$(comp_run "" 1)"; comp_rc=$?
if [ "$comp_rc" -eq 0 ] && [ "$(comp_count)" -eq 1 ] && grep -qx -- '--core-only' "$COMP_ARGS"; then
  ok "composition-full-launches-health-once"
else
  bad "composition-full-launches-health-once" "rc=$comp_rc count=$(comp_count) args=[$(tr '\n' ',' < "$COMP_ARGS")]"
fi
case "$comp_out" in
  *"health-check-timeout already accounted; dependency row omitted"*) ok "composition-explains-reduced-row-count" ;;
  *) bad "composition-explains-reduced-row-count" "composition marker missing" ;;
esac
fi

if t32_case_selected both; then
comp_out="$(comp_run "health-check-timeout,liveness" 0)"; comp_rc=$?
if [ "$comp_rc" -eq 0 ] && [ "$(comp_count)" -eq 1 ] && grep -qx -- '--core-only' "$COMP_ARGS"; then
  ok "composition-both-selected-launches-health-once"
else
  bad "composition-both-selected-launches-health-once" "rc=$comp_rc count=$(comp_count) args=[$(tr '\n' ',' < "$COMP_ARGS")]"
fi
fi

if t32_case_selected liveness; then
comp_out="$(comp_run "liveness" 0)"; comp_rc=$?
if [ "$comp_rc" -eq 0 ] && [ "$(comp_count)" -eq 1 ] && grep -qx 'standalone' "$COMP_ARGS" \
   && printf '%s\n' "$comp_out" | grep -q '^PASS: liveness ac6-health-check-timeout-no-regression$'; then
  ok "composition-liveness-only-retains-health-dependency"
else
  bad "composition-liveness-only-retains-health-dependency" "rc=$comp_rc count=$(comp_count) args=[$(tr '\n' ',' < "$COMP_ARGS")]"
fi
fi

if t32_case_selected failed; then
comp_out="$(comp_run "health-check-timeout,liveness" 0 fail)"; comp_rc=$?
if [ "$comp_rc" -ne 0 ] && [ "$(comp_count)" -eq 1 ] \
   && ! printf '%s\n' "$comp_out" | grep -q '^PASS: liveness ac6-health-check-timeout-no-regression$'; then
  ok "composition-failed-health-stays-red-without-fabricated-pass"
else
  bad "composition-failed-health-stays-red-without-fabricated-pass" "rc=$comp_rc count=$(comp_count)"
fi
fi

if t32_case_selected missing; then
mv "$COMPREPO/hooks/tests/test-health-check-timeout.sh" "$COMPREPO/test-health-check-timeout.disabled"
comp_out="$(comp_run "health-check-timeout,liveness" 0)"; comp_rc=$?
if [ "$comp_rc" -ne 0 ] && [ "$(comp_count)" -eq 0 ] \
   && ! printf '%s\n' "$comp_out" | grep -q '^PASS: liveness ac6-health-check-timeout-no-regression$'; then
  ok "composition-missing-health-stays-red"
else
  bad "composition-missing-health-stays-red" "rc=$comp_rc count=$(comp_count)"
fi
mv "$COMPREPO/test-health-check-timeout.disabled" "$COMPREPO/hooks/tests/test-health-check-timeout.sh"
fi

if t32_case_selected core; then
core_out="$(cd "$COMPREPO" && FF_COMP_COUNT="$COMP_COUNT" FF_COMP_ARGS="$COMP_ARGS" \
  bash hooks/tests/test-liveness-bounded-run.sh --core-only 2>&1)"; core_rc=$?
core_summary="$(printf '%s\n' "$core_out" | grep 'CORE-ONLY' | tail -1)"
if [ "$core_rc" -eq 0 ] && printf '%s' "$core_summary" | grep -q 'partial, non-attesting' \
   && ! ffhc_run_tests_pass_ok "$core_summary"; then
  ok "core-only-summary-rejected-as-complete-proof"
else
  bad "core-only-summary-rejected-as-complete-proof" "rc=$core_rc summary=[$core_summary]"
fi

bash "$ROOT/hooks/tests/test-liveness-bounded-run.sh" --unknown >/dev/null 2>&1; unknown_rc=$?
[ "$unknown_rc" -eq 2 ] && ok "liveness-unknown-mode-exit-2-before-work" \
  || bad "liveness-unknown-mode-exit-2-before-work" "rc=$unknown_rc"
fi
rm -rf "$COMPREPO"

# (tasks.md T32)
if t32_case_selected helper; then
HELPREPO="$(mktemp -d)"
mkdir -p "$HELPREPO/hooks/tests" "$HELPREPO/hooks/local/lib" "$HELPREPO/templates"
cp "$ROOT/hooks/tests/test-liveness-bounded-run.sh" "$HELPREPO/hooks/tests/"
cp "$ROOT/templates/handoff-implement.md" "$HELPREPO/templates/"
( cd "$HELPREPO" && git init -q )
HELP_COUNT="$HELPREPO/bounded-count"
cat > "$HELPREPO/hooks/local/lib/bounded-run.sh" <<'SH'
bounded_run() {
  local n=0
  [ ! -s "$FF_HELP_COUNT" ] || read -r n < "$FF_HELP_COUNT"
  n=$((n + 1)); printf '%s\n' "$n" > "$FF_HELP_COUNT"
  case "$n" in
    1) echo "bounded-run: still running: synthetic" >&2; echo "bounded-run: TIMEOUT: synthetic" >&2; return 124 ;;
    2) echo "bounded-run: TIMEOUT: synthetic" >&2; return 137 ;;
    3) echo "bounded-run: SKIPPED: synthetic" >&2; return 125 ;;
    *) echo "bounded-run: unexpected duplicate invocation" >&2; return 99 ;;
  esac
}
SH
cat > "$HELPREPO/hooks/local/lib/run-with-timeout.sh" <<'SH'
FFHC_NAP_OK=1
ffhc_detect_timeout() { :; }
ffhc_timed_out() { [ "${1:-}" = 124 ] || [ "${1:-}" = 137 ]; }
run_with_timeout() { shift; "$@"; }
ffhc_run_bounded() { if [ "$1" = 600 ]; then FFHC_LAST_RC=0; else FFHC_LAST_RC=124; fi; return 0; }
ffhc_run_tests_pass_ok() { return 1; }
ffhc_count_pass_lines() { echo 0; }
ffhc_select_pass_line() { :; }
ffhc_pass_line_broken_msg() { :; }
SH
helper_out="$(cd "$HELPREPO" && FF_HELP_COUNT="$HELP_COUNT" \
  bash hooks/tests/test-liveness-bounded-run.sh --core-only 2>&1)"; helper_rc=$?
helper_count=0; [ ! -s "$HELP_COUNT" ] || read -r helper_count < "$HELP_COUNT"
if [ "$helper_count" -eq 3 ] \
   && printf '%s\n' "$helper_out" | grep -q '^PASS: liveness ac3a-hang-rc-124-or-137$' \
   && printf '%s\n' "$helper_out" | grep -q '^PASS: liveness ac3a-terminal-timeout-line$' \
   && printf '%s\n' "$helper_out" | grep -q '^PASS: liveness ac3d-ignored-sigterm-sigkilled$' \
   && printf '%s\n' "$helper_out" | grep -q '^PASS: liveness ac3c-no-binary-skip-rc-125$'; then
  ok "bounded-helper-single-call-couples-output-and-status"
else
  bad "bounded-helper-single-call-couples-output-and-status" "script_rc=$helper_rc calls=$helper_count"
fi
rm -rf "$HELPREPO"
fi
fi

# (tasks.md T33)
if [ "$t32_only" -eq 0 ]; then
PHASEREPO="$(mktemp -d)"
mkdir -p "$PHASEREPO/hooks/tests" "$PHASEREPO/hooks/local/lib"
cp "$RT" "$PHASEREPO/hooks/tests/run-tests.sh"
cat > "$PHASEREPO/hooks/local/lib/run-with-timeout.sh" <<'SH'
ffhc_detect_timeout() { FFHC_TIMEOUT_BIN=""; }
ffhc_is_msys() { return 1; }
ffhc_timed_out() { [ "${1:-}" = 124 ] || [ "${1:-}" = 137 ]; }
ffhc_run_bounded() {
  local capture
  capture="$(mktemp)" || { FFHC_LAST_OUT="capture setup failed"; FFHC_LAST_RC=125; return 0; }
  shift; "$@" > "$capture" 2>&1; FFHC_LAST_RC=$?
  FFHC_LAST_OUT="$(<"$capture")"; rm -f "$capture"
}
SH
( cd "$PHASEREPO" && git init -q )
cat > "$PHASEREPO/hooks/tests/test-return-budget.sh" <<'SH'
#!/usr/bin/env bash
echo "PASS: return-budget t33-success"
SH
cat > "$PHASEREPO/hooks/tests/test-supersede-primitive.sh" <<'SH'
#!/usr/bin/env bash
echo "PASS: supersede-primitive t33-pass-before-crash"
exit 7
SH
cat > "$PHASEREPO/hooks/tests/test-rule-inventory.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$PHASEREPO/hooks/tests/test-boot-size.sh" <<'SH'
#!/usr/bin/env bash
exit 124
SH
chmod +x "$PHASEREPO/hooks/tests/"test-*.sh
phase_out="$(cd "$PHASEREPO" && FF_PHASE_TIMEOUT=37 FFHC_HEARTBEAT_SECS=0 \
  FF_ONLY=return-budget,supersede-primitive,rule-inventory,boot-size,prohibition-residency \
  bash hooks/tests/run-tests.sh 2>&1)"; phase_rc=$?

if [ "$phase_rc" -ne 0 ] \
   && printf '%s\n' "$phase_out" | grep -Eq '^\[run-tests\] START tag=return-budget timeout_budget=37s ' \
   && printf '%s\n' "$phase_out" | grep -Eq '^\[run-tests\] END tag=return-budget elapsed=[0-9]+s rc=0 timeout_budget=37s$'; then
  ok "phase-reporting-success-start-end-budget-rc"
else
  bad "phase-reporting-success-start-end-budget-rc" "success lifecycle missing or aggregate unexpectedly green"
fi
if printf '%s\n' "$phase_out" | grep -Eq '^\[run-tests\] END tag=supersede-primitive elapsed=[0-9]+s rc=7 timeout_budget=37s$' \
   && printf '%s\n' "$phase_out" | grep -q '^FAIL: test-supersede-primitive.sh crashed (exit 7) after reporting only PASS scenarios$'; then
  ok "phase-reporting-pass-only-crash-stays-red"
else
  bad "phase-reporting-pass-only-crash-stays-red" "rc7 lifecycle or harness failure missing"
fi
if printf '%s\n' "$phase_out" | grep -Eq '^\[run-tests\] END tag=boot-size elapsed=[0-9]+s rc=124 timeout_budget=37s$' \
   && printf '%s\n' "$phase_out" | grep -q '^FAIL: test-boot-size.sh exit 124 without reporting scenarios$'; then
  ok "phase-reporting-timeout-stays-red"
else
  bad "phase-reporting-timeout-stays-red" "rc124 lifecycle or zero-row failure missing"
fi
if printf '%s\n' "$phase_out" | grep -q '^\[run-tests\] START tag=prohibition-residency timeout_budget=37s label=missing$' \
   && printf '%s\n' "$phase_out" | grep -q '^\[run-tests\] END tag=prohibition-residency elapsed=0s rc=127 timeout_budget=37s$' \
   && printf '%s\n' "$phase_out" | grep -q '^FAIL: test-prohibition-residency.sh missing (selected phase did not execute)$'; then
  ok "phase-reporting-missing-selection-stays-red"
else
  bad "phase-reporting-missing-selection-stays-red" "missing lifecycle/failure row absent"
fi
if printf '%s\n' "$phase_out" | grep -q '^FAIL: test-rule-inventory.sh exit 0 without reporting scenarios$'; then
  ok "phase-reporting-zero-row-success-stays-red"
else
  bad "phase-reporting-zero-row-success-stays-red" "rc0 zero-row phase was not rejected"
fi

cat > "$PHASEREPO/hooks/tests/test-validator-evidence.sh" <<'SH'
#!/usr/bin/env bash
echo "N/A: validator-evidence synthetic-escape — forbidden"
SH
chmod +x "$PHASEREPO/hooks/tests/test-validator-evidence.sh"
na_out="$(cd "$PHASEREPO" && FF_ONLY=validator-evidence bash hooks/tests/run-tests.sh 2>&1)"; na_rc=$?
if [ "$na_rc" -ne 0 ] \
   && printf '%s\n' "$na_out" | grep -q '^FAIL: test-validator-evidence.sh reported an unauthorized N/A scenario$'; then
  ok "phase-reporting-unrelated-na-stays-red"
else
  bad "phase-reporting-unrelated-na-stays-red" "unrelated N/A escaped: rc=$na_rc"
fi

cat > "$PHASEREPO/hooks/tests/test-run-tests-signal-reap.sh" <<'SH'
#!/usr/bin/env bash
echo "N/A: signal-reap all-scenarios — off-MSYS. POSIX process-group teardown reaps the phase tree, so this defect class cannot exist here. Declared statically; owned by the required verify-windows-msys job."
SH
chmod +x "$PHASEREPO/hooks/tests/test-run-tests-signal-reap.sh"
sig_na_out="$(cd "$PHASEREPO" && FF_ONLY=signal-reap bash hooks/tests/run-tests.sh 2>&1)"; sig_na_rc=$?
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    if [ "$sig_na_rc" -ne 0 ] \
       && printf '%s\n' "$sig_na_out" | grep -q '^FAIL: test-run-tests-signal-reap.sh reported an unauthorized N/A scenario$'; then
      ok "phase-reporting-msys-signal-na-stays-red"
    else
      bad "phase-reporting-msys-signal-na-stays-red" "MSYS signal N/A escaped: rc=$sig_na_rc"
    fi ;;
  *)
    sig_na_summary="$(printf '%s\n' "$sig_na_out" | grep -E '^\[run-tests\] [0-9]+/[0-9]+ PASS' | tail -1)"
    if [ "$sig_na_rc" -eq 0 ] \
       && printf '%s\n' "$sig_na_out" | grep -Fxq 'N/A: signal-reap all-scenarios — off-MSYS. POSIX process-group teardown reaps the phase tree, so this defect class cannot exist here. Declared statically; owned by the required verify-windows-msys job.' \
       && printf '%s\n' "$sig_na_summary" | grep -q '^\[run-tests\] 0/0 PASS (SCOPED FF_ONLY='; then
      ok "phase-reporting-off-msys-signal-na-visible-excluded"
    else
      bad "phase-reporting-off-msys-signal-na-visible-excluded" "rc=$sig_na_rc summary=[$sig_na_summary]"
    fi ;;
esac
phase_summary="$(printf '%s\n' "$phase_out" | grep -E '^\[run-tests\] [0-9]+/[0-9]+ PASS' | tail -1)"
if printf '%s' "$phase_summary" | grep -q '(SCOPED FF_ONLY=' && ! ffhc_run_tests_pass_ok "$phase_summary"; then
  ok "phase-reporting-scoped-summary-remains-nonattesting"
else
  bad "phase-reporting-scoped-summary-remains-nonattesting" "summary=[$phase_summary]"
fi
rm -rf "$PHASEREPO"
fi

finish
