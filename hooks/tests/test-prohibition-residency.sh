#!/usr/bin/env bash
# Fusebase Flow — prohibition-residency gate (token-floor-remediation AC24 / decisions A3).
#
# A3: prohibitions resident, elaborations lazy. A prohibition parked in a lazy
# references/*.md is only "loaded" by an agent who already remembered it — the exact trap
# the T6/T7 compression re-opened (correction-round BLOCKERs 1-2). Two arms:
#
#   A. LEDGER (exact)     — each enumerated prohibition MUST match in its resident
#                           SKILL.md. Restorations cannot silently regress.
#   B. DRIFT NET (heuristic) — every normative line in a lazy reference of a MANDATORY
#                           skill must share vocabulary with a resident line, else it is
#                           reported as a prohibition with no resident counterpart.
#
# Arm B is a net, not a proof: it catches a NEW prohibition written straight into a lazy
# file (the regression shape), not every possible paraphrase. Arm A is the exact contract.
#
# SCOPE (derived, not hardcoded): lazy references of skills whose SKILL.md declares
# `mandatory_load: true`, minus the per-role don't-lists. Those four ARE resident — the
# attested role must read its own file (SKILL.md § Per-role scoped loading) and the boot
# floor budgets one of them. Non-mandatory skills load SKILL.md and references together,
# so "residency" has no meaning there.
#
# Usage:
#   bash hooks/tests/test-prohibition-residency.sh              # report against this repo
#   bash hooks/tests/test-prohibition-residency.sh --check ROOT # silent; exit = failures
#
# Output contract (parsed by run-tests.sh): "PASS: prohibition-residency <name>" /
# "FAIL: prohibition-residency <name>"; exit code = number of failures.

set -uo pipefail

COMM_SKILL="flow-skills/communication/SKILL.md"
ROLE_SKILL="flow-skills/role-discipline/SKILL.md"

# Resident-by-role: read by the attested role, counted in the boot floor (test-boot-size.sh
# § ceiling-role-reference). Not lazy — excluded from arm B by design, not by convenience.
RESIDENT_BY_ROLE="product-owner.md ai-developer.md architect.md deploy.md"

# --- Arm A ledger: name|resident file|ERE that must match --------------------------
# Every row is a clause that shipped lazy in T6/T7 and was restored at T13, or a
# pre-existing resident prohibition that must never migrate out.
LEDGER=(
    "relay-mandatory|$ROLE_SKILL|MUST\*{0,2} run all 5 steps"
    "relay-no-exceptions|$ROLE_SKILL|no exceptions, no shortcuts"
    "relay-wait|$ROLE_SKILL|silence.*approval"
    "popup-prohibition|$ROLE_SKILL|Never use modal popup"
    "popup-refusal-phrasing|$ROLE_SKILL|Per FR-19, I.ll put the options in chat text"
    "gate-no-terminal|$ROLE_SKILL|Never hand the operator a terminal"
    "gate-self-approval|$ROLE_SKILL|self-approval and forbidden"
    "gate-uncovered-action|$ROLE_SKILL|not presented before.*not covered by it"
    "gate-role-authority|$ROLE_SKILL|routed to the owning role"
    "gate-backstops|$ROLE_SKILL|never weaken or bypass them"
    "gate-deflection-phrasing|$ROLE_SKILL|You don.t run anything"
    "momentum-prohibition|$ROLE_SKILL|Never suggest stopping"
    "momentum-refusal-phrasing|$ROLE_SKILL|deleting wrap-up phrasing per FR-17"
    "supersede-prohibition|$ROLE_SKILL|Never keep old . new in one file"
    "supersede-refusal-phrasing|$ROLE_SKILL|deleting accumulated content per FR-18"
    "operator-dont-list|$ROLE_SKILL|OD-7"
    "operator-not-enforced|$ROLE_SKILL|never enforces or blocks"
    "stop-missing-attestation|$ROLE_SKILL|STOP.*attest before any other action"
    "stop-two-roles|$ROLE_SKILL|re-attest one role"
    "stop-operator-insists|$ROLE_SKILL|accepts the refusal or explicitly amends the rule"
    "escalation-no-bypass|$ROLE_SKILL|never silently bypass"
    "no-on-demand-load|$ROLE_SKILL|Do NOT load this SKILL.md on demand"
    "no-prohibition-demotion|$ROLE_SKILL|Do NOT move a prohibition out of this file"
    "modeb-visuals|$COMM_SKILL|visuals never in Mode-B files"
    "modeb-b3|$COMM_SKILL|never .First X"
    "modeb-b4|$COMM_SKILL|never .the earlier change"
    "modeb-b5|$COMM_SKILL|never paraphrase a heading"
    "modeb-b6|$COMM_SKILL|never .I considered X"
    "modeb-b7|$COMM_SKILL|never .see above"
    "modeb-b8|$COMM_SKILL|never re-explain or restate"
    "modeb-b11|$COMM_SKILL|never switch synonyms"
    "modeb-b12|$COMM_SKILL|never open with"
    "modea-decoration|$COMM_SKILL|never over-decorate"
    "modea-width|$COMM_SKILL|under 80 characters"
)

# lazy_refs ROOT -> paths (relative) of in-scope lazy reference files.
lazy_refs() {
    local root="$1" skill base ref
    for skill in "$root"/flow-skills/*/SKILL.md; do
        [ -f "$skill" ] || continue
        grep -q '^mandatory_load: true' "$skill" || continue
        for ref in "$(dirname "$skill")"/references/*.md; do
            [ -f "$ref" ] || continue
            base="$(basename "$ref")"
            case " $RESIDENT_BY_ROLE " in *" $base "*) continue ;; esac
            echo "${ref#"$root"/}"
        done
    done
}

# uncovered REF SKILL -> one line per normative line with no resident vocabulary anchor.
uncovered() {
    awk -v skillfile="$2" -v f="$1" '
    BEGIN {
        while ((getline l < skillfile) > 0) skill = skill " " tolower(l)
        split("should because therefore however instead another through before already " \
              "cannot itself content section example without between others", sw, " ")
        for (i in sw) STOP[sw[i]] = 1
    }
    {
        if (fence) { if ($0 ~ /^```/) fence = 0; next }   # worked examples are elaboration
        if ($0 ~ /^```/) { fence = 1; next }
        if ($0 ~ /^[[:space:]]*[>❌✅]/) next               # quoted / ❌✅ example lines
        low = tolower($0)
        if (low !~ /must|never|do not|don.t|forbidden|stop|refuse/) next
        n = split(low, w, /[^a-z0-9]+/); need = 0; have = 0
        for (i = 1; i <= n; i++) {
            t = w[i]
            if (length(t) < 6 || (t in STOP)) continue
            need++
            if (index(skill, substr(t, 1, 6)) > 0) have++
        }
        if (need < 2) next   # a one-word cell (e.g. a "Do not use" column header) is not a rule
        # >=2 anchors, or half the salient vocabulary for short clauses.
        if (have >= 2 || have * 2 >= need) next
        printf "%s:%d: normative clause with no resident counterpart (%d/%d anchors)\n", \
               f, NR, have, need
    }' "$1"
}

# check_root ROOT: "<name>|<ok|bad>|<detail>" per assertion. Shared by live + fixtures.
check_root() {
    local root="$1" name file pat entry ref skill hits n=0 bad=0
    for entry in "${LEDGER[@]}"; do
        IFS='|' read -r name file pat <<< "$entry"
        if grep -qE "$pat" "$root/$file" 2>/dev/null; then
            echo "ledger-$name|ok|resident in $(basename "$(dirname "$file")")"
        else
            echo "ledger-$name|bad|missing from $file — prohibition is not resident"
        fi
    done

    while read -r ref; do
        [ -n "$ref" ] || continue
        skill="$root/$(dirname "$(dirname "$ref")")/SKILL.md"
        hits="$(uncovered "$root/$ref" "$skill")"
        if [ -n "$hits" ]; then
            echo "lazy-normative-$(basename "$ref")|bad|$(printf '%s' "$hits" | head -1)"
            bad=1
        fi
        n=$((n + 1))
    done < <(lazy_refs "$root")
    [ "$n" -eq 0 ] && echo "lazy-scope|bad|no mandatory-skill lazy reference found" \
                   || echo "lazy-scope|ok|$n lazy reference(s) scanned"
    [ "$bad" -eq 0 ] && echo "lazy-normative-clean|ok|no orphaned prohibition"
}

if [ "${1:-}" = "--check" ]; then
    [ -n "${2:-}" ] || { echo "[test-prohibition-residency] --check needs a ROOT" >&2; exit 2; }
    exit "$(check_root "$2" | grep -c '|bad|')"
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: prohibition-residency $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: prohibition-residency $1 ($2)"; }

while IFS='|' read -r name verdict detail; do
    [ -n "$name" ] || continue
    [ "$verdict" = "ok" ] && ok "$name" || bad "$name" "$detail"
done < <(check_root "$ROOT")

# --- RED: both arms must bite on a mutated copy -------------------------------------
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t prohres)"
trap '[ -n "${TMP:-}" ] && rm -rf "$TMP"' EXIT

fixture() {
    local d="$TMP/$1"
    rm -rf "$d"
    mkdir -p "$d/flow-skills/communication/references" "$d/flow-skills/role-discipline/references"
    cp "$ROOT/$COMM_SKILL" "$d/$COMM_SKILL"
    cp "$ROOT/$ROLE_SKILL" "$d/$ROLE_SKILL"
    local ref
    while read -r ref; do [ -n "$ref" ] && cp "$ROOT/$ref" "$d/$ref"; done < <(lazy_refs "$ROOT")
    echo "$d"
}

red() {
    local d out; d="$(fixture "$1")"
    "$2" "$d"
    out="$(check_root "$d")"
    printf '%s\n' "$out" | grep -qF "$3|bad|" \
        && ok "red-$1" \
        || bad "red-$1" "row '$3' did not go bad — that arm does not bite"
}

d="$(fixture baseline)"
[ "$(check_root "$d" | grep -c '|bad|')" -eq 0 ] \
    && ok "red-fixture-baseline-green" \
    || bad "red-fixture-baseline-green" "unmutated fixture already fails — red arms are vacuous"

# Arm B: a brand-new prohibition written straight into a lazy file (the regression shape).
plant_lazy_prohibition() {
    printf '\nNever reconfigure the quarantine partition without a witness manifest.\n' \
        >> "$1/flow-skills/role-discipline/references/shared-protocols.md"
}
# Arm A: a restored prohibition demoted back out of the resident file.
demote_prohibition() {
    grep -v "Never hand the operator a terminal" "$1/$ROLE_SKILL" > "$1/x" && mv "$1/x" "$1/$ROLE_SKILL"
}

red "planted-lazy-prohibition" plant_lazy_prohibition "lazy-normative-shared-protocols.md"
red "demoted-prohibition"      demote_prohibition     "ledger-gate-no-terminal"

echo "[test-prohibition-residency] $pass/$((pass + fail)) PASS"
exit $fail
