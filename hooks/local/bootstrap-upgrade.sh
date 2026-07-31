#!/usr/bin/env bash
# Fusebase Flow — bootstrap-upgrade.sh  (U5: first-hop upgrade for pre-3.6.0 installs)
#
# PROVENANCE:
#   Shipped Fusebase Flow v3.8.0+. Lives at hooks/local/ — outside the FuseBase CLI
#   refresh manifest.
#
# PURPOSE:
#   The blessed in-place upgrade path is `upgrade.sh`, but it ships *inside* the
#   version you're trying to reach. A pre-3.6.0 "append-only overlay" install has
#   no upgrade.sh / sync-version-strings.sh / .fusebase-flow-source/. This script
#   is the one-shot first hop: it stages an upstream copy and EXECUTES the engine
#   FROM THAT SOURCE TREE, so classification decides every consumer write.
#
#   For an install that ALSO lacks this bootstrap script (truly old), copy-paste
#   the equivalent one-liner from the README "Upgrading an installed overlay"
#   section — it does the same clone + run.
#
# What it does:
#   1. Ensure .fusebase-flow-source/ exists — clone upstream if absent (or reuse a
#      plain dir you already staged).
#   2. Synthesize the classifier's base manifest from the upstream tag equal to the
#      consumer's installed VERSION (K13a) — the ONE pre-classification write, and it
#      is the classifier's own input, not consumer content.
#   3. `exec` the SOURCE clone's hooks/local/upgrade.sh (passing through any flags,
#      e.g. --dry-run / --auto-yes). Managed consumer paths — engine scripts and
#      hooks/local/lib/ included — are written only by that engine's classified
#      per-file apply loop.
#
# What it does NOT do (AC25 / K10 / K20):
#   - Copy the engine, lib, or any other managed path into the consumer tree before
#     classification authorizes it; an aborted hop leaves the tree byte-identical
#     except the base manifest above and logs.
#   - Touch application code, .claude/settings.json, or CLI-owned assets.
#   - Delete anything. It writes no backup of its own either (there is nothing to back
#     up before handoff); the engine's .pre-upgrade-<ts> snapshot is the backup. The
#     *.pre-bootstrap-<ts> git-exclude below is retained for trees that still carry
#     snapshots from the older copy-then-handoff hop.
#
# Usage:
#   bash hooks/local/bootstrap-upgrade.sh [--source <dir>] [--repo <url>] [--ref <branch>] [-- <upgrade.sh flags>]
#   bash hooks/local/bootstrap-upgrade.sh --repair-managed <repo-relative-path> [--repair-managed <path> ...]
# Examples:
#   bash hooks/local/bootstrap-upgrade.sh --dry-run
#   bash hooks/local/bootstrap-upgrade.sh -- --auto-yes
#   bash hooks/local/bootstrap-upgrade.sh --source ../fusebase-flow
#   bash hooks/local/bootstrap-upgrade.sh --repair-managed hooks/handlers/stop.py
#
# --repair-managed (AC3): repeatable, deliberate byte repair for a managed path a manifest
# verifier reported as drifted. It materializes + verifies the source, then replaces ONLY the
# named paths from those verified bytes and re-runs both verifiers. Naming each path IS the
# authorization: --auto-yes never repairs, and an unreported/unmanaged path is refused.
#
# Exit: 0 success; 1 error; 2 bad arg.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

SOURCE_CLONE=".fusebase-flow-source"
FF_MCM_REL="audit/managed-content-manifest.json"
REPO_URL="https://github.com/fusebase-dev/fusebase-flow.git"
REF="main"
SRC_OVERRIDE=""
PASSTHROUGH=()
REPAIR_PATHS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) SRC_OVERRIDE="${2:-}"; shift 2 ;;
    --repo)   REPO_URL="${2:-}"; shift 2 ;;
    --ref)    REF="${2:-}"; shift 2 ;;
    --repair-managed)   REPAIR_PATHS+=("${2:-}"); shift 2 ;;
    --repair-managed=*) REPAIR_PATHS+=("${1#*=}"); shift ;;
    --help|-h) sed -n '2,46p' "$0"; exit 0 ;;
    --) shift; PASSTHROUGH=("$@"); break ;;
    *) echo "[bootstrap-upgrade] Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

TS=$(date -u +%Y%m%dT%H%M%SZ)

# ---- Step 1: ensure a source copy ----
if [ -n "$SRC_OVERRIDE" ]; then
  if [ ! -d "$SRC_OVERRIDE" ]; then
    echo "[bootstrap-upgrade] FATAL: --source '$SRC_OVERRIDE' is not a directory." >&2
    exit 1
  fi
  SOURCE_CLONE="$SRC_OVERRIDE"
  echo "[bootstrap-upgrade] Using source: $SOURCE_CLONE"
elif [ -d "$SOURCE_CLONE" ]; then
  echo "[bootstrap-upgrade] Reusing existing $SOURCE_CLONE/"
else
  if ! command -v git >/dev/null 2>&1; then
    echo "[bootstrap-upgrade] FATAL: git not found and no $SOURCE_CLONE/ present." >&2
    echo "                    Stage an upstream copy at $SOURCE_CLONE/ manually, then re-run." >&2
    exit 1
  fi
  echo "[bootstrap-upgrade] Cloning $REPO_URL ($REF) -> $SOURCE_CLONE/ ..."
  # TRIPWIRE (line endings): the staging clone MUST check out with the consumer's own
  # core.autocrlf. If it inherits a different global value, every managed file differs by
  # EOL alone — the classifier then reads the whole tree as upstream-changed (or
  # consumer-changed) and either overwrites or preserves everything for the wrong reason.
  FF_EOL="$(git config --get core.autocrlf 2>/dev/null || true)"
  [ -n "$FF_EOL" ] || FF_EOL="false"
  git -c core.autocrlf="$FF_EOL" clone --depth 1 --branch "$REF" "$REPO_URL" "$SOURCE_CLONE"
fi

# ---- Step 1b: canonical source boundary BEFORE any source-derived read (decision M1 / AC2) ----
# TRIPWIRE (source trust): the VERDICT is always reached by TRUSTED CODE — the installed lib, or,
# when this install predates it, the minimal embedded materialize+verify pair below. NEVER by
# shell sourced out of the source: neither $SOURCE_CLONE's mutable worktree nor the snapshot taken
# from it. A source-supplied materialize-managed-source.sh can redefine ff_source_verify_tree and
# approve itself, so "source it, then verify with it" proves nothing. Source-derived shell may
# enter this process only AFTER trusted code has proven the tree, and only for the repair API.
FF_MMS_LIB="$ROOT/hooks/local/lib/materialize-managed-source.sh"
SOURCE_TREE="$SOURCE_CLONE"
SOURCE_TREE_FLAGS=()
FF_BOOT_TREE=""
FF_BOOT_TREE_OWNED=0
BOOT_COMMIT=""
FF_SOURCE_REPO=""; FF_SOURCE_COMMIT=""; FF_SOURCE_KIND=""
FF_SOURCE_STATE=""; FF_SOURCE_REASON=""; FF_SOURCE_DRIFT=""

ff_boot_cleanup() {
  [ "${FF_BOOT_TREE_OWNED:-0}" = "1" ] || return 0
  local t="$FF_BOOT_TREE"
  FF_BOOT_TREE_OWNED=0
  # TRIPWIRE (destructive): only a directory WE created from the ff-source- template.
  case "${t##*/}" in
    ff-source-*) [ -d "$t" ] && rm -rf -- "$t" ;;
  esac
  return 0
}

# The M10/M11 verdict, embedded. Mirrors _ff_mms_verify in the shared lib on purpose: this is the
# one piece of the boundary that cannot be borrowed from the tree it judges (R3 / re-review B1).
# What it drives IS the source's own managed_content_manifest.py — the same trust model the
# installed lib uses: a manifest-bearing tree is proven by its shipped verifier or it aborts, and
# a manifest+verifier source needs no materialize-managed-source.sh to be provable (M11).
# TRIPWIRE (re-review B4): $2 exists so a caller can supply a verifier it ALREADY PROVED. A tree
# whose own verifier is part of what is in question — the mutable worktree at Step 2c — must be
# judged with that argument, never with the default below.
ff_boot_verify() {   # <tree> [<trusted verifier>]; sets FF_SOURCE_STATE/_REASON/_DRIFT. rc 1 => abort
  local tree="$1" mcm="${2:-}" mrel="$FF_MCM_REL" out rc
  [ -n "$mcm" ] || mcm="$tree/hooks/local/lib/managed_content_manifest.py"
  FF_SOURCE_STATE=""; FF_SOURCE_REASON=""; FF_SOURCE_DRIFT=""
  if [ ! -f "$tree/$mrel" ]; then
    FF_SOURCE_STATE="UNVERIFIED_LEGACY_SOURCE"
    FF_SOURCE_REASON="source ships no $mrel (pre-4.7.0 source)"
    return 0
  fi
  if [ ! -f "$mcm" ]; then
    FF_SOURCE_REASON="source ships $mrel but no hooks/local/lib/managed_content_manifest.py to check it against — these bytes cannot be proven to be what upstream shipped"
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    FF_SOURCE_REASON="source ships $mrel but python3 is unavailable to verify it — these bytes cannot be proven to be what upstream shipped"
    return 1
  fi
  out="$(python3 "$mcm" verify --root "$tree" --json 2>/dev/null)"; rc=$?
  FF_SOURCE_DRIFT="$(printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
fs = [f.get("path", "?") for f in d.get("files", []) or []]
s = ", ".join(fs[:8])
if len(fs) > 8:
    s += " (+%d more)" % (len(fs) - 8)
print(s)
' 2>/dev/null)"
  # TRIPWIRE (decision M10): UNVERIFIED_LEGACY_SOURCE is reachable ONLY from the manifest-ABSENT
  # branch above. Never widen the rc-0 success case beyond a literal MATCH verdict either.
  case "$rc" in
    0)
      case "$out" in
        *'"verdict": "MATCH"'*|*'"verdict":"MATCH"'*)
          FF_SOURCE_STATE="VERIFIED"; FF_SOURCE_DRIFT=""; return 0 ;;
        *) FF_SOURCE_REASON="the source verifier exited 0 without a MATCH verdict for $mrel (truncated or replaced managed_content_manifest.py?)"
           return 1 ;;
      esac ;;
    1) FF_SOURCE_REASON="the source tree does not match its own shipped $mrel (DRIFT)"; return 1 ;;
    2) FF_SOURCE_REASON="the source tree's $mrel is corrupt or self-hash mismatched (BROKEN)"; return 1 ;;
    *) FF_SOURCE_REASON="the source verifier could not check $mrel (exited rc=$rc)"; return 1 ;;
  esac
}

# Minimal embedded materialization for an install that predates hooks/local/lib/
# materialize-managed-source.sh. Deliberately duplicates only the primitives that cannot be
# borrowed from the source without trusting it first: the two materializations and the verdict.
ff_boot_materialize() {
  local dest cand oid lib repo kind
  dest="$(mktemp -d "${TMPDIR:-/tmp}/ff-source-XXXXXX" 2>/dev/null || true)"
  if [ -z "$dest" ] || [ ! -d "$dest" ]; then
    echo "[bootstrap-upgrade] FATAL: could not create a temporary source tree." >&2
    return 1
  fi
  FF_BOOT_TREE="$dest"; FF_BOOT_TREE_OWNED=1
  trap 'ff_boot_cleanup' EXIT
  trap 'rc=$?; ff_boot_cleanup; exit $rc' INT TERM
  if [ -e "$SOURCE_CLONE/.git" ] && command -v git >/dev/null 2>&1; then
    for cand in "$REF" "origin/$REF" "HEAD"; do
      [ -n "$cand" ] || continue
      oid="$(git -C "$SOURCE_CLONE" rev-parse --verify -q "${cand}^{commit}" 2>/dev/null || true)"
      [ -n "$oid" ] && break
    done
    if [ -z "${oid:-}" ]; then
      echo "[bootstrap-upgrade] FATAL: cannot resolve '$REF', 'origin/$REF' or HEAD to a commit in $SOURCE_CLONE." >&2
      return 1
    fi
    # TRIPWIRE (decision M1): incoming U is forced core.autocrlf=false + core.eol=lf on EVERY OS,
    # exactly as materialize-managed-source.sh does. The consumer's EOL belongs to the K13
    # historical base B below — never to incoming content.
    if ! git -C "$SOURCE_CLONE" -c core.autocrlf=false -c core.eol=lf archive "$oid" | tar -x -C "$dest"; then
      echo "[bootstrap-upgrade] FATAL: git archive of $oid failed." >&2
      return 1
    fi
    BOOT_COMMIT="$oid"
    echo "[bootstrap-upgrade] materialized git source @ $oid from objects (embedded boundary)."
  else
    if ! cp -R "$SOURCE_CLONE/." "$dest/" 2>/dev/null; then
      echo "[bootstrap-upgrade] FATAL: could not snapshot the plain source directory." >&2
      return 1
    fi
    rm -rf "$dest/.git" 2>/dev/null || true
    echo "[bootstrap-upgrade] materialized plain source -> immutable snapshot (embedded boundary)."
  fi
  SOURCE_TREE="$dest"
  repo="$(cd "$SOURCE_CLONE" && pwd)"
  kind="$([ -n "$BOOT_COMMIT" ] && echo git || echo plain)"
  # The verdict runs on THIS script's code, before any shell comes out of $dest.
  if ! ff_boot_verify "$dest"; then
    echo "[bootstrap-upgrade] ABORT: $FF_SOURCE_REASON" >&2
    [ -n "$FF_SOURCE_DRIFT" ] && echo "[bootstrap-upgrade]        offending path(s): $FF_SOURCE_DRIFT" >&2
    echo "[bootstrap-upgrade] NOTHING was written. Re-stage a clean source tree and retry." >&2
    return 1
  fi
  echo "[bootstrap-upgrade] embedded-boundary verdict on the materialized tree: state=$FF_SOURCE_STATE"
  [ "$FF_SOURCE_STATE" = "UNVERIFIED_LEGACY_SOURCE" ] \
    && echo "[bootstrap-upgrade] UNVERIFIED_LEGACY_SOURCE: $FF_SOURCE_REASON — proceeding for pre-manifest source compatibility (decision M10)."
  # Only a PROVEN tree may contribute shell to this process, and only for the shared repair API
  # (--repair-managed). Sourcing the lib resets the FF_SOURCE_* contract, so re-assert it after.
  lib="$dest/hooks/local/lib/materialize-managed-source.sh"
  if [ "$FF_SOURCE_STATE" = "VERIFIED" ] && [ -f "$lib" ]; then
    # shellcheck source=/dev/null
    . "$lib"
    ff_source_adopt "$dest" 0        # ownership stays with ff_boot_cleanup — one owner only
    FF_SOURCE_STATE="VERIFIED"; FF_SOURCE_REASON=""; FF_SOURCE_DRIFT=""
  fi
  FF_SOURCE_REPO="$repo"; FF_SOURCE_COMMIT="$BOOT_COMMIT"; FF_SOURCE_KIND="$kind"
  return 0
}

if [ -f "$FF_MMS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$FF_MMS_LIB"
  trap 'ff_source_cleanup' EXIT
  trap 'rc=$?; ff_source_cleanup; exit $rc' INT TERM
  ff_source_open "$SOURCE_CLONE" "" 0 "$REF" || exit 1
  SOURCE_TREE="$FF_SOURCE_TREE"
else
  ff_boot_materialize || exit 1
fi

if [ ! -f "$SOURCE_TREE/VERSION" ]; then
  echo "[bootstrap-upgrade] FATAL: $SOURCE_CLONE/VERSION missing — not a Fusebase Flow source tree." >&2
  exit 1
fi
echo "[bootstrap-upgrade] Source VERSION: $(tr -d '\n\r' < "$SOURCE_TREE/VERSION")"

# Git-exclude the *.pre-*-<ts> backup snapshots so a downstream `git add -A` (notably
# FuseBase CLI's `fusebase update` checkpoint) never stages them — the rule and its rationale
# live in the shared lib, which upgrade.sh uses too (no second copy to drift).
# The target-version copy wins, but only out of a tree the boundary PROVED — an unverified
# legacy source contributes no shell to this process (same rule as the materializer above).
FF_BH_LIB="$ROOT/hooks/local/lib/backup-hygiene.sh"
[ "$FF_SOURCE_STATE" = "VERIFIED" ] && [ -f "$SOURCE_TREE/hooks/local/lib/backup-hygiene.sh" ] \
  && FF_BH_LIB="$SOURCE_TREE/hooks/local/lib/backup-hygiene.sh"
# shellcheck source=/dev/null
[ -f "$FF_BH_LIB" ] && . "$FF_BH_LIB"
if command -v ff_git_exclude_backups >/dev/null 2>&1; then
  ff_git_exclude_backups || echo "[bootstrap-upgrade] WARN: could not update .git/info/exclude — backups may be stageable by a later 'git add -A' (delete or unstage before committing)." >&2
fi

# ---- --repair-managed (AC3): deliberate exact-path byte repair, then re-verify ----
if [ "${#REPAIR_PATHS[@]}" -gt 0 ]; then
  if ! command -v ff_repair_managed >/dev/null 2>&1; then
    echo "[bootstrap-upgrade] FATAL: --repair-managed needs hooks/local/lib/materialize-managed-source.sh" >&2
    echo "                    from a 4.7.0+ source tree; none was found." >&2
    exit 1
  fi
  if [ "$FF_SOURCE_STATE" != "VERIFIED" ]; then
    echo "[bootstrap-upgrade] FATAL: repair requires a VERIFIED source; state is $FF_SOURCE_STATE" >&2
    echo "                    ($FF_SOURCE_REASON). Repairing from unverified bytes would install" >&2
    echo "                    content nobody can prove upstream shipped." >&2
    exit 1
  fi
  ff_repair_managed "$ROOT" "$SOURCE_TREE" "$TS" "${REPAIR_PATHS[@]}" || exit 1
  echo "[bootstrap-upgrade] re-verifying both manifests after repair…"
  REPAIR_RC=0
  for v in verify-hook-manifest.sh verify-managed-content-manifest.sh; do
    [ -f "hooks/local/$v" ] || continue
    bash "hooks/local/$v" || REPAIR_RC=$?
  done
  exit "$REPAIR_RC"
fi

# ---- Step 2: NOTHING is written here (decision K10/K20) ----
#
# TRIPWIRE: this step used to copy the fetched engine scripts and the WHOLE
# hooks/local/lib/ into the consumer tree BEFORE any classification ran, then exec the
# installed copy. A later `changed-by-both` abort therefore could not truthfully say
# "nothing was written", and a consumer's engine/lib customizations were already gone.
# The engine now runs FROM THE SOURCE CLONE; every managed consumer path — including the
# engine scripts and hooks/local/lib/ — is written only by upgrade.sh's classified
# per-file apply loop, which already treats them as managed content.
#
# The ONE pre-classification write that remains is Step 2b's audit/managed-content-
# manifest.json: it is the classifier's own INPUT, not consumer content, and without it
# the classifier cannot distinguish the consumer's edits from upstream's at all.
ENGINE_SRC="$SOURCE_TREE/hooks/local/upgrade.sh"
if [ ! -f "$ENGINE_SRC" ]; then
  echo "[bootstrap-upgrade] FATAL: $ENGINE_SRC missing — not a usable source tree." >&2
  exit 1
fi

# ---- Step 2c: the tree we PROVED must be the tree the engine CONSUMES ----------------------
# TRIPWIRE (verified-tree/consumed-tree split): a PRE-boundary engine cannot receive
# --source-tree, so Step 3 below runs it from $SOURCE_CLONE — the MUTABLE WORKTREE — and it
# reads `.fusebase-flow-source` BY NAME. For a git source the canonical tree comes from COMMITTED
# OBJECTS, so a clean commit with a tampered worktree would verify MATCH and then install the
# tampered bytes: VERIFIED about bytes nobody installs (same fail-open class as F2 / M11).
# Keeping the canonical tree alive does NOT fix it — the engine would still read the worktree by
# name. So on this route the verdict is re-reached on $SOURCE_CLONE itself, and it is reached with
# TRUSTED CODE ONLY (re-review B4): the verifier out of the canonical tree THIS RUN ALREADY PROVED,
# plus this script's own embedded logic — NEVER the worktree's own managed_content_manifest.py,
# which is part of what is in question (a tamper that rewrites it too can print MATCH for itself:
# B1 in Python instead of shell). No trusted verifier available => abort; never "ask it about
# itself". The two manifests must also be BYTE-IDENTICAL, or a re-stamped worktree would be
# self-consistent and prove nothing — matching manifests on both trees is what makes the engine we
# grepped in the canonical tree the engine we execute from the worktree.
#
# ACCEPTED LIMITATION (TOCTOU, local threat model): $SOURCE_CLONE stays mutable between this
# verdict and the engine's reads, and Step 2b's tag fetch widens that window. Verifying AFTER
# Step 2b would trade a truthful "NOTHING was written" abort for a shorter window; closing it
# entirely means replacing the operator's staging area. A local process that can race this can
# already edit this script. See docs/release-notes/v4.7.0.md § Known limitation (pre-boundary route).
LEGACY_ENGINE=0
if ! grep -q -- '--source-tree)' "$ENGINE_SRC" 2>/dev/null; then
  LEGACY_ENGINE=1
  BOOT_PROVEN_STATE="$FF_SOURCE_STATE"
  BOOT_TRUSTED_MCM=""
  [ "$BOOT_PROVEN_STATE" = "VERIFIED" ] \
    && [ -f "$SOURCE_TREE/hooks/local/lib/managed_content_manifest.py" ] \
    && BOOT_TRUSTED_MCM="$SOURCE_TREE/hooks/local/lib/managed_content_manifest.py"
  if [ -f "$SOURCE_CLONE/$FF_MCM_REL" ] && [ -z "$BOOT_TRUSTED_MCM" ]; then
    echo "[bootstrap-upgrade] ABORT: $SOURCE_CLONE ships $FF_MCM_REL — the tree this pre-boundary" >&2
    echo "                    engine actually reads — but the canonical tree this run proved" >&2
    echo "                    (state=$BOOT_PROVEN_STATE) supplies no verifier this script can trust," >&2
    echo "                    and the worktree's own copy cannot answer a question about itself." >&2
    echo "[bootstrap-upgrade] NOTHING was written: no managed path was touched and the engine never ran." >&2
    exit 1
  fi
  if ! ff_boot_verify "$SOURCE_CLONE" "$BOOT_TRUSTED_MCM"; then
    echo "[bootstrap-upgrade] ABORT: the source engine predates the canonical-tree handoff, so it reads" >&2
    echo "                    $SOURCE_CLONE directly — and $FF_SOURCE_REASON" >&2
    [ -n "$FF_SOURCE_DRIFT" ] && echo "[bootstrap-upgrade]        offending path(s): $FF_SOURCE_DRIFT" >&2
    echo "[bootstrap-upgrade] NOTHING was written: no managed path was touched and the engine never ran." >&2
    exit 1
  fi
  if [ "$BOOT_PROVEN_STATE" = "VERIFIED" ] && [ "$FF_SOURCE_STATE" != "VERIFIED" ]; then
    echo "[bootstrap-upgrade] ABORT: the canonical tree proved VERIFIED, but $SOURCE_CLONE — the tree this" >&2
    echo "                    pre-boundary engine actually reads — ships no $FF_MCM_REL, so those" >&2
    echo "                    bytes cannot be proven to be what upstream shipped (M10/M11: the legacy" >&2
    echo "                    fallback is for a source that has no manifest anywhere, not for one" >&2
    echo "                    whose worktree hides it)." >&2
    echo "[bootstrap-upgrade] NOTHING was written: no managed path was touched and the engine never ran." >&2
    exit 1
  fi
  if [ -n "$BOOT_TRUSTED_MCM" ] && ! cmp -s "$SOURCE_TREE/$FF_MCM_REL" "$SOURCE_CLONE/$FF_MCM_REL"; then
    echo "[bootstrap-upgrade] ABORT: $SOURCE_CLONE ships a DIFFERENT $FF_MCM_REL than the canonical" >&2
    echo "                    tree this run proved. A worktree re-stamped against its own bytes is" >&2
    echo "                    self-consistent and proves nothing about what upstream shipped." >&2
    echo "[bootstrap-upgrade] NOTHING was written: no managed path was touched and the engine never ran." >&2
    exit 1
  fi
  if [ -n "$BOOT_TRUSTED_MCM" ]; then
    echo "[bootstrap-upgrade] re-verified the tree the pre-boundary engine consumes ($SOURCE_CLONE) with the proven canonical verifier: state=$FF_SOURCE_STATE"
  else
    echo "[bootstrap-upgrade] re-verified the tree the pre-boundary engine consumes ($SOURCE_CLONE): state=$FF_SOURCE_STATE"
  fi
fi

# ---- Step 2b: SYNTHESIZE the classifier's base for a consumer arriving without one ----
#
# WHY THIS IS LOAD-BEARING (decision K13a): a consumer on <= 4.6.1 has no
# audit/managed-content-manifest.json. Without a base, EVERY managed path classifies
# `unknown-base`, K9 preserves all of them, and the upgrade reports success while
# installing NOTHING. The classifier release could not deliver its own content.
#
# The fix is not a guess: the upstream tag equal to the consumer's installed VERSION is
# BYTE-IDENTICAL to what their last install/upgrade wrote. Stamping a base from that tag
# is a reconstruction of a fact, not an inference. Only when the tag cannot be resolved
# (a forked or unreleased VERSION) does the tree fall through to `unknown-base` — which is
# preserve + report, never abort (K9 row 10).
BASE_REL="$FF_MCM_REL"
MCM_SRC="$SOURCE_TREE/hooks/local/lib/managed_content_manifest.py"

ff_synthesize_base() {
  local ver tag tmp rc
  if [ -f "$BASE_REL" ]; then
    echo "[bootstrap-upgrade] base manifest already present ($BASE_REL) — no synthesis needed."
    return 0
  fi
  if [ ! -f "$MCM_SRC" ] || ! command -v python3 >/dev/null 2>&1; then
    echo "[bootstrap-upgrade] NOTE: the source tree has no managed-content module (pre-4.7.0)" >&2
    echo "                    or python3 is unavailable — no base can be synthesized." >&2
    return 1
  fi
  [ -f VERSION ] || { echo "[bootstrap-upgrade] NOTE: no local VERSION — cannot pick a base tag." >&2; return 1; }
  ver="$(tr -d '\n\r' < VERSION)"
  tag="v$ver"
  if [ ! -d "$SOURCE_CLONE/.git" ]; then
    echo "[bootstrap-upgrade] NOTE: $SOURCE_CLONE is a plain directory (no .git), so the" >&2
    echo "                    $tag tree cannot be recovered — skipping base synthesis." >&2
    return 1
  fi
  # A --depth 1 --branch <ref> clone carries no tags; fetch just the one we need.
  if ! git -C "$SOURCE_CLONE" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    git -C "$SOURCE_CLONE" fetch --depth 1 origin "refs/tags/$tag:refs/tags/$tag" >/dev/null 2>&1 || true
  fi
  if ! git -C "$SOURCE_CLONE" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    echo "[bootstrap-upgrade] NOTE: upstream tag $tag could not be resolved (forked or"
    echo "                    unreleased VERSION). Proceeding with NO base: every managed"
    echo "                    path will classify 'unknown-base', which PRESERVES it and"
    echo "                    reports it — nothing is overwritten, but little is refreshed."
    return 1
  fi
  tmp="$(mktemp -d)"
  # TRIPWIRE (line endings, decision M1) — VERIFIED, do not "simplify" this away, and do NOT
  # make it match the incoming-U call in materialize-managed-source.sh. This is the historical
  # base B: it models what the consumer's own git WROTE at $tag, so it must keep the
  # CONSUMER's EOL convention. `git archive` DOES apply core.autocrlf to files without an eol
  # attribute (measured: true emits CRLF, false/input emit LF), so without this flag the base
  # hashes differ from the consumer's working tree for EVERY managed path — all of them
  # classify changed-by-both and the upgrade aborts having delivered nothing. Forcing LF here
  # is the OPPOSITE error: it makes every untouched CRLF consumer file look locally edited.
  # (A 2026-07-28 review claimed archive ignores autocrlf; removing the flag reproduced the
  # whole-tree misclassification above, so the claim is false on this platform.)
  local eol
  eol="$(git config --get core.autocrlf 2>/dev/null || true)"
  [ -n "$eol" ] || eol="false"
  if ! git -C "$SOURCE_CLONE" -c core.autocrlf="$eol" archive "$tag" | tar -x -C "$tmp" 2>/dev/null; then
    echo "[bootstrap-upgrade] WARN: could not extract $tag — skipping base synthesis." >&2
    rm -rf "$tmp"; return 1
  fi
  python3 "$MCM_SRC" stamp --root "$tmp" >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] || [ ! -f "$tmp/$BASE_REL" ]; then
    echo "[bootstrap-upgrade] WARN: base stamp from $tag failed (rc $rc) — skipping." >&2
    rm -rf "$tmp"; return 1
  fi
  mkdir -p "$(dirname "$BASE_REL")"
  cp "$tmp/$BASE_REL" "$BASE_REL"
  rm -rf "$tmp"
  echo "[bootstrap-upgrade] synthesized the classifier base from upstream tag $tag -> $BASE_REL"
  echo "                    (this is what upstream shipped you at $ver, so the upgrade can now"
  echo "                     tell YOUR edits from upstream's.)"
  return 0
}
ff_synthesize_base || true

# ---- Step 3: hand off to the SOURCE engine (never the installed one) ----
# The boundary crosses here as ABSOLUTE internal flags (decision M1 / AC2). We `exec`, so this
# process is replaced and its EXIT trap never runs: ownership of the temp tree transfers to the
# engine via --source-tree-owned, which arms the identical cleanup on its own side. Only pass
# the flags when the source engine understands them (an older --source tree would exit 2 —
# Step 2c decided that, and re-proved the consumed tree for the legacy branch below).
if [ "$LEGACY_ENGINE" = "0" ]; then
  SOURCE_TREE_FLAGS=(--source-tree "$SOURCE_TREE" --source-repo "${FF_SOURCE_REPO:-$SOURCE_CLONE}")
  if [ "${FF_SOURCE_TREE_TEMP:-0}" = "1" ] || [ "${FF_BOOT_TREE_OWNED:-0}" = "1" ]; then
    SOURCE_TREE_FLAGS+=(--source-tree-owned)
  fi
  [ -n "${FF_SOURCE_COMMIT:-}" ] && SOURCE_TREE_FLAGS+=(--source-commit "$FF_SOURCE_COMMIT")
  # handed over; no trap of ours may delete the tree the engine now owns
  FF_SOURCE_TREE_TEMP=0; FF_BOOT_TREE_OWNED=0
else
  # TRIPWIRE (M10 legacy route): a PRE-boundary engine can neither receive nor clean up the
  # canonical tree, and it reads $SOURCE_CLONE itself — so the tree is released HERE and the
  # engine runs from $SOURCE_CLONE. NEVER `exec` a path inside the tree this branch just
  # deleted: that is what stopped a genuine pre-4.7.0 source (M10's named
  # UNVERIFIED_LEGACY_SOURCE route) from upgrading at all — bash exits 127 on a vanished engine.
  # What makes releasing it safe is Step 2c: $SOURCE_CLONE, the tree this engine reads, carries
  # the verdict below on its OWN bytes. Never reach this branch without that re-verification.
  ENGINE_SRC="$SOURCE_CLONE/hooks/local/upgrade.sh"
  if [ ! -f "$ENGINE_SRC" ]; then
    echo "[bootstrap-upgrade] FATAL: the source engine predates the canonical-tree handoff and" >&2
    echo "                    $ENGINE_SRC is missing — nothing to hand off to." >&2
    exit 1
  fi
  echo "[bootstrap-upgrade] NOTE: the source engine predates the canonical-tree handoff; it reads"
  echo "                    $SOURCE_CLONE itself, so the canonical tree is released here and the"
  echo "                    engine runs from $SOURCE_CLONE (source state: ${FF_SOURCE_STATE:-unknown})."
  command -v ff_source_cleanup >/dev/null 2>&1 && ff_source_cleanup
  ff_boot_cleanup
fi
echo "[bootstrap-upgrade] Handing off to $ENGINE_SRC ${PASSTHROUGH[*]:-}"
echo ""
exec bash "$ENGINE_SRC" ${SOURCE_TREE_FLAGS[@]+"${SOURCE_TREE_FLAGS[@]}"} ${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}
