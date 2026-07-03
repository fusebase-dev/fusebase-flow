#!/usr/bin/env bash
# Fusebase Flow — trusted-HEAD FR-07 enforcer + tool-time policy-assert tests (T28).
# Split out of test-bootstrap-exception.sh along the self-protecting-control seam
# (FR-25 module-size ratchet). Companion to that file; shares the same throwaway-repo
# harness (new_repo) and the REAL path_policy / pre-commit / pre_tool_use / hook scripts.
#
# Proves the two self-protecting-control load-points fail closed:
#   #1 pre-commit §3 runs FR-07 from the COMMITTED (HEAD) enforcer for staged
#      enforcement-code/policy changes, so a staged tampered-but-LYING path_policy
#      cannot self-pass its own gate; the common path + legit-approved flow + the
#      first-adoption bootstrap edge are preserved.
#   #7 pre_tool_use.py asserts the protected-paths policy is present before
#      evaluate_path(), so a missing/empty policy DENIES a protected edit at TOOL time.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: trusted-enforcer <name>" / "FAIL: trusted-enforcer <name>"; exit = fail count.
# (T30 label fix, finding 7: run-tests.sh invokes this file under the `trusted-enforcer`
#  tag, so the emitted label MUST be `trusted-enforcer` — with the old `bootstrap-exception`
#  tag the PASS rows were never counted by run_shell_phase's `^PASS: trusted-enforcer ` grep.
#  Assertion NAMES keep the 17.. numbering so they still read continuously with the
#  companion test-bootstrap-exception.sh, which owns 1..16 under its own tag.)

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: trusted-enforcer $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: trusted-enforcer $1 (${2:-})"; }
finish() { echo "[test-trusted-enforcer] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: trusted-enforcer skipped-no-python3"; pass=$((pass + 1)); finish; }

# new_repo: a throwaway git repo carrying the Flow bits these tests exercise (same as the
# companion test-bootstrap-exception.sh). The seed commit contains ONLY seed.txt — the
# enforcer files live in the working tree but NOT in HEAD; head_with_enforcer (below)
# commits them into HEAD when a test needs the TRUSTED-HEAD path to fire.
new_repo() {
  local D; D="$(mktemp -d)"
  mkdir -p "$D/hooks/shared" "$D/hooks/git" "$D/hooks/local" "$D/policies" "$D/state/approvals" "$D/src"
  cp "$ROOT/hooks/shared/path_policy.py"   "$D/hooks/shared/"
  cp "$ROOT/hooks/shared/policy_loader.py" "$D/hooks/shared/"
  cp "$ROOT/hooks/shared/"*.py             "$D/hooks/shared/" 2>/dev/null || true
  : > "$D/hooks/shared/__init__.py"
  cp "$ROOT/policies/protected-paths.yml"  "$D/policies/"
  cp "$ROOT/hooks/git/pre-commit"          "$D/hooks/git/"
  cp "$ROOT/hooks/local/install-git-hooks.sh"     "$D/hooks/local/"
  cp "$ROOT/hooks/local/write-bootstrap-approval.sh" "$D/hooks/local/"
  ( cd "$D" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config core.autocrlf false \
      && echo seed > seed.txt && git add seed.txt && git commit -qm seed )
  echo "$D"
}
run_precommit() { ( cd "$1" && bash hooks/git/pre-commit >/dev/null 2>&1 ); }

# =============================================================================
# T28 — self-protecting-control load-points fail closed.
#   #1 pre-commit §3 runs FR-07 from the TRUSTED (HEAD) enforcer for staged
#      enforcement-code/policy changes -> a staged tampered-but-LYING path_policy
#      can no longer self-pass its own gate.
#   #7 pre_tool_use.py asserts the protected-paths policy is present BEFORE
#      evaluate_path() -> a missing/empty policy DENIES a protected edit at TOOL
#      time (fail closed), instead of waving it through.
# RED→GREEN vs 38be1ef (T27 HEAD): its working-tree enforcer + no tool-time assert
# are the fail-opens this task closes.
# =============================================================================

# T28_BASELINE: the T27 HEAD pre-commit / handler, for RED proofs. Reachable in the
# real checkout; skipped gracefully otherwise.
T28_BASE_REF="38be1ef"

# lying_path_policy PATH: write a path_policy.py that IMPORTS cleanly but LIES —
# is_protected()/evaluate() claim nothing is protected. staged_change_paths stays real
# so §3 is entered with the real staged set (the tamper only defeats classification).
lying_path_policy() {
  cat > "$1" <<'LIE'
from dataclasses import dataclass
@dataclass
class PathDecision:
    path: str
    protected: bool = False
    category = None
    has_exception: bool = False
    decision: str = "allow"
    reason: str = ""
    rule_id: str = "FR-07"
def assert_protected_policy_loaded(root=None):
    return None
def is_protected(path):
    return (False, None)
def has_active_exception(path, root=None, *, category=None):
    return False
def staged_change_paths(root):
    import subprocess
    p = subprocess.run(["git", "diff", "--cached", "--name-only"],
                       capture_output=True, text=True, cwd=str(root))
    return [n for n in p.stdout.splitlines() if n]
def evaluate(path, *, root=None):
    return PathDecision(path=path)
def compute_staged_tree_digest(paths, root):
    return ""
def evaluate_many(paths, *, root=None):
    return [evaluate(p, root=root) for p in paths]
LIE
}

# head_with_enforcer: new_repo's seed commit contains ONLY seed.txt (the enforcer files
# live in the working tree but NOT in HEAD). The TRUSTED-HEAD path (#1) only fires when
# HEAD CONTAINS the enforcer (an existing control being tampered); when HEAD lacks it the
# prep correctly falls back to the working tree (first-adoption bootstrap — a control that
# doesn't exist yet can't be "tampered"). So to exercise the TRUSTED path, commit the CLEAN
# enforcer + policy into HEAD first. (Tests 17/18; 19c separately covers the bootstrap edge.)
head_with_enforcer() {  # $1 = repo dir
  ( cd "$1" && git add hooks/shared/path_policy.py hooks/shared/policy_loader.py \
      hooks/shared/__init__.py policies/protected-paths.yml \
      && bash hooks/local/write-bootstrap-approval.sh >/dev/null 2>&1 \
      && git commit -qm 'seed clean enforcer into HEAD' \
      && bash hooks/local/write-bootstrap-approval.sh --consume >/dev/null 2>&1 )
}

# ---- 17 (#1). TAMPER-BLOCKS: with the CLEAN enforcer already in HEAD, stage a LYING
#      path_policy.py (imports cleanly, claims nothing protected) + a protected edit. The
#      TRUSTED HEAD enforcer runs, still sees hooks/shared/path_policy.py +
#      policies/protected-paths.yml as protected -> BLOCK. RED: the pre-T28 working-tree
#      enforcer (38be1ef) imports the LYING module and exits 0 (the lie self-passes). ----
D="$(new_repo)"
head_with_enforcer "$D"   # HEAD now carries the CLEAN enforcer -> trusted path fires.
# Now stage the tamper (a lying path_policy + a protected policy edit riding along).
lying_path_policy "$D/hooks/shared/path_policy.py"
printf '\n# tamper: protected policy edit rides along\n' >> "$D/policies/protected-paths.yml"
( cd "$D" && git add hooks/shared/path_policy.py policies/protected-paths.yml )
T17_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
T17_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || T17_RC=$?
if [ "$T17_RC" -ne 0 ]; then ok "17-tamper-lying-enforcer-blocks (trusted HEAD runs, exit $T17_RC)"; else bad "17-tamper-lying-enforcer-blocks" "a staged LYING path_policy self-passed its own gate — FR-07 disabled going forward (fail-OPEN)"; fi
if echo "$T17_ERR" | grep -qiE "protected paths edited|FR-07"; then ok "17-tamper-diagnostic-emitted"; else bad "17-tamper-diagnostic-emitted" "no FR-07 diagnostic naming the blocked protected paths"; fi
# RED proof: the pre-T28 pre-commit imports the WORKING-TREE (lying) enforcer -> exit 0.
if git -C "$ROOT" cat-file -e "$T28_BASE_REF:hooks/git/pre-commit" 2>/dev/null; then
  git -C "$ROOT" show "$T28_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit-t27"
  RED_RC=0; ( cd "$D" && bash hooks/git/pre-commit-t27 >/dev/null 2>&1 ) || RED_RC=$?
  if [ "$RED_RC" -eq 0 ]; then ok "17-RED-t27-was-fail-open (working-tree enforcer exit 0: the lie self-passed)"; else ok "17-RED-t27-not-exit0-here (GREEN still asserted)"; fi
else ok "17-RED-skipped-no-baseline (38be1ef pre-commit not reachable)"; fi
rm -rf "$D"

# ---- 18 (#1). LEGIT APPROVED enforcer edit still PASSES: a REAL path_policy.py edit
#      (not a tamper) + the sanctioned single-use bootstrap approval on disk. The trusted
#      HEAD enforcer finds the approval in the working-tree state/approvals/ and ALLOWS it.
#      (This is exactly how THIS task's own T28 commit must pass.) ----
D="$(new_repo)"
head_with_enforcer "$D"   # CLEAN enforcer in HEAD -> trusted path fires for this edit.
printf '\n# T28: a real, sanctioned comment-only edit\n' >> "$D/hooks/shared/path_policy.py"
( cd "$D" && git add hooks/shared/path_policy.py && bash hooks/local/write-bootstrap-approval.sh >/dev/null 2>&1 )
if run_precommit "$D"; then ok "18-legit-approved-enforcer-edit-passes (trusted HEAD honors the working-tree approval)"; else bad "18-legit-approved-enforcer-edit-passes" "a sanctioned, approved real path_policy edit was blocked by the trusted-HEAD path"; fi
# ...and WITHOUT the approval the SAME real edit BLOCKS (trusted HEAD still enforces).
( cd "$D" && bash hooks/local/write-bootstrap-approval.sh --consume >/dev/null 2>&1 )
if run_precommit "$D"; then bad "18-unapproved-enforcer-edit-blocks" "an UNAPPROVED real path_policy edit passed (trusted-HEAD enforcement absent)"; else ok "18-unapproved-enforcer-edit-blocks"; fi
rm -rf "$D"

# ---- 19 (#1). COMMON PATH UNCHANGED: a commit that does NOT touch the enforcer runs the
#      working-tree path exactly as before. A non-protected edit passes; a protected
#      (non-enforcer) edit without approval blocks. Trusted-HEAD dispatch must not fire. ----
D="$(new_repo)"
# 19a. non-protected edit -> PASS.
echo "app" > "$D/src/app.py"; ( cd "$D" && git add src/app.py )
if run_precommit "$D"; then ok "19a-common-nonprotected-edit-passes"; else bad "19a-common-nonprotected-edit-passes" "a plain non-protected edit was blocked (common path changed)"; fi
( cd "$D" && git commit -qm 'add app' )
# 19b. protected NON-enforcer edit (fusebase.json deployment_config) without approval -> BLOCK.
echo '{}' > "$D/fusebase.json"; ( cd "$D" && git add fusebase.json )
if run_precommit "$D"; then bad "19b-common-protected-nonenforcer-edit-blocks" "a protected deployment_config edit passed without approval (common path changed)"; else ok "19b-common-protected-nonenforcer-edit-blocks"; fi
rm -rf "$D"

# ---- 19c/d (#1). BOOTSTRAP EDGE. A fresh consumer's FIRST commit ADDS the enforcer
#      files: HEAD lacks them -> `git show HEAD:` reports "absent" -> the prep FALLS BACK
#      to the working-tree enforcer (the file being added is not a tamper). The first-add
#      still goes through the normal sanctioned flow (mint approval -> pass). A TRANSIENT
#      git error (HEAD HAS the file but show fails) is NOT bootstrap -> fail closed (asserted
#      via source: the prep distinguishes rc1=absent from any other rc, and only falls back
#      on absent — an unreachable-to-fabricate-cleanly path, like test 16). ----
# 19c. HEAD lacks path_policy.py (first-adoption). Build a repo whose seed commit has NO
#      enforcer, then stage the first-add of the whole enforcer + mint the bootstrap approval.
D="$(mktemp -d)"
mkdir -p "$D/hooks/shared" "$D/hooks/git" "$D/hooks/local" "$D/policies" "$D/state/approvals" "$D/src"
cp "$ROOT/hooks/git/pre-commit" "$D/hooks/git/"
cp "$ROOT/hooks/local/write-bootstrap-approval.sh" "$D/hooks/local/"
( cd "$D" && git init -q && git config user.email t@t.t && git config user.name t \
    && git config core.autocrlf false && echo seed > seed.txt && git add seed.txt && git commit -qm seed )
# Now ADD the enforcer files + policy for the FIRST time (HEAD has none of them).
cp "$ROOT/hooks/shared/"*.py "$D/hooks/shared/" 2>/dev/null || true
: > "$D/hooks/shared/__init__.py"
cp "$ROOT/policies/protected-paths.yml" "$D/policies/"
( cd "$D" && git add hooks/shared policies/protected-paths.yml )
# Capture stderr to confirm the fallback note fires (not a fail-closed BLOCK).
BOOT_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
if echo "$BOOT_ERR" | grep -qiE "first-adoption bootstrap|not in HEAD"; then ok "19c-bootstrap-first-add-falls-back (working-tree enforcer note emitted)"; else bad "19c-bootstrap-first-add-falls-back" "the first-add of the enforcer did NOT emit the bootstrap fallback note (may have wrongly fail-closed)"; fi
# With the sanctioned approval the first-add commit PASSES (normal WS1b flow through fallback).
( cd "$D" && bash hooks/local/write-bootstrap-approval.sh >/dev/null 2>&1 )
if run_precommit "$D"; then ok "19c-bootstrap-first-add-with-approval-passes"; else bad "19c-bootstrap-first-add-with-approval-passes" "the sanctioned first-add of the enforcer was blocked (bootstrap broken)"; fi
rm -rf "$D"
# 19d. TRANSIENT-vs-BOOTSTRAP distinction fails CLOSED on a non-absent git error. T30 moved
#      the decision from the python prep into the SHELL: `git ls-tree HEAD -- <sentinel>` is
#      run by bash; rc0+empty => genuinely absent (bootstrap fallback), rc!=0 => transient ->
#      BLOCK (never fall back to the untrusted tree). Asserted via source (the reachable
#      bootstrap path is covered live by 19c). Anchors updated for the shell location:
#      the `_ls_rc -ne 0` transient guard + the "transient git error"/"NOT falling back"
#      diagnostic (T30 — no longer `r.returncode != 0` inside the python prep).
if grep -q 'transient git error' "$ROOT/hooks/git/pre-commit" \
   && grep -q '_ls_rc" -ne 0' "$ROOT/hooks/git/pre-commit" \
   && grep -q 'NOT falling back' "$ROOT/hooks/git/pre-commit"; then
  ok "19d-transient-error-fails-closed-not-fallback (source)"
else
  bad "19d-transient-error-fails-closed-not-fallback" "the transient-vs-bootstrap fail-closed guard (#1) not found in pre-commit source"
fi

# ---- 20 (#7). TOOL-TIME missing-policy DENIES (fail closed). pre_tool_use.py must call
#      assert_protected_policy_loaded() BEFORE evaluate_path(); a missing/empty
#      protected-paths.yml -> DENY a protected-path Edit/Write at tool time. With the
#      shipped policy present, a normal edit is unaffected. RED (pre-T28 allows) -> GREEN. ----
D="$(new_repo)"
# new_repo copies hooks/shared/*.py but not the handler — bring in pre_tool_use.py (its
# shared deps audit_logger/command_policy/secret_scanner/path_policy/policy_loader are all
# already copied by new_repo).
mkdir -p "$D/hooks/handlers"
cp "$ROOT/hooks/handlers/pre_tool_use.py" "$D/hooks/handlers/"
# run_tool CWD FILEPATH: pipe a PreToolUse Write event (cwd=".") into the handler in $D,
# print the decision. Mirrors run-tests.sh's fixture runner (cwd="." relative).
tool_decision() { # $1=file_path
  printf '{"event":"pre_tool_use","tool_name":"Write","cwd":".","tool_input":{"file_path":"%s","content":"x"}}' "$1" \
    | ( cd "$D" && python3 hooks/handlers/pre_tool_use.py ) 2>/dev/null \
    | python3 -c 'import json,sys;
try:
    print(json.load(sys.stdin).get("decision",""))
except Exception:
    print("PARSE_ERR")'
}
# 20a. protected-paths.yml MISSING -> protected-path Write DENIES.
rm -f "$D/policies/protected-paths.yml"
if [ "$(tool_decision fusebase.json)" = "deny" ]; then ok "20a-tooltime-missing-policy-denies (fail closed)"; else bad "20a-tooltime-missing-policy-denies" "a missing protected-paths.yml let a protected-path Write pass at tool time (fail-OPEN)"; fi
# 20b. protected-paths.yml EMPTY (zero-byte) -> DENY.
: > "$D/policies/protected-paths.yml"
if [ "$(tool_decision fusebase.json)" = "deny" ]; then ok "20b-tooltime-empty-policy-denies"; else bad "20b-tooltime-empty-policy-denies" "an EMPTY protected-paths.yml let a protected-path Write pass at tool time"; fi
# 20c. SHIPPED policy present -> NON-protected Write ALLOWED (no over-block).
cp "$ROOT/policies/protected-paths.yml" "$D/policies/"
if [ "$(tool_decision src/foo.py)" = "allow" ]; then ok "20c-tooltime-shipped-policy-nonprotected-allows"; else bad "20c-tooltime-shipped-policy-nonprotected-allows" "the policy-present assert over-blocked a NORMAL non-protected edit"; fi
# 20d. SHIPPED policy present -> PROTECTED Write still DENIES (normal enforcement intact).
if [ "$(tool_decision fusebase.json)" = "deny" ]; then ok "20d-tooltime-shipped-policy-protected-denies"; else bad "20d-tooltime-shipped-policy-protected-denies" "shipped policy present but a protected-path Write was allowed (enforcement broke)"; fi
# RED proof: the pre-T28 handler (38be1ef) with a MISSING policy allows the protected write.
if git -C "$ROOT" cat-file -e "$T28_BASE_REF:hooks/handlers/pre_tool_use.py" 2>/dev/null; then
  git -C "$ROOT" show "$T28_BASE_REF:hooks/handlers/pre_tool_use.py" > "$D/hooks/handlers/pre_tool_use_t27.py"
  rm -f "$D/policies/protected-paths.yml"
  RED_DEC="$(printf '{"event":"pre_tool_use","tool_name":"Write","cwd":".","tool_input":{"file_path":"fusebase.json","content":"x"}}' | ( cd "$D" && python3 hooks/handlers/pre_tool_use_t27.py ) 2>/dev/null | python3 -c 'import json,sys;
try:
    print(json.load(sys.stdin).get("decision",""))
except Exception:
    print("PARSE_ERR")')"
  if [ "$RED_DEC" = "allow" ]; then ok "20-RED-t27-was-fail-open (pre-T28 handler allowed the protected write on missing policy)"; else ok "20-RED-t27-not-allow-here (GREEN still asserted)"; fi
else ok "20-RED-skipped-no-baseline (38be1ef handler not reachable)"; fi
rm -rf "$D"

# =============================================================================
# T29 — the trusted-HEAD enforcer is now UNCONDITIONAL + no Python startup injection.
#   #1 (T29-A) UNSTAGED enforcer tamper: T28 only extracted HEAD when the staged set
#      touched the enforcer files. Editing the WORKING-TREE path_policy.py to lie
#      WITHOUT staging it, then staging only a protected file, kept T28's conditional
#      OFF -> §3 imported the lying working-tree enforcer -> exit 0. Now §3 ALWAYS
#      runs from HEAD -> the unstaged lie has no effect -> BLOCK.
#   #2 (T29-B) Python STARTUP injection: an untracked hooks/sitecustomize.py (or
#      usercustomize.py) with `os._exit(0)` was imported at interpreter startup via
#      `site` BEFORE any check -> exit 0. Closed by `python3 -S` (§2 + §3) + a
#      PYTHONPATH isolated to the trusted temp dir. Also proves `-S` did NOT disable
#      §2: a real secret staged alongside a sitecustomize still BLOCKS on the secret.
# RED→GREEN vs a12b450 (T28 HEAD): both bypasses exit 0 there.
# =============================================================================
T29_BASE_REF="a12b450"

# ---- 21 (#1 T29-A). UNSTAGED-ENFORCER-TAMPER-BLOCKS. Clean enforcer in HEAD. Tamper the
#      WORKING-TREE path_policy.py to lie (imports cleanly, "nothing protected") but do NOT
#      stage it; stage ONLY a protected file (FLOW_RULES.md). The unconditional trusted-HEAD
#      enforcer runs the CLEAN HEAD path_policy -> still sees FLOW_RULES.md protected -> BLOCK.
#      RED: a12b450's conditional stayed OFF (enforcer not staged) -> working-tree lie ran -> 0. ----
D="$(new_repo)"
head_with_enforcer "$D"   # CLEAN enforcer in HEAD -> trusted path fires unconditionally now.
lying_path_policy "$D/hooks/shared/path_policy.py"   # working tree tampered...
printf '# flow rules (protected edit)\n' > "$D/FLOW_RULES.md"
( cd "$D" && git add FLOW_RULES.md )                 # ...but ONLY the protected file is staged.
T21_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
T21_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || T21_RC=$?
if [ "$T21_RC" -ne 0 ]; then ok "21-unstaged-enforcer-tamper-blocks (trusted HEAD runs unconditionally, exit $T21_RC)"; else bad "21-unstaged-enforcer-tamper-blocks" "an UNSTAGED lying working-tree enforcer let a staged protected edit through — FR-07 fail-OPEN"; fi
if echo "$T21_ERR" | grep -qiE "protected paths edited|FR-07"; then ok "21-unstaged-tamper-diagnostic-emitted"; else bad "21-unstaged-tamper-diagnostic-emitted" "no FR-07 diagnostic on the blocked protected edit"; fi
# RED proof: the pre-T29 pre-commit's conditional stays off (enforcer not staged) -> exit 0.
if git -C "$ROOT" cat-file -e "$T29_BASE_REF:hooks/git/pre-commit" 2>/dev/null; then
  git -C "$ROOT" show "$T29_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit-t28"
  RED21=0; ( cd "$D" && bash hooks/git/pre-commit-t28 >/dev/null 2>&1 ) || RED21=$?
  if [ "$RED21" -eq 0 ]; then ok "21-RED-t28-was-fail-open (conditional OFF: unstaged lie self-passed at exit 0)"; else ok "21-RED-t28-not-exit0-here (GREEN still asserted)"; fi
else ok "21-RED-skipped-no-baseline (a12b450 pre-commit not reachable)"; fi
rm -rf "$D"

# ---- 22 (#2 T29-B). STARTUP-INJECTION-BLOCKS + SECRET-SCAN-STILL-BLOCKS-UNDER-S. An
#      untracked hooks/sitecustomize.py with `import os; os._exit(0)` is imported at python
#      startup via `site` before any check — under `-S` it does NOT run, so §3 runs and BLOCKS
#      the staged protected edit. Then the usercustomize.py variant. Then: stage a REAL secret
#      alongside the sitecustomize — §2 must STILL block on the secret (proving `-S` disabled
#      the injection, not the scan). RED: a12b450 imports the startup file -> exit 0. ----
inject_startup() { printf 'import os\nos._exit(0)\n' > "$1"; }   # $1 = target file path

D="$(new_repo)"
head_with_enforcer "$D"
# 22a. sitecustomize injection + staged protected edit -> BLOCK under -S.
inject_startup "$D/hooks/sitecustomize.py"
printf '# flow rules (protected edit)\n' > "$D/FLOW_RULES.md"
( cd "$D" && git add FLOW_RULES.md )
T22A_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || T22A_RC=$?
if [ "$T22A_RC" -ne 0 ]; then ok "22a-sitecustomize-injection-blocks (-S disables startup file; §3 runs, exit $T22A_RC)"; else bad "22a-sitecustomize-injection-blocks" "an untracked hooks/sitecustomize.py os._exit(0) short-circuited the check at startup — fail-OPEN"; fi
# RED proof: pre-T29 imports the sitecustomize at startup -> exit 0.
if git -C "$ROOT" cat-file -e "$T29_BASE_REF:hooks/git/pre-commit" 2>/dev/null; then
  git -C "$ROOT" show "$T29_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit-t28"
  RED22=0; ( cd "$D" && bash hooks/git/pre-commit-t28 >/dev/null 2>&1 ) || RED22=$?
  if [ "$RED22" -eq 0 ]; then ok "22a-RED-t28-was-fail-open (startup os._exit(0) exited the check at 0)"; else ok "22a-RED-t28-not-exit0-here (GREEN still asserted)"; fi
  rm -f "$D/hooks/git/pre-commit-t28"
else ok "22a-RED-skipped-no-baseline (a12b450 pre-commit not reachable)"; fi
rm -f "$D/hooks/sitecustomize.py"
# 22b. usercustomize.py variant -> BLOCK (site imports usercustomize too; -S disables both).
inject_startup "$D/hooks/usercustomize.py"
T22B_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || T22B_RC=$?
if [ "$T22B_RC" -ne 0 ]; then ok "22b-usercustomize-injection-blocks (-S disables usercustomize; exit $T22B_RC)"; else bad "22b-usercustomize-injection-blocks" "an untracked hooks/usercustomize.py os._exit(0) short-circuited the check — fail-OPEN"; fi
rm -f "$D/hooks/usercustomize.py"
( cd "$D" && git restore --staged FLOW_RULES.md >/dev/null 2>&1; rm -f FLOW_RULES.md )
rm -rf "$D"

# 22c. SECRET-SCAN-STILL-BLOCKS-UNDER-S: stage a REAL secret (AWS access key id) alongside a
#      sitecustomize os._exit(0). `-S` stops the injection but the secret scan (§2) still runs
#      and BLOCKS on the secret — proving `-S` did not disable §2. Needs secret-patterns.yml.
D="$(new_repo)"
cp "$ROOT/policies/secret-patterns.yml" "$D/policies/" 2>/dev/null || true
inject_startup "$D/hooks/sitecustomize.py"
# Construct the key at runtime so this test file itself carries no committed secret.
AKIA_KEY="AKIA""IOSFODNN7EXAMPLE"
printf 'const k = "%s";\n' "$AKIA_KEY" > "$D/src/leak.js"
( cd "$D" && git add src/leak.js )
T22C_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
T22C_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || T22C_RC=$?
if [ "$T22C_RC" -ne 0 ] && echo "$T22C_ERR" | grep -qiE "secret pattern|BLOCK — secret"; then ok "22c-secret-scan-still-blocks-under-S (§2 ran under -S with sitecustomize present, exit $T22C_RC)"; else bad "22c-secret-scan-still-blocks-under-S" "-S disabled the secret scan (a real staged secret was NOT blocked: exit $T22C_RC)"; fi
rm -rf "$D"

# =============================================================================
# T30 — close the mutable-Python-load-point class ENTIRELY. T29 hardened §2/§3 MAIN
# with `-S`, but the §3 PREP (git-show extraction) still ran PLAIN python3 with an
# INHERITED PYTHONPATH, and the trusted-vs-fallback verdict was a python-WRITABLE
# RESULT value. Live PoC (deploy-gate confirm): `PYTHONPATH=$ROOT/hooks` + untracked
# hooks/sitecustomize.py (forging RESULT=fallback / os._exit(0)) + an UNSTAGED lying
# path_policy.py + a STAGED protected file => exit 0. Fix: (A) scrub the hook env once
# at the top; (B) `-S` + a controlled PYTHONPATH on EVERY python invocation incl. PREP;
# (C) move the trusted-vs-fallback DECISION into the SHELL via `git ls-tree HEAD` (a
# forged RESULT can no longer be honored when HEAD has the enforcer).
# RED→GREEN vs ec94204 (T29 HEAD): the PoC exits 0 there.
# =============================================================================
T30_BASE_REF="ec94204"

# forge_fallback_site: an untracked hooks/sitecustomize.py that (like the PoC) FORGES the
# trusted-HEAD verdict — writes `RESULT=fallback` into the prep temp dir — and short-circuits
# the interpreter with os._exit(0). Under the T30 fix the PREP runs `-S` (this file never
# imports) AND the shell — not python — decides trusted-vs-fallback, so the forgery is inert.
forge_fallback_site() {  # $1 = target sitecustomize path
  cat > "$1" <<'FORGE'
import os
_tmp = os.environ.get("FR07_TMP")
if _tmp:
    try:
        with open(os.path.join(_tmp, "_result"), "w") as _f:
            _f.write("RESULT=fallback\n")
    except Exception:
        pass
os._exit(0)
FORGE
}

# ---- 23 (#T30-A). PREP-STEP-INJECTION-BLOCKS — the deploy-gate confirm's live PoC verbatim.
#      CLEAN enforcer in HEAD. Export a hostile PYTHONPATH=$D/hooks, drop an untracked
#      hooks/sitecustomize.py forging RESULT=fallback / os._exit(0), tamper the UNSTAGED
#      working-tree path_policy.py to lie, and stage ONLY a protected file (FLOW_RULES.md).
#      T30: env scrubbed + PREP under -S + git-based decision => trusted HEAD enforcer runs
#      => BLOCK. RED: ec94204's plain-python3 PREP imports the sitecustomize -> RESULT=fallback
#      honored -> working-tree lie runs -> exit 0. ----
D="$(new_repo)"
head_with_enforcer "$D"                              # CLEAN enforcer in HEAD.
forge_fallback_site "$D/hooks/sitecustomize.py"      # forges the verdict at py startup...
lying_path_policy "$D/hooks/shared/path_policy.py"   # ...unstaged working-tree lie...
printf '# flow rules (protected edit)\n' > "$D/FLOW_RULES.md"
( cd "$D" && git add FLOW_RULES.md )                 # ...only the protected file staged.
T23_ERR="$( ( cd "$D" && PYTHONPATH="$D/hooks" bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
T23_RC=0; ( cd "$D" && PYTHONPATH="$D/hooks" bash hooks/git/pre-commit >/dev/null 2>&1 ) || T23_RC=$?
if [ "$T23_RC" -ne 0 ]; then ok "23-prep-step-injection-blocks (env scrub + -S PREP + git decision, exit $T23_RC)"; else bad "23-prep-step-injection-blocks" "the live PoC (hostile PYTHONPATH + forging sitecustomize + unstaged lying path_policy + staged protected) STILL fail-open at exit 0 — FR-07 bypassable"; fi
if echo "$T23_ERR" | grep -qiE "protected paths edited|FR-07"; then ok "23-prep-injection-diagnostic-emitted"; else bad "23-prep-injection-diagnostic-emitted" "no FR-07 diagnostic on the blocked protected edit"; fi
# RED proof: pre-T30 (ec94204) plain-python3 PREP imports the sitecustomize -> exit 0.
if git -C "$ROOT" cat-file -e "$T30_BASE_REF:hooks/git/pre-commit" 2>/dev/null; then
  git -C "$ROOT" show "$T30_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit-t29"
  RED23=0; ( cd "$D" && PYTHONPATH="$D/hooks" bash hooks/git/pre-commit-t29 >/dev/null 2>&1 ) || RED23=$?
  if [ "$RED23" -eq 0 ]; then ok "23-RED-t29-was-fail-open (plain-python3 PREP honored the forged RESULT=fallback; the PoC self-passed at exit 0)"; else ok "23-RED-t29-not-exit0-here (GREEN still asserted)"; fi
  rm -f "$D/hooks/git/pre-commit-t29"
else ok "23-RED-skipped-no-baseline (ec94204 pre-commit not reachable)"; fi
rm -rf "$D"

# ---- 24 (#T30-A). INHERITED-PYTHONPATH-NEUTRALIZED (no over-block). With a hostile
#      PYTHONPATH exported, a normal protected-WITHOUT-approval edit still BLOCKS and a
#      normal NON-protected edit still PASSES — the env scrub neutralizes the inherited
#      value without collateral over-block. ----
# 24a. hostile PYTHONPATH + protected-no-approval -> BLOCK.
D="$(new_repo)"
head_with_enforcer "$D"
printf '# flow rules (protected edit)\n' > "$D/FLOW_RULES.md"
( cd "$D" && git add FLOW_RULES.md )
T24A_RC=0; ( cd "$D" && PYTHONPATH="$D/hooks" bash hooks/git/pre-commit >/dev/null 2>&1 ) || T24A_RC=$?
if [ "$T24A_RC" -ne 0 ]; then ok "24a-hostile-pythonpath-protected-no-approval-blocks (exit $T24A_RC)"; else bad "24a-hostile-pythonpath-protected-no-approval-blocks" "a protected-no-approval edit passed under hostile PYTHONPATH (env scrub failed)"; fi
rm -rf "$D"
# 24b. hostile PYTHONPATH + non-protected edit -> PASS (no over-block).
D="$(new_repo)"
head_with_enforcer "$D"
echo "app" > "$D/src/app.py"
( cd "$D" && git add src/app.py )
if ( cd "$D" && PYTHONPATH="$D/hooks" bash hooks/git/pre-commit >/dev/null 2>&1 ); then ok "24b-hostile-pythonpath-nonprotected-passes (no over-block)"; else bad "24b-hostile-pythonpath-nonprotected-passes" "a plain non-protected edit was over-blocked under hostile PYTHONPATH"; fi
rm -rf "$D"

# ---- 25 (#T30-C). FORGED-FALLBACK-IMPOSSIBLE-WHEN-HEAD-HAS-ENFORCER. An untracked
#      sitecustomize FORGES RESULT=fallback (no os._exit — so if the decision were still
#      the python-written file, the working-tree lying enforcer would run). Under T30 the
#      SHELL decides trusted via `git ls-tree HEAD`, so the forgery is inert => the trusted
#      HEAD enforcer runs => BLOCK. ----
D="$(new_repo)"
head_with_enforcer "$D"
# sitecustomize that ONLY forges the verdict (no os._exit — isolates the decision-source fix).
cat > "$D/hooks/sitecustomize.py" <<'FORGE2'
import os
_tmp = os.environ.get("FR07_TMP")
if _tmp:
    try:
        with open(os.path.join(_tmp, "_result"), "w") as _f:
            _f.write("RESULT=fallback\n")
    except Exception:
        pass
FORGE2
lying_path_policy "$D/hooks/shared/path_policy.py"   # unstaged working-tree lie (fallback target)
printf '# flow rules (protected edit)\n' > "$D/FLOW_RULES.md"
( cd "$D" && git add FLOW_RULES.md )
T25_ERR="$( ( cd "$D" && PYTHONPATH="$D/hooks" bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
T25_RC=0; ( cd "$D" && PYTHONPATH="$D/hooks" bash hooks/git/pre-commit >/dev/null 2>&1 ) || T25_RC=$?
if [ "$T25_RC" -ne 0 ] && echo "$T25_ERR" | grep -qiE "protected paths edited|FR-07"; then ok "25-forged-fallback-impossible-when-HEAD-has-enforcer (git decides trusted; forged RESULT inert -> BLOCK, exit $T25_RC)"; else bad "25-forged-fallback-impossible-when-HEAD-has-enforcer" "a forged RESULT=fallback caused the working-tree lying enforcer to run when HEAD has the enforcer (fail-open, exit $T25_RC)"; fi
rm -rf "$D"

# ---- 26 (#T30-B). PYYAML-STILL-IMPORTS-UNDER-S. The trusted MAIN check runs under `-S`
#      and re-adds site-packages via getsitepackages()/getusersitepackages() PATHS only.
#      Prove PyYAML (the enforcer's policy_loader dep) still imports under that regime, so
#      the trusted-policy seed does not silently fail. ----
if python3 -S -c 'import site,sys
d=[]
try: d.extend(site.getsitepackages())
except Exception: pass
try:
    u=site.getusersitepackages()
    if u: d.append(u)
except Exception: pass
for p in d:
    if p and p not in sys.path: sys.path.append(p)
import yaml
' >/dev/null 2>&1; then ok "26-pyyaml-imports-under-S (getsitepackages re-add works)"; else bad "26-pyyaml-imports-under-S" "PyYAML did NOT import under -S with the getsitepackages re-add — the trusted-policy seed would silently fail"; fi

# =============================================================================
# T32 — strip the CWD/repo-root entry from the §3 FR-07 MAIN `python3 -S -` (stdin) invocation.
# T29-T31 hardened §3 with `-S` + env scrub + trusted-HEAD enforcer/policy + a SHELL-decided
# trusted-vs-fallback, but the §3 MAIN still ran as `python3 -S -` (STDIN), leaving the repo-root
# CWD on sys.path[0]. An UNSTAGED repo-root pathlib.py (os._exit(0)) — or a yaml.py shadow —
# imported BEFORE the enforcer -> the §3 process exited 0 -> an unapproved protected edit
# committed unguarded. T32 runs §3 MAIN as a FILE SCRIPT from the trusted temp dir (sys.path[0]
# = that dir, CWD never added) + an in-script CWD scrub + PYTHONSAFEPATH + prepend site-packages.
# RED→GREEN vs 41a8c6d.
# =============================================================================
T32_BASE_REF="41a8c6d"

# t32_red_repo: a throwaway repo whose HEAD carries the pre-T32 pre-commit + shared enforcer +
# policies, so the RED baseline is a FAITHFUL pre-T32 env (stdin `-S -` §3 MAIN). Echoes the
# repo dir with the CLEAN enforcer already committed into HEAD (trusted path fires), or "" if
# the baseline blob is unreachable.
t32_red_repo() {
  git -C "$ROOT" cat-file -e "$T32_BASE_REF:hooks/git/pre-commit" 2>/dev/null || { echo ""; return; }
  local D; D="$(mktemp -d)"
  mkdir -p "$D/hooks/shared" "$D/hooks/git" "$D/hooks/local" "$D/policies" "$D/state/approvals" "$D/src"
  local f
  for f in __init__.py path_policy.py policy_loader.py audit_logger.py secret_scanner.py staged_secret_scan.py; do
    git -C "$ROOT" show "$T32_BASE_REF:hooks/shared/$f" > "$D/hooks/shared/$f" 2>/dev/null || true
  done
  git -C "$ROOT" show "$T32_BASE_REF:policies/protected-paths.yml" > "$D/policies/protected-paths.yml"
  git -C "$ROOT" show "$T32_BASE_REF:policies/secret-patterns.yml" > "$D/policies/secret-patterns.yml" 2>/dev/null || true
  git -C "$ROOT" show "$T32_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit"
  cp "$ROOT/hooks/local/write-bootstrap-approval.sh" "$D/hooks/local/" 2>/dev/null || true
  ( cd "$D" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config core.autocrlf false \
      && git add -A && git commit -qm 'seed clean enforcer into HEAD' )   # CLEAN enforcer in HEAD.
  echo "$D"
}
# fr07_repo: like new_repo but with the CLEAN enforcer already committed into HEAD so the
# UNCONDITIONAL trusted-HEAD §3 path fires (this task's FIXED working-tree pre-commit).
fr07_repo() {
  local D; D="$(new_repo)"
  head_with_enforcer "$D"
  echo "$D"
}
drop_pathlib_shadow() { printf 'import os\nos._exit(0)\n' > "$1/pathlib.py"; }
drop_yaml_pathlib_shadow() {   # a yaml.py that also short-circuits (the §3 yaml variant)
  printf 'import os\nos._exit(0)\n' > "$1/yaml.py"
}

# ---- 27 (T32 §3). CWD-SHADOW-FR07-PATHLIB-BLOCKS. Clean enforcer in HEAD; drop an UNSTAGED
#      repo-root pathlib.py (os._exit(0)); stage an UNAPPROVED protected edit (FLOW_RULES.md).
#      T32 §3 file-script strips CWD -> pathlib resolves to stdlib -> the enforcer runs -> BLOCK.
#      RED (41a8c6d): stdin `-S -` leaves CWD at sys.path[0] -> pathlib shadow os._exit(0)s -> §3
#      exits 0 -> the protected edit commits. ----
D="$(fr07_repo)"
drop_pathlib_shadow "$D"
printf '# flow rules (protected edit)\n' > "$D/FLOW_RULES.md"
( cd "$D" && git add FLOW_RULES.md )
T27_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
T27_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || T27_RC=$?
if [ "$T27_RC" -ne 0 ]; then ok "27-cwd-shadow-fr07-pathlib-blocks (§3 file-script strips CWD; pathlib shadow inert, exit $T27_RC)"; else bad "27-cwd-shadow-fr07-pathlib-blocks" "an UNSTAGED repo-root pathlib.py shadow let an unapproved protected edit through (rc=$T27_RC) — §3 CWD-on-sys.path bypass"; fi
if echo "$T27_ERR" | grep -qiE "protected paths edited|FR-07"; then ok "27-cwd-shadow-fr07-pathlib-diagnostic"; else bad "27-cwd-shadow-fr07-pathlib-diagnostic" "no FR-07 diagnostic on the blocked protected edit under the pathlib shadow"; fi
RED="$(t32_red_repo)"
if [ -n "$RED" ]; then
  drop_pathlib_shadow "$RED"; printf '# flow rules (protected edit)\n' > "$RED/FLOW_RULES.md"
  ( cd "$RED" && git add FLOW_RULES.md )
  RED27=0; ( cd "$RED" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || RED27=$?
  if [ "$RED27" -eq 0 ]; then ok "27-RED-was-fail-open (41a8c6d stdin -S - imported the repo-root pathlib shadow; the protected edit self-passed at exit 0)"; else ok "27-RED-not-exit0-here (GREEN still asserted)"; fi
  rm -rf "$RED"
else ok "27-RED-skipped-no-baseline (41a8c6d not reachable)"; fi
rm -rf "$D"

# ---- 28 (T32 §3, yaml variant). CWD-SHADOW-FR07-YAML-BLOCKS. Same as 27 but the UNSTAGED
#      repo-root shadow is yaml.py (os._exit(0)) — §3's trusted-policy seed does `import yaml`,
#      so a repo-root yaml.py on the CWD path fires there. T32 strips CWD -> BLOCK. ----
D="$(fr07_repo)"
drop_yaml_pathlib_shadow "$D"
printf '# flow rules (protected edit)\n' > "$D/FLOW_RULES.md"
( cd "$D" && git add FLOW_RULES.md )
T28Y_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || T28Y_RC=$?
if [ "$T28Y_RC" -ne 0 ]; then ok "28-cwd-shadow-fr07-yaml-blocks (§3 file-script strips CWD; repo-root yaml.py shadow inert, exit $T28Y_RC)"; else bad "28-cwd-shadow-fr07-yaml-blocks" "an UNSTAGED repo-root yaml.py shadow let an unapproved protected edit through (rc=$T28Y_RC) — §3 CWD-shadow bypass"; fi
RED="$(t32_red_repo)"
if [ -n "$RED" ]; then
  drop_yaml_pathlib_shadow "$RED"; printf '# flow rules (protected edit)\n' > "$RED/FLOW_RULES.md"
  ( cd "$RED" && git add FLOW_RULES.md )
  RED28=0; ( cd "$RED" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || RED28=$?
  if [ "$RED28" -eq 0 ]; then ok "28-RED-yaml-was-fail-open (41a8c6d imported the repo-root yaml.py shadow at the §3 seed; the protected edit self-passed at exit 0)"; else ok "28-RED-yaml-not-exit0-here (GREEN still asserted)"; fi
  rm -rf "$RED"
else ok "28-RED-yaml-skipped-no-baseline (41a8c6d not reachable)"; fi
rm -rf "$D"

# ---- 29 (T32 §3). NO-OVER-BLOCK + LEGIT-APPROVED. Under the T32 file-script §3, a legit
#      APPROVED enforcer edit still PASSES (the trusted HEAD honors the working-tree approval),
#      and a plain non-protected edit still PASSES (no over-block from the CWD strip). ----
D="$(fr07_repo)"
printf '\n# T32: a real, sanctioned comment-only edit\n' >> "$D/hooks/shared/path_policy.py"
( cd "$D" && git add hooks/shared/path_policy.py && bash hooks/local/write-bootstrap-approval.sh >/dev/null 2>&1 )
if run_precommit "$D"; then ok "29-cwd-strip-legit-approved-enforcer-edit-passes (T32 §3 file-script honors the working-tree approval)"; else bad "29-cwd-strip-legit-approved-enforcer-edit-passes" "a sanctioned approved enforcer edit was blocked by the T32 §3 file-script path"; fi
( cd "$D" && bash hooks/local/write-bootstrap-approval.sh --consume >/dev/null 2>&1 )
rm -rf "$D"
D="$(new_repo)"   # no enforcer in HEAD needed — a plain non-protected edit on the common path
echo "app" > "$D/src/app.py"; ( cd "$D" && git add src/app.py )
if run_precommit "$D"; then ok "29-cwd-strip-nonprotected-edit-passes (no over-block)"; else bad "29-cwd-strip-nonprotected-edit-passes" "a plain non-protected edit was over-blocked under the T32 §3 file-script path"; fi
rm -rf "$D"

# ---- 30 (T32 §3). SOURCE ASSERTS: §3 MAIN is a FILE SCRIPT (not stdin `-S -`), the §3 wrapper
#      scrubs CWD via the unshadowable builtin os core, and the §3 sentinel loop uses the
#      FILE-REDIRECT pattern (MSYS rc=124 hang fix, #3), not `$(git ls-tree)` command substitution. ----
if grep -q 'cat > "\$FR07_TMP/_main.py"' "$ROOT/hooks/git/pre-commit" \
   && grep -q 'python3 -S "\$FR07_TMP/_main.py"' "$ROOT/hooks/git/pre-commit" \
   && ! grep -q 'PYTHONPATH="\$FR07_IMPORT_DIR" python3 -S - ' "$ROOT/hooks/git/pre-commit"; then
  ok "30-cwd-strip-fr07-main-is-file-script (source: §3 MAIN runs python3 -S \$FR07_TMP/_main.py, no stdin -S -)"
else
  bad "30-cwd-strip-fr07-main-is-file-script" "§3 MAIN still uses stdin `python3 -S -` or the file-script invocation is absent"
fi
if grep -q 'import nt as _oscore' "$ROOT/hooks/git/pre-commit" \
   && grep -q 'import posix as _oscore' "$ROOT/hooks/git/pre-commit" \
   && grep -q 'sys.path\[:\] = \[p for p in sys.path if p not in _drop\]' "$ROOT/hooks/git/pre-commit"; then
  ok "30-cwd-strip-inscript-scrub-uses-builtin-oscore (nt/posix builtin -> unshadowable CWD source; sys.path filtered, not del path[0])"
else
  bad "30-cwd-strip-inscript-scrub-uses-builtin-oscore" "the in-script CWD scrub (builtin nt/posix + sys.path filter) not found in the §3/§2 wrappers"
fi
if grep -q 'git ls-tree HEAD -- "\$_s" > "\$FR07_LSFILE"' "$ROOT/hooks/git/pre-commit" \
   && ! grep -q '_ls="\$(git ls-tree HEAD' "$ROOT/hooks/git/pre-commit"; then
  ok "30-cwd-strip-fr07-sentinel-file-redirect (§3 sentinel via file redirect, no \$(git ls-tree) command substitution — MSYS rc=124 hang closed)"
else
  bad "30-cwd-strip-fr07-sentinel-file-redirect" "§3 sentinel loop still uses \$(git ls-tree ...) command substitution (MSYS hang risk)"
fi

finish
