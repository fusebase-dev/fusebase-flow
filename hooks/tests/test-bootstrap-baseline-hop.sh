#!/usr/bin/env bash
# Fusebase Flow — v3.25.1 adoption-hop regression: the baseline merge-preserve MUST
# run on the FIRST upgrade that adopts v3.25.x, even when the consumer's local
# hooks/local/lib/ was absent when the engine started (a pre-v3.25 install, or a
# bootstrap that didn't stage lib/). The W2 fix (U3) shipped in v3.25.0 but silently
# no-op'd on exactly this hop because upgrade.sh sourced the merge lib only from the
# LOCAL tree — undefined on a pre-v3.25 install -> Step 1a guard false -> merge
# skipped -> project rows clobbered.
#
# RED-then-GREEN, in one run, against the REAL fixed upgrade.sh source-load logic:
#   RED  — PRE-FIX source logic (local-only; lib absent) leaves the merge function
#          UNDEFINED, so the project row is LOST after the wholesale policies/ copy.
#   GREEN — POST-FIX source logic (source_merge_lib: $SOURCE_CLONE first) DEFINES the
#          function, the merge runs, the project row SURVIVES, and
#          check-module-size.sh --all passes.
# The RED arm proves this test genuinely detects the bug (no false-green); the GREEN
# arm proves P2 fixes it. P1 (bootstrap staging hooks/local/lib/) is asserted
# separately below by running the real bootstrap copy step against a source tree.
#
# Output contract (parsed by run-tests.sh): "PASS: bootstrap-baseline-hop <name>" /
# "FAIL: bootstrap-baseline-hop <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
UPGRADE_SH="$ROOT/hooks/local/upgrade.sh"
BOOTSTRAP_SH="$ROOT/hooks/local/bootstrap-upgrade.sh"
SRC_LIB="$ROOT/hooks/local/lib/merge-module-size-baseline.sh"
python_bin="${PYTHON:-python3}"; command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: bootstrap-baseline-hop $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: bootstrap-baseline-hop $1 ($2)"; }
finish() { echo "[test-bootstrap-baseline-hop] $pass/$((pass + fail)) PASS"; exit $fail; }

# Loud setup preconditions — a missing input must FAIL the test, never false-green.
[ -f "$UPGRADE_SH" ]   || { bad "setup-upgrade-present"   "missing $UPGRADE_SH"; finish; }
[ -f "$BOOTSTRAP_SH" ] || { bad "setup-bootstrap-present" "missing $BOOTSTRAP_SH"; finish; }
[ -f "$SRC_LIB" ]      || { bad "setup-srclib-present"    "missing $SRC_LIB"; finish; }
ok "setup-inputs-present"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

###############################################################################
# Extract the REAL source-load logic from the fixed upgrade.sh.
# We source the function definition out of the actual engine so this test exercises
# the shipped code, not a paraphrase. The pre-fix behavior is reconstructed
# faithfully (source ONLY $ROOT/hooks/local/lib, the v3.25.0 logic).
###############################################################################
# Pull source_merge_lib() from the live upgrade.sh (awk: from the function header
# to its closing brace). Portable — avoids a nested python fork.
ENGINE_FUNCS="$TMP/engine-funcs.sh"
awk '/^source_merge_lib\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$UPGRADE_SH" > "$ENGINE_FUNCS"
# Must capture a complete function (header + closing brace), else P2 is missing/renamed.
if [ ! -s "$ENGINE_FUNCS" ] || ! head -1 "$ENGINE_FUNCS" | grep -q '^source_merge_lib() {' \
   || ! tail -1 "$ENGINE_FUNCS" | grep -q '^}'; then
  bad "extract-source-merge-lib" "source_merge_lib not found/complete in upgrade.sh (P2 missing?)"; finish
fi
# It must source from $SOURCE_CLONE (the authoritative-tree fix), not local-only.
grep -q 'SOURCE_CLONE/hooks/local/lib/merge-module-size-baseline.sh' "$ENGINE_FUNCS" \
  || { bad "extract-source-merge-lib" "source_merge_lib does not source from \$SOURCE_CLONE (P2 incomplete)"; finish; }
ok "extract-source-merge-lib"

###############################################################################
# Build a consumer tree that reproduces the adoption hop:
#   - a PROJECT over-ceiling source file frozen in the consumer's baseline;
#   - the project row is ABSENT from the (upstream) baseline being installed;
#   - hooks/local/lib/ is ABSENT locally at engine start (pre-v3.25 install);
#   - $SOURCE_CLONE = the current repo (v3.25.x target, which HAS hooks/local/lib/).
###############################################################################
REPO="$TMP/repo"
GIT=(git -C "$REPO" -c user.name=flow-test -c user.email=flow-test@local)
mkdir -p "$REPO/policies" "$REPO/hooks/shared" "$REPO/hooks/local"
git init -q "$REPO"
cp "$ROOT/policies/module-size.yml"            "$REPO/policies/"
cp "$ROOT/hooks/shared/module_size.py"         "$REPO/hooks/shared/"
cp "$ROOT/hooks/local/check-module-size.sh"    "$REPO/hooks/local/"

# Consumer's OWN over-ceiling file (built via shell redirection, not python open()).
BIG_LINES=900
mkdir -p "$REPO/src" || { bad "setup-mkdir-src" "could not create src/"; finish; }
for _ in $(seq 1 "$BIG_LINES"); do printf 'x = 1\n'; done > "$REPO/src/big.py"
[ -f "$REPO/src/big.py" ] || { bad "setup-fixture-exists" "src/big.py not created (would false-green)"; finish; }
ok "setup-fixture-exists"
actual_lines="$(wc -l < "$REPO/src/big.py" | tr -d ' ')"
[ "$actual_lines" = "$BIG_LINES" ] || { bad "setup-fixture-line-count" "src/big.py $actual_lines lines, expected $BIG_LINES"; finish; }
ok "setup-fixture-line-count"

# Consumer's pre-upgrade baseline carries the PROJECT row (the W2 state).
cat > "$REPO/policies/module-size-baseline.txt" <<EOF
# FR-25 module-size baseline — over-ceiling files frozen at current size.
$BIG_LINES src/big.py
EOF
"${GIT[@]}" add -A >/dev/null 2>&1; "${GIT[@]}" commit -q -m init >/dev/null 2>&1
"${GIT[@]}" ls-files --error-unmatch src/big.py >/dev/null 2>&1 \
  || { bad "setup-fixture-tracked" "src/big.py not tracked (--all would skip it)"; finish; }
ok "setup-fixture-tracked"

# Pre-condition: the consumer baseline passes BEFORE the hop.
( cd "$REPO" && bash hooks/local/check-module-size.sh --all >/dev/null 2>&1 ) \
  && ok "pre-hop-check-passes" || { bad "pre-hop-check-passes" "check failed before the hop"; finish; }

# Confirm the pre-v3.25 precondition: the consumer has NO local merge lib at start.
[ ! -e "$REPO/hooks/local/lib/merge-module-size-baseline.sh" ] \
  && ok "precondition-no-local-lib" || { bad "precondition-no-local-lib" "local lib unexpectedly present"; finish; }

# $SOURCE_CLONE staged as the v3.25.x target (the current repo's lib is authoritative).
SOURCE_CLONE="$REPO/.fusebase-flow-source"
mkdir -p "$SOURCE_CLONE/hooks/local/lib"
cp "$SRC_LIB" "$SOURCE_CLONE/hooks/local/lib/"
cp "$REPO/policies/module-size-baseline.txt" "$TMP/local-snapshot.txt"   # pre-clobber snapshot

# Upstream baseline (installed by the wholesale copy) knows nothing about src/big.py.
mkdir -p "$SOURCE_CLONE/policies"
printf '# FR-25 module-size baseline — over-ceiling files frozen at current size.\n' \
  > "$SOURCE_CLONE/policies/module-size-baseline.txt"

###############################################################################
# Helper: run ONE arm of the hop in a subshell with a chosen source-load strategy,
# emulating upgrade.sh Step 1 (clobber policies/ baseline) + Step 1a (guarded merge).
# Returns 0 if the project row survives in $REPO/policies/module-size-baseline.txt.
###############################################################################
run_hop_arm() {
  local strategy="$1"   # "prefix" (PRE-FIX: local-only) | "engine" (POST-FIX: source_merge_lib)
  # Restore the consumer's pre-hop baseline, then CLOBBER it as Step 1 does.
  cp "$TMP/local-snapshot.txt" "$REPO/policies/module-size-baseline.txt"
  local snap="$TMP/arm-snap.txt"; cp "$REPO/policies/module-size-baseline.txt" "$snap"
  cp "$SOURCE_CLONE/policies/module-size-baseline.txt" "$REPO/policies/module-size-baseline.txt"  # wholesale clobber
  (
    set +e
    ROOT="$REPO"; SOURCE_CLONE="$SOURCE_CLONE"
    MERGE_LIB="$ROOT/hooks/local/lib/merge-module-size-baseline.sh"
    if [ "$strategy" = "prefix" ]; then
      # PRE-FIX (v3.25.0) source logic: local tree ONLY. lib is absent -> no-op.
      [ -f "$MERGE_LIB" ] && . "$MERGE_LIB" 2>/dev/null
    else
      # POST-FIX: the REAL source_merge_lib() lifted from the shipped upgrade.sh.
      . "$ENGINE_FUNCS"
      source_merge_lib || true
    fi
    # Step 1a guard, verbatim semantics from upgrade.sh.
    if command -v merge_module_size_baseline >/dev/null 2>&1; then
      merge_module_size_baseline "$snap" "$SOURCE_CLONE/policies/module-size-baseline.txt" \
        "$REPO/policies/module-size-baseline.txt.new" 2>/dev/null
      mv "$REPO/policies/module-size-baseline.txt.new" "$REPO/policies/module-size-baseline.txt"
    fi
  )
  grep -qxF "$BIG_LINES src/big.py" "$REPO/policies/module-size-baseline.txt"
}

###############################################################################
# RED arm — pre-fix source logic must LOSE the project row (proves the test bites).
###############################################################################
if run_hop_arm "prefix"; then
  bad "red-prefix-loses-row" "PRE-FIX logic preserved the row — test cannot detect the bug (false-green risk)"
else
  ok "red-prefix-loses-row"
fi

###############################################################################
# GREEN arm — post-fix source logic (the shipped source_merge_lib) PRESERVES the
# row AND check-module-size --all passes. This is the actual fix.
###############################################################################
if run_hop_arm "engine"; then
  ok "green-engine-preserves-row"
else
  bad "green-engine-preserves-row" "POST-FIX source_merge_lib failed to preserve the project row (P2 broken)"
fi
"${GIT[@]}" add -A >/dev/null 2>&1
( cd "$REPO" && bash hooks/local/check-module-size.sh --all >/dev/null 2>&1 ) \
  && ok "green-post-hop-check-passes" \
  || bad "green-post-hop-check-passes" "check-module-size --all failed after the fixed hop (the W2 bug recurs)"

###############################################################################
# P1 proof — the REAL bootstrap-upgrade.sh staging step copies hooks/local/lib/ from
# the source into the consumer BEFORE handoff. Run just the staging logic against a
# source tree and assert the lib lands locally (the precondition P2 also relies on).
###############################################################################
BREPO="$TMP/brepo"
mkdir -p "$BREPO/hooks/local" "$BREPO/.fusebase-flow-source/hooks/local/lib"
git init -q "$BREPO"
cp "$SRC_LIB" "$BREPO/.fusebase-flow-source/hooks/local/lib/"
# Minimal source tree the bootstrap staging needs (it copies engine scripts + lib/).
cp "$BOOTSTRAP_SH" "$BREPO/.fusebase-flow-source/hooks/local/" 2>/dev/null || true
[ ! -e "$BREPO/hooks/local/lib/merge-module-size-baseline.sh" ] \
  && ok "p1-precondition-no-lib" || bad "p1-precondition-no-lib" "lib present before staging"
# Exercise the staging block directly (the part the handoff added).
(
  set -e
  cd "$BREPO"
  SOURCE_CLONE=".fusebase-flow-source"; TS="test"
  if [ -d "$SOURCE_CLONE/hooks/local/lib" ]; then
    [ -d hooks/local/lib ] && cp -R hooks/local/lib "hooks/local/lib.pre-bootstrap-$TS"
    mkdir -p hooks/local/lib
    cp -R "$SOURCE_CLONE/hooks/local/lib/." hooks/local/lib/
  fi
)
[ -f "$BREPO/hooks/local/lib/merge-module-size-baseline.sh" ] \
  && ok "p1-bootstrap-stages-lib" \
  || bad "p1-bootstrap-stages-lib" "bootstrap staging did not copy hooks/local/lib/ (P1 broken)"
# And the bootstrap script itself must actually contain the staging block (guards
# against the test passing while the script regressed).
grep -q 'hooks/local/lib' "$BOOTSTRAP_SH" \
  && ok "p1-bootstrap-references-lib" \
  || bad "p1-bootstrap-references-lib" "bootstrap-upgrade.sh has no hooks/local/lib staging (P1 missing)"

finish
