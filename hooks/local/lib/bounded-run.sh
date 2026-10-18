#!/usr/bin/env bash
# Fusebase Flow — liveness-discipline bounded-run helper (FR-27).
# spec: docs/specs/liveness-discipline/spec.md (AC3). skill: flow-skills/liveness-discipline.
#
# WHY: a long/silent background launch that HANGS emits no completion event, so the
# agent is never re-invoked and idles silently. This wrapper bounds the MONITORED
# process to a wall-clock deadline, emits a heartbeat while it runs, and ALWAYS
# prints a terminal line (completion or a "bounded-run: TIMEOUT" line) so the job
# reaches completion-or-death instead of a 0-byte silent idle.
#
# REUSE-NOT-DUPLICATE: the bounded-execution core (timeout/gtimeout detection, the
# -k kill grace, rc-124/137 timeout classification, the no-binary skip policy) is
# sourced from run-with-timeout.sh. That file's ffhc_* API is the contract the
# health-check engine sources directly — this helper MUST NOT modify it (FR-07).
#
# HONEST SCOPE (D7 — do not overstate): this bounds the monitored process only. It
# does NOT kill an `&`-detached grandchild or an uninterruptible OS wait, and does
# NOT prove the host re-invokes the agent. Don't `&`-detach under the wrapper; put
# a deadline INSIDE long scripts too. See the skill for the full protocol.

# Source the shared core (ffhc_detect_timeout / run_with_timeout / ffhc_timed_out).
# Resolve via BASH_SOURCE so it works wherever the lib dir is copied.
# shellcheck source=run-with-timeout.sh
. "$(dirname "${BASH_SOURCE[0]}")/run-with-timeout.sh"

# TRIPWIRE: resolved once at source time — a relative BASH_SOURCE after a caller's `cd` would write
# outside the git-excluded <repo>/state/audit/liveness (decision D; backup-hygiene.sh writes the exclude).
_BR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd -P)"
_BR_HB_DEFAULT=""
if [ -n "$_BR_ROOT" ] && [ -f "$_BR_ROOT/hooks/local/lib/bounded-run.sh" ]; then
  _BR_HB_DEFAULT="$_BR_ROOT/state/audit/liveness"
fi

# bounded_run DEADLINE_SECS LABEL -- CMD [ARGS...]
#   Runs CMD bounded to DEADLINE_SECS via the sourced run_with_timeout core, with a
#   stderr heartbeat every BOUNDED_RUN_HEARTBEAT_SECS (default 10) so a live-but-slow
#   job can't masquerade as a hang. ALWAYS emits a terminal stderr line:
#     "bounded-run: TIMEOUT after <secs>s — <label> (rc <rc>)"  on a timeout-induced kill, OR
#     "bounded-run: done — <label> (rc <rc>, <secs>s)"          on normal completion.
#   Returns the wrapped command's own rc; 124 on deadline-elapsed; 137 when the child
#   ignored SIGTERM and was SIGKILLed after run_with_timeout's -k grace.
#   No-timeout-binary policy is inherited from the core (see below) — never a false
#   "bounded": with no binary and BOUNDED_RUN_ALLOW_UNBOUNDED!=1 the run is SKIPPED
#   (terminal "SKIPPED (no timeout binary)" line, sentinel rc 125), so a slow op can
#   never silently hang the caller.
#   Heartbeat file: BOUNDED_RUN_HB_DIR (unset = <repo>/state/audit/liveness; empty = off), one
#   <label>-<pid>-<n>.hb per call; *.hb untouched for BOUNDED_RUN_HB_RETAIN_DAYS (7) are pruned.
#   Line 2 is `cmd sha256=<hex>`, the sha256 of CMD's arguments each NUL-terminated (absent without a hasher).
#   TRIPWIRE: a "running" record proves the WRAPPER is alive, never that CMD progresses. No terminal record
#   (done/TIMEOUT/SKIPPED) = the wrapper has not returned yet; an rc-137 return lands after deadline +
#   FFHC_TIMEOUT_KILL_GRACE (5s), so call it hung only with none by launch + deadline + grace + ~30 s (MSYS reap).
bounded_run() {
  local deadline="$1" label="$2"; shift 2
  [ "${1:-}" = "--" ] && shift   # tolerate the readability "--" separator

  local hb="${BOUNDED_RUN_HEARTBEAT_SECS:-10}" hbf
  _bounded_run_hb_open "$label" "$deadline" "$@"; hbf="$_BR_HB_FILE"
  ffhc_detect_timeout

  # No-binary policy (mirrors ffhc_run_bounded H5): SKIP rather than run unbounded,
  # so the absence of `timeout` can never reintroduce a silent unbounded wait. An
  # operator can opt into an unbounded run with BOUNDED_RUN_ALLOW_UNBOUNDED=1.
  if [ -z "${FFHC_TIMEOUT_BIN:-}" ] && [ "${BOUNDED_RUN_ALLOW_UNBOUNDED:-0}" != "1" ]; then
    echo "bounded-run: SKIPPED (no timeout binary) — $label" >&2
    _bounded_run_hb_note "$hbf" "SKIPPED"
    return 125
  fi

  # Heartbeat child: incremental progress to stderr while CMD runs. It is internal
  # plumbing fully owned and reaped by this function (the `kill` below) — NOT user
  # `&`-detached work, so it does not contradict the don't-detach rule. Bounded by
  # its own (deadline + grace) cap so it can never outlive a wrapper that died.
  local hb_pid=""
  if [ "$hb" -gt 0 ] 2>/dev/null; then
    _bounded_run_heartbeat "$hb" "$deadline" "$label" "$hbf" &
    hb_pid=$!
  fi

  local start rc end elapsed
  start=$(date +%s)
  if [ -n "${FFHC_TIMEOUT_BIN:-}" ]; then
    run_with_timeout "$deadline" "$@"; rc=$?
  else
    "$@"; rc=$?   # BOUNDED_RUN_ALLOW_UNBOUNDED=1 path (operator opt-in)
  fi
  end=$(date +%s); elapsed=$((end - start))

  # Reap the heartbeat (it is ours; never leave it running past the monitored proc).
  if [ -n "$hb_pid" ]; then
    kill "$hb_pid" 2>/dev/null
    wait "$hb_pid" 2>/dev/null
  fi

  # Terminal line — guaranteed on EVERY path so the job reaches completion-or-death.
  if ffhc_timed_out "$rc"; then
    echo "bounded-run: TIMEOUT after ${deadline}s — $label (rc $rc)" >&2
    _bounded_run_hb_note "$hbf" "TIMEOUT rc=$rc"
  else
    echo "bounded-run: done — $label (rc $rc, ${elapsed}s)" >&2
    _bounded_run_hb_note "$hbf" "done rc=$rc ${elapsed}s"
  fi
  return "$rc"
}

# Sets _BR_HB_FILE ("" = off). Not callable via $(...): BASHPID and the sequence must be the caller's.
# TRIPWIRE: every write is `{ ...; } 2>/dev/null || :` — a file failure must never change rc or leak stderr.
_bounded_run_hb_open() {
  local dir="${BOUNDED_RUN_HB_DIR-$_BR_HB_DEFAULT}" name="${1//[^A-Za-z0-9._-]/-}"
  _BR_HB_FILE=""
  [ -n "$dir" ] || return 0
  _BR_HB_SEQ=$(( ${_BR_HB_SEQ:-0} + 1 ))
  name="${name:0:60}"
  _BR_HB_FILE="$dir/${name:-run}-${BASHPID:-$$}-$_BR_HB_SEQ.hb"
  { [ -d "$dir" ] || mkdir -p "$dir"; } 2>/dev/null || :
  find "$dir" -maxdepth 1 -type f -name '*.hb' -mtime +"${BOUNDED_RUN_HB_RETAIN_DAYS:-7}" -delete 2>/dev/null || :
  { printf 'bounded-run %s deadline=%ss\n' "$1" "$2" > "$_BR_HB_FILE"; } 2>/dev/null || :
  local sha; sha="$(shift 2; _bounded_run_cmd_sha "$@")"
  [ -z "$sha" ] || { printf 'cmd sha256=%s\n' "$sha" >> "$_BR_HB_FILE"; } 2>/dev/null || :
}

# sha256 of the arguments, each NUL-terminated; "" without sha256sum or shasum (a reader then uses the label).
_bounded_run_cmd_sha() {
  local out=""
  if command -v sha256sum >/dev/null 2>&1; then out="$(printf '%s\0' "$@" | sha256sum 2>/dev/null)"
  elif command -v shasum >/dev/null 2>&1; then out="$(printf '%s\0' "$@" | shasum -a 256 2>/dev/null)"
  fi
  out="${out%% *}"
  case "$out" in *[!0-9a-f]*|"") out="" ;; esac
  [ "${#out}" -eq 64 ] && printf '%s' "$out"
  return 0
}

_bounded_run_hb_note() {
  [ -n "$1" ] || return 0
  { printf '%s\n' "$2" >> "$1"; } 2>/dev/null || :
}

# Heartbeat loop: print one progress line per interval until the (deadline + a small
# grace) cap, then exit. Capped so a parent that vanished without reaping us still
# self-terminates instead of becoming the very orphan this rule warns against.
_bounded_run_heartbeat() {
  local interval="$1" deadline="$2" label="$3" hbf="${4:-}"
  local waited=0 cap=$((deadline + 5))
  while [ "$waited" -lt "$cap" ]; do
    sleep "$interval"
    waited=$((waited + interval))
    echo "bounded-run: still running (${waited}s/${deadline}s) — $label" >&2
    _bounded_run_hb_note "$hbf" "running ${waited}/${deadline}"
  done
}

# bounded_wait PATH ERE [CAP_SECS=230] — rc 0 match · 124 cap reached · 2 refused (bad bound, CAP >= TTL, invalid ERE).
# TRIPWIRE: CAP stays under the 300 s sub-agent cache TTL (T123); the issuing tool call needs a timeout >= 240 s.
# TRIPWIRE: no kill, no ffhc_*, no pipe into grep (backlog bounded-run-waits-unbounded-after-reap, pipefail-grep-q-sigpipe-race).
bounded_wait() {
  local path="${1:-}" pat="${2:-}" cap="${3:-230}"
  local poll="${BOUNDED_WAIT_POLL_SECS:-15}" ttl="${BOUNDED_WAIT_TTL_SECS:-300}"
  local v grc=0 start="$SECONDS" end left s b0 b1 state
  if [ -z "$path" ] || [ -z "$pat" ]; then
    echo "bounded-wait: refused — usage: bounded_wait PATH ERE [CAP_SECS]" >&2; return 2
  fi
  for v in "$cap" "$poll" "$ttl"; do
    case "$v" in
      ''|0*|*[!0-9]*) echo "bounded-wait: refused — bound '$v' is not a positive integer" >&2; return 2 ;;
    esac
    [ "${#v}" -le 6 ] || { echo "bounded-wait: refused — bound '$v' is too large" >&2; return 2; }
  done
  if [ "$cap" -ge "$ttl" ]; then
    echo "bounded-wait: refused — cap ${cap}s must stay under the ${ttl}s cache TTL" >&2; return 2
  fi
  grep -qE -- "$pat" /dev/null 2>/dev/null || grc=$?
  if [ "$grc" -eq 2 ]; then
    echo "bounded-wait: refused — invalid ERE: $pat" >&2; return 2
  fi
  b0="$(_bounded_wait_bytes "$path")"
  end=$((start + cap))
  while :; do
    if [ -f "$path" ] && grep -qE -- "$pat" "$path" 2>/dev/null; then
      b1="$(_bounded_wait_bytes "$path")"
      echo "bounded-wait: matched — $path ($((SECONDS - start))s, $b1 bytes, growth $((b1 - b0)))" >&2
      return 0
    fi
    left=$((end - SECONDS))
    [ "$left" -gt 0 ] || break
    s="$poll"; [ "$s" -le "$left" ] || s="$left"
    sleep "$s"
  done
  b1="$(_bounded_wait_bytes "$path")"
  if [ -f "$path" ]; then state="$b1 bytes, growth $((b1 - b0))"
  elif [ -e "$path" ]; then state="not a regular file"
  else state="absent"; fi
  echo "bounded-wait: TIMEOUT after ${cap}s — $path ($state)" >&2
  return 124
}

# TRIPWIRE: regular files only — `wc -c <` (like grep) blocks forever on a FIFO.
_bounded_wait_bytes() {
  local n=""
  if [ -f "$1" ]; then n="$(wc -c < "$1" 2>/dev/null)"; fi
  printf '%s' "$(( ${n:-0} + 0 ))"
}
