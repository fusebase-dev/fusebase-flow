#!/usr/bin/env bash
# Fusebase Flow — git-wrapper smoke (D9). Single temp repo, 5 sequential scenarios.
# Proves the commit-msg + pre-commit WRAPPERS run and gate; it does NOT re-cover
# every branch — deep §2/§3 trusted-HEAD coverage stays in test-secret-scan-staged.sh
# / test-trusted-enforcer.sh.
#
# Contract (parsed by run-tests.sh run_shell_phase): "PASS: git-smoke <name>" /
# "FAIL: git-smoke <name>" lines; exit = fail count. Bounded-friendly: no unbounded
# waits; cleanup trap removes only its own mktemp root.
set -uo pipefail

REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CM="$REPO/hooks/git/commit-msg"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-git-smoke.XXXXXX")"
cleanup() { case "$TMP" in "${TMPDIR:-/tmp}"/ffhc-git-smoke.*) rm -rf -- "$TMP" ;; esac; }
trap cleanup EXIT

fail=0
pass_case() { echo "PASS: git-smoke $1"; }
fail_case() { echo "FAIL: git-smoke $1 ($2)"; fail=$((fail + 1)); }

# --- commit-msg scenarios (direct invocation with a message file; no git state) ---
run_cm() {  # run_cm <subject>  -> sets CM_RC
  printf '%s\n' "$1" > "$TMP/msg.txt"
  bash "$CM" "$TMP/msg.txt" >/dev/null 2>&1; CM_RC=$?
}

run_cm "feat: no ticket"
if [ "$CM_RC" -ne 0 ]; then pass_case "commit-msg blocks missing T-number"
else fail_case "commit-msg blocks missing T-number" "rc=$CM_RC expected nonzero"; fi

run_cm "docs(flow): clarify FR-12 approval semantics"
if [ "$CM_RC" -eq 0 ]; then pass_case "commit-msg allows docs prefix"
else fail_case "commit-msg allows docs prefix" "rc=$CM_RC expected 0"; fi

run_cm "feat(x): T9 add y"
if [ "$CM_RC" -eq 0 ]; then pass_case "commit-msg allows T-numbered subject"
else fail_case "commit-msg allows T-numbered subject" "rc=$CM_RC expected 0"; fi

# --- pre-commit scenarios: a fresh temp repo (unborn HEAD => §2/§3 take the
#     documented first-adoption fallback to the working-tree scanner/enforcer,
#     which needs the Flow hook layer + policies present in the tree). ---
CONSUMER="$TMP/consumer"
mkdir -p "$CONSUMER/hooks"
cp -R "$REPO/hooks/shared" "$CONSUMER/hooks/shared"
cp -R "$REPO/hooks/local"  "$CONSUMER/hooks/local"
cp -R "$REPO/hooks/git"    "$CONSUMER/hooks/git"
cp -R "$REPO/policies"     "$CONSUMER/policies"
( cd "$CONSUMER" && git init -q && git config user.email t@example.com && git config user.name t )
PC="$CONSUMER/hooks/git/pre-commit"

# Scenario 4: pre-commit §1 blocks a staged .env (bash-only path, before python).
(
  cd "$CONSUMER"
  printf 'API_KEY=placeholder\n' > .env
  git add .env >/dev/null 2>&1
  bash "$PC" >/dev/null 2>&1
); PC_RC=$?
if [ "$PC_RC" -ne 0 ]; then pass_case "pre-commit blocks staged .env"
else fail_case "pre-commit blocks staged .env" "rc=$PC_RC expected nonzero"; fi

# Scenario 5: pre-commit passes a benign staged file end-to-end (§1-§5 all clear).
(
  cd "$CONSUMER"
  git reset -q -- .env >/dev/null 2>&1 || true
  rm -f .env
  printf '# consumer note\nhello world\n' > note.md
  git add note.md >/dev/null 2>&1
  bash "$PC" >/dev/null 2>&1
); PC_RC2=$?
if [ "$PC_RC2" -eq 0 ]; then pass_case "pre-commit passes benign staged file"
else fail_case "pre-commit passes benign staged file" "rc=$PC_RC2 expected 0"; fi

exit "$fail"
