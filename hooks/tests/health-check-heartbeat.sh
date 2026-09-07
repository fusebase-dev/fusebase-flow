#!/usr/bin/env bash
# Synchronized AC5 proof for the parent-owned heartbeat in run-with-timeout.sh.

AC5_CONTROLLER="$ROOT/hooks/tests/lib/heartbeat-probe.py"

_ac5_pid_alive() {
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

_ac5_live_proof() {
  [ "${AC5_STARTED:-no}" = "yes" ] &&
    [ "${AC5_COMPLETED:-no}" = "yes" ] &&
    [ "${AC5_EXITED:-no}" = "yes" ] &&
    [ "${AC5_DONE:-no}" = "yes" ] &&
    [ "${AC5_RELEASE_REASON:-}" = "two-heartbeats" ] &&
    [ "${AC5_PRE_RELEASE:-0}" -ge 2 ] 2>/dev/null
}

_ac5_start_case() { # <dir> <tag> <mode> <heartbeat-secs>
  local directory="$1" tag="$2" mode="$3" heartbeat="$4"
  FFHC_HEARTBEAT_SECS="$heartbeat" FFHC_HEARTBEAT_LABEL="ac5-$tag" \
    bash "$directory/probe.sh" "$ROOT" "$directory" "$tag" "$mode" \
    >"$directory/stdout.$tag" 2>"$directory/err.$tag" &
  AC5_PROBE_PID=$!
  python3 "$AC5_CONTROLLER" "$directory" "$tag" "$mode" \
    --evidence-deadline 8 --completion-deadline 30
  AC5_CONTROLLER_RC=$?
  wait "$AC5_PROBE_PID" 2>/dev/null
  AC5_PROBE_RC=$?
  # The controller writes shell-safe ASCII scalars only.
  # shellcheck disable=SC1090
  . "$directory/control.$tag"
}

_ac5_case_clean() { # <dir> <tag>
  local directory="$1" tag="$2" pid
  for pid_file in "$directory/probe-pid.$tag" "$directory/child-pid.$tag" "$directory/heartbeat-pid.$tag"; do
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    _ac5_pid_alive "$pid" && return 1
  done
  return 0
}

ht_ac5_heartbeat() {
  local timeout_bin
  timeout_bin="$(bash -c '. "$1/hooks/local/lib/run-with-timeout.sh"; ffhc_detect_timeout; printf "%s" "${FFHC_TIMEOUT_BIN:-}"' _ "$ROOT" 2>/dev/null || true)"
  if [ -z "$timeout_bin" ]; then
    ht_pass "ac5-heartbeat-before-child-exit [SKIP - no timeout binary; the capture path under test is unreachable]"
    return 0
  fi

  local directory; directory="$(mktemp -d "$TMP_BASE/ac5.XXXXXX")"
  cat >"$directory/child.sh" <<'AC5_CHILD'
#!/usr/bin/env bash
set -uo pipefail
directory="$1"; tag="$2"
trap ': >"$directory/exited.$tag"' EXIT
printf '%s' "$BASHPID" >"$directory/child-pid.$tag"
printf 'ac5-payload-line-1\n'
printf 'ac5-stderr-line\n' >&2
: >"$directory/started.$tag"
while [ ! -f "$directory/release.$tag" ]; do sleep 0.05; done
# Leave a real post-release window so the late-only negative can emit before child exit.
sleep 0.35
printf 'ac5-payload-line-2\n'
AC5_CHILD
  cat >"$directory/probe.sh" <<'AC5_PROBE'
#!/usr/bin/env bash
set -uo pipefail
root="$1"; directory="$2"; tag="$3"; mode="$4"
printf '%s' "$BASHPID" >"$directory/probe-pid.$tag"
. "$root/hooks/local/lib/run-with-timeout.sh"
ffhc_detect_timeout

# Test-only seams discriminate recurring live progress from one-shot and late emissions.
if [ "$mode" = "oneshot" ]; then
  _ffhc_heartbeat_loop() {
    while [ ! -f "$directory/started.$tag" ]; do sleep 0.05; done
    printf '[bounded] still running (%ss/%ss) — %s\n' "$1" "$2" "$3" >&2
    while [ ! -f "$directory/release.$tag" ]; do sleep 0.05; done
  }
elif [ "$mode" = "late" ]; then
  _ffhc_heartbeat_loop() {
    while [ ! -f "$directory/release.$tag" ]; do sleep 0.05; done
    printf '[bounded] still running (late/%ss) — %s\n' "$2" "$3" >&2
    sleep 1
  }
fi

# Record the real helper identity without changing its start/stop behavior.
eval "$(declare -f _ffhc_heartbeat_start | sed '1s/_ffhc_heartbeat_start/_ac5_real_heartbeat_start/')"
_ffhc_heartbeat_start() {
  _ac5_real_heartbeat_start "$@"
  printf '%s' "$FFHC_HEARTBEAT_HPID" >"$directory/heartbeat-pid.$tag"
}

ffhc_run_bounded 20 bash "$directory/child.sh" "$directory" "$tag"
[ "$mode" = "contaminate" ] && FFHC_LAST_OUT="$FFHC_LAST_OUT
[bounded] still running (contaminated capture)"
printf '%s' "$FFHC_LAST_OUT" >"$directory/out.$tag"
printf '%s' "$FFHC_LAST_RC" >"$directory/rc.$tag"
: >"$directory/done.$tag"
AC5_PROBE
  chmod +x "$directory/child.sh" "$directory/probe.sh"

  local failure="" live_payload="" off_payload="" leak_pid=""
  local positive_summary=""

  _ac5_start_case "$directory" live live 1
  _ac5_live_proof || failure="$failure [live controller did not observe two pre-release parent heartbeats]"
  [ "$AC5_CONTROLLER_RC" -eq 0 ] && [ "$AC5_PROBE_RC" -eq 0 ] \
    || failure="$failure [live controller/probe rc=$AC5_CONTROLLER_RC/$AC5_PROBE_RC]"
  [ "$(cat "$directory/rc.live" 2>/dev/null)" = "0" ] \
    || failure="$failure [bounded child rc was not preserved]"
  _ac5_case_clean "$directory" live || failure="$failure [live case left an owned process]"
  live_payload="$directory/out.live"
  positive_summary="started=$AC5_STARTED heartbeats=$AC5_PRE_RELEASE first=${AC5_FIRST_MS}ms second=${AC5_SECOND_MS}ms release=$AC5_RELEASE_REASON exited=$AC5_EXITED cleanup=yes elapsed=${AC5_ELAPSED_MS}ms"

  _ac5_start_case "$directory" off off 0
  [ "$AC5_PRE_RELEASE" -eq 0 ] && [ "$AC5_TOTAL" -eq 0 ] \
    || failure="$failure [heartbeat-off emitted progress]"
  _ac5_case_clean "$directory" off || failure="$failure [off case left an owned process]"
  off_payload="$directory/out.off"
  cmp -s "$live_payload" "$off_payload" \
    || failure="$failure [live capture differs from heartbeat-off capture]"
  grep -q 'ac5-stderr-line' "$live_payload" \
    || failure="$failure [merged child stderr is absent from capture]"
  grep -q '\[bounded\] still running' "$live_payload" \
    && failure="$failure [parent heartbeat leaked into captured payload]"

  _ac5_start_case "$directory" disabled disabled 0
  _ac5_live_proof && failure="$failure [disabled heartbeat passed recurring-live proof]"
  _ac5_case_clean "$directory" disabled || failure="$failure [disabled case left an owned process]"

  _ac5_start_case "$directory" oneshot oneshot 1
  [ "$AC5_PRE_RELEASE" -eq 1 ] \
    || failure="$failure [one-shot control emitted $AC5_PRE_RELEASE pre-release heartbeats, expected 1]"
  _ac5_live_proof && failure="$failure [one-shot heartbeat passed recurring-live proof]"
  _ac5_case_clean "$directory" oneshot || failure="$failure [one-shot case left an owned process]"

  _ac5_start_case "$directory" late late 1
  [ "$AC5_PRE_RELEASE" -eq 0 ] && [ "$AC5_TOTAL" -ge 1 ] \
    || failure="$failure [late-only control did not remain post-release]"
  _ac5_live_proof && failure="$failure [late-only heartbeat passed recurring-live proof]"
  _ac5_case_clean "$directory" late || failure="$failure [late case left an owned process]"

  _ac5_start_case "$directory" contaminate contaminate 1
  cmp -s "$live_payload" "$directory/out.contaminate" \
    && failure="$failure [capture-contamination control passed byte parity]"
  _ac5_case_clean "$directory" contaminate || failure="$failure [contamination case left an owned process]"

  sleep 20 & leak_pid=$!
  _ac5_pid_alive "$leak_pid" || failure="$failure [cleanup negative was not alive for discrimination]"
  kill "$leak_pid" 2>/dev/null; wait "$leak_pid" 2>/dev/null
  _ac5_pid_alive "$leak_pid" && failure="$failure [cleanup negative could not be reaped]"

  if [ -z "$failure" ]; then
    ht_pass "ac5-heartbeat-before-child-exit ($positive_summary; disabled/one-shot/late/capture/cleanup negatives rejected)"
  else
    ht_fail "ac5-heartbeat-before-child-exit" "$failure"
  fi
}

ht_ac5_optins() {
  local failure="" library="$ROOT/hooks/local/lib/run-with-timeout.sh" code
  code="$(grep -vE '^[[:space:]]*#' "$library" || true)"
  grep -q 'FFHC_HEARTBEAT_SECS' "$ROOT/hooks/tests/run-tests.sh" \
    || failure="$failure [run-tests.sh does not opt into the heartbeat]"
  grep -q 'FFHC_HEARTBEAT_SECS' "$ROOT/hooks/local/lib/hook-integrity-check.sh" \
    || failure="$failure [health deep run does not opt into the heartbeat]"
  grep -q '_ffhc_timeout_child_done "$_done" "$secs" "$@" >"$_tf"' "$library" \
    || failure="$failure [tempfile capture is gone]"
  printf '%s\n' "$code" | grep -qE '\|[[:space:]]*(tee|while[[:space:]]+read)' \
    && failure="$failure [tee/pipe capture reintroduced the MSYS inherited-pipe hang]"
  printf '%s\n' "$code" | grep -qE '(^|[^[:alnum:]_])(stdbuf|PYTHONUNBUFFERED)' \
    && failure="$failure [child-side unbuffering changed capture semantics]"
  printf '%s\n' "$code" | grep -qE '_hbpid="?\$\(' \
    && failure="$failure [heartbeat pid is captured through a blocking command substitution]"
  if [ -z "$failure" ]; then
    ht_pass "ac5-both-consumers-opt-in-and-capture-transport-unchanged"
  else
    ht_fail "ac5-both-consumers-opt-in-and-capture-transport-unchanged" "$failure"
  fi
}
