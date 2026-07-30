#!/usr/bin/env bash
# Fusebase Flow — sanctioned removal of Flow's own upgrade backups (decision M5).
#
# TRIPWIRE (M5): authorization is EXACT repo-relative stem membership — never a string prefix,
# glob, `startsWith`, or bare-basename alias. `agentsX.pre-upgrade-<ts>`,
# `agents.pre-upgrade-<ts>.bak` and a root-level `hook-layer-manifest.json.pre-upgrade-<ts>` are
# NOT members. Widening this predicate turns a validated tool back into `rm -rf` with extra steps.
#
# TRIPWIRE (M5): exactly two CLI forms, and they cannot be combined:
#   bash hooks/local/cleanup-flow-backups.sh --all
#   bash hooks/local/cleanup-flow-backups.sh <exact-repo-relative-target> [<target> ...]
# Adding another form (--list / --dry-run / a pattern mode) needs the decision redirected first.
#
# Eligible: `<authorized-stem>.pre-upgrade-<YYYYMMDDTHHMMSSZ>`, where <authorized-stem> is an exact
#   repo-relative name from `managed_content_manifest.py list-managed` (the K14 single home) plus
#   VERSION, legacy `skills`, policies/module-size-baseline.txt and each installed
#   docs/_fusebase-flow/<doc>.md; and the exact `.fusebase-flow-source` staging clone.
# Refused before ANY deletion: absolute paths, `..`, glob/shell metacharacters, symlinks,
#   non-members, malformed stamps, and anything resolving outside the repo root. An invalid
#   explicit batch deletes none of its members.
#
# Exit: 0 success / nothing to do; 1 refused or error; 2 bad arg.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || { echo "[cleanup-flow-backups] FATAL: cannot enter repo root." >&2; exit 1; }
ROOT_RESOLVED="$(cd "$ROOT" && pwd -P)"

SOURCE_CLONE_TARGET=".fusebase-flow-source"

MODE=""
TARGETS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)      [ -z "$MODE" ] || { echo "[cleanup-flow-backups] FATAL: --all cannot be combined with explicit targets." >&2; exit 2; }; MODE="all" ;;
    --help|-h)  sed -n '2,22p' "$0"; exit 0 ;;
    -*)         echo "[cleanup-flow-backups] FATAL: unknown option: $1" >&2; exit 2 ;;
    *)
      [ "$MODE" = "all" ] && { echo "[cleanup-flow-backups] FATAL: --all cannot be combined with explicit targets." >&2; exit 2; }
      MODE="targets"; TARGETS+=("$1") ;;
  esac
  shift
done
if [ -z "$MODE" ]; then
  echo "[cleanup-flow-backups] FATAL: choose exactly one mode — --all, or one or more exact repo-relative targets." >&2
  echo "                       Run with --help for the eligibility rules." >&2
  exit 2
fi

BH_LIB="$ROOT/hooks/local/lib/backup-hygiene.sh"
if [ ! -f "$BH_LIB" ]; then
  echo "[cleanup-flow-backups] FATAL: missing $BH_LIB — ff_backup_stem is the exact-shape authority." >&2
  exit 1
fi
# shellcheck source=lib/backup-hygiene.sh
. "$BH_LIB"

# ---- the authorized stem set (exact names, never patterns) --------------------------------
MCM="$ROOT/hooks/local/lib/managed_content_manifest.py"
AUTHORIZED_STEMS=""
if command -v python3 >/dev/null 2>&1 && [ -f "$MCM" ]; then
  AUTHORIZED_STEMS="$(
    { python3 "$MCM" list-managed --dirs; python3 "$MCM" list-managed --files; } 2>/dev/null | sed '/^$/d'
  )"
fi
if [ -z "$AUTHORIZED_STEMS" ]; then
  # FAIL CLOSED: an empty authority set must never mean "everything is eligible".
  echo "[cleanup-flow-backups] FATAL: could not read the managed set from $MCM (python3 present?)." >&2
  echo "                       Refusing to delete anything without its exact authority list." >&2
  exit 1
fi
# TRIPWIRE (M5): every entry is an EXACT repo-relative stem. Never add a bare-basename alias for
# a nested path — `audit/hook-layer-manifest.json` must not make a ROOT-level
# hook-layer-manifest.json.pre-upgrade-<ts> eligible. A basename alias is string-prefix
# authorization by another name: the authority set stops describing paths and starts describing
# names, and every same-named file anywhere in the tree inherits the authority.
AUTHORIZED_STEMS="$AUTHORIZED_STEMS
VERSION
skills
policies/module-size-baseline.txt"
# Framework docs land namespaced; only stems that are actually INSTALLED are authorized.
if [ -d docs/_fusebase-flow ]; then
  while IFS= read -r d; do
    [ -n "$d" ] && AUTHORIZED_STEMS="$AUTHORIZED_STEMS
$d"
  done < <(find docs/_fusebase-flow -maxdepth 1 -name '*.md' -type f 2>/dev/null | sed 's#^\./##')
fi

is_authorized_stem() {   # <stem>
  case $'\n'"$AUTHORIZED_STEMS"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

# ---- per-target validation ---------------------------------------------------------------
# Echoes nothing; sets REJECT_REASON on refusal. Order matters: syntax first (cheapest and
# most dangerous), then membership, then filesystem identity.
REJECT_REASON=""
validate_target() {   # <repo-relative target>
  local t="$1" stem base dir full resolved
  REJECT_REASON=""
  case "$t" in
    "")            REJECT_REASON="empty target"; return 1 ;;
    /*|[A-Za-z]:*|'\\'*) REJECT_REASON="absolute path (targets are repo-relative)"; return 1 ;;
    *..*)          REJECT_REASON="'..' path segment"; return 1 ;;
    *'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*|*'~'*)
                   REJECT_REASON="glob metacharacter (this tool never expands patterns)"; return 1 ;;
    *'$'*|*'`'*|*';'*|*'&'*|*'|'*|*'
'*)                REJECT_REASON="shell metacharacter or newline"; return 1 ;;
  esac
  t="${t%/}"
  [ -e "$t" ] || { REJECT_REASON="does not exist"; return 1; }
  # TRIPWIRE (destructive): a symlink is refused OUTRIGHT — resolving it and deleting the
  # resolved path would let a link inside the repo delete something outside it, and deleting
  # the link itself while calling it a backup would be a lie about what was removed.
  [ -L "$t" ] && { REJECT_REASON="symlink (refused outright, inside or outside the repo)"; return 1; }
  if [ "$t" = "$SOURCE_CLONE_TARGET" ]; then
    :   # the staging clone: an explicitly allowed target, no timestamp involved
  else
    base="${t##*/}"
    stem="$(ff_backup_stem "$base" 2>/dev/null)" || {
      REJECT_REASON="not a '<managed-name>.pre-upgrade-<YYYYMMDDTHHMMSSZ>' backup name"; return 1; }
    dir="${t%/*}"; [ "$dir" = "$t" ] && dir=""
    # The authority is the WHOLE repo-relative stem, so a nested authority never leaks to the
    # root and a root authority never leaks into a subdirectory.
    full="${dir:+$dir/}$stem"
    if ! is_authorized_stem "$full"; then
      REJECT_REASON="'$full' is not an exact member of the managed set (exact repo-relative stems only — no basename or prefix matching)"
      return 1
    fi
  fi
  # Resolved-path containment: the parent must resolve inside the repo root, and the target
  # must be a direct child of it. Checked AFTER the symlink refusal, as defence in depth.
  dir="${t%/*}"; [ "$dir" = "$t" ] && dir="."
  resolved="$(cd "$dir" 2>/dev/null && pwd -P)" || { REJECT_REASON="parent directory unreachable"; return 1; }
  case "$resolved" in
    "$ROOT_RESOLVED"|"$ROOT_RESOLVED"/*) ;;
    *) REJECT_REASON="resolves outside the repo root ($resolved)"; return 1 ;;
  esac
  return 0
}

# ---- --all enumeration -------------------------------------------------------------------
# Enumerates ONLY what validate_target already authorizes: the same predicate, never a wider
# find. Depth is bounded to the two places Flow actually writes backups.
enumerate_eligible() {
  local p
  { find . -maxdepth 1 -name "*.pre-upgrade-$FF_BACKUP_TS_GLOB" 2>/dev/null
    find ./audit ./policies ./docs/_fusebase-flow -maxdepth 1 \
      -name "*.pre-upgrade-$FF_BACKUP_TS_GLOB" 2>/dev/null
    [ -e "$SOURCE_CLONE_TARGET" ] && printf '%s\n' "./$SOURCE_CLONE_TARGET"
  } | sed 's#^\./##' | sort -u | while IFS= read -r p; do
        [ -n "$p" ] || continue
        validate_target "$p" && printf '%s\n' "$p"
      done
}

if [ "$MODE" = "all" ]; then
  mapfile -t TARGETS < <(enumerate_eligible)
  if [ "${#TARGETS[@]}" -eq 0 ]; then
    echo "[cleanup-flow-backups] no eligible Flow backups found — nothing to do."
    exit 0
  fi
else
  # ALL-OR-NOTHING: validate the whole explicit batch before deleting any member, so a typo in
  # target 4 can never leave targets 1-3 already gone.
  REFUSALS=""
  for t in "${TARGETS[@]}"; do
    validate_target "$t" || REFUSALS="$REFUSALS
  - $t  ($REJECT_REASON)"
  done
  if [ -n "$REFUSALS" ]; then
    echo "[cleanup-flow-backups] REFUSED — nothing was deleted:$REFUSALS" >&2
    echo "[cleanup-flow-backups] Eligible targets right now:" >&2
    enumerate_eligible | sed 's/^/    /' >&2
    exit 1
  fi
fi

removed=0
for t in "${TARGETS[@]}"; do
  t="${t%/}"
  if rm -rf -- "$t"; then
    echo "[cleanup-flow-backups] removed $t"
    removed=$((removed + 1))
  else
    echo "[cleanup-flow-backups] WARN: could not remove $t" >&2
  fi
done
echo "[cleanup-flow-backups] done — $removed target(s) removed."
exit 0
