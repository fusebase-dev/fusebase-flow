#!/usr/bin/env bash
# Fusebase Flow — token-waste-audit labeled auto-classification contract (S6 / AC15-AC19).
#
# The instrument's job is to make human adjudication cheaper, never to decide silently:
# a dismissed finding is invisible, so a false negative costs more than a false positive.
# Both A8 predicates are CONJUNCTIVE and every branch is pinned here, matching AND
# non-matching:
#
#   growing-source-tail (AC15) — dismissed only on same full read key + (monotonic growth
#     OR all-differing digests) + no contradictory event. fx-02 is the arm that bites:
#     sizes differ while the normalized bodies are identical, so a size-difference-only
#     re-read MUST stay live. fx-03/04/05 pin the three contradictory-event branches.
#   possible-FR-10-triple (AC16) — exactly-3 runs are LABELED; dismissed only when the
#     command is probe-shaped. fx-07 (3 non-probe runs) staying live is the proof the
#     tool does not confuse three failed retries with a reproduction triple.
#
# AC17 evidence, AC18 separate dismissal count, AC19 four named terminal states are
# asserted on stdout/report text — silence must never look like cleanliness.
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: token-waste-classify <name>"
# / "FAIL: token-waste-classify <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
AUDIT="$ROOT/hooks/local/token-waste-audit.py"
FIX="$ROOT/hooks/tests/fixtures"
PY="${PYTHON:-python3}"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: token-waste-classify $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: token-waste-classify $1 ($2)"; }
finish() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; echo "[test-token-waste-classify] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v "$PY" >/dev/null 2>&1 || PY=python
command -v "$PY" >/dev/null 2>&1 || { bad "setup-python" "no python interpreter"; finish; }
[ -f "$AUDIT" ] || { bad "setup-audit-present" "missing $AUDIT"; finish; }
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14; do
    ls "$FIX"/token-waste-"$i"-*.jsonl >/dev/null 2>&1 || { bad "setup-fixtures-present" "missing fixture $i"; finish; }
done
ok "setup-inputs-present"

TMP="$(mktemp -d)"
mkdir -p "$TMP/mixed" "$TMP/nodata" "$TMP/clean" "$TMP/allclassified" "$TMP/falseneg"
cp "$FIX"/token-waste-0[1-8]-*.jsonl "$TMP/mixed/"
cp "$FIX"/token-waste-09-*.jsonl     "$TMP/nodata/"
cp "$FIX"/token-waste-10-*.jsonl     "$TMP/clean/"
cp "$FIX"/token-waste-01-*.jsonl     "$TMP/allclassified/"
# fx-11..14 are the A8-amendment false negatives (AC25/AC26) — kept in their own dir so
# the mixed-dir disposition counts above stay the AC15-AC19 contract, unchanged.
cp "$FIX"/token-waste-1[1-4]-*.jsonl "$TMP/falseneg/"

# TRIPWIRE: run from $TMP, never the repo — the parser resolves its report path from the
# git root, so a repo-cwd run would clobber the operator's real state/audit report.
run_audit() { # run_audit <subdir> [extra args...]
    local sub="$1"; shift
    # No MSYS_NO_PATHCONV here: --dir MUST be MSYS-converted, or a Windows Python
    # resolves the raw /tmp/... string against the wrong drive and finds no transcripts.
    ( cd "$TMP" && PYTHONIOENCODING=utf-8 "$PY" "$AUDIT" --dir "$TMP/$sub" "$@" 2>&1 )
}

OUT="$(run_audit mixed)"
# TRIPWIRE: read the report path off stdout, never rebuild it from $TMP — MSYS and the
# Windows Python disagree about how /tmp/... spells the same directory.
REPORT="$(printf '%s\n' "$OUT" | sed -n 's/.*| report: //p' | head -1)"
command -v cygpath >/dev/null 2>&1 && REPORT="$(cygpath -u "$REPORT" 2>/dev/null || printf '%s' "$REPORT")"
[ -f "$REPORT" ] && ok "report-written" || { bad "report-written" "no report at '$REPORT'"; finish; }

says()  { printf '%s' "$2" | grep -qF "$3" && ok "$1" || bad "$1" "expected: $3"; }
lacks() { printf '%s' "$2" | grep -qF "$3" && bad "$1" "unexpected: $3" || ok "$1"; }
RPT="$(cat "$REPORT")"

# --- AC15/AC16 dispositions: exactly two dismissals, and the right two ----------------
says "ac18-live-counts-exclude-dismissed" "$OUT" "re-read 4 | polling 2"
says "ac18-dismissed-counted-separately"  "$OUT" "Auto-classified (dismissed, NOT counted above): 2"
says "ac15-growing-tail-dismissed"        "$OUT" "token-waste-01-growing-tail-classified.jsonl | re-read | auto-classified: growing-source-tail"
says "ac16-probe-triple-dismissed"        "$OUT" "token-waste-06-probe-triple-classified.jsonl | polling | auto-classified: possible-FR-10-triple"

# --- the arms that bite: nothing else may be dismissed --------------------------------
DISMISSED="$(printf '%s' "$OUT" | grep -F 'auto-classified:' || true)"
lacks "ac15-size-differs-only-not-dismissed"   "$DISMISSED" "token-waste-02"
lacks "ac15-intervening-write-not-dismissed"   "$DISMISSED" "token-waste-03"
lacks "ac15-compaction-not-dismissed"          "$DISMISSED" "token-waste-04"
lacks "ac15-error-result-not-dismissed"        "$DISMISSED" "token-waste-05"
lacks "ac16-nonprobe-triple-not-dismissed"     "$DISMISSED" "token-waste-07"
lacks "ac16-nonprobe-quad-not-dismissed"       "$DISMISSED" "token-waste-08"

# --- AC17: every disposition prints the rule AND the evidence that triggered it -------
says "ac17-growing-tail-evidence"      "$OUT" "monotonic growth (sizes [100, 200, 300], 3 distinct digests); no contradictory event"
says "ac17-probe-triple-evidence"      "$OUT" "probe-shaped: test runner (run-tests)"
says "ac15-size-differs-only-evidence" "$RPT" "size difference alone is not sufficient"
says "ac15-contradictory-write"        "$RPT" "intervening write to the read path at event"
says "ac15-contradictory-compaction"   "$RPT" "context compaction between the reads at event"
says "ac15-contradictory-error"        "$RPT" "error-shaped tool_result for one of the reads"
says "ac16-triple-label-kept-live"     "$RPT" "possible-FR-10-triple"
says "ac16-since-last-write-noted"     "$RPT" "runs since the last write (not necessarily consecutive)"

# --- AC18: two sections, dismissals never inside the live table ------------------------
says "ac18-live-section"      "$RPT" "## Findings — LIVE candidates that MAY indicate an FR-26 rule"
says "ac18-dismissed-section" "$RPT" "## Auto-classified (dismissed — counted separately, never silently dropped)"
LIVE_TABLE="$(printf '%s\n' "$RPT" | sed -n '/## Findings — LIVE/,/## Auto-classified/p')"
lacks "ac18-live-table-has-no-dismissals" "$LIVE_TABLE" "token-waste-01-growing-tail-classified.jsonl"

# --- AC16 probe predicate, other branch: a documented gate probe dismisses fx-07 -------
OUT_PROBE="$(run_audit mixed --probe-command 'curl -sS https://example.invalid/api')"
says "ac16-probe-command-branch"   "$OUT_PROBE" "Auto-classified (dismissed, NOT counted above): 3"
says "ac16-probe-command-evidence" "$OUT_PROBE" "documented gate probe (--probe-command curl -sS https://example.invalid/api)"

# --- AC19: four terminal states, each named in words -----------------------------------
says "ac19-state-candidates-found" "$OUT" "TERMINAL STATE: candidates found (live candidates need adjudication)"
says "ac19-state-all-classified"   "$(run_audit allclassified)" "TERMINAL STATE: candidates found but all auto-classified"
says "ac19-state-clean"            "$(run_audit clean)"         "TERMINAL STATE: no candidates above thresholds"
says "ac19-state-parse-failure"    "$(run_audit nodata)"        "TERMINAL STATE: no transcripts / parse failure"
says "ac19-state-no-transcripts"   "$(run_audit missing-dir)"   "TERMINAL STATE: no transcripts / parse failure"

# --- AC25/AC26: the four Codex-PoC false negatives stay LIVE ---------------------------
# Run WITH the documented probe fx-13 embeds: verb-anchored matching and normalized
# --probe-command equality must still refuse to dismiss any of the four.
OUT_FN="$(run_audit falseneg --probe-command 'bash hooks/local/preflight.sh')"
says  "ac25-falseneg-none-dismissed" "$OUT_FN" "Auto-classified (dismissed, NOT counted above): 0"
says  "ac25-falseneg-all-stay-live"      "$OUT_FN" "re-read 1 | polling 3"
FN_DISMISSED="$(printf '%s' "$OUT_FN" | grep -F 'auto-classified:' || true)"
lacks "ac25-echo-status-not-dismissed"    "$FN_DISMISSED" "token-waste-11"
lacks "ac25-message-status-not-dismissed" "$FN_DISMISSED" "token-waste-12"
lacks "ac25-probe-plus-mutation-not-dismissed" "$FN_DISMISSED" "token-waste-13"
lacks "ac26-path-alias-not-dismissed"     "$FN_DISMISSED" "token-waste-14"

# --- privacy invariant: fixture bodies never reach the report --------------------------
lacks "privacy-no-result-bodies" "$RPT" "aaaaaaaaaa"

finish
