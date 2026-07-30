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
# TRIPWIRE (source trust): the boundary implementation comes from TRUSTED LOCAL CODE — the
# installed copy — or, when this install predates it, from the tree the minimal embedded
# materialization below produced out of git OBJECTS. NEVER from $SOURCE_CLONE's mutable
# WORKTREE: that copy could redefine materialization and verification before any canonical tree
# exists, i.e. the code deciding whether the source is canonical would itself be unverified.
FF_MMS_LIB="$ROOT/hooks/local/lib/materialize-managed-source.sh"
SOURCE_TREE="$SOURCE_CLONE"
SOURCE_TREE_FLAGS=()
FF_BOOT_TREE=""
FF_BOOT_TREE_OWNED=0
BOOT_COMMIT=""

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

# Minimal embedded materialization for an install that predates hooks/local/lib/
# materialize-managed-source.sh. Deliberately duplicates only the two primitives that cannot be
# borrowed from the source without trusting it first; the VERDICT still comes from the shared lib,
# sourced afterwards from the materialized tree.
ff_boot_materialize() {
  local dest cand oid lib
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
  lib="$dest/hooks/local/lib/materialize-managed-source.sh"
  if [ -f "$lib" ]; then
    # shellcheck source=/dev/null
    . "$lib"
    ff_source_adopt "$dest" 1        # ownership + cleanup move to the lib
    FF_BOOT_TREE_OWNED=0
    trap 'ff_source_cleanup' EXIT
    trap 'rc=$?; ff_source_cleanup; exit $rc' INT TERM
    FF_SOURCE_REPO="$(cd "$SOURCE_CLONE" && pwd)"
    FF_SOURCE_COMMIT="$BOOT_COMMIT"
    FF_SOURCE_KIND="$([ -n "$BOOT_COMMIT" ] && echo git || echo plain)"
    ff_source_verify_tree "$dest" || return 1
    return 0
  fi
  # No boundary lib in the materialized tree = a genuinely pre-4.7.0 source. It may still
  # upgrade, but a manifest-BEARING tree with no verifier is refused (same rule as M10's).
  if [ -f "$dest/audit/managed-content-manifest.json" ]; then
    echo "[bootstrap-upgrade] FATAL: the source ships audit/managed-content-manifest.json but no" >&2
    echo "                    hooks/local/lib/materialize-managed-source.sh to verify it with, and" >&2
    echo "                    this install has no trusted copy either — these bytes cannot be proven" >&2
    echo "                    to be what upstream shipped. NOTHING was written." >&2
    return 1
  fi
  FF_SOURCE_STATE="UNVERIFIED_LEGACY_SOURCE"
  echo "[bootstrap-upgrade] NOTE: pre-boundary source (no manifest, no materializer) — proceeding as"
  echo "                    UNVERIFIED_LEGACY_SOURCE from the materialized tree (decision M10)."
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
FF_BH_LIB="$SOURCE_TREE/hooks/local/lib/backup-hygiene.sh"
[ -f "$FF_BH_LIB" ] || FF_BH_LIB="$ROOT/hooks/local/lib/backup-hygiene.sh"
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
BASE_REL="audit/managed-content-manifest.json"
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
# the flags when the source engine understands them (an older --source tree would exit 2).
if grep -q -- '--source-tree)' "$ENGINE_SRC" 2>/dev/null; then
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
