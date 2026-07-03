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
#   "PASS: bootstrap-exception <name>" / "FAIL: bootstrap-exception <name>"; exit = fail count.
# (Tag kept as "bootstrap-exception" so the assertion names read continuously with the
#  companion file — tests 17..20 follow 1..16 there.)

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: bootstrap-exception $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: bootstrap-exception $1 (${2:-})"; }
finish() { echo "[test-trusted-enforcer] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: bootstrap-exception skipped-no-python3"; pass=$((pass + 1)); finish; }

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
# 19d. TRANSIENT-vs-BOOTSTRAP distinction fails CLOSED on a non-absent git error. The prep
#      only falls back when `git cat-file -e HEAD:<file>` returns rc 1 (genuinely absent);
#      any other nonzero rc (128 etc.) is transient -> BLOCK, never fall back to the untrusted
#      tree. Asserted via source (the reachable bootstrap path is covered live by 19c).
if grep -q 'transient git error' "$ROOT/hooks/git/pre-commit" \
   && grep -q 'r.returncode != 0' "$ROOT/hooks/git/pre-commit" \
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

finish
