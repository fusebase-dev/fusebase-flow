#!/usr/bin/env bash
# Fusebase Flow — mutation discriminator for the §1b missing-interpreter block (AC6).
# Spec: docs/specs/msys-test-fixture-rework/spec.md; evidence contract in
# docs/specs/msys-test-fixture-rework/verification-gate.md § Mutation evidence contract.
#
# A named RED is NOT proof. This harness accepts the contract test as an oracle only after all
# four clauses hold: unique mutation target; unmutated BASELINE copy GREEN; the mutant flips
# EXACTLY `8-interpreter-absent-blocks`; every prerequisite/control row identical; and an
# UNMUTATED copy presented as the mutant is REJECTED (the harness fails itself).
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: interpreter-mutation <name>" / "FAIL: interpreter-mutation <name>"; exit = fail count.
#
# TRIPWIRE — production hooks/git/pre-commit is COPIED and mutated only inside this run's temp
# state; it is byte-compared at the end and must never be written to.
# TRIPWIRE — deleting the target `exit 1` still yields rc != 0 (an empty FFPC_FOUND writes a
# broken `exec  "$@"` shim and a later python3 call fails), which is exactly why the verdict is a
# one-row delta plus control invariance, never "the run went red".

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOOK="$ROOT/hooks/git/pre-commit"
CONTRACT="$ROOT/hooks/tests/test-pre-commit-interpreter-contract.sh"
TARGET_ROW="8-interpreter-absent-blocks"
DIAG="no supported Python 3.10+ interpreter found"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: interpreter-mutation $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: interpreter-mutation $1 (${2:-})"; }
finish() { echo "[test-pre-commit-interpreter-mutation] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$HOOK" ]     || { bad "hook-present" "missing $HOOK"; finish; }
[ -f "$CONTRACT" ] || { bad "contract-present" "missing $CONTRACT"; finish; }
command -v python3 >/dev/null 2>&1 || { ok "skipped-no-python3"; finish; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffim-mutation.XXXXXX")"
cleanup() { case "$TMP" in "${TMPDIR:-/tmp}"/ffim-mutation.*) rm -rf -- "$TMP" ;; esac; }
trap cleanup EXIT

# ---- 1. Unique target: the ONE `exit 1` between §1b's diagnostic and the end of its if-block. ----
diag_hits="$(grep -cF "$DIAG" "$HOOK")"
if [ "${diag_hits:-0}" -eq 1 ]; then ok "mutation-diagnostic-unique"
else bad "mutation-diagnostic-unique" "expected exactly 1 missing-interpreter diagnostic, found ${diag_hits:-0}"; finish; fi

diag_line="$(grep -nF "$DIAG" "$HOOK" | cut -d: -f1)"
fi_line="$(awk -v d="$diag_line" 'NR>d && /^[[:space:]]*fi[[:space:]]*$/ {print NR; exit}' "$HOOK")"
targets="$(awk -v d="$diag_line" -v f="${fi_line:-0}" 'NR>d && NR<f && /^[[:space:]]*exit 1[[:space:]]*$/ {print NR}' "$HOOK")"
target_n="$(printf '%s' "$targets" | grep -c . || true)"
if [ "${target_n:-0}" -eq 1 ]; then ok "mutation-target-unique"
else bad "mutation-target-unique" "expected exactly 1 diagnostic-adjacent 'exit 1' in lines $((diag_line + 1))..$((${fi_line:-0} - 1)), found ${target_n:-0}"; finish; fi
TARGET_LINE="$targets"

# ---- 2. Isolated copies: baseline, mutant, and the unmutated negative control. ----
cp "$HOOK" "$TMP/baseline"
cp "$HOOK" "$TMP/negative"
sed "${TARGET_LINE}d" "$HOOK" > "$TMP/mutant"
removed="$(diff "$TMP/baseline" "$TMP/mutant" | grep -c '^<' || true)"
added="$(diff "$TMP/baseline" "$TMP/mutant" | grep -c '^>' || true)"
if [ "${removed:-0}" -eq 1 ] && [ "${added:-0}" -eq 0 ]; then ok "mutation-is-single-line-deletion"
else bad "mutation-is-single-line-deletion" "expected exactly one removed line and none added (removed=${removed:-0} added=${added:-0})"; finish; fi
if cmp -s "$TMP/baseline" "$TMP/negative"; then ok "mutation-negative-control-is-unmutated"
else bad "mutation-negative-control-is-unmutated" "the negative control differs from the unmutated hook"; finish; fi

# ---- 3. Run the contract oracle against each copy; normalize to "<row>=<PASS|FAIL>". ----
run_contract() {   # run_contract <hook-copy> <label> -> sets RC_LAST; writes $TMP/<label>.results
  local hook="$1" label="$2" rc=0
  FFIC_HOOK="$hook" bash "$CONTRACT" > "$TMP/$label.out" 2> "$TMP/$label.err" || rc=$?
  sed -n 's/^\(PASS\|FAIL\): interpreter-contract \([^ ]*\).*/\2=\1/p' "$TMP/$label.out" | sort > "$TMP/$label.results"
  RC_LAST=$rc
}

run_contract "$TMP/baseline" baseline; baseline_rc=$RC_LAST
base_rows="$(grep -c . "$TMP/baseline.results" || true)"
base_fails="$(grep -c '=FAIL$' "$TMP/baseline.results" || true)"
if [ "${base_rows:-0}" -ge 4 ] && [ "${base_fails:-0}" -eq 0 ] && [ "$baseline_rc" -eq 0 ]; then
  ok "mutation-baseline-green"
else
  bad "mutation-baseline-green" "the UNMUTATED copy is not GREEN (rows=${base_rows:-0} fails=${base_fails:-0} rc=$baseline_rc) — no mutant verdict can be trusted"
  finish
fi

run_contract "$TMP/mutant" mutant; mutant_rc=$RC_LAST
run_contract "$TMP/negative" negative; negative_rc=$RC_LAST

# mutation_verdict <baseline.results> <candidate.results>: 0 ONLY when the candidate flips exactly
# the target row PASS->FAIL and leaves every other row identical. MV_TARGET / MV_CONTROLS carry the
# clause-level outcome so each can be reported as its own row.
mutation_verdict() {
  local b="$1" c="$2" line row res_b res_c
  MV_TARGET=0; MV_CONTROLS=1; MV_NOTE=""
  if ! diff <(cut -d= -f1 "$b") <(cut -d= -f1 "$c") >/dev/null 2>&1; then
    MV_CONTROLS=0; MV_NOTE="row-name sets differ between baseline and candidate"; return 1
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    row="${line%%=*}"; res_b="${line#*=}"
    res_c="$(sed -n "s/^$row=//p" "$c")"
    if [ "$row" = "$TARGET_ROW" ]; then
      if [ "$res_b" = "PASS" ] && [ "$res_c" = "FAIL" ]; then MV_TARGET=1
      else MV_NOTE="$MV_NOTE target row did not flip PASS->FAIL (baseline=$res_b candidate=$res_c);"; fi
    elif [ "$res_b" != "$res_c" ]; then
      MV_CONTROLS=0; MV_NOTE="$MV_NOTE control row '$row' changed ($res_b -> $res_c);"
    fi
  done < "$b"
  [ "$MV_TARGET" -eq 1 ] && [ "$MV_CONTROLS" -eq 1 ]
}

mutation_verdict "$TMP/baseline.results" "$TMP/mutant.results"; mutant_verdict_rc=$?
mutant_target=$MV_TARGET; mutant_controls=$MV_CONTROLS; mutant_note="$MV_NOTE"
mutant_fails="$(grep -c '=FAIL$' "$TMP/mutant.results" || true)"

if [ "$mutant_target" -eq 1 ] && [ "${mutant_fails:-0}" -eq 1 ]; then
  ok "mutation-mutant-fails-exactly-the-target-row"
else
  bad "mutation-mutant-fails-exactly-the-target-row" \
      "expected exactly 1 FAIL row ($TARGET_ROW); got ${mutant_fails:-0} FAIL row(s).${mutant_note:+ $mutant_note}"
fi
if [ "$mutant_controls" -eq 1 ]; then ok "mutation-controls-identical"
else bad "mutation-controls-identical" "a prerequisite/control row changed between baseline and mutant:${mutant_note:-}"; fi

# ---- 4. Negative control: an UNMUTATED copy presented as the mutant must be REJECTED. ----
mutation_verdict "$TMP/baseline.results" "$TMP/negative.results"; negative_verdict_rc=$?
if [ "$negative_verdict_rc" -ne 0 ]; then
  ok "mutation-negative-control-rejected"
else
  bad "mutation-negative-control-rejected" \
      "the harness ACCEPTED an unmutated copy as a detected mutant — an undetected mutation would pass this gate"
fi

# ---- 5. AC10: the production hook was never written to. ----
if cmp -s "$HOOK" "$TMP/baseline" && git -C "$ROOT" diff --quiet -- hooks/git/pre-commit 2>/dev/null; then
  ok "mutation-production-hook-unchanged"
else
  bad "mutation-production-hook-unchanged" "hooks/git/pre-commit differs from the copy taken at start, or from the index"
fi

# Evidence for the gate report's mutation_proof field (stderr: the ^PASS:/^FAIL: parse stays clean).
{
  echo "[interpreter-mutation] target: 1 unique 'exit 1' at ${HOOK#"$ROOT/"}:$TARGET_LINE (diagnostic line $diag_line, block ends $fi_line)"
  echo "[interpreter-mutation] baseline rc=$baseline_rc rows=$base_rows fails=$base_fails"
  echo "[interpreter-mutation] mutant   rc=$mutant_rc fails=$mutant_fails verdict_rc=$mutant_verdict_rc"
  echo "[interpreter-mutation] negative rc=$negative_rc verdict_rc=$negative_verdict_rc (nonzero = correctly rejected)"
  echo "[interpreter-mutation] delta:"
  diff "$TMP/baseline.results" "$TMP/mutant.results" || true
} >&2

finish
