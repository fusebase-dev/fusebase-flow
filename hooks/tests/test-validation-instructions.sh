#!/usr/bin/env bash
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HELPER="$ROOT/hooks/local/lib/precommit-validator-reuse.sh"
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0

run_case() {
    local name="$1" lint="$2" types="$3" expected_rc="$4" expected_log="$5" rc=0 actual
    local case_dir="$WORK/$name"
    mkdir -p "$case_dir"
    (
        cd "$case_dir" || exit 2
        export CHECK_LOG="$case_dir/calls"
        export FUSEBASE_FLOW_LINT="$lint" FUSEBASE_FLOW_TYPECHECK="$types"
        . "$HELPER"
        run_precommit_validators "$PWD" "$PATH"
    ) >"$case_dir/output" 2>&1 || rc=$?
    actual="$(cat "$case_dir/calls" 2>/dev/null || true)"
    if [ "$rc" -eq "$expected_rc" ] && [ "$actual" = "$expected_log" ]; then
        echo "PASS: validation-instructions $name"
        pass=$((pass + 1))
    else
        echo "FAIL: validation-instructions $name (rc=$rc expected=$expected_rc calls=$actual)"
        cat "$case_dir/output" >&2
        fail=$((fail + 1))
    fi
}

lint='printf "lint\n" >> "$CHECK_LOG"'
types='printf "typecheck\n" >> "$CHECK_LOG"'
run_case both-validators-run "$lint" "$types" 0 $'lint\ntypecheck'
run_case lint-failure-blocks "$lint; false" "$types" 1 lint
run_case typecheck-failure-blocks "$lint" "$types; false" 1 $'lint\ntypecheck'
run_case typecheck-only '' "$types" 0 typecheck
run_case no-configured-validators '' '' 0 ''
echo "[test-validation-instructions] $pass/$((pass + fail)) PASS"
exit "$fail"
