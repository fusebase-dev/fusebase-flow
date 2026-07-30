#!/usr/bin/env bash
# Fusebase Flow — transient .pre-*-<ts> backup hygiene (one home for three consumers).
#
# PROVENANCE:
#   Extracted verbatim from hooks/local/upgrade.sh + hooks/local/bootstrap-upgrade.sh per
#   FR-25 (the engine is at the 800-line ceiling) — the git-exclude half was DUPLICATED in
#   both entry scripts. Sourced by both, and by hooks/local/cleanup-flow-backups.sh.
#
# API:
#   FF_BACKUP_TS_GLOB          the EXACT `date -u +%Y%m%dT%H%M%SZ` shell glob
#   ff_backup_stem <name>      echo the stem iff <name> is exactly "<stem>.pre-upgrade-<ts>"
#   ff_git_exclude_backups     idempotently git-exclude the backup families (rc 1 = write failed)
#   ff_prune_pre_backups [N]   keep the newest N backups per stem, delete the rest

# TRIPWIRE (DELETE-path defense-in-depth): the suffix is `date -u +%Y%m%dT%H%M%SZ`, so every
# consumer requires this EXACT shape. A file that merely CONTAINS ".pre-upgrade-" (e.g.
# config.pre-upgrade-template.yml) can never match, so it is never eligible for deletion,
# never pruned from a test's discovery set, and never authorized for cleanup.
FF_BACKUP_TS_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z'

ff_backup_stem() {   # <basename> -> stem on stdout; rc 1 when not an exact Flow backup name
  local n="$1" stem ts
  stem="${n%.pre-upgrade-*}"
  [ "$stem" != "$n" ] && [ -n "$stem" ] || return 1
  ts="${n#"$stem".pre-upgrade-}"
  case "$ts" in
    $FF_BACKUP_TS_GLOB) printf '%s\n' "$stem" ;;
    *) return 1 ;;
  esac
}

# Git-exclude the *.pre-*-<ts> backup snapshots the upgrade is about to drop, so a
# downstream `git add -A` (notably FuseBase CLI's `fusebase update` pre-update checkpoint)
# never stages them. Flow's own backups carry the OLD secret-scan test fixtures (dummy
# ghp_/sk-ant-/cookie literals), which otherwise trip the pre-commit secret scan and
# HARD-BLOCK the checkpoint (field escalation, v4.3.2). Local + idempotent. Keep the
# backups until validated: only previously-COMMITTED content is recoverable from git
# history; an uncommitted local customization overwritten during refresh survives only
# in its backup.
ff_git_exclude_backups() {
  local ex line d
  # git-path resolves info/exclude to the COMMON dir for linked worktrees (--git-dir would
  # point at .git/worktrees/<id>/, whose info/exclude git does NOT read). NOT a git repo (or
  # git unavailable) => no `git add -A` staging risk => nothing to exclude => success no-op
  # (return 0). Only a real WRITE failure inside a git repo returns nonzero (so the caller
  # can note it without silently claiming the backups are git-excluded).
  ex="$(git rev-parse --git-path info/exclude 2>/dev/null)" || return 0
  [ -n "$ex" ] || return 0
  mkdir -p "$(dirname "$ex")" 2>/dev/null || return 1
  # If the file exists it must be READABLE (so grep rc1 = "absent" is trustworthy, not an I/O
  # error) and, if non-empty, END IN A NEWLINE — else the first append glues onto an
  # unterminated last line and the pattern is swallowed (commented out).
  [ -e "$ex" ] && { [ -r "$ex" ] || return 1; }
  if [ -s "$ex" ] && [ -n "$(tail -c1 "$ex" 2>/dev/null)" ]; then
    printf '\n' >> "$ex" 2>/dev/null || return 1
  fi
  d="$FF_BACKUP_TS_GLOB"
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

# U10: .pre-* backup retention (keep the most-recent N per stem). Left unpruned they accrete
# (~70 observed, dotfile-prefixed so easy to miss). The <ts> is a sortable UTC stamp, so
# lexicographic reverse-sort == newest-first. Only OUR timestamped suffixes; never .git /
# the source clone.
#
# WS5 busy-loop ROOT FIX (not just a bound): the prior prune ran a FULL-TREE `find .` PER
# unique stem (K stems x M files = O(K*M) traversals, each a fork), so a large backup set
# fork-stormed MSYS into an apparent busy-loop / 255-at-tail. This is SINGLE-PASS: ONE
# `find`, tag each backup with its stem, sort by (stem, ts-descending) so same-stem
# newest-first are adjacent, then one awk pass emits only the ones BEYOND N. O(M) forks.
ff_prune_pre_backups() {
  local retain="${1:-${FF_PRE_RETAIN:-3}}"
  case "$retain" in ''|*[!0-9]*) retain=3 ;; esac
  local to_delete bak _tsg="$FF_BACKUP_TS_GLOB"
  to_delete="$(
    find . -path ./.git -prune -o -path ./.fusebase-flow-source -prune -o \
      \( -name "*.pre-upgrade-$_tsg" -o -name "*.pre-refresh-$_tsg" \) -print 2>/dev/null \
    | sed -nE 's|^(.*)\.pre-(upgrade\|refresh)-([0-9]{8}T[0-9]{6}Z)$|\1\t\3\t&|p' \
    | sort -t "$(printf '\t')" -k1,1 -k2,2r \
    | awk -F '\t' -v n="$retain" '{ if ($1==prev) c++; else { c=1; prev=$1 } if (c>n) print $3 }'
  )"
  [ -n "$to_delete" ] || return 0
  while IFS= read -r bak; do
    [ -n "$bak" ] && [ -e "$bak" ] || continue
    rm -rf -- "$bak" && echo "[upgrade] U10: pruned old backup $bak"
  done <<< "$to_delete"
}
