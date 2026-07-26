#!/usr/bin/env bash
# Fusebase Flow — rule-inventory instrument contract test (S5-pre / AC2).
#
# hooks/local/rule-inventory.sh is the safety instrument the whole S5 compression phase
# leans on: a compressed carrier is accepted only when its inventory diff against the
# committed baseline is EMPTY. An instrument that cannot fail is worthless, so both arms
# are proven here against a throwaway fixture tree (never the live repo):
#
#   RED   — deleting an FR row / a don't-list row / a principle name, rewording a rule
#           STATEMENT, moving a rule resident->lazy, or moving a don't-list row between
#           roles, makes the diff non-empty. The last two are the T14 additions: under
#           the pre-T14 two-column schema both mutations produced a CLEAN diff, which is
#           how the correction round's BLOCKERs reached the gate unseen.
#   GREEN — rewording the Enforcement column, or re-laying-out a principle from heading
#           to table row to bullet, keeps the diff EMPTY. This is what lets T6/T7/T8
#           restructure carriers without the instrument crying wolf.
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: rule-inventory <name>"
# / "FAIL: rule-inventory <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
INV="$ROOT/hooks/local/rule-inventory.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: rule-inventory $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: rule-inventory $1 ($2)"; }
finish() { echo "[test-rule-inventory] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$INV" ] || { bad "setup-instrument-present" "missing $INV"; finish; }
ok "setup-instrument-present"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# mkfix <dir>: a minimal source tree with exactly the three inputs the instrument reads.
mkfix() {
    mkdir -p "$1/flow-skills/role-discipline/references" "$1/flow-skills/communication/references"
    cp "$ROOT/FLOW_RULES.md" "$1/FLOW_RULES.md"
    cp "$ROOT"/flow-skills/role-discipline/references/*.md "$1/flow-skills/role-discipline/references/"
    cp "$ROOT"/flow-skills/communication/references/*.md "$1/flow-skills/communication/references/"
    cp "$ROOT/flow-skills/communication/SKILL.md" "$1/flow-skills/communication/SKILL.md"
    cp "$ROOT/flow-skills/role-discipline/SKILL.md" "$1/flow-skills/role-discipline/SKILL.md"
}
inv() { bash "$INV" --root "$1"; }

# edit <file> <sed -E script>. Pipes are written as [|] — sed -E reads a bare | as alternation.
edit() { sed -E "$2" "$1" > "$1.new" && mv "$1.new" "$1"; }
# col <file> <row-ere> <n> <text>: replace the nth pipe-column of the matching row.
col() {
    awk -F'|' -v OFS='|' -v re="$2" -v n="$3" -v t="$4" \
      '$0 ~ re { $n = " " t " " } { print }' "$1" > "$1.new" && mv "$1.new" "$1"
}

FR_FILE=FLOW_RULES.md
IM_FILE=flow-skills/role-discipline/references/ai-developer.md
DP_FILE=flow-skills/role-discipline/references/deploy.md
RD_FILE=flow-skills/role-discipline/SKILL.md
CM_FILE=flow-skills/communication/SKILL.md

m_drop_fr()        { edit "$1/$FR_FILE" '/^[|] *FR-13 *[|]/d'; }
m_drop_dont()      { edit "$1/$IM_FILE" '/^[|] *IM\.4 *[|]/d'; }
m_drop_principle() { edit "$1/$CM_FILE" '/^#+ *B7\./d; /^[|] *B7 *[|]/d'; }
m_reword_statement()   { col "$1/$FR_FILE" '^[|] *FR-03 *[|]' 4 'a completely different rule statement'; }
m_reword_enforcement() { col "$1/$FR_FILE" '^[|] *FR-03 *[|]' 5 'enforcement reworded: hook renamed, wording rewritten end to end'; }
# The resident layout is free to change (T6 moved headings -> table rows), so each relayout
# mutator flips whichever form it finds. The no-op guard in mutate() is what stops a
# stale mutator from passing vacuously once the layout moves again.
headings_form() { grep -qE '^#+ *B[0-9]+\.' "$1/$CM_FILE"; }
m_principle_relayout() {
    if headings_form "$1"; then edit "$1/$CM_FILE" 's,^#+ *(B[0-9]+)\. (.+)$,| \1 | \2 | see references/mode-b-detail.md |,'
    else edit "$1/$CM_FILE" 's,^\| *(B[0-9]+) *\| *([^|]+)\|.*$,### \1. \2,'; fi
}
m_principle_bullet() {
    if headings_form "$1"; then edit "$1/$CM_FILE" 's,^#+ *(B[0-9]+)\. (.+)$,- **\1** — \2 (detail: references/mode-b-detail.md),'
    else edit "$1/$CM_FILE" 's,^\| *(B[0-9]+) *\| *([^|]+)\|.*$,- **\1** — \2,'; fi
}
# A heading naming the RANGE ("B1–B12 worked examples") is prose, not a definition —
# it must not mint a phantom principle (which would poison the diff forever).
m_range_heading()      { printf '\n## B1-B12 worked examples\n\n## B1–B12 worked examples\n' >> "$1/$CM_FILE"; }

# T14 residency arms. Both mutations keep the rule TEXT alive somewhere in the tree —
# only its home changes, which is exactly what the pre-T14 schema could not see.
# (a) resident -> lazy: OD-3 is carried by BOTH the resident SKILL.md and the lazy
#     shared-protocols.md; deleting only the resident copy must still be RED.
m_move_resident_to_lazy() { edit "$1/$RD_FILE" '/^[|] *OD-3 *[|]/d'; }
# (b) cross-role move: row text and ID unchanged, only the owning role file differs.
m_move_dont_between_roles() {
    grep -E '^[|] *IM\.4 *[|]' "$1/$IM_FILE" >> "$1/$DP_FILE"
    edit "$1/$IM_FILE" '/^[|] *IM\.4 *[|]/d'
}

# mutate <name> <red|green> <mutator-fn>
mutate() {
    local name="$1" expect="$2" fn="$3" d="$TMP/m-$1"
    mkfix "$d"; "$fn" "$d"
    # No-op guard: a mutator that stopped matching (source layout moved on) would make
    # a RED case silently green and a GREEN case prove nothing. Fail loudly instead.
    if diff -r -q "$BASE" "$d" >/dev/null 2>&1; then
        bad "$name" "mutator changed nothing — the case proves nothing"; return
    fi
    inv "$d" > "$TMP/out-$name.txt" 2>/dev/null
    if cmp -s "$TMP/baseline.txt" "$TMP/out-$name.txt"; then
        if [ "$expect" = "green" ]; then ok "$name"
        else bad "$name" "diff EMPTY — the instrument does not catch this rule loss"; fi
    else
        if [ "$expect" = "red" ]; then ok "$name"
        else bad "$name" "diff NON-EMPTY: $(diff "$TMP/baseline.txt" "$TMP/out-$name.txt" | head -2 | tr '\n' ' ')"; fi
    fi
}

BASE="$TMP/base"; mkfix "$BASE"
inv "$BASE" > "$TMP/baseline.txt" 2>"$TMP/baseline.err"
if [ -s "$TMP/baseline.txt" ]; then ok "baseline-produced"
else bad "baseline-produced" "empty inventory: $(head -1 "$TMP/baseline.err")"; finish; fi

# --- structural coverage: every rule family is actually inventoried ------------------
missing=""
for n in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27; do
    grep -q "^FR-$n	" "$TMP/baseline.txt" || missing="$missing FR-$n"
done
[ -z "$missing" ] && ok "covers-fr-01-27" || bad "covers-fr-01-27" "absent:$missing"

missing=""
for p in PO IM AR DP; do
    grep -qE "^$p\.[0-9]+	" "$TMP/baseline.txt" || missing="$missing $p"
done
[ -z "$missing" ] && ok "covers-all-role-dont-lists" || bad "covers-all-role-dont-lists" "absent:$missing"

missing=""
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
    grep -q "^B$n	" "$TMP/baseline.txt" || missing="$missing B$n"
done
[ -z "$missing" ] && ok "covers-b1-b12" || bad "covers-b1-b12" "absent:$missing"

# --- schema: 4 columns; residency is a source-file property (T14 / AC2 amended) ------
if awk -F'\t' 'NF != 4 { bad = 1 } END { exit bad + 0 }' "$TMP/baseline.txt"; then
    ok "schema-four-columns"
else bad "schema-four-columns" "a row is not <id>TAB<text>TAB<path>TAB<residency>"; fi

if awk -F'\t' '$4 != "resident" && $4 != "lazy" { bad = 1 } END { exit bad + 0 }' "$TMP/baseline.txt"; then
    ok "schema-residency-values"
else bad "schema-residency-values" "residency column is not resident|lazy"; fi

# Both residencies must be populated: an all-resident inventory makes the resident->lazy
# arm untestable; an all-lazy one means the parser lost the resident carriers.
for want in resident lazy; do
    awk -F'\t' -v w="$want" '$4 == w { n++ } END { exit (n > 0) ? 0 : 1 }' "$TMP/baseline.txt" \
      && ok "schema-has-$want-rows" || bad "schema-has-$want-rows" "no $want rows"
done

# Every path column must be repo-relative: an absolute checkout path would make the
# baseline machine-specific and every diff permanently non-empty.
if awk -F'\t' '$3 ~ /^([A-Za-z]:)?\// { bad = 1 } END { exit bad + 0 }' "$TMP/baseline.txt"; then
    ok "schema-relative-paths"
else bad "schema-relative-paths" "an absolute source path leaked into the inventory"; fi

missing=""
for cat in "WT\." "PROT\." "OD-" "FAIL\." "REF\." "QS\." "FC\." "MODE\." "ROLE\." "BOOT\."; do
    grep -qE "^$cat" "$TMP/baseline.txt" || missing="$missing $cat"
done
[ -z "$missing" ] && ok "covers-amended-categories" || bad "covers-amended-categories" "absent:$missing"

inv "$BASE" > "$TMP/rerun.txt"
cmp -s "$TMP/baseline.txt" "$TMP/rerun.txt" && ok "deterministic-rerun" \
  || bad "deterministic-rerun" "two runs on an unchanged tree differ"

# --- RED arms (each MUST make the diff non-empty) ------------------------------------
mutate drop-fr-row        red   m_drop_fr
mutate drop-dont-row      red   m_drop_dont
mutate drop-principle     red   m_drop_principle
mutate reword-statement   red   m_reword_statement
mutate move-resident-to-lazy   red m_move_resident_to_lazy
mutate move-dont-between-roles red m_move_dont_between_roles
# --- GREEN arms (each MUST keep the diff empty) --------------------------------------
mutate reword-enforcement green m_reword_enforcement
mutate principle-relayout   green m_principle_relayout
mutate principle-as-bullet green m_principle_bullet
mutate range-heading-ignored green m_range_heading

# --- fail-closed: an unreadable/empty source must never look like "nothing lost" -----
D="$TMP/fc-nofr"; mkfix "$D"; edit "$D/$FR_FILE" '/^[|] *FR-[0-9]+ *[|]/d'
fc_out="$(inv "$D" 2>/dev/null)"; fc_rc=$?
if [ "$fc_rc" -ne 0 ] && [ -z "$fc_out" ]; then ok "fail-closed-zero-fr-rows"
else bad "fail-closed-zero-fr-rows" "rc=$fc_rc, stdout $( [ -z "$fc_out" ] && echo empty || echo non-empty)"; fi

mkdir -p "$TMP/fc-empty"
inv "$TMP/fc-empty" >/dev/null 2>&1 && bad "fail-closed-missing-sources" "rc=0 on a tree with no rule files" \
  || ok "fail-closed-missing-sources"

bash "$INV" --bogus-flag >/dev/null 2>&1; [ $? -eq 2 ] && ok "rejects-unknown-arg" \
  || bad "rejects-unknown-arg" "unknown flag did not exit 2"

finish
