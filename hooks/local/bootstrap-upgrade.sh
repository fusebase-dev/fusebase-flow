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
#   is the one-shot first hop: it stages an upstream copy, copies the engine
#   scripts into hooks/local/, then runs upgrade.sh.
#
#   For an install that ALSO lacks this bootstrap script (truly old), copy-paste
#   the equivalent one-liner from the README "Upgrading an installed overlay"
#   section — it does the same clone + copy + run.
#
# What it does:
#   1. Ensure .fusebase-flow-source/ exists — clone upstream if absent (or reuse a
#      plain dir you already staged).
#   2. Copy the engine + recovery + mirror scripts from the source into hooks/local/
#      (upgrade.sh, upgrade-engine.sh, sync-version-strings.sh, post-fusebase-update.sh,
#      mirror-skills.sh, mirror-agents.sh, preflight.sh) + the overlay templates dir
#      + the engine's sourced lib dir hooks/local/lib/ (the new upgrade.sh sources
#      merge-module-size-baseline.sh from there; staging it BEFORE handoff is what
#      lets the v3.25.x baseline merge-preserve actually run on the adoption hop).
#   3. Hand off to upgrade.sh (passing through any flags, e.g. --dry-run / --auto-yes).
#
# What it does NOT do:
#   - Touch application code, .claude/settings.json, or CLI-owned assets.
#   - Delete anything (every copied target that already exists is backed up
#     .pre-bootstrap-<ts>).
#
# Usage:
#   bash hooks/local/bootstrap-upgrade.sh [--source <dir>] [--repo <url>] [--ref <branch>] [-- <upgrade.sh flags>]
# Examples:
#   bash hooks/local/bootstrap-upgrade.sh --dry-run
#   bash hooks/local/bootstrap-upgrade.sh -- --auto-yes
#   bash hooks/local/bootstrap-upgrade.sh --source ../fusebase-flow
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

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source) SRC_OVERRIDE="${2:-}"; shift 2 ;;
    --repo)   REPO_URL="${2:-}"; shift 2 ;;
    --ref)    REF="${2:-}"; shift 2 ;;
    --help|-h) sed -n '2,38p' "$0"; exit 0 ;;
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

if [ ! -f "$SOURCE_CLONE/VERSION" ]; then
  echo "[bootstrap-upgrade] FATAL: $SOURCE_CLONE/VERSION missing — not a Fusebase Flow source tree." >&2
  exit 1
fi
echo "[bootstrap-upgrade] Source VERSION: $(tr -d '\n\r' < "$SOURCE_CLONE/VERSION")"

# Git-exclude the *.pre-*-<ts> backup snapshots we are about to drop, so a downstream
# `git add -A` (notably FuseBase CLI's `fusebase update` checkpoint) never stages them.
# upgrade.sh's hooks.pre-upgrade/policies.pre-upgrade snapshots carry the OLD secret-scan
# fixtures that HARD-BLOCK such a checkpoint; git-excluding ALL backup families (incl. these
# .pre-bootstrap ones) keeps a wholesale add clean (field escalation, v4.3.2). Local + idempotent.
ff_git_exclude_backups() {
  local ex line d
  ex="$(git rev-parse --git-path info/exclude 2>/dev/null)" || return 0   # not a git repo -> no staging risk -> no-op
  [ -n "$ex" ] || return 0
  mkdir -p "$(dirname "$ex")" 2>/dev/null || return 1
  [ -e "$ex" ] && { [ -r "$ex" ] || return 1; }
  if [ -s "$ex" ] && [ -n "$(tail -c1 "$ex" 2>/dev/null)" ]; then
    printf '\n' >> "$ex" 2>/dev/null || return 1
  fi
  d='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'
  for line in \
    "# Fusebase Flow upgrade/refresh backups (transient; keep until validated) — never stage them." \
    "*.pre-upgrade-$d" \
    "*.pre-bootstrap-$d" \
    "*.pre-refresh-$d"; do
    if ! grep -qxF "$line" "$ex" 2>/dev/null; then
      printf '%s\n' "$line" >> "$ex" 2>/dev/null || return 1
    fi
  done
  return 0
}
ff_git_exclude_backups || echo "[bootstrap-upgrade] WARN: could not update .git/info/exclude — backups may be stageable by a later 'git add -A' (delete or unstage before committing)." >&2

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
ENGINE_SRC="$SOURCE_CLONE/hooks/local/upgrade.sh"
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
MCM_SRC="$SOURCE_CLONE/hooks/local/lib/managed_content_manifest.py"

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
  # TRIPWIRE (line endings) — VERIFIED, do not "simplify" this away: `git archive` DOES
  # apply core.autocrlf to files without an eol attribute (measured: autocrlf=true emits
  # CRLF, false/input emit LF). Without this flag the staging clone's own autocrlf wins and
  # the synthesized base hashes differ from the consumer's working tree for EVERY managed
  # path — they then classify changed-by-both and the upgrade aborts having delivered
  # nothing. Force the CONSUMER's convention so the base matches what their git wrote.
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
echo "[bootstrap-upgrade] Handing off to $ENGINE_SRC ${PASSTHROUGH[*]:-}"
echo ""
if [ "${#PASSTHROUGH[@]}" -gt 0 ]; then
  exec bash "$ENGINE_SRC" "${PASSTHROUGH[@]}"
else
  exec bash "$ENGINE_SRC"
fi
