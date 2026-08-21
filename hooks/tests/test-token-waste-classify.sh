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
# TRIPWIRE (incident E7, 2026-08-21) — platform/data-loss: never name this TMP/TEMP/TMPDIR.
# On Windows those are PRE-SET env vars holding the operator's profile temp dir, and the three
# `finish` calls below (no python, missing audit, missing fixture) run BEFORE the mkdtemp
# assignment — a non-empty check would pass and recursively delete the operator's entire %TEMP%.
TW_TMP=""
tw_cleanup() { case "$TW_TMP" in "${TMPDIR:-/tmp}"/ffhc-tokenwaste.*) rm -rf -- "$TW_TMP" ;; esac; }
finish() { tw_cleanup; echo "[test-token-waste-classify] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v "$PY" >/dev/null 2>&1 || PY=python
command -v "$PY" >/dev/null 2>&1 || { bad "setup-python" "no python interpreter"; finish; }
[ -f "$AUDIT" ] || { bad "setup-audit-present" "missing $AUDIT"; finish; }
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14; do
    ls "$FIX"/token-waste-"$i"-*.jsonl >/dev/null 2>&1 || { bad "setup-fixtures-present" "missing fixture $i"; finish; }
done
ok "setup-inputs-present"

TW_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-tokenwaste.XXXXXX")" || { bad "setup-tmpdir" "mktemp -d failed"; finish; }
mkdir -p "$TW_TMP/mixed" "$TW_TMP/nodata" "$TW_TMP/clean" "$TW_TMP/allclassified" "$TW_TMP/falseneg"
cp "$FIX"/token-waste-0[1-8]-*.jsonl "$TW_TMP/mixed/"
cp "$FIX"/token-waste-09-*.jsonl     "$TW_TMP/nodata/"
cp "$FIX"/token-waste-10-*.jsonl     "$TW_TMP/clean/"
cp "$FIX"/token-waste-01-*.jsonl     "$TW_TMP/allclassified/"
# fx-11..14 are the A8-amendment false negatives (AC25/AC26) — kept in their own dir so
# the mixed-dir disposition counts above stay the AC15-AC19 contract, unchanged.
cp "$FIX"/token-waste-1[1-4]-*.jsonl "$TW_TMP/falseneg/"

# TRIPWIRE: run from $TW_TMP, never the repo — the parser resolves its report path from the
# git root, so a repo-cwd run would clobber the operator's real state/audit report.
run_audit() { # run_audit <subdir> [extra args...]
    local sub="$1"; shift
    # No MSYS_NO_PATHCONV here: --dir MUST be MSYS-converted, or a Windows Python
    # resolves the raw /tmp/... string against the wrong drive and finds no transcripts.
    ( cd "$TW_TMP" && PYTHONIOENCODING=utf-8 "$PY" "$AUDIT" --dir "$TW_TMP/$sub" "$@" 2>&1 )
}

OUT="$(run_audit mixed)"
# TRIPWIRE: read the report path off stdout, never rebuild it from $TW_TMP — MSYS and the
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

# --- AC27: absence is not enough — pin each survivor's EXACT row and evidence ----------
# TRIPWIRE: an aggregate count plus "fixture N is not in the dismissed list" lets one
# vanished candidate hide behind one extra candidate elsewhere. Each row below is matched
# verbatim INSIDE that fixture's own session section, so a substitution cannot net out.
TE02="FR-26 TE-02 — no re-reads of unchanged in-context files"
TE08="FR-26 TE-08 — record-then-read (smoke-testing § Verification cost discipline)"
READ3="re-read | Read x3 identical window: /repo/src/service.log | — | $TE02"
section() { printf '%s\n' "$RPT" | awk -v f="### token-waste-$1-" 'index($0,f)==1{on=1;next} on&&/^#/{on=0} on'; }
row() { says "ac27-row-$1" "$(section "$1")" "| $2 |"; }

row 02 "$READ3 | sizes [7, 3, 7], 1 distinct digest(s) — neither monotonic growth nor all-differing digests (size difference alone is not sufficient)"
row 03 "$READ3 | growth signal present but contradicted — intervening write to the read path at event 10"
row 04 "$READ3 | growth signal present but contradicted — context compaction between the reads at event 9"
row 05 "$READ3 | growth signal present but contradicted — error-shaped tool_result for one of the reads"
row 07 "polling | Bash x3 (no intervening Edit/Write): curl -sS https://example.invalid/api | possible-FR-10-triple | $TE08 | exactly 3 runs since the last write (not necessarily consecutive); command is NOT probe-shaped — 3 failed retries and 3 polls are count-identical to a genuine FR-10 reproduction triple, so this stays live"
row 08 "polling | Bash x4 (no intervening Edit/Write): curl -sS https://example.invalid/other | — | $TE08 | 4 runs since the last write (not necessarily consecutive)"

# --- AC27: mutation controls — each arm must FAIL under ITS unsafe classifier ----------
# A green assertion that can never fire proves nothing. Each control patches exactly the
# predicate that keeps its fixture live and requires the fixture to then be DISMISSED; a
# missing patch anchor fails the control instead of passing it vacuously.
cat > "$TW_TMP/mutate.py" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
pairs = sys.argv[3:]
for old, new in zip(pairs[::2], pairs[1::2]):
    if old not in text:
        sys.exit("MUTATION-ANCHOR-MISSING: " + old)
    text = text.replace(old, new, 1)
open(dst, "w", encoding="utf-8", newline="\n").write(text)
PY
mutctl() { # mutctl <fixture-id> <old> <new> [<old> <new> ...]
    local fx="$1"; shift
    local dir="$TW_TMP/mut$fx" mutant="$TW_TMP/mutant-$fx.py" out
    mkdir -p "$dir"; cp "$FIX"/token-waste-"$fx"-*.jsonl "$dir/"
    "$PY" "$TW_TMP/mutate.py" "$AUDIT" "$mutant" "$@" >/dev/null 2>&1 \
        || { bad "ac27-mutctl-$fx" "patch anchor missing — control would pass vacuously"; return; }
    out="$( cd "$TW_TMP" && PYTHONIOENCODING=utf-8 "$PY" "$mutant" --dir "$dir" 2>&1 )"
    printf '%s' "$out" | grep -F 'auto-classified:' | grep -qF "token-waste-$fx" \
        && ok "ac27-mutctl-$fx" \
        || bad "ac27-mutctl-$fx" "unsafe classifier did NOT dismiss fx-$fx — the arm proves nothing"
}
mutctl 02 'if not (grew or all_differ):' 'if not (len(set(sizes)) > 1):' \
          'if any(b < a for a, b in zip(sizes, sizes[1:])) and len({e[2] for e in events}) == 1:' 'if False:'
mutctl 03 'if lo < wseq < hi and wpath == path:' 'if False:'
mutctl 04 'if lo < cseq < hi:' 'if False:'
mutctl 05 'if any(e[3] for e in events):' 'if False:'
mutctl 07 'shape = probe_shaped(cmd, probe_cmds)' 'shape = "unsafe: exactly-3 dismissal"'
mutctl 08 'if n != FR10_TRIPLE:' 'if n < FR10_TRIPLE:' \
          'shape = probe_shaped(cmd, probe_cmds)' 'shape = "unsafe: any-repeat dismissal"'

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
