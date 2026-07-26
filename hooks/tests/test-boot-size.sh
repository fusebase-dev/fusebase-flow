#!/usr/bin/env bash
# Fusebase Flow — boot-floor size + boot-contract gate (token-floor-remediation AC1/AC3-AC5).
#
# Guards the role-aware session-boot floor: the bytes every session pays before any work
# starts. Three arms, all deterministic (bytes / grep — never judgment):
#   1. per-artifact ceilings   — one oversized artifact can't hide inside a passing total
#   2. total ceiling           — the sum can't creep past the budget via many small growths
#   3. boot contract           — YAML frontmatter at byte 1 + the anti-reread rule present
#                                in BOTH mandatory skills, and every required lazy
#                                references/*.md exists (preflight mirrors only what
#                                exists, so a deleted reference looks clean to it)
#   4. body-eager claim        — no surface carrier may assert a mandatory skill BODY is
#                                already in context (AC11 / A5 amended): descriptions are
#                                injected, bodies are not. A false eager claim makes a
#                                mandatory skill silently never load.
#
# Ceilings are decisions.md A2 (token-floor-remediation), amended 3x (T7, T13, T22/T23).
# Changing one is a decision amendment, never a test edit.
#
# Usage:
#   bash hooks/tests/test-boot-size.sh                 # report scenarios against this repo
#   bash hooks/tests/test-boot-size.sh --check ROOT    # silent; exit = failure count (fixtures)
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: boot-size <name>"
# / "FAIL: boot-size <name>"; exit code = number of failures.

set -uo pipefail

# --- ceilings (decisions.md A2 — 3rd amendment 2026-07-26, correction round T22/T23) --
# Residency outranks the budget: a prohibition is NEVER moved to a lazy reference to fit
# a ceiling. If every prohibition cannot be held resident under these numbers, the answer
# is BLOCKED-AT-budget + a decision amendment — never a rule demotion.
CEIL_COMMUNICATION=7000
CEIL_ROLE_DISCIPLINE=14500
CEIL_FLOW_RULES=11500
CEIL_ROLE_REFERENCE=9200
CEIL_TOTAL=42200

COMM_SKILL="flow-skills/communication/SKILL.md"
ROLE_SKILL="flow-skills/role-discipline/SKILL.md"
RULES_FILE="FLOW_RULES.md"
# Role references are the per-role don't-list files ONLY. shared-protocols.md is a lazy
# body file, never resident, so it is deliberately outside the role-reference ceiling.
ROLE_REFS=(product-owner ai-developer architect deploy)
REQUIRED_REFS=(
    "flow-skills/role-discipline/references/shared-protocols.md"
    "flow-skills/role-discipline/references/product-owner.md"
    "flow-skills/role-discipline/references/ai-developer.md"
    "flow-skills/role-discipline/references/architect.md"
    "flow-skills/role-discipline/references/deploy.md"
    "flow-skills/communication/references/mode-b-detail.md"
    "flow-skills/communication/references/patterns.md"
)
ANTI_REREAD="Do not re-Read this file if it is already in your context"

# Surface carriers that tell an agent what is/isn't in its context at session start.
# AC11 (A5 amended, T15): descriptions/metadata are injected, bodies are NOT — on every
# surface. A row claiming eager BODY loading suppresses a mandatory read.
SURFACE_CARRIERS=(
    "AGENTS.md"
    "CLAUDE.md"
    "hooks/local/fusebase-flow-overlays/agents-md-overlay.md"
    "hooks/local/fusebase-flow-overlays/claude-md-overlay.md"
    ".codex/config.toml.example"
    "GEMINI.md"
    ".github/copilot-instructions.md"
    ".cursor/rules/fusebase-flow-always.mdc"
    "$COMM_SKILL"
    "$ROLE_SKILL"
)

bytes() { [ -f "$1" ] && wc -c < "$1" | tr -d ' \r' || echo 0; }

# body_eager_hits FILE -> "<file>:<lineno>: <verdict>" per offending line.
# Three claim shapes, matched semantically (not by a phrase blacklist):
#   A  a bare presence assertion ("already in context") with no body-presence condition
#   B  an auto-load/auto-inject verb applied to a body noun with no negator before it
#   C  a "do not Read" instruction with no body-presence condition attached
# COND is the only escape hatch: the instruction must be conditioned on whether the exact
# body is present. A surface NAME is never a valid condition — that is the T15 defect.
body_eager_hits() {
    awk -v f="$1" '
    function cond(s) { return (s ~ /unless|if it is not|if the exact|not already|is not present|not in (your )?context|body-presence|body not in context/) }
    {
        low = tolower($0)
        gsub(/\*|`|_/, "", low)                      # markdown emphasis is not semantics
        noun = (low ~ /bod(y|ies)|skill\.md|both files|either file|those files|these files|mandatory skills?/)
        # Scoped to skill BODIES: "spec.md is already in context" is a true statement
        # about an artifact, not a boot-load claim.
        if (noun && low ~ /already (present )?in (your )?context/ && !cond(low))
            print f ":" NR ": bare presence assertion"
        if (noun && match(low, /auto-?(load|inject)[a-z]*/)) {
            pre = substr(low, 1, RSTART - 1)
            if (pre !~ /(no surface|nothing|never|not|no)[^a-z]*$/ && !cond(low))
                print f ":" NR ": unnegated auto-load claim over a skill body"
        }
        if (low ~ /do +not +(re-?)?read/ && !cond(low))
            print f ":" NR ": unconditional do-not-Read instruction"
    }' "$1"
}

# largest_role_ref ROOT -> "<bytes> <name>"; 0 when none are readable.
largest_role_ref() {
    local root="$1" max=0 who="(none)" n b
    for n in "${ROLE_REFS[@]}"; do
        b="$(bytes "$root/flow-skills/role-discipline/references/$n.md")"
        [ "$b" -gt "$max" ] && { max="$b"; who="$n"; }
    done
    echo "$max $who"
}

# check_root ROOT: emit one "<name>|<ok|bad>|<detail>" line per assertion on stdout.
# Pure function of the tree — the reporting mode and the RED fixtures share it, so a
# fixture can never pass through a different code path than the live check.
check_root() {
    local root="$1" v r lr lrb lrname total=0
    for pair in "communication:$COMM_SKILL:$CEIL_COMMUNICATION" \
                "role-discipline:$ROLE_SKILL:$CEIL_ROLE_DISCIPLINE" \
                "flow-rules:$RULES_FILE:$CEIL_FLOW_RULES"; do
        IFS=':' read -r name path ceil <<< "$pair"
        v="$(bytes "$root/$path")"
        total=$((total + v))
        if [ "$v" -eq 0 ]; then
            echo "ceiling-$name|bad|missing $path"
        elif [ "$v" -le "$ceil" ]; then
            echo "ceiling-$name|ok|$v <= $ceil"
        else
            echo "ceiling-$name|bad|$path is $v bytes, ceiling $ceil"
        fi
    done

    lr="$(largest_role_ref "$root")"; lrb="${lr%% *}"; lrname="${lr##* }"
    total=$((total + lrb))
    if [ "$lrb" -eq 0 ]; then
        echo "ceiling-role-reference|bad|no role reference file readable"
    elif [ "$lrb" -le "$CEIL_ROLE_REFERENCE" ]; then
        echo "ceiling-role-reference|ok|$lrname $lrb <= $CEIL_ROLE_REFERENCE"
    else
        echo "ceiling-role-reference|bad|$lrname is $lrb bytes, ceiling $CEIL_ROLE_REFERENCE"
    fi

    if [ "$total" -le "$CEIL_TOTAL" ]; then
        echo "total-boot-floor|ok|$total <= $CEIL_TOTAL"
    else
        echo "total-boot-floor|bad|role-aware boot floor is $total bytes, ceiling $CEIL_TOTAL"
    fi

    # TRIPWIRE: preflight.sh anchors "---" at byte 1 of every SKILL.md; the T3 anti-reread
    # line must sit BELOW the frontmatter, never above it.
    for pair in "communication:$COMM_SKILL" "role-discipline:$ROLE_SKILL"; do
        IFS=':' read -r name path <<< "$pair"
        if [ "$(head -c 3 "$root/$path" 2>/dev/null)" = "---" ]; then
            echo "frontmatter-first-$name|ok|--- at byte 1"
        else
            echo "frontmatter-first-$name|bad|$path does not open with YAML frontmatter"
        fi
        if grep -qF "$ANTI_REREAD" "$root/$path" 2>/dev/null; then
            echo "anti-reread-$name|ok|rule present"
        else
            echo "anti-reread-$name|bad|$path lost the anti-reread rule"
        fi
    done

    r=0
    for f in "${REQUIRED_REFS[@]}"; do
        [ -f "$root/$f" ] || { echo "required-references|bad|missing $f"; r=1; break; }
    done
    [ "$r" -eq 0 ] && echo "required-references|ok|${#REQUIRED_REFS[@]} present"

    local hits="" n=0
    for f in "${SURFACE_CARRIERS[@]}"; do
        [ -f "$root/$f" ] || { echo "body-eager-claim|bad|surface carrier missing: $f"; return 0; }
        hits="$(body_eager_hits "$root/$f")"
        if [ -n "$hits" ]; then
            echo "body-eager-claim|bad|$f: $(printf '%s' "$hits" | head -1 | cut -d: -f2-)"
            return 0
        fi
        n=$((n + 1))
    done
    echo "body-eager-claim|ok|$n surface carriers claim descriptions only"
}

# --- --check MODE: silent; exit code = number of bad assertions (fixture driver) -----
if [ "${1:-}" = "--check" ]; then
    [ -n "${2:-}" ] || { echo "[test-boot-size] --check needs a ROOT" >&2; exit 2; }
    exit "$(check_root "$2" | grep -c '|bad|')"
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SELF="$ROOT/hooks/tests/test-boot-size.sh"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: boot-size $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: boot-size $1 ($2)"; }
finish() { echo "[test-boot-size] $pass/$((pass + fail)) PASS"; exit $fail; }

# --- GREEN: the live tree satisfies every assertion ---------------------------------
while IFS='|' read -r name verdict detail; do
    [ -n "$name" ] || continue
    [ "$verdict" = "ok" ] && ok "$name" || bad "$name" "$detail"
done < <(check_root "$ROOT")

# --- RED: every arm must actually bite on a mutated copy ----------------------------
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t bootsize)"
cleanup() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; }
trap cleanup EXIT

# fixture NAME -> builds $TMP/NAME as a pristine copy of the four measured artifacts
# plus every required reference (empty stand-ins: only existence and the two greps
# are checked on references, never their size).
fixture() {
    local d="$TMP/$1"
    rm -rf "$d"; mkdir -p "$d/flow-skills/communication/references" \
                          "$d/flow-skills/role-discipline/references"
    cp "$ROOT/$COMM_SKILL"  "$d/$COMM_SKILL"
    cp "$ROOT/$ROLE_SKILL"  "$d/$ROLE_SKILL"
    cp "$ROOT/$RULES_FILE"  "$d/$RULES_FILE"
    local n
    for n in "${ROLE_REFS[@]}"; do
        cp "$ROOT/flow-skills/role-discipline/references/$n.md" \
           "$d/flow-skills/role-discipline/references/$n.md"
    done
    local f
    for f in "${REQUIRED_REFS[@]}"; do [ -f "$d/$f" ] || : > "$d/$f"; done
    for f in "${SURFACE_CARRIERS[@]}"; do
        mkdir -p "$d/$(dirname "$f")"; cp "$ROOT/$f" "$d/$f"
    done
    echo "$d"
}

# red <scenario> <mutate-fn> <row-that-must-go-bad>: a non-zero exit alone would only
# prove SOMETHING failed; asserting the named row proves THAT arm is what bit.
red() {
    local d out; d="$(fixture "$1")"
    "$2" "$d"
    out="$(check_root "$d")"
    if printf '%s\n' "$out" | grep -qF "$3|bad|"; then
        ok "red-$1"
    else
        bad "red-$1" "row '$3' did not go bad — that arm does not bite"
    fi
}

# A pristine fixture must be GREEN, else every red-* below proves nothing.
d="$(fixture baseline)"
bash "$SELF" --check "$d" >/dev/null 2>&1 \
    && ok "red-fixture-baseline-green" \
    || bad "red-fixture-baseline-green" "unmutated fixture already fails — red arms are vacuous"

grow_comm()  { head -c 7000 /dev/zero | tr '\0' 'x' >> "$1/$COMM_SKILL"; }
grow_role()  { head -c 12000 /dev/zero | tr '\0' 'x' >> "$1/$ROLE_SKILL"; }
grow_rules() { head -c 12000 /dev/zero | tr '\0' 'x' >> "$1/$RULES_FILE"; }
grow_ref()   { head -c 10000 /dev/zero | tr '\0' 'x' \
                 >> "$1/flow-skills/role-discipline/references/ai-developer.md"; }
strip_frontmatter() { printf 'no frontmatter\n' | cat - "$1/$ROLE_SKILL" > "$1/tmp" \
                        && mv "$1/tmp" "$1/$ROLE_SKILL"; }
strip_antireread()  { grep -vF "$ANTI_REREAD" "$1/$COMM_SKILL" > "$1/tmp" \
                        && mv "$1/tmp" "$1/$COMM_SKILL"; }
drop_reference()    { rm -f "$1/flow-skills/role-discipline/references/shared-protocols.md"; }
# The verbatim pre-T15 claim: it is what shipped, and it is what must never ship again.
plant_body_claim()  { printf 'Because Claude Code auto-injects both bodies, do not Read either file again.\n' \
                        >> "$1/CLAUDE.md"; }

red "ceiling-communication"      grow_comm           "ceiling-communication"
red "ceiling-role-discipline"    grow_role           "ceiling-role-discipline"
red "ceiling-flow-rules"         grow_rules          "ceiling-flow-rules"
red "ceiling-role-reference"     grow_ref            "ceiling-role-reference"
red "total-boot-floor"           grow_comm           "total-boot-floor"
red "frontmatter-first"          strip_frontmatter   "frontmatter-first-role-discipline"
red "anti-reread"                strip_antireread    "anti-reread-communication"
red "missing-required-reference" drop_reference      "required-references"
red "body-eager-claim"           plant_body_claim    "body-eager-claim"

# The four per-artifact ceilings sum to EXACTLY the total, so the total arm can never
# fire on its own — it is a backstop, and this invariant is what makes it non-vacuous.
# A future ceiling amendment that forgets to move the total lands here, not in prod.
sum=$((CEIL_COMMUNICATION + CEIL_ROLE_DISCIPLINE + CEIL_FLOW_RULES + CEIL_ROLE_REFERENCE))
[ "$sum" -eq "$CEIL_TOTAL" ] \
    && ok "ceilings-sum-to-total" \
    || bad "ceilings-sum-to-total" "per-artifact ceilings sum to $sum, total ceiling is $CEIL_TOTAL"

finish
