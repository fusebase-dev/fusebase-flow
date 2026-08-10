#!/usr/bin/env bash
# Fusebase Flow — publish-time tag -> verified-SHA binding (BLOCKER B2).
#
# WHY-home: docs/specs/backlog-triage-execution/final-architecture-review.md finding 2.
# `gh release create --verify-tag` matches on tag NAME only — it never compares the tag's
# TARGET with the commit CI actually verified, so a force-moved v* tag publishes a Release
# for code no `verify` job ever ran. This resolves the tag FROM THE REMOTE, peels it to a
# commit, and refuses unless it equals the verified SHA.
#
# TRIPWIRE — the fetch is not decoration. The workspace tag ref is whatever the checkout
# took at job start; the tag can have moved since. Re-fetching immediately before (and
# again after) publication shrinks the window to the fetch->create interval. It cannot
# CLOSE it: only a repo-side tag ruleset stops the tag moving at all. PUBLISHING.md
# § Publication paths names that as an operator action — do not let this script's presence
# be read as closure of the TOCTOU interval.
#
# TRIPWIRE — peel with ^{commit}. An ANNOTATED tag's own object id is NOT the commit id;
# comparing it to a commit SHA would refuse every annotated release.
#
# TRIPWIRE — there is deliberately NO env knob to skip the fetch or the comparison. A
# "compare the local ref instead" escape would be the whole defect back behind a flag, and
# CI is exactly where someone would set it. The re-fetch is mutation-tested instead:
# test-release-tag-binding.sh strips `refresh_tag_from_remote` from a COPY of this file and
# asserts the moved tag is then wrongly accepted, so the fetch cannot become decorative.
#
# Usage:  bash hooks/local/verify-tag-target.sh <tag> <verified-sha> [remote]
# Exit:   0 = tag target == verified SHA
#         1 = refuse (mismatch, unresolvable tag, unusable input, fetch failure)

set -uo pipefail

TAG="${1:-}"
WANT="${2:-}"
REMOTE="${3:-origin}"

die() {   # die <message>
    echo "::error::[verify-tag-target] $1" >&2
    echo "[verify-tag-target] REFUSING to publish: $1" >&2
    exit 1
}

[ -n "$TAG" ]  || die "no tag given (usage: verify-tag-target.sh <tag> <verified-sha> [remote])"
[ -n "$WANT" ] || die "no verified SHA given for tag '$TAG' — an empty expectation would match anything"

# A short/abbreviated/unset SHA must never be accepted: `[ "$a" = "$b" ]` on a truncated
# value silently compares two different things. Require a full 40-hex object id.
case "$WANT" in
    *[!0-9a-fA-F]* | "") die "verified SHA '$WANT' is not hexadecimal" ;;
esac
[ "${#WANT}" -eq 40 ] || die "verified SHA '$WANT' is not a full 40-character object id"

# --force: the tag may have MOVED, and a non-forced fetch of an existing ref is REJECTED by
# git, which would silently leave us comparing the stale workspace ref — the exact bypass
# this script exists to close. Kept as a one-line call so the mutation test can excise it.
refresh_tag_from_remote() {
    if ! git fetch --no-tags --force "$REMOTE" "refs/tags/$TAG:refs/tags/$TAG" >/dev/null 2>&1; then
        die "could not fetch refs/tags/$TAG from '$REMOTE' — cannot prove what the tag points at"
    fi
}
refresh_tag_from_remote

TARGET="$(git rev-parse --verify --quiet "refs/tags/$TAG^{commit}" 2>/dev/null)"
[ -n "$TARGET" ] || die "tag '$TAG' does not resolve to a commit (missing tag, or a tag object that peels to a non-commit)"

if [ "$TARGET" != "$WANT" ]; then
    die "tag '$TAG' now points at $TARGET but the verified commit is $WANT — the tag was moved after verification. No Release is created."
fi

echo "[verify-tag-target] tag '$TAG' -> $TARGET == verified SHA. Binding holds."
exit 0
