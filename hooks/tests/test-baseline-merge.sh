#!/usr/bin/env bash
# Fusebase Flow — AC3 (W2 regression): module-size-baseline merge-preserve (U3).
# Proves the LOCKED merge rule: pre-existing PROJECT rows survive an upgrade and
# check-module-size.sh --all still passes; upstream rows take the upstream count;
# a Flow row dropped upstream is removed; ownership = upstream-baseline membership
# (NOT path prefixes); malformed local rows are warned, never silently dropped.
#
# Output contract (parsed by run-tests.sh): "PASS: baseline-merge <name>" /
# "FAIL: baseline-merge <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MERGE_LIB="$ROOT/hooks/local/lib/merge-module-size-baseline.sh"
python_bin="${PYTHON:-python3}"; command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: baseline-merge $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: baseline-merge $1 ($2)"; }

if [ ! -f "$MERGE_LIB" ]; then
  bad "merge-lib-present" "missing $MERGE_LIB"; echo "[test-baseline-merge] $pass/$((pass + fail)) PASS"; exit $fail
fi
. "$MERGE_LIB"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

###############################################################################
# Part 1 — the merge rule in isolation.
###############################################################################
# Note the deliberate prefix collision: upstream + a project row BOTH live under
# hooks/tests/ — proving ownership is MEMBERSHIP, not path prefix.
cat > "$TMP/local.txt" <<'EOF'
# header
900 src/app/legacy-monolith.ts
850 hooks/tests/recovery-sim.sh
820 hooks/tests/project-own-helper.sh
999 hooks/local/flow-file-dropped-upstream.sh
garbage non-numeric row
EOF
cat > "$TMP/upstream.txt" <<'EOF'
# header
954 hooks/tests/recovery-sim.sh
EOF

merged="$TMP/merged.txt"
warns="$(merge_module_size_baseline "$TMP/local.txt" "$TMP/upstream.txt" "$merged" 2>&1 >/dev/null)"

# Upstream count wins for the upstream-owned row.
grep -qxF "954 hooks/tests/recovery-sim.sh" "$merged" \
  && ok "upstream-count-wins" || bad "upstream-count-wins" "expected '954 hooks/tests/recovery-sim.sh'"
# Local 850 for that same path is NOT preserved (superseded by upstream).
grep -qxF "850 hooks/tests/recovery-sim.sh" "$merged" \
  && bad "local-superseded-by-upstream" "stale local 850 row survived" || ok "local-superseded-by-upstream"
# Project rows (NOT in upstream baseline) preserved verbatim — incl. one that
# shares the hooks/tests/ prefix with the upstream row (membership, not prefix).
grep -qxF "820 hooks/tests/project-own-helper.sh" "$merged" \
  && ok "project-row-preserved-same-prefix" || bad "project-row-preserved-same-prefix" "hooks/tests/ project row dropped"
grep -qxF "900 src/app/legacy-monolith.ts" "$merged" \
  && ok "project-row-preserved-other-tree" || bad "project-row-preserved-other-tree" "src/ project row dropped"
# A local row under a Flow-owned tree but ABSENT from the upstream baseline is, by
# the membership rule, preserved as a project row (the only signal is membership).
grep -qxF "999 hooks/local/flow-file-dropped-upstream.sh" "$merged" \
  && ok "absent-upstream-row-kept-by-membership" || bad "absent-upstream-row-kept-by-membership" "row dropped"
# Malformed local row WARNED, never silently dropped.
echo "$warns" | grep -q "malformed LOCAL row" \
  && ok "malformed-row-warned" || bad "malformed-row-warned" "no warning emitted for the garbage row"
# Deterministic sort by path + standard header.
head -1 "$merged" | grep -q "FR-25 module-size baseline" \
  && ok "standard-header" || bad "standard-header" "missing standard header"
body="$(grep -vE '^#' "$merged")"
[ "$body" = "$(echo "$body" | sort -k2)" ] \
  && ok "deterministic-sort" || bad "deterministic-sort" "body not path-sorted"

###############################################################################
# Part 2 — INTEGRATION: simulate the upgrade clobber+merge, then check-module-size.
###############################################################################
GIT=(git -C "$TMP/repo" -c user.name=flow-test -c user.email=flow-test@local)
mkdir -p "$TMP/repo/policies" "$TMP/repo/hooks/shared" "$TMP/repo/hooks/local"
git init -q "$TMP/repo"
cp "$ROOT/policies/module-size.yml" "$TMP/repo/policies/"
cp "$ROOT/hooks/shared/module_size.py" "$TMP/repo/hooks/shared/"
cp "$ROOT/hooks/local/check-module-size.sh" "$TMP/repo/hooks/local/"

# The consumer has its OWN over-ceiling source file, frozen in the baseline.
# Tripwire: build big.py via SHELL REDIRECTION, not a Python open() — a Python
# path that FileNotFiles on Git-Bash used to print to stderr yet leave the test
# green (the merge/check then ran against a NON-EXISTENT file, so check-module-size
# --all had nothing to gate and passed for the WRONG reason). The setup below FAILS
# the test loudly if the fixture is missing or the wrong size, so AC3 genuinely
# exercises the W2 preserve-project-rows case.
BIG_LINES=900
mkdir -p "$TMP/repo/src" || { bad "setup-mkdir-src" "could not create src/"; echo "[test-baseline-merge] $pass/$((pass + fail)) PASS"; exit $fail; }
for _ in $(seq 1 "$BIG_LINES"); do printf 'x = 1\n'; done > "$TMP/repo/src/big.py"
# Assert the fixture EXISTS and is EXACTLY over-ceiling BEFORE any merge/check — a
# silent setup failure here is what produced the false-green.
if [ ! -f "$TMP/repo/src/big.py" ]; then
  bad "setup-fixture-exists" "src/big.py was not created (would false-green AC3)"
  echo "[test-baseline-merge] $pass/$((pass + fail)) PASS"; exit $fail
fi
ok "setup-fixture-exists"
actual_lines="$(wc -l < "$TMP/repo/src/big.py" | tr -d ' ')"
if [ "$actual_lines" != "$BIG_LINES" ]; then
  bad "setup-fixture-line-count" "src/big.py is $actual_lines lines, expected $BIG_LINES (over-ceiling fixture wrong)"
  echo "[test-baseline-merge] $pass/$((pass + fail)) PASS"; exit $fail
fi
ok "setup-fixture-line-count"
# Pre-existing baseline: the consumer's project row (frozen) — this is the W2 state.
cat > "$TMP/repo/policies/module-size-baseline.txt" <<EOF
# FR-25 module-size baseline — over-ceiling files frozen at current size.
$BIG_LINES src/big.py
EOF
"${GIT[@]}" add -A >/dev/null 2>&1; "${GIT[@]}" commit -q -m init >/dev/null 2>&1
# Assert the over-ceiling fixture is git-TRACKED (--all uses `git ls-files`; an
# untracked file is invisible to the gate, another way the guard could no-op).
if ! "${GIT[@]}" ls-files --error-unmatch src/big.py >/dev/null 2>&1; then
  bad "setup-fixture-tracked" "src/big.py not tracked after commit (--all would skip it)"
  echo "[test-baseline-merge] $pass/$((pass + fail)) PASS"; exit $fail
fi
ok "setup-fixture-tracked"

# Baseline passes BEFORE the upgrade.
( cd "$TMP/repo" && bash hooks/local/check-module-size.sh --all >/dev/null 2>&1 )
[ $? -eq 0 ] && ok "pre-upgrade-check-passes" || bad "pre-upgrade-check-passes" "check failed before upgrade"

# Simulate upgrade step 1: snapshot local, then CLOBBER the baseline with upstream's
# (upstream baseline knows nothing about the consumer's src/big.py).
snap="$TMP/repo/.snap"; cp "$TMP/repo/policies/module-size-baseline.txt" "$snap"
printf '# header\n' > "$TMP/repo/policies/module-size-baseline.txt"   # upstream has no over-ceiling rows
# Without the merge, the project row is gone:
grep -qxF "900 src/big.py" "$TMP/repo/policies/module-size-baseline.txt" \
  && bad "clobber-precondition" "clobber did not remove the project row" || ok "clobber-removed-project-row"
# Apply the U3 merge (snapshot=local, current=just-installed-upstream).
merge_module_size_baseline "$snap" "$TMP/repo/policies/module-size-baseline.txt" "$TMP/repo/policies/module-size-baseline.txt.new" 2>/dev/null
mv "$TMP/repo/policies/module-size-baseline.txt.new" "$TMP/repo/policies/module-size-baseline.txt"

# AC3: the project row is back AND check-module-size --all passes post-upgrade.
grep -qxF "900 src/big.py" "$TMP/repo/policies/module-size-baseline.txt" \
  && ok "post-upgrade-project-row-survives" || bad "post-upgrade-project-row-survives" "project row not restored"
"${GIT[@]}" add -A >/dev/null 2>&1
( cd "$TMP/repo" && bash hooks/local/check-module-size.sh --all >/dev/null 2>&1 )
[ $? -eq 0 ] && ok "post-upgrade-check-passes" || bad "post-upgrade-check-passes" "check-module-size --all failed AFTER upgrade (the W2 bug)"

echo "[test-baseline-merge] $pass/$((pass + fail)) PASS"
exit $fail
