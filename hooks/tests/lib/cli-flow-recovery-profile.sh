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
# no name outside this list is read or recorded. The two FFCP_TRACE_* entries are here because
# they CHANGE BEHAVIOUR (where the trace lands): an override with no provenance is the same
# blind spot as an unrecorded timeout.
FFCP_ENV_ALLOWLIST=(FF_ONLY FF_SKIP_CLI_RECOVERY FF_CLI_RECOVERY_TIMEOUT FF_PHASE_TIMEOUT \
  FFHC_TIMEOUT_KILL_GRACE FFHC_USE_JOB_OBJECT FFHC_HEARTBEAT_SECS \
  FFCP_TRACE_FILE FFCP_TRACE_ROOT)
FFCP_TRACE_OVERRIDE="(default)"

# ffcp_env_value NAME: the value SAFE to record. Sets FFCP_ENV_VALUE.
# TRIPWIRE: an allowlisted NAME is not a licence to record its VALUE. FF_ONLY is free text an
# operator types on a command line, so a secret pasted there was written to the trace verbatim.
# Only self-evidently non-secret shapes (a number, optionally with a unit suffix) are recorded
# as-is; everything else is reduced to a shape description. FFCP_TRACE_* record their DISPOSITION
# only - the raw value is a filesystem path, which § 5 excludes from the trace outright.
ffcp_env_value() {
  local name="$1" v
  if [ -z "${!name+x}" ]; then FFCP_ENV_VALUE="(default)"; return 0; fi
  case "$name" in FFCP_TRACE_FILE|FFCP_TRACE_ROOT) FFCP_ENV_VALUE="set ($FFCP_TRACE_OVERRIDE)"; return 0 ;; esac
  v="${!name}"
  case "$v" in
    '') FFCP_ENV_VALUE="set (empty)" ;;
    *[!0-9a-z]*|"") FFCP_ENV_VALUE="set (redacted; ${#v} chars)" ;;
    [0-9]*) FFCP_ENV_VALUE="$v" ;;
    *) FFCP_ENV_VALUE="set (redacted; ${#v} chars)" ;;
  esac
  return 0
}

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

# TRIPWIRE: a trace write may NEVER surface to the caller. The harness runs under `set -e`, so an
# unguarded append meant a full disk or a vanished trace dir aborted the run BEFORE its PASS/FAIL
# bytes - instrumentation deciding a verdict. A failed write disarms the seam for the rest of the
# run (FFCP_READY=0) and returns 0.
ffcp_write() {
  [ "$FFCP_READY" -eq 1 ] || return 0
  printf '%s\n' "$1" >> "$FFCP_TRACE_FILE" 2>/dev/null || FFCP_READY=0
  return 0
}
ffcp_meta() { ffcp_write "$(printf 'meta\t%s\t%s' "$1" "$2")"; return 0; }

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

  # CONTAINMENT: an ambient FFCP_TRACE_FILE / FFCP_TRACE_ROOT used to name ANY existing path,
  # which the `: >` below then TRUNCATED - a profiler able to destroy an arbitrary file. Both
  # overrides must resolve under the designated audit root; anything else (including any `..`
  # segment, which makes a prefix test meaningless) is REJECTED and the default is used. Rejection
  # is recorded in the provenance, never silent.
  local audit_root="$repo/state/audit"
  ffcp_contained() {   # ffcp_contained PATH -> 0 when safely under the audit root
    case "${1:-}" in
      *..*|'') return 1 ;;
      "$audit_root"/*) return 0 ;;
      *) return 1 ;;
    esac
  }
  if [ -n "$FFCP_TRACE_FILE" ] && ! ffcp_contained "$FFCP_TRACE_FILE"; then
    FFCP_TRACE_FILE=""; FFCP_TRACE_OVERRIDE="rejected: outside $repo/state/audit"
  elif [ -n "$FFCP_TRACE_FILE" ]; then
    FFCP_TRACE_OVERRIDE="accepted"
  fi
  local root="${FFCP_TRACE_ROOT:-}"
  if [ -n "$root" ] && ! ffcp_contained "$root"; then
    root=""; FFCP_TRACE_OVERRIDE="rejected: outside $repo/state/audit"
  elif [ -n "$root" ] && [ "$FFCP_TRACE_OVERRIDE" = "(default)" ]; then
    FFCP_TRACE_OVERRIDE="accepted"
  fi

  if [ -z "$FFCP_TRACE_FILE" ]; then
    FFCP_TRACE_DIR="${root:-$audit_root/cli-flow-recovery-profiles}/$head"
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
  local name
  for name in "${FFCP_ENV_ALLOWLIST[@]}"; do
    ffcp_env_value "$name"
    ffcp_clean "$FFCP_ENV_VALUE"
    ffcp_meta "env.$name" "$FFCP_CLEAN"
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
  ffcp_write "$(printf 'event\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$FFCP_SEQ" "$ev" "$sid" "$start" "$end" "$dur" "$result" "$script" "$label")"
  printf '[%s] %s %s %s %sms\n' "$FFCP_SCRIPT" "$ev" "$sid" "$result" "$dur" >&2 2>/dev/null || true
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
