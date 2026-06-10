#!/usr/bin/env bash
# Fusebase Flow — FR-25 module-size ratchet scenarios.
# Self-contained: builds a temp git repo per scenario set, runs the real
# check script against it. Invoked by run-tests.sh (phase 2); standalone OK.
# Output contract (parsed by run-tests.sh): "PASS: module-size <name>" /
# "FAIL: module-size <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
python_bin="${PYTHON:-python3}"
command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"
if ! command -v "$python_bin" >/dev/null 2>&1; then
    echo "[test-module-size] python not found; skipping" >&2
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

GIT=(git -C "$TMP" -c user.name=flow-test -c user.email=flow-test@local)

# Temp repo with the real policy + engine.
git init -q "$TMP"
mkdir -p "$TMP/policies" "$TMP/hooks/shared" "$TMP/hooks/local"
cp "$ROOT/policies/module-size.yml" "$TMP/policies/"
cp "$ROOT/hooks/shared/module_size.py" "$TMP/hooks/shared/"
cp "$ROOT/hooks/local/check-module-size.sh" "$TMP/hooks/local/"
"${GIT[@]}" add -A >/dev/null 2>&1
"${GIT[@]}" commit -q -m "init" >/dev/null 2>&1

gen_lines() { # gen_lines <count> <file>
    "$python_bin" -c "import sys; open(sys.argv[2],'w').write('x = 1\n' * int(sys.argv[1]))" "$1" "$2"
}

check() { (cd "$TMP" && bash hooks/local/check-module-size.sh "$@"); }

pass=0
fail=0
verdict() { # verdict <name> <expected_exit> <actual_exit>
    if [ "$2" -eq "$3" ]; then
        pass=$((pass + 1)); echo "PASS: module-size $1"
    else
        fail=$((fail + 1)); echo "FAIL: module-size $1 (expected exit $2, got $3)"
    fi
}

# S1 — no baseline: over-ceiling new file staged -> warn-only, exit 0.
gen_lines 900 "$TMP/big_new.py"
"${GIT[@]}" add big_new.py >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "warn-without-baseline" 0 $?
"${GIT[@]}" reset -q big_new.py >/dev/null 2>&1; rm -f "$TMP/big_new.py"

# Activate the ratchet: generate + commit an (empty) baseline.
check --write-baseline >/dev/null 2>&1
"${GIT[@]}" add policies/module-size-baseline.txt >/dev/null 2>&1
"${GIT[@]}" commit -q -m "baseline" >/dev/null 2>&1

# S2 — baseline present: new under-ceiling file -> exit 0.
gen_lines 100 "$TMP/small.py"
"${GIT[@]}" add small.py >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "new-under-ceiling-passes" 0 $?
"${GIT[@]}" reset -q small.py >/dev/null 2>&1; rm -f "$TMP/small.py"

# S3 — baseline present: new over-ceiling file -> BLOCK, exit 1.
gen_lines 900 "$TMP/big_new.py"
"${GIT[@]}" add big_new.py >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "new-over-ceiling-blocked" 1 $?
"${GIT[@]}" reset -q big_new.py >/dev/null 2>&1; rm -f "$TMP/big_new.py"

# Legacy monolith: commit at 900 lines, re-baseline (freezes it at 900).
gen_lines 900 "$TMP/legacy.py"
"${GIT[@]}" add legacy.py >/dev/null 2>&1
"${GIT[@]}" commit -q -m "legacy monolith" >/dev/null 2>&1
check --write-baseline >/dev/null 2>&1
"${GIT[@]}" add policies/module-size-baseline.txt >/dev/null 2>&1
"${GIT[@]}" commit -q -m "re-baseline" >/dev/null 2>&1

# S4 — baselined over-ceiling file shrinks (900 -> 850) -> exit 0 (ratchet allows).
gen_lines 850 "$TMP/legacy.py"
"${GIT[@]}" add legacy.py >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "ratchet-allows-shrink" 0 $?
"${GIT[@]}" reset -q legacy.py >/dev/null 2>&1; "${GIT[@]}" checkout -q -- legacy.py >/dev/null 2>&1

# S5 — baselined over-ceiling file grows (900 -> 950) -> BLOCK, exit 1.
gen_lines 950 "$TMP/legacy.py"
"${GIT[@]}" add legacy.py >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "ratchet-blocks-growth" 1 $?
"${GIT[@]}" reset -q legacy.py >/dev/null 2>&1; "${GIT[@]}" checkout -q -- legacy.py >/dev/null 2>&1

# S6 — exempt glob: over-ceiling file under vendor/ -> exit 0.
mkdir -p "$TMP/vendor"
gen_lines 1000 "$TMP/vendor/big.js"
"${GIT[@]}" add vendor/big.js >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "exempt-glob-passes" 0 $?
"${GIT[@]}" reset -q vendor/big.js >/dev/null 2>&1; rm -rf "$TMP/vendor"

# S7 — gitignored local override may NOT flip enforcement to warn: violation still blocks.
printf 'enforcement: warn\n' > "$TMP/policies/module-size.local.yml"
gen_lines 900 "$TMP/big_new.py"
"${GIT[@]}" add big_new.py >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "local-override-cannot-disarm" 1 $?
"${GIT[@]}" reset -q big_new.py >/dev/null 2>&1; rm -f "$TMP/big_new.py" "$TMP/policies/module-size.local.yml"

# S8 — single-file re-key: tightens ONE row (900 baseline -> 850), no global amnesty;
# growth past the re-keyed value then blocks.
gen_lines 850 "$TMP/legacy.py"
"${GIT[@]}" add legacy.py >/dev/null 2>&1
"${GIT[@]}" commit -q -m "shrink legacy" >/dev/null 2>&1
check --write-baseline legacy.py >/dev/null 2>&1
gen_lines 880 "$TMP/legacy.py"   # 880 > re-keyed 850 (old baseline 900 would have passed)
"${GIT[@]}" add legacy.py >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "single-file-rekey-ratchets" 1 $?
"${GIT[@]}" reset -q legacy.py >/dev/null 2>&1; "${GIT[@]}" checkout -q -- legacy.py >/dev/null 2>&1

echo "[test-module-size] $pass/$((pass + fail)) PASS"
exit $fail
