#!/usr/bin/env bash
# Fusebase Flow — S3A observability seam for hooks/tests/test-cli-flow-recovery.sh.
# WHY-home: docs/specs/backlog-triage-execution/execution-plan.md § S3A (+ P1, § 5 provenance).
#
# INSTRUMENTATION ONLY. This seam makes cost visible. It selects no optimization, reduces no
# fixture, consolidates no invocation, changes no timeout, and shares no mutable state between
# scenarios. Nothing here may ever alter what the harness asserts.
#
# It owns the result-reporting + timing responsibility that used to sit inline in the harness:
# pass() and fail() are defined HERE, print the SAME bytes they printed before, and additionally
# close a timed milestone. That is what lets the 954-line harness gain observability without
# gaining lines (FR-25 ratchet).
#
# TRIPWIRE - stdout is a parse contract. run-tests.sh counts ^PASS:/^FAIL: lines and a strict
# summary; ffhc_run_bounded_stdout DISCARDS this child's stderr. So: pass() writes exactly one
# stdout line, identical to the pre-seam bytes, and every trace/timing byte goes to the trace
# file and stderr. Never add a stdout write here.
#
# TRIPWIRE - no forks on the hot path. A Git-Bash process spawn costs ~1s on MSYS. A $( ) per
# event would add seconds to the very measurement this seam exists to take, so the clock, the
# scenario-id derivation, and the basename all use parameter expansion into globals instead of
# command substitution.
#
# Trace: state/audit/cli-flow-recovery-profiles/<full-head>/run-<utc>-<pid>.tsv
#   meta<TAB>key<TAB>value                                              (provenance header)
#   event<TAB>seq<TAB>name<TAB>scenario<TAB>start_ms<TAB>end_ms<TAB>duration_ms<TAB>result<TAB>script<TAB>label

FFCP_TRACE_FILE="${FFCP_TRACE_FILE:-}"
FFCP_TRACE_DIR=""
FFCP_SCRIPT=""
FFCP_SEQ=0
FFCP_LAST_MS=0
FFCP_RAW0_MS=0
FFCP_LAST_RAW_MS=0
FFCP_CLOCK=""
FFCP_NOW_MS=0
FFCP_SCENARIO_ID=""
FFCP_READY=0

# Provenance allowlist (execution-plan § 5). NAMES ONLY - the environment is never dumped, and
# no name outside this list is read or recorded.
FFCP_ENV_ALLOWLIST=(FF_ONLY FF_SKIP_CLI_RECOVERY FF_CLI_RECOVERY_TIMEOUT FF_PHASE_TIMEOUT \
  FFHC_TIMEOUT_KILL_GRACE FFHC_USE_JOB_OBJECT FFHC_HEARTBEAT_SECS)

# ffcp_clean <string>: collapse the field separators out of a value. Sets FFCP_CLEAN.
# A label carrying a TAB or newline would silently shift every column to its right.
ffcp_clean() {
  local s="$1"
  s="${s//$'\t'/ }"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  FFCP_CLEAN="$s"
}

# ffcp_raw_ms: current clock in ms into FFCP_NOW_MS. Fork-free on bash >= 5 (EPOCHREALTIME).
# HONESTY: this is a WALL clock, not a true monotonic source - bash exposes none. ffcp_now_ms
# clamps it non-decreasing, which is what the "monotonic" column actually guarantees.
ffcp_raw_ms() {
  if [ "$FFCP_CLOCK" = "epochrealtime" ]; then
    local er="${EPOCHREALTIME/,/.}"
    FFCP_NOW_MS=$(( ${er%%.*} * 1000 + 10#${er#*.} / 1000 ))
  elif [ "$FFCP_CLOCK" = "date-ns" ]; then
    local ns; ns="$(date +%s%N 2>/dev/null)"
    FFCP_NOW_MS=$(( 10#${ns:-0} / 1000000 ))
  else
    local s; s="$(date +%s 2>/dev/null)"
    FFCP_NOW_MS=$(( 10#${s:-0} * 1000 ))
  fi
}

# ffcp_now_ms: milliseconds since ffcp_init, clamped non-decreasing, into FFCP_NOW_MS.
ffcp_now_ms() {
  ffcp_raw_ms
  [ "$FFCP_NOW_MS" -lt "$FFCP_LAST_RAW_MS" ] && FFCP_NOW_MS="$FFCP_LAST_RAW_MS"
  FFCP_LAST_RAW_MS="$FFCP_NOW_MS"
  FFCP_NOW_MS=$(( FFCP_NOW_MS - FFCP_RAW0_MS ))
}

# ffcp_scenario_id <label>: leading "U20: ..." / "F3: ..." tag, else s<seq>. Sets FFCP_SCENARIO_ID.
ffcp_scenario_id() {
  local head="${1%%:*}"
  if [ "$head" != "$1" ] && [ -n "$head" ] && [ "${#head}" -le 24 ] && [ "${head//[!\ ]/}" = "" ]; then
    FFCP_SCENARIO_ID="$head"
  else
    FFCP_SCENARIO_ID="s$(( FFCP_SEQ + 1 ))"
  fi
}

ffcp_meta() { [ "$FFCP_READY" -eq 1 ] && printf 'meta\t%s\t%s\n' "$1" "$2" >> "$FFCP_TRACE_FILE"; return 0; }

# ffcp_init [script-basename]: resolve the trace target, write provenance, start the clock.
# Never fails the caller: if the trace target cannot be created, instrumentation goes quiet and
# the harness runs exactly as it did before (a profiler must not be able to red a gate).
ffcp_init() {
  FFCP_SCRIPT="${1:-${0##*/}}"
  if [ -n "${EPOCHREALTIME:-}" ]; then
    FFCP_CLOCK="epochrealtime"
  else
    # bash < 5: no EPOCHREALTIME. A `date` without %N support echoes a literal trailing N.
    local ns; ns="$(date +%s%N 2>/dev/null)"
    case "$ns" in *N|"") FFCP_CLOCK="date-s" ;; *) FFCP_CLOCK="date-ns" ;; esac
  fi

  local repo head dirty
  repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo unknown)"
  if git -C "$repo" diff --quiet HEAD 2>/dev/null; then dirty=0; else dirty=1; fi

  if [ -z "$FFCP_TRACE_FILE" ]; then
    FFCP_TRACE_DIR="${FFCP_TRACE_ROOT:-$repo/state/audit/cli-flow-recovery-profiles}/$head"
    mkdir -p "$FFCP_TRACE_DIR" 2>/dev/null || { FFCP_READY=0; return 0; }
    FFCP_TRACE_FILE="$FFCP_TRACE_DIR/run-$(date -u +%Y%m%dT%H%M%SZ)-$$.tsv"
  else
    FFCP_TRACE_DIR="${FFCP_TRACE_FILE%/*}"
    mkdir -p "$FFCP_TRACE_DIR" 2>/dev/null || { FFCP_READY=0; return 0; }
  fi
  : > "$FFCP_TRACE_FILE" 2>/dev/null || { FFCP_READY=0; return 0; }
  FFCP_READY=1

  ffcp_meta schema "fusebase-flow/cli-flow-recovery-profile/1"
  ffcp_meta head "$head"
  ffcp_meta head_dirty "$dirty"
  ffcp_meta platform "$(uname -s 2>/dev/null || echo unknown)/$(uname -m 2>/dev/null || echo unknown)"
  ffcp_meta shell "bash ${BASH_VERSION:-unknown}"
  ffcp_meta script "$FFCP_SCRIPT"
  ffcp_meta clock "$FFCP_CLOCK (wall clock, clamped non-decreasing; bash exposes no monotonic source)"
  ffcp_meta started_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local name val
  for name in "${FFCP_ENV_ALLOWLIST[@]}"; do
    val="${!name-}"
    if [ -z "${!name+x}" ]; then val="(default)"; else ffcp_clean "$val"; val="$FFCP_CLEAN"; fi
    ffcp_meta "env.$name" "$val"
  done

  ffcp_raw_ms; FFCP_RAW0_MS="$FFCP_NOW_MS"; FFCP_LAST_RAW_MS="$FFCP_NOW_MS"; FFCP_LAST_MS=0
  printf '[%s] profile trace: %s\n' "$FFCP_SCRIPT" "$FFCP_TRACE_FILE" >&2
  return 0
}

# ffcp_event <event-name> <scenario-id> <result> <invoked-script> [label]
# One row per completed milestone. start_ms is the previous milestone's end - i.e. the interval
# attributed to this scenario is everything the harness did since the last milestone. That is
# what the row measures; it is NOT a claim about which sub-command inside the interval was slow.
ffcp_event() {
  [ "$FFCP_READY" -eq 1 ] || return 0
  local ev="$1" sid="$2" result="$3" script="$4" label="${5:-}"
  ffcp_now_ms
  local start="$FFCP_LAST_MS" end="$FFCP_NOW_MS"
  local dur=$(( end - start ))
  [ "$dur" -lt 0 ] && dur=0
  FFCP_SEQ=$(( FFCP_SEQ + 1 ))
  FFCP_LAST_MS="$end"
  ffcp_clean "$label"; label="$FFCP_CLEAN"
  ffcp_clean "$sid";   sid="$FFCP_CLEAN"
  printf 'event\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$FFCP_SEQ" "$ev" "$sid" "$start" "$end" "$dur" "$result" "$script" "$label" \
    >> "$FFCP_TRACE_FILE"
  printf '[%s] %s %s %s %sms\n' "$FFCP_SCRIPT" "$ev" "$sid" "$result" "$dur" >&2
  return 0
}

# ffcp_substep <scenario-id> <invoked-script-basename> [label]: a named milestone INSIDE a
# scenario, attributing the interval to the script the harness just invoked.
ffcp_substep() { ffcp_event substep "$1" OK "$2" "${3:-}"; }

# pass / fail: the harness's result reporters. The stdout/stderr bytes and the exit behaviour
# are exactly what they were before this seam existed; the milestone row is the only addition.
pass() {
  ffcp_scenario_id "$*"
  ffcp_event scenario "$FFCP_SCENARIO_ID" PASS "$FFCP_SCRIPT" "$*"
  echo "[test-cli-flow-recovery] PASS: $*"
}

fail() {
  ffcp_scenario_id "$*"
  ffcp_event scenario "$FFCP_SCENARIO_ID" FAIL "$FFCP_SCRIPT" "$*"
  echo "[test-cli-flow-recovery] FAIL: $*" >&2
  exit 1
}
