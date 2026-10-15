#!/usr/bin/env bash
# Fusebase Flow — gate-contract: hooks/local/verify-gate.sh validates gate_report VALUES, not
# field names, on a report filled from the shipped template (decision A4, v5.11 O7).
#
# Output contract (parsed by run-tests.sh run_shell_phase): "PASS: gate-contract <name>"
# / "FAIL: gate-contract <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
VG="$ROOT/hooks/local/verify-gate.sh"
LIB="$ROOT/hooks/local/lib/gate_contract_check.py"
POLICY="$ROOT/policies/gate-contracts.yml"
TPL="$ROOT/templates/gate-report.md"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: gate-contract $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: gate-contract $1 ($2)"; }
# TRIPWIRE (incident E7) — platform/data-loss: never name this TMP/TEMP/TMPDIR; on Windows those
# are pre-set to the operator's profile temp dir and would reach the recursive delete.
GC_TMP=""
gc_cleanup() { case "$GC_TMP" in "${TMPDIR:-/tmp}"/ffhc-gatec.*) rm -rf -- "$GC_TMP" ;; esac; }
finish() { echo "[test-gate-contract] $pass/$((pass + fail)) PASS"; gc_cleanup; exit $fail; }

GC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-gatec.XXXXXX")" || { bad "setup-tmpdir" "mktemp -d failed"; finish; }
for f in "$VG" "$LIB" "$POLICY" "$TPL"; do
    [ -f "$f" ] || { bad "setup-inputs-present" "missing $f"; finish; }
done
command -v python3 >/dev/null 2>&1 || { bad "setup-python3" "python3 not on PATH"; finish; }
ok "setup-inputs-present"

# TRIPWIRE: fixtures derive from the shipped template, so template/contract drift reddens pass-template.
if ! PYTHONIOENCODING=utf-8 python3 - "$TPL" "$GC_TMP" <<'PY'
import sys
from pathlib import Path

tpl, out = Path(sys.argv[1]).read_text(encoding="utf-8"), Path(sys.argv[2])
body = tpl.split("```markdown\n", 1)[1].split("\n## Fill-in checklist", 1)[0]
HEAD = "## 7. Gate satisfaction"


def with_rows(rows, src=body):
    head, tail = src.split(HEAD, 1)
    lines = tail.split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith("| Gate item"))
    end = start + 2
    while end < len(lines) and lines[end].startswith("|"):
        end += 1
    new = ["| " + " | ".join(r) + " |" for r in rows]
    return head + HEAD + "\n".join(lines[:start + 2] + new + lines[end:])


GOOD = ("hook suite green", "0 FAIL", "0 FAIL", "state/audit/hook-test-results.md @ abc1234", "PASS")
OPEN = ("smoke S1", "PASS", "not run", "—", "FAIL")
passing = with_rows([GOOD, OPEN])
fixtures = {
    "pass-template": passing,
    "stated-valid-enum": passing.replace("## 3. Lint + typecheck status\n",
                                         "## 3. Lint + typecheck status\n\n**Lint status:** clean\n", 1),
    "raw-template": body,
    "checkmark": with_rows([GOOD[:4] + ("✓",), OPEN]),
    "partial": with_rows([GOOD[:4] + ("PARTIAL",), OPEN]),
    "blank": with_rows([GOOD[:4] + ("",), OPEN]),
    "dash-evidence": with_rows([GOOD[:3] + ("—", "PASS"), OPEN]),
    "empty-evidence": with_rows([GOOD[:3] + ("", "PASS"), OPEN]),
    "escaped-pipe": with_rows([GOOD[:3] + ("`grep a \\| wc -l` = 0 @ abc1234", "`PASS`"), OPEN]),
    "placeholder-evidence": with_rows([GOOD[:3] + ("`<path / log line / ledger row>`", "PASS"), OPEN]),
    "zero-rows": with_rows([]),
    "bad-enum": passing.replace("## 3. Lint + typecheck status\n",
                                "## 3. Lint + typecheck status\n\n**Lint status:** flaky\n", 1),
    "old-pass-column": with_rows([("suite", "green", "green", "✓")], passing.replace(
        "| Gate item | Required | Actual | Evidence | Status |\n|---|---|---|---|---|",
        "| Gate item | Required | Actual | Pass? |\n|---|---|---|---|", 1)),
    "missing-summary": "\n".join(l for l in passing.split("\n")
                                 if not l.startswith("**Implementation summary:**")),
}
for name, text in fixtures.items():
    (out / (name + ".md")).write_text(text, encoding="utf-8")
PY
then
    bad "setup-fixtures" "fixture generation from $TPL failed (template shape moved?)"; finish
fi

expect() {
    local name="$1" fx="$GC_TMP/$2.md" want="$3" needle="${4:-}" out rc=0
    out="$(bash "$VG" "$fx" gate_report 2>&1)" || rc=$?
    if [ "$rc" -ne "$want" ]; then
        bad "$name" "rc=$rc expected $want: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)"
    elif [ -n "$needle" ] && ! grep -qF -- "$needle" <<< "$out"; then
        bad "$name" "rc=$rc but output lacks '$needle': $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)"
    else
        ok "$name"
    fi
}

expect "pass-template-shaped-report"        pass-template        0
expect "pass-stated-valid-enum"             stated-valid-enum    0
expect "fail-unfilled-template-placeholder" raw-template         1 "row 1: PASS without evidence"
expect "fail-checkmark-status"              checkmark            1 "row 1: status"
expect "fail-partial-status"                partial              1 "row 1: status 'PARTIAL'"
expect "fail-blank-status"                  blank                1 "row 1: status ''"
expect "fail-pass-with-dash-evidence"       dash-evidence        1 "row 1: PASS without evidence"
expect "fail-pass-with-empty-evidence"      empty-evidence       1 "row 1: PASS without evidence ('')"
expect "pass-escaped-pipe-and-code-status"  escaped-pipe         0
expect "fail-pass-with-placeholder-evidence" placeholder-evidence 1 "row 1: PASS without evidence"
expect "fail-zero-gate-rows"                zero-rows            1 "0 rows under 'Gate satisfaction'"
expect "fail-stated-enum-out-of-range"      bad-enum             1 "lint status: stated value 'flaky'"
expect "fail-old-pass-column-table"         old-pass-column      1 "has no Status column"
expect "fail-missing-required-field"        missing-summary      1 "missing: implementation summary"

rc=0; bash "$VG" "$GC_TMP/pass-template.md" no_such_contract >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then ok "unknown-contract-rc-2"; else bad "unknown-contract-rc-2" "rc=$rc"; fi

# TRIPWIRE (RED arm): a value-defect fixture the name-only mutant rejects proves nothing about the value rules.
set --
for fx in checkmark partial blank dash-evidence empty-evidence placeholder-evidence zero-rows bad-enum old-pass-column; do
    set -- "$@" "$GC_TMP/$fx.md"
done
n_bad=$#
red="$(PYTHONIOENCODING=utf-8 python3 - "$LIB" "$POLICY" "$@" <<'PY' 2>&1
import contextlib, importlib.util, io, sys

spec = importlib.util.spec_from_file_location("gate_contract_check", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.check_values = lambda fields, text: []
for fx in sys.argv[3:]:
    with contextlib.redirect_stdout(io.StringIO()):
        rc = mod.main(["gate_contract_check.py", fx, "gate_report", sys.argv[2]])
    print("%d %s" % (rc, fx))
PY
)"
rejected="$(printf '%s\n' "$red" | grep -v '^0 ' || true)"
if [ "$(printf '%s\n' "$red" | grep -c '^0 ')" -eq "$n_bad" ] && [ -z "$rejected" ]; then
    ok "red-name-only-mutant-accepts-every-value-defect"
else
    bad "red-name-only-mutant-accepts-every-value-defect" "premise moved — mutant output: $(printf '%s' "$red" | tr '\n' ' ' | cut -c1-300)"
fi

finish
