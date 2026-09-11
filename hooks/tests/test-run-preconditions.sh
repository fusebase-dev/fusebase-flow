#!/usr/bin/env bash
# Fusebase Flow — run-tests.sh invocation preconditions (hooks/tests/lib/run-preconditions.sh).
# Decision rows source the lib and call the check directly (function boundary, milliseconds).
# Wiring rows drive a COPY of the runner in a synthetic, stamped maintainer tree that exits at the
# last line before any output or phase, so "proceeds" means "passed every precondition". The
# judged working tree is never written to.
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
for f in verify-hook-manifest stamp-hook-manifest verify-managed-content-manifest stamp-managed-content-manifest; do
    cp "$ROOT/hooks/local/$f.sh" "$FX/hooks/local/"
done
cp "$ROOT/hooks/local/lib/hook_manifest.py" "$ROOT/hooks/local/lib/managed_content_manifest.py" \
   "$ROOT/hooks/local/lib/eol_guard.py" "$FX/hooks/local/lib/"
cp "$ROOT/VERSION" "$FX/"
# Stub engine: no real bound (liveness has its own phases); it logs each command it runs.
cat > "$FX/hooks/local/lib/run-with-timeout.sh" <<'STUB'
ffhc_detect_timeout() { FFHC_TIMEOUT_BIN=""; }
ffhc_is_msys() { return 1; }
ffhc_timed_out() { return 1; }
ffhc_run_bounded() {
  local capture; shift
  printf '%s\n' "$*" >> "$ROOT/.git/bounded.log"
  capture="$(mktemp)" || { FFHC_LAST_OUT="capture setup failed"; FFHC_LAST_RC=125; return 0; }
  "$@" > "$capture" 2>&1; FFHC_LAST_RC=$?; FFHC_LAST_SKIPPED=0
  FFHC_LAST_OUT="$(<"$capture")"; rm -f "$capture"
}
STUB
: > "$FX/docs/maintainer-testing.md"
( cd "$FX" && git init -q )
BLOG="$FX/.git/bounded.log"
# TRIPWIRE: the anchor is the runner's first write, which every phase follows. A precondition
# evaluated after it is too late, and these rows then go red, which is intended.
sed -i '/^mkdir -p "\$(dirname "\$RESULTS_FILE")"$/i\echo "[fixture] past preconditions"; exit 0' \
    "$FX/hooks/tests/run-tests.sh"
if grep -qx 'echo "\[fixture\] past preconditions"; exit 0' "$FX/hooks/tests/run-tests.sh"; then
    ok "setup-fixture-exits-before-first-write"
else
    bad "setup-fixture-exits-before-first-write" "anchor not found; wiring rows below would run real phases"
fi
( cd "$FX" && bash hooks/local/stamp-hook-manifest.sh && bash hooks/local/stamp-managed-content-manifest.sh ) \
    >"$TMP/stamp.out" 2>&1 \
    && ok "setup-fixture-stamped" \
    || bad "setup-fixture-stamped" "$(tr '\n' ' ' < "$TMP/stamp.out" | cut -c1-200)"

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
stale()   { grep -q '^\[run-tests\] REFUSED: verify-[a-z-]*-manifest\.sh rc=' "$TMP/err"; }
why()     { printf 'rc=%s err=%s' "$RC" "$(tr '\n' ' ' < "$TMP/err" | cut -c1-240)"; }
expect_refused() {  # <row> VAR=val...
    local row="$1"; shift; rt "$@"
    if [ "$RC" -eq 2 ] && refusal && ! past; then ok "$row"
    else bad "$row" "expected rc 2 + refusal before the first write; $(why)"; fi
}
expect_proceeds() {  # <row> VAR=val...
    local row="$1"; shift; rt "$@"
    if [ "$RC" -eq 0 ] && ! grep -q 'REFUSED' "$TMP/err" && past; then ok "$row"
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
# Also the stamped-tree arm of the manifest pre-check: FF_FULL selects release phases, so both
# verifiers must run and MATCH for this row to proceed.
: > "$BLOG"
expect_proceeds "local-full-with-gap-proceeds-on-a-stamped-tree" FF_FULL=1 "FF_EVIDENCE_GAP=probe full gap"
if grep -qx '\[run-tests\] FF_EVIDENCE_GAP: probe full gap' "$TMP/err"; then ok "accepted-gap-is-printed-verbatim"
else bad "accepted-gap-is-printed-verbatim" "the run did not print the named gap; $(why)"; fi
if grep -q 'verify-hook-manifest\.sh' "$BLOG" && grep -q 'verify-managed-content-manifest\.sh' "$BLOG"; then
    ok "precheck-invokes-both-existing-verifiers"
else
    bad "precheck-invokes-both-existing-verifiers" "bounded log: $(tr '\n' ' ' < "$BLOG" | cut -c1-200)"
fi
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

# --- A stale manifest fails before any phase, and is never restamped --------------------------
# One edit to a hook-layer file, one NEW collected file: the hook-layer verifier reports extra=0 for
# a new file, so only the managed-content arm names it (docs/backlog/local-gate-misses-manifest-freshness/).
printf '# unstamped edit\n' >> "$FX/hooks/local/lib/run-with-timeout.sh"
printf '#!/usr/bin/env bash\n' > "$FX/hooks/tests/test-new-probe.sh"
cp "$FX/audit/hook-layer-manifest.json" "$TMP/hl.before"
cp "$FX/audit/managed-content-manifest.json" "$TMP/mc.before"
rt FF_ONLY=cli-flow-recovery
if [ "$RC" -eq 2 ] && stale && ! past \
    && grep -q 'modified: hooks/local/lib/run-with-timeout\.sh$' "$TMP/err" \
    && grep -q 'extra: hooks/tests/test-new-probe\.sh$' "$TMP/err" \
    && grep -q 'hook-layer first' "$TMP/err"; then
    ok "unstamped-edit-refuses-before-any-phase-naming-paths"
else
    bad "unstamped-edit-refuses-before-any-phase-naming-paths" "$(why)"
fi
if cmp -s "$TMP/hl.before" "$FX/audit/hook-layer-manifest.json" \
    && cmp -s "$TMP/mc.before" "$FX/audit/managed-content-manifest.json"; then ok "precheck-never-restamps"
else bad "precheck-never-restamps" "a refused run rewrote a committed manifest"; fi
expect_proceeds "fast-release-selection-skips-the-precheck"  FF_ONLY=command-policy
expect_proceeds "non-release-selection-skips-the-precheck"   FF_ONLY=boot-size
expect_proceeds "hosted-ci-skips-the-precheck"               GITHUB_ACTIONS=true CI=true FF_RELEASE=1
rm -f "$FX/docs/maintainer-testing.md"
expect_proceeds "consumer-tree-skips-the-precheck"           FF_FULL=1

finish
