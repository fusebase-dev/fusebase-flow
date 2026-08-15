#!/usr/bin/env bash
# Fusebase Flow — the local gate must fail where CI fails: manifest freshness.
#
# WHY THIS EXISTS (six occurrences of one class)
#   CI's `verify` job re-stamps audit/hook-layer-manifest.json and
#   audit/managed-content-manifest.json and requires the re-stamp to be a NO-OP
#   (.github/workflows/fusebase-flow-verify.yml § "Hook-layer manifest freshness" /
#   "Managed-content manifest freshness"). The local suite had no such assertion, so a
#   commit that touched a covered path but skipped the re-stamp passed locally and reddened
#   BOTH hosted platforms — deterministically, since it is a content check, not a flake.
#   That has now happened six times in this repo (backlog: local-gate-misses-manifest-freshness).
#
#   Six occurrences means the missing assertion is the defect, not the forgetting. This is
#   the assertion. Same shape as the `<%=` tripwire and the fingerprint-row invariant: an
#   invariant that holds by assertion rather than by remembering.
#
# SIDE-EFFECT DISCIPLINE
#   Re-stamping is the only way to test the property CI tests, and stamping writes the real
#   files. This phase therefore SNAPSHOTS both manifests first and restores them from the
#   snapshot on EVERY exit path (trap). Worst case — the harness is SIGKILLed mid-phase —
#   the tree keeps a freshly stamped manifest, which is the content CI wants anyway.
#
# COST: measured 8s total on loaded MSYS (verify 3s + hook stamp 4s + managed stamp 1s),
#   which is why this is one of the few phases promoted into FF_FAST_TAGS — an assertion
#   that only runs in the full tier would not have caught any of the six occurrences.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: manifest-fresh <name>" / "FAIL: manifest-fresh <name>"; exit code = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: manifest-fresh $1"; }
bad() { fail=$((fail + 1)); local w="${2:-}"; [ -z "$w" ] || w=" ($(printf '%s' "$w" | tr '\n\r\t' '   ' | cut -c1-400))"; echo "FAIL: manifest-fresh $1$w"; }
finish() { echo "[test-manifest-freshness] $pass/$((pass + fail)) PASS"; exit $fail; }

HOOK_MF="audit/hook-layer-manifest.json"
MANAGED_MF="audit/managed-content-manifest.json"

TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-manifest-fresh.$$"
mkdir -p "$TMP_BASE"

# TRIPWIRE: restore BEFORE removing the snapshot dir, and do both on every exit path. A
# phase that can leave a mutated manifest behind would corrupt the very artifact it guards.
restore() {
  [ -f "$TMP_BASE/hook.json" ]    && cp "$TMP_BASE/hook.json"    "$ROOT/$HOOK_MF"    2>/dev/null
  [ -f "$TMP_BASE/managed.json" ] && cp "$TMP_BASE/managed.json" "$ROOT/$MANAGED_MF" 2>/dev/null
  case "$TMP_BASE" in
    /tmp/fusebase-flow-manifest-fresh.*|*/tmp/fusebase-flow-manifest-fresh.*|*/Temp/fusebase-flow-manifest-fresh.*)
      rm -rf "$TMP_BASE" ;;
  esac
}
trap restore EXIT

for f in "$HOOK_MF" "$MANAGED_MF"; do
  [ -f "$ROOT/$f" ] || { bad setup-manifests-present "missing $f"; finish; }
done
cp "$ROOT/$HOOK_MF"    "$TMP_BASE/hook.json"
cp "$ROOT/$MANAGED_MF" "$TMP_BASE/managed.json"
ok setup-manifests-present

# stamp_is_noop <stamp-script> <manifest-path> -> rc 0 iff re-stamping changed nothing.
# Mirrors CI exactly: run the stamp, then `git diff --exit-code` on the manifest.
stamp_is_noop() {
  bash "$1" >/dev/null 2>&1 || return 2
  git diff --exit-code --quiet -- "$2"
}

###############################################################################
# CONTROL FIRST — prove the assertion can fail before trusting that it passes.
# A freshness check that cannot detect a stale manifest is exactly the gap that let
# six occurrences through, so it is demonstrated, not assumed.
###############################################################################
printf '\n' >> "$ROOT/$HOOK_MF"                       # a stale/edited manifest
if stamp_is_noop hooks/local/stamp-hook-manifest.sh "$HOOK_MF"; then
  bad control-detects-a-stale-manifest "a deliberately mutated $HOOK_MF still read as fresh — this phase proves nothing"
else
  ok "control-detects-a-stale-manifest (a mutated hook-layer manifest is caught; the check discriminates)"
fi
cp "$TMP_BASE/hook.json" "$ROOT/$HOOK_MF"             # undo the control mutation

###############################################################################
# The real assertions — the same two properties CI enforces.
###############################################################################
if stamp_is_noop hooks/local/stamp-hook-manifest.sh "$HOOK_MF"; then
  ok "hook-layer-manifest-fresh (re-stamp is a no-op; CI step 'Hook-layer manifest freshness' would pass)"
else
  bad hook-layer-manifest-fresh "re-stamping $HOOK_MF changed it — a covered path moved without a re-stamp. Fix: bash hooks/local/stamp-hook-manifest.sh && git add $HOOK_MF"
fi
cp "$TMP_BASE/hook.json" "$ROOT/$HOOK_MF"

if stamp_is_noop hooks/local/stamp-managed-content-manifest.sh "$MANAGED_MF"; then
  ok "managed-content-manifest-fresh (re-stamp is a no-op; CI step 'Managed-content manifest freshness' would pass)"
else
  bad managed-content-manifest-fresh "re-stamping $MANAGED_MF changed it — a managed path moved without a re-stamp. Fix: bash hooks/local/stamp-managed-content-manifest.sh && git add $MANAGED_MF"
fi
cp "$TMP_BASE/managed.json" "$ROOT/$MANAGED_MF"

# The verifiers CI runs after each stamp. verify-hook-manifest also catches an EXTRA covered
# file that no stamp was ever run for, which is the shape most of the six occurrences took.
vout="$(bash hooks/local/verify-hook-manifest.sh 2>&1)"; vrc=$?
if [ "$vrc" -eq 0 ] && printf '%s' "$vout" | grep -q "MATCH"; then
  ok "verify-hook-manifest-MATCH"
else
  bad verify-hook-manifest-MATCH "rc=$vrc $vout"
fi

mout="$(bash hooks/local/verify-managed-content-manifest.sh 2>&1)"; mrc=$?
if [ "$mrc" -eq 0 ] && printf '%s' "$mout" | grep -q "MATCH"; then
  ok "verify-managed-content-manifest-MATCH"
else
  bad verify-managed-content-manifest-MATCH "rc=$mrc $mout"
fi

finish
