#!/usr/bin/env bash
# Fusebase Flow — cross-artifact boot-floor budget literal consistency (AC1 amended / T18).
#
# MAJOR 9: the A2 2nd amendment HALF-LANDED — the enforcing test moved to the new ceilings
# while several prose carriers still stated the superseded ones, and nothing noticed. This
# test makes the CEIL_* literals in test-boot-size.sh the single source of truth and fails
# when a live carrier states a boot-floor ceiling/budget that is not one of them.
#
# Carriers are DISCOVERED by content, never enumerated in a list — so a carrier introduced
# by the NEXT amendment is covered the day it lands, which is the property that makes a
# half-landed amendment impossible rather than merely unlikely.
#
# Two deliberate exclusions, both "dated record, not live carrier": generated/dated history
# (CHANGELOG, FLOW_RULES_HISTORY, release-notes, docs/changes, docs/tmp, compatibility) and
# gate/deploy reports (they record what a run MEASURED against the ceiling of that day).
# A stale live line may also opt out by carrying an explicit supersession marker — the
# escape hatch is annotation, never silence.
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: budget-literals <name>"
# / "FAIL: budget-literals <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 1
BOOT_TEST="hooks/tests/test-boot-size.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: budget-literals $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: budget-literals $1 ($2)"; }
# TRIPWIRE (incident E7, 2026-08-21) — platform/data-loss: never name this TMP/TEMP/TMPDIR.
# On Windows those are PRE-SET env vars holding the operator's profile temp dir, and the two
# `finish` calls below (missing boot-test, no CEIL_* parsed) run BEFORE the mkdtemp assignment —
# a non-empty check would pass and recursively delete the operator's entire %TEMP%.
BL_TMP=""
bl_cleanup() { case "$BL_TMP" in "${TMPDIR:-/tmp}"/ffhc-budgetlit.*) rm -rf -- "$BL_TMP" ;; esac; }
finish() { bl_cleanup; echo "[test-budget-literals] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$BOOT_TEST" ] || { bad "setup-boot-test-present" "missing $BOOT_TEST"; finish; }

# Source of truth: every ceiling the boot-size gate actually ENFORCES.
mapfile -t ENFORCED < <(grep -E '^CEIL_[A-Z_]+=[0-9]+$' "$BOOT_TEST" | cut -d= -f2 | sort -u)
if [ "${#ENFORCED[@]}" -ge 2 ]; then
    ok "enforced-ceilings-read (${#ENFORCED[@]} distinct CEIL_* literals)"
else
    bad "enforced-ceilings-read" "no CEIL_* literals parsed from $BOOT_TEST"; finish
fi
TOTAL_RAW="$(grep -E '^CEIL_TOTAL=[0-9]+$' "$BOOT_TEST" | cut -d= -f2)"
TOTAL_PRETTY="$(printf '%s' "$TOTAL_RAW" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')"

is_enforced() { local n="$1" e; for e in "${ENFORCED[@]}"; do [ "$n" = "$e" ] && return 0; done; return 1; }

CONTEXT_RE='boot[ -]floor|Boot-floor|boot[ -]size|role-aware|byte budget|per-artifact ceiling|amendment ceiling|2nd-amendment'
HIST_RE='supersede|superseded|since raised|1st-amendment|pre-correction|historical|records the pre-'
# A stated CEILING: "≤N,NNN", "N,NNN budget", "budget/ceiling … N,NNN". Bare measurements
# (36,699 measured, 78,148 floor) are NOT ceilings and must not be swept in.
CEIL_RE='(≤|<=)[[:space:]]*[0-9]{1,3},?[0-9]{3}|[0-9]{1,3},[0-9]{3}[- ](byte )?(budget|ceiling)|(budget|ceiling)[^0-9]{0,12}[0-9]{1,3},[0-9]{3}'

carrier_files() { # carrier_files <dir>
    find "$1" \( -type d \( -name '.git' -o -name 'node_modules' -o -name '.fusebase-flow-source' \
            -o -name 'state' -o -name 'internal' -o -name 'release-notes' -o -name 'tmp' \
            -o -name 'changes' \) -prune \) -o \
        \( -type f \( -name '*.md' -o -name '*.mdc' -o -name '*.sh' \) \
             ! -name 'CHANGELOG.md' ! -name 'FLOW_RULES_HISTORY.md' ! -name 'compatibility.md' \
             ! -name 'gate-report.md' ! -name 'deploy-report.md' -print \)
}

scan() { # scan <dir> -> one "path:line: literal" per divergence
    local dir="$1" hit path rest lineno text n
    while IFS= read -r hit; do
        path="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"; text="${rest#*:}"
        printf '%s' "$text" | grep -qE "$HIST_RE" && continue
        for n in $(printf '%s' "$text" | grep -oE "$CEIL_RE" | grep -oE '[0-9][0-9,]*' | tr -d ','); do
            is_enforced "$n" || printf '%s:%s: %s\n' "${path#./}" "$lineno" "$n"
        done
    done < <(carrier_files "$dir" | xargs grep -nHE "$CONTEXT_RE" 2>/dev/null)
}

DIVERGENT="$(scan .)"
if [ -z "$DIVERGENT" ]; then
    ok "no-divergent-budget-literal (enforced: ${ENFORCED[*]})"
else
    bad "no-divergent-budget-literal" "carrier(s) state a ceiling the boot-size gate does not enforce: $(printf '%s' "$DIVERGENT" | tr '\n' ' ')"
fi

# The enforced total must be VISIBLE to a reader, not only to the gate — a silent budget
# is how the previous amendment went stale in prose while the test stayed green.
STATERS="$(carrier_files . | xargs grep -lF "$TOTAL_PRETTY" 2>/dev/null | wc -l)"
[ "$STATERS" -ge 2 ] \
    && ok "enforced-total-stated-in-prose ($STATERS carrier(s) say $TOTAL_PRETTY)" \
    || bad "enforced-total-stated-in-prose" "only $STATERS carrier(s) state $TOTAL_PRETTY"

# --- red/green controls: the scan must FIRE, and must not fire indiscriminately ---------
BL_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-budgetlit.XXXXXX")" || { bad "setup-tmpdir" "mktemp -d failed"; finish; }
mkdir -p "$BL_TMP/red" "$BL_TMP/green" "$BL_TMP/annotated"
# TRIPWIRE: the stale fixture literal is interpolated, never spelled inline next to a
# context keyword — spelling it out would make this file its own first violation.
STALE_LIT="36,800"
printf 'The role-aware boot floor budget is ≤%s bytes.\n' "$STALE_LIT"    > "$BL_TMP/red/stale.md"
printf 'The role-aware boot floor budget is ≤%s bytes.\n' "$TOTAL_PRETTY" > "$BL_TMP/green/current.md"
printf 'Boot-floor total was ≤%s — since superseded by the A2 2nd amendment.\n' "$STALE_LIT" \
    > "$BL_TMP/annotated/history.md"
printf '%s' "$(scan "$BL_TMP/red")" | grep -q '36800' \
    && ok "red-stale-literal-detected" \
    || bad "red-stale-literal-detected" "planted ≤36,800 carrier was NOT reported — the scan proves nothing"
[ -z "$(scan "$BL_TMP/green")" ] \
    && ok "green-current-literal-accepted" \
    || bad "green-current-literal-accepted" "planted current-total carrier was wrongly reported"
[ -z "$(scan "$BL_TMP/annotated")" ] \
    && ok "annotated-history-exempt" \
    || bad "annotated-history-exempt" "an explicitly superseded line was reported as divergent"

finish
