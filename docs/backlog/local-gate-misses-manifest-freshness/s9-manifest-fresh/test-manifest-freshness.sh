#!/usr/bin/env bash
# Fusebase Flow — the local gate must fail where CI fails: manifest freshness.
#
# WHY THIS EXISTS
#   CI's `verify` job re-stamps audit/hook-layer-manifest.json and
#   audit/managed-content-manifest.json and requires the re-stamp to be a NO-OP
#   (.github/workflows/fusebase-flow-verify.yml § "Hook-layer manifest freshness" /
#   "Managed-content manifest freshness"). The local suite had no such assertion, so a commit
#   that touched a covered path but skipped the re-stamp passed locally and reddened BOTH
#   hosted platforms — deterministically, since it is a content check, not a flake. Six
#   occurrences (backlog: local-gate-misses-manifest-freshness); six means the missing
#   assertion is the defect, not the forgetting.
#
# SIDE-EFFECT DISCIPLINE — READ THIS BEFORE CHANGING ANYTHING HERE
#   A gate test must NOT mutate the tree it judges. An earlier version of this phase (and the
#   2026-08-05 attempt before it) snapshotted the real manifests, stamped over them, and
#   restored under an `EXIT` trap. Adversarial review rejected that and was right: the trap
#   does not survive SIGKILL, cannot run on a read-only checkout, and two concurrent runs can
#   restore each other's backups and leave the tree dirty. Both conditions are real on this
#   project — a SIGKILLed harness and concurrent suites have both occurred.
#
#   So every arm here is one of:
#     (a) read-only against the judged tree (the verifiers, the eol scan), or
#     (b) executed inside a DISPOSABLE scratch worktree checked out from a ref.
#   The judged working tree is never written to. The only footprint outside it is a git
#   worktree registration under .git/worktrees/, pruned defensively at start and removed at
#   the end; a SIGKILL leaves at most a stale registration, which `git worktree prune` clears.
#
#   The scratch worktree is also the only way to test the property HONESTLY: git materializes
#   it per .gitattributes, so it holds the bytes that actually SHIP. Stamping the local
#   working tree cannot see an eol defect at all — the stamper and the verifier both read the
#   same wrong bytes and agree with each other (that is exactly how a CRLF manifest shipped).
#
# COST: worktree add 1s + stamp 4s + managed stamp 1s + verifiers 3s ~= 10s on loaded MSYS.
#   Deliberately NOT in FF_FAST_TAGS: placement of this phase in the shipped default gate is
#   an OPEN OPERATOR DECISION (see the backlog entry) and promoting it would pre-empt that.
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

# The ref whose committed tree is judged. Defaults to HEAD (what CI checks out). Overridable
# ONLY so the RED arm is reproducible by anyone against a known-bad commit — it selects WHICH
# commit to judge, never whether the assertion holds.
FFMF_REF="${FFMF_REF:-HEAD}"

TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-manifest-fresh.$$"
mkdir -p "$TMP_BASE"
WT="$TMP_BASE/wt"

cleanup() {
  # TRIPWIRE: remove ONLY this phase's own worktree, by path. Never a blanket
  # `git worktree prune` — that deregisters ANY worktree whose directory is momentarily
  # unavailable, including other sessions' (four unrelated ones are registered in this repo
  # right now). A test phase must not touch shared repo metadata it does not own, and prune
  # is not needed for correctness: the $$-unique path means `worktree add` always succeeds.
  # A SIGKILL therefore leaks at most one stale admin entry, which a human `git worktree
  # prune` clears — strictly less harm than pruning other people's registrations every run.
  git worktree remove --force "$WT" >/dev/null 2>&1
  case "$TMP_BASE" in
    /tmp/fusebase-flow-manifest-fresh.*|*/tmp/fusebase-flow-manifest-fresh.*|*/Temp/fusebase-flow-manifest-fresh.*)
      rm -rf "$TMP_BASE" ;;
  esac
}
trap cleanup EXIT

for f in "$HOOK_MF" "$MANAGED_MF"; do
  [ -f "$ROOT/$f" ] || { bad setup-manifests-present "missing $f"; finish; }
done
ok setup-manifests-present

if ! git worktree add --detach "$WT" "$FFMF_REF" >/dev/null 2>&1; then
  bad setup-scratch-worktree "could not create a scratch worktree at $FFMF_REF"
  finish
fi
ok "setup-scratch-worktree (disposable checkout of $FFMF_REF; the judged tree is never written to)"

# wt_stamp_is_noop <stamp-script> <manifest-path> -> rc 0 iff re-stamping inside the scratch
# worktree leaves it byte-identical to what the ref committed. This is CI's exact property.
wt_stamp_is_noop() {
  ( cd "$WT" && bash "$1" >/dev/null 2>&1 ) || return 2
  git -C "$WT" diff --exit-code --quiet -- "$2"
}

###############################################################################
# The two properties CI enforces, evaluated on the bytes that ship.
###############################################################################
if wt_stamp_is_noop hooks/local/stamp-hook-manifest.sh "$HOOK_MF"; then
  ok "hook-layer-manifest-fresh (re-stamp of the committed tree is a no-op; CI step 'Hook-layer manifest freshness' would pass)"
else
  bad hook-layer-manifest-fresh "re-stamping $HOOK_MF in a clean checkout of $FFMF_REF changed it — the committed manifest does not describe the committed tree. Fix: bash hooks/local/stamp-hook-manifest.sh && git add $HOOK_MF"
fi

if wt_stamp_is_noop hooks/local/stamp-managed-content-manifest.sh "$MANAGED_MF"; then
  ok "managed-content-manifest-fresh (re-stamp of the committed tree is a no-op; CI step 'Managed-content manifest freshness' would pass)"
else
  bad managed-content-manifest-fresh "re-stamping $MANAGED_MF in a clean checkout of $FFMF_REF changed it. Fix: bash hooks/local/stamp-managed-content-manifest.sh && git add $MANAGED_MF"
fi

###############################################################################
# CONTROL — prove the two rows above can fail. Runs LAST of the worktree arms because
# it dirties the scratch checkout; ordering is safe precisely because that checkout is
# disposable and is not the tree under judgement.
#
# TRIPWIRE: mutate a COVERED FILE, never a manifest. `wt_stamp_is_noop` stamps BEFORE it
# diffs, so a mutated manifest is regenerated and the mutation erased — the diff comes back
# clean and the control "passes" while testing nothing. An earlier version did exactly that
# and only revealed itself when the real rows went green and the control did not.
###############################################################################
printf '\n# transient control mutation (scratch worktree only)\n' >> "$WT/hooks/local/preflight.sh"
if wt_stamp_is_noop hooks/local/stamp-hook-manifest.sh "$HOOK_MF"; then
  bad control-detects-an-unstamped-covered-file "a modified covered file did not make the re-stamp diff — this phase cannot detect the class it exists to stop"
else
  ok "control-detects-an-unstamped-covered-file (a covered file changed without a re-stamp is caught; the rows above are not vacuous)"
fi

###############################################################################
# Read-only arms against the judged tree.
###############################################################################
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
# EOL normalization — the class the stamp-compare above now catches, asserted directly
# so the failure NAMES the offending path instead of only reporting a manifest diff.
#
# WHY: the stampers hash WORKING-TREE bytes. A file created on Windows with CRLF is
# normalized to LF in the index by `.gitattributes` (`*.sh`/`*.json text eol=lf`), but the
# working tree keeps the original CRLF until the path is re-checked-out. The manifest then
# records a digest of bytes that never ship — and locally the stamper and the verifier read
# the SAME wrong bytes and agree. MATCH locally, red in CI.
#
# Discriminator: only paths whose attributes REQUIRE lf in the worktree (`eol=lf`) count.
# `text=auto` paths are legitimately `w/crlf` on Windows; flagging those would be noise.
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

# CONTROL: feed the detector a synthetic listing carrying a known offender plus the three
# shapes that must NOT fire. A detector that flags nothing would sail through the real row on
# a clean tree and prove nothing.
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
  bad no-eol-mismatched-covered-paths "$(printf '%s' "$offenders" | tr '\n' ' ') -- the stamper hashes working-tree bytes, so the manifests describe bytes that never ship; CI checks out lf and disagrees. Fix: remove the worktree copy and re-checkout (git checkout-index -f) so git materializes it per .gitattributes; do not hand-edit bytes"
fi

finish
