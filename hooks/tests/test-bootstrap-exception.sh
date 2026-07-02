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

# ---- 4. GLOB-ARTIFACT BYPASS (T10 BLOCKER): a crafted bootstrap artifact whose
#         `paths` carries a GLOB (`hooks/shared/**`) must NOT authorize an edit to a
#         concrete NEW/unrelated file under that tree — the glob must never bind a
#         concrete queried path. The pre-commit must DENY. ----
D="$(new_repo)"
# Stage a concrete NEW protected-internals file under hooks/shared/.
echo "print('x')" > "$D/hooks/shared/new_unrelated.py"
( cd "$D" && git add hooks/shared/new_unrelated.py )
# Craft the ATTACK artifact by hand (NOT via the writer): a wildcard `paths` entry +
# the bootstrap operation + a tree_digest computed for that glob string. With the T10
# fix the glob is rejected two ways (exact-membership drop + glob-metachar reject), so
# no concrete path under the tree can bind.
GLOB_DIGEST="$(cd "$D" && PYTHONPATH="$D/hooks" python3 - <<'PY'
from shared.path_policy import compute_staged_tree_digest
from pathlib import Path
print(compute_staged_tree_digest(["hooks/shared/**"], Path(".")))
PY
)"
cat > "$D/state/approvals/protected_path_edit-flow-bootstrap-glob.json" <<JSON
{ "approved_by": "attacker", "scope": "flow-internals-bootstrap",
  "expires_at": "2999-01-01T00:00:00Z", "reason": "crafted glob bypass",
  "action": "protected_path_edit", "operation": "flow-internals-bootstrap",
  "tree_digest": "$GLOB_DIGEST", "paths": ["hooks/shared/**"] }
JSON
if run_precommit "$D"; then bad "4-glob-artifact-denies" "a glob-bearing bootstrap artifact authorized a concrete edit under the tree (STANDING bypass!)"; else ok "4-glob-artifact-denies"; fi

# ---- 4b. NO-STAGED-CONTENT: a bootstrap artifact listing an EXACT concrete path
#          that is NOT in the pending commit must DENY (an approvable internals path
#          must actually be staged). Same staged file as above; artifact names a
#          DIFFERENT concrete path (FLOW_RULES.md) that is not staged. ----
NOSTAGE_DIGEST="$(cd "$D" && PYTHONPATH="$D/hooks" python3 - <<'PY'
from shared.path_policy import compute_staged_tree_digest
from pathlib import Path
print(compute_staged_tree_digest(["FLOW_RULES.md"], Path(".")))
PY
)"
rm -f "$D"/state/approvals/protected_path_edit-flow-bootstrap-glob.json
cat > "$D/state/approvals/protected_path_edit-flow-bootstrap-nostage.json" <<JSON
{ "approved_by": "attacker", "scope": "flow-internals-bootstrap",
  "expires_at": "2999-01-01T00:00:00Z", "reason": "unstaged concrete path",
  "action": "protected_path_edit", "operation": "flow-internals-bootstrap",
  "tree_digest": "$NOSTAGE_DIGEST", "paths": ["FLOW_RULES.md"] }
JSON
# The QUERIED staged path (hooks/shared/new_unrelated.py) is protected and this
# artifact doesn't list it -> DENY; and even for FLOW_RULES.md the no-staged-content
# guard would reject. Assert the staged internals edit is still blocked.
if run_precommit "$D"; then bad "4b-no-staged-content-denies" "an artifact whose approved path is not in the pending commit authorized the edit"; else ok "4b-no-staged-content-denies"; fi
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
# --force installs the Flow hook (the custom one stays in the backup). Key off the
# UNIQUE managed marker (T11) — the token that identifies a Flow-managed hook.
( cd "$D" && bash hooks/local/install-git-hooks.sh --force >/dev/null 2>&1 || true )
if head -5 "$D/.git/hooks/pre-commit" | grep -qF "fusebase-flow-managed-hook:"; then ok "3-force-installs-flow-hook"; else bad "3-force-installs-flow-hook" "--force did not install the Flow hook (unique marker absent)"; fi
# A Flow-managed hook refreshes in place (no spurious backup, no skip).
( cd "$D" && bash hooks/local/install-git-hooks.sh >/dev/null 2>&1 || true )
if head -5 "$D/.git/hooks/pre-commit" | grep -qF "fusebase-flow-managed-hook:"; then ok "3-flow-hook-refreshed-in-place"; else bad "3-flow-hook-refreshed-in-place" "Flow-managed hook was not refreshed in place (unique marker absent)"; fi
rm -rf "$D"

# ---- 6. DELETE + RENAME coverage (T23 — closes the shipped FR-07 bypass): §3 of the
#         pre-commit used to gate on `--diff-filter=ACM` only, so a staged DELETE
#         (`git rm`) or RENAME of a protected file never reached path_policy and
#         committed with exit 0, no approval. Now the FULL staged change set is
#         evaluated (A/C/M path; D deleted path; R BOTH old+new). The digest-bound
#         single-use approval still authorizes a sanctioned delete/rename. ----
D="$(new_repo)"
# Seed a committed protected file to delete + one to rename, plus a non-protected file.
echo "print('victim')" > "$D/hooks/shared/victim.py"
echo "rules"          > "$D/FLOW_RULES.md"
echo "app"            > "$D/src/app.py"
( cd "$D" && git add -A && git commit -qm 'seed protected+nonprotected' )

# 6a. Staged DELETE of a protected path BLOCKS without an approval (RED before T23).
( cd "$D" && git rm -q hooks/shared/victim.py )
if run_precommit "$D"; then bad "6a-protected-delete-blocked" "a staged git-rm of a protected path committed with NO approval (FR-07 bypass)"; else ok "6a-protected-delete-blocked"; fi
# 6b. That SAME delete PASSES once the sanctioned single-use approval is minted (no --no-verify).
( cd "$D" && bash hooks/local/write-bootstrap-approval.sh >/dev/null 2>&1 )
if run_precommit "$D"; then ok "6b-protected-delete-with-approval-passes"; else bad "6b-protected-delete-with-approval-passes" "sanctioned delete blocked even with the minted approval"; fi
( cd "$D" && git commit -qm 'chore(flow): remove victim' && bash hooks/local/write-bootstrap-approval.sh --consume >/dev/null 2>&1 )

# 6c. Staged RENAME of a protected path (old+new both under protection) BLOCKS w/o approval.
( cd "$D" && git mv FLOW_RULES.md FLOW_RULES_v2.md && git add -A )
if run_precommit "$D"; then bad "6c-protected-rename-blocked" "a staged rename of a protected path committed with NO approval"; else ok "6c-protected-rename-blocked"; fi
# 6d. RENAME PASSES with the sanctioned approval (writer + verifier share the full staged set).
( cd "$D" && bash hooks/local/write-bootstrap-approval.sh >/dev/null 2>&1 )
if run_precommit "$D"; then ok "6d-protected-rename-with-approval-passes"; else bad "6d-protected-rename-with-approval-passes" "sanctioned rename blocked even with the minted approval"; fi
( cd "$D" && git commit -qm 'chore(flow): rename rules' && bash hooks/local/write-bootstrap-approval.sh --consume >/dev/null 2>&1 )
rm -rf "$D"

# 6e/6f. Leaving/entering protection: a rename whose OLD path is protected (moving OUT)
#         and one whose NEW path is protected (moving IN) must BOTH block — both sides
#         of the rename are evaluated.
D="$(new_repo)"
echo "print('mover')" > "$D/hooks/shared/mover.py"; echo "in" > "$D/src/incoming.py"
( cd "$D" && git add -A && git commit -qm 'seed mover+incoming' )
( cd "$D" && git mv hooks/shared/mover.py src/mover.py )   # protected -> non-protected (leaving)
if run_precommit "$D"; then bad "6e-rename-leaving-protection-blocked" "moving a protected file OUT of protection was allowed (old path not evaluated)"; else ok "6e-rename-leaving-protection-blocked"; fi
( cd "$D" && git reset -q --hard HEAD )
( cd "$D" && git mv src/incoming.py hooks/shared/incoming.py )   # non-protected -> protected (entering)
if run_precommit "$D"; then bad "6f-rename-entering-protection-blocked" "renaming a file INTO protection was allowed (new path not evaluated)"; else ok "6f-rename-entering-protection-blocked"; fi
rm -rf "$D"

# 6g. NON-protected delete/rename PASSES without any approval (no over-blocking).
D="$(new_repo)"
echo "app" > "$D/src/app.py"; ( cd "$D" && git add -A && git commit -qm 'seed app' )
( cd "$D" && git rm -q src/app.py )
if run_precommit "$D"; then ok "6g-nonprotected-delete-passes"; else bad "6g-nonprotected-delete-passes" "a non-protected delete was blocked"; fi
( cd "$D" && git reset -q --hard HEAD && git mv src/app.py src/app2.py )
if run_precommit "$D"; then ok "6g-nonprotected-rename-passes"; else bad "6g-nonprotected-rename-passes" "a non-protected rename was blocked"; fi
rm -rf "$D"

# 6h. SINGLE-USE not weakened by T23: a delete-approval must NOT authorize a later,
#      unrelated protected EDIT (the staged digest changes -> still DENIES).
D="$(new_repo)"
echo "print('gone')" > "$D/hooks/shared/gone.py"; ( cd "$D" && git add -A && git commit -qm 'seed gone' )
( cd "$D" && git rm -q hooks/shared/gone.py && bash hooks/local/write-bootstrap-approval.sh >/dev/null 2>&1 && git commit -qm 'chore: rm gone' )
# Leave the artifact in place; stage an UNRELATED protected edit.
printf '\n# unrelated\n' >> "$D/policies/protected-paths.yml"
( cd "$D" && git add policies/protected-paths.yml )
if run_precommit "$D"; then bad "6h-delete-approval-single-use" "a stale delete-approval acted as a STANDING bypass for an unrelated protected edit"; else ok "6h-delete-approval-single-use"; fi
rm -rf "$D"

# ---- 5. UNIQUE MANAGED MARKER (T11): a custom hook whose header MENTIONS the words
#         "Fusebase Flow" (in a comment) but carries NO unique managed marker must be
#         treated as CUSTOM — PRESERVED + backed up, never silently clobbered. The old
#         generic-substring detector clobbered such a hook; the unique marker fixes it. ----
D="$(new_repo)"
# A hand-written custom hook that references Fusebase Flow in a comment (NO unique marker).
printf '%s\n' "#!/bin/sh" "# my project hook — integrates with Fusebase Flow conventions" "echo mentions-fusebase-flow-but-custom" > "$D/.git/hooks/pre-commit"
chmod +x "$D/.git/hooks/pre-commit"
( cd "$D" && bash hooks/local/install-git-hooks.sh >/dev/null 2>&1 || true )
if grep -q mentions-fusebase-flow-but-custom "$D/.git/hooks/pre-commit"; then ok "5-fusebase-mentioning-custom-hook-preserved"; else bad "5-fusebase-mentioning-custom-hook-preserved" "a custom hook that merely mentions 'Fusebase Flow' was silently clobbered (generic-substring false positive)"; fi
if ls "$D"/.git/hooks/pre-commit.pre-flow-* >/dev/null 2>&1; then ok "5-fusebase-mentioning-custom-hook-backed-up"; else bad "5-fusebase-mentioning-custom-hook-backed-up" "no backup of the Fusebase-mentioning custom hook was written"; fi
# A genuine Flow hook (unique marker) refreshes in place — no spurious backup skip.
cp "$ROOT/hooks/git/pre-commit" "$D/.git/hooks/pre-commit"
( cd "$D" && bash hooks/local/install-git-hooks.sh >/dev/null 2>&1 || true )
if head -5 "$D/.git/hooks/pre-commit" | grep -qF "fusebase-flow-managed-hook:"; then ok "5-genuine-flow-hook-refreshed-by-unique-marker"; else bad "5-genuine-flow-hook-refreshed-by-unique-marker" "a genuine unique-marker Flow hook was not refreshed in place"; fi
rm -rf "$D"

# ---- 7. IMPORT FAIL-CLOSED (T25 BLOCKER): §3 used to `except Exception: sys.exit(0)`
#         — a fail-OPEN. If path_policy can't load (a missing dep like PyYAML, a broken/
#         tampered module, a syntax error introduced in the SAME commit), the entire FR-07
#         protected-path check was silently skipped (exit 0) and the protected edit
#         committed unguarded. A security control must FAIL CLOSED: the pre-commit must
#         EXIT NONZERO (block) + name the failure, never wave the edit through. We force a
#         deterministic import failure (independent of whether PyYAML is installed) by
#         replacing path_policy.py in this throwaway repo with a module that raises on
#         import, then staging a PROTECTED edit. RED (old code exits 0) -> GREEN (exits 1). ----
D="$(new_repo)"
# Overwrite the copied path_policy.py with a shim that raises on import (simulates a
# missing dep / broken module). Isolated to this throwaway repo — no other test sees it.
cat > "$D/hooks/shared/path_policy.py" <<'PYSHIM'
raise ImportError("simulated missing dependency (T25 import-fail-closed test shim)")
PYSHIM
# Stage a fusebase_flow_internals protected edit (policies/*.yml).
printf '\n# import-fail edit\n' >> "$D/policies/protected-paths.yml"
( cd "$D" && git add policies/protected-paths.yml )
# Capture stderr to assert the diagnostic is emitted (not a silent skip).
IMPORT_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
IMPORT_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || IMPORT_RC=$?
if [ "$IMPORT_RC" -ne 0 ]; then ok "7-import-error-fails-closed (pre-commit BLOCKS, exit $IMPORT_RC)"; else bad "7-import-error-fails-closed" "path_policy import error left FR-07 fail-OPEN — pre-commit exited 0 and the protected edit was NOT blocked"; fi
if echo "$IMPORT_ERR" | grep -qiE "FR-07|could not load|import"; then ok "7-import-error-diagnostic-emitted"; else bad "7-import-error-diagnostic-emitted" "no stderr diagnostic naming the import failure (operator can't diagnose)"; fi
rm -rf "$D"

# ---- 8. PYTHON3-ABSENT NO-SILENT-SKIP (T25): §3's outer gate used to silently skip
#         FR-07 when python3 was unavailable AND changes were staged. That is a quiet
#         hole — a protected edit committing with no enforcement and no message. The fix
#         emits a LOUD stderr WARNING (python3 required to enforce FR-07) so the gap is
#         visible; it does NOT hard-block (a python3-less env must still be able to
#         commit; §2's secret scan already gates on `command -v python3`). We mask python3
#         by building a PATH that drops every dir containing a python3/python executable
#         (git/bash/grep/sed stay resolvable), stage a protected edit, and assert the
#         hook emits the WARN and does NOT exit 0 SILENTLY (a bare silent skip is the bug). ----
D="$(new_repo)"
# Build a python-free PATH: keep every PATH dir that does NOT contain python3/python.
NOPY_PATH=""
_ifs_save="$IFS"; IFS=':'
for _d in $PATH; do
  [ -n "$_d" ] || continue
  if [ -x "$_d/python3" ] || [ -x "$_d/python" ] || [ -x "$_d/python3.exe" ] || [ -x "$_d/python.exe" ]; then continue; fi
  NOPY_PATH="${NOPY_PATH:+$NOPY_PATH:}$_d"
done
IFS="$_ifs_save"
# Sanity: with the curated PATH, python3 must be gone but bash/git still present.
if PATH="$NOPY_PATH" command -v python3 >/dev/null 2>&1; then
  bad "8-python3-mask-precondition" "could not mask python3 from PATH for the test (python3 still resolvable)"
else
  printf '\n# python3-absent edit\n' >> "$D/policies/protected-paths.yml"
  ( cd "$D" && git add policies/protected-paths.yml )
  NOPY_ERR="$( ( cd "$D" && PATH="$NOPY_PATH" bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
  NOPY_RC=0; ( cd "$D" && PATH="$NOPY_PATH" bash hooks/git/pre-commit >/dev/null 2>&1 ) || NOPY_RC=$?
  # Assert a LOUD warning was emitted — NOT a silent exit-0 with no message about FR-07.
  if echo "$NOPY_ERR" | grep -qiE "python3|FR-07"; then ok "8-python3-absent-loud-warn (stderr names the un-enforceable FR-07 check; not a silent skip)"; else bad "8-python3-absent-loud-warn" "python3-absent path emitted NO warning — FR-07 silently skipped with no operator signal"; fi
fi
rm -rf "$D"

finish
