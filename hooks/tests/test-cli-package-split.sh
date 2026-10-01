#!/usr/bin/env bash
# Fusebase Flow — split @fusebase/* install advisory: module rows + health-wrapper rows.
# Outcome record: docs/changes/2026-09-30-ovation-escalation-f1-f4.md (F1).
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: cli-packages <name>" / "FAIL: cli-packages <name>"; exit code = failure count.
# TRIPWIRE: never spawn the health engine here — ~55 s per run on MSYS (docs/maintainer-testing.md, cli-version row).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$ROOT/hooks/local/lib"
MOD="$LIB/fusebase_package_split.py"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: cli-packages $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: cli-packages $1 ($(printf '%s' "${2:-}" | tr '\n' '|' | cut -c1-400))"; }
finish() { echo "[test-cli-package-split] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { bad setup-python3 "python3 not on PATH"; finish; }
[ -f "$MOD" ] || { bad setup-module "missing $MOD"; finish; }
TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/ff-cli-packages.XXXXXX")" || { bad setup-tmpdir "mktemp -d failed"; finish; }
trap 'rm -rf "$TMP_BASE"' EXIT

SDK="@fusebase/fusebase-gate-sdk"
pkg()  { mkdir -p "$1" && printf '%s\n' "$2" > "$1/package.json"; }
inst() { pkg "$1/node_modules/$SDK" "{\"name\":\"$SDK\",\"version\":\"$2\"}"; }

split_fixture() {
  echo '{}' > "$1/fusebase.json"
  pkg "$1" "{\"dependencies\":{\"$SDK\":\"^2.14.0\",\"react\":\"18.0.0\"}}"; inst "$1" 2.14.0
  pkg "$1/tests/e2e" "{\"devDependencies\":{\"$SDK\":\"2.14.0\"}}"
  pkg "$1/apps/benchmarking/backend" "{\"dependencies\":{\"$SDK\":\"2.11.9\"}}"; inst "$1/apps/benchmarking/backend" 2.11.9
}
fixture() { local d="$TMP_BASE/$1"; mkdir -p "$d" && printf '%s' "$d"; }

run_mod() {
  ( cd "$1" && MSYS_NO_PATHCONV=1 python3 -I -S - . < "$MOD" ) > "$1.out" 2> "$1.err"
}
SPLIT_LINE="$SDK resolves to 2 versions — 2.14.0: ., tests/e2e · 2.11.9: apps/benchmarking/backend. Separate copies break instanceof checks (e.g. ApiError) across them. Owner: FuseBase CLI version management. Fix: align these package.json entries, then npm install in each root."

D="$(fixture split)"; split_fixture "$D"
if run_mod "$D" && [ "$(cat "$D.out")" = "$SPLIT_LINE" ] && ! grep -q 'fusebase update' "$D.out"; then
  ok "split-names-both-versions-and-their-roots"
else
  bad "split-names-both-versions-and-their-roots" "rc=$? out=$(cat "$D.out") err=$(cat "$D.err")"
fi

D="$(fixture unified)"; split_fixture "$D"; rm -rf "$D/apps/benchmarking/backend/node_modules"
pkg "$D/apps/uninstalled" "{\"dependencies\":{\"@fusebase/other-sdk\":\"1.0.0\"}}"
if run_mod "$D" && [ ! -s "$D.out" ]; then ok "unified-or-unresolvable-prints-nothing"
else bad "unified-or-unresolvable-prints-nothing" "out=$(cat "$D.out") err=$(cat "$D.err")"; fi

D="$(fixture no-fusebase-json)"; split_fixture "$D"; rm -f "$D/fusebase.json"
if run_mod "$D" && [ ! -s "$D.out" ]; then ok "no-fusebase-json-prints-nothing"
else bad "no-fusebase-json-prints-nothing" "out=$(cat "$D.out")"; fi

D="$(fixture hoisted)"; split_fixture "$D"; rm -rf "$D/apps/benchmarking/backend/node_modules"; inst "$D/tests/e2e" 2.11.9
if run_mod "$D" && grep -qF -- "— 2.14.0: ., apps/benchmarking/backend · 2.11.9: tests/e2e." "$D.out"; then
  ok "hoisted-backend-resolves-from-root"
else
  bad "hoisted-backend-resolves-from-root" "out=$(cat "$D.out") err=$(cat "$D.err")"
fi

D="$(fixture ignored-dirs)"; split_fixture "$D"; rm -rf "$D/apps/benchmarking/backend/node_modules"
for sub in node_modules/some-dep .claude/worktrees/w1 .fusebase-flow-source; do
  pkg "$D/$sub" "{\"dependencies\":{\"$SDK\":\"1.0.0\"}}"; inst "$D/$sub" 1.0.0
done
if run_mod "$D" && [ ! -s "$D.out" ]; then ok "node-modules-and-dot-dirs-ignored"
else bad "node-modules-and-dot-dirs-ignored" "out=$(cat "$D.out")"; fi

VERDICT_ARRAYS="LOCAL_OK LOCAL_DRIFT LOCAL_BROKEN LOCAL_UNVERIFIED LOCAL_DEFERRED CLI_LAYER_DRIFT CLI_VERSION_UNSUPPORTED SHARED_MERGE_DRIFT"
wrap() {
  ( cd "$2" || exit 97
    . "$LIB/run-with-timeout.sh"; ffhc_detect_timeout
    . "$1/cli-version-check.sh"
    local a; for a in $VERDICT_ARRAYS CLI_VERSION_ADVISORY; do eval "$a=()"; done
    ffhc_cli_package_split_check
    local n=0; for a in $VERDICT_ARRAYS; do eval "n=\$((n + \${#$a[@]}))"; done
    printf '%s\t%s\t%s' "$n" "${#CLI_VERSION_ADVISORY[@]}" "${CLI_VERSION_ADVISORY[0]:-}" )
}

D="$(fixture wrap-split)"; split_fixture "$D"
got="$(wrap "$LIB" "$D")"
if [ "$got" = "0	1	$SPLIT_LINE" ]; then ok "wrapper-appends-one-advisory-and-no-verdict-entry"
else bad "wrapper-appends-one-advisory-and-no-verdict-entry" "$got"; fi

D="$(fixture wrap-gated)"; split_fixture "$D"; rm -f "$D/fusebase.json"
got="$(wrap "$LIB" "$D")"
if [ "$got" = "0	0	" ]; then ok "wrapper-gated-on-fusebase-json"
else bad "wrapper-gated-on-fusebase-json" "$got"; fi

for case in failing missing; do
  L="$TMP_BASE/lib-$case"; mkdir -p "$L"; cp "$LIB/cli-version-check.sh" "$L/"
  [ "$case" = failing ] && printf 'raise SystemExit(3)\n' > "$L/fusebase_package_split.py"
  D="$(fixture "wrap-$case")"; split_fixture "$D"
  got="$(wrap "$L" "$D")"
  case "$got" in
    "0	1	@fusebase/* install check: did not complete — "*) ok "wrapper-reports-$case-scan-as-incomplete" ;;
    *) bad "wrapper-reports-$case-scan-as-incomplete" "$got" ;;
  esac
done

finish
