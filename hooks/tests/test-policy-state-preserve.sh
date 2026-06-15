#!/usr/bin/env bash
# Fusebase Flow — AC7: policy-state preserve. A project's workflow_mode /
# worker_undisturbed value, held in a *.local.yml (deep-merged by policy_loader),
# survives an upgrade that refreshes policies/ wholesale — because the wholesale
# copy ships NO *.local.yml, so it cannot clobber the project override.
#
# Output contract (parsed by run-tests.sh): "PASS: policy-state <name>" /
# "FAIL: policy-state <name>"; exit code = number of failures.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
python_bin="${PYTHON:-python3}"; command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: policy-state $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: policy-state $1 ($2)"; }

if ! command -v "$python_bin" >/dev/null 2>&1; then
  echo "[test-policy-state-preserve] python not found; skipping" >&2; exit 0
fi
if ! "$python_bin" -c "import yaml" >/dev/null 2>&1; then
  echo "[test-policy-state-preserve] PyYAML not available; skipping" >&2; exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/policies" "$TMP/repo/hooks/shared"
git -C "$TMP/repo" init -q
cp "$ROOT/hooks/shared/policy_loader.py" "$TMP/repo/hooks/shared/"

# --- Committed defaults (what upstream ships) ---
cat > "$TMP/repo/policies/approval-policy.yml" <<'EOF'
schema_version: 2
workflow_mode: direct_to_main
require_approval: {}
EOF
cat > "$TMP/repo/policies/protected-paths.yml" <<'EOF'
schema_version: 1
categories:
  worker_undisturbed:
    paths: []
EOF

# --- Project overrides (the consumer's own state) in *.local.yml ---
cat > "$TMP/repo/policies/approval-policy.local.yml" <<'EOF'
workflow_mode: branch_pr
EOF
cat > "$TMP/repo/policies/protected-paths.local.yml" <<'EOF'
categories:
  worker_undisturbed:
    paths:
      - "src/workers/**/*.ts"
EOF

read_val() { # read_val <policy-name> <python-expr-on-merged-dict 'd'>
  ( cd "$TMP/repo" && FUSEBASE_FLOW_ROOT="$TMP/repo" "$python_bin" - "$1" "$2" <<'PY'
import sys
sys.path.insert(0, "hooks/shared")
from policy_loader import get_policy, reset_cache
reset_cache()
d = get_policy(sys.argv[1])
print(eval(sys.argv[2]))
PY
  )
}

# Pre-upgrade: the project override wins via deep-merge.
wm="$(read_val approval-policy "d.get('workflow_mode')")"
[ "$wm" = "branch_pr" ] && ok "pre-upgrade-workflow_mode-override-wins" \
  || bad "pre-upgrade-workflow_mode-override-wins" "got '$wm', expected branch_pr"
wu="$(read_val protected-paths "d['categories']['worker_undisturbed']['paths']")"
echo "$wu" | grep -q "src/workers" && ok "pre-upgrade-worker_undisturbed-override-wins" \
  || bad "pre-upgrade-worker_undisturbed-override-wins" "got '$wu'"

# --- Simulate the upgrade: refresh the COMMITTED policies/ wholesale from a fresh
#     upstream (which carries direct_to_main + empty worker_undisturbed and NO
#     *.local.yml). This is exactly upgrade.sh's `cp -R upstream/policies/. policies/`. ---
mkdir -p "$TMP/upstream/policies"
cat > "$TMP/upstream/policies/approval-policy.yml" <<'EOF'
schema_version: 2
workflow_mode: direct_to_main
require_approval: {}
EOF
cat > "$TMP/upstream/policies/protected-paths.yml" <<'EOF'
schema_version: 1
categories:
  worker_undisturbed:
    paths: []
EOF
cp -R "$TMP/upstream/policies/." "$TMP/repo/policies/"   # the wholesale clobber

# The *.local.yml files are NOT in upstream, so the copy left them untouched.
[ -f "$TMP/repo/policies/approval-policy.local.yml" ] && [ -f "$TMP/repo/policies/protected-paths.local.yml" ] \
  && ok "local-overrides-survive-wholesale-copy" \
  || bad "local-overrides-survive-wholesale-copy" "a *.local.yml was removed by the policies refresh"

# Post-upgrade: the project override STILL wins (committed base is fresh upstream,
# local override deep-merged on top).
wm2="$(read_val approval-policy "d.get('workflow_mode')")"
[ "$wm2" = "branch_pr" ] && ok "post-upgrade-workflow_mode-preserved" \
  || bad "post-upgrade-workflow_mode-preserved" "got '$wm2' after upgrade (project state lost)"
wu2="$(read_val protected-paths "d['categories']['worker_undisturbed']['paths']")"
echo "$wu2" | grep -q "src/workers" && ok "post-upgrade-worker_undisturbed-preserved" \
  || bad "post-upgrade-worker_undisturbed-preserved" "got '$wu2' after upgrade (project state lost)"

echo "[test-policy-state-preserve] $pass/$((pass + fail)) PASS"
exit $fail
