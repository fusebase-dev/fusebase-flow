#!/usr/bin/env bash
# Fusebase Flow — single-use bootstrap protected-path exception + safe hook install
# tests (WS1b/c). Spec: docs/specs/windows-msys-hardening/roadmap.md § WS1.
#
# Proves, against REAL git repos + the REAL path_policy/pre-commit/install-git-hooks:
#   - fresh/upgrade setup commit through the wired pre-commit passes with NO --no-verify
#     once the digest-bound bootstrap approval is minted (write-bootstrap-approval.sh);
#   - the exception is SINGLE-USE: a second, unrelated protected-path edit still DENIES
#     (the staged digest changes -> the artifact no longer matches);
#   - install-git-hooks.sh PRESERVES a pre-existing custom .git/hooks/pre-commit
#     (backs it up, never silent-clobber) and refreshes a Flow-managed one in place.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: bootstrap-exception <name>" / "FAIL: bootstrap-exception <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: bootstrap-exception $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: bootstrap-exception $1 (${2:-})"; }
finish() { echo "[test-bootstrap-exception] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: bootstrap-exception skipped-no-python3"; pass=$((pass + 1)); finish; }

# new_repo: a throwaway git repo carrying the Flow bits this test exercises — the
# path_policy stack, protected-paths.yml, the pre-commit hook, and the local scripts.
new_repo() {
  local D; D="$(mktemp -d)"
  mkdir -p "$D/hooks/shared" "$D/hooks/git" "$D/hooks/local" "$D/policies" "$D/state/approvals" "$D/src"
  cp "$ROOT/hooks/shared/path_policy.py"   "$D/hooks/shared/"
  cp "$ROOT/hooks/shared/policy_loader.py" "$D/hooks/shared/"
  cp "$ROOT/hooks/shared/"*.py             "$D/hooks/shared/" 2>/dev/null || true
  : > "$D/hooks/shared/__init__.py"
  cp "$ROOT/policies/protected-paths.yml"  "$D/policies/"
  cp "$ROOT/hooks/git/pre-commit"          "$D/hooks/git/"
  cp "$ROOT/hooks/git/commit-msg"          "$D/hooks/git/" 2>/dev/null || true
  cp "$ROOT/hooks/local/install-git-hooks.sh"     "$D/hooks/local/"
  cp "$ROOT/hooks/local/write-bootstrap-approval.sh" "$D/hooks/local/"
  ( cd "$D" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config core.autocrlf false \
      && echo seed > seed.txt && git add seed.txt && git commit -qm seed )
  echo "$D"
}
# run_precommit DIR: run the REAL pre-commit hook in DIR; return its exit code.
run_precommit() { ( cd "$1" && bash hooks/git/pre-commit >/dev/null 2>&1 ); }

# ---- 1. Fresh/upgrade setup commit: protected-internals edit is ALLOWED once the
#         single-use digest-bound approval is minted (no --no-verify). ----
D="$(new_repo)"
# Edit a fusebase_flow_internals path (policies/*.yml) and stage it.
printf '\n# bootstrap edit\n' >> "$D/policies/protected-paths.yml"
( cd "$D" && git add policies/protected-paths.yml )
# Without an approval, the pre-commit must BLOCK (protected path, no exception).
if run_precommit "$D"; then bad "1-blocks-without-approval" "protected internals edit was NOT blocked pre-approval"; else ok "1-blocks-without-approval"; fi
# Mint the single-use bootstrap approval for exactly this staged changeset, then commit passes.
( cd "$D" && bash hooks/local/write-bootstrap-approval.sh >/dev/null 2>&1 )
if run_precommit "$D"; then ok "1-passes-with-bootstrap-approval-no-noverify"; else bad "1-passes-with-bootstrap-approval-no-noverify" "setup commit blocked even with the minted approval"; fi

# ---- 2. SINGLE-USE / reuse-denial: after the setup commit, a SECOND unrelated
#         protected-path edit still DENIES (the staged digest no longer matches). ----
( cd "$D" && git commit -qm 'chore(flow): setup commit' )
# Leave the (not-yet-consumed) artifact in place to prove digest-binding, not TTL, is
# what denies reuse. Stage a DIFFERENT protected internals edit (FLOW_RULES.md).
echo "FLOW_RULES seed" > "$D/FLOW_RULES.md"
( cd "$D" && git add FLOW_RULES.md )
if run_precommit "$D"; then bad "2-reuse-second-unrelated-edit-denies" "the bootstrap artifact acted as a STANDING bypass (reuse allowed a different edit!)"; else ok "2-reuse-second-unrelated-edit-denies"; fi
# And --consume removes the artifact (single-use cleanup).
( cd "$D" && bash hooks/local/write-bootstrap-approval.sh --consume >/dev/null 2>&1 )
if ls "$D"/state/approvals/protected_path_edit-flow-bootstrap-*.json >/dev/null 2>&1; then
  bad "2-consume-cleans-artifact" "bootstrap artifact still present after --consume"
else ok "2-consume-cleans-artifact"; fi
rm -rf "$D"

# ---- 3. Safe hook (re)install: a pre-existing CUSTOM .git/hooks/pre-commit is
#         PRESERVED + backed up (never silent-clobber); needs --force to replace. ----
D="$(new_repo)"
CUSTOM_MARKER="#!/bin/sh"$'\n'"echo custom-hook-sentinel"
printf '%s\n' "$CUSTOM_MARKER" > "$D/.git/hooks/pre-commit"
chmod +x "$D/.git/hooks/pre-commit"
( cd "$D" && bash hooks/local/install-git-hooks.sh >/dev/null 2>&1 || true )
if grep -q custom-hook-sentinel "$D/.git/hooks/pre-commit"; then ok "3-custom-hook-preserved"; else bad "3-custom-hook-preserved" "custom pre-commit was silently overwritten"; fi
if ls "$D"/.git/hooks/pre-commit.pre-flow-* >/dev/null 2>&1; then ok "3-custom-hook-backed-up"; else bad "3-custom-hook-backed-up" "no backup of the custom hook was written"; fi
# --force installs the Flow hook (the custom one stays in the backup).
( cd "$D" && bash hooks/local/install-git-hooks.sh --force >/dev/null 2>&1 || true )
if head -5 "$D/.git/hooks/pre-commit" | grep -qF "Fusebase Flow"; then ok "3-force-installs-flow-hook"; else bad "3-force-installs-flow-hook" "--force did not install the Flow hook"; fi
# A Flow-managed hook refreshes in place (no spurious backup, no skip).
( cd "$D" && bash hooks/local/install-git-hooks.sh >/dev/null 2>&1 || true )
if head -5 "$D/.git/hooks/pre-commit" | grep -qF "Fusebase Flow"; then ok "3-flow-hook-refreshed-in-place"; else bad "3-flow-hook-refreshed-in-place" "Flow-managed hook was not refreshed in place"; fi
rm -rf "$D"

finish
