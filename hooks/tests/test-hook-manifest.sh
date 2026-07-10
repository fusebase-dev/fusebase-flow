#!/usr/bin/env bash
# Fusebase Flow — hook-layer manifest stamp/verify self-test (tag hook-manifest, T5).
# Operates ONLY on a TEMP COPY of the covered tree via hook_manifest.py --root
# (R2 — the live tree is never mutated). 8 scenarios.
#
# Contract (run_shell_phase): "PASS: hook-manifest <name>" / "FAIL: hook-manifest
# <name>"; exit = fail count. Cleanup trap removes only its own mktemp root.
set -uo pipefail

REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB="$REPO/hooks/local/lib/hook_manifest.py"
python_bin="${PYTHON:-python3}"; command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-hook-manifest.XXXXXX")"
cleanup() { case "$TMP" in "${TMPDIR:-/tmp}"/ffhc-hook-manifest.*) rm -rf -- "$TMP" ;; esac; }
trap cleanup EXIT

fail=0
ok() { echo "PASS: hook-manifest $1"; }
no() { echo "FAIL: hook-manifest $1 ($2)"; fail=$((fail + 1)); }

# Build the temp covered tree (hooks/ + VERSION); the manifest lands in $TMP/audit/.
cp -R "$REPO/hooks" "$TMP/hooks"
cp "$REPO/VERSION" "$TMP/VERSION"
MAN="$TMP/audit/hook-layer-manifest.json"
stamp() { "$python_bin" "$LIB" stamp --root "$TMP" >/dev/null 2>&1; }
verify() { "$python_bin" "$LIB" verify --root "$TMP" 2>/dev/null; }  # prints; returns rc
manifest_has() { "$python_bin" - "$MAN" "$1" <<'PY'
import json, pathlib, sys
paths = {a["path"] for a in json.loads(pathlib.Path(sys.argv[1]).read_text())["assets"]}
raise SystemExit(0 if sys.argv[2] in paths else 1)
PY
}

# Covered-set sentinels: transcript fixtures are included; local overrides and
# bytecode caches are excluded.
JSONL_SENTINEL="hooks/tests/fixtures/manifest-covered-sentinel.jsonl"
LOCAL_SENTINEL="hooks/local/manifest-ignored.local.sh"
PYC_SENTINEL="hooks/shared/__pycache__/x.pyc"
printf '{"event":"sentinel"}\n' > "$TMP/$JSONL_SENTINEL"
printf '# local override\n' > "$TMP/$LOCAL_SENTINEL"
mkdir -p "$TMP/hooks/shared/__pycache__"
printf 'bytecode sentinel\n' > "$TMP/$PYC_SENTINEL"
stamp

# 1. covered-set include/exclude contract.
if manifest_has "$JSONL_SENTINEL" \
   && ! manifest_has "$LOCAL_SENTINEL" \
   && ! manifest_has "$PYC_SENTINEL"; then
  ok "covered set includes .jsonl; excludes *.local.* and __pycache__/*.pyc"
else
  no "covered-set include/exclude contract" "manifest membership mismatch"
fi

# 2. deleting a listed file => rc 1 DRIFT naming the missing path.
rm -f "$TMP/$JSONL_SENTINEL"
out="$(verify)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "$JSONL_SENTINEL" \
   && printf '%s' "$out" | grep -q "missing"; then
  ok "deleted listed file => rc 1 DRIFT naming missing path"
else
  no "deleted listed file => rc 1 DRIFT naming missing path" "rc=$rc"
fi
printf '{"event":"sentinel"}\n' > "$TMP/$JSONL_SENTINEL"
stamp

# 3. stamp byte-idempotence (D1 — no "modulo generated_at" allowance).
stamp; cp "$MAN" "$TMP/m1.json"; stamp
if cmp -s "$MAN" "$TMP/m1.json"; then ok "stamp byte-idempotence"
else no "stamp byte-idempotence" "two stamps produced different bytes"; fi

# 4. verify MATCH.
out="$(verify)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "MATCH"; then ok "verify MATCH"
else no "verify MATCH" "rc=$rc"; fi

# 5. tampered covered file => rc 1 naming the file.
printf '\n# tamper\n' >> "$TMP/hooks/shared/git_utils.py"
out="$(verify)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "hooks/shared/git_utils.py"; then ok "tampered covered file => drift naming it"
else no "tampered covered file => drift naming it" "rc=$rc"; fi
cp "$REPO/hooks/shared/git_utils.py" "$TMP/hooks/shared/git_utils.py"  # restore exact bytes

# 6. Scan A — extra hooks/shared/*.py not in the manifest => rc 1.
touch "$TMP/hooks/shared/x_extra.py"
out="$(verify)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "x_extra.py"; then ok "Scan A extra hooks/shared file => drift"
else no "Scan A extra hooks/shared file => drift" "rc=$rc"; fi
rm -f "$TMP/hooks/shared/x_extra.py"

# 7. Scan B — sitecustomize.py nested under hooks/tests/ => rc 1, python-startup-file.
touch "$TMP/hooks/tests/sitecustomize.py"
out="$(verify)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "python-startup-file"; then ok "Scan B nested sitecustomize.py => startup-file drift"
else no "Scan B nested sitecustomize.py => startup-file drift" "rc=$rc"; fi
rm -f "$TMP/hooks/tests/sitecustomize.py"

# 8. corrupt self-hash => rc 2 BROKEN; then absent manifest => rc 4 ABSENT (SF8).
"$python_bin" - "$MAN" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
d["manifest_self_sha256"] = "0" * 64
p.write_text(json.dumps(d, indent=2) + "\n")
PY
out="$(verify)"; rc_self=$?
rm -f "$MAN"
out2="$(verify)"; rc_absent=$?
if [ "$rc_self" -eq 2 ] && printf '%s' "$out" | grep -q "BROKEN" \
   && [ "$rc_absent" -eq 4 ] && printf '%s' "$out2" | grep -q "ABSENT"; then
  ok "corrupt self-hash => rc 2; absent manifest => rc 4"
else
  no "corrupt self-hash => rc 2; absent manifest => rc 4" "rc_self=$rc_self rc_absent=$rc_absent"
fi

exit "$fail"
