#!/usr/bin/env bash
# Fusebase Flow — AC6 (amended, MINOR 14): the extracted amendment log is content-equivalent
# to the pre-extraction `FLOW_RULES.md` section EXCEPT a normalized final newline.
#
# The original claim was "byte-preserved", which was false: the source section ended without
# a trailing LF and the extracted file adds one. The amended contract is exact and testable —
# old payload + exactly one normalizing final LF == new payload, byte for byte. Anything
# else (a dropped entry, a reflowed line, an edited date) fails.
#
# The pre-extraction blob is resolved from git history DYNAMICALLY (the commit that ADDED
# FLOW_RULES_HISTORY.md, then its parent), never from a pinned SHA — a rebase or a graft
# must not silently turn this into a no-op.
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: history-extraction <name>"
# / "FAIL: history-extraction <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 1
HIST="FLOW_RULES_HISTORY.md"
RULES="FLOW_RULES.md"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: history-extraction $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: history-extraction $1 ($2)"; }
# TRIPWIRE (incident E7, 2026-08-21) — platform/data-loss: never name this TMP/TEMP/TMPDIR.
# On Windows those are PRE-SET env vars holding the operator's profile temp dir, and the four
# `finish` calls below (missing-input x2, extraction-commit-resolved x2) run BEFORE the mkdtemp
# assignment — a non-empty check passed and deleted the operator's whole %TEMP% on a shallow clone.
HX_TMP=""
hx_cleanup() { case "$HX_TMP" in "${TMPDIR:-/tmp}"/ffhc-histext.*) rm -rf -- "$HX_TMP" ;; esac; }
finish() { hx_cleanup; echo "[test-history-extraction] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$HIST" ]  || { bad "setup-history-present" "missing $HIST"; finish; }
[ -f "$RULES" ] || { bad "setup-rules-present" "missing $RULES"; finish; }
ok "setup-inputs-present"

# A4: the heading stays as a compatibility stub (sweep anchor + ~9 read-stop references),
# and the dated entries must be gone from the live file.
STUB="$(sed -n '/^## Amendment log/,$p' "$RULES")"
printf '%s' "$STUB" | grep -qE '^## Amendment log' \
    && ok "stub-heading-retained" || bad "stub-heading-retained" "no '## Amendment log' heading in $RULES"
printf '%s' "$STUB" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' \
    && bad "stub-carries-no-dated-entries" "dated log entries still inline in $RULES" \
    || ok "stub-carries-no-dated-entries"

ADD_SHA="$(git log --diff-filter=A --format=%H -- "$HIST" 2>/dev/null | tail -1)"
[ -n "$ADD_SHA" ] || { bad "extraction-commit-resolved" "cannot find the commit that added $HIST"; finish; }
git cat-file -e "$ADD_SHA^:$RULES" 2>/dev/null \
    || { bad "extraction-commit-resolved" "pre-extraction $RULES unreachable at $ADD_SHA^"; finish; }
ok "extraction-commit-resolved (${ADD_SHA:0:7})"

HX_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-histext.XXXXXX")" || { bad "setup-tmpdir" "mktemp -d failed"; finish; }
# The payload is the fenced log block; the surrounding prose banner is deliberately NEW
# (it points back at the live file), so equivalence is asserted on the payload, not the file.
git show "$ADD_SHA^:$RULES" | sed -n '/^## Amendment log/,$p' | sed -n '/^```$/,$p' > "$HX_TMP/old.raw"
sed -n '/^```$/,$p' "$HIST" > "$HX_TMP/new.raw"
[ -s "$HX_TMP/old.raw" ] && [ -s "$HX_TMP/new.raw" ] \
    && ok "payloads-extracted" || { bad "payloads-extracted" "one side extracted empty"; finish; }

# THE amended contract: old payload with trailing newlines normalized to exactly one == new.
printf '%s\n' "$(cat "$HX_TMP/old.raw")" > "$HX_TMP/old.norm"
cmp -s "$HX_TMP/old.norm" "$HX_TMP/new.raw" \
    && ok "content-equivalent-modulo-final-newline" \
    || bad "content-equivalent-modulo-final-newline" \
           "$(diff "$HX_TMP/old.norm" "$HX_TMP/new.raw" | head -3 | tr '\n' ' ')"

# ...and the normalization is the ONLY difference: raw sizes differ by at most one byte.
OLD_B="$(wc -c < "$HX_TMP/old.raw")"; NEW_B="$(wc -c < "$HX_TMP/new.raw")"
DELTA=$((NEW_B - OLD_B))
[ "$DELTA" -ge 0 ] && [ "$DELTA" -le 1 ] \
    && ok "only-difference-is-the-final-newline (raw delta ${DELTA}B)" \
    || bad "only-difference-is-the-final-newline" "raw payload delta is ${DELTA}B, not 0 or 1"

# --- red controls: the comparison must FAIL on any real content change ------------------
sed '$d' "$HX_TMP/new.raw" > "$HX_TMP/truncated.raw"
cmp -s "$HX_TMP/old.norm" "$HX_TMP/truncated.raw" \
    && bad "red-truncated-payload-detected" "a truncated payload still compared equal" \
    || ok "red-truncated-payload-detected"
sed '1,/^2026-/s/^2026-/2027-/' "$HX_TMP/new.raw" > "$HX_TMP/edited.raw"
if cmp -s "$HX_TMP/new.raw" "$HX_TMP/edited.raw"; then
    bad "red-edited-payload-detected" "mutation anchor missing — the control would pass vacuously"
elif cmp -s "$HX_TMP/old.norm" "$HX_TMP/edited.raw"; then
    bad "red-edited-payload-detected" "an edited log date still compared equal"
else
    ok "red-edited-payload-detected"
fi

finish
