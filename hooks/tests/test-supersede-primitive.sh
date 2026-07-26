#!/usr/bin/env bash
# Fusebase Flow — supersede write-primitive contract test (S2 / AC14).
#
# FR-18 governs authoritative CONTENT, never the write tool. Four carriers used to
# disagree about that, and token-economy TE-06 asserted the opposite outright
# ("FR-18 supersede rewrites are MANDATED") — the contradiction an agent resolved
# by regenerating unchanged files.
#
#   PRESENT arm — every carrier states both dimensions (Edit default / Write for
#                 structure-mode-ticket or most-sections-changed).
#   ABSENT arm  — the retired contradictory phrasings are gone. This is the arm that
#                 bites: re-adding "supersede rewrites are MANDATED" or "whole-file
#                 replace is mandated" anywhere restores the contradiction while every
#                 PRESENT assertion still passes.
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: supersede-primitive <name>"
# / "FAIL: supersede-primitive <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RULES="$ROOT/FLOW_RULES.md"
ROLE="$ROOT/flow-skills/role-discipline/SKILL.md"
HSKILL="$ROOT/flow-skills/handoff/SKILL.md"
TECON="$ROOT/flow-skills/token-economy/SKILL.md"
TPL="$ROOT/templates/handoff.md"
CMD_H="$ROOT/.claude/commands/handoff.md"
OVL_H="$ROOT/hooks/local/fusebase-flow-overlays/commands/handoff.md"
CMD_T="$ROOT/.claude/commands/token-waste-audit.md"
OVL_T="$ROOT/hooks/local/fusebase-flow-overlays/commands/token-waste-audit.md"
AUDIT="$ROOT/hooks/local/token-waste-audit.py"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: supersede-primitive $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: supersede-primitive $1 ($2)"; }
finish() { echo "[test-supersede-primitive] $pass/$((pass + fail)) PASS"; exit $fail; }

for f in "$RULES" "$ROLE" "$HSKILL" "$TECON" "$TPL" "$CMD_H" "$OVL_H" "$CMD_T" "$OVL_T" "$AUDIT"; do
    [ -f "$f" ] || { bad "setup-inputs-present" "missing $f"; finish; }
done
ok "setup-inputs-present"

has()  { grep -qF "$2" "$1" && ok "$3" || bad "$3" "$4"; }
lacks(){ grep -qF "$2" "$1" && bad "$3" "$4" || ok "$3"; }

# both_dimensions FILE: 0 iff some single line carries the Edit default AND the
# Write-for-structure case. Half the rule on its own is what caused the contradiction.
both_dimensions() {
    grep -F 'targeted `Edit`' "$1" | grep -qF 'full `Write`'
}

# --- PRESENT: both dimensions in each rule carrier ----------------------------------
both_dimensions "$RULES"  && ok "ac14-flow-rules-both-dimensions" \
  || bad "ac14-flow-rules-both-dimensions" "FR-18 row does not carry Edit-default + Write-for-structure on one line"
both_dimensions "$ROLE"   && ok "ac14-role-discipline-both-dimensions" \
  || bad "ac14-role-discipline-both-dimensions" "role-discipline lacks both dimensions on one line"
both_dimensions "$HSKILL" && ok "ac14-handoff-skill-both-dimensions" \
  || bad "ac14-handoff-skill-both-dimensions" "handoff skill lacks both dimensions on one line"
both_dimensions "$TECON"  && ok "ac14-token-economy-both-dimensions" \
  || bad "ac14-token-economy-both-dimensions" "TE-06 lacks both dimensions on one line"
both_dimensions "$TPL"    && ok "ac14-template-both-dimensions" \
  || bad "ac14-template-both-dimensions" "templates/handoff.md lacks both dimensions on one line"

# --- PRESENT: the semantics-not-the-file statement + the named anchor ---------------
has "$RULES" "supersede replaces stale *semantics*, not the file" \
    "ac14-flow-rules-semantics-clause" "FR-18 row lost the semantics-not-the-file clause"
has "$ROLE" "### Write primitive — Edit is the default, Write is for structure changes" \
    "ac14-role-discipline-write-primitive-section" "§ Supersede Convention has no Write primitive subsection"
has "$ROLE" "| FR-18 | Revising an artifact" \
    "ac14-role-discipline-digest-row" "FR-24 write-time digest lost its FR-18 row"
has "$HSKILL" "never *retype the file*" \
    "ac14-handoff-skill-fresh-disambiguated" "handoff skill still leaves \"fresh\" ambiguous"

# --- PRESENT: both command surfaces AND their overlay twins -------------------------
has "$CMD_H" "supersede replaces stale *semantics*, not the file" \
    "ac14-handoff-command" "/handoff command lacks the write-primitive clause"
has "$OVL_H" "supersede replaces stale *semantics*, not the file" \
    "ac14-handoff-overlay-twin" "/handoff overlay twin lacks the clause (twin edited separately?)"
has "$CMD_T" "warranted FR-18 full-\`Write\` supersede" \
    "ac14-audit-command" "/token-waste-audit command still calls a supersede rewrite unconditional"
has "$OVL_T" "warranted FR-18 full-\`Write\` supersede" \
    "ac14-audit-overlay-twin" "/token-waste-audit overlay twin not re-spliced"
cmp -s "$CMD_H" "$OVL_H" && ok "ac21-handoff-twin-byte-identical" \
  || bad "ac21-handoff-twin-byte-identical" "/handoff command and overlay twin differ"
cmp -s "$CMD_T" "$OVL_T" && ok "ac21-audit-twin-byte-identical" \
  || bad "ac21-audit-twin-byte-identical" "/token-waste-audit command and overlay twin differ"

# --- PRESENT: the parser's false-positive header is conditional ---------------------
# TRIPWIRE: FALSE_POSITIVE_HEADER is implicit string concatenation across source
# lines, so grep only ever sees a fragment — match per-fragment, never the joined text.
has "$AUDIT" "a WARRANTED FR-18 full-Write" \
    "ac14-audit-parser-header" "token-waste-audit.py FP header does not qualify the supersede class"
has "$AUDIT" "mandates the replaced semantics, not the rewrite tool" \
    "ac14-audit-parser-primitive-clause" "parser FP header does not say FR-18 mandates semantics, not the tool"

# --- ABSENT arm: the retired contradictory phrasings (this is what bites) -----------
lacks "$TECON" "FR-18 supersede rewrites are MANDATED, not waste" \
    "ac14-te06-contradiction-gone" "TE-06 still asserts FR-18 rewrites are mandatory (the contradiction)"
lacks "$AUDIT" "whole-file replace is mandated" \
    "ac14-audit-contradiction-gone" "parser FP header still says whole-file replace is mandated"
lacks "$TECON" "candidates: FR-18 supersede rewrites" \
    "ac14-te-antipattern-qualified" "token-economy anti-pattern still names unqualified supersede rewrites"

finish
