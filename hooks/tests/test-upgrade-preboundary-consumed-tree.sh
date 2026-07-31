#!/usr/bin/env bash
# Fusebase Flow — the PRE-BOUNDARY route: the tree we PROVED vs the tree the engine CONSUMES.
# Spec: docs/specs/upgrade-source-integrity-and-observability/ (decisions M1, M10, M11).
#
# Seam (extracted from test-upgrade-source-boundary.sh at FR-25's ceiling): that file owns WHICH
# BYTES enter the consumer and the source-shape matrix; this one owns the single hardest route
# through the hop — a source whose upgrade.sh predates `--source-tree` cannot be handed a
# materialized tree, so it reads `.fusebase-flow-source` BY NAME. Everything here is an
# adversarial case against the split that opens up when the tree we prove is not the tree that
# is read: who may answer the question (B4), what code the interpreter runs before the answer
# (B5), what counts as an answer (B5b), and what the answer actually covers (B6).
#
# Every case here was observed RED at the commit named in its own block comment. Two of the
# assertions are coverage repair and one is a negative control; each says so where it lives.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: preboundary-consumed <name>" / "FAIL: preboundary-consumed <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: preboundary-consumed $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: preboundary-consumed $1 (${2:-})"; }
finish() { echo "[test-upgrade-preboundary-consumed-tree] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: preboundary-consumed skipped-no-python3"; pass=1; finish; }
command -v git >/dev/null 2>&1 || { echo "PASS: preboundary-consumed skipped-no-git"; pass=1; finish; }

# shellcheck source=lib/upgrade-fixtures.sh
. "$ROOT/hooks/tests/lib/upgrade-fixtures.sh"

B3_ROOT="$(mktemp -d)"

# ---- 2i-bis. B4: the tree the engine CONSUMES may not be judged by its OWN verifier ---------
# One level deeper than 2i/R3: Step 2c re-reaches the verdict on the mutable worktree, and doing
# that by executing the WORKTREE's managed_content_manifest.py lets a tamper that ALSO rewrites
# that file print MATCH for itself — B1 in Python instead of shell. GIT transport only: the
# canonical tree comes from CLEAN COMMITTED OBJECTS, so it verifies honestly and the lying
# worktree verifier is the only thing between the tampered payload and the consumer.
for helper in "H-" "H+"; do
  LV="$(bnd_plain_case "$B3_ROOT/liarverifier-$helper")"
  LVS="$LV/.fusebase-flow-source"
  [ "$helper" = "H-" ] && rm -f "$LV/hooks/local/lib/materialize-managed-source.sh"
  rm -f "$LVS/hooks/local/lib/materialize-managed-source.sh"
  bnd_legacy_engine "$LVS"
  ( cd "$LVS" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  bnd_git_source "$LVS"
  # BOTH mutations land AFTER the commit: the payload the consumer would receive, and the
  # verifier that would be asked about it.
  printf 'control TAMPERED\n' > "$LVS/hooks/local/control.sh"
  cat > "$LVS/hooks/local/lib/managed_content_manifest.py" <<'LIAR'
import sys
print('{"verdict": "MATCH", "listed": 0, "files": []}')
sys.exit(0)
LIAR
  LV_LOG="$B3_ROOT/liarverifier-$helper.log"
  ( cd "$LV" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source --ref main \
      -- --auto-yes ) > "$LV_LOG" 2>&1
  LV_RC=$?
  lv_fail=""
  [ "$LV_RC" -ne 0 ] || lv_fail="$lv_fail [a worktree that tampered its OWN verifier upgraded anyway (rc 0)]"
  grep -q "ABORT" "$LV_LOG" || lv_fail="$lv_fail [no abort diagnostic]"
  grep -q "audit/managed-content-manifest.json" "$LV_LOG" \
    || lv_fail="$lv_fail [the abort does not name audit/managed-content-manifest.json]"
  grep -q "hooks/local/control.sh" "$LV_LOG" \
    || lv_fail="$lv_fail [the offending payload path is not named]"
  grep -q "control v1" "$LV/hooks/local/control.sh" || lv_fail="$lv_fail [tampered bytes were installed]"
  [ ! -f "$LV/legacy-engine-argv.txt" ] || lv_fail="$lv_fail [the engine ran despite the abort]"
  if [ -z "$lv_fail" ]; then
    ok "b4-consumed-worktree-cannot-be-approved-by-its-own-verifier-git-$helper"
  else
    bad "b4-consumed-worktree-cannot-be-approved-by-its-own-verifier-git-$helper" "rc=$LV_RC$lv_fail :: $(tail -8 "$LV_LOG" | tr '\n' '|')"
  fi
done

# ---- 2i-ter. M10/M11 downgrade: hiding the worktree manifest must not buy the legacy route --
# The canonical tree is VERIFIED from committed objects; the WORKTREE's manifest is deleted after
# the commit. UNVERIFIED_LEGACY_SOURCE is M10's fallback for a source that has no manifest
# ANYWHERE — never for one whose worktree hides it, or a single `rm` downgrades "unprovable bytes
# abort" into "unprovable bytes install". The control flow already refused this at 7f173f3; what
# was missing is any case pinning it, and a diagnostic that names the file the consumed tree lacks.
for helper in "H-" "H+"; do
  MH="$(bnd_plain_case "$B3_ROOT/hidemanifest-$helper")"
  MHS="$MH/.fusebase-flow-source"
  [ "$helper" = "H-" ] && rm -f "$MH/hooks/local/lib/materialize-managed-source.sh"
  rm -f "$MHS/hooks/local/lib/materialize-managed-source.sh"
  bnd_legacy_engine "$MHS"
  ( cd "$MHS" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  bnd_git_source "$MHS"
  rm -f "$MHS/audit/managed-content-manifest.json"
  MH_LOG="$B3_ROOT/hidemanifest-$helper.log"
  ( cd "$MH" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source --ref main \
      -- --auto-yes ) > "$MH_LOG" 2>&1
  MH_RC=$?
  mh_fail=""
  [ "$MH_RC" -ne 0 ] || mh_fail="$mh_fail [hiding the worktree manifest upgraded anyway (rc 0)]"
  grep -q "ABORT" "$MH_LOG" || mh_fail="$mh_fail [no abort diagnostic]"
  grep -q "audit/managed-content-manifest.json" "$MH_LOG" \
    || mh_fail="$mh_fail [the abort does not name audit/managed-content-manifest.json — the operator cannot tell WHICH file the consumed tree is missing]"
  grep -q "UNVERIFIED_LEGACY_SOURCE" "$MH_LOG" \
    && mh_fail="$mh_fail [routed to the legacy fallback although the canonical tree ships the manifest — M10 reserves that for manifest-ABSENT sources]"
  [ ! -f "$MH/legacy-engine-argv.txt" ] || mh_fail="$mh_fail [the engine ran on the hidden-manifest worktree]"
  grep -q "control v1" "$MH/hooks/local/control.sh" || mh_fail="$mh_fail [content was written during the abort]"
  if [ -z "$mh_fail" ]; then
    ok "m10-hiding-the-worktree-manifest-does-not-downgrade-to-the-legacy-route-git-$helper"
  else
    bad "m10-hiding-the-worktree-manifest-does-not-downgrade-to-the-legacy-route-git-$helper" "rc=$MH_RC$mh_fail :: $(tail -8 "$MH_LOG" | tr '\n' '|')"
  fi
done

# ---- 2i-quater. B5: choosing a TRUSTED verifier FILE is not enough ---------------------------
# B4 made Step 2c run the canonical tree's managed_content_manifest.py. That fixes WHICH SCRIPT
# runs and says nothing about WHICH CODE the interpreter executes first: plain `python3 <file>`
# still imports `sitecustomize` from sys.path, so a startup file reachable from the JUDGED tree
# (an inherited PYTHONPATH is the whole exploit) runs BEFORE the trusted verifier, prints a MATCH
# document and os._exit(0)s. The verifier never executes. This is the repository's own catalogued
# class (test-trusted-enforcer.sh T29/T30, hook_manifest.py STARTUP_BASENAMES), one layer below
# B4. Here the WORKTREE VERIFIER IS HONEST and the payload alone is tampered: the only thing
# standing between the consumer and those bytes is whether the interpreter was hardened.
for helper in "H-" "H+"; do
  SV="$(bnd_plain_case "$B3_ROOT/startupinject-$helper")"
  SVS="$SV/.fusebase-flow-source"
  [ "$helper" = "H-" ] && rm -f "$SV/hooks/local/lib/materialize-managed-source.sh"
  rm -f "$SVS/hooks/local/lib/materialize-managed-source.sh"
  bnd_legacy_engine "$SVS"
  ( cd "$SVS" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  bnd_git_source "$SVS"
  # Payload tampered AFTER the commit; the verifier is left exactly as committed.
  printf 'control TAMPERED\n' > "$SVS/hooks/local/control.sh"
  mkdir -p "$SVS/hooks"
  cat > "$SVS/hooks/sitecustomize.py" <<'STARTUP'
import os, sys
sys.stdout.write('{"verdict": "MATCH", "listed": 0, "files": []}\n')
sys.stdout.flush()
os._exit(0)
STARTUP
  SV_LOG="$B3_ROOT/startupinject-$helper.log"
  ( cd "$SV" && PYTHONPATH="$SVS/hooks" bash hooks/local/bootstrap-upgrade.sh \
      --source .fusebase-flow-source --ref main -- --auto-yes ) > "$SV_LOG" 2>&1
  SV_RC=$?
  sv_fail=""
  [ "$SV_RC" -ne 0 ] || sv_fail="$sv_fail [a hostile python startup file forged the verdict and the upgrade completed (rc 0)]"
  grep -q "ABORT" "$SV_LOG" || sv_fail="$sv_fail [no abort diagnostic]"
  grep -q "audit/managed-content-manifest.json" "$SV_LOG" \
    || sv_fail="$sv_fail [the abort does not name audit/managed-content-manifest.json]"
  grep -q "hooks/local/control.sh" "$SV_LOG" \
    || sv_fail="$sv_fail [the offending payload path is not named]"
  grep -q "control v1" "$SV/hooks/local/control.sh" || sv_fail="$sv_fail [tampered bytes were installed]"
  [ ! -f "$SV/legacy-engine-argv.txt" ] || sv_fail="$sv_fail [the engine ran despite the abort]"
  if [ -z "$sv_fail" ]; then
    ok "b5-hostile-python-startup-file-cannot-forge-the-source-verdict-git-$helper"
  else
    bad "b5-hostile-python-startup-file-cannot-forge-the-source-verdict-git-$helper" "rc=$SV_RC$sv_fail :: $(tail -8 "$SV_LOG" | tr '\n' '|')"
  fi
done

# ---- 2i-quinquies. B5b: a MATCH TOKEN is not a MATCH VERDICT ---------------------------------
# The rc-0 success case used to be a substring test for `"verdict": "MATCH"` anywhere in the
# payload. A verifier replaced with something that emits an unparseable blob CONTAINING that
# token — a truncated write, a wrapper that prepends noise, an attacker who only controls part
# of the output — was therefore read as a clean tree. PLAIN transport on purpose: the snapshot
# is a byte copy of the worktree, so the source's OWN verifier is the one that answers and the
# trusted-verifier fix of B4 cannot mask the parsing question. Both helper shapes run because
# the two carriers (bootstrap's embedded ff_boot_verify, the lib's _ff_mms_verify) each had
# their own copy of the substring test.
for helper in "H-" "H+"; do
  TK="$(bnd_plain_case "$B3_ROOT/matchtoken-$helper")"
  TKS="$TK/.fusebase-flow-source"
  [ "$helper" = "H-" ] && rm -f "$TK/hooks/local/lib/materialize-managed-source.sh"
  rm -f "$TKS/hooks/local/lib/materialize-managed-source.sh"
  bnd_legacy_engine "$TKS"
  ( cd "$TKS" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  printf 'control TAMPERED\n' > "$TKS/hooks/local/control.sh"
  cat > "$TKS/hooks/local/lib/managed_content_manifest.py" <<'TOKEN'
import sys
sys.stdout.write('managed-content OK -- "verdict": "MATCH" (listed 285, drifted 0)\n')
sys.exit(0)
TOKEN
  TK_LOG="$B3_ROOT/matchtoken-$helper.log"
  ( cd "$TK" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source --ref main \
      -- --auto-yes ) > "$TK_LOG" 2>&1
  TK_RC=$?
  tk_fail=""
  [ "$TK_RC" -ne 0 ] || tk_fail="$tk_fail [an unparseable payload carrying a MATCH token was accepted as a verdict (rc 0)]"
  grep -q "ABORT" "$TK_LOG" || tk_fail="$tk_fail [no abort diagnostic]"
  grep -q "audit/managed-content-manifest.json" "$TK_LOG" \
    || tk_fail="$tk_fail [the abort does not name audit/managed-content-manifest.json]"
  grep -q "parseable MATCH verdict" "$TK_LOG" \
    || tk_fail="$tk_fail [the diagnostic does not say the verdict failed to PARSE — an operator reading it cannot tell this from ordinary drift]"
  grep -q "control v1" "$TK/hooks/local/control.sh" || tk_fail="$tk_fail [tampered bytes were installed]"
  [ ! -f "$TK/legacy-engine-argv.txt" ] || tk_fail="$tk_fail [the engine ran despite the abort]"
  if [ -z "$tk_fail" ]; then
    ok "b5-match-token-in-unparseable-output-is-not-a-verdict-plain-$helper"
  else
    bad "b5-match-token-in-unparseable-output-is-not-a-verdict-plain-$helper" "rc=$TK_RC$tk_fail :: $(tail -8 "$TK_LOG" | tr '\n' '|')"
  fi
done

# ---- 2i-sexies. B6: the manifest proves the MANAGED set, and the engine reads more than that -
# managed_content_manifest.py's MANAGED_DIRS/MANAGED_FILES exclude VERSION and docs/, but the
# shipped v4.7.0 tag engine reads .fusebase-flow-source/VERSION and writes it into the consumer,
# and --with-framework-docs copies .fusebase-flow-source/docs/*.md verbatim. So a clean commit
# whose WORKTREE tampers ONLY those two files satisfies the verifier (managed content really is
# clean) AND the manifest cmp (nobody re-stamped anything) — and the tampered bytes install.
# "The consumed tree is proven" was true of the managed subset and false of what is consumed.
# NOTE the fixture engine: it copies both unmanifested inputs, exactly like the tag engine.
for helper in "H-" "H+"; do
  UB="$(bnd_plain_case "$B3_ROOT/unbound-$helper")"
  UBS="$UB/.fusebase-flow-source"
  [ "$helper" = "H-" ] && rm -f "$UB/hooks/local/lib/materialize-managed-source.sh"
  rm -f "$UBS/hooks/local/lib/materialize-managed-source.sh"
  mkdir -p "$UBS/docs" "$UB/docs"
  printf 'framework v2\n' > "$UBS/docs/framework.md"
  printf 'framework v1\n' > "$UB/docs/framework.md"
  cat > "$UBS/hooks/local/upgrade.sh" <<'LEGACYUB'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" > "./legacy-engine-argv.txt"
cp ".fusebase-flow-source/hooks/local/control.sh" "hooks/local/control.sh"
cp ".fusebase-flow-source/docs/framework.md" "docs/framework.md"
tr -d '\n\r' < ".fusebase-flow-source/VERSION" > VERSION
exit 0
LEGACYUB
  ( cd "$UBS" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  bnd_git_source "$UBS"
  # AFTER the commit, and ONLY outside the managed set: managed content stays clean on purpose,
  # so neither the verifier nor the manifest cmp has anything to say about this.
  printf '9.9.9\n'              > "$UBS/VERSION"
  printf 'framework TAMPERED\n' > "$UBS/docs/framework.md"
  UB_LOG="$B3_ROOT/unbound-$helper.log"
  ( cd "$UB" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source --ref main \
      -- --auto-yes ) > "$UB_LOG" 2>&1
  UB_RC=$?
  ub_fail=""
  [ "$UB_RC" -ne 0 ] || ub_fail="$ub_fail [tampering only the UNMANIFESTED inputs upgraded anyway (rc 0)]"
  grep -q "ABORT" "$UB_LOG" || ub_fail="$ub_fail [no abort diagnostic]"
  grep -qE '^ +VERSION' "$UB_LOG" \
    || ub_fail="$ub_fail [the abort does not name VERSION as an offending path]"
  grep -qE '^ +docs/framework\.md' "$UB_LOG" \
    || ub_fail="$ub_fail [the abort does not name docs/framework.md as an offending path]"
  [ ! -f "$UB/legacy-engine-argv.txt" ] || ub_fail="$ub_fail [the engine ran despite the abort]"
  grep -q "4.6.1" "$UB/VERSION" || ub_fail="$ub_fail [a tampered VERSION was installed]"
  grep -q "framework v1" "$UB/docs/framework.md" || ub_fail="$ub_fail [a tampered doc was installed]"
  if [ -z "$ub_fail" ]; then
    ok "b6-unmanifested-inputs-the-engine-reads-are-bound-to-the-canonical-tree-git-$helper"
  else
    bad "b6-unmanifested-inputs-the-engine-reads-are-bound-to-the-canonical-tree-git-$helper" "rc=$UB_RC$ub_fail :: $(tail -8 "$UB_LOG" | tr '\n' '|')"
  fi
done

# NEGATIVE CONTROL for 2i-sexies. The binding above is CR-INSENSITIVE, and it has to be: a
# staging worktree is checked out under the CONSUMER's core.autocrlf while the canonical tree is
# forced LF (M1), so a byte cmp here would abort clean Windows upgrades. A worktree whose VERSION
# differs from the canonical tree by CR ALONE must therefore still upgrade — if this case ever
# starts failing, the guard above has been tightened into a false-rejection of ordinary consumers.
NC="$(bnd_plain_case "$B3_ROOT/unbound-crlf-nc")"
NCS="$NC/.fusebase-flow-source"
rm -f "$NCS/hooks/local/lib/materialize-managed-source.sh"
bnd_legacy_engine "$NCS"
( cd "$NCS" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
bnd_git_source "$NCS"
printf '4.7.0\r\n' > "$NCS/VERSION"          # same value, CRLF instead of LF
NC_LOG="$B3_ROOT/unbound-crlf-nc.log"
( cd "$NC" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source --ref main \
    -- --auto-yes ) > "$NC_LOG" 2>&1
NC_RC=$?
nc_fail=""
[ "$NC_RC" -eq 0 ] || nc_fail="$nc_fail [a CR-only difference in an unmanifested input aborted a clean upgrade]"
grep -q "does not cover but the engine still consumes" "$NC_LOG" \
  && nc_fail="$nc_fail [the unbound-input guard fired on a CR-only difference]"
[ -f "$NC/legacy-engine-argv.txt" ] || nc_fail="$nc_fail [the engine never ran]"
grep -q "control v2" "$NC/hooks/local/control.sh" || nc_fail="$nc_fail [content was not refreshed]"
if [ -z "$nc_fail" ]; then
  ok "b6-negative-control-cr-only-difference-still-upgrades-git"
else
  bad "b6-negative-control-cr-only-difference-still-upgrades-git" "rc=$NC_RC$nc_fail :: $(tail -8 "$NC_LOG" | tr '\n' '|')"
fi

rm -rf "$B3_ROOT"
finish
