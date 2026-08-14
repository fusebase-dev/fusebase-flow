#!/usr/bin/env bash
# Fusebase Flow — every release tag must carry a fingerprint row (consumer finding N3).
# WHY-home: docs/backlog/fingerprint-row-driven-by-publish-not-tag/README.md
#
# WHAT IT DRIVES: hooks/local/preflight.sh section 10 against a REAL local clone of THIS repo,
# with THIS repo's real tags. Nothing is simulated with string fixtures: the discriminator row
# removes the `v4.9.1` row — the exact row that shipped missing inside v4.9.2's permanent tree —
# and requires preflight to name v4.9.1. Restored, it must go quiet again.
#
# ROW CLASSES:
#   CONTROL        green tree stays green (a check that always fires blocks every release).
#   DISCRIMINATOR  red against the pre-fix tree, where nothing asserted the row at all.
#   EXEMPTION      a tag AT HEAD must not fail its own missing row — a tagged tree cannot
#                  contain its own row, so without this the check makes releasing impossible.
#                  Paired with a scoping control: the exemption must not silence OTHER misses.
#
# TIER: heavy (clones the repo, runs preflight 4x). FF_ONLY=fingerprint-rows or FF_FULL=1.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: fingerprint-rows <name>" / "FAIL: fingerprint-rows <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FP_REL="docs/release-fingerprints.md"

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "PASS: fingerprint-rows $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL: fingerprint-rows $1 (${2:-})"; }
skip() { echo "PASS: fingerprint-rows $1 [SKIP — $2]"; pass=$((pass + 1)); }
finish() { echo "[test-fingerprint-row-per-tag] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v git >/dev/null 2>&1 || { skip "setup" "no git"; finish; }
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { skip "setup" "not a git repo"; finish; }
# The oracle is THIS repo's real tag history; a tagless tree cannot drive it.
git -C "$ROOT" rev-parse -q --verify refs/tags/v4.9.1 >/dev/null 2>&1 \
  || { skip "setup" "tag v4.9.1 absent — the N3 oracle needs the real tag history"; finish; }

CLONE="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-fprow.XXXXXX" 2>/dev/null)"
[ -n "$CLONE" ] || { bad "setup" "could not create a temp dir"; finish; }
cleanup() { rm -rf "$CLONE" 2>/dev/null; }
trap cleanup EXIT
# --local: hardlinked object store, so this is cheap and carries every tag.
if ! git clone --quiet --local "$ROOT" "$CLONE/repo" >/dev/null 2>&1; then
  bad "setup" "could not clone the repo into $CLONE"; finish
fi
REPO="$CLONE/repo"
FP="$REPO/$FP_REL"
# TRIPWIRE: the clone supplies the TAG HISTORY (that is the whole reason for cloning); the files
# UNDER TEST come from the working tree. A clone carries committed objects only, so without this
# the phase silently validated the previous commit — it graded the pre-fix preflight as passing
# while the working tree held the fix.
cp "$ROOT/hooks/local/preflight.sh" "$REPO/hooks/local/preflight.sh"
cp "$ROOT/$FP_REL" "$FP"
cp "$FP" "$CLONE/fingerprints.orig"

# fp_preflight: run preflight in the clone, echo ONLY its fingerprint-row error line (empty when
# the check is quiet). Preflight reports other things; this row asserts on its own message, so an
# unrelated warning elsewhere can neither mask nor fake it.
fp_preflight() {
  ( cd "$REPO" && bash hooks/local/preflight.sh 2>&1 ) | grep -F "has no row for tag(s)" || true
}

# --- CONTROL: the clone as-committed must be quiet -------------------------------------------
ctl="$(fp_preflight)"
if [ -z "$ctl" ]; then
  ok "green-tree-stays-green (every tag in the coverage window has a row => no error; a check that fires on a healthy tree would block every release)"
else
  bad "green-tree-stays-green" "clean clone reported a missing row: $ctl"
fi

# --- DISCRIMINATOR: the exact miss that shipped ----------------------------------------------
# v4.9.1 was tagged well before v4.9.2 was cut, so v4.9.2's tree COULD have carried its row.
grep -v '^| `v4.9.1` |' "$CLONE/fingerprints.orig" > "$FP"
red="$(fp_preflight)"
if printf '%s' "$red" | grep -q 'v4\.9\.1'; then
  ok "missing-row-fails-naming-the-tag (v4.9.1's row removed => preflight FAILS and names v4.9.1 — the exact row that shipped missing inside v4.9.2's permanent tree)"
else
  bad "missing-row-fails-naming-the-tag" "removing v4.9.1's row did not produce an error naming it; got: [$red]"
fi
# The remedy has to be actionable from the message alone.
if printf '%s' "$red" | grep -q 'print-release-fingerprints.sh.*v4\.9\.1'; then
  ok "failure-names-the-generating-command (message carries 'print-release-fingerprints.sh v4.9.1' — the row is generated, never hand-transcribed)"
else
  bad "failure-names-the-generating-command" "error does not name the generator + tag: [$red]"
fi

# --- CONTROL: restoring the row restores silence ---------------------------------------------
cp "$CLONE/fingerprints.orig" "$FP"
green="$(fp_preflight)"
if [ -z "$green" ]; then
  ok "restored-row-passes (row put back => check quiet again; it tracks the row, not some sticky state)"
else
  bad "restored-row-passes" "restoring the row left an error: $green"
fi

# --- EXEMPTION + its scoping control ----------------------------------------------------------
# Simulate cutting the next release: bump VERSION, commit, tag it AT HEAD. That tag can never
# have a row (self-reference limit), so it must NOT fail. In the SAME run, v4.9.1's row is
# removed — so the run also proves the exemption is scoped to the HEAD tag and does not silence
# a real miss.
grep -v '^| `v4.9.1` |' "$CLONE/fingerprints.orig" > "$FP"
(
  cd "$REPO" || exit 1
  git config user.email ffhc@example.invalid
  git config user.name  "ffhc test"
  echo "4.9.3" > VERSION
  git add VERSION "$FP_REL" >/dev/null 2>&1
  git commit -q -m "simulate the next release cut" >/dev/null 2>&1
  git tag v4.9.3
) >/dev/null 2>&1
ex="$(fp_preflight)"
if printf '%s' "$ex" | grep -q 'v4\.9\.3'; then
  bad "head-tag-is-exempt" "the tag AT HEAD (v4.9.3) was reported missing — a tagged tree cannot contain its own row, so this would make every release impossible: [$ex]"
else
  ok "head-tag-is-exempt (v4.9.3 tagged at HEAD with no row anywhere => not reported; the self-reference limit stays honoured and releases stay cuttable)"
fi
if printf '%s' "$ex" | grep -q 'v4\.9\.1'; then
  ok "exemption-is-scoped-not-a-mute (the same run still names v4.9.1 — exempting the HEAD tag does not switch the assertion off for every other tag)"
else
  bad "exemption-is-scoped-not-a-mute" "with a HEAD tag present the check stopped reporting the genuinely missing v4.9.1: [$ex]"
fi

finish
