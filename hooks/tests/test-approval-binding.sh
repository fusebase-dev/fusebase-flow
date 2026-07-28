#!/usr/bin/env bash
# Fusebase Flow — approval-artifact schema, expiry, action-agreement and binding tests.
# Spec: docs/specs/approval-binding-and-upgrade-classification/spec.md (AC1..AC3, AC9..AC12, AC19).
#
# Drives the REAL hooks/shared/approval_artifact.py (and, from T3 on, command_policy)
# rather than a re-implementation, so a drift between the loader and its callers fails here.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: approval-binding <name>" / "FAIL: approval-binding <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: approval-binding $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: approval-binding $1 (${2:-})"; }
finish() { echo "[test-approval-binding] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: approval-binding skipped-no-python3"; pass=1; finish; }

# ---- 1. Verdict table (AC2, AC3): every state, and load() raises on nothing --------
VERDICT_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks"))
from shared.approval_artifact import (  # noqa: E402
    Verdict, evaluate_artifact, is_acceptable, load, parse_expiry, filename_action,
)

FUTURE = "2099-01-01T00:00:00Z"
PAST = "2000-01-01T00:00:00Z"
A = "production_deploy"

# (name, body, expected verdict) — body is evaluated against expected_action=A.
cases = [
    ("expiry-missing-key",      {"action": A},                              Verdict.MISSING_EXPIRY),
    ("expiry-empty-string",     {"action": A, "expires_at": ""},            Verdict.MISSING_EXPIRY),
    ("expiry-whitespace",       {"action": A, "expires_at": "   "},         Verdict.MISSING_EXPIRY),
    ("expiry-null",             {"action": A, "expires_at": None},          Verdict.MISSING_EXPIRY),
    ("expiry-integer",          {"action": A, "expires_at": 20991231},      Verdict.MALFORMED),
    ("expiry-bool",             {"action": A, "expires_at": True},          Verdict.MALFORMED),
    ("expiry-list",             {"action": A, "expires_at": [FUTURE]},      Verdict.MALFORMED),
    ("expiry-garbage",          {"action": A, "expires_at": "not-a-date"},  Verdict.MALFORMED),
    ("expiry-future-utc",       {"action": A, "expires_at": FUTURE},        Verdict.VALID),
    ("expiry-past-utc",         {"action": A, "expires_at": PAST},          Verdict.EXPIRED),
    ("expiry-future-offset",    {"action": A, "expires_at": "2099-01-01T00:00:00+02:00"}, Verdict.VALID),
    ("expiry-naive-future",     {"action": A, "expires_at": "2099-01-01T00:00:00"},       Verdict.VALID),
    ("action-mismatch",         {"action": "database_migration", "expires_at": FUTURE},   Verdict.ACTION_MISMATCH),
    ("action-absent-legacy-ok", {"expires_at": FUTURE},                     Verdict.VALID),
    ("action-non-string",       {"action": 7, "expires_at": FUTURE},        Verdict.MALFORMED),
    ("schema-v2-action-absent", {"schema_version": 2, "expires_at": FUTURE}, Verdict.MALFORMED),
    ("schema-unknown-version",  {"schema_version": 9, "action": A, "expires_at": FUTURE}, Verdict.MALFORMED),
    ("schema-non-int",          {"schema_version": "2", "action": A, "expires_at": FUTURE}, Verdict.MALFORMED),
    ("toplevel-array",          [1, 2, 3],                                  Verdict.MALFORMED),
    ("toplevel-string",         "approved",                                 Verdict.MALFORMED),
    ("toplevel-number",         42,                                         Verdict.MALFORMED),
    ("toplevel-null",           None,                                       Verdict.MALFORMED),
    ("unicode-fields-ok",       {"action": A, "expires_at": FUTURE, "reason": "приветÜñî 🚀"}, Verdict.VALID),
]
fails = []
for name, body, expected in cases:
    try:
        got = evaluate_artifact(body, expected_action=A)
    except BaseException as e:                      # noqa: BLE001 — the point of the test
        fails.append(f"{name}: RAISED {e!r}")
        continue
    if got is not expected:
        fails.append(f"{name}: expected {expected} got {got}")

# load() must never raise, for any file content.
with tempfile.TemporaryDirectory() as d:
    dd = Path(d)
    blobs = {
        "production_deploy-a-20260728.json": '{"action":"production_deploy"}',
        "production_deploy-b-20260728.json": "[1,2,3]",
        "production_deploy-c-20260728.json": "not json at all {{{",
        "production_deploy-d-20260728.json": "",
        "production_deploy-e-20260728.json": "\x00\x01\x02",
    }
    for fn, blob in blobs.items():
        (dd / fn).write_text(blob, encoding="utf-8", errors="replace")
    for fn in blobs:
        try:
            art = load(dd / fn)
        except BaseException as e:                  # noqa: BLE001
            fails.append(f"load-{fn}: RAISED {e!r}")
            continue
        if art is None:
            fails.append(f"load-{fn}: returned None for a readable file")
    try:
        if load(dd / "does-not-exist.json") is not None:
            fails.append("load-absent: expected None for a missing file")
    except BaseException as e:                      # noqa: BLE001
        fails.append(f"load-absent: RAISED {e!r}")

# parse_expiry never string-compares and never raises.
for bad_value in (None, 5, True, [], {}, "", "   ", "yesterday", "2026-13-45T99:99:99Z"):
    try:
        if parse_expiry(bad_value) is not None:
            fails.append(f"parse_expiry({bad_value!r}) should be None")
    except BaseException as e:                      # noqa: BLE001
        fails.append(f"parse_expiry({bad_value!r}): RAISED {e!r}")

# K17 per-carrier pass-sets.
expect_accept = {
    (Verdict.VALID, False): True,   (Verdict.VALID, True): True,
    (Verdict.MISSING_EXPIRY, False): True, (Verdict.MISSING_EXPIRY, True): False,
    (Verdict.EXPIRED, False): False, (Verdict.EXPIRED, True): False,
    (Verdict.MALFORMED, False): False, (Verdict.MALFORMED, True): False,
    (Verdict.ACTION_MISMATCH, False): False, (Verdict.ACTION_MISMATCH, True): False,
    (Verdict.BINDING_MISMATCH, False): False, (Verdict.BINDING_MISMATCH, True): False,
}
for (v, strict), want in expect_accept.items():
    if is_acceptable(v, strict=strict) is not want:
        fails.append(f"is_acceptable({v},strict={strict}) expected {want}")
if any(m.name == "LEGACY_OK" for m in Verdict):
    fails.append("Verdict carries LEGACY_OK — K17 forbids mode-dependent members")

if filename_action("production_deploy-my-hyphenated-slug-20260728.json") != "production_deploy":
    fails.append("filename_action: hyphenated slug broke the action boundary")

print(json.dumps(fails))
PY
)"
if [ "$VERDICT_OUT" = "[]" ]; then
  ok "verdict-table-and-loader-total"
else
  bad "verdict-table-and-loader-total" "$VERDICT_OUT"
fi

# ---- 2. AC19: no authorship-enforcement claim survives in the canonical files ------
AC19_FILES=(
  "policies/approval-policy.yml"
  "flow-skills/role-discipline/references/deploy.md"
  "workflows/greenlight-deploy.md"
)
ac19_hits=""
for f in "${AC19_FILES[@]}"; do
  if grep -nEi "hooks? (check|enforce|verif)[a-z]* this against|against the self-attested role" "$ROOT/$f" >/dev/null 2>&1; then
    ac19_hits="$ac19_hits $f"
  fi
done
if [ -z "$ac19_hits" ]; then
  ok "ac19-no-authorship-enforcement-claim"
else
  bad "ac19-no-authorship-enforcement-claim" "claim survives in:$ac19_hits"
fi
if grep -q "enforced_by_hooks: false" "$ROOT/policies/approval-policy.yml"; then
  ok "ac19-approval-authors-marked-declarative"
else
  bad "ac19-approval-authors-marked-declarative" "approval_authors is not marked enforced_by_hooks: false"
fi

finish
