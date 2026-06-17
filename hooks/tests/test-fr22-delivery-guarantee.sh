#!/usr/bin/env bash
# Fusebase Flow — fr22-delivery-guarantee (Phase 1) regression test.
# Exercises the REAL shipped surfaces (no paraphrase): the handoff template text
# (AC1) and the live stop.py signal detection + warn-not-deny semantics (AC3).
#
# AC1  — templates/handoff-implement.md carries the FR-22 Delegation push block by
#        construction (present-by-construction, not a "remember to inline" line).
# AC3  — genuine RED-then-GREEN against hooks/handlers/stop.py:
#          RED   — marker ABSENT  -> comment_policy_review_applied NOT detected, AND
#                  a done-claim with all REQUIRED signals still ALLOWS (the
#                  recommended-missing signal must NOT block — decision D1).
#          GREEN — marker PRESENT (either phrase) -> signal detected.
#        The RED arm proves the test bites: were detection broken to always-true,
#        red-marker-absent-not-detected FAILs; were the recommended list wired as a
#        required/deny entry, red-absent-still-allows FAILs.
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: fr22-delivery <name>"
# / "FAIL: fr22-delivery <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STOP_PY="$ROOT/hooks/handlers/stop.py"
TEMPLATE="$ROOT/templates/handoff-implement.md"
python_bin="${PYTHON:-python3}"; command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: fr22-delivery $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: fr22-delivery $1 ($2)"; }
finish() { echo "[test-fr22-delivery-guarantee] $pass/$((pass + fail)) PASS"; exit $fail; }

# Loud setup preconditions — a missing input must FAIL, never false-green.
[ -f "$STOP_PY" ]   || { bad "setup-stop-present"     "missing $STOP_PY"; finish; }
[ -f "$TEMPLATE" ]  || { bad "setup-template-present" "missing $TEMPLATE"; finish; }
ok "setup-inputs-present"

###############################################################################
# AC1 — the template carries the FR-22 push block text by construction.
# Assert the load-bearing block lines, not just the heading (a heading alone
# without the rendered block would be the old "remember to inline" failure).
###############################################################################
grep -qF "COMMENT POLICY (FR-22) — applies to all code you write:" "$TEMPLATE" \
  && ok "ac1-template-has-pushblock-header" \
  || bad "ac1-template-has-pushblock-header" "FR-22 push-block header not rendered in template"
grep -qF "1) TRIPWIRE — a constraint an editor could break unknowingly" "$TEMPLATE" \
  && ok "ac1-template-has-tripwire-line" \
  || bad "ac1-template-has-tripwire-line" "tripwire line missing from template push block"
grep -qF "2) RETRIEVAL POINTER — a ≤1-line tag naming the external WHY-home" "$TEMPLATE" \
  && ok "ac1-template-has-pointer-line" \
  || bad "ac1-template-has-pointer-line" "retrieval-pointer line missing from template push block"
grep -qF "Do NOT match surrounding comment density upward." "$TEMPLATE" \
  && ok "ac1-template-has-density-clause" \
  || bad "ac1-template-has-density-clause" "density clause missing from template push block"
# Guard against regression to the old prose-only instruction (no rendered block).
grep -q "Present-by-construction" "$TEMPLATE" \
  && ok "ac1-template-present-by-construction-note" \
  || bad "ac1-template-present-by-construction-note" "present-by-construction marker absent (regressed to remember-to-inline?)"

###############################################################################
# AC3 — RED-then-GREEN against the REAL stop.py. Helper invokes the live handler
# with a chosen agent_message and returns its JSON decision + whether the signal
# fired (we read the signal directly from stop.py's own detector to avoid a
# paraphrase).
###############################################################################
# Probe the live detector for one phrase (true/false), using the shipped function.
detect_signal() { # detect_signal <message> -> prints "True"/"False"
  MSG="$1" "$python_bin" - "$STOP_PY" <<'PY'
import os, sys, importlib.util
spec = importlib.util.spec_from_file_location("stop_mod", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
det = mod._signals_from_transcript(os.environ["MSG"], {})
print(det.get("comment_policy_review_applied", False))
PY
}

# Run the live stop.py end-to-end with a done-claim message; print its decision.
stop_decision() { # stop_decision <agent_message> -> prints decision string
  printf '{"agent_message":%s,"cwd":"."}' "$("$python_bin" -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" \
    | "$python_bin" "$STOP_PY" 2>/dev/null \
    | "$python_bin" -c 'import json,sys;print(json.load(sys.stdin).get("decision",""))'
}

DONE_BASE="all tasks done. git diff --stat. lint clean. typecheck clean. Gate report."

# RED — marker ABSENT: signal must NOT be detected.
if [ "$(detect_signal "$DONE_BASE")" = "False" ]; then
  ok "ac3-red-absent-not-detected"
else
  bad "ac3-red-absent-not-detected" "signal fired with NO marker present (detector too loose -> false-green risk)"
fi

# RED — marker ABSENT but all REQUIRED signals present: stop must still ALLOW
# (the recommended/warn signal must NOT block — decision D1).
if [ "$(stop_decision "$DONE_BASE")" = "allow" ]; then
  ok "ac3-red-absent-still-allows"
else
  bad "ac3-red-absent-still-allows" "missing recommended FR-22 signal blocked the done-claim (must warn, not deny)"
fi

# GREEN — 'applied' marker present: signal detected.
if [ "$(detect_signal "$DONE_BASE comment-policy review: applied (FR-22)")" = "True" ]; then
  ok "ac3-green-applied-detected"
else
  bad "ac3-green-applied-detected" "'applied (FR-22)' marker did not trigger the signal"
fi

# GREEN — 'N/A' marker present (no-code ticket): signal detected.
if [ "$(detect_signal "$DONE_BASE comment-policy review: N/A (FR-22; no code diff)")" = "True" ]; then
  ok "ac3-green-na-detected"
else
  bad "ac3-green-na-detected" "'N/A (FR-22; no code diff)' marker did not trigger the signal"
fi

# Guard — existing required signal still blocks (proves we did not loosen the gate).
# A done-claim missing the gate report (required) must still DENY.
if [ "$(stop_decision "all tasks done. git diff --stat. lint clean. typecheck clean.")" = "deny" ]; then
  ok "ac3-required-still-denies"
else
  bad "ac3-required-still-denies" "a missing REQUIRED signal no longer denies (gate loosened)"
fi

finish
