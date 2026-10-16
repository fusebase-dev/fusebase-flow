#!/usr/bin/env bash
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t wasted-effort-windowing)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/selftest.out"

if ! python3 "$ROOT/hooks/local/find-wasted-effort.py" --selftest >"$OUT" 2>&1; then
    cat "$OUT"
    echo "FAIL: wasted-effort-windowing selftest"
    echo "[test-wasted-effort-windowing] 0/1 PASS"
    exit 1
fi

pass=0
fail=0
check() {
    if grep -qF "$2" "$OUT"; then
        pass=$((pass + 1))
        echo "PASS: wasted-effort-windowing $1"
    else
        fail=$((fail + 1))
        echo "FAIL: wasted-effort-windowing $1 (missing fixture result: $2)"
    fi
}

check "old-artifact-outside-window" "PASS windowing: old committed artifact is historical outside selected window"
check "exact-linkage" "PASS windowing: exact outcome/task/commit match is linked"
check "dirty-and-unlinked-content-excluded" "PASS windowing: dirty content is not linked by an older clean commit"
check "mixed-report-partition" "PASS windowing: mixed report partitions conclusions"
check "task-mismatch" "PASS windowing: task mismatch and unstructured dirty outcomes remain historical"
check "cosmetic-footer" "PASS windowing: cosmetic footer cannot promote old structured outcome"
check "approval-history-separated" "PASS windowing: approval history is retained outside window verdicts"
check "false-positive-preserved" "PASS windowing: linked instructional fixture cannot fabricate a gate outcome"
check "report-labels-both-scopes" "PASS windowing: report labels window and historical evidence separately"
check "template-table-linkage" "PASS windowing: template report with a resolving commit-table row is linked"
check "template-single-count" "PASS windowing: two-row linked report counts its gate outcome once"
check "template-gate-row-outcomes" "PASS windowing: linked template report carries its gate-satisfaction row outcomes"
check "template-status-required" "PASS windowing: template report without a Status line stays historical"
check "b5-docs-gate-subject" "PASS windowing: docs(gate) commit cannot link an unstructured report (B5)"
check "task-range-round" "PASS rounds: Task range groups T5 and T6 commits into one round keyed by the spec dir"
check "task-range-no-foreign-claim" "PASS rounds: an older Task range cannot claim another ticket's commit absent from its table"
check "task-range-ambiguity" "PASS rounds: a commit two reports' tables both resolve falls back to the subject"
check "task-range-bounds-claims" "PASS rounds: a resolving row outside the report's Task range stays unclaimed"
check "real-template-linked" "PASS windowing: real gate-report template with all-PASS gate rows is linked"
check "real-template-relay-no-block" "PASS windowing: real template relay block adds no gate block"
check "real-template-no-firing" "PASS windowing: real template all-PASS report fires no control class"
check "real-template-deviation-approval" "PASS windowing: real template deviations section still counts its approval"
check "template-fail-row-blocks" "PASS windowing: linked template FAIL row without a block phrase counts a gate block"
check "real-template-fail-row" "PASS windowing: real template FAIL row counts one gate block"
check "template-fail-row-rule1" "PASS windowing: rule 1 cannot confirm over a linked template FAIL row"
check "deploy-report-keeps-phrase" "PASS windowing: a deploy report with a commit table keeps its recorded block phrase"

echo "[test-wasted-effort-windowing] $pass/$((pass + fail)) PASS"
exit "$fail"
