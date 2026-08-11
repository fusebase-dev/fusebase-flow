#!/usr/bin/env bash
# Fusebase Flow — guarded orphan reap. Ticket: docs/backlog/harness-kill-leaves-orphan-children/.
#
# Sourced by BOTH teardown paths — hooks/tests/lib/orphan-sentinel.sh (out-of-band) and
# hooks/tests/run-tests.sh's EXIT trap (harness-side). One guard set, never two copies.
#
# FAIL CLOSED is the contract: every guard returns WITHOUT signalling when it cannot POSITIVELY
# confirm the recorded identity. Unresolvable own/harness pgid, non-numeric pgid, start-token
# mismatch, occupied-but-unverifiable leader pid, and no process table at all => kill NOTHING.
#
# TRIPWIRE — I/O BUDGET. The harness-side path runs inside the outer `timeout -k` grace, so the
# guards must reach `kill` within a few seconds or be SIGKILLed having signalled nothing (measured:
# they were). On this platform ONE `/proc/<pid>/stat` read costs ~500ms while ONE `ps` covering
# every process costs ~350ms. So: one `ps` snapshot serves the own-group, ancestry and membership
# lookups, and `/proc` is read ONLY for start tokens, which `ps` does not carry — two reads total.
# Do NOT reintroduce a per-pid `/proc` walk, a `$( )` per lookup, or a `<<<` (a temp file each).
#
# Identity record (written by hooks/local/lib/run-with-timeout.sh: ffhc_sentinel_note):
#   "v1 <pid> <winpid|-> <pgid|-> END"  — one APPENDED line. A short append is a single write,
#   so a reader never sees a partial record; "nothing in flight" is a truncate, likewise atomic.
#   ffor_state_read takes the LAST complete v1..END line.

FFOR_COMM=""; FFOR_PPID=""; FFOR_PGID=""; FFOR_START=""
FFOR_S_PID=""; FFOR_S_WIN=""; FFOR_S_PGID=""
FFOR_R_PGID=""; FFOR_R_LEADSTART=""
FFOR_MEMBERS=""
FFOR_PS=""
FFOR_ROW_PPID=""; FFOR_ROW_PGID=""; FFOR_ROW_WIN=""
FFOR_PGID_OUT=""

ffor_numeric() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
ffor_alive() { kill -0 "${1:-0}" 2>/dev/null; }

# ffor_snapshot: one `ps` for the whole reap into FFOR_PS. Returns 1 when no process table is
# available, which every caller must treat as "cannot confirm anything".
ffor_snapshot() {
  FFOR_PS=""
  command -v ps >/dev/null 2>&1 || return 1
  FFOR_PS="$(ps 2>/dev/null)" || return 1
  [ -n "$FFOR_PS" ] || return 1
  return 0
}

# ffor_row PID -> FFOR_ROW_PPID/PGID/WIN from the snapshot (columns: PID PPID PGID WINPID …).
# Fork-free by construction: an `awk`/`grep` per lookup would cost more than the snapshot did.
ffor_row() {
  FFOR_ROW_PPID=""; FFOR_ROW_PGID=""; FFOR_ROW_WIN=""
  local want="${1:-}" rows="$FFOR_PS" line rest a
  ffor_numeric "$want" || return 1
  while [ -n "$rows" ]; do
    line="${rows%%$'\n'*}"
    if [ "$line" = "$rows" ]; then rows=""; else rows="${rows#*$'\n'}"; fi
    line="${line#"${line%%[! ]*}"}"
    a="${line%% *}"
    [ "$a" = "$want" ] || continue
    rest="${line#"$a"}"; rest="${rest#"${rest%%[! ]*}"}"
    FFOR_ROW_PPID="${rest%% *}"
    rest="${rest#"$FFOR_ROW_PPID"}"; rest="${rest#"${rest%%[! ]*}"}"
    FFOR_ROW_PGID="${rest%% *}"
    rest="${rest#"$FFOR_ROW_PGID"}"; rest="${rest#"${rest%%[! ]*}"}"
    FFOR_ROW_WIN="${rest%% *}"
    ffor_numeric "$FFOR_ROW_PPID" && ffor_numeric "$FFOR_ROW_PGID" || return 1
    return 0
  done
  return 1
}

# ffor_identity PID: parse /proc/<pid>/stat into FFOR_COMM/PPID/PGID/START. Returns 1 when the pid
# is gone OR the line is unparsable — a caller must treat 1 as UNCONFIRMED, never as "fine".
# This is the ONLY source of the start token, so it stays; keep its call sites countable.
# comm is split off by pattern first, so a name containing a space cannot shift the numeric fields.
ffor_identity() {
  FFOR_COMM=""; FFOR_PPID=""; FFOR_PGID=""; FFOR_START=""
  local s rest tok n=0
  ffor_numeric "${1:-}" || return 1
  IFS= read -r s 2>/dev/null < "/proc/$1/stat" || return 1
  case "$s" in *') '*) : ;; *) return 1 ;; esac
  FFOR_COMM="${s%%) *}"; FFOR_COMM="${FFOR_COMM##*\(}"
  rest="${s#*) }"
  while [ -n "$rest" ]; do              # after "(comm) ": 1 state, 2 ppid, 3 pgrp … 20 starttime
    tok="${rest%% *}"; n=$((n + 1))
    case "$n" in
      2)  FFOR_PPID="$tok" ;;
      3)  FFOR_PGID="$tok" ;;
      20) FFOR_START="$tok"; break ;;
    esac
    [ "$tok" = "$rest" ] && break
    rest="${rest#* }"
  done
  ffor_numeric "$FFOR_PPID" && ffor_numeric "$FFOR_PGID" && ffor_numeric "$FFOR_START" || return 1
  return 0
}

# ffor_pgid_of PID -> FFOR_PGID_OUT, from the snapshot when there is one, else /proc. An empty
# result is always a refusal at the call site, never a default.
ffor_pgid_of() {
  FFOR_PGID_OUT=""
  if [ -n "$FFOR_PS" ] && ffor_row "${1:-}"; then FFOR_PGID_OUT="$FFOR_ROW_PGID"; return 0; fi
  ffor_identity "${1:-}" || return 1
  FFOR_PGID_OUT="$FFOR_PGID"
  return 0
}

# ffor_state_read STATE -> FFOR_S_PID/WIN/PGID ("" when nothing is in flight or no complete
# record exists). An incomplete tail line is IGNORED rather than read as "nothing in flight".
ffor_state_read() {
  FFOR_S_PID=""; FFOR_S_WIN=""; FFOR_S_PGID=""
  [ -r "${1:-}" ] || return 0
  local v p w g e
  while read -r v p w g e; do
    [ "$v" = "v1" ] && [ "$e" = "END" ] || continue
    FFOR_S_PID="$p"; FFOR_S_WIN="$w"; FFOR_S_PGID="$g"
  done < "$1"
  [ "$FFOR_S_WIN" = "-" ] && FFOR_S_WIN=""
  [ "$FFOR_S_PGID" = "-" ] && FFOR_S_PGID=""
  ffor_numeric "$FFOR_S_PID" || { FFOR_S_PID=""; FFOR_S_WIN=""; FFOR_S_PGID=""; }
  return 0
}

# ffor_resolve PID [PGID] -> FFOR_R_PGID + FFOR_R_LEADSTART (the group LEADER's start token — the
# field that binds this group to this run across pid reuse). Requires a LIVE pid; returns 1 with
# empty outputs unless the group is self-led and every field is numeric. The recorded PGID is a
# HINT only: it can predate the child's own setpgid, so the LIVE group wins.
ffor_resolve() {
  FFOR_R_PGID=""; FFOR_R_LEADSTART=""
  local pgid
  [ -n "$FFOR_PS" ] || ffor_snapshot || true
  ffor_pgid_of "${1:-}" || return 1
  pgid="$FFOR_PGID_OUT"
  ffor_numeric "$pgid" || return 1
  ffor_identity "$pgid" || return 1          # start token: /proc is the only source
  [ "$FFOR_PGID" = "$pgid" ] || return 1     # a leader must lead its own group
  FFOR_R_PGID="$pgid"; FFOR_R_LEADSTART="$FFOR_START"
  return 0
}

# ffor_is_ancestor PID PGID: 0 (true) when PID, or any process in PGID, is on THIS process's parent
# chain — reaping it would kill something we run inside. This is what makes the "never an ancestor"
# guarantee an implementation rather than a comment. NO process table => 0 (refuse): an
# unverifiable chain is not a safe chain. A link missing from the table ends the walk only when it
# is also provably dead. Bounded to 32 hops so a self-referential ppid cannot spin.
ffor_is_ancestor() {
  local target_pid="${1:-}" target_pgid="${2:-}" p=$$ hops=0
  [ -n "$FFOR_PS" ] || return 0
  while [ "$hops" -lt 32 ]; do
    [ "$p" = "$target_pid" ] && return 0
    if ! ffor_row "$p"; then
      ffor_alive "$p" && return 0
      return 1
    fi
    [ "$FFOR_ROW_PGID" = "$target_pgid" ] && return 0
    [ "$FFOR_ROW_PPID" -le 1 ] && return 1
    p="$FFOR_ROW_PPID"; hops=$((hops + 1))
  done
  return 0
}

# ffor_group_members PGID -> FFOR_MEMBERS ("<pid> <winpid>" rows) from the snapshot. Returns 1 when
# there is no snapshot, so a caller can never read an empty list as "the group is empty".
ffor_group_members() {
  FFOR_MEMBERS=""
  local want="${1:-}" rows line rest pid ppid pgid win
  # Take a snapshot if the caller has not: returning 1 for "no snapshot yet" reads identically to
  # "no process table", and a caller that mistook one for the other would silently see an empty
  # group. Callers that need FRESH data (ffor_reap's post-kill sweep) re-snapshot explicitly.
  [ -n "$FFOR_PS" ] || ffor_snapshot || return 1
  rows="$FFOR_PS"
  ffor_numeric "$want" || return 1
  while [ -n "$rows" ]; do
    line="${rows%%$'\n'*}"
    if [ "$line" = "$rows" ]; then rows=""; else rows="${rows#*$'\n'}"; fi
    line="${line#"${line%%[! ]*}"}"
    pid="${line%% *}"
    ffor_numeric "$pid" || continue
    rest="${line#"$pid"}";  rest="${rest#"${rest%%[! ]*}"}"
    ppid="${rest%% *}";     rest="${rest#"$ppid"}"; rest="${rest#"${rest%%[! ]*}"}"
    pgid="${rest%% *}";     rest="${rest#"$pgid"}"; rest="${rest#"${rest%%[! ]*}"}"
    win="${rest%% *}"
    [ "$pgid" = "$want" ] || continue
    FFOR_MEMBERS="$FFOR_MEMBERS$pid $win"$'\n'
  done
  return 0
}

# ffor_any_alive ROWS: 0 (true) while any "<pid> <winpid>" row is still alive. Fork-free.
ffor_any_alive() {
  local rows="${1:-}" p line
  while [ -n "$rows" ]; do
    line="${rows%%$'\n'*}"
    if [ "$line" = "$rows" ]; then rows=""; else rows="${rows#*$'\n'}"; fi
    p="${line%% *}"
    ffor_numeric "$p" && ffor_alive "$p" && return 0
  done
  return 1
}

# ffor_reap PID WINPID PGID LEADER_START HARNESS_PGID GRACE
# Terminate that ONE process group. Always returns 0 — no caller may depend on a kill happening.
ffor_reap() {
  local cpid="${1:-}" cwin="${2:-}" cpgid="${3:-}" clead="${4:-}" hpgid="${5:-}" grace="${6:-5}"
  local own i rows mpid mwin

  ffor_numeric "$cpgid" || return 0
  [ "$cpgid" -gt 1 ] || return 0
  ffor_numeric "$clead" || return 0          # no group-identity token => nothing is confirmable
  ffor_numeric "$grace" || grace=5
  ffor_snapshot || return 0                  # no process table => confirm nothing, kill nothing

  # Never our own group, never the harness's, never an ancestor's. An UNRESOLVED lookup kills
  # NOTHING: the shipped guard failed OPEN here, so an empty pgid read removed the guard entirely.
  ffor_pgid_of $$ || return 0
  own="$FFOR_PGID_OUT"
  ffor_numeric "$own" || return 0
  [ "$cpgid" = "$own" ] && return 0
  ffor_numeric "$hpgid" || return 0
  [ "$cpgid" = "$hpgid" ] && return 0
  ffor_is_ancestor "$cpid" "$cpgid" && return 0

  # Bind the GROUP, not the leader's liveness: the leaked topology has the leader DEAD with
  # descendants alive, which is the case this exists for. A pgid equals its leader's pid, so a
  # FREE leader pid means every process still carrying this pgid joined while OUR leader held
  # it; an OCCUPIED leader pid must still carry our recorded start token, or this is pid reuse.
  if ffor_identity "$cpgid"; then
    [ "$FFOR_START" = "$clead" ] || return 0
    [ "$FFOR_PGID" = "$cpgid" ] || return 0
  else
    ffor_alive "$cpgid" && return 0          # occupied but unverifiable => kill nothing
  fi

  # A still-live recorded child must still match what was recorded.
  if ffor_alive "$cpid"; then
    ffor_row "$cpid" || return 0
    [ "$FFOR_ROW_PGID" = "$cpgid" ] || return 0
    [ -n "$cwin" ] && [ "$FFOR_ROW_WIN" != "$cwin" ] && return 0
  fi

  # SIGNAL FIRST, account afterwards: on the harness's EXIT path every millisecond spent above
  # this line is a chance to be SIGKILLed having signalled nothing.
  kill -TERM -"$cpgid" 2>/dev/null
  ffor_group_members "$cpgid"; rows="$FFOR_MEMBERS"
  i=0
  while [ "$i" -lt "$grace" ]; do
    ffor_any_alive "$rows" || break
    sleep 1; i=$((i + 1))
  done
  kill -KILL -"$cpgid" 2>/dev/null

  # Native survivors a POSIX group signal cannot reach. EVERY target is revalidated against a
  # FRESH process-table observation taken after the kill — the pre-kill snapshot alone is a TOCTOU
  # window wide enough for pid reuse (docs/problem-catalog/bounded-run-msys-collateral-kill/).
  command -v taskkill >/dev/null 2>&1 || return 0
  ffor_snapshot || return 0
  ffor_group_members "$cpgid" || return 0
  rows="$FFOR_MEMBERS"
  while [ -n "$rows" ]; do
    mpid="${rows%%$'\n'*}"
    if [ "$mpid" = "$rows" ]; then rows=""; else rows="${rows#*$'\n'}"; fi
    mwin="${mpid#* }"; mpid="${mpid%% *}"
    ffor_numeric "$mpid" || continue
    ffor_numeric "$mwin" || continue
    [ "$mpid" = "$$" ] && continue
    ffor_alive "$mpid" || continue
    ffor_row "$mpid" || continue
    [ "$FFOR_ROW_PGID" = "$cpgid" ] || continue
    [ "$FFOR_ROW_WIN" = "$mwin" ] || continue
    taskkill //F //PID "$mwin" >/dev/null 2>&1 || true
  done
  return 0
}
