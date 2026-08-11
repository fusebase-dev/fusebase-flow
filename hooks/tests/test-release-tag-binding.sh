#!/usr/bin/env bash
# Fusebase Flow — B2 discriminator: a force-moved tag must not publish unverified code.
# WHY-home: docs/specs/backlog-triage-execution/final-architecture-review.md finding 2.
#
# WHAT IT DRIVES: hooks/local/verify-tag-target.sh against a REAL git remote — a bare origin
# plus two working clones — so the tag genuinely moves out from under a checkout that already
# holds the old ref. Nothing here is simulated with string fixtures: the row that carries the
# claim (`moved-tag-refused`) is red against the pre-fix tree, where publication resolved the
# tag by NAME only (`gh release create --verify-tag`) and never compared its target.
#
# ROW CLASSES:
#   DISCRIMINATOR  red against the pre-fix behaviour (name-only tag matching).
#   CONTROL        passed before too; it exists to catch a REGRESSION (refusing a good tag).
#
# TIER: not in the fast local default (FF_FAST_TAGS is an allowlist — a new phase is heavy
# until measured). Reach it with FF_ONLY=release-tag-binding or FF_FULL=1; CI runs it.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: release-tag-binding <name>" / "FAIL: release-tag-binding <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT="$ROOT/hooks/local/verify-tag-target.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: release-tag-binding $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: release-tag-binding $1 (${2:-})"; }
finish() { echo "[test-release-tag-binding] $pass/$((pass + fail)) PASS, $fail FAIL"; exit $fail; }

[ -f "$SCRIPT" ] || { bad "setup-script-present" "missing $SCRIPT"; finish; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-tagbind.XXXXXX")" || { bad "setup-tmp" "mktemp failed"; finish; }
cleanup() { rm -rf "$TMP" 2>/dev/null; }
trap cleanup EXIT

# Identity + hook isolation: the fixture repos must never pick up this repository's git hooks
# or the operator's commit identity requirements.
G() { git -c user.email=tagbind@example.invalid -c user.name=tagbind -c core.hooksPath=/dev/null \
          -c core.autocrlf=false -c advice.detachedHead=false "$@"; }

ORIGIN="$TMP/origin.git"
WORK="$TMP/work"
CLONE="$TMP/clone"
TAG="v0.0.0-tagbind"

setup_ok=1
G init --bare -q "$ORIGIN" 2>/dev/null || setup_ok=0
G init -q "$WORK" 2>/dev/null || setup_ok=0
if [ "$setup_ok" -eq 1 ]; then
    (
        cd "$WORK" || exit 1
        printf 'verified\n' > file.txt
        G add file.txt && G commit -q -m "verified commit" \
          && G remote add origin "$ORIGIN" \
          && G push -q origin HEAD:refs/heads/main \
          && G tag "$TAG" \
          && G push -q origin "refs/tags/$TAG"
    ) || setup_ok=0
fi
[ "$setup_ok" -eq 1 ] || { bad "setup-fixture" "could not build the origin/work git fixture"; finish; }

SHA_VERIFIED="$( cd "$WORK" && G rev-parse HEAD )"
G clone -q "$ORIGIN" "$CLONE" 2>/dev/null || { bad "setup-clone" "clone failed"; finish; }
# A SECOND pre-move clone, reserved for the mutation row at the bottom. The first clone stops
# being stale the moment the real script re-fetches into it, and a mutation measured against a
# refreshed ref would silently stop discriminating.
CLONE_STALE="$TMP/clone-stale"
G clone -q "$ORIGIN" "$CLONE_STALE" 2>/dev/null || { bad "setup-clone-stale" "second clone failed"; finish; }

run_check() {   # run_check <cwd> <tag> <sha> -> rc
    ( cd "$1" && bash "$SCRIPT" "$2" "$3" origin >/dev/null 2>&1 )
}

# --- CONTROL: the matching case still publishes -------------------------------------------
if run_check "$CLONE" "$TAG" "$SHA_VERIFIED"; then
    ok "matching-tag-accepted [CONTROL] (tag target == verified SHA => rc 0, publication proceeds)"
else
    bad "matching-tag-accepted" "an unmoved tag pointing at the verified SHA was refused — this would block every legitimate release"
fi

# --- DISCRIMINATOR: the tag is force-moved AFTER verification -----------------------------
# The clone's LOCAL ref still says $SHA_VERIFIED, so a check that trusts the workspace ref
# (or matches by tag NAME, as `gh release create --verify-tag` does) reports success here.
# Only a remote re-resolve sees the move.
moved_ok=1
(
    cd "$WORK" || exit 1
    printf 'unverified\n' > file.txt
    G add file.txt && G commit -q -m "unverified commit" \
      && G push -q origin HEAD:refs/heads/main \
      && G tag -f "$TAG" >/dev/null 2>&1 \
      && G push -q --force origin "refs/tags/$TAG"
) || moved_ok=0
SHA_MOVED="$( cd "$WORK" && G rev-parse HEAD )"

if [ "$moved_ok" -ne 1 ] || [ "$SHA_MOVED" = "$SHA_VERIFIED" ]; then
    bad "moved-tag-refused" "could not force-move the tag on the fixture remote; the discriminator did not run (reported red, never as a pass)"
else
    local_ref="$( cd "$CLONE" && G rev-parse "refs/tags/$TAG^{commit}" 2>/dev/null )"
    if [ "$local_ref" != "$SHA_VERIFIED" ]; then
        bad "moved-tag-refused" "the clone's stale local tag ref was already $local_ref, so this row could not discriminate remote re-resolve from workspace trust"
    elif run_check "$CLONE" "$TAG" "$SHA_VERIFIED"; then
        bad "moved-tag-refused" "the tag now targets $SHA_MOVED but the check ACCEPTED it against verified $SHA_VERIFIED — a force-moved tag would publish unverified code"
    else
        ok "moved-tag-refused [DISCRIMINATOR] (tag force-moved to ${SHA_MOVED:0:12} after verification of ${SHA_VERIFIED:0:12}; stale local ref still said the verified SHA and the check still refused)"
    fi
fi

# --- CONTROL: the moved tag verifies against ITS OWN target -------------------------------
if run_check "$CLONE" "$TAG" "$SHA_MOVED"; then
    ok "moved-tag-accepted-for-its-own-sha [CONTROL] (the check binds tag->SHA, it does not blanket-refuse moved tags)"
else
    bad "moved-tag-accepted-for-its-own-sha" "the check refused a tag that DOES point at the SHA it was asked about — it is not comparing targets"
fi

# --- DISCRIMINATOR: an ANNOTATED tag must be peeled to its commit --------------------------
# An annotated tag's own object id is not a commit id. A check that compared the raw ref
# would refuse every annotated release (or, worse, be "fixed" by dropping the comparison).
ATAG="v0.0.0-tagbind-annotated"
anno_ok=1
(
    cd "$WORK" || exit 1
    G tag -a "$ATAG" -m "annotated" "$SHA_VERIFIED" >/dev/null 2>&1 \
      && G push -q origin "refs/tags/$ATAG"
) || anno_ok=0
if [ "$anno_ok" -ne 1 ]; then
    bad "annotated-tag-peeled" "could not create/push the annotated fixture tag; the row did not run"
else
    raw="$( cd "$WORK" && G rev-parse "refs/tags/$ATAG" 2>/dev/null )"
    if [ "$raw" = "$SHA_VERIFIED" ]; then
        bad "annotated-tag-peeled" "the fixture tag is not actually annotated (ref id == commit id), so peeling was not exercised"
    elif run_check "$CLONE" "$ATAG" "$SHA_VERIFIED"; then
        ok "annotated-tag-peeled [DISCRIMINATOR] (tag object ${raw:0:12} peels to commit ${SHA_VERIFIED:0:12} and is accepted)"
    else
        bad "annotated-tag-peeled" "an annotated tag whose commit IS the verified SHA was refused — the check compares the tag object, not the peeled commit"
    fi
fi

# --- DISCRIMINATORS: unusable input must refuse, never pass --------------------------------
# An empty or abbreviated expectation is how a "comparison" silently becomes a no-op.
if ( cd "$CLONE" && bash "$SCRIPT" "$TAG" "" origin >/dev/null 2>&1 ); then
    bad "empty-expected-sha-refused" "an EMPTY verified SHA was accepted — the comparison would match anything"
else
    ok "empty-expected-sha-refused [DISCRIMINATOR] (an empty expectation is refused, not treated as a match)"
fi
if ( cd "$CLONE" && bash "$SCRIPT" "$TAG" "${SHA_VERIFIED:0:12}" origin >/dev/null 2>&1 ); then
    bad "abbreviated-expected-sha-refused" "an ABBREVIATED verified SHA was accepted — a truncated compare is not a compare"
else
    ok "abbreviated-expected-sha-refused [DISCRIMINATOR] (a 12-char abbreviation is refused; only a full 40-hex id can bind)"
fi
if ( cd "$CLONE" && bash "$SCRIPT" "v0.0.0-does-not-exist" "$SHA_VERIFIED" origin >/dev/null 2>&1 ); then
    bad "unresolvable-tag-refused" "a tag that does not exist on the remote was accepted"
else
    ok "unresolvable-tag-refused [CONTROL] (an unresolvable tag refuses rather than falling through)"
fi

# --- RETAINED RED-BEFORE MUTATION: the remote re-resolve must be load-bearing --------------
# There is no pre-fix script to re-run (publication matched the tag by NAME only), so the
# claim "re-fetching is what catches a moved tag" is proved by excising the re-fetch from a
# COPY and showing the discriminator then goes the wrong way. If this mutation stops flipping
# the result, `refresh_tag_from_remote` has become decoration and the row above proves nothing.
MUT="$TMP/verify-tag-target.mutated.sh"
sed 's/^refresh_tag_from_remote$/: # MUTATED: trust the stale workspace ref/' "$SCRIPT" > "$MUT"
stale_ref="$( cd "$CLONE_STALE" && G rev-parse "refs/tags/$TAG^{commit}" 2>/dev/null )"
if ! grep -q "MUTATED: trust the stale workspace ref" "$MUT"; then
    bad "mutation-without-refetch-accepts-the-moved-tag" "the mutation anchor (a bare \`refresh_tag_from_remote\` call line) no longer exists — an unapplied mutation proves nothing"
elif [ "$stale_ref" != "$SHA_VERIFIED" ]; then
    bad "mutation-without-refetch-accepts-the-moved-tag" "the reserved pre-move clone is not stale (ref=$stale_ref); the mutation could not be measured"
elif ( cd "$CLONE_STALE" && bash "$MUT" "$TAG" "$SHA_VERIFIED" origin >/dev/null 2>&1 ); then
    ok "mutation-without-refetch-accepts-the-moved-tag [DISCRIMINATOR] (excising the remote re-resolve makes the force-moved tag pass — the fetch is what carries the claim)"
else
    bad "mutation-without-refetch-accepts-the-moved-tag" "the mutated script still refused; either the fixture's local ref is not stale or the refusal comes from somewhere other than the re-resolve, so 'moved-tag-refused' is not attributable to it"
fi

finish
