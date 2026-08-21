#!/usr/bin/env bash
# Fusebase Flow — recover a tree whose base was written by a run that could not classify it.
# Ticket N6 (half-apply-self-seals) · decision N6-D2 § Consequence (recovery scope).
#
# WHAT WENT WRONG, and why the ORDER below is the entire procedure:
#   A pre-N6 engine upgraded a tree that had no audit/managed-content-manifest.json. Paths it
#   could not classify were PRESERVED (K9 row 10), and then the run copied upstream's manifest
#   wholesale as the new base (K13b) and advanced VERSION. The base now claims upstream's
#   bytes are the consumer's history for files that were never refreshed, so the next run
#   reports them `consumer-only` — "YOU changed these" — and the one after that
#   `changed-by-both`, which ABORTS.
#
#   TRIPWIRE — the obvious repair is self-defeating: deleting the base and re-synthesising
#   keys off `v$(cat VERSION)` (synthesize-base.sh:57-75), and the bad run ALREADY advanced
#   VERSION (upgrade.sh:674-681). That reconstructs upstream's CURRENT tree as the
#   "historical" base and rebuilds the same poison. Restore the last truthful VERSION FIRST.
#   Do not reorder these steps, and do not offer a "just re-stamp" shortcut.
#
# WHAT THIS CAN AND CANNOT DO — N6-D2 is LOCKED on this point.
#   There is NO local signal that identifies the release a poisoned tree came from: a poisoned
#   tree and a healthy edited tree are byte-identical in every locally observable respect.
#   So this tool repairs ONLY trees that still carry external ground truth:
#     1. the last truthful version — VERSION.pre-upgrade-<TS>, or base_provenance.prior_version
#        (written by N6-D2 engines), or --prior-version given by a human who knows;
#     2. a source clone carrying the matching tag, so the base is a RECONSTRUCTION OF FACT
#        (the tag is byte-identical to what the consumer's last install wrote — K13a), never
#        an inference.
#   Without both it REFUSES and says so. It never guesses a baseline: a wrong baseline
#   misclassifies every path it disagrees with, which is the same damage applied deliberately.
#   Two distinct candidate versions is likewise a REFUSAL, not a coin flip — more than one run
#   may have been bad, and only the operator knows.
#
# READ-ONLY BY DEFAULT. --apply is the only mode that writes, and it backs up VERSION and the
# base to *.pre-recover-<TS> before touching either.

set -uo pipefail

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BASE_REL="audit/managed-content-manifest.json"
SOURCE_REPO=".fusebase-flow-source"
PRIOR=""
APPLY=0

usage() {
  cat >&2 <<'USAGE'
Usage: bash hooks/local/recover-missing-base.sh [--apply] [--prior-version <v>] [--repo <dir>]

  (default)              PREVIEW only — identifies the last truthful version and prints the
                         exact plan. Writes nothing.
  --apply                restore VERSION to the last truthful version, then rebuild the base
                         from that upstream tag. Backs up VERSION + base to *.pre-recover-<TS>.
  --prior-version <v>    name the last truthful version yourself (required when the tree
                         carries more than one candidate, or none).
  --repo <dir>           source clone carrying the tags (default: .fusebase-flow-source).

Exit: 0 recovered / previewed · 2 cannot recover (no ground truth) · 1 error.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --prior-version) PRIOR="${2:-}"; shift ;;
    --repo) SOURCE_REPO="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[recover] unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

say()  { echo "[recover] $*"; }
die2() { echo "[recover] $*" >&2; }

[ -f VERSION ] || { die2 "no VERSION at the repo root — run this from the consumer tree."; exit 1; }
CUR="$(tr -d '\n\r' < VERSION)"

MCM="hooks/local/lib/managed_content_manifest.py"
FFSB_LIB="hooks/local/lib/synthesize-base.sh"
ff_rec_py() { python3 -I -S "$@"; }   # isolated, never a bare python3: what this writes IS
                                      # the classifier's reference data (re-review B5).

# ---- Step 1: establish the LAST TRUTHFUL VERSION. Nothing is rebuilt before this. --------
CANDIDATES=""
if [ -z "$PRIOR" ] && [ -f "$BASE_REL" ] && command -v python3 >/dev/null 2>&1; then
  # N6-D2 engines record it in the base itself — the only zero-ambiguity source.
  PROV="$(ff_rec_py - "$BASE_REL" 2>/dev/null <<'PY'
import json, sys
try:
    p = json.load(open(sys.argv[1], encoding="utf-8")).get("base_provenance") or {}
except Exception:
    raise SystemExit
if p.get("prior_base") == "absent" and p.get("prior_version"):
    print(p["prior_version"])
PY
)"
  [ -n "$PROV" ] && { PRIOR="$PROV"; say "last truthful version from base_provenance: $PRIOR"; }
fi

if [ -z "$PRIOR" ]; then
  CANDIDATES="$(for f in VERSION.pre-upgrade-*; do [ -f "$f" ] && tr -d '\n\r' < "$f" && echo; done 2>/dev/null | sed '/^$/d' | sort -u)"
  COUNT="$(printf '%s' "$CANDIDATES" | grep -c . || true)"
  if [ "${COUNT:-0}" -eq 1 ]; then
    PRIOR="$CANDIDATES"
    say "last truthful version from VERSION.pre-upgrade-*: $PRIOR"
  elif [ "${COUNT:-0}" -gt 1 ]; then
    die2 "CANNOT RECOVER AUTOMATICALLY — this tree carries MORE THAN ONE candidate for the"
    die2 "last truthful version, so more than one upgrade may have run against a missing base:"
    for c in $CANDIDATES; do die2 "    $c"; done
    die2 "  Picking one would be a GUESS, and a wrong baseline misclassifies every path it"
    die2 "  disagrees with. Identify the release your tree actually descends from — match it"
    die2 "  by fingerprint in docs/release-fingerprints.md, never by eye — then re-run with:"
    die2 "    bash hooks/local/recover-missing-base.sh --prior-version <version> --apply"
    exit 2
  fi
fi

if [ -z "$PRIOR" ]; then
  die2 "CANNOT RECOVER AUTOMATICALLY — no ground truth for the last truthful version."
  die2 "  This tree has no VERSION.pre-upgrade-* backup and no base_provenance record, and"
  die2 "  NOTHING in a tree identifies the release it came from: a half-applied tree and a"
  die2 "  tree you edited yourself are byte-identical locally (decision N6-D2)."
  die2 "  Inventing a baseline here would misclassify every path it disagreed with, so this"
  die2 "  tool refuses. The manual route, which needs a human judgement this tool cannot make:"
  die2 "    1. docs/release-fingerprints.md lists every released tree's manifest fingerprint."
  die2 "       Match YOUR tree against it to find the release you descend from. By fingerprint,"
  die2 "       never by guess."
  die2 "    2. Re-run with that version named:"
  die2 "         bash hooks/local/recover-missing-base.sh --prior-version <version> --apply"
  die2 "  Until then change nothing: preserve *.pre-upgrade-*, VERSION backups, the source"
  die2 "  clone and your logs. See docs/ADVISORY-2026-08-20-missing-base-upgrade.md."
  exit 2
fi

# ---- Step 2: the reconstruction must come from a TAG, or not at all. --------------------
TAG="v$PRIOR"
if [ ! -d "$SOURCE_REPO/.git" ]; then
  die2 "CANNOT RECOVER AUTOMATICALLY — $SOURCE_REPO is not a git clone, so the $TAG tree"
  die2 "  cannot be recovered from it. The base must be a reconstruction of what upstream"
  die2 "  ACTUALLY shipped you, never an inference from your current tree (K13b)."
  die2 "  Provide a clone that carries the tags and re-run:"
  die2 "    git clone <fusebase-flow-url> $SOURCE_REPO"
  die2 "    bash hooks/local/recover-missing-base.sh --prior-version $PRIOR --apply"
  exit 2
fi
if ! git -C "$SOURCE_REPO" rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  git -C "$SOURCE_REPO" fetch --depth 1 origin "refs/tags/$TAG:refs/tags/$TAG" >/dev/null 2>&1 || true
fi
if ! git -C "$SOURCE_REPO" rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  die2 "CANNOT RECOVER AUTOMATICALLY — $SOURCE_REPO carries no tag $TAG."
  die2 "  Without that tag there is no record of what upstream shipped you at $PRIOR, and this"
  die2 "  tool will not synthesise one from your current tree — that is K13b's rejected move."
  die2 "  Fetch the tags and re-run:"
  die2 "    git -C $SOURCE_REPO fetch --tags"
  die2 "    bash hooks/local/recover-missing-base.sh --prior-version $PRIOR --apply"
  die2 "  If $TAG does not exist upstream, your VERSION was forked or unreleased: identify the"
  die2 "  release you descend from in docs/release-fingerprints.md and name it explicitly."
  exit 2
fi

# ---- Step 3: preview or apply -----------------------------------------------------------
say "current VERSION: $CUR   last truthful version: $PRIOR   reconstructing from: $TAG"
if [ "$APPLY" -ne 1 ]; then
  say "DRY-RUN — nothing written. A real run WOULD, in this order:"
  say "    1. back up VERSION and $BASE_REL to *.pre-recover-$TS"
  say "    2. restore VERSION to $PRIOR   <- FIRST: base synthesis keys off VERSION, so"
  say "                                      rebuilding while it reads $CUR recreates the poison"
  say "    3. rebuild $BASE_REL from upstream tag $TAG"
  say "    4. then: bash hooks/local/upgrade.sh   (the ordinary path works again)"
  say "  Re-run with --apply to perform it."
  exit 0
fi

cp VERSION "VERSION.pre-recover-$TS" 2>/dev/null || true
[ -f "$BASE_REL" ] && cp "$BASE_REL" "$BASE_REL.pre-recover-$TS" 2>/dev/null
printf '%s\n' "$PRIOR" > VERSION
say "VERSION restored to $PRIOR (backup: VERSION.pre-recover-$TS)"

# The base must be REPLACED, not merged: ffsb_synthesize_base treats an existing base as
# authoritative and returns early (synthesize-base.sh:46-49), which would hand the poisoned
# base straight back.
rm -f "$BASE_REL"
[ -f "$FFSB_LIB" ] || { die2 "missing $FFSB_LIB — cannot rebuild the base."; exit 1; }
# shellcheck source=lib/synthesize-base.sh
. "$FFSB_LIB"
if ! ffsb_synthesize_base "recover" "$BASE_REL" "$MCM" "$SOURCE_REPO" ff_rec_py; then
  die2 "base reconstruction FAILED (reason: ${FFSB_REASON:-unknown}). VERSION is $PRIOR and the"
  die2 "  poisoned base is preserved at $BASE_REL.pre-recover-$TS — restore it if you need the"
  die2 "  tree exactly as it was."
  exit 1
fi

if [ -f docs/release-fingerprints.md ] && grep -q "$TAG" docs/release-fingerprints.md 2>/dev/null; then
  say "docs/release-fingerprints.md carries a row for $TAG — cross-check the manifest"
  say "  fingerprint there against your rebuilt base if you want independent confirmation."
fi
say "RECOVERED. The base now records what upstream shipped you at $PRIOR, so the classifier"
say "  can tell your edits from upstream's again. Next: bash hooks/local/upgrade.sh"
say "  Paths you genuinely edited will now report 'consumer-only' truthfully, and anything"
say "  upstream also changed will report 'changed-by-both' for you to reconcile."
exit 0
