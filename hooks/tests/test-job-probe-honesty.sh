#!/usr/bin/env bash
# Fusebase Flow — Job Object capability-probe HONESTY (backlog release-gate-flaky-job-probe).
#
# Extracted from test-msys-tree-cleanup.sh (FR-25 seam): that phase is MSYS-centric, while every
# row here is PLATFORM-INDEPENDENT — each drives _ffhc_job_probe_run / _ffhc_job_probe_classify
# with run_with_timeout STUBBED, so there is no powershell, no timing and no host dependence and
# Linux CI asserts the same guarantee the Windows leg does. The MECHANISM smoke (does the fence
# actually assign and kill) stays in test-msys-tree-cleanup.sh, which is where it can run.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: job-probe <name>" / "FAIL: job-probe <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB="$ROOT/hooks/local/lib/run-with-timeout.sh"
FENCE="$ROOT/hooks/local/lib/job-fence.sh"   # the fence + probe source (FR-25 extraction)

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "PASS: job-probe $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL: job-probe $1 (${2:-})"; }
finish() { echo "[test-job-probe-honesty] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$LIB" ] && [ -f "$FENCE" ] || { bad "setup-lib-present" "missing $LIB or $FENCE"; finish; }
# shellcheck source=/dev/null
. "$LIB"
ffhc_detect_timeout

# --- Probe honesty, ALL PLATFORMS (backlog release-gate-flaky-job-probe). The probe used to
# discard run_with_timeout's rc and classify on the ASSIGN-OK substring alone, so a watchdog kill
# (124/137) or a powershell that never started was cached as CAPABILITY ABSENCE for the process —
# a no-answer silently deleting the fence, and the flaky-gate defect class. These drive
# _ffhc_job_probe_run directly (the platform-independent seam) with run_with_timeout STUBBED: no
# powershell, no timing, no host dependence, so the guarantee is asserted on Linux CI too. ---
(
  FFHC_JOB_PROBE_RESULT=""; FFHC_JOB_PROBE_CLASS=""; FFHC_JOB_PROBE_TRIES=0
  run_with_timeout() { return 124; }                       # watchdog kill, nothing captured
  _ffhc_job_probe_run 2>/dev/null; r1=$?
  [ "$r1" -ne 0 ] && [ "$FFHC_JOB_PROBE_CLASS" = "timeout-or-error" ] && [ -z "$FFHC_JOB_PROBE_RESULT" ] || exit 1
  _ffhc_job_probe_run 2>/dev/null                          # budget spent => parked, never "no"
  [ "$FFHC_JOB_PROBE_RESULT" = "err" ] && [ "$FFHC_JOB_PROBE_TRIES" -eq 2 ] || exit 1
  FFHC_USE_JOB_OBJECT=1 ffhc_job_available 2>/dev/null
  [ $? -ne 0 ] && [ "$FFHC_JOB_PROBE_TRIES" -eq 2 ]        # parked => unavailable, no 3rd probe
); probe_noanswer=$?
if [ "$probe_noanswer" -eq 0 ]; then
  ok "probe-no-answer-never-cached-as-absence (watchdog rc 124 + no marker => class timeout-or-error, cache left UNKNOWN so the next call re-probes; after FFHC_JOB_PROBE_MAX_ATTEMPTS it parks as 'err' — never 'no', and never a 3rd live probe)"
else
  bad "probe-no-answer-never-cached-as-absence" "a no-answer probe (rc 124, no marker) was misclassified or memoised as capability absence — that is the flaky-gate defect: class=$FFHC_JOB_PROBE_CLASS cache=[$FFHC_JOB_PROBE_RESULT]"
fi

(
  FFHC_JOB_PROBE_RESULT=""; FFHC_JOB_PROBE_CLASS=""; FFHC_JOB_PROBE_TRIES=0
  run_with_timeout() { echo "ASSIGN-FAIL setinfo 24"; return 3; }   # the helper's OWN answer
  _ffhc_job_probe_run 2>/dev/null
  [ "$FFHC_JOB_PROBE_CLASS" = "definite-negative" ] && [ "$FFHC_JOB_PROBE_RESULT" = "no" ] || exit 1
  FFHC_USE_JOB_OBJECT=1 ffhc_job_available 2>/dev/null
  [ $? -ne 0 ] && [ "$FFHC_JOB_PROBE_TRIES" -eq 1 ]
); probe_defneg=$?
if [ "$probe_defneg" -eq 0 ]; then
  ok "probe-definite-negative-is-cached (an explicit ASSIGN-FAIL is the helper ANSWERING no => cached, no re-probe — the retry budget is for no-answers only)"
else
  bad "probe-definite-negative-is-cached" "ASSIGN-FAIL was not treated as a definite negative (class=$FFHC_JOB_PROBE_CLASS cache=[$FFHC_JOB_PROBE_RESULT]) — a real negative must not burn the retry budget"
fi

diag="$( ( FFHC_JOB_PROBE_RESULT=""; FFHC_JOB_PROBE_CLASS=""; FFHC_JOB_PROBE_TRIES=0
           run_with_timeout() { return 124; }; _ffhc_job_probe_run ) 2>&1 >/dev/null )"
diag_n="$(printf '%s\n' "$diag" | grep -c '^\[ffhc-job-probe\] ')"
if [ "$diag_n" -eq 1 ] && [ "$(printf '%s\n' "$diag" | wc -l)" -eq 1 ] && printf '%s' "$diag" \
     | grep -qE 'result=timeout-or-error rc=124 elapsed_ms=[0-9]+ helper=ok marker=absent attempt=1/[0-9]+ cache=unknown'; then
  ok "probe-emits-one-line-diagnosis (a non-ok probe prints exactly ONE stderr line carrying result/rc/elapsed_ms/helper/marker/attempt/cache — run-tests replays a failing phase's unparsed output, so a hosted run explains itself without a re-run)"
else
  bad "probe-emits-one-line-diagnosis" "expected exactly one '[ffhc-job-probe]' stderr line with rc/elapsed/helper/marker; got $diag_n line(s): [$diag]"
fi

if [ "$(_ffhc_job_probe_classify 0 'x ASSIGN-OK y PROBE-DONE')" = "ok" ] \
     && [ "$(_ffhc_job_probe_classify 0 'ASSIGN-FAIL assign 5')" = "definite-negative" ] \
     && [ "$(_ffhc_job_probe_classify 1 '')" = "timeout-or-error" ] \
     && [ "$(_ffhc_job_probe_classify 1 'powershell.exe : File cannot be loaded')" = "timeout-or-error" ] \
     && [ "$(_ffhc_job_probe_classify 124 'ASSIGN-OK PROBE-DONE')" = "timeout-or-error" ] \
     && [ "$(_ffhc_job_probe_classify 0 'ASSIGN-OK')" = "timeout-or-error" ] \
     && [ "$(_ffhc_job_probe_classify 0 'ASSIGN-OK then ASSIGN-FAIL assign 5')" = "definite-negative" ]; then
  ok "probe-classify-tri-state (ok needs ALL of rc 0 + ASSIGN-OK + PROBE-DONE; rc 124 with both markers, or ASSIGN-OK with no end sentinel, is timeout-or-error; ASSIGN-FAIL outranks ASSIGN-OK on mixed output; empty or a powershell start/parse error => timeout-or-error)"
else
  bad "probe-classify-tri-state" "classifier verdict wrong: clean='$(_ffhc_job_probe_classify 0 'x ASSIGN-OK y PROBE-DONE')' rc124-with-markers='$(_ffhc_job_probe_classify 124 'ASSIGN-OK PROBE-DONE')' no-sentinel='$(_ffhc_job_probe_classify 0 'ASSIGN-OK')' mixed='$(_ffhc_job_probe_classify 0 'ASSIGN-OK then ASSIGN-FAIL assign 5')' (expected ok / timeout-or-error / timeout-or-error / definite-negative)"
fi

# The SHIP-BLOCKER pair, end-to-end through _ffhc_job_probe_run: rc must decide the VERDICT, not
# only the diagnosis. A marker-then-watchdog-kill must not be cached or returned as success.
(
  FFHC_JOB_PROBE_RESULT=""; FFHC_JOB_PROBE_CLASS=""; FFHC_JOB_PROBE_TRIES=0
  run_with_timeout() { echo "ASSIGN-OK"; echo "PROBE-DONE"; return 124; }
  _ffhc_job_probe_run 2>/dev/null; r=$?
  [ "$r" -ne 0 ] && [ "$FFHC_JOB_PROBE_CLASS" = "timeout-or-error" ] && [ "$FFHC_JOB_PROBE_RESULT" != "ok" ]
); probe_markerto=$?
if [ "$probe_markerto" -eq 0 ]; then
  ok "probe-marker-then-timeout-is-not-ok (ASSIGN-OK + PROBE-DONE but watchdog rc 124 => timeout-or-error, never cached or returned as available — 'answered, then killed' is not a capability proof)"
else
  bad "probe-marker-then-timeout-is-not-ok" "a probe that printed its markers and was then KILLED by the watchdog was accepted as success (class=$FFHC_JOB_PROBE_CLASS cache=[$FFHC_JOB_PROBE_RESULT]) — false green"
fi

(
  FFHC_JOB_PROBE_RESULT=""; FFHC_JOB_PROBE_CLASS=""; FFHC_JOB_PROBE_TRIES=0
  run_with_timeout() { echo "ASSIGN-OK"; echo "ASSIGN-FAIL assign 5"; return 5; }
  _ffhc_job_probe_run 2>/dev/null; r=$?
  [ "$r" -ne 0 ] && [ "$FFHC_JOB_PROBE_CLASS" = "definite-negative" ] && [ "$FFHC_JOB_PROBE_RESULT" = "no" ]
); probe_mixed=$?
if [ "$probe_mixed" -eq 0 ]; then
  ok "probe-mixed-markers-are-negative (ASSIGN-OK followed by ASSIGN-FAIL => definite-negative; the failure marker outranks the success marker, so a substring scan cannot pick the optimistic one)"
else
  bad "probe-mixed-markers-are-negative" "mixed ASSIGN-OK/ASSIGN-FAIL output did not resolve to definite-negative (class=$FFHC_JOB_PROBE_CLASS cache=[$FFHC_JOB_PROBE_RESULT])"
fi

# Helper materialisation is ATOMIC (all platforms). The old writer was `cat > $p` behind an
# existence test: the destination becomes visible the instant cat opens it, so a concurrent probe
# passed the test and executed a half-written script — a load-dependent parse failure that reads
# exactly like capability absence. Eight racers into an empty TMPDIR, while the parent samples the
# destination continuously: every racer must get a COMPLETE file and the destination must never be
# observed present-but-incomplete.
jr_dir="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-jobrace.XXXXXX" 2>/dev/null)"
if [ -n "$jr_dir" ] && [ -d "$jr_dir" ]; then
  jr_res="$jr_dir/res"; : > "$jr_res"
  ( export TMPDIR="$jr_dir"
    # THE DEFECT IS A NON-EMPTY, UNTERMINATED READ — a half-written script that parses as garbage.
    # A momentarily ABSENT destination is NOT that defect (a replacing rename can degrade to
    # unlink+rename on Windows) and the probe now classifies a missing helper honestly as
    # timeout-or-error, never as absence. So a racer records `partialread` (the failure) only for
    # a file that exists, is non-empty, and still lacks the sentinel on a re-read.
    for _ in 1 2 3 4 5 6 7 8; do
      ( p="$(_ffhc_job_helper_path)"
        if [ -z "$p" ]; then echo empty >> "$jr_res"
        else
          t="$(tail -1 "$p" 2>/dev/null)"
          [ "$t" = "# FENCE-EOF" ] || { sleep 0.2; t="$(tail -1 "$p" 2>/dev/null)"; }
          if [ "$t" = "# FENCE-EOF" ]; then echo ok >> "$jr_res"
          elif [ -s "$p" ]; then echo partialread >> "$jr_res"
          else echo empty >> "$jr_res"; fi
        fi
      ) >/dev/null 2>&1 &
    done
    # Sample the destination continuously. PARTIAL means present, NON-EMPTY and not sentinel-
    # terminated: `-s` excludes the momentary ENOENT of a replacing rename, and the confirm
    # re-read excludes any residue of that window — a genuinely half-written file stays
    # half-written (nothing rewrites it in place), so a real defect survives both.
    jr_f="$jr_dir/ffhc-job-fence-v2.ps1"; jr_partial=0; jr_n=0
    while [ "$jr_n" -lt 400 ]; do
      if [ -s "$jr_f" ] && [ "$(tail -1 "$jr_f" 2>/dev/null)" != "# FENCE-EOF" ] \
           && [ "$(tail -1 "$jr_f" 2>/dev/null)" != "# FENCE-EOF" ]; then jr_partial=1; break; fi
      jr_n=$((jr_n + 1))
    done
    wait
    # Uncontended control: with the race over, a plain call must yield a complete file — so the
    # row can never pass vacuously on 8 empty answers.
    jr_ctl="$(_ffhc_job_helper_path)"
    [ -n "$jr_ctl" ] && [ "$(tail -1 "$jr_ctl" 2>/dev/null)" = "# FENCE-EOF" ] && jr_ctl_ok=0 || jr_ctl_ok=1
    printf 'sampler-partial=%s ok=%s partialread=%s empty=%s temps=%s control=%s' "$jr_partial" \
      "$(grep -c '^ok$' "$jr_res")" "$(grep -c '^partialread$' "$jr_res")" "$(grep -c '^empty$' "$jr_res")" \
      "$(ls "$jr_dir" | grep -c '^ffhc-job-fence\.')" "$jr_ctl_ok" > "$jr_dir/metrics"
    [ "$jr_partial" -eq 0 ] && [ "$jr_ctl_ok" -eq 0 ] && ! grep -q '^partialread$' "$jr_res" \
      && [ "$(( $(grep -c '^ok$' "$jr_res") + $(grep -c '^empty$' "$jr_res") ))" -eq 8 ] \
      && [ "$(ls "$jr_dir" | grep -c '^ffhc-job-fence\.')" -eq 0 ]   # no orphaned staging temps
  ); jr_rc=$?
  jr_metrics="$(cat "$jr_dir/metrics" 2>/dev/null)"; [ -n "$jr_metrics" ] || jr_metrics="metrics missing"
  rm -rf "$jr_dir"
  if [ "$jr_rc" -eq 0 ]; then
    ok "helper-materialise-is-atomic (8 concurrent _ffhc_job_helper_path calls into one empty TMPDIR: the destination was NEVER observed present-but-unterminated across 400 samples, no caller read a non-empty unterminated helper, the uncontended control call yielded a complete file, and no staging temp leaked)"
  else
    bad "helper-materialise-is-atomic" "concurrent materialisation exposed a partial helper or leaked a staging temp ($jr_metrics; expected sampler-partial=0 partialread=0 ok+empty=8 temps=0 control=0) — a half-written .ps1 fails to parse and the probe reads it as capability absence"
  fi
else
  bad "helper-materialise-is-atomic" "could not create a temp dir for the race fixture"
fi

# Source-structure belts — deterministic and host-independent, like the knob-first belt above.
# Each names a property a "simplifying" edit would silently drop, on a platform that cannot
# execute the Windows path at all.
grep -q -- '-DeadlineSecs 1 2>&1' "$FENCE"                                          && src_err=0 || src_err=1
grep -q 'if ($WinPid -le 0)' "$FENCE"                                               && src_w0=0  || src_w0=1
grep -qE '^\s*\$ticks = \[int\]\(\[math\]::Ceiling\(\$DeadlineSecs / 0\.1\)\)\s*$' "$FENCE" && src_tick=0 || src_tick=1
grep -q '_ffhc_job_probe_classify "$rc" "$out"' "$FENCE"                            && src_rc=0  || src_rc=1
grep -q 'mv -f "$tmp" "$p"' "$FENCE" && ! grep -qE '^\s*cat > "\$p" <<' "$FENCE"       && src_mv=0  || src_mv=1
if [ "$src_err" -eq 0 ] && [ "$src_w0" -eq 0 ] && [ "$src_tick" -eq 0 ] && [ "$src_rc" -eq 0 ] && [ "$src_mv" -eq 0 ]; then
  ok "probe-source-invariants (probe captures powershell stderr (2>&1, not 2>/dev/null) so a start/parse failure is diagnosable; WinPid<=0 exits the helper right after create+setinfo; the tick count is the bare ceil(DeadlineSecs/0.1) with no +20 inflation; the watchdog rc is PASSED to the classifier, not merely logged; the helper is published by rename, never by a direct cat into the destination)"
else
  bad "probe-source-invariants" "lost a probe invariant: stderr-captured=$src_err winpid0-early-exit=$src_w0 no-tick-inflation=$src_tick rc-reaches-classifier=$src_rc atomic-publish=$src_mv (0=good) — dropping stderr makes a hosted failure undiagnosable; classifying without the rc re-opens the marker-then-timeout false green"
fi


finish
