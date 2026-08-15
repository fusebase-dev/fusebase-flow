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

python_bin="${PYTHON:-python3}"
command -v "$python_bin" >/dev/null 2>&1 || python_bin="python"

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
# A freshness check that cannot detect staleness is exactly the gap that let six
# occurrences through, so it is demonstrated, not assumed.
#
# TRIPWIRE: the control must mutate a COVERED FILE, never the manifest. Mutating the
# manifest proves nothing — `stamp_is_noop` runs the stamp FIRST, which regenerates the
# manifest from the covered files and silently erases the mutation, so the diff comes back
# clean and the control "passes" while testing nothing. (That is exactly what the first
# version of this row did.) An untracked NEW file under a covered path reproduces the real
# shape of the class: a covered path moved, no re-stamp followed.
###############################################################################
CONTROL_FILE="$ROOT/hooks/tests/zz-manifest-freshness-control.sh"
control_cleanup() { rm -f "$CONTROL_FILE" 2>/dev/null; }
trap 'control_cleanup; restore' EXIT
printf '#!/usr/bin/env bash\n# transient control artifact; deleted by test-manifest-freshness.sh\nexit 0\n' > "$CONTROL_FILE"
if stamp_is_noop hooks/local/stamp-hook-manifest.sh "$HOOK_MF"; then
  bad control-detects-an-unstamped-covered-file "a NEW covered file under hooks/tests/ did not make the re-stamp diff — this phase cannot detect the class it exists to stop"
else
  ok "control-detects-an-unstamped-covered-file (a new covered file is caught; the check discriminates)"
fi
control_cleanup
cp "$TMP_BASE/hook.json" "$ROOT/$HOOK_MF"             # undo the control's re-stamp

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

###############################################################################
# EOL normalization — the one class the four rows above CANNOT see, by construction.
#
# WHY: the stamper hashes WORKING-TREE bytes. A file created on Windows with CRLF is
# normalized to LF in the index by `.gitattributes` (`*.sh`/`*.json text eol=lf`), but the
# working tree keeps the original CRLF until the path is re-checked-out. So the manifest
# records a digest of bytes that never ship. Locally the stamper and the verifier read the
# SAME wrong bytes and agree with each other — MATCH, every time — while CI checks out LF
# and disagrees. Same shape as the two defects this branch already fixed: provenance that
# describes the local copy instead of the artifact, and a check that cannot fail.
#
# This is why the row exists at all: no amount of re-stamping or re-verifying finds it.
# Discriminator: only paths whose attributes REQUIRE lf in the worktree (`eol=lf`) count.
# `text=auto` paths are legitimately `w/crlf` on Windows — flagging those would be noise.
###############################################################################
eol_offenders() {   # eol_offenders <ls-files-eol-listing-file> -> one "path (i/x w/y)" per line
  "$python_bin" - "$1" <<'PY'
import re, sys, pathlib
for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines():
    # TRIPWIRE: the attr field CONTAINS A SPACE ("attr/text eol=lf"), so it must be matched
    # non-greedily up to the TAB before the path — not with \S+, which stops at that space,
    # matches nothing, and makes this detector silently report zero offenders on every input.
    # Its first version did exactly that, and only the control row caught it.
    m = re.match(r"^i/(\S+)\s+w/(\S+)\s+attr/(.*?)\t(.*)$", line)
    if not m:
        continue
    idx, work, attr, path = m.groups()
    if "eol=lf" not in attr:      # text=auto: w/crlf on Windows is correct, not a defect
        continue
    # "-" binary · "none" empty / no line endings at all (e.g. .gitkeep) · "lf" already correct
    if work in ("-", "none", "lf"):
        continue
    print(f"{path} (i/{idx} w/{work} attr/{attr})")
PY
}

# CONTROL: feed the detector a synthetic listing carrying a known offender plus the two
# shapes that must NOT be flagged. A detector that flags nothing would sail through the real
# row on a clean tree and prove nothing — the same trap the freshness control fell into.
cat > "$TMP_BASE/eol-control.txt" <<'EOL'
i/lf	w/crlf	attr/text eol=lf      	fake/offender.sh
i/lf	w/crlf	attr/text=auto        	fake/legit-autocrlf.example
i/lf	w/lf	attr/text eol=lf      	fake/correct.sh
i/-	w/-	attr/-                	fake/binary.png
EOL
cout="$(eol_offenders "$TMP_BASE/eol-control.txt")"
if [ "$(printf '%s' "$cout" | grep -c .)" = "1" ] && printf '%s' "$cout" | grep -q "fake/offender.sh"; then
  ok "control-eol-detector-discriminates (flags the eol=lf offender; ignores text=auto, correct-lf and binary)"
else
  bad control-eol-detector-discriminates "expected exactly fake/offender.sh, got: $cout"
fi

git ls-files --eol > "$TMP_BASE/eol-real.txt" 2>/dev/null
offenders="$(eol_offenders "$TMP_BASE/eol-real.txt")"
if [ -z "$offenders" ]; then
  ok "no-eol-mismatched-covered-paths (every eol=lf path is lf in the working tree, so the stamper hashes the bytes that actually ship)"
else
  bad no-eol-mismatched-covered-paths "$(printf '%s' "$offenders" | tr '\n' ' ') -- the stamper hashes working-tree bytes, so these manifests describe bytes that never ship; CI checks out lf and disagrees. Fix: git rm --cached -- <path> is NOT it; remove the worktree copy and re-checkout so git materializes it per .gitattributes"
fi

finish
