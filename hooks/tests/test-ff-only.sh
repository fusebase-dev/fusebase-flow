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

# --- Scoped to a single cheap phase: exactly 1 `starting` marker, (count-1) SKIPs,
#     a scoped summary that the strict classifier REJECTS, and a scoped results file. ---
sc_out="$(FF_ONLY=newline-preserve bash "$RT" 2>/tmp/ff-only-sc.$$.err)"; sc_rc=$?
sc_err="$(cat /tmp/ff-only-sc.$$.err 2>/dev/null)"; rm -f "/tmp/ff-only-sc.$$.err"

starts="$(printf '%s\n' "$sc_err" | grep -c '^\[run-tests\] starting ')"
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
if [ -f "$ROOT/state/audit/hook-test-results-scoped.md" ]; then
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

# --- A scoped run WITH a real failure still exits non-zero (fail-closed on failure,
#     not just on the summary shape). Inject a temporary always-fail fixture whose
#     expected decision can never match, scope to the fixtures phase, assert rc != 0.
#     TRIPWIRE: the injected fixture MUST live in the fixtures dir that run-tests.sh
#     globs ($ROOT/hooks/tests/fixtures) so the scoped fixtures phase discovers it — it
#     cannot be relocated to an isolated tmpdir without changing run-tests' TESTS_DIR
#     discovery. So it is LEAK-PROOFED with a trap that removes it on ANY exit/signal
#     (a bare `rm -f` after the run leaks the fixture if the script dies mid-run, and a
#     stray zz-*.json then poisons every future full-gate fixture loop). ---
BADFIX="$ROOT/hooks/tests/fixtures/zz-ff-only-injected-fail.json"
trap 'rm -f "$BADFIX"' EXIT
cat > "$BADFIX" <<'JSON'
{"_test":"ff-only injected failure","_handler":"pre_tool_use.py","_expected_decision":"deny","tool_name":"Read","tool_input":{"file_path":"README.md"}}
JSON
FF_ONLY=fixtures bash "$RT" >/dev/null 2>&1; inj_rc=$?
rm -f "$BADFIX"
trap - EXIT
[ "$inj_rc" -ne 0 ] && ok "scoped-with-injected-failure-exits-nonzero (rc=$inj_rc)" \
  || bad "scoped-with-injected-failure-exits-nonzero" "scoped run with an injected failing fixture returned rc 0 (must be non-zero)"

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
cp "$ROOT/hooks/local/lib/run-with-timeout.sh" "$DIAGREPO/hooks/local/lib/"
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

# --- Opt-in-only phases (architecture-review step 2) -------------------------------------------
# cli-flow-profile was a temporary diagnostic that became a REQUIRED gate phase. It proves trace
# schema/containment/redaction, not recovery correctness, so it is not release coverage. It must
# be absent from the default set and still reachable by name.
# TRIPWIRE: both arms are proved by EXECUTION in an isolated fixture repo, not by the FF_LIST
# advertisement — a list that disagrees with what runs is the exact failure this guards.
list_unscoped="$(FF_ONLY= FF_LIST=1 bash "$RT" 2>/dev/null)"
list_named="$(FF_ONLY=cli-flow-profile FF_LIST=1 bash "$RT" 2>/dev/null)"
case "$list_unscoped" in
  *"SKIP cli-flow-profile"*) ok "optin-listed-skip-when-unscoped" ;;
  *) bad "optin-listed-skip-when-unscoped" "unscoped FF_LIST does not mark cli-flow-profile SKIP" ;;
esac
case "$list_named" in
  *"RUN  cli-flow-profile"*) ok "optin-listed-run-when-named" ;;
  *) bad "optin-listed-run-when-named" "FF_ONLY=cli-flow-profile FF_LIST does not mark it RUN" ;;
esac

OPTINREPO="$(mktemp -d)"
mkdir -p "$OPTINREPO/hooks/tests" "$OPTINREPO/hooks/local/lib"
cp "$RT" "$OPTINREPO/hooks/tests/run-tests.sh"
cp "$ROOT/hooks/local/lib/run-with-timeout.sh" "$OPTINREPO/hooks/local/lib/"
( cd "$OPTINREPO" && git init -q )
OPTIN_SENTINEL="$OPTINREPO/cli-flow-profile-executed"
# Stub standing in for the real phase script: every OTHER phase script is absent from this
# fixture repo, so run-tests' `[ -f "$script" ]` guard no-ops them and only this one can run.
cat > "$OPTINREPO/hooks/tests/test-cli-flow-recovery-profile.sh" <<EOF
#!/usr/bin/env bash
touch "$OPTIN_SENTINEL"
echo "PASS: cli-flow-profile stub-executed"
EOF
( cd "$OPTINREPO" && bash hooks/tests/run-tests.sh >/dev/null 2>&1 )
if [ -f "$OPTIN_SENTINEL" ]; then
  bad "optin-phase-not-executed-by-default-run" "an UNSCOPED run executed the opt-in cli-flow-profile phase"
else
  ok "optin-phase-not-executed-by-default-run"
fi
( cd "$OPTINREPO" && FF_ONLY=cli-flow-profile bash hooks/tests/run-tests.sh >/dev/null 2>&1 )
if [ -f "$OPTIN_SENTINEL" ]; then
  ok "optin-phase-executes-when-named"
else
  bad "optin-phase-executes-when-named" "FF_ONLY=cli-flow-profile did not execute the phase"
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
cp "$ROOT/hooks/local/lib/run-with-timeout.sh" "$TIERREPO/hooks/local/lib/"
( cd "$TIERREPO" && git init -q )
HEAVY_SENTINEL="$TIERREPO/heavy-phase-executed"
printf 'print("PASS: stub-fixture")\n' > "$TIERREPO/hooks/tests/run_hook_tests.py"
printf '#!/usr/bin/env bash\necho "PASS: git-smoke stub"\n' > "$TIERREPO/hooks/tests/test-git-hooks-smoke.sh"
cat > "$TIERREPO/hooks/tests/test-rule-inventory.sh" <<EOF
#!/usr/bin/env bash
touch "$HEAVY_SENTINEL"
echo "PASS: rule-inventory stub"
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

finish
