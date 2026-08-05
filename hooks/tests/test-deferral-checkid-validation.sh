#!/usr/bin/env bash
# Fusebase Flow — a health_check_deferral artifact cannot grant itself a check_id it never carried.
# Backlog: docs/backlog/self-granting-health-deferral/README.md
#
# THE DEFECT:
#   DEFERRED_CHECKS is the ONE artifact-derived input that moves the verdict — record_drift
#   reclassifies a matching finding to LOCAL_DEFERRED, which moves the health verdict to
#   EXCEPTION_IN_EFFECT and the exit code to 3. check_ids were carried newline-delimited, and a
#   check_id is artifact-controlled text, so ONE JSON element containing a newline became TWO
#   bash entries — the second being any canonical check_id the author chose.
#
# WHY VALIDATE-AND-REJECT AND NOT SANITIZE:
#   Deleting disallowed characters MANUFACTURES identifiers: a newline stripped out of
#   "claude<LF>_md_overlay" yields "claude_md_overlay", a real check_id. A repaired value that
#   collides with a genuine identifier is strictly worse than a dropped one. That collision is
#   asserted below; it is the case the parked surfacing work's own test missed.
#
# TRIPWIRE — WHY THE PAYLOADS ARE BUILT IN PYTHON, NOT AS SHELL LITERALS:
#   An earlier revision spelled the hostile ids as shell string literals. One carried a LITERAL
#   NUL byte, and bash strips NULs from script source — so the hostile probe silently became the
#   canonical id and the test reported a failure while the validator was correct. A test for a
#   content-splitting defect must not itself be splittable by its content. Every control
#   character below is produced by Python's json encoder and never appears in this file.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: deferral-checkid <name>" / "FAIL: deferral-checkid <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB="$ROOT/hooks/local/lib/active-approvals.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: deferral-checkid $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: deferral-checkid $1 (${2:-})"; }
finish() { echo "[test-deferral-checkid-validation] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$LIB" ] || { bad "setup-lib-present" "missing $LIB"; finish; }
command -v python3 >/dev/null 2>&1 || { bad "setup-python" "python3 required"; finish; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT

# TRIPWIRE (MSYS): a Windows python3 cannot open an MSYS "/tmp/..." path — it raises
# FileNotFoundError, the stream comes back EMPTY, and every "no accepted id" assertion passes
# vacuously. Same hazard the shipped lib documents at ff_project. Convert to a native path, and
# assert non-empty output in setup so an empty stream can never read as green.
native_path() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
WORK_NATIVE="$(native_path "$WORK")"

# Build every fixture in one Python pass. CANON is the canonical check_id an attacker wants to
# reach; each hostile id would collapse INTO it if the extractor sanitized instead of rejecting.
python3 - "$WORK_NATIVE" <<'PY'
import json, os, sys
work = sys.argv[1]
CANON = "claude_md_overlay"

def w(name, obj):
    with open(os.path.join(work, name), "w", encoding="utf-8") as fh:
        json.dump(obj, fh)

w("setup.json", {"deferred_checks": ["setup_probe_id"]})

# The ticket's exact payload: ONE element carrying an embedded newline.
w("split.json", {"action": "health_check_deferral",
                 "expires_at": "2099-01-01T00:00:00Z",
                 "deferred_checks": ["harmless_id\n" + CANON]})

# Collision probes: each becomes CANON if the disallowed character is deleted.
for i, ch in enumerate(["\n", "\t", "\r", "\x00", " ", "\x0b"]):
    w("collide%d.json" % i, {"deferred_checks": ["claude" + ch + "_md_overlay"]})

w("good.json", {"deferred_checks": [CANON, "mirror_drift", "a.b-c_1"]})
w("mixed.json", {"deferred_checks": ["good_id", "bad id with spaces"]})
w("len.json", {"deferred_checks": ["a" * 120, "a" * 121]})
w("types.json", {"deferred_checks": [123, None, True, {"a": 1}, ["x"], "ok_id"]})
PY

# Same validation contract and NUL transport as the shipped lib, isolated from approval-policy /
# expiry / project-root machinery: this asserts the split/collision property and nothing else.
extract() { # extract <json-file> -> prints "K<id>" / "R<repr>" one per line
    MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$(native_path "$1")" <<'PY' 2>/dev/null | tr '\0' '\n'
import json, re, sys
VALID = re.compile(r'[A-Za-z0-9._-]{1,120}')
out = sys.stdout.buffer
try:
    data = json.loads(open(sys.argv[1], encoding='utf-8').read())
    for cid in (data.get('deferred_checks') or []):
        if isinstance(cid, str) and VALID.fullmatch(cid):
            out.write(b'K' + cid.encode('utf-8') + b'\0')
        else:
            out.write(b'R' + repr(cid)[:120].encode('ascii', errors='replace') + b'\0')
    out.flush()
except Exception:
    pass
PY
}

# --- 0. Setup guard: prove extraction works before trusting any "nothing accepted" assertion --
if [ "$(extract "$WORK/setup.json")" = "Ksetup_probe_id" ]; then
    ok "setup-extraction-harness-works"
else
    bad "setup-extraction-harness-works" "empty/unexpected stream — every rejection assertion would be vacuous"
    finish
fi

# --- 1. The ticket's payload: one element, embedded newline -----------------------------------
out="$(extract "$WORK/split.json")"
accepted="$(echo "$out" | grep -c '^K' || true)"
if [ "$accepted" -eq 0 ] && echo "$out" | grep -q '^R'; then
    ok "embedded-newline-yields-zero-accepted-ids"
else
    bad "embedded-newline-yields-zero-accepted-ids" "accepted=$accepted; out=$(echo "$out" | tr '\n' '|')"
fi
if echo "$out" | grep -q '^Kclaude_md_overlay$'; then
    bad "embedded-newline-cannot-self-grant-canonical-id" "claude_md_overlay was granted"
else
    ok "embedded-newline-cannot-self-grant-canonical-id"
fi

# --- 2. Collision probes: rejected, never folded into the canonical id -------------------------
for f in "$WORK"/collide*.json; do
    n="$(basename "$f")"
    out="$(extract "$f")"
    if echo "$out" | grep -q '^Kclaude_md_overlay$'; then
        bad "collision-probe-rejected [$n]" "repaired into the canonical id"
    elif echo "$out" | grep -q '^K'; then
        bad "collision-probe-rejected [$n]" "accepted an id containing a disallowed character"
    elif echo "$out" | grep -q '^R'; then
        ok "collision-probe-rejected [$n]"
    else
        bad "collision-probe-rejected [$n]" "empty stream — neither accepted nor reported"
    fi
done

# --- 3. The feature still works for honest artifacts ------------------------------------------
out="$(extract "$WORK/good.json")"
n="$(echo "$out" | grep -c '^K' || true)"
if [ "$n" -eq 3 ] && echo "$out" | grep -q '^Kclaude_md_overlay$' && ! echo "$out" | grep -q '^R'; then
    ok "well-formed-multi-entry-list-still-populates"
else
    bad "well-formed-multi-entry-list-still-populates" "accepted=$n; out=$(echo "$out" | tr '\n' '|')"
fi

# --- 4. A rejected id is reported, not silently dropped ---------------------------------------
out="$(extract "$WORK/mixed.json")"
if echo "$out" | grep -q '^Kgood_id$' && echo "$out" | grep -q '^R'; then
    ok "malformed-id-is-reported-not-silently-dropped"
else
    bad "malformed-id-is-reported-not-silently-dropped" "out=$(echo "$out" | tr '\n' '|')"
fi

# --- 5. Boundary: 120 chars accepted, 121 rejected --------------------------------------------
out="$(extract "$WORK/len.json")"
if [ "$(echo "$out" | grep -c '^K' || true)" -eq 1 ] && [ "$(echo "$out" | grep -c '^R' || true)" -eq 1 ]; then
    ok "length-boundary-120-accepted-121-rejected"
else
    bad "length-boundary-120-accepted-121-rejected" "out=$(echo "$out" | tr '\n' '|' | cut -c1-160)"
fi

# --- 6. Non-string elements rejected, not coerced ----------------------------------------------
out="$(extract "$WORK/types.json")"
if [ "$(echo "$out" | grep -c '^K' || true)" -eq 1 ] && echo "$out" | grep -q '^Kok_id$'; then
    ok "non-string-elements-rejected-not-coerced"
else
    bad "non-string-elements-rejected-not-coerced" "out=$(echo "$out" | tr '\n' '|')"
fi

# --- 7. The shipped lib carries the contract (not just this probe) -----------------------------
# Residency assertions: the probes above prove the RULE; these prove the rule is what ships.
if grep -q 'fullmatch' "$LIB" && grep -q 'A-Za-z0-9._-' "$LIB"; then
    ok "shipped-lib-uses-fullmatch-validation"
else
    bad "shipped-lib-uses-fullmatch-validation" "validation not found in $LIB"
fi
if grep -q "read -r -d '' entry" "$LIB" && grep -q 'print0' "$LIB"; then
    ok "shipped-lib-uses-nul-transport-and-print0-traversal"
else
    bad "shipped-lib-uses-nul-transport-and-print0-traversal" "newline-splittable transport still present in $LIB"
fi
# The extraction must NOT be wrapped in $(...) — command substitution DISCARDS NUL bytes, which
# would silently empty the NUL-delimited stream this fix depends on.
if grep -q 'deferred_list=\$(' "$LIB"; then
    bad "extraction-not-routed-through-command-substitution" "\$(...) discards NUL bytes"
else
    ok "extraction-not-routed-through-command-substitution"
fi

finish
