#!/usr/bin/env bash
# Fusebase Flow — run-tests.sh invocation preconditions (hooks/tests/lib/run-preconditions.sh).
# Decision rows source the lib and call the check directly (function boundary, milliseconds).
# Wiring rows drive a COPY of the runner in a synthetic maintainer tree that exits at the last
# line before any output or phase, so "proceeds" means "passed every precondition". The judged
# working tree is never written to.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: run-preconditions <name>" / "FAIL: run-preconditions <name>"; exit = fail count.

set -uo pipefail

ROOT=""
_cap="$(mktemp 2>/dev/null || true)"
if [ -n "$_cap" ]; then
    git rev-parse --show-toplevel > "$_cap" 2>/dev/null || :
    IFS= read -r ROOT < "$_cap" 2>/dev/null || :
    rm -f "$_cap" 2>/dev/null
fi
[ -n "$ROOT" ] || ROOT="$(pwd)"

RT="$ROOT/hooks/tests/run-tests.sh"
LIB="$ROOT/hooks/tests/lib/run-preconditions.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: run-preconditions $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: run-preconditions $1 (${2:-})"; }
finish() { echo "[test-run-preconditions] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$RT" ] && [ -f "$LIB" ] || { bad "setup-runner-and-lib-present" "missing $RT or $LIB"; finish; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT
FX="$TMP/tree"
mkdir -p "$FX/hooks/tests/lib" "$FX/hooks/local/lib" "$FX/docs"
cp "$RT" "$FX/hooks/tests/run-tests.sh"
cp "$LIB" "$FX/hooks/tests/lib/"
printf '%s\n' 'ffhc_detect_timeout() { FFHC_TIMEOUT_BIN=""; }' 'ffhc_is_msys() { return 1; }' \
    'ffhc_timed_out() { return 1; }' > "$FX/hooks/local/lib/run-with-timeout.sh"
: > "$FX/docs/maintainer-testing.md"
( cd "$FX" && git init -q )
# TRIPWIRE: the anchor is the runner's first write, which every phase follows. A precondition
# evaluated after it is too late, and these rows then go red, which is intended.
sed -i '/^mkdir -p "\$(dirname "\$RESULTS_FILE")"$/i\echo "[fixture] past preconditions"; exit 0' \
    "$FX/hooks/tests/run-tests.sh"
if grep -qx 'echo "\[fixture\] past preconditions"; exit 0' "$FX/hooks/tests/run-tests.sh"; then
    ok "setup-fixture-exits-before-first-write"
else
    bad "setup-fixture-exits-before-first-write" "anchor not found; wiring rows below would run real phases"
fi

# rt VAR=val...: one runner invocation with every inherited selector and hosted marker removed
# first. An inherited GITHUB_ACTIONS/CI/FF_RELEASE (release CI runs this suite) would exempt a "local" row.
RC=0
rt() {
    ( cd "$FX" && env -u GITHUB_ACTIONS -u CI -u FF_ONLY -u FF_FULL -u FF_RELEASE -u FF_LIST \
        -u FF_EVIDENCE_GAP "$@" bash hooks/tests/run-tests.sh >"$TMP/out" 2>"$TMP/err" )
    RC=$?
}
past()    { grep -qx '\[fixture\] past preconditions' "$TMP/out"; }
refusal() { grep -q 'REFUSED: local FF_FULL/FF_RELEASE needs a nonempty FF_EVIDENCE_GAP' "$TMP/err"; }
why()     { printf 'rc=%s err=%s' "$RC" "$(tr '\n' ' ' < "$TMP/err" | cut -c1-200)"; }
expect_refused() {  # <row> VAR=val...
    local row="$1"; shift; rt "$@"
    if [ "$RC" -eq 2 ] && refusal && ! past; then ok "$row"
    else bad "$row" "expected rc 2 + refusal before the first write; $(why)"; fi
}
expect_proceeds() {  # <row> VAR=val...
    local row="$1"; shift; rt "$@"
    if [ "$RC" -eq 0 ] && ! refusal && past; then ok "$row"
    else bad "$row" "expected every precondition to pass; $(why)"; fi
}

# guard_row <row> <expect-rc> <FF_ATTESTING> <FF_RELEASE_RUN> VAR=val...: the lib's decision alone.
guard_row() {
    local row="$1" want="$2" att="$3" rel="$4" got; shift 4
    ( unset GITHUB_ACTIONS CI FF_EVIDENCE_GAP
      for kv in "$@"; do export "$kv"; done
      ROOT="$FX"; FF_ATTESTING="$att"; FF_RELEASE_RUN="$rel"
      . "$LIB" && ff_require_evidence_gap ) >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then ok "$row"; else bad "$row" "ff_require_evidence_gap rc=$got, expected $want"; fi
}

# --- Local full verification is an explicit exception (docs/maintainer-testing.md) ------------
expect_refused  "local-full-without-gap-is-refused"       FF_FULL=1
expect_refused  "local-full-with-empty-gap-is-refused"    FF_FULL=1 FF_EVIDENCE_GAP=
expect_refused  "local-release-without-gap-is-refused"    FF_RELEASE=1
expect_proceeds "local-full-with-gap-proceeds"            FF_FULL=1 "FF_EVIDENCE_GAP=probe full gap"
if grep -qx '\[run-tests\] FF_EVIDENCE_GAP: probe full gap' "$TMP/err"; then ok "accepted-gap-is-printed-verbatim"
else bad "accepted-gap-is-printed-verbatim" "the run did not print the named gap; $(why)"; fi
# The verbatim release step (`FF_RELEASE=1 bash hooks/tests/run-tests.sh`) under GitHub's defaults.
expect_proceeds "release-ci-invocation-needs-no-gap"      GITHUB_ACTIONS=true CI=true FF_RELEASE=1
expect_proceeds "focused-full-combination-needs-no-gap"   FF_ONLY=newline-preserve FF_FULL=1
rt FF_RELEASE=1 FF_LIST=1
if [ "$RC" -eq 0 ] && ! refusal && grep -q '^RUN  run-preconditions$' "$TMP/out"; then ok "listing-needs-no-gap"
else bad "listing-needs-no-gap" "$(why)"; fi

guard_row "blank-gap-is-refused"                2 1 0 "FF_EVIDENCE_GAP= 	 "
guard_row "local-release-with-gap-proceeds"     0 0 1 "FF_EVIDENCE_GAP=probe release gap"
guard_row "hosted-default-full-needs-no-gap"    0 1 0 GITHUB_ACTIONS=true CI=true
guard_row "github-actions-marker-alone-exempts" 0 0 1 GITHUB_ACTIONS=true
guard_row "ci-marker-alone-exempts"             0 0 1 CI=true
guard_row "non-true-hosted-values-do-not-exempt" 2 0 1 GITHUB_ACTIONS=1 CI=false
guard_row "fast-and-focused-modes-are-not-gated" 0 0 0
rm -f "$FX/docs/maintainer-testing.md"
guard_row "consumer-tree-is-exempt"             0 1 0
: > "$FX/docs/maintainer-testing.md"

mv "$FX/hooks/tests/lib/run-preconditions.sh" "$TMP/lib.aside"
rt
if [ "$RC" -eq 2 ] && ! past && grep -q 'run-preconditions.sh missing' "$TMP/err"; then ok "missing-lib-fails-closed"
else bad "missing-lib-fails-closed" "a runner without its preconditions ran anyway; $(why)"; fi
mv "$TMP/lib.aside" "$FX/hooks/tests/lib/run-preconditions.sh"

finish
