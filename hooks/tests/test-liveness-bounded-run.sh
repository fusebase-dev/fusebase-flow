#!/usr/bin/env bash
# Fusebase Flow — liveness-discipline bounded-run tests (FR-27).
# Spec: docs/specs/liveness-discipline/spec.md (AC3 a-e, AC4, AC6). Skill:
# flow-skills/liveness-discipline. Tooling: hooks/local/lib/bounded-run.sh.
#
# The load-bearing check (spec § Risks "attestation theatre / inert lever"): the
# bounded-run tooling must GENUINELY terminate a hang. AC3a/d run a real hanging /
# SIGTERM-ignoring child against a short deadline and assert the terminal timeout
# line + rc 124/137 — not a presence-of-a-signal check. Genuine, loud asserts.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: liveness <name>" / "FAIL: liveness <name>"; exit code = failure count.

set -uo pipefail

core_only=0
case "$#" in
  0) ;;
  1)
    if [ "$1" = "--core-only" ]; then
      core_only=1
    else
      echo "[test-liveness-bounded-run] ERROR: unknown mode '$1' (expected --core-only)" >&2
      exit 2
    fi
    ;;
  *)
    echo "[test-liveness-bounded-run] ERROR: expected no arguments or --core-only" >&2
    exit 2
    ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
LIB="$ROOT/hooks/local/lib/bounded-run.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: liveness $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: liveness $1 (${2:-})"; }
finish() {
  if [ "$core_only" -eq 1 ]; then
    echo "[test-liveness-bounded-run] $pass/$((pass + fail)) PASS (CORE-ONLY — partial, non-attesting)"
  else
    echo "[test-liveness-bounded-run] $pass/$((pass + fail)) PASS"
  fi
  exit $fail
}

# Loud precondition: a missing lib must FAIL, never false-green.
[ -f "$LIB" ] || { bad "setup-lib-present" "missing $LIB"; finish; }
ok "setup-lib-present"

# bash -n on the lib (syntax gate; a broken lib must not silently pass downstream).
if bash -n "$LIB" 2>/dev/null; then ok "lib-syntax-clean"; else bad "lib-syntax-clean" "bash -n failed"; fi

# TRIPWIRE: test-ff-only's stub lib defines only bounded_run and pins exactly 3 calls — every
# bounded_wait / heartbeat-file row (and the 4th, relative-source call) runs only when have_bw=1.
have_bw=0
( set +u; . "$LIB" >/dev/null 2>&1; type bounded_wait >/dev/null 2>&1 ) && have_bw=1
if [ "$have_bw" -eq 0 ] && grep -q '^bounded_wait()' "$LIB"; then
  bad "bounded-wait-sourced" "the lib text defines bounded_wait but sourcing it did not"
fi
skip_row() { ok "$1 [SKIP — sourced lib defines no bounded_wait]"; }
HBT="$(mktemp -d "${TMPDIR:-/tmp}/ff-liveness-hb.XXXXXX" 2>/dev/null)" || { bad "setup-hb-tmpdir" "mktemp -d failed"; finish; }
trap 'rm -rf "$HBT"' EXIT
: > "$HBT/t0"

# Run a bounded_run call in a clean subshell; echo "RC=<rc>" + stderr (the wrapper
# logs heartbeats + the terminal line to stderr).
run_bounded() { # run_bounded <env-assignments> <deadline> <label> -- <cmd...> ; prints stderr then RC=<rc>
  local env_assign="$1"; shift
  local capture out rc
  capture="$(mktemp "${TMPDIR:-/tmp}/ff-liveness-bounded.$$.XXXXXX" 2>/dev/null)" || {
    printf 'bounded-run helper capture setup failed\nRC=125\n'
    return 0
  }
  env $env_assign bash -c '
    source "'"$LIB"'"
    bounded_run "$@"
  ' _ "$@" 2>"$capture" >/dev/null
  rc=$?
  out="$(<"$capture")"
  rm -f "$capture"
  printf '%s\nRC=%s\n' "$out" "$rc"
}

###############################################################################
# AC3a — a deliberately-hanging command terminates with a timeout line within the
# deadline (rc 124 or 137). The silent-unbounded-wait is structurally bounded.
###############################################################################
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  HB_A="$HBT/a"; mkdir -p "$HB_A" && touch -t 202001010000 "$HB_A/stale-1-1.hb"
  start=$(date +%s)
  a_out="$(BOUNDED_RUN_HB_DIR="$HB_A" run_bounded "BOUNDED_RUN_HEARTBEAT_SECS=1" 2 "hang probe" -- sleep 30)"
  end=$(date +%s); span=$((end - start))
  a_rc="$(echo "$a_out" | sed -n 's/^RC=//p' | tail -1)"
  # rc must be timeout-induced (124 deadline, or 137 SIGKILL after -k grace).
  if [ "$a_rc" = "124" ] || [ "$a_rc" = "137" ]; then ok "ac3a-hang-rc-124-or-137"; else bad "ac3a-hang-rc-124-or-137" "rc=$a_rc (sleep 30 not bounded!)"; fi
  # Terminal timeout line present (the job reached death, not a silent idle).
  echo "$a_out" | grep -q "bounded-run: TIMEOUT" && ok "ac3a-terminal-timeout-line" || bad "ac3a-terminal-timeout-line" "no terminal TIMEOUT line: $a_out"
  # Bounded within a sane window (deadline 2s + the -k grace 5s + heartbeat-cap slack).
  if [ "$span" -le 20 ]; then ok "ac3a-bounded-within-deadline"; else bad "ac3a-bounded-within-deadline" "took ${span}s (deadline was 2s)"; fi
  ###############################################################################
  # AC3b — incremental progress is emitted (heartbeat line) while CMD runs.
  ###############################################################################
  echo "$a_out" | grep -q "bounded-run: still running" && ok "ac3b-incremental-progress" || bad "ac3b-incremental-progress" "no heartbeat line in: $a_out"
  if [ "$have_bw" -eq 1 ]; then
    hb_files=( "$HB_A"/*.hb ); hb_a="${hb_files[0]}"
    if [ "${#hb_files[@]}" -eq 1 ] && [ -f "$hb_a" ] && case "${hb_a##*/}" in hang-probe-*-1.hb) true ;; *) false ;; esac; then
      ok "hb-one-file-per-call-and-stale-pruned"
    else
      bad "hb-one-file-per-call-and-stale-pruned" "files: ${hb_files[*]}"
    fi
    [ "$(head -n 1 "$hb_a" 2>/dev/null)" = "bounded-run hang probe deadline=2s" ] \
      && ok "hb-header-label-and-deadline" || bad "hb-header-label-and-deadline" "$(head -n 1 "$hb_a" 2>/dev/null)"
    grep -qE '^running [0-9]+/2$' "$hb_a" 2>/dev/null \
      && ok "hb-advances-while-running" || bad "hb-advances-while-running" "$(cat "$hb_a" 2>/dev/null)"
    case "$(tail -n 1 "$hb_a" 2>/dev/null)" in
      "TIMEOUT rc=124"|"TIMEOUT rc=137") ok "hb-terminal-record-last" ;;
      *) bad "hb-terminal-record-last" "$(cat "$hb_a" 2>/dev/null)" ;;
    esac
  else
    for r in hb-one-file-per-call-and-stale-pruned hb-header-label-and-deadline hb-advances-while-running hb-terminal-record-last; do skip_row "$r"; done
  fi
  ###############################################################################
  # AC3d — an ignored-SIGTERM child is still killed by run_with_timeout's -k
  # SIGKILL grace => rc 137. The child traps TERM and keeps sleeping.
  ###############################################################################
  d_out="$(BOUNDED_RUN_HB_DIR= run_bounded "FFHC_TIMEOUT_KILL_GRACE=1s BOUNDED_RUN_HEARTBEAT_SECS=10" 1 "stubborn child" -- bash -c 'trap "" TERM; sleep 30')"
  d_rc="$(echo "$d_out" | sed -n 's/^RC=//p' | tail -1)"
  if [ "$d_rc" = "137" ]; then ok "ac3d-ignored-sigterm-sigkilled"; else bad "ac3d-ignored-sigterm-sigkilled" "rc=$d_rc (expected 137 — the -k SIGKILL grace did not fire)"; fi
else
  # No timeout binary on this host: AC3a/b/d cannot run the bounded path. Record a
  # visible SKIP (not a silent pass) — but AC3c below STILL asserts the degrade
  # policy, which is exactly the no-binary case.
  echo "PASS: liveness ac3a-skipped-no-timeout-binary (host lacks timeout/gtimeout; AC3c covers degrade)"; pass=$((pass + 1))
fi

###############################################################################
# AC3c — no-timeout-binary path degrades per the skip policy (NOT a false
# "bounded"): the wrapper SKIPs (sentinel rc 125), the command does NOT run, and
# a marker file proves non-execution. Forced via FFHC_FORCE_NO_TIMEOUT=1.
###############################################################################
MARK="${TMPDIR:-/tmp}/fusebase-flow-liveness-mark.$$"
rm -f "$MARK"
c_out="$(BOUNDED_RUN_HB_DIR="$HBT/c" run_bounded "FFHC_FORCE_NO_TIMEOUT=1" 2 "degrade" -- touch "$MARK")"
c_rc="$(echo "$c_out" | sed -n 's/^RC=//p' | tail -1)"
if [ "$c_rc" = "125" ]; then ok "ac3c-no-binary-skip-rc-125"; else bad "ac3c-no-binary-skip-rc-125" "rc=$c_rc (expected 125 sentinel)"; fi
# The command MUST NOT have run (no false "bounded" that silently executes unbounded).
if [ ! -e "$MARK" ]; then ok "ac3c-no-binary-command-not-run"; else bad "ac3c-no-binary-command-not-run" "command ran despite no-binary skip (false bounded!)"; rm -f "$MARK"; fi
echo "$c_out" | grep -q "bounded-run: SKIPPED" && ok "ac3c-skip-marker-line" || bad "ac3c-skip-marker-line" "no SKIPPED line: $c_out"

###############################################################################
# Heartbeat file (A3.5, decision D). TRIPWIRE: AC3a/AC3c point BOUNDED_RUN_HB_DIR at $HBT and
# AC3d sets it empty, so no row writes the live tree's state/.
###############################################################################
if [ "$have_bw" -eq 1 ]; then
  hb_c=( "$HBT/c"/degrade-*-1.hb )
  if [ -f "${hb_c[0]}" ] && [ "$(head -n 1 "${hb_c[0]}")" = "bounded-run degrade deadline=2s" ] \
     && [ "$(tail -n 1 "${hb_c[0]}")" = "SKIPPED" ]; then
    ok "hb-skip-path-records-skipped"
  else
    bad "hb-skip-path-records-skipped" "files: ${hb_c[*]}"
  fi
  RR="$HBT/rel root"
  mkdir -p "$RR/hooks/local/lib" "$RR/sub" \
    && cp "$ROOT/hooks/local/lib/bounded-run.sh" "$ROOT/hooks/local/lib/run-with-timeout.sh" "$RR/hooks/local/lib/" \
    && : > "$HBT/t-rel"
  ( cd "$RR" && unset BOUNDED_RUN_HB_DIR && set +u && . hooks/local/lib/bounded-run.sh && cd sub \
    && BOUNDED_RUN_HEARTBEAT_SECS=0 bounded_run 5 "rel probe" -- true ) >/dev/null 2>&1
  rel_new="$(find "$RR" -type f -newer "$HBT/t-rel" 2>/dev/null)"
  case "$rel_new" in
    *$'\n'*) bad "hb-relative-source-then-cd-writes-only-under-root-liveness" "more than one new file: [$rel_new]" ;;
    "$RR/state/audit/liveness/rel-probe-"*-1.hb)
      case "$(tail -n 1 "$rel_new")" in
        "done rc=0 "*s|SKIPPED) ok "hb-relative-source-then-cd-writes-only-under-root-liveness" ;;
        *) bad "hb-relative-source-then-cd-writes-only-under-root-liveness" "record: $(cat "$rel_new")" ;;
      esac ;;
    *) bad "hb-relative-source-then-cd-writes-only-under-root-liveness" "new files: [$rel_new]" ;;
  esac
  # TRIPWIRE: match only this suite's labels — an outer bounded_run wrapping this suite heartbeats into the same dir.
  live_new="$(find "$ROOT/state/audit/liveness" -maxdepth 1 \( -name 'hang-probe-*.hb' -o -name 'stubborn-child-*.hb' \
    -o -name 'degrade-*.hb' -o -name 'rel-probe-*.hb' \) -newer "$HBT/t0" 2>/dev/null)"
  [ -z "$live_new" ] && ok "hb-suite-writes-nothing-under-live-state" \
    || bad "hb-suite-writes-nothing-under-live-state" "$live_new"
else
  for r in hb-skip-path-records-skipped hb-relative-source-then-cd-writes-only-under-root-liveness hb-suite-writes-nothing-under-live-state; do skip_row "$r"; done
fi

###############################################################################
# bounded_wait (A10): self-bounding poll on one regular file; never calls bounded_run.
###############################################################################
run_wait() { # run_wait <cap> <path> <ere>: stderr -> $HBT/err; rc = bounded_wait's
  rm -f "$HBT/ready"
  ( set +u; . "$LIB" >/dev/null 2>&1; : > "$HBT/ready"; bounded_wait "$2" "$3" "$1" ) 2>"$HBT/err"
}
if [ "$have_bw" -eq 1 ]; then
  # TRIPWIRE: the append waits for bounded_wait's 2nd grep (its first poll, after it read the start
  # size) — a timed sleep races the start-size read on a loaded MSYS host and reports growth 0.
  mkdir -p "$HBT/gshim" && printf '#!/bin/sh\n[ -e "%s" ] && echo x >> "%s"\nexec "%s" "$@"\n' \
    "$HBT/ready" "$HBT/grep-calls" "$(command -v grep)" > "$HBT/gshim/grep" && chmod +x "$HBT/gshim/grep"
  printf 'started\n' > "$HBT/log"
  ( i=0; while [ "$(cat "$HBT/grep-calls" 2>/dev/null | wc -l)" -lt 2 ] && [ "$i" -lt 120 ]; do sleep 1; i=$((i + 1)); done
    printf 'DONE\n' >> "$HBT/log" ) & bw_writer=$!
  PATH="$HBT/gshim:$PATH" BOUNDED_WAIT_POLL_SECS=1 run_wait 120 "$HBT/log" '^DONE$'; w_rc=$?
  wait "$bw_writer" 2>/dev/null
  if [ "$w_rc" -eq 0 ] && grep -q "bounded-wait: matched — .*(.*s, 13 bytes, growth 5)" "$HBT/err"; then
    ok "bounded-wait-match-rc-0-reports-bytes-and-growth"
  else
    bad "bounded-wait-match-rc-0-reports-bytes-and-growth" "rc=$w_rc $(cat "$HBT/err")"
  fi

  printf 'running\n' > "$HBT/quiet"
  w_start=$(date +%s)
  BOUNDED_WAIT_POLL_SECS=120 run_wait 2 "$HBT/quiet" '^DONE$'; w_rc=$?
  w_span=$(( $(date +%s) - w_start ))
  if [ "$w_rc" -eq 124 ] && [ "$w_span" -le 60 ] \
     && grep -q "bounded-wait: TIMEOUT after 2s — .*(8 bytes, growth 0)" "$HBT/err"; then
    ok "bounded-wait-no-match-rc-124-poll-clamped-to-cap"
  else
    bad "bounded-wait-no-match-rc-124-poll-clamped-to-cap" "rc=$w_rc ${w_span}s $(cat "$HBT/err")"
  fi

  mkdir -p "$HBT/shim" && printf '#!/bin/sh\nexit 125\n' > "$HBT/shim/timeout" && cp "$HBT/shim/timeout" "$HBT/shim/gtimeout" \
    && chmod +x "$HBT/shim/timeout" "$HBT/shim/gtimeout"
  PATH="$HBT/shim:$PATH" FFHC_FORCE_NO_TIMEOUT=1 BOUNDED_WAIT_POLL_SECS=1 run_wait 2 "$HBT/absent" 'x'; w_rc=$?
  [ "$w_rc" -eq 124 ] && ok "bounded-wait-no-timeout-binary-still-bounded" \
    || bad "bounded-wait-no-timeout-binary-still-bounded" "rc=$w_rc (125 = it depended on a timeout binary)"
  grep -q "bounded-wait: TIMEOUT after 2s — .*(absent)" "$HBT/err" && ok "bounded-wait-absent-path-is-not-yet" \
    || bad "bounded-wait-absent-path-is-not-yet" "$(cat "$HBT/err")"

  mkfifo "$HBT/fifo" 2>/dev/null || mkdir -p "$HBT/fifo"
  BOUNDED_WAIT_POLL_SECS=1 run_wait 2 "$HBT/fifo" 'x'; w_rc=$?
  [ "$w_rc" -eq 124 ] && grep -q "(not a regular file)" "$HBT/err" && ok "bounded-wait-non-regular-path-never-read" \
    || bad "bounded-wait-non-regular-path-never-read" "rc=$w_rc $(cat "$HBT/err")"

  run_wait 300 "$HBT/log" 'x'; w_rc=$?
  [ "$w_rc" -eq 2 ] && grep -q "must stay under the 300s cache TTL" "$HBT/err" \
    && ok "bounded-wait-cap-at-ttl-refused-rc-2" || bad "bounded-wait-cap-at-ttl-refused-rc-2" "rc=$w_rc $(cat "$HBT/err")"
  run_wait 2 "$HBT/log" '('; w_rc=$?
  [ "$w_rc" -eq 2 ] && grep -q "invalid ERE" "$HBT/err" \
    && ok "bounded-wait-invalid-ere-refused-rc-2" || bad "bounded-wait-invalid-ere-refused-rc-2" "rc=$w_rc $(cat "$HBT/err")"
  BOUNDED_WAIT_POLL_SECS=0 run_wait 2 "$HBT/log" 'x'; w_rc=$?
  [ "$w_rc" -eq 2 ] && grep -q "not a positive integer" "$HBT/err" \
    && ok "bounded-wait-non-positive-bound-refused-rc-2" || bad "bounded-wait-non-positive-bound-refused-rc-2" "rc=$w_rc $(cat "$HBT/err")"
  run_wait 2 "" 'x'; w_rc=$?
  [ "$w_rc" -eq 2 ] && ok "bounded-wait-missing-argument-refused-rc-2" \
    || bad "bounded-wait-missing-argument-refused-rc-2" "rc=$w_rc $(cat "$HBT/err")"
else
  for r in bounded-wait-match-rc-0-reports-bytes-and-growth bounded-wait-no-match-rc-124-poll-clamped-to-cap \
           bounded-wait-no-timeout-binary-still-bounded bounded-wait-absent-path-is-not-yet \
           bounded-wait-non-regular-path-never-read bounded-wait-cap-at-ttl-refused-rc-2 \
           bounded-wait-invalid-ere-refused-rc-2 bounded-wait-non-positive-bound-refused-rc-2 \
           bounded-wait-missing-argument-refused-rc-2; do skip_row "$r"; done
fi

###############################################################################
# AC3e / AC6 — FFHC API intact + no regression: the existing health-check timeout
# suite (which sources run-with-timeout.sh and exercises the ffhc_* API) still
# passes. bounded-run.sh reuses that core; if it broke the API the suite fails.
###############################################################################
if [ "$core_only" -eq 1 ]; then
  echo "[test-liveness-bounded-run] CORE-ONLY: health-check-timeout dependency omitted; partial, non-attesting" >&2
elif [ -f "$ROOT/hooks/tests/test-health-check-timeout.sh" ]; then
  ht_out="$(bash "$ROOT/hooks/tests/test-health-check-timeout.sh" 2>&1)"; ht_rc=$?
  ht_failed="$(echo "$ht_out" | grep -c '^FAIL: health-check-timeout')"
  if [ "$ht_rc" -eq 0 ] && [ "$ht_failed" -eq 0 ]; then
    ok "ac6-health-check-timeout-no-regression"
  else
    bad "ac6-health-check-timeout-no-regression" "health-check timeout suite failed ($ht_failed FAIL, rc $ht_rc) — ffhc_* API regressed?"
  fi
else
  bad "ac6-health-check-timeout-no-regression" "test-health-check-timeout.sh missing (cannot prove AC6)"
fi
# Direct FFHC API surface check: sourcing run-with-timeout.sh still defines the
# functions the health-check engine calls directly (the API contract, FR-07).
api_check="$(bash -c '
  source "'"$ROOT"'/hooks/local/lib/run-with-timeout.sh"
  for fn in ffhc_detect_timeout ffhc_timed_out run_with_timeout ffhc_run_bounded \
            ffhc_run_tests_pass_ok ffhc_count_pass_lines ffhc_select_pass_line \
            ffhc_pass_line_broken_msg; do
    type "$fn" >/dev/null 2>&1 || { echo "MISSING:$fn"; exit 1; }
  done
  echo OK
' 2>&1)"
[ "$api_check" = "OK" ] && ok "ac6-ffhc-api-functions-present" || bad "ac6-ffhc-api-functions-present" "$api_check"

###############################################################################
# AC4 — the implement-handoff template carries the liveness clause in the
# Role-bootstrap HARD-INVARIANTS, not only the Tracks section. Assert the FR-27
# clause appears in the "Hard invariants" paragraph (the prose between that bold
# label and the next "## " or "**Refusal" boundary), and ALSO guard against a
# false-pass where it ONLY lives in the Tracks section.
###############################################################################
IMPL="$ROOT/templates/handoff-implement.md"
if [ -f "$IMPL" ]; then
  # Extract the Hard-invariants region: the paragraph starting at "**Hard invariants**"
  # up to the next blank-line-delimited "---" separator (the role-bootstrap block).
  hard_region="$(awk '/\*\*Hard invariants\*\*/{f=1} f{print} /^## Mandatory pre-execution reads/{f=0}' "$IMPL")"
  if echo "$hard_region" | grep -qi "FR-27" && echo "$hard_region" | grep -qi "liveness"; then
    ok "ac4-liveness-in-hard-invariants"
  else
    bad "ac4-liveness-in-hard-invariants" "FR-27/liveness clause absent from the Role-bootstrap Hard-invariants region"
  fi
  # Bite-check: the assertion is meaningful only if the Hard-invariants region was
  # actually extracted (non-empty) and is NOT the whole file (which would let a
  # Tracks-only mention pass). The region must be smaller than the full file.
  full_lines="$(wc -l < "$IMPL")"; region_lines="$(echo "$hard_region" | wc -l)"
  if [ -n "$hard_region" ] && [ "$region_lines" -lt "$full_lines" ]; then
    ok "ac4-hard-region-bounded"
  else
    bad "ac4-hard-region-bounded" "Hard-invariants region empty or unbounded (extraction wrong; assertion would not bite)"
  fi
else
  bad "ac4-liveness-in-hard-invariants" "templates/handoff-implement.md missing"
fi

###############################################################################
# F3 (v3.30.6) — adaptive reap-loop poll. The reap loop now naps sub-second
# (spawn-free) instead of a hard `sleep 1`/iteration, BUT the deadline stays a
# hard FLOOR: a bounded op must NOT reap EARLY (before GNU timeout's own TERM at
# `secs`). These asserts drive ffhc_run_bounded directly against run-with-timeout.sh.
###############################################################################
RWT="$ROOT/hooks/local/lib/run-with-timeout.sh"
if [ -f "$RWT" ]; then
  # Probe the primitive in a subshell so the module fd doesn't leak into this suite.
  nap_ok="$(bash -c 'source "'"$RWT"'"; echo "${FFHC_NAP_OK:-0}"' 2>/dev/null)"
  if [ "$nap_ok" = "1" ]; then ok "f3-nap-primitive-probed-usable (FFHC_NAP_OK=1 on this host)"; else
    ok "f3-nap-primitive-unavailable-fallback-used (FFHC_NAP_OK=0 => literal sleep-1 fallback; no regression)"; fi

  if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    # (1) FAST child completes under its LARGE budget with its OWN rc — the reap loop must
    # NOT block for the whole 600s budget (a 1s-per-iteration sleep floor is gone; the nap
    # ladder polls sub-second). The load-bearing deterministic assert is: own rc preserved
    # AND wall NOT anywhere near the 600s budget. Absolute wall is host-startup-dominated
    # under saturation, so the ceiling is a generous "not the budget" bound (30s), not a
    # tight one — the point is "doesn't block for secs", not a microbenchmark.
    f_start=$(date +%s)
    bash -c 'source "'"$RWT"'"; ffhc_detect_timeout; ffhc_run_bounded 600 bash -c "exit 0"; exit $FFHC_LAST_RC' >/dev/null 2>&1; f_rc=$?
    f_end=$(date +%s); f_wall=$((f_end - f_start))
    if [ "$f_rc" -eq 0 ] && [ "$f_wall" -lt 30 ]; then
      ok "f3-fast-child-returns-well-under-budget (${f_wall}s wall for a 600s-budget instant child, own rc=0 — reap loop did not block for the budget; nap ladder, not a 1s sleep floor)"
    else
      bad "f3-fast-child-returns-well-under-budget" "took ${f_wall}s rc=$f_rc (expected own rc 0 + wall well under the 600s budget)"
    fi

    # (2) NO-EARLY-REAP FLOOR + BOUNDED-REAP CEILING: a hang-child (sleep 60) bounded at 2
    # must return a timeout-induced rc (124/137) with wall in [FLOOR, CEILING].
    #   FLOOR   = deadline (2s): the deadline is a hard floor — a bounded op must NEVER reap
    #             EARLY (before GNU timeout's own TERM at `secs`). Critical safety property.
    #   CEILING = deadline(2) + grace(5) + a DOCUMENTED host-jitter margin. cap = 7s; the
    #             regression this must catch is "child never killed / reap TENS-of-seconds
    #             late", NOT the legitimate few-seconds-late reap on a saturated host.
    #             Measured on a heavily-saturated host the reap lands 10-25s wall (rc 124/137,
    #             child genuinely killed — never near its 60s completion). CEILING=45s gives
    #             ~20s headroom over the worst measured jitter (non-flaky) while sitting well
    #             below the 60s never-killed completion, so a gross late-reap / never-killed
    #             regression FAILs (a rc=0 sleep-completion also FAILs the rc classifier).
    #             sleep 60 (not 30) is deliberate: it separates the ~10-25s legit reap window
    #             from the never-killed signature by a wide margin. TRIPWIRE: keep BOTH bounds
    #             — a floor-only assert lets a never-killed/late reap wrongly PASS (the exact
    #             hole this strengthens); do not widen CEILING to swallow a 60s never-kill.
    export FFHC_TIMEOUT_KILL_GRACE=5s
    F3_REAP_CEILING=45
    h_start=$(date +%s)
    h_rc="$(bash -c 'source "'"$RWT"'"; ffhc_detect_timeout; ffhc_run_bounded 2 bash -c "sleep 60"; echo $FFHC_LAST_RC' 2>/dev/null | tail -1)"
    h_end=$(date +%s); h_wall=$((h_end - h_start))
    if { [ "$h_rc" = "124" ] || [ "$h_rc" = "137" ]; } && [ "$h_wall" -ge 2 ] && [ "$h_wall" -le "$F3_REAP_CEILING" ]; then
      ok "f3-no-early-reap-bounded (hang-child bounded at 2s => timeout rc=$h_rc in ${h_wall}s: FLOOR >=2s honored AND CEILING <=${F3_REAP_CEILING}s — never reaped early, never a late/never-kill regression)"
    else
      bad "f3-no-early-reap-bounded" "hang-child bounded at 2s returned rc=$h_rc in ${h_wall}s (need timeout rc 124/137 AND 2s <= wall <= ${F3_REAP_CEILING}s — EARLY reap, non-timeout rc, or a gross late/never-kill reap is a behavior change)"
    fi

    # (3) FALLBACK path exercised: force FFHC_NAP_OK off => the loop takes the literal
    # `sleep 1; waited+=1` branch and STILL honors the deadline floor + timeout rc.
    fb_rc="$(bash -c 'source "'"$RWT"'"; ffhc_detect_timeout; FFHC_NAP_OK=0; ffhc_run_bounded 2 bash -c "sleep 30"; echo $FFHC_LAST_RC' 2>/dev/null | tail -1)"
    if [ "$fb_rc" = "124" ] || [ "$fb_rc" = "137" ]; then
      ok "f3-fallback-sleep1-path-still-bounds (FFHC_NAP_OK=0 => literal sleep-1 loop still returns timeout rc=$fb_rc — zero regression on the fallback)"
    else
      bad "f3-fallback-sleep1-path-still-bounds" "fallback loop returned rc=$fb_rc (expected timeout 124/137)"
    fi
  else
    ok "f3-fast-child-returns-well-under-budget [SKIP — no timeout binary]"
    ok "f3-no-early-reap-bounded [SKIP — no timeout binary]"
    ok "f3-fallback-sleep1-path-still-bounds [SKIP — no timeout binary]"
  fi

  # (4) mkfifo-unusable host => FFHC_NAP_OK must be 0 (probe rejects cleanly) => v3.30.5
  # sleep-1 fallback. Shadow mkfifo with a shim that FAILS (equivalent to mkfifo absent /
  # a filesystem that can't make FIFOs); everything else stays on the real PATH so the
  # probe's own mktemp works. The probe's `mkfifo … || return 0` guard must fire.
  STUB="$(mktemp -d)"
  printf '#!/bin/sh\nexit 1\n' > "$STUB/mkfifo"; chmod +x "$STUB/mkfifo"
  nofifo_ok="$(PATH="$STUB:$PATH" bash -c 'source "'"$RWT"'"; echo "${FFHC_NAP_OK:-x}"' 2>/dev/null | tail -1)"
  rm -rf "$STUB"
  if [ "$nofifo_ok" = "0" ]; then
    ok "f3-mkfifo-absent-forces-fallback (mkfifo unusable => FFHC_NAP_OK=0 => v3.30.5 sleep-1 behavior)"
  else
    bad "f3-mkfifo-absent-forces-fallback" "FFHC_NAP_OK=[$nofifo_ok] with mkfifo unusable (expected 0 — the probe must reject cleanly and fall back)"
  fi
else
  bad "f3-nap-primitive-probed-usable" "run-with-timeout.sh missing ($RWT)"
fi

finish
