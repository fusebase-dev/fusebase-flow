#!/usr/bin/env bash
# Fusebase Flow — delegated chat-return budget contract test (S1 / AC12–AC13).
#
# Asserts the REAL shipped carriers (no paraphrase):
#   AC12 — the ≤80-line AND ≤6,000-character cap is present in the task-delegation
#          successor/return contract and in BOTH handoff-template push blocks, with
#          the overflow route (sanctioned durable artifact; commit only when the
#          owning workflow requires it).
#   AC13 — the canonical gate report and deploy report carry an EXPLICIT exemption
#          at their own contract sections.
#   RED  — a line-only cap must not satisfy the predicate. The bite arm strips the
#          character limit from a temp copy; if `both_limits` still passed, the test
#          would be vacuous and AC12's whole point (one 32k-char line evades a
#          line-only gate) would go unenforced.
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: return-budget <name>"
# / "FAIL: return-budget <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SKILL="$ROOT/flow-skills/task-delegation/SKILL.md"
IMPL="$ROOT/templates/handoff-implement.md"
DEPL="$ROOT/templates/handoff-deploy.md"
HANDOFF="$ROOT/templates/handoff.md"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: return-budget $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: return-budget $1 ($2)"; }
finish() { echo "[test-return-budget] $pass/$((pass + fail)) PASS"; exit $fail; }

for f in "$SKILL" "$IMPL" "$DEPL" "$HANDOFF"; do
    [ -f "$f" ] || { bad "setup-inputs-present" "missing $f"; finish; }
done
ok "setup-inputs-present"

# both_limits FILE: 0 iff some single line carries BOTH caps. A line-only cap fails.
both_limits() { grep -F '≤80 lines' "$1" | grep -qF '≤6,000 characters'; }

has() { # has FILE LITERAL NAME DETAIL
    grep -qF "$2" "$1" && ok "$3" || bad "$3" "$4"
}

# --- AC12: both limits, on one line, in each of the three carriers ------------------
both_limits "$SKILL" && ok "ac12-skill-both-limits" \
  || bad "ac12-skill-both-limits" "task-delegation SKILL.md lacks a line carrying both ≤80 lines and ≤6,000 characters"
both_limits "$IMPL" && ok "ac12-implement-both-limits" \
  || bad "ac12-implement-both-limits" "handoff-implement.md push block lacks both caps on one line"
both_limits "$DEPL" && ok "ac12-deploy-both-limits" \
  || bad "ac12-deploy-both-limits" "handoff-deploy.md push block lacks both caps on one line"

# --- AC12: the overflow route (artifact path, conditional commit) -------------------
has "$SKILL" "write a sanctioned durable artifact and return its path" \
    "ac12-skill-overflow-route" "overflow-to-artifact route missing from the return contract"
has "$SKILL" "commit only when the owning workflow requires it" \
    "ac12-skill-commit-conditional" "unconditional-commit regression (read-only delegates must not be forced to commit)"
has "$IMPL" "write a sanctioned durable artifact and return its path" \
    "ac12-implement-overflow-route" "overflow-to-artifact route missing from the implement push block"
has "$DEPL" "write a sanctioned durable artifact and return its path" \
    "ac12-deploy-overflow-route" "overflow-to-artifact route missing from the deploy push block"

# --- AC12: the budget is a named field of the delegation brief ----------------------
has "$SKILL" "| Return budget |" \
    "ac12-skill-brief-field" "delegation-brief table has no Return budget row"

# --- AC13: explicit exemption AT the gate/deploy report contract sections -----------
has "$IMPL" "Exempt from the delegated chat-return budget" \
    "ac13-implement-gate-exempt" "gate report contract does not state the AC13 exemption"
has "$DEPL" "Exempt from the delegated chat-return budget" \
    "ac13-deploy-report-exempt" "deploy report contract does not state the AC13 exemption"
has "$SKILL" "Exempt from the budget (AC13)" \
    "ac13-skill-exemption" "return-shape section does not carry the gate/deploy exemption"

# --- AC12: handoff.md points a successor at the durable-artifact route --------------
has "$HANDOFF" "successor contract" \
    "ac12-handoff-successor-pointer" "handoff template lost the successor-contract pointer"

# --- RED bite arm: strip the character cap; the predicate must reject ---------------
mutant="$(mktemp "${TMPDIR:-/tmp}/ffhc-rb-mutant.XXXXXX")"
sed 's/≤6,000 characters/UNBOUNDED/g' "$SKILL" > "$mutant" 2>/dev/null
if both_limits "$mutant"; then
    bad "red-line-only-cap-rejected" "predicate accepted a line-only cap — test is vacuous"
else
    ok "red-line-only-cap-rejected"
fi
rm -f "$mutant"

finish
