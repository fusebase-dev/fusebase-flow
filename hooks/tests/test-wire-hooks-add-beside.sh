#!/usr/bin/env bash
# Fusebase Flow — --wire-hooks must ADD BESIDE an occupied lifecycle-event array, and
# must never record a wiring intent it did not achieve.
#
# The defect (MEASURED, deterministic): settings-json-merge.py's add branch is a WHOLESALE
# REPLACE guarded to fire only when there is nothing to preserve (`event not in hooks or not
# hooks[event]`). A consumer who wired their OWN PreToolUse veto before adopting Flow lands in
# the fall-through, where _migrate_blocks (no legacy Flow command) and _widen_matchers (skips
# any block naming no hooks/handlers/ command) are both correct no-ops. Nothing adds Flow's
# block. Measured on all FIVE non-Stop events; Stop alone had an add-beside path.
#
# Why it was worse than a missing feature: the intent marker was recorded on the merge's EXIT
# CODE, and that merge exits 0 (it applied every other change). So the tree recorded INTENT with
# enforcement absent, and the health arm then reported "PreToolUse ENFORCEMENT STRIPPED" and
# prescribed --wire-hooks — the command that had just produced the state. A loop that cannot
# converge, on the population v4.14.0's release note directed at that exact command.
#
# The oracle is the CONTROL SET, not the fixed case: key-absent / [] / consumer+flow all wired
# BEFORE the fix, so a bare "the handler is present" assertion proves nothing. Only the
# consumer-only row separates the fix from the pre-fix code.
#
# Output contract (parsed by run-tests.sh): "PASS: wire-hooks-beside <name>" /
# "FAIL: wire-hooks-beside <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MERGE="$ROOT/hooks/local/fusebase-flow-overlays/settings-json-merge.py"
HWI_LIB="$ROOT/hooks/local/lib/hook-wiring-intent.sh"
RECOVERY="$ROOT/hooks/local/post-fusebase-update.sh"
PY="${PYTHON:-python3}"; command -v "$PY" >/dev/null 2>&1 || PY="python"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: wire-hooks-beside $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: wire-hooks-beside $1 ($2)"; }
# TRIPWIRE (incident E7): never name this TMP/TEMP/TMPDIR — on Windows those are PRE-SET env
# vars holding the operator's profile temp dir, and finish() can run BEFORE the mkdtemp
# assignment. Guard the delete on the mkdtemp TEMPLATE, never on non-emptiness.
WHB_TMP=""
whb_cleanup() { case "$WHB_TMP" in "${TMPDIR:-/tmp}"/ffhc-wirebeside.*) rm -rf -- "$WHB_TMP" ;; esac; }
finish() { whb_cleanup; echo "[test-wire-hooks-add-beside] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$MERGE" ]    || { bad "setup-merge-present" "missing $MERGE"; finish; }
[ -f "$HWI_LIB" ]  || { bad "setup-hwi-lib-present" "missing $HWI_LIB"; finish; }
[ -f "$RECOVERY" ] || { bad "setup-recovery-present" "missing $RECOVERY"; finish; }
command -v "$PY" >/dev/null 2>&1 || { bad "setup-python" "no python interpreter"; finish; }

WHB_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-wirebeside.XXXXXX")" || { bad "setup-mktemp" "mktemp failed"; finish; }
trap whb_cleanup EXIT

# shellcheck source=../local/lib/hook-wiring-intent.sh
. "$HWI_LIB"

###############################################################################
# Harness
###############################################################################
# Canonical handler stem per event — the detection contract the health arm applies
# (hooks/local/lib/hook-wiring-intent.sh: the `hooks/handlers/<stem>.py` SUBSTRING, never the
# event key). Kept as data so a new event is one row here, not a new code path.
EVENTS="SessionStart:session_start UserPromptSubmit:user_prompt_submit PreToolUse:pre_tool_use \
PostToolUse:post_tool_use PreCompact:pre_compact"

CONSUMER_CMD='bash "$CLAUDE_PROJECT_DIR"/hooks/local/consumer-veto.local.sh'

newtree() {   # -> a fresh fixture root (mktemp: a shell counter would not survive $( ))
  local d; d="$(mktemp -d "$WHB_TMP/fxXXXXXX")"
  mkdir -p "$d/.claude" "$d/state/audit"
  echo "$d"
}

# write_settings <file> <python-literal-for-the-hooks-dict>
write_settings() { printf '%s\n' "$2" > "$1"; }

# consumer_only <file> <event> — the defect's input: the consumer wired their OWN veto on this
# event BEFORE adopting Flow. Non-empty array, no Flow block.
consumer_only() {
  "$PY" - "$1" "$2" "$CONSUMER_CMD" <<'PY'
import json, sys
path, event, cmd = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {"hooks": {event: [{"matcher": "Bash|Edit|Write",
                          "hooks": [{"type": "command", "command": cmd, "timeout": 20}]}]}}
open(path, "w", encoding="utf-8").write(json.dumps(doc, indent=2) + "\n")
PY
}

# run_merge <tree> — run the merge exactly as Step 5 of post-fusebase-update.sh does.
run_merge() { ( cd "$1" && "$PY" "$MERGE" .claude/settings.json >/dev/null 2>&1 ); }

# handler_count <tree> <stem>
handler_count() { grep -c "hooks/handlers/$2\.py" "$1/.claude/settings.json" 2>/dev/null || true; }

# run_arm <tree> — the health engine's PreToolUse enforcement arm, called as the engine calls
# it, with record_drift stubbed the way the engine defines it.
run_arm() {
  LOCAL_OK=(); LOCAL_DRIFT=(); LOCAL_BROKEN=(); LOCAL_UNVERIFIED=(); LOCAL_DEFERRED=()
  DRIFT_IDS=()
  record_drift() { DRIFT_IDS+=("$1"); LOCAL_DRIFT+=("$2"); }
  ffhc_hwi_check "$1"
}
joined() { printf '%s\n' ${1+"$@"}; }

###############################################################################
# Rows A1-A4 — THE CONTROL SET. All four states of the event array, per event.
# A1/A2/A3 wired BEFORE the fix too; they are here so a green A4 cannot come from
# a change that simply always appends.
###############################################################################
for pair in $EVENTS; do
  event="${pair%%:*}"; stem="${pair#*:}"

  # A1 — key absent  => wired (wholesale-add branch; pre-existing behaviour)
  t="$(newtree)"; write_settings "$t/.claude/settings.json" '{ "hooks": {} }'
  run_merge "$t"
  [ "$(handler_count "$t" "$stem")" -ge 1 ] \
    && ok "A1-$event-key-absent-wired" \
    || bad "A1-$event-key-absent-wired" "handler absent after merge"

  # A2 — empty array => wired (same branch; `not hooks[event]` is true)
  t="$(newtree)"; write_settings "$t/.claude/settings.json" "{ \"hooks\": { \"$event\": [] } }"
  run_merge "$t"
  [ "$(handler_count "$t" "$stem")" -ge 1 ] \
    && ok "A2-$event-empty-array-wired" \
    || bad "A2-$event-empty-array-wired" "handler absent after merge"

  # A3 — consumer block + Flow block => present exactly ONCE (no duplicate append)
  t="$(newtree)"
  "$PY" - "$t/.claude/settings.json" "$event" "$stem" "$CONSUMER_CMD" <<'PY'
import json, sys
path, event, stem, cmd = sys.argv[1:5]
flow = 'bash "$CLAUDE_PROJECT_DIR"/hooks/local/run-handler.sh "$CLAUDE_PROJECT_DIR"/hooks/handlers/%s.py' % stem
doc = {"hooks": {event: [
    {"matcher": "Bash|Edit|Write", "hooks": [{"type": "command", "command": cmd, "timeout": 20}]},
    {"matcher": "Bash|PowerShell|Edit|Write|MultiEdit|NotebookEdit",
     "hooks": [{"type": "command", "command": flow, "timeout": 30}]}]}}
open(path, "w", encoding="utf-8").write(json.dumps(doc, indent=2) + "\n")
PY
  run_merge "$t"
  [ "$(handler_count "$t" "$stem")" -eq 1 ] \
    && ok "A3-$event-consumer-plus-flow-no-duplicate" \
    || bad "A3-$event-consumer-plus-flow-no-duplicate" "count=$(handler_count "$t" "$stem"), expected exactly 1"

  # A4 — CONSUMER ONLY => the defect. Non-empty array, no Flow block, nothing adds one.
  t="$(newtree)"; consumer_only "$t/.claude/settings.json" "$event"
  run_merge "$t"
  [ "$(handler_count "$t" "$stem")" -ge 1 ] \
    && ok "A4-$event-consumer-only-wired" \
    || bad "A4-$event-consumer-only-wired" "OCCUPIED $event array: Flow handler NOT added (the defect)"
done

###############################################################################
# Row A5 — PRESERVE, the other half. The consumer's block must survive DEEP-EQUAL
# (matcher never rewritten, chain never edited, timeout kept) and stay at its index.
# _widen_matchers already documents this guarantee for a Flow block; adding beside must
# not cost it.
###############################################################################
t="$(newtree)"; consumer_only "$t/.claude/settings.json" "PreToolUse"
cp "$t/.claude/settings.json" "$t/before.json"
run_merge "$t"
if "$PY" - "$t/before.json" "$t/.claude/settings.json" <<'PY'
import json, sys
before = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["PreToolUse"]
after  = json.load(open(sys.argv[2], encoding="utf-8"))["hooks"]["PreToolUse"]
# Index-stable AND deep-equal: the consumer's block is byte-for-byte the same object at the
# same position. An append that reordered, rewrote a matcher or edited the chain fails here.
sys.exit(0 if len(after) >= len(before) and after[:len(before)] == before else 1)
PY
then ok "A5-consumer-block-preserved-deep-equal"
else bad "A5-consumer-block-preserved-deep-equal" "consumer block was dropped, reordered or rewritten"
fi

###############################################################################
# Row A6 — the APPENDED block carries FLOW's matcher, not the consumer's. This is why the
# fix appends a SEPARATE block instead of appending Flow's command into the consumer's chain:
# inheriting `Bash|Edit|Write` would re-open E6 (PowerShell never reaches the handler, so
# FR-06 denies and FR-12 approvals do not apply to it) on every consumer tree.
###############################################################################
if "$PY" - "$t/.claude/settings.json" <<'PY'
import json, sys
blocks = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["PreToolUse"]
flow = [b for b in blocks
        if any("hooks/handlers/pre_tool_use.py" in (h.get("command") or "") for h in b.get("hooks", []))]
if not flow:
    sys.exit(1)
toks = set((flow[0].get("matcher") or "").split("|"))
sys.exit(0 if {"Bash", "PowerShell", "Edit", "Write", "MultiEdit", "NotebookEdit"} <= toks else 1)
PY
then ok "A6-appended-block-carries-full-e6-matcher"
else bad "A6-appended-block-carries-full-e6-matcher" "appended Flow block does not name every command-carrying tool"
fi

###############################################################################
# Row A7 — IDEMPOTENT. A second --wire-hooks on the repaired tree is byte-identical: the
# repair must not append a second Flow block on every run.
###############################################################################
cp "$t/.claude/settings.json" "$t/pass1.json"
run_merge "$t"
if cmp -s "$t/pass1.json" "$t/.claude/settings.json"; then ok "A7-second-merge-byte-identical"; else
  bad "A7-second-merge-byte-identical" "re-running the merge changed the file"; fi

###############################################################################
# Row A8 — MANY consumer blocks: none dropped, order preserved, Flow appended once.
###############################################################################
t="$(newtree)"
"$PY" - "$t/.claude/settings.json" <<'PY'
import json, sys
doc = {"hooks": {"PreToolUse": [
    {"matcher": "Bash",  "hooks": [{"type": "command", "command": "bash ./guard-a.sh"}]},
    {"matcher": "Write", "hooks": [{"type": "command", "command": "bash ./guard-b.sh"}]},
    {"matcher": "Edit",  "hooks": [{"type": "command", "command": "bash ./guard-c.sh"}]}]}}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(doc, indent=2) + "\n")
PY
run_merge "$t"
if "$PY" - "$t/.claude/settings.json" <<'PY'
import json, sys
blocks = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["PreToolUse"]
cmds = [h.get("command", "") for b in blocks for h in b.get("hooks", [])]
consumer = [c for c in cmds if "guard-" in c]
flow = [c for c in cmds if "hooks/handlers/pre_tool_use.py" in c]
sys.exit(0 if consumer == ["bash ./guard-a.sh", "bash ./guard-b.sh", "bash ./guard-c.sh"]
              and len(flow) == 1 else 1)
PY
then ok "A8-multiple-consumer-blocks-order-preserved"
else bad "A8-multiple-consumer-blocks-order-preserved" "a consumer block was dropped/reordered, or Flow was added more than once"
fi

###############################################################################
# Rows B1-B3 — INTENT RECORDS THE ACHIEVED STATE, never the merge's exit code.
###############################################################################
# B1 — rc 0 + handler PRESENT => marker written. (The normal successful path.)
t="$(newtree)"; consumer_only "$t/.claude/settings.json" "PreToolUse"; run_merge "$t"
ffhc_hwi_record_wiring "$t" 0 >/dev/null 2>&1; b1_rc=$?
if [ -f "$t/state/audit/flow-hook-wiring-intent.json" ] && [ "$b1_rc" -eq 0 ]; then
  ok "B1-achieved-wiring-records-intent"
else
  bad "B1-achieved-wiring-records-intent" "rc=$b1_rc marker=$([ -f "$t/state/audit/flow-hook-wiring-intent.json" ] && echo yes || echo no)"
fi

# B2 — rc 0 + handler ABSENT => NO marker. The negative that closes the loop: whatever leaves
# the handler absent, the tree must not record an intent the health arm would then report as
# stripped enforcement while prescribing this same command.
t="$(newtree)"
"$PY" - "$t/.claude/settings.json" <<'PY'
import json, sys
doc = {"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash ./somebody-elses-guard.sh"}]}]}}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(doc, indent=2) + "\n")
PY
ffhc_hwi_record_wiring "$t" 0 >/dev/null 2>&1; b2_rc=$?
if [ ! -f "$t/state/audit/flow-hook-wiring-intent.json" ]; then
  ok "B2-unachieved-wiring-records-nothing"
else
  bad "B2-unachieved-wiring-records-nothing" "intent recorded with $FFHC_HWI_HANDLER absent (rc=$b2_rc)"
fi
# The caller has to be able to TELL, or it cannot warn. A silent no-op here would just move the
# silence one layer out.
if [ "$b2_rc" -ne 0 ]; then ok "B2-unachieved-returns-distinguishable-rc"; else
  bad "B2-unachieved-returns-distinguishable-rc" "returned 0 without recording — the caller cannot warn"; fi

# B3 — merge rc NONZERO => no marker (the pre-existing half of the contract, kept).
t="$(newtree)"; consumer_only "$t/.claude/settings.json" "PreToolUse"; run_merge "$t"
ffhc_hwi_record_wiring "$t" 1 >/dev/null 2>&1
if [ ! -f "$t/state/audit/flow-hook-wiring-intent.json" ]; then ok "B3-failed-merge-records-nothing"; else
  bad "B3-failed-merge-records-nothing" "marker written after a nonzero merge exit"; fi

###############################################################################
# Row C1 — END-TO-END + CONVERGENCE. The real post-fusebase-update.sh --wire-hooks on a
# consumer-only tree, then the real health arm on the result. This is the property that
# actually matters: after ONE --wire-hooks the health check must not report ENFORCEMENT
# STRIPPED on the tree --wire-hooks just succeeded on.
#
# rc is deliberately NOT asserted (the fixture lacks the overlay sources, so the script warns
# and exits 1) — asserting the ACHIEVED state instead of the exit code is this ticket's subject.
###############################################################################
t="$(newtree)"
mkdir -p "$t/hooks/local/fusebase-flow-overlays"
cp "$MERGE" "$t/hooks/local/fusebase-flow-overlays/"
consumer_only "$t/.claude/settings.json" "PreToolUse"
( cd "$t" && bash "$RECOVERY" --wire-hooks >"$t/wire.log" 2>&1 )
if [ "$(handler_count "$t" pre_tool_use)" -ge 1 ]; then ok "C1-e2e-wire-hooks-wires-handler"; else
  bad "C1-e2e-wire-hooks-wires-handler" "handler still absent after a real --wire-hooks run"; fi
if [ -f "$t/state/audit/flow-hook-wiring-intent.json" ]; then ok "C1-e2e-wire-hooks-records-intent"; else
  bad "C1-e2e-wire-hooks-records-intent" "no intent marker after a real --wire-hooks run"; fi
run_arm "$t"
if [ "${#LOCAL_DRIFT[@]}" -eq 0 ] && joined "${LOCAL_OK[@]}" | grep -q "pre_tool_use.py"; then
  ok "C1-convergence-no-stripped-report-after-wire-hooks"
else
  bad "C1-convergence-no-stripped-report-after-wire-hooks" "drift=$(joined "${LOCAL_DRIFT[@]}")"
fi

###############################################################################
# Row C2 — END-TO-END FAIL-CLOSED. A merge that exits 0 without wiring (stubbed) must leave
# NO marker and must WARN. Proves the caller, not just the lib: an unachieved wiring that
# recorded intent is what made the recovery loop non-convergent.
###############################################################################
t="$(newtree)"
mkdir -p "$t/hooks/local/fusebase-flow-overlays"
printf '#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n' > "$t/hooks/local/fusebase-flow-overlays/settings-json-merge.py"
consumer_only "$t/.claude/settings.json" "PreToolUse"
( cd "$t" && bash "$RECOVERY" --wire-hooks >"$t/wire.log" 2>&1 )
if [ ! -f "$t/state/audit/flow-hook-wiring-intent.json" ]; then ok "C2-e2e-unachieved-records-nothing"; else
  bad "C2-e2e-unachieved-records-nothing" "intent recorded although the merge wired nothing"; fi
if grep -qi "NOT recorded\|not wired" "$t/wire.log"; then ok "C2-e2e-unachieved-warns"; else
  bad "C2-e2e-unachieved-warns" "the run said nothing about the unachieved wiring"; fi
# And the summary must not CLAIM a marker it did not write.
if grep -q "recorded Flow hook-wiring intent" "$t/wire.log"; then
  bad "C2-e2e-no-false-claim" "summary claims 'recorded Flow hook-wiring intent' with no marker on disk"
else ok "C2-e2e-no-false-claim"; fi

###############################################################################
# Row D1 — the caller is actually WIRED to the achieved-state verdict. A lib that fails closed
# and a caller that ignores its rc is the same blind spot (the existing hook-wiring-intent
# Row 9 makes the same structural argument).
###############################################################################
if grep -q "ffhc_hwi_record_wiring" "$RECOVERY" \
   && grep -qE 'HWI_RC|ffhc_hwi_record_wiring[^|]*;[[:space:]]*[A-Z_]+=\$\?' "$RECOVERY"; then
  ok "D1-recovery-consumes-record-verdict"
else
  bad "D1-recovery-consumes-record-verdict" "post-fusebase-update.sh does not capture the recorder's rc"
fi

finish
