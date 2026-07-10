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

# S9 — DELTA-AWARE adoption grace: a PRE-EXISTING over-ceiling file NOT in the baseline
# may be touched/shrunk in a change gate (--staged/--worktree) without blocking (the
# refactor path); only NEW-over-ceiling files and GROWTH block. Commit it over-ceiling
# at HEAD; do NOT re-baseline it.
gen_lines 900 "$TMP/preexisting.py"
"${GIT[@]}" add preexisting.py >/dev/null 2>&1
"${GIT[@]}" commit -q -m "pre-existing monolith (not baselined)" >/dev/null 2>&1

# S9a — touch it non-growing (900 -> 880) -> ALLOW, exit 0 (old code hard-blocked this).
gen_lines 880 "$TMP/preexisting.py"
"${GIT[@]}" add preexisting.py >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "preexisting-nonbaselined-shrink-allowed" 0 $?
"${GIT[@]}" reset -q preexisting.py >/dev/null 2>&1; "${GIT[@]}" checkout -q -- preexisting.py >/dev/null 2>&1

# S9b — grow it (900 -> 950) -> BLOCK, exit 1 (growing an un-adopted monolith is a violation).
gen_lines 950 "$TMP/preexisting.py"
"${GIT[@]}" add preexisting.py >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "preexisting-nonbaselined-growth-blocked" 1 $?
"${GIT[@]}" reset -q preexisting.py >/dev/null 2>&1; "${GIT[@]}" checkout -q -- preexisting.py >/dev/null 2>&1

# S9c — worktree gate is delta-aware too: a non-growing worktree edit of the pre-existing
# monolith passes (exit 0).
gen_lines 890 "$TMP/preexisting.py"
check --worktree >/dev/null 2>&1; verdict "preexisting-nonbaselined-worktree-touch-allowed" 0 $?
"${GIT[@]}" checkout -q -- preexisting.py >/dev/null 2>&1

# S9d — --all (audit) is ABSOLUTE, not delta-aware: it still REPORTS the un-baselined
# over-ceiling file (exit 1), so the audit view tells you what to adopt.
check --all >/dev/null 2>&1; verdict "preexisting-nonbaselined-audit-still-reports" 1 $?
"${GIT[@]}" rm -q preexisting.py >/dev/null 2>&1; "${GIT[@]}" commit -q -m "drop preexisting" >/dev/null 2>&1

# S10 — RENAME must not bypass the gate: a pre-existing over-ceiling file RENAMED and
# GROWN must still BLOCK. Without --no-renames the move is classified R and dropped by
# --diff-filter=ACM, so the grown monolith escapes; --no-renames surfaces the destination
# as an Added path -> delta branch sees prev=None (new path) -> BLOCK.
gen_lines 900 "$TMP/mono.py"
"${GIT[@]}" add mono.py >/dev/null 2>&1
"${GIT[@]}" commit -q -m "monolith to rename" >/dev/null 2>&1
"${GIT[@]}" mv mono.py mono2.py >/dev/null 2>&1
gen_lines 950 "$TMP/mono2.py"   # renamed AND grown past its old size
"${GIT[@]}" add mono2.py >/dev/null 2>&1
check --staged >/dev/null 2>&1; verdict "rename-grown-monolith-still-blocks" 1 $?
"${GIT[@]}" reset -q >/dev/null 2>&1

# S11 — DoS guard: a redirected baseline_file pointing at an existing NON-baseline file is
# REFUSED (exit 2) and the victim file is never clobbered with baseline text.
printf 'important: config\n' > "$TMP/policies/victim.yml"
"${GIT[@]}" add policies/victim.yml >/dev/null 2>&1
"${GIT[@]}" commit -q -m "victim config" >/dev/null 2>&1
printf 'baseline_file: policies/victim.yml\n' >> "$TMP/policies/module-size.yml"   # worktree redirect
check --write-baseline >/dev/null 2>&1; verdict "write-baseline-refuses-non-baseline-clobber" 2 $?
if grep -q '^important: config$' "$TMP/policies/victim.yml"; then
    pass=$((pass + 1)); echo "PASS: module-size victim-file-not-clobbered"
else
    fail=$((fail + 1)); echo "FAIL: module-size victim-file-not-clobbered (baseline text overwrote it)"
fi
# restore policy (drop the redirect line)
grep -v '^baseline_file: policies/victim.yml$' "$TMP/policies/module-size.yml" > "$TMP/policies/module-size.yml.tmp" && mv "$TMP/policies/module-size.yml.tmp" "$TMP/policies/module-size.yml"

echo "[test-module-size] $pass/$((pass + fail)) PASS"
exit $fail
