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
check "direct-and-explicit-linkage" "PASS windowing: explicit selected-commit SHA links an uncommitted artifact"
check "dirty-and-unlinked-content-excluded" "PASS windowing: dirty content is not linked by an older clean commit"
check "approval-history-separated" "PASS windowing: approval history is retained outside window verdicts"
check "false-positive-preserved" "PASS windowing: linked instructional fixture cannot fabricate a gate outcome"
check "report-labels-both-scopes" "PASS windowing: report labels window and historical evidence separately"

echo "[test-wasted-effort-windowing] $pass/$((pass + fail)) PASS"
exit "$fail"
