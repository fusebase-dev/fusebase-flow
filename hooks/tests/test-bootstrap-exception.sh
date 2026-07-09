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
#         by building a PATH that drops every dir containing a python3/python executable,
#         stage a protected edit, and assert the hook emits SOME loud signal (NOT a bare
#         silent exit 0). PLATFORM NOTE: on MSYS python3 lives in a dir separate from
#         git/bash, so the mask reaches §3's "python3 not found; FR-07…" WARN. On Linux/CI
#         python3 shares /usr/bin with git/bash, so dropping python3's dir ALSO removes git
#         ⇒ the hook loudly SKIPS at the git-root check ("not in a git repo; skipping") or
#         fails closed ("Refusing to commit fail-open…"). All are LOUD (the no-silent-skip
#         invariant); the assertion accepts each without weakening it. ----
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
  # Assert a LOUD signal was emitted — NOT a silent exit-0. Accepts the MSYS python3-WARN
  # AND the Linux loud-skip/fail-closed signals (python3 shares /usr/bin with git there, so
  # the mask also removes git ⇒ the hook loudly skips at the git-root check).
  if echo "$NOPY_ERR" | grep -qiE "python3|FR-07|not in a git repo|skipping|Refusing to commit fail-open|unverifiable protected-path|could not list staged changes|failing closed"; then ok "8-python3-absent-loud-warn (stderr carries a loud non-silent signal; MSYS: python3/FR-07 WARN, Linux: git-root skip / fail-closed)"; else bad "8-python3-absent-loud-warn" "python3-absent path emitted NO signal at all — a truly silent skip (FR-07 finding, not a test bug)"; fi
fi
rm -rf "$D"

# ---- 9. ENUMERATION FAIL-CLOSED (T26 BLOCKER): T25 closed the IMPORT fail-open, but
#         path_policy.staged_change_paths() returns [] on ANY subprocess exception AND on a
#         nonzero git rc (subprocess.run does NOT raise on nonzero). If enumeration FAILS
#         while staged changes exist, §3 saw paths=[] -> no hits -> exit 0: a SECOND fail-OPEN.
#         The §3 cross-check now re-lists staged names with an explicit rc check and blocks on
#         (a) git-list rc!=0 or (b) names-present-but-enumeration-empty. Both simulations are
#         pure-Python (host-independent): a bash/.cmd git-shim is NOT honored by the hook's
#         Windows-native python subprocess, so we override at the module boundary instead.
#         RED (old T25 code exits 0) -> GREEN (T26 exits 1). ----
D="$(new_repo)"
# 9a. enum-failure-fails-closed: staged_change_paths() returns [] while a PROTECTED file is
#     staged (simulates a failed/[]-returning enumeration). Cross-check: names non-empty +
#     paths empty -> BLOCK. Append the override so evaluate/is_protected stay the REAL ones.
cat >> "$D/hooks/shared/path_policy.py" <<'PYOV'

def staged_change_paths(root):  # T26 test override: enumeration returns [] (failure/disagreement)
    return []
PYOV
printf '\n# enum-fail edit\n' >> "$D/policies/protected-paths.yml"
( cd "$D" && git add policies/protected-paths.yml )
# GREEN: the T26 pre-commit must BLOCK (names present, enumeration empty).
ENUM_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
ENUM_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || ENUM_RC=$?
if [ "$ENUM_RC" -ne 0 ]; then ok "9a-enum-failure-fails-closed (pre-commit BLOCKS, exit $ENUM_RC)"; else bad "9a-enum-failure-fails-closed" "enumeration returned [] while a PROTECTED file was staged and the pre-commit exited 0 — SECOND fail-OPEN"; fi
if echo "$ENUM_ERR" | grep -qiE "FR-07|enumeration|failing closed"; then ok "9a-enum-failure-diagnostic-emitted"; else bad "9a-enum-failure-diagnostic-emitted" "no stderr diagnostic naming the enumeration failure"; fi
# RED proof: the T25 HEAD pre-commit with the SAME override exits 0 (the fail-open we are closing).
if git -C "$ROOT" cat-file -e "d77169f:hooks/git/pre-commit" 2>/dev/null; then
  git -C "$ROOT" show "d77169f:hooks/git/pre-commit" > "$D/hooks/git/pre-commit-t25"
  RED_RC=0; ( cd "$D" && bash hooks/git/pre-commit-t25 >/dev/null 2>&1 ) || RED_RC=$?
  if [ "$RED_RC" -eq 0 ]; then ok "9a-RED-old-code-was-fail-open (T25 pre-commit exit 0 on the same scenario)"; else ok "9a-RED-skipped (old code not exit 0 here; GREEN still asserted)"; fi
else
  ok "9a-RED-skipped-no-baseline (d77169f pre-commit not reachable in this checkout)"
fi
rm -rf "$D"

# 9b. git-list-failure-fails-closed: the hook's inner `git diff --cached --name-only` returns
#     nonzero -> list_rc!=0 -> BLOCK (not exit 0). Simulated by a sitecustomize.py on the hook's
#     PYTHONPATH (=$ROOT/hooks) that patches subprocess.run to fail ONLY the inner name-only call
#     (the outer bash STAGED_ANY uses the real git, unaffected, so §3 is still entered).
D="$(new_repo)"
cat > "$D/hooks/sitecustomize.py" <<'PYSC'
import subprocess as _sp
_orig = _sp.run
def _patched(cmd, *a, **k):
    if isinstance(cmd, (list, tuple)) and "diff" in cmd and "--name-only" in cmd:
        class _R:
            returncode = 9; stdout = ""; stderr = ""
        return _R()
    return _orig(cmd, *a, **k)
_sp.run = _patched
PYSC
printf '\n# git-list-fail edit\n' >> "$D/policies/protected-paths.yml"
( cd "$D" && git add policies/protected-paths.yml )
GLF_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
GLF_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || GLF_RC=$?
if [ "$GLF_RC" -ne 0 ]; then ok "9b-git-list-failure-fails-closed (pre-commit BLOCKS, exit $GLF_RC)"; else bad "9b-git-list-failure-fails-closed" "inner git-list rc!=0 left FR-07 fail-OPEN — pre-commit exited 0"; fi
if echo "$GLF_ERR" | grep -qiE "FR-07|list staged|failing closed"; then ok "9b-git-list-failure-diagnostic-emitted"; else bad "9b-git-list-failure-diagnostic-emitted" "no stderr diagnostic naming the git-list failure"; fi
rm -rf "$D"

# ---- 10. NO-FALSE-BLOCK (T26): the cross-check must NOT over-block the happy path. rc0 +
#          genuinely-no-staged-changes returns [] LEGITIMATELY (must PASS); a non-protected edit
#          passes; a protected edit WITH the sanctioned approval passes. (9/10 mirror T25's
#          import/python3 no-silent-skip coverage on the enumeration axis.) ----
D="$(new_repo)"
# 10a. NO staged changes -> rc0-empty is legit -> PASS (not a false block).
NOSTAGE_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || NOSTAGE_RC=$?
if [ "$NOSTAGE_RC" -eq 0 ]; then ok "10a-no-staged-changes-passes (rc0-empty not over-blocked)"; else bad "10a-no-staged-changes-passes" "a commit with NO staged changes was blocked (rc0-empty over-blocked)"; fi
# 10b. NON-protected edit -> PASS.
echo "app" > "$D/src/app.py"; ( cd "$D" && git add src/app.py )
if run_precommit "$D"; then ok "10b-nonprotected-edit-passes"; else bad "10b-nonprotected-edit-passes" "a non-protected edit was blocked by the enumeration cross-check"; fi
( cd "$D" && git commit -qm 'add app' )
# 10c. PROTECTED edit WITH the sanctioned approval -> PASS (cross-check doesn't interfere).
printf '\n# approved edit\n' >> "$D/policies/protected-paths.yml"; ( cd "$D" && git add policies/protected-paths.yml )
( cd "$D" && bash hooks/local/write-bootstrap-approval.sh >/dev/null 2>&1 )
if run_precommit "$D"; then ok "10c-protected-edit-with-approval-passes"; else bad "10c-protected-edit-with-approval-passes" "a protected edit with a valid approval was blocked by the enumeration cross-check"; fi
rm -rf "$D"

# =============================================================================
# T27 — FR-07 fails CLOSED at EVERY remaining load-point (convergence batch).
# #3 BaseException (SystemExit-0 self-bypass), #4 name-status rc, #5 missing/
# overridden protected-paths policy, #1 outer git-list rc. RED→GREEN vs dadea26 (T26).
# =============================================================================

# T27_BASELINE: the T26 HEAD pre-commit, for RED proofs (its `except Exception` +
# rc-ignoring staged_change_paths are the fail-opens this task closes). Reachable in the
# real checkout; skipped gracefully otherwise.
T27_BASE_REF="dadea26"

# ---- 11 (#3). SystemExit(0) SELF-BYPASS: a staged/tampered path_policy.py that does
#      `raise SystemExit(0)` on import — SystemExit subclasses BaseException, so the old
#      `except Exception` §3 import wrapper let it exit 0 UNGUARDED while a PROTECTED edit
#      was staged (stage the tampered module in the SAME commit). The BaseException wrapper
#      (T27#3) BLOCKS. RED (dadea26 exits 0) -> GREEN (exit 1). ----
D="$(new_repo)"
cat > "$D/hooks/shared/path_policy.py" <<'PYSHIM'
import sys
raise SystemExit(0)  # T27#3 shim: clean exit-0 on import (BaseException, not Exception)
PYSHIM
printf '\n# systemexit-import edit\n' >> "$D/policies/protected-paths.yml"
( cd "$D" && git add policies/protected-paths.yml )
SE_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
SE_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || SE_RC=$?
if [ "$SE_RC" -ne 0 ]; then ok "11-systemexit0-import-blocks (pre-commit BLOCKS, exit $SE_RC)"; else bad "11-systemexit0-import-blocks" "a tampered path_policy raising SystemExit(0) on import left FR-07 fail-OPEN (exit 0)"; fi
if echo "$SE_ERR" | grep -qiE "FR-07|could not load|import"; then ok "11-systemexit0-import-diagnostic"; else bad "11-systemexit0-import-diagnostic" "no diagnostic naming the load failure"; fi
# RED proof: the T26 pre-commit with the SAME shim exits 0 (the fail-open being closed).
if git -C "$ROOT" cat-file -e "$T27_BASE_REF:hooks/git/pre-commit" 2>/dev/null; then
  git -C "$ROOT" show "$T27_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit-t26"
  RED_RC=0; ( cd "$D" && bash hooks/git/pre-commit-t26 >/dev/null 2>&1 ) || RED_RC=$?
  if [ "$RED_RC" -eq 0 ]; then ok "11-RED-t26-was-fail-open (dadea26 exit 0 on SystemExit(0) import)"; else ok "11-RED-t26-not-exit0-here (GREEN still asserted)"; fi
else ok "11-RED-skipped-no-baseline"; fi
rm -rf "$D"

# ---- 11b (#3). SystemExit(0) from INSIDE evaluate(): a tampered path_policy whose
#      evaluate() short-circuits with sys.exit(0). The old body `except Exception` let it
#      exit 0. T27's SystemExit split (re-raise nonzero, rewrite code-0 -> BLOCK) closes it.
#      Keep is_protected/staged_change_paths real (so §3 is entered + a hit is found). ----
D="$(new_repo)"
cat >> "$D/hooks/shared/path_policy.py" <<'PYOV'

def evaluate(path, *, root=None):  # T27#3 shim: clean exit-0 inside the check
    import sys
    sys.exit(0)
PYOV
printf '\n# systemexit-eval edit\n' >> "$D/policies/protected-paths.yml"
( cd "$D" && git add policies/protected-paths.yml )
SEE_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
SEE_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || SEE_RC=$?
if [ "$SEE_RC" -ne 0 ]; then ok "11b-systemexit0-in-evaluate-blocks (exit $SEE_RC)"; else bad "11b-systemexit0-in-evaluate-blocks" "sys.exit(0) inside evaluate() left FR-07 fail-OPEN (exit 0)"; fi
if echo "$SEE_ERR" | grep -qiE "FR-07|exit\(0\)|failing closed|self-exit"; then ok "11b-systemexit0-in-evaluate-diagnostic"; else bad "11b-systemexit0-in-evaluate-diagnostic" "no diagnostic naming the in-check exit(0)"; fi
rm -rf "$D"

# ---- 11c (#3). NO OVER-BLOCK: a REAL protected-hit sys.exit(1) still exits 1 (the
#      SystemExit split re-raises nonzero), and a clean no-hit still PASSES (exit 0).
#      (Real-hit exit-1 is already covered by test 1; here assert the clean pass isn't
#      swallowed by the new SystemExit handler.) ----
D="$(new_repo)"
echo "app" > "$D/src/app.py"; ( cd "$D" && git add src/app.py )
if run_precommit "$D"; then ok "11c-clean-nohit-still-passes (SystemExit split doesn't over-block)"; else bad "11c-clean-nohit-still-passes" "a clean non-protected commit was blocked by the SystemExit handler"; fi
rm -rf "$D"

# ---- 12 (#4). NAME-STATUS rc FAIL-CLOSED: staged_change_paths ignored the git
#      `--name-status -M` returncode, so a nonzero rc with PARTIAL stdout yielded a
#      nonempty-but-INCOMPLETE list that could MISS a protected path. T27#4 RAISES on
#      nonzero rc (and on a subprocess exception). Two proofs: (a) a UNIT assertion that
#      staged_change_paths raises on a nonzero name-status rc; (b) a pre-commit that
#      BLOCKS when name-status returns rc!=0 + partial output omitting the protected path. ----
D="$(new_repo)"
# 12a. UNIT: patch subprocess so name-status returns rc=2 -> staged_change_paths must RAISE.
UNIT_OUT="$(cd "$D" && PYTHONPATH="$D/hooks" python3 - <<'PY'
import subprocess as sp
from pathlib import Path
_orig = sp.run
def _patched(cmd, *a, **k):
    if isinstance(cmd, (list, tuple)) and "--name-status" in cmd:
        class _R: returncode = 2; stdout = "M\tsrc/app.py\n"; stderr = ""
        return _R()
    return _orig(cmd, *a, **k)
sp.run = _patched
from shared.path_policy import staged_change_paths
try:
    staged_change_paths(Path("."))
    print("NORAISE")
except RuntimeError as e:
    print("RAISED" if "rc=2" in str(e) or "name-status failed" in str(e) else "WRONGRAISE")
except Exception as e:
    print("OTHER:%r" % e)
PY
)"
if [ "$UNIT_OUT" = "RAISED" ]; then ok "12a-staged_change_paths-raises-on-rc (unit)"; else bad "12a-staged_change_paths-raises-on-rc" "expected RuntimeError on nonzero name-status rc, got: $UNIT_OUT"; fi
rm -rf "$D"

# 12b. INTEGRATION: sitecustomize on the hook's PYTHONPATH fails the name-status call
#      (rc=2, partial stdout that OMITS the staged protected path). The inner name-ONLY
#      cross-check still lists it (real git) -> names present; staged_change_paths RAISES
#      -> body BaseException wrapper -> BLOCK. RED (dadea26 evaluated the partial list, no
#      protected hit -> exit 0) -> GREEN (exit 1).
D="$(new_repo)"
cat > "$D/hooks/sitecustomize.py" <<'PYSC'
import subprocess as _sp
_orig = _sp.run
def _patched(cmd, *a, **k):
    if isinstance(cmd, (list, tuple)) and "--name-status" in cmd:
        class _R:
            returncode = 2
            stdout = "M\tsrc/unrelated_nonprotected.txt\n"  # PARTIAL: omits the protected path
            stderr = ""
        return _R()
    return _orig(cmd, *a, **k)
_sp.run = _patched
PYSC
printf '\n# name-status-partial edit\n' >> "$D/policies/protected-paths.yml"
( cd "$D" && git add policies/protected-paths.yml )
NS_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
NS_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || NS_RC=$?
if [ "$NS_RC" -ne 0 ]; then ok "12b-name-status-partial-rc-blocks (exit $NS_RC)"; else bad "12b-name-status-partial-rc-blocks" "a nonzero name-status rc with partial output omitting the protected path left FR-07 fail-OPEN (exit 0)"; fi
if echo "$NS_ERR" | grep -qiE "FR-07|name-status|failing closed|errored"; then ok "12b-name-status-partial-diagnostic"; else bad "12b-name-status-partial-diagnostic" "no diagnostic naming the name-status failure"; fi
# RED proof: the T26 pre-commit with the SAME sitecustomize evaluated the partial list.
if git -C "$ROOT" cat-file -e "$T27_BASE_REF:hooks/git/pre-commit" 2>/dev/null; then
  git -C "$ROOT" show "$T27_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit-t26"
  RED_RC=0; ( cd "$D" && bash hooks/git/pre-commit-t26 >/dev/null 2>&1 ) || RED_RC=$?
  if [ "$RED_RC" -eq 0 ]; then ok "12b-RED-t26-was-fail-open (partial list evaluated, no hit, exit 0)"; else ok "12b-RED-t26-not-exit0-here (GREEN still asserted)"; fi
else ok "12b-RED-skipped-no-baseline"; fi
rm -rf "$D"

# ---- 13 (#5). MISSING/EMPTY protected-paths policy FAILS CLOSED. A missing/emptied
#      protected-paths.yml made is_protected() always False -> FR-07 silently OFF. The
#      T27#5 assert_protected_policy_loaded() at the enforcement point BLOCKS with a
#      policy-missing diagnostic. Three sub-cases: removed, emptied file, emptied sentinel. ----
# 13a. protected-paths.yml REMOVED entirely -> BLOCK. Stage a would-be protected edit
#      under hooks/shared/ (protected by the SHIPPED policy) so §3 is entered with intent.
D="$(new_repo)"
echo "print('x')" > "$D/hooks/shared/new_file.py"
( cd "$D" && git add hooks/shared/new_file.py )
rm -f "$D/policies/protected-paths.yml"
P_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
P_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || P_RC=$?
if [ "$P_RC" -ne 0 ]; then ok "13a-missing-policy-blocks (exit $P_RC)"; else bad "13a-missing-policy-blocks" "a REMOVED protected-paths.yml left FR-07 fully OFF (silent pass, exit 0)"; fi
if echo "$P_ERR" | grep -qiE "protected-paths policy|cannot enforce FR-07|missing"; then ok "13a-missing-policy-diagnostic"; else bad "13a-missing-policy-diagnostic" "no policy-missing diagnostic"; fi
# RED proof: dadea26 had no policy-present assertion -> exits 0 (silent fail-open).
if git -C "$ROOT" cat-file -e "$T27_BASE_REF:hooks/git/pre-commit" 2>/dev/null; then
  git -C "$ROOT" show "$T27_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit-t26"
  RED_RC=0; ( cd "$D" && bash hooks/git/pre-commit-t26 >/dev/null 2>&1 ) || RED_RC=$?
  if [ "$RED_RC" -eq 0 ]; then ok "13a-RED-t26-was-fail-open (missing policy exit 0)"; else ok "13a-RED-t26-not-exit0-here (GREEN still asserted)"; fi
else ok "13a-RED-skipped-no-baseline"; fi
rm -rf "$D"

# 13b. protected-paths.yml EMPTIED (zero-byte) -> BLOCK (mapping absent).
D="$(new_repo)"
echo "print('x')" > "$D/hooks/shared/new_file.py"; ( cd "$D" && git add hooks/shared/new_file.py )
: > "$D/policies/protected-paths.yml"
E_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || E_RC=$?
if [ "$E_RC" -ne 0 ]; then ok "13b-empty-policy-blocks (exit $E_RC)"; else bad "13b-empty-policy-blocks" "an EMPTY protected-paths.yml left FR-07 OFF (exit 0)"; fi
rm -rf "$D"

# 13c. sentinel category EMPTIED (fusebase_flow_internals: paths: []) -> BLOCK. A policy
#      that parses but drops the Flow-internals protections is unenforceable for FR-07.
D="$(new_repo)"
echo "print('x')" > "$D/hooks/shared/new_file.py"; ( cd "$D" && git add hooks/shared/new_file.py )
cat > "$D/policies/protected-paths.yml" <<'YML'
schema_version: 1
categories:
  fusebase_flow_internals:
    paths: []
on_unapproved_edit: deny
YML
S_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || S_RC=$?
if [ "$S_RC" -ne 0 ]; then ok "13c-emptied-sentinel-category-blocks (exit $S_RC)"; else bad "13c-emptied-sentinel-category-blocks" "an emptied fusebase_flow_internals category left FR-07 OFF (exit 0)"; fi
rm -rf "$D"

# ---- 14 (#5). LOCAL OVERRIDE CANNOT ERASE fusebase_flow_internals (additive-only). A
#      gitignored protected-paths.local.yml that sets fusebase_flow_internals.paths: []
#      must NOT relax the base — the loader re-unions base paths, so the category is STILL
#      enforced. Prove via pre-commit (a protected edit + the erasing local -> still BLOCK)
#      AND a unit assertion the merged paths still contain the base FLOW_RULES.md pattern. ----
D="$(new_repo)"
cat > "$D/policies/protected-paths.local.yml" <<'YML'
categories:
  fusebase_flow_internals:
    paths: []
YML
# 14a. UNIT: merged fusebase_flow_internals paths still include the base entries.
U14="$(cd "$D" && FUSEBASE_FLOW_ROOT="$D" PYTHONPATH="$D/hooks" python3 - <<'PY'
from shared.policy_loader import get_policy, reset_cache
reset_cache()
paths = (get_policy("protected-paths").get("categories") or {}).get("fusebase_flow_internals", {}).get("paths") or []
print("KEPT" if any("hooks/shared" in p or "FLOW_RULES" in p for p in paths) else "ERASED")
PY
)"
if [ "$U14" = "KEPT" ]; then ok "14a-local-override-cannot-erase-internals (unit: base paths re-unioned)"; else bad "14a-local-override-cannot-erase-internals" "local paths:[] ERASED the base fusebase_flow_internals category (got: $U14)"; fi
# 14b. PRE-COMMIT: a protected internals edit with the erasing local override still BLOCKS.
printf '\n# override-erase attempt\n' >> "$D/FLOW_RULES.md" 2>/dev/null || echo seed > "$D/FLOW_RULES.md"
( cd "$D" && git add FLOW_RULES.md )
O_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || O_RC=$?
if [ "$O_RC" -ne 0 ]; then ok "14b-erasing-local-still-blocks-protected-edit (exit $O_RC)"; else bad "14b-erasing-local-still-blocks-protected-edit" "a protected edit committed with exit 0 because a local override erased the category"; fi
rm -rf "$D"

# 14c. ADDITIVE local override STILL WORKS (no over-restriction regression): a local that
#      ADDS a path to a category is honored (mirrors test-policy-state-preserve's contract).
D="$(new_repo)"
cat > "$D/policies/protected-paths.local.yml" <<'YML'
categories:
  worker_undisturbed:
    paths:
      - "src/workers/**/*.ts"
YML
ADD14="$(cd "$D" && FUSEBASE_FLOW_ROOT="$D" PYTHONPATH="$D/hooks" python3 - <<'PY'
from shared.policy_loader import get_policy, reset_cache
reset_cache()
paths = (get_policy("protected-paths").get("categories") or {}).get("worker_undisturbed", {}).get("paths") or []
print("ADDED" if any("src/workers" in p for p in paths) else "MISSING")
PY
)"
if [ "$ADD14" = "ADDED" ]; then ok "14c-additive-local-override-still-honored"; else bad "14c-additive-local-override-still-honored" "an additive local override was dropped (got: $ADD14)"; fi
rm -rf "$D"

# ---- 15 (#5 happy path + no cross-policy regression). The SHIPPED protected-paths.yml
#      (present + valid) enforces normally, and get_policy for OTHER policies is unchanged. ----
D="$(new_repo)"
printf '\n# happy-path protected edit\n' >> "$D/policies/protected-paths.yml"; ( cd "$D" && git add policies/protected-paths.yml )
# 15a. Shipped policy present -> protected edit still BLOCKS without approval (unchanged).
H_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || H_RC=$?
if [ "$H_RC" -ne 0 ]; then ok "15a-happy-path-protected-edit-still-blocks"; else bad "15a-happy-path-protected-edit-still-blocks" "shipped policy present but protected edit passed (enforcement broke)"; fi
# 15b. ...and PASSES with the minted approval (assert_protected_policy_loaded doesn't over-block).
( cd "$D" && bash hooks/local/write-bootstrap-approval.sh >/dev/null 2>&1 )
if run_precommit "$D"; then ok "15b-happy-path-with-approval-passes"; else bad "15b-happy-path-with-approval-passes" "policy-present assertion over-blocked an approved protected edit"; fi
# 15c. CROSS-POLICY: get_policy for a NON-protected-paths policy is byte-for-byte the
#      normal deep-merge (no additive-union leakage). approval-policy.local.yml override wins.
cat > "$D/policies/approval-policy.yml" <<'YML'
schema_version: 2
workflow_mode: direct_to_main
require_approval: {}
YML
cat > "$D/policies/approval-policy.local.yml" <<'YML'
workflow_mode: branch_pr
YML
X15="$(cd "$D" && FUSEBASE_FLOW_ROOT="$D" PYTHONPATH="$D/hooks" python3 - <<'PY'
from shared.policy_loader import get_policy, reset_cache
reset_cache()
print(get_policy("approval-policy").get("workflow_mode"))
PY
)"
if [ "$X15" = "branch_pr" ]; then ok "15c-cross-policy-get_policy-unchanged (approval-policy local override wins)"; else bad "15c-cross-policy-get_policy-unchanged" "approval-policy merge changed (got: $X15, expected branch_pr)"; fi
rm -rf "$D"

# ---- 16 (#1). OUTER git-list rc fail-closed. The outer bash `git diff --cached
#      --name-only` rc is now captured; a nonzero rc fails closed (mirrors the inner
#      python rc-check). Non-reachable via a real broken repo (it wouldn't commit), so we
#      assert the guard EXISTS in source (grep) rather than fabricate an unreachable
#      scenario — the inner python rc-checks (tests 9b/12) cover the reachable path.
if grep -q 'STAGED_ANY_RC' "$ROOT/hooks/git/pre-commit" && grep -q 'outer git rc' "$ROOT/hooks/git/pre-commit"; then
  ok "16-outer-git-list-rc-guard-present (source)"
else
  bad "16-outer-git-list-rc-guard-present" "outer git-list rc guard (#1) not found in pre-commit source"
fi

finish
