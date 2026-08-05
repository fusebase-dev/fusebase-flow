#!/usr/bin/env bash
# Fusebase Flow — local gate parity with the CI manifest-freshness steps.
# Backlog: docs/backlog/local-gate-misses-manifest-freshness/README.md (AC1..AC3).
#
# WHAT THIS PROVES:
#   CI runs `stamp-*-manifest.sh` then `git diff --exit-code`, then `verify-*-manifest.sh`.
#   The local suite had no equivalent, so a change to a manifest-collected file that forgot to
#   re-stamp passed locally (625/625 at eca925b) and reddened main. These assertions replay both
#   CI steps against the ACTUAL tree.
#
# WHY IT STAMPS TO A SCRATCH PATH:
#   AC2 — a freshness checker that stamps IN PLACE masks the very drift it tests for: it would
#   rewrite the manifest to match the tree and then find no difference, forever green. `--out`
#   sends the recomputed manifest to a temp file; the committed manifest is never written.
#
# COVERAGE SPLIT (both arms are needed; neither subsumes the other):
#   verify  -> modified/missing listed assets + import-adjacent extras. Exit 1 names each path.
#   stamp+diff -> everything verify's extra-scan does not reach, e.g. a NEW collected file under
#                 hooks/local/*.sh or hooks/tests/* that is simply absent from the listing.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: manifest-freshness <name>" / "FAIL: manifest-freshness <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOOK_MANIFEST="$ROOT/audit/hook-layer-manifest.json"
MC_MANIFEST="$ROOT/audit/managed-content-manifest.json"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: manifest-freshness $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: manifest-freshness $1 (${2:-})"; }
finish() { echo "[test-manifest-freshness] $pass/$((pass + fail)) PASS"; exit $fail; }

TMPDIR_MF="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/mf-$$")"
mkdir -p "$TMPDIR_MF"

# TRIPWIRE: the red arm below temporarily edits a real collected file. This trap is the ONLY
# thing standing between an interrupted run and a dirty tree — restore is unconditional and
# runs before the temp dir is removed. Never convert it to a conditional cleanup.
REDARM_TARGET="$ROOT/hooks/local/stamp-managed-content-manifest.sh"
REDARM_BACKUP="$TMPDIR_MF/redarm.bak"
_mf_cleanup() {
    if [ -f "$REDARM_BACKUP" ]; then
        cp -p "$REDARM_BACKUP" "$REDARM_TARGET" 2>/dev/null || true
    fi
    rm -rf "$TMPDIR_MF" 2>/dev/null || true
}
trap _mf_cleanup EXIT

for f in "$HOOK_MANIFEST" "$MC_MANIFEST"; do
    [ -f "$f" ] || { bad "setup-manifest-present" "missing $f"; finish; }
done

# AC2 baseline. Snapshot the committed manifests' CONTENT before any check runs, and compare
# content after. Deliberately NOT `git diff`: that asks "does this match the index", which goes
# red the moment a legitimate restamp is staged for commit, and green if a check both wrote the
# manifest AND the tree happened to be stale in the same way. Content in / content out is the
# only question AC2 asks.
_mf_sha() { python3 -c "
import hashlib,sys
print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())
" "$1" 2>/dev/null || echo "UNREADABLE"; }
HOOK_SHA_BEFORE="$(_mf_sha "$HOOK_MANIFEST")"
MC_SHA_BEFORE="$(_mf_sha "$MC_MANIFEST")"

# --- AC1/green: verify arms agree the committed manifests match the tree -------------------
hv_out="$(bash "$ROOT/hooks/local/verify-hook-manifest.sh" 2>&1)"; hv_rc=$?
if [ "$hv_rc" -eq 0 ]; then
    ok "hook-layer-verify-clean"
else
    bad "hook-layer-verify-clean" "rc=$hv_rc; $(echo "$hv_out" | tr '\n' ' ')"
fi

mv_out="$(bash "$ROOT/hooks/local/verify-managed-content-manifest.sh" 2>&1)"; mv_rc=$?
if [ "$mv_rc" -eq 0 ]; then
    ok "managed-content-verify-clean"
else
    bad "managed-content-verify-clean" "rc=$mv_rc; $(echo "$mv_out" | tr '\n' ' ')"
fi

# --- AC1/green: recomputed manifests are byte-identical to the committed ones ---------------
# This is the `stamp` + `git diff --exit-code` CI step, redirected away from the tree.
hs="$TMPDIR_MF/hook-layer.json"
if bash "$ROOT/hooks/local/stamp-hook-manifest.sh" --out "$hs" >/dev/null 2>&1 \
   && cmp -s "$HOOK_MANIFEST" "$hs"; then
    ok "hook-layer-restamp-identical"
else
    bad "hook-layer-restamp-identical" "recomputed manifest differs; run stamp-hook-manifest.sh and commit"
fi

ms="$TMPDIR_MF/managed-content.json"
if bash "$ROOT/hooks/local/stamp-managed-content-manifest.sh" --out "$ms" >/dev/null 2>&1 \
   && cmp -s "$MC_MANIFEST" "$ms"; then
    ok "managed-content-restamp-identical"
else
    bad "managed-content-restamp-identical" "recomputed manifest differs; run stamp-managed-content-manifest.sh and commit"
fi

# --- AC2: the checks did not write either committed manifest -------------------------------
if [ "$(_mf_sha "$HOOK_MANIFEST")" = "$HOOK_SHA_BEFORE" ] \
   && [ "$(_mf_sha "$MC_MANIFEST")" = "$MC_SHA_BEFORE" ]; then
    ok "checks-do-not-mutate-committed-manifests"
else
    bad "checks-do-not-mutate-committed-manifests" "a manifest was written during the check — an in-place stamp masks the drift it tests for"
fi

# --- AC3 red arm: plant a whitespace edit in a collected file; the check MUST fail ----------
if [ -f "$REDARM_TARGET" ]; then
    REDARM_SHA_BEFORE="$(_mf_sha "$REDARM_TARGET")"
    cp -p "$REDARM_TARGET" "$REDARM_BACKUP"
    printf '\n' >> "$REDARM_TARGET"

    red_out="$(bash "$ROOT/hooks/local/verify-hook-manifest.sh" 2>&1)"; red_rc=$?
    if [ "$red_rc" -ne 0 ] && echo "$red_out" | grep -q "stamp-managed-content-manifest.sh"; then
        ok "red-arm-planted-edit-fails-and-names-the-path"
    else
        bad "red-arm-planted-edit-fails-and-names-the-path" "rc=$red_rc; expected non-zero naming the edited path"
    fi

    # Restore, then prove the restore was byte-exact — a red arm that leaves the tree dirty
    # would turn every subsequent run of this suite red for the wrong reason.
    cp -p "$REDARM_BACKUP" "$REDARM_TARGET"
    rm -f "$REDARM_BACKUP"
    if [ "$(_mf_sha "$REDARM_TARGET")" = "$REDARM_SHA_BEFORE" ]; then
        ok "red-arm-restores-the-tree-exactly"
    else
        bad "red-arm-restores-the-tree-exactly" "planted edit was not fully reverted — subsequent runs would go red for the wrong reason"
    fi
else
    bad "red-arm-target-present" "missing $REDARM_TARGET"
fi

finish
