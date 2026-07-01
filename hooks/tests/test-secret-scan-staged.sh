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
# WS1a additions: the ghp_ tokens are constructed at RUNTIME (no literal PAT is a
# committed + line here), a NEGATIVE test proves a real secret in a NON-designed
# hooks/tests/*.sh still blocks (the narrow exclude did not blind the scanner), and a
# RELEASE-GATE SELF-TEST stages the full working tree through the fixed scan (exit 0)
# to catch any future in-tree literal token before tagging.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: secret-scan-staged <name>" / "FAIL: secret-scan-staged <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HELPER="$ROOT/hooks/shared/staged_secret_scan.py"
# TRIPWIRE (WS1a): construct every ghp_-shaped token at RUNTIME so no literal PAT is a
# committed `+` line in THIS file — the release-gate self-test stages the whole tree
# through the fixed pre-commit, so any in-tree literal PAT would self-block the release.
# Narrow-exclude discipline: this runtime construction (not a `:(exclude)hooks/tests/`)
# is what keeps the scanner able to catch a REAL secret dropped into non-designed test
# code (see negative test below).
# A real GitHub-PAT-shaped token (40 chars after ghp_) — matches the high-confidence
# github_personal_access_token pattern; used as the "real secret" probe.
SECRET="ghp_$(printf 'a%.0s' $(seq 1 40))"
# The two designed secret-patterns.yml example tokens (ghp_ + 36 chars), built the same
# way: the sed below rewrites the committed x-token to the y-token to prove that editing
# the designed-token policy file is NOT blocked (path-excluded).
DESIGNED_X="ghp_$(printf 'x%.0s' $(seq 1 36))"
DESIGNED_Y="ghp_$(printf 'y%.0s' $(seq 1 36))"

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
sed -i "s/$DESIGNED_X/$DESIGNED_Y/" "$D/policies/secret-patterns.yml"
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

# NEGATIVE TEST (WS1a): a REAL hard-coded secret added to a NON-designed hooks/tests/*.sh
# (test CODE one level above hooks/tests/fixtures/) STILL BLOCKS. Proves the narrow
# exclude (fixtures/ + the two policy files only) did not blind the scanner to real
# secrets in test code — the reason WS1a keeps runtime tokens instead of :(exclude)hooks/tests/.
D="$(new_repo)"
mkdir -p "$D/hooks/tests"
printf 'TOKEN="%s"\n' "$SECRET" > "$D/hooks/tests/leaky-test.sh"
( cd "$D" && git add hooks/tests/leaky-test.sh )
if run_helper "$D"; then bad "a1-real-secret-in-nondesigned-test-still-blocks" "a real secret in hooks/tests/*.sh was NOT blocked (narrow exclude blinded the scanner!)"; else ok "a1-real-secret-in-nondesigned-test-still-blocks"; fi
rm -rf "$D"

# RELEASE-GATE SELF-TEST (WS1a): stage the ENTIRE release tree (the WORKING tree — what
# is about to be committed/tagged, not the prior HEAD) through the fixed pre-commit
# secret scan and assert exit 0 — catches any future in-tree literal token before
# tagging. Uses an explicit path-staging list (git ls-files -z | git add --), NOT
# `git add -A` (command-policy compat). Files are copied into a throwaway repo so the
# real .git/hooks stay out of scope: this exercises ONLY the staged_secret_scan helper
# against a full-tree staged diff, deterministically here (no host dependence).
D="$(mktemp -d)"
( cd "$ROOT" && git init -q "$D" && git -C "$D" config user.email t@t.t \
    && git -C "$D" config user.name t && git -C "$D" config core.autocrlf false )
# Copy the exact tracked working-tree set into the throwaway repo in ONE pass (a
# per-file cp loop over ~700 files is prohibitively slow on a loaded MSYS host): pipe
# `git ls-files -z` through a single tar. Then stage everything explicitly (no `git
# add -A`; the exact tracked set is what tar carried).
( cd "$ROOT" && git ls-files -z | tar --null -T - -cf - 2>/dev/null ) | ( cd "$D" && tar -xf - ) 2>/dev/null
( cd "$D" && git ls-files -o --exclude-standard -z | xargs -0 -r git add -- ) 2>/dev/null
if ( cd "$D" && PYTHONPATH="$D/hooks" python3 "$D/hooks/shared/staged_secret_scan.py" >/dev/null 2>&1 ); then
  ok "release-gate-self-test-tree-commits-clean"
else
  bad "release-gate-self-test-tree-commits-clean" "the full release tree tripped the secret scan (an in-tree literal token ships a self-blocking release)"
fi
rm -rf "$D"

finish
