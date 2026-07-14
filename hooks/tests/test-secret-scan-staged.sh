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

# v4.4.1 (field escalation, hardened under Codex-High review): the scanner excludes ONLY the
# EXACT root producers of the D-A1 files — `hooks.pre-upgrade-<ts>/tests/fixtures/**` and
# `policies.pre-upgrade-<ts>/secret-patterns*.yml` (ts = [0-9]{8}T[0-9]{6}Z) — so a wholesale
# `git add -A` (fusebase-update checkpoint) does not false-block on Flow's own fixture/policy
# backups, while NOTHING else is waved through.
TS="20260101T000000Z"
# (positive) the exact root fixture/policy twins are excluded -> no block
D="$(new_repo)"
mkdir -p "$D/hooks.pre-upgrade-$TS/tests/fixtures" "$D/policies.pre-upgrade-$TS"
echo "$SECRET" > "$D/hooks.pre-upgrade-$TS/tests/fixtures/10_designed.txt"
echo "$SECRET" > "$D/policies.pre-upgrade-$TS/secret-patterns.yml"
( cd "$D" && git add "hooks.pre-upgrade-$TS/tests/fixtures/10_designed.txt" "policies.pre-upgrade-$TS/secret-patterns.yml" )
if run_helper "$D"; then ok "backup-fixture-policy-twins-excluded"; else bad "backup-fixture-policy-twins-excluded" "a timestamped root fixture/policy backup twin false-blocked"; fi
rm -rf "$D"

# (negative) the exclusion is EXACT + ROOT-ANCHORED: every one of these STILL BLOCKS.
#   - backup of a NON-fixture real file (an upgrade overwriting a secret leaves it here)
#   - a backup-shaped name with no timestamp / a bare "1"
#   - a fixtures path with a bogus timestamp ("plain")
#   - the `*T*Z`-glob spoof: a literal "TZ" where a real stamp should be
#   - an EXACT timestamp but NOT at the repo root (nested) / under the WRONG dir prefix
for spoof in \
  "backup-of-real-file:hooks.pre-upgrade-$TS/local/leak.sh" \
  "name-spoof-no-ts:src/x.pre-upgrade-1/credentials.txt" \
  "untimestamped-fixtures:z.pre-upgrade-plain/tests/fixtures/creds.txt" \
  "tz-glob-spoof:src/x.pre-upgrade-TZ/tests/fixtures/creds.txt" \
  "exact-ts-non-root:sub/hooks.pre-upgrade-$TS/tests/fixtures/creds.txt" \
  "exact-ts-wrong-prefix:evil.pre-upgrade-$TS/tests/fixtures/creds.txt"; do
  name="${spoof%%:*}"; path="${spoof#*:}"
  D="$(new_repo)"; mkdir -p "$D/$(dirname "$path")"; echo "$SECRET" > "$D/$path"
  ( cd "$D" && git add "$path" )
  if run_helper "$D"; then bad "secret-still-blocks-$name" "a real secret at $path bypassed the scanner"; else ok "secret-still-blocks-$name"; fi
  rm -rf "$D"
done

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

# =============================================================================
# T31 — the §2 secret scanner + its patterns now run from the TRUSTED (HEAD) copy.
# T29/T30 hardened §2 with `-S` + an env scrub, but the SCRIPT (staged_secret_scan.py)
# and its PATTERNS (secret-patterns.yml) were still the mutable working tree: an UNSTAGED
# tamper of either => "no secrets" => a real staged secret commits unguarded. Same
# mutable-Python-load class as the §3 self-tamper (T28-T30), applied to the secret gate.
# These scenarios run the REAL pre-commit (the tamper only takes effect through the hook's
# trusted-HEAD dispatch, not the bare helper). RED→GREEN vs 555b897 (T30 HEAD).
# =============================================================================
T31_BASE_REF="555b897"

# ph_repo: a throwaway repo whose HEAD carries the CLEAN scanner stack + patterns + the
# FR-07 enforcer/policy (so §3 doesn't fail-closed on a missing protected-paths.yml) + the
# real pre-commit + the bootstrap-approval writer. Echoes the repo dir.
ph_repo() {
  local D; D="$(mktemp -d)"
  mkdir -p "$D/hooks/shared" "$D/hooks/git" "$D/hooks/local" "$D/policies" "$D/state/approvals" "$D/src"
  cp "$ROOT/hooks/shared/"*.py "$D/hooks/shared/" 2>/dev/null || true
  : > "$D/hooks/shared/__init__.py"
  cp "$ROOT/policies/secret-patterns.yml"  "$D/policies/"
  cp "$ROOT/policies/protected-paths.yml"  "$D/policies/"
  cp "$ROOT/hooks/git/pre-commit"          "$D/hooks/git/"
  cp "$ROOT/hooks/local/write-bootstrap-approval.sh" "$D/hooks/local/" 2>/dev/null || true
  ( cd "$D" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config core.autocrlf false \
      && git add -A && git commit -qm seed )   # CLEAN scanner + patterns now in HEAD.
  echo "$D"
}
run_precommit_pc() { ( cd "$1" && bash hooks/git/pre-commit >/dev/null 2>&1 ); }
# A real high-confidence secret (AWS access key id), built so this test file carries no
# committed secret literal (WS1a runtime-construction discipline).
AKIA_KEY="AKIA""IOSFODNN7EXAMPLE"

# ---- T31 #1. SCRIPT-TAMPER-BLOCKS. Clean scanner in HEAD. Tamper the WORKING-TREE
#      staged_secret_scan.py (UNSTAGED) to `return 0` (report no secrets); stage a file
#      with a REAL secret. The TRUSTED HEAD scanner runs -> BLOCK. RED (555b897): the
#      tampered working-tree scanner runs -> the secret commits (rc=0). ----
D="$(ph_repo)"
printf 'import sys\ndef main():\n    return 0\nif __name__ == "__main__":\n    sys.exit(main())\n' > "$D/hooks/shared/staged_secret_scan.py"  # UNSTAGED tamper
printf 'const k = "%s";\n' "$AKIA_KEY" > "$D/src/leak.js"
( cd "$D" && git add src/leak.js )   # stage ONLY the secret; the scanner tamper is unstaged.
T31A_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
T31A_RC=0; run_precommit_pc "$D" || T31A_RC=$?
if [ "$T31A_RC" -ne 0 ] && echo "$T31A_ERR" | grep -qiE "secret pattern|BLOCK — secret"; then ok "secret-scan-script-tamper-blocks (trusted HEAD scanner runs, exit $T31A_RC)"; else bad "secret-scan-script-tamper-blocks" "an UNSTAGED working-tree staged_secret_scan.py tamper let a real staged secret through (rc=$T31A_RC) — FR-12 fail-OPEN"; fi
# RED proof: the pre-T31 pre-commit runs the tampered working-tree scanner -> exit 0.
if git -C "$ROOT" cat-file -e "$T31_BASE_REF:hooks/git/pre-commit" 2>/dev/null; then
  git -C "$ROOT" show "$T31_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit-t30"
  RED31A=0; ( cd "$D" && bash hooks/git/pre-commit-t30 >/dev/null 2>&1 ) || RED31A=$?
  if [ "$RED31A" -eq 0 ]; then ok "secret-scan-script-tamper-RED-t30-was-fail-open (working-tree scanner ran; the secret self-passed at exit 0)"; else ok "secret-scan-script-tamper-RED-t30-not-exit0-here (GREEN still asserted)"; fi
  rm -f "$D/hooks/git/pre-commit-t30"
else ok "secret-scan-script-tamper-RED-skipped-no-baseline (555b897 pre-commit not reachable)"; fi
rm -rf "$D"

# ---- T31 #2. PATTERNS-TAMPER-BLOCKS. Clean scanner+patterns in HEAD. Empty the
#      WORKING-TREE secret-patterns.yml (UNSTAGED) so no pattern matches; stage a real
#      secret. The TRUSTED HEAD patterns (seeded into the loader cache) run -> BLOCK.
#      RED (555b897): the emptied working-tree patterns load -> no match -> commit (rc=0). ----
D="$(ph_repo)"
printf 'schema_version: 1\ndefault_action: block\npatterns: []\nwhitelist: []\n' > "$D/policies/secret-patterns.yml"  # UNSTAGED tamper (emptied)
printf 'const k = "%s";\n' "$AKIA_KEY" > "$D/src/leak.js"
( cd "$D" && git add src/leak.js )
T31B_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
T31B_RC=0; run_precommit_pc "$D" || T31B_RC=$?
if [ "$T31B_RC" -ne 0 ] && echo "$T31B_ERR" | grep -qiE "secret pattern|BLOCK — secret"; then ok "secret-scan-patterns-tamper-blocks (trusted HEAD patterns run, exit $T31B_RC)"; else bad "secret-scan-patterns-tamper-blocks" "an UNSTAGED emptied working-tree secret-patterns.yml let a real staged secret through (rc=$T31B_RC) — FR-12 fail-OPEN"; fi
if git -C "$ROOT" cat-file -e "$T31_BASE_REF:hooks/git/pre-commit" 2>/dev/null; then
  git -C "$ROOT" show "$T31_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit-t30"
  RED31B=0; ( cd "$D" && bash hooks/git/pre-commit-t30 >/dev/null 2>&1 ) || RED31B=$?
  if [ "$RED31B" -eq 0 ]; then ok "secret-scan-patterns-tamper-RED-t30-was-fail-open (emptied working-tree patterns loaded; the secret self-passed at exit 0)"; else ok "secret-scan-patterns-tamper-RED-t30-not-exit0-here (GREEN still asserted)"; fi
  rm -f "$D/hooks/git/pre-commit-t30"
else ok "secret-scan-patterns-tamper-RED-skipped-no-baseline (555b897 pre-commit not reachable)"; fi
rm -rf "$D"

# ---- T31 #3. STILL-BLOCKS-NORMAL. Untampered clean scanner in HEAD, a real staged secret
#      -> BLOCK through the trusted-HEAD path (regression: §2 detection intact). ----
D="$(ph_repo)"
printf 'const k = "%s";\n' "$AKIA_KEY" > "$D/src/leak.js"
( cd "$D" && git add src/leak.js )
T31C_RC=0; run_precommit_pc "$D" || T31C_RC=$?
if [ "$T31C_RC" -ne 0 ]; then ok "secret-scan-still-blocks-normal (trusted HEAD, untampered, exit $T31C_RC)"; else bad "secret-scan-still-blocks-normal" "a real staged secret was NOT blocked under the trusted-HEAD path (detection broke)"; fi
rm -rf "$D"

# ---- T31 #4. NO-OVER-BLOCK. A legit non-secret commit passes cleanly through the
#      trusted-HEAD §2 path (and §3, a non-protected src edit). ----
D="$(ph_repo)"
echo "const ok = 'hello world';" > "$D/src/app.js"
( cd "$D" && git add src/app.js )
if run_precommit_pc "$D"; then ok "secret-scan-no-over-block-legit-passes (trusted HEAD §2, non-secret)"; else bad "secret-scan-no-over-block-legit-passes" "a legit non-secret commit was over-blocked by the trusted-HEAD §2 path"; fi
rm -rf "$D"

# ---- T31 #5. BOOTSTRAP-EDGE. HEAD LACKS the scanner (first-adoption): the shell falls
#      back to the working-tree scanner (with a note) and STILL blocks a real secret. ----
D="$(mktemp -d)"
mkdir -p "$D/hooks/shared" "$D/hooks/git" "$D/policies" "$D/src"
cp "$ROOT/hooks/git/pre-commit" "$D/hooks/git/"
( cd "$D" && git init -q && git config user.email t@t.t && git config user.name t \
    && git config core.autocrlf false && echo seed > seed.txt && git add seed.txt && git commit -qm seed )
# First-add the scanner stack + patterns + a real secret (HEAD has none of them).
cp "$ROOT/hooks/shared/"*.py "$D/hooks/shared/" 2>/dev/null || true
: > "$D/hooks/shared/__init__.py"
cp "$ROOT/policies/secret-patterns.yml" "$D/policies/"
cp "$ROOT/policies/protected-paths.yml" "$D/policies/"
printf 'const k = "%s";\n' "$AKIA_KEY" > "$D/src/leak.js"
( cd "$D" && git add hooks/shared policies/secret-patterns.yml policies/protected-paths.yml src/leak.js )
BOOT_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
BOOT_RC=0; ( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || BOOT_RC=$?
if echo "$BOOT_ERR" | grep -qiE "first-adoption bootstrap|not in HEAD"; then ok "secret-scan-bootstrap-edge-falls-back (working-tree scanner note emitted)"; else bad "secret-scan-bootstrap-edge-falls-back" "the first-add of the scanner did NOT emit the §2 bootstrap fallback note"; fi
if [ "$BOOT_RC" -ne 0 ] && echo "$BOOT_ERR" | grep -qiE "secret pattern|BLOCK — secret"; then ok "secret-scan-bootstrap-edge-still-blocks (fallback scanner blocks the real secret, exit $BOOT_RC)"; else bad "secret-scan-bootstrap-edge-still-blocks" "the bootstrap fallback did NOT block a real staged secret (rc=$BOOT_RC)"; fi
rm -rf "$D"

# ---- T31 #6. TRANSIENT-ERROR-FAILS-CLOSED (source). The §2 trusted-vs-fallback decision
#      is shell-decided via `git ls-tree HEAD -- <sentinel>`: rc0+empty => genuinely absent
#      (bootstrap fallback), rc!=0 => transient -> BLOCK (never fall back to the untrusted
#      tree). Asserted via source (the reachable bootstrap path is covered live by #5). ----
if grep -q '§2 secret scan could not read the trusted HEAD copy' "$ROOT/hooks/git/pre-commit" \
   && grep -q '_sls_rc" -ne 0' "$ROOT/hooks/git/pre-commit" \
   && grep -q 'NOT falling back to the untrusted working tree' "$ROOT/hooks/git/pre-commit"; then
  ok "secret-scan-transient-error-fails-closed (source)"
else
  bad "secret-scan-transient-error-fails-closed" "the §2 transient-vs-bootstrap fail-closed guard not found in pre-commit source"
fi

# ---- T31 #7. GREP-VERIFY: §2 runs the trusted-HEAD scanner. The §2 python invocation
#      imports from the trusted temp dir (SEC_IMPORT_DIR), NOT the old bare
#      `$ROOT/hooks/shared/staged_secret_scan.py` working-tree helper path. ----
if grep -q 'PYTHONPATH="\$SEC_IMPORT_DIR" python3 -S' "$ROOT/hooks/git/pre-commit" \
   && ! grep -q 'python3 -S "\$ROOT/hooks/shared/staged_secret_scan.py"' "$ROOT/hooks/git/pre-commit"; then
  ok "secret-scan-invokes-trusted-head-not-worktree (source: §2 imports from SEC_IMPORT_DIR, no bare \$ROOT/hooks helper invocation)"
else
  bad "secret-scan-invokes-trusted-head-not-worktree" "§2 still invokes the bare working-tree staged_secret_scan.py, or the trusted SEC_IMPORT_DIR invocation is absent"
fi

# ---- T31 #8. PYYAML-UNDER-S. The trusted §2 seed re-adds site-packages under -S via
#      getsitepackages()/getusersitepackages() PATHS; prove PyYAML still imports so the
#      trusted-patterns seed does not silently fail. ----
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
' >/dev/null 2>&1; then ok "secret-scan-pyyaml-imports-under-S (getsitepackages re-add works for the §2 seed)"; else bad "secret-scan-pyyaml-imports-under-S" "PyYAML did NOT import under -S — the §2 trusted-patterns seed would silently fail"; fi

# =============================================================================
# T32 — strip the CWD/repo-root entry from every `python3 -S -` (stdin) invocation so a
# repo-root module shadow (pathlib.py / yaml.py) can no longer run BEFORE the checks. T29-T31
# hardened §2 with `-S` + env scrub + trusted-HEAD code/patterns, but the §2 MAIN check still
# ran as `python3 -S -` (STDIN), which leaves the repo-root CWD on sys.path[0]. `pathlib` is
# NOT builtin, and _restore_site_packages APPENDED site-packages (behind the CWD), so an
# UNSTAGED repo-root pathlib.py (os._exit(0)) OR a discriminating yaml.py shim ran ahead of
# stdlib/site and neutered §2 -> a real staged secret committed unguarded. T32 runs the MAIN
# check as a FILE SCRIPT from the trusted temp dir (sys.path[0] = that dir, CWD never added) +
# an in-script CWD scrub + PYTHONSAFEPATH=1 + PREPEND site-packages. RED→GREEN vs 41a8c6d.
# =============================================================================
T32_BASE_REF="41a8c6d"

# t32_red_repo: a throwaway repo whose HEAD carries the T32_BASE_REF (pre-T32) pre-commit +
# the pre-T32 shared scanner stack + patterns + protected-paths policy, so the RED baseline
# is a FAITHFUL pre-T32 environment (append-style _restore_site_packages + stdin `-S -` MAIN).
# Echoes the repo dir, or empty string if the baseline blob is unreachable.
t32_red_repo() {
  git -C "$ROOT" cat-file -e "$T32_BASE_REF:hooks/git/pre-commit" 2>/dev/null || { echo ""; return; }
  local D; D="$(mktemp -d)"
  mkdir -p "$D/hooks/shared" "$D/hooks/git" "$D/policies" "$D/state/approvals" "$D/src"
  local f
  for f in __init__.py staged_secret_scan.py secret_scanner.py audit_logger.py policy_loader.py path_policy.py; do
    git -C "$ROOT" show "$T32_BASE_REF:hooks/shared/$f" > "$D/hooks/shared/$f" 2>/dev/null || true
  done
  git -C "$ROOT" show "$T32_BASE_REF:policies/secret-patterns.yml" > "$D/policies/secret-patterns.yml"
  git -C "$ROOT" show "$T32_BASE_REF:policies/protected-paths.yml" > "$D/policies/protected-paths.yml"
  git -C "$ROOT" show "$T32_BASE_REF:hooks/git/pre-commit" > "$D/hooks/git/pre-commit"
  ( cd "$D" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config core.autocrlf false && git add -A && git commit -qm seed )
  echo "$D"
}

# drop_pathlib_shadow: an UNSTAGED repo-root pathlib.py that short-circuits the interpreter.
drop_pathlib_shadow() { printf 'import os\nos._exit(0)\n' > "$1/pathlib.py"; }
# drop_yaml_shim: the DISCRIMINATING repo-root yaml.py — empty secret-patterns (neuter §2) but a
# VALID non-empty fusebase_flow_internals policy for protected-paths text (keep §3 green), keyed
# on `local_override_may_relax`/`categories:` (only protected-paths.yml carries them).
drop_yaml_shim() {
  cat > "$1/yaml.py" <<'YSHIM'
def safe_load(text):
    t = text.decode("utf-8", "replace") if isinstance(text, (bytes, bytearray)) else (text or "")
    if "local_override_may_relax" in t or "categories:" in t:
        return {"schema_version": 1, "local_override_may_relax": False,
                "categories": {"fusebase_flow_internals": {"paths": ["FLOW_RULES.md", "policies/*.yml", "hooks/handlers/**", "hooks/shared/**"]}}}
    return {"schema_version": 1, "default_action": "block", "patterns": [], "whitelist": []}
def load(t, *a, **k):
    return safe_load(t)
class YAMLError(Exception):
    pass
YSHIM
}

# ---- T32 #1. CWD-SHADOW-SECRET-PATHLIB-BLOCKS (§2, Codex vector). Clean scanner in HEAD;
#      drop an UNSTAGED repo-root pathlib.py (os._exit(0)); stage a real AWS key. The T32
#      MAIN file-script strips CWD -> pathlib resolves to stdlib -> §2 runs -> BLOCK.
#      RED (41a8c6d): stdin `-S -` leaves CWD at sys.path[0] -> pathlib shadow os._exit(0)s ->
#      the §2 process exits 0 -> the secret commits. ----
D="$(ph_repo)"
drop_pathlib_shadow "$D"
printf 'const k = "%s";\n' "$AKIA_KEY" > "$D/src/leak.js"
( cd "$D" && git add src/leak.js )
T32A_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
T32A_RC=0; run_precommit_pc "$D" || T32A_RC=$?
if [ "$T32A_RC" -ne 0 ] && echo "$T32A_ERR" | grep -qiE "secret pattern|BLOCK — secret"; then ok "cwd-shadow-secret-pathlib-blocks (§2 file-script strips CWD; pathlib shadow inert, exit $T32A_RC)"; else bad "cwd-shadow-secret-pathlib-blocks" "an UNSTAGED repo-root pathlib.py shadow let a real staged secret through (rc=$T32A_RC) — §2 CWD-on-sys.path bypass"; fi
# RED proof on 41a8c6d (faithful pre-T32 env): the stdin `-S -` MAIN imports the shadow -> exit 0.
RED="$(t32_red_repo)"
if [ -n "$RED" ]; then
  drop_pathlib_shadow "$RED"; printf 'const k = "%s";\n' "$AKIA_KEY" > "$RED/src/leak.js"
  ( cd "$RED" && git add src/leak.js )
  RED32A=0; ( cd "$RED" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || RED32A=$?
  if [ "$RED32A" -eq 0 ]; then ok "cwd-shadow-secret-pathlib-RED-was-fail-open (41a8c6d stdin -S - imported the repo-root pathlib shadow; secret self-passed at exit 0)"; else ok "cwd-shadow-secret-pathlib-RED-not-exit0-here (GREEN still asserted)"; fi
  rm -rf "$RED"
else ok "cwd-shadow-secret-pathlib-RED-skipped-no-baseline (41a8c6d not reachable)"; fi
rm -rf "$D"

# ---- T32 #2. CWD-SHADOW-SECRET-YAML-BLOCKS (§2, panel vector — the discriminating-shim PoC,
#      verified END-TO-END). Clean scanner+patterns+enforcer in HEAD; drop the UNSTAGED
#      discriminating repo-root yaml.py (empty patterns for §2, valid policy for §3); stage a
#      real AWS key in a NON-protected path (src/leak.js). T32 strips CWD -> real PyYAML wins ->
#      §2 seeds the TRUSTED patterns -> BLOCK. RED (41a8c6d): the shim wins (CWD ahead of the
#      APPENDED site-packages) -> §2 sees empty patterns -> §3 stays green -> "all checks
#      passed", exit 0, the AWS key lands in HEAD. ----
D="$(ph_repo)"
drop_yaml_shim "$D"
printf 'const k = "%s";\n' "$AKIA_KEY" > "$D/src/leak.js"
( cd "$D" && git add src/leak.js )
T32B_ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"
T32B_RC=0; run_precommit_pc "$D" || T32B_RC=$?
if [ "$T32B_RC" -ne 0 ] && echo "$T32B_ERR" | grep -qiE "secret pattern|BLOCK — secret"; then ok "cwd-shadow-secret-yaml-blocks (discriminating shim inert; real PyYAML wins; §2 BLOCKS, exit $T32B_RC)"; else bad "cwd-shadow-secret-yaml-blocks" "the discriminating repo-root yaml.py shim neutered §2 and a real staged secret committed (rc=$T32B_RC) — §2 CWD-shadow bypass"; fi
RED="$(t32_red_repo)"
if [ -n "$RED" ]; then
  drop_yaml_shim "$RED"; printf 'const k = "%s";\n' "$AKIA_KEY" > "$RED/src/leak.js"
  ( cd "$RED" && git add src/leak.js )
  RED32B=0; ( cd "$RED" && bash hooks/git/pre-commit >/dev/null 2>&1 ) || RED32B=$?
  if [ "$RED32B" -eq 0 ]; then ok "cwd-shadow-secret-yaml-RED-was-fail-open (41a8c6d: discriminating shim neutered §2, kept §3 green; the AWS key self-passed at exit 0)"; else ok "cwd-shadow-secret-yaml-RED-not-exit0-here (GREEN still asserted)"; fi
  rm -rf "$RED"
else ok "cwd-shadow-secret-yaml-RED-skipped-no-baseline (41a8c6d not reachable)"; fi
rm -rf "$D"

# ---- T32 #3. YAML-STILL-IMPORTS / NO-OVER-BLOCK. A legit non-secret commit still passes the
#      T32 file-script §2 path (real PyYAML imports under the CWD-strip + prepend); a real
#      secret on the untampered path still BLOCKS (§2 detection intact). ----
D="$(ph_repo)"
echo "const ok = 'hello world';" > "$D/src/app.js"
( cd "$D" && git add src/app.js )
if run_precommit_pc "$D"; then ok "cwd-strip-no-over-block-legit-passes (T32 file-script §2, non-secret, PyYAML imports)"; else bad "cwd-strip-no-over-block-legit-passes" "a legit non-secret commit was over-blocked by the T32 §2 file-script path (did PyYAML fail to import after the CWD strip?)"; fi
rm -rf "$D"
D="$(ph_repo)"
printf 'const k = "%s";\n' "$AKIA_KEY" > "$D/src/leak.js"
( cd "$D" && git add src/leak.js )
T32C_RC=0; run_precommit_pc "$D" || T32C_RC=$?
if [ "$T32C_RC" -ne 0 ]; then ok "cwd-strip-still-blocks-untampered-secret (§2 detection intact under file-script, exit $T32C_RC)"; else bad "cwd-strip-still-blocks-untampered-secret" "a real staged secret was NOT blocked under the T32 §2 file-script path (detection broke)"; fi
rm -rf "$D"

# ---- T32 #4. SYSPATH-HAS-NO-CWD (assert) + PREPEND ORDER. The §2 MAIN wrapper's effective
#      sys.path must NOT contain '', '.', or the repo-root/CWD before the first non-builtin
#      import, AND _restore_site_packages must PREPEND (not append) site-packages AFTER the
#      leading trusted import dir. Extract the shipped §2 wrapper body + run it with a probe
#      shim that would only load if CWD were on the path. ----
# 4a. Assert the shipped §2 MAIN runs as a FILE SCRIPT (not `python3 -S -` stdin) + scrubs CWD.
if grep -q 'cat > "\$SEC_TMP/_main_secret.py"' "$ROOT/hooks/git/pre-commit" \
   && grep -q 'python3 -S "\$SEC_TMP/_main_secret.py"' "$ROOT/hooks/git/pre-commit" \
   && ! grep -q 'PYTHONPATH="\$SEC_IMPORT_DIR" python3 -S - ' "$ROOT/hooks/git/pre-commit"; then
  ok "cwd-strip-sec-main-is-file-script (source: §2 MAIN runs python3 -S \$SEC_TMP/_main_secret.py, no stdin -S -)"
else
  bad "cwd-strip-sec-main-is-file-script" "§2 MAIN still uses stdin `python3 -S -` or the file-script invocation is absent"
fi
# 4b. Live probe: a file-script in a fresh temp dir, run from CWD holding a shadow module, must
#     NOT see '', '.', or the CWD on sys.path — the direct guarantee behind the shadow tests.
PROBE_TMP="$(mktemp -d)"; PROBE_CWD="$(mktemp -d)"
printf 'import os\nos._exit(0)\n' > "$PROBE_CWD/pathlib.py"   # a shadow that would fire IF CWD were on the path
cat > "$PROBE_TMP/probe.py" <<'PROBE'
import sys
_cwd = None
try:
    import nt as _oscore
except ImportError:
    import posix as _oscore
try:
    _cwd = _oscore.getcwd()
except Exception:
    _cwd = None
_drop = {"", "."}
if _cwd:
    _drop.add(_cwd)
sys.path[:] = [p for p in sys.path if p not in _drop]
from pathlib import Path   # would hit the CWD shadow (os._exit 0) if CWD survived
print("NO_CWD_ON_PATH")
PROBE
PROBE_OUT="$( ( cd "$PROBE_CWD" && python3 -S "$PROBE_TMP/probe.py" ) 2>/dev/null )"
if [ "$PROBE_OUT" = "NO_CWD_ON_PATH" ]; then ok "cwd-strip-syspath-has-no-cwd (file-script + in-script scrub: '', '.', CWD absent before first non-builtin import)"; else bad "cwd-strip-syspath-has-no-cwd" "a file-script run from a CWD holding a pathlib.py shadow still imported it (CWD survived on sys.path) — got: '$PROBE_OUT'"; fi
rm -rf "$PROBE_TMP" "$PROBE_CWD"
# 4c. Source assert: _restore_site_packages PREPENDS (insert), not append.
if grep -q 'sys.path.insert(insert_at, p)' "$ROOT/hooks/shared/staged_secret_scan.py" \
   && ! grep -q 'sys.path.append(p)' "$ROOT/hooks/shared/staged_secret_scan.py"; then
  ok "cwd-strip-restore-site-packages-prepends (staged_secret_scan: insert after leading trusted dir, not append)"
else
  bad "cwd-strip-restore-site-packages-prepends" "staged_secret_scan._restore_site_packages still appends site-packages (a surviving CWD yaml.py could still shadow real PyYAML)"
fi
# 4d. Source assert: PYTHONSAFEPATH=1 exported at the hook top (defense-in-depth).
if grep -q 'export PYTHONSAFEPATH=1' "$ROOT/hooks/git/pre-commit"; then
  ok "cwd-strip-pythonsafepath-exported (defense-in-depth: 3.11+ never puts CWD on sys.path)"
else
  bad "cwd-strip-pythonsafepath-exported" "PYTHONSAFEPATH=1 not exported at the hook top"
fi
# 4e. Source assert: §2 sentinel loop uses the FILE-REDIRECT pattern, not `$(git ls-tree)` command
#     substitution (MSYS rc=124 hang fix, #3). The capture writes to SEC_LSFILE then reads it.
if grep -q 'git ls-tree HEAD -- "\$_s" > "\$SEC_LSFILE"' "$ROOT/hooks/git/pre-commit" \
   && ! grep -q '_sls="\$(git ls-tree HEAD' "$ROOT/hooks/git/pre-commit"; then
  ok "cwd-strip-sec-sentinel-file-redirect (§2 sentinel via file redirect, no \$(git ls-tree) command substitution — MSYS rc=124 hang closed)"
else
  bad "cwd-strip-sec-sentinel-file-redirect" "§2 sentinel loop still uses \$(git ls-tree ...) command substitution (MSYS hang risk)"
fi

finish
