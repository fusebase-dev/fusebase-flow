#!/usr/bin/env bash
# Fusebase Flow — po-verifiable-boot regression test.
# Exercises the REAL shipped surfaces (no paraphrase): both command copies
# (AC1), command-vs-agent boot-block drift (AC2), the live user_prompt_submit.py
# detector (AC3), and the live stop.py dedicated PO-activation path (AC4).
#
# AC1 — both command copies carry the boot block + the stable marker prefix
#       '[[ PO-ACTIVATED | FuseBase Flow' (NOT a version number) and are
#       byte-identical.
# AC2 — the delimited PO-BOOT-BLOCK in the command == the one in the canonical
#       agent (drift guard, D4).
# AC3 — user_prompt_submit.py: a /product-owner prompt -> reminder (warn); a
#       non-PO prompt mentioning "product owner" as words -> no reminder (no
#       false positive); never blocks (rc 0).
# AC4 — genuine RED-then-GREEN against hooks/handlers/stop.py:
#         RED   — PO activation WITHOUT the marker (and NO claim phrase) -> warn
#                 emitted AND stdout decision still 'allow' (the PO path fires
#                 outside CLAIM_PATTERNS; never denies).
#         GREEN — PO activation WITH the marker -> no warn.
#                 non-PO transcript -> no warn (no false positive).
#       Gate-not-loosened guard: a done/deploy claim missing a REQUIRED signal
#       still DENIES. The RED arm proves the test bites: were the detector
#       always-false, red-no-marker-warns FAILs; were the PO warn wired to deny,
#       red-no-marker-still-allows FAILs; were the done gate loosened,
#       required-still-denies FAILs.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: po-verifiable-boot <name>" / "FAIL: po-verifiable-boot <name>";
#   exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CMD="$ROOT/.claude/commands/product-owner.md"
CMD_OVERLAY="$ROOT/hooks/local/fusebase-flow-overlays/commands/product-owner.md"
AGENT="$ROOT/agents/product-owner/AGENT.md"
STOP_PY="$ROOT/hooks/handlers/stop.py"
UPS_PY="$ROOT/hooks/handlers/user_prompt_submit.py"
MARKER_PREFIX='[[ PO-ACTIVATED | FuseBase Flow'
python_bin="${PYTHON:-python3}"; command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: po-verifiable-boot $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: po-verifiable-boot $1 ($2)"; }
finish() { echo "[test-po-verifiable-boot] $pass/$((pass + fail)) PASS"; exit $fail; }

# Loud setup preconditions — a missing input must FAIL, never false-green.
for f in "$CMD" "$CMD_OVERLAY" "$AGENT" "$STOP_PY" "$UPS_PY"; do
  [ -f "$f" ] || { bad "setup-input-present" "missing $f"; finish; }
done
ok "setup-inputs-present"

###############################################################################
# AC1 — both command copies carry the block + marker prefix, byte-identical.
###############################################################################
grep -qF "$MARKER_PREFIX" "$CMD" \
  && ok "ac1-cmd-has-marker-prefix" \
  || bad "ac1-cmd-has-marker-prefix" "stable marker prefix missing from command"
grep -qF "$MARKER_PREFIX" "$CMD_OVERLAY" \
  && ok "ac1-overlay-has-marker-prefix" \
  || bad "ac1-overlay-has-marker-prefix" "stable marker prefix missing from overlay command"
# The checklist block (present-by-construction, not a 'remember to attest' line).
grep -qF "PO activation — FuseBase Flow operating requirements" "$CMD" \
  && ok "ac1-cmd-has-checklist" \
  || bad "ac1-cmd-has-checklist" "activation checklist header missing from command"
if diff -q "$CMD" "$CMD_OVERLAY" >/dev/null 2>&1; then
  ok "ac1-cmd-overlay-byte-identical"
else
  bad "ac1-cmd-overlay-byte-identical" "command and overlay copy diverged"
fi

###############################################################################
# AC2 — drift guard: the delimited PO-BOOT-BLOCK in the command == the one in
# the canonical agent. Extract between the START/END markers (exclusive).
###############################################################################
extract_block() { # extract_block <file> -> prints lines strictly between markers
  awk '/PO-BOOT-BLOCK:START/{f=1;next} /PO-BOOT-BLOCK:END/{f=0} f' "$1"
}
cmd_block="$(extract_block "$CMD")"
agent_block="$(extract_block "$AGENT")"
if [ -z "$cmd_block" ]; then
  bad "ac2-cmd-block-nonempty" "no PO-BOOT-BLOCK delimited region in command (drift guard cannot run)"
elif [ -z "$agent_block" ]; then
  bad "ac2-agent-block-nonempty" "no PO-BOOT-BLOCK delimited region in agent (drift guard cannot run)"
elif [ "$cmd_block" = "$agent_block" ]; then
  ok "ac2-cmd-agent-block-match"
else
  bad "ac2-cmd-agent-block-match" "command boot block != agent boot block (D4 drift)"
fi
# Sanity: the extracted block actually contains the marker (guards against the
# awk extracting an empty/wrong region that would trivially 'match').
echo "$cmd_block" | grep -qF "$MARKER_PREFIX" \
  && ok "ac2-extracted-block-has-marker" \
  || bad "ac2-extracted-block-has-marker" "extracted boot block lacks the marker (extraction wrong?)"

###############################################################################
# AC3 — live user_prompt_submit.py detection.
###############################################################################
# MSYS/Git-Bash rewrites any leading-slash string into a Windows path at the
# shell layer (even via env var), corrupting '/product-owner'. Portable fix: the
# literal slash is encoded as the sentinel '@SLASH@' in test prompts and Python
# (not the shell) decodes it when building the JSON. No platform env-var needed.
mkjson() { # mkjson <key> ; reads MSG env -> prints {"<key>":<json>,"cwd":"."}
  KEY="$1" "$python_bin" -c 'import json,os;print(json.dumps({os.environ["KEY"]:os.environ.get("MSG","").replace("@SLASH@","/"),"cwd":"."}))'
}
ups_run() { # ups_run <user_prompt> -> prints "decision|warns_joined" via stdout JSON
  MSG="$1" mkjson user_prompt \
    | "$python_bin" "$UPS_PY" 2>/dev/null \
    | "$python_bin" -c 'import json,sys;d=json.load(sys.stdin);print(d.get("decision","")+"|"+" ".join(d.get("warnings",[])))'
}
ups_rc() { # ups_rc <user_prompt> -> prints the handler exit code
  MSG="$1" mkjson user_prompt | "$python_bin" "$UPS_PY" >/dev/null 2>&1; echo $?
}

po_out="$(ups_run "@SLASH@product-owner let us plan ticket X")"
if echo "$po_out" | grep -q "emit the activation boot"; then
  ok "ac3-po-prompt-reminder"
else
  bad "ac3-po-prompt-reminder" "/product-owner prompt did not emit the activation reminder (got: $po_out)"
fi
# False-positive guard: 'product owner' as plain words (no slash command).
nonpo_out="$(ups_run "please review the product owner role documentation")"
if echo "$nonpo_out" | grep -q "emit the activation boot"; then
  bad "ac3-nonpo-no-reminder" "non-PO prompt falsely triggered the activation reminder (got: $nonpo_out)"
else
  ok "ac3-nonpo-no-reminder"
fi
# Never blocks (rc 0) even when the reminder fires.
if [ "$(ups_rc "@SLASH@product-owner go")" = "0" ]; then
  ok "ac3-never-blocks"
else
  bad "ac3-never-blocks" "user_prompt_submit returned non-zero rc on a /product-owner prompt"
fi

###############################################################################
# AC4 — RED-then-GREEN against the REAL stop.py dedicated PO-activation path.
# Helpers run the live handler and report (a) stdout decision and (b) whether a
# PO-activation warn was emitted to stderr.
###############################################################################
stop_decision() { # stop_decision <agent_message> -> stdout JSON decision
  MSG="$1" mkjson agent_message \
    | "$python_bin" "$STOP_PY" 2>/dev/null \
    | "$python_bin" -c 'import json,sys;print(json.load(sys.stdin).get("decision",""))'
}
stop_po_warned() { # stop_po_warned <agent_message> -> prints "yes"/"no" from stderr
  local err
  err="$(MSG="$1" mkjson agent_message | "$python_bin" "$STOP_PY" 2>&1 >/dev/null)"
  if echo "$err" | grep -q "activation marker is absent"; then echo "yes"; else echo "no"; fi
}

# A PO activation message with NO claim phrase (proves the path fires outside
# CLAIM_PATTERNS) and NO marker.
PO_NO_MARKER="@SLASH@product-owner starting the session, here is the plan"
# Same PO activation but WITH the marker echoed.
PO_WITH_MARKER="@SLASH@product-owner $MARKER_PREFIX 3.26.0 | FR-01..FR-26 | no-app-code ]]"
# A non-PO transcript (plain words, no slash command, no marker).
NON_PO="discussing the product owner workflow in general"
# A done-claim missing the REQUIRED gate report (no PO activation involved).
DONE_MISSING_REQUIRED="all tasks done. git diff --stat. lint clean. typecheck clean."

# RED — PO activation, no marker, NO claim phrase: warn emitted...
if [ "$(stop_po_warned "$PO_NO_MARKER")" = "yes" ]; then
  ok "ac4-red-no-marker-warns"
else
  bad "ac4-red-no-marker-warns" "PO activation without marker did NOT warn (path inert / detector always-false)"
fi
# ...AND stdout decision still 'allow' (the PO warn never denies; fires without a claim).
if [ "$(stop_decision "$PO_NO_MARKER")" = "allow" ]; then
  ok "ac4-red-no-marker-still-allows"
else
  bad "ac4-red-no-marker-still-allows" "PO warn flipped the decision away from allow (must never deny)"
fi

# GREEN — PO activation WITH marker: no warn.
if [ "$(stop_po_warned "$PO_WITH_MARKER")" = "no" ]; then
  ok "ac4-green-with-marker-no-warn"
else
  bad "ac4-green-with-marker-no-warn" "marker present but PO-activation warn still fired"
fi
# GREEN — non-PO transcript: no warn (no false positive).
if [ "$(stop_po_warned "$NON_PO")" = "no" ]; then
  ok "ac4-green-nonpo-no-warn"
else
  bad "ac4-green-nonpo-no-warn" "non-PO transcript falsely triggered the PO-activation warn"
fi

# Gate-not-loosened guard: a done-claim missing a REQUIRED signal still DENIES.
if [ "$(stop_decision "$DONE_MISSING_REQUIRED")" = "deny" ]; then
  ok "ac4-required-still-denies"
else
  bad "ac4-required-still-denies" "a missing REQUIRED done-gate signal no longer denies (gate loosened)"
fi

finish
