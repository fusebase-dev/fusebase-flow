#!/usr/bin/env bash
# Fusebase Flow — staged-diff secret scan tests (D-A1 / AC-A1, AC-A2).
# Spec: docs/specs/secret-scan-and-msys-liveness-fix/spec.md.
#
# Proves the pre-commit secret step (hooks/shared/staged_secret_scan.py): scans
# ONLY added (+) lines and path-excludes the scanner's designed-token files
# (secret-patterns.yml + local override + hooks/tests/fixtures/), so a Flow upgrade
# that edits secret-patterns.yml is NOT blocked, while a REAL secret on a + line in
# a normal file STILL blocks. Each scenario builds a throwaway git repo and runs the
# REAL helper against a REAL staged diff (the pathspec exclude is a git-level effect,
# not simulated).
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: secret-scan-staged <name>" / "FAIL: secret-scan-staged <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HELPER="$ROOT/hooks/shared/staged_secret_scan.py"
# A real GitHub-PAT-shaped token (40 chars after ghp_) — matches the high-confidence
# github_personal_access_token pattern; used as the "real secret" probe.
SECRET="ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: secret-scan-staged $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: secret-scan-staged $1 (${2:-})"; }
finish() { echo "[test-secret-scan-staged] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$HELPER" ] || { bad "setup-helper-present" "missing $HELPER"; finish; }
ok "setup-helper-present"
command -v python3 >/dev/null 2>&1 || { echo "PASS: secret-scan-staged skipped-no-python3"; pass=$((pass + 1)); finish; }

# new_repo: a minimal git repo with the scanner stack copied in, seeded with one
# commit. Echoes the repo dir. Scans run via: (cd $D && python3 helper).
new_repo() {
  local D; D="$(mktemp -d)"
  mkdir -p "$D/hooks/shared" "$D/policies" "$D/hooks/tests/fixtures" "$D/src"
  cp "$ROOT/hooks/shared/staged_secret_scan.py" "$D/hooks/shared/"
  cp "$ROOT/hooks/shared/secret_scanner.py" "$D/hooks/shared/"
  cp "$ROOT/hooks/shared/audit_logger.py" "$D/hooks/shared/" 2>/dev/null || true
  cp "$ROOT/hooks/shared/policy_loader.py" "$D/hooks/shared/" 2>/dev/null || true
  : > "$D/hooks/shared/__init__.py"
  cp "$ROOT/policies/secret-patterns.yml" "$D/policies/"
  ( cd "$D" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config core.autocrlf false \
      && echo seed > seed.txt && git add -A && git commit -qm seed )
  echo "$D"
}
run_helper() { ( cd "$1" && PYTHONPATH="$1/hooks" python3 "$1/hooks/shared/staged_secret_scan.py" >/dev/null 2>&1 ); }

# AC-A1 #1: editing secret-patterns.yml (touching its own ghp example token) is NOT
# blocked (RED was BLOCK — the self-trip). Path-exclude removes it from the scan.
D="$(new_repo)"
sed -i "s/ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/ghp_yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy/" "$D/policies/secret-patterns.yml"
( cd "$D" && git add policies/secret-patterns.yml )
if run_helper "$D"; then ok "a1-edit-secret-patterns-not-blocked"; else bad "a1-edit-secret-patterns-not-blocked" "the secret-patterns.yml edit was BLOCKED (path-exclude failed)"; fi
rm -rf "$D"

# AC-A1 #2: a REAL secret on a + line in a NORMAL file STILL blocks (no weakening).
D="$(new_repo)"
echo "const TOKEN = '$SECRET';" > "$D/src/config.ts"
( cd "$D" && git add src/config.ts )
if run_helper "$D"; then bad "a1-real-secret-plus-line-still-blocks" "a real + secret was NOT blocked (detection weakened!)"; else ok "a1-real-secret-plus-line-still-blocks"; fi
rm -rf "$D"

# AC-A1 #3: a secret only on a REMOVED (-) line in a normal file is NOT blocked
# (removed content is leaving the repo).
D="$(new_repo)"
echo "const TOKEN = '$SECRET';" > "$D/src/config.ts"
( cd "$D" && git add src/config.ts && git commit -qm add-secret )
( cd "$D" && rm src/config.ts && git add src/config.ts )   # stage the deletion (- line)
if run_helper "$D"; then ok "a1-removed-line-secret-not-blocked"; else bad "a1-removed-line-secret-not-blocked" "a removed (-) secret blocked the commit"; fi
rm -rf "$D"

# AC-A1 #4 (deliberate gap, D-A1): a real secret added INSIDE hooks/tests/fixtures/
# is NOT caught by the commit scan (designed-token path exclude).
D="$(new_repo)"
echo "$SECRET" > "$D/hooks/tests/fixtures/99_designed.txt"
( cd "$D" && git add hooks/tests/fixtures/99_designed.txt )
if run_helper "$D"; then ok "a1-fixtures-excluded-deliberate-gap"; else bad "a1-fixtures-excluded-deliberate-gap" "fixtures/ secret blocked — exclusion not applied"; fi
rm -rf "$D"

# AC-A2: no whitelist entry was added to ship the fix, and the scanner's own fixtures
# 10/11 still detect (scan() semantics unchanged). Assert (a) the committed
# secret-patterns.yml whitelist is still empty, and (b) the two handler fixtures
# produce their expected decisions via the REAL handlers.
WL="$(grep -E '^whitelist:' "$ROOT/policies/secret-patterns.yml" | head -1)"
if [ "$WL" = "whitelist: []" ]; then ok "a2-no-whitelist-added"; else bad "a2-no-whitelist-added" "whitelist is not empty: $WL"; fi

f10="$(python3 "$ROOT/hooks/handlers/user_prompt_submit.py" < "$ROOT/hooks/tests/fixtures/10_user_prompt_submit_secret.json" 2>/dev/null)"
echo "$f10" | grep -q '"decision": "warn"' && ok "a2-fixture10-still-detects" || bad "a2-fixture10-still-detects" "fixture 10 decision changed: $f10"
f11="$(python3 "$ROOT/hooks/handlers/pre_tool_use.py" < "$ROOT/hooks/tests/fixtures/11_pre_tool_use_secret_in_write.json" 2>/dev/null)"
echo "$f11" | grep -q '"decision": "deny"' && ok "a2-fixture11-still-detects" || bad "a2-fixture11-still-detects" "fixture 11 decision changed: $f11"

finish
