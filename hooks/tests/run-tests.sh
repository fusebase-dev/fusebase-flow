#!/usr/bin/env bash
# Fusebase Flow — hook test runner
# Pipes each fixture into its target handler and checks the response.
#
# ## Release evidence authority — NO run of this script is release evidence
#   The CI `verify` job on the tagged SHA is (.github/workflows/fusebase-flow-release.yml
#   -> needs: verify -> fusebase-flow-verify.yml). This harness run locally is developer
#   feedback: unpinned host, no SHA/platform recorded, gates nothing.
#   Canonical statement: PUBLISHING.md § Release evidence authority.
#
# ## Run tiers
#   (default)          FAST LOCAL DEFAULT — the FF_FAST_TAGS set only. Budgeted at <=10min
#                      under loaded MSYS. Non-attesting: hook-test-results-fast.md.
#   FF_FULL=1          the FULL unscoped set (every non-opt-in phase). The one explicit
#                      maintainer invocation. Attesting: hook-test-results.md + the strict
#                      summary. CI (GITHUB_ACTIONS/CI) takes this path automatically.
#   FF_ONLY="a,b"      SCOPED subset (implement-loop iteration speed); opt-in and heavy
#                      tags are reachable this way. Non-attesting: hook-test-results-scoped.md.
#   FF_LIST=1          print the tag list (RUN/SKIP) for THIS invocation; exit 0, no run.
#
#   Every non-attesting run is fail-closed BY CONSTRUCTION: its summary line is deliberately
#   NOT the strict "[run-tests] N/N PASS" shape, so ffhc_run_tests_pass_ok /
#   ffhc_count_pass_lines read it as NOT a clean full pass, and its rows go to a separate
#   file — the canonical hook-test-results.md is never touched by a subset run.
#   A LOCAL gate report may cite ONLY state/audit/hook-test-results.md — never the -scoped
#   or -fast file. Unknown or empty FF_ONLY selection => exit 2 (never a "scoped to
#   nothing" green). Canonical home for this rule: this header +
#   flow-skills/validation-and-qa/SKILL.md (sub-mode A).

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TESTS_DIR="$ROOT/hooks/tests/fixtures"
HANDLERS_DIR="$ROOT/hooks/handlers"

python_bin="${PYTHON:-python3}"

if ! command -v "$python_bin" >/dev/null 2>&1; then
    echo "[run-tests] $python_bin not found; install Python 3.10+." >&2
    exit 1
fi

# Bounded-run engine (WS2-core strict-scoped reap): each heavy phase runs under
# ffhc_run_bounded (tempfile capture + the recorded-child taskkill), so an MSYS
# native grandchild can't hold a $(...) pipe open past the deadline and freeze the
# harness. Reads FFHC_LAST_OUT / FFHC_LAST_RC after each call.
. "$ROOT/hooks/local/lib/run-with-timeout.sh"
ffhc_detect_timeout
# Guarded group-reap primitives, shared with the out-of-band sentinel so both teardown paths
# apply the SAME fail-closed guards (a second copy would drift).
FF_ORPHAN_REAP="$ROOT/hooks/tests/lib/orphan-reap.sh"
# shellcheck source=/dev/null
[ -f "$FF_ORPHAN_REAP" ] && . "$FF_ORPHAN_REAP"

# Per-phase heavy-run bound — a liveness backstop, not a performance assertion.
# 600s was a rounded-up quiet-host observation and two phases crossed it with ZERO failed
# assertions (bootstrap-exception 602s, upgrade-repair-managed 603s) while Linux was 746/746
# on the identical commit; bootstrap-exception then measured 680s on an unloaded host.
# 1800s is ~2.6x that 680s. NOTE: nothing MECHANICALLY enforces a headroom multiplier — this
# is a reviewed value, not a checked invariant. Backlog: gate-bounds-lack-headroom.
FF_PHASE_TIMEOUT="${FF_PHASE_TIMEOUT:-1800}"

# Opt into the parent-owned heartbeat (decision M3); FFHC_HEARTBEAT_SECS=0 silences it.
# TRIPWIRE: deliberately NOT exported — a child test script must not inherit a heartbeat that
# would land inside ITS captured payload.
FFHC_HEARTBEAT_SECS="${FFHC_HEARTBEAT_SECS:-30}"

# --- FF_ONLY scoped-gate parse (implement-loop iteration speed) ---------------------
# Canonical phase tags, in run order. This list is the FF_LIST discovery source and the
# FF_ONLY validation set; add a tag here (and its guard) when a phase is added.
FF_TAGS=(fixtures module-size health-check-timeout git-smoke hook-manifest newline-preserve baseline-merge \
  sync-allowlist policy-state bootstrap-baseline-hop fr22-delivery po-verifiable-boot \
  po-investigate liveness codex-parity codex-plugin cli-0259 secret-scan-staged bootstrap-exception \
  lane-router \
  trusted-enforcer hook-install-rc msys-tree-cleanup ws5-upgrade ff-only return-budget \
  supersede-primitive rule-inventory boot-size prohibition-residency token-waste-classify \
  budget-literals history-extraction approval-binding approval-writer command-policy upgrade-classify \
  upgrade-boundary preboundary-consumed upgrade-repair recovery-hint install-doc release-authority cli-flow-profile \
  signal-reap cli-flow-recovery)

# OPT-IN-ONLY tags: registered and reachable, but NEVER in the default/required set — they
# run only when named in FF_ONLY. cli-flow-profile is the temporary recovery-instrumentation
# diagnostic: it proves trace schema, containment, redaction and failure-inertness, NOT
# recovery correctness, so it is not release coverage (architecture-review Q3).
FF_OPTIN_TAGS=(cli-flow-profile)
declare -A FF_OPTIN=(); for t in "${FF_OPTIN_TAGS[@]}"; do FF_OPTIN[$t]=1; done

declare -A FF_SEL=()      # selected tags (populated only when scoped)
FF_SCOPED=0               # 1 iff FF_ONLY is a non-empty selection
if [ -n "${FF_ONLY:-}" ]; then
  # Split on commas; trim surrounding whitespace per tag. A bogus or all-blank
  # selection => exit 2 (never a silent "scoped to nothing" green).
  IFS=',' read -r -a _ff_req <<< "$FF_ONLY"
  declare -A _ff_valid=(); for t in "${FF_TAGS[@]}"; do _ff_valid[$t]=1; done
  for raw in "${_ff_req[@]}"; do
    tag="${raw#"${raw%%[![:space:]]*}"}"; tag="${tag%"${tag##*[![:space:]]}"}"   # trim
    [ -z "$tag" ] && continue
    if [ -z "${_ff_valid[$tag]:-}" ]; then
      echo "[run-tests] ERROR: FF_ONLY unknown tag '$tag' (valid: ${FF_TAGS[*]})" >&2
      exit 2
    fi
    FF_SEL[$tag]=1
  done
  if [ "${#FF_SEL[@]}" -eq 0 ]; then
    echo "[run-tests] ERROR: FF_ONLY selected no valid tags (was '$FF_ONLY')" >&2
    exit 2
  fi
  FF_SCOPED=1
fi

# --- Local tier: the FAST set is the local default -------------------------------------
# Membership is the architecture-review Q4 "Local default" tier, minus the one member that
# breaks the review's OWN bound policy ("Local product budget: <=10 minutes under loaded
# MSYS. A phase that breaks the budget leaves the local tier — the wall is not raised"):
# secret-scan-staged measured 456s of a 600s budget on this host. Its scanner still runs on
# EVERY commit via hooks/git/pre-commit; only the scenario phase moved. release-authority
# (14s) is added — it guards the release-evidence contract itself.
# TRIPWIRE: this is an ALLOWLIST, so a NEW phase is heavy until measured and promoted. The
# safe direction: a new phase runs in CI/full from day one, never silently on the budget.
FF_FAST_TAGS=(fixtures module-size git-smoke hook-manifest lane-router \
  approval-binding approval-writer command-policy release-authority)
declare -A FF_FAST=(); for t in "${FF_FAST_TAGS[@]}"; do FF_FAST[$t]=1; done

# FF_FULL=1 => the full unscoped run (every non-opt-in phase). CI is always full: the CI
# `verify` job on the tagged SHA is the release evidence, so it must never inherit the
# local budget tier. This is why .github/workflows/* needs no edit to keep its coverage.
FF_FULL_RUN=0
if [ "${FF_FULL:-0}" = "1" ] || [ "${GITHUB_ACTIONS:-}" = "true" ] || [ "${CI:-}" = "true" ]; then
  FF_FULL_RUN=1
fi

# ATTESTING = the full unscoped set, and nothing else. Scoped and fast-default runs are
# non-attesting BY CONSTRUCTION (separate results file + a summary the strict classifier
# rejects) — a subset can never be mistaken for the complete local result.
FF_ATTESTING=0
[ "$FF_SCOPED" -eq 0 ] && [ "$FF_FULL_RUN" -eq 1 ] && FF_ATTESTING=1

# ff_selected TAG: scoped => the tag must be in the selection (opt-in and heavy tags are BOTH
# reachable that way). Unscoped => never an opt-in tag; heavy tags only on a full run.
ff_selected() {
  if [ "$FF_SCOPED" -eq 1 ]; then [ -n "${FF_SEL[$1]:-}" ]; return; fi
  [ -z "${FF_OPTIN[$1]:-}" ] || return 1
  [ "$FF_FULL_RUN" -eq 1 ] || [ -n "${FF_FAST[$1]:-}" ]
}
# ff_skip_note TAG: the visible per-phase skip line, naming WHY and how to get the phase back.
ff_skip_note() {
  if [ "$FF_SCOPED" -eq 1 ]; then echo "SKIP (FF_ONLY): $1"
  elif [ -n "${FF_OPTIN[$1]:-}" ]; then echo "SKIP (opt-in diagnostic — FF_ONLY=$1 to run): $1"
  else echo "SKIP (heavy — FF_FULL=1 for the full set; CI runs it): $1"; fi
}

# FF_LIST=1: print the canonical tags with RUN/SKIP markers and exit 0 (no run).
# TRIPWIRE: routed through ff_selected, never a second predicate — a list that could
# disagree with what actually runs is worse than no list.
if [ "${FF_LIST:-0}" = "1" ]; then
  for t in "${FF_TAGS[@]}"; do
    if ff_selected "$t"; then echo "RUN  $t"; else echo "SKIP $t"; fi
  done
  exit 0
fi

# Subset runs write to a SEPARATE results file so the full-gate hook-test-results.md is
# never clobbered (the health engine / gate reports read only the full file). ONLY an
# attesting (full unscoped) run may touch the canonical path.
if [ "$FF_SCOPED" -eq 1 ]; then
  RESULTS_FILE="$ROOT/state/audit/hook-test-results-scoped.md"
elif [ "$FF_ATTESTING" -eq 0 ]; then
  RESULTS_FILE="$ROOT/state/audit/hook-test-results-fast.md"
else
  RESULTS_FILE="$ROOT/state/audit/hook-test-results.md"
fi

# EXIT-trap reaper (WS3): if the harness is signaled while a bounded phase is still in
# flight, taskkill ONLY that phase's own recorded child winpid — FFHC_LAST_WINPID, set
# live at launch by the T1 capture — strict-scoped, never a broad taskkill (depends on
# WS2-core). It passes FFHC_LAST_CHILD_PID too (T12), so the trap gets the SAME PID-reuse
# re-verify guard as the deadline path (ffhc_msys_taskkill_winpid re-checks the winpid
# still maps to our child before killing). The lib + run_bounded_phase CLEAR both the
# instant a phase returns (its child is already reaped by then), so a normal exit reaps
# nothing and a stale/reused winpid is never swept. The reap is a no-op off-MSYS.
FFHC_LAST_WINPID=""
FFHC_LAST_CHILD_PID=""
# _ff_reap_in_flight: the SAME guarded group reap the sentinel runs, executed harness-side while
# an EXIT trap still can. It reads the PUBLISHED record, so there is exactly one definition of
# "what is in flight". No record, no guard lib, or an unconfirmable identity => no-op.
_ff_reap_in_flight() {
    [ -n "${FFHC_SENTINEL_STATE:-}" ] || return 0
    command -v ffor_state_read >/dev/null 2>&1 || return 0
    ffor_state_read "$FFHC_SENTINEL_STATE"
    [ -n "$FFOR_S_PID" ] || return 0
    ffor_resolve "$FFOR_S_PID" "$FFOR_S_PGID" || return 0
    ffor_pgid_of $$ || return 0   # snapshot-backed: a `$( )` here costs a fork this path cannot afford
    ffor_reap "$FFOR_S_PID" "$FFOR_S_WIN" "$FFOR_R_PGID" "$FFOR_R_LEADSTART" \
        "$FFOR_PGID_OUT" "${FF_SENTINEL_GRACE:-5}"
    return 0
}
# TRIPWIRE (ordering): cleanup FIRST, disarm the sentinel LAST. The reverse order cleared the
# in-flight record and killed the sentinel BEFORE the known-insufficient `taskkill //T` ran, so
# on every EXIT path that does run — the nap-forced-off arm — nothing reaped the phase group.
_ff_exit_reap() {
    _ff_reap_in_flight
    if ffhc_is_msys && [ -n "$FFHC_LAST_WINPID" ]; then
        ffhc_msys_taskkill_winpid "$FFHC_LAST_WINPID" "$FFHC_LAST_CHILD_PID"
    fi
    _ff_sentinel_stop
}

# --- S2 orphan sentinel (T4) ------------------------------------------------------------------
# TIER: armed around the DEEP runner only (FF_FULL / CI / a scoped run that may name a heavy tag),
# never on the fast local default. The sentinel is symptom-support for multi-minute MSYS process
# trees; the fast tier has none, so paying for it on every local check is cost without coverage
# (architecture-review Q3: "keep it only around the Windows/MSYS deep runner").
# TRIPWIRE: the EXIT trap above is NOT a teardown guarantee. T3 measured that this harness is deaf
# to TERM/INT while a bounded phase polls (an explicit TERM trap never fired in 12s), so an outer
# `timeout -k 5s` SIGKILLs it and NOTHING harness-side runs — the phase child and its grandchild
# then outlive the gate and corrupt the next run's timings.
# The sentinel is the out-of-band answer: `timeout` gives it its OWN process group (immune to the
# group signal that kills us) plus a hard cap (it can never outlive the run). It watches THIS pid
# and, if we die with a phase in flight, revalidates the recorded identity and terminates that
# phase's process group only. Evidence: state/audit/run-tests-signal-reap/<full-head>/summary.md.
FF_SENTINEL_PID=""
FF_SENTINEL_PGID=""
FF_SENTINEL_GRACE=5
FFHC_SENTINEL_STATE=""
_ff_sentinel_start() {
    ffhc_is_msys || return 0
    [ "$FF_FULL_RUN" -eq 1 ] || [ "$FF_SCOPED" -eq 1 ] || return 0
    [ -n "${FFHC_TIMEOUT_BIN:-}" ] || return 0
    local sentinel="$ROOT/hooks/tests/lib/orphan-sentinel.sh"
    [ -f "$sentinel" ] || return 0
    FFHC_SENTINEL_STATE="$(mktemp "${TMPDIR:-/tmp}/ffhc-sentinel.$$.XXXXXX" 2>/dev/null)" || {
        FFHC_SENTINEL_STATE=""; return 0; }
    local grace="${FFHC_TIMEOUT_KILL_GRACE:-5s}"; grace="${grace%[!0-9]*}"
    case "$grace" in ''|*[!0-9]*) grace=5 ;; esac
    FF_SENTINEL_GRACE="$grace"
    # Cap is a backstop only — the sentinel exits as soon as we die or it is stopped below.
    "$FFHC_TIMEOUT_BIN" "${FF_SENTINEL_CAP:-21600}" bash "$sentinel" \
        "$$" "$(ffhc_pgid_of $$)" "$FFHC_SENTINEL_STATE" "$grace" >/dev/null 2>&1 &
    FF_SENTINEL_PID=$!
    # The sentinel runs in the wrapper's OWN group. Recording that group is what lets the stop
    # below still reach the sentinel when its `timeout` wrapper has died — a PID-only kill on a
    # dead wrapper would leave the guard running with nothing left to guard.
    FF_SENTINEL_PGID="$(ffhc_pgid_of "$FF_SENTINEL_PID")"
}
_ff_sentinel_stop() {
    [ -n "$FF_SENTINEL_PID" ] || { [ -n "$FFHC_SENTINEL_STATE" ] && rm -f "$FFHC_SENTINEL_STATE" 2>/dev/null; return 0; }
    ffhc_sentinel_note                      # nothing in flight => a racing reap finds nothing
    kill "$FF_SENTINEL_PID" 2>/dev/null
    wait "$FF_SENTINEL_PID" 2>/dev/null
    # Only ever the sentinel's OWN group, and never ours: an unresolved OR matching pgid signals
    # nothing (the sentinel self-exits within a poll tick of our death regardless).
    local own; own="$(ffhc_pgid_of $$)"
    if [ -n "$FF_SENTINEL_PGID" ] && [ -n "$own" ] && [ "$FF_SENTINEL_PGID" != "$own" ]; then
        case "$FF_SENTINEL_PGID" in
            *[!0-9]*) : ;;
            *) [ "$FF_SENTINEL_PGID" -gt 1 ] && kill -TERM -"$FF_SENTINEL_PGID" 2>/dev/null ;;
        esac
    fi
    FF_SENTINEL_PGID=""
    FF_SENTINEL_PID=""
    [ -n "$FFHC_SENTINEL_STATE" ] && rm -f "$FFHC_SENTINEL_STATE" 2>/dev/null
    return 0
}
trap _ff_exit_reap EXIT
_ff_sentinel_start

# progress <phase>: flush a starting marker to stderr BEFORE the (possibly multi-min)
# phase runs, so a slow phase is visibly progressing, never mistakable for a freeze.
progress() { printf '[run-tests] starting %s\n' "$1" >&2; }

# run_bounded_phase <label> CMD...: flush progress, run CMD under ffhc_run_bounded
# (tempfile capture + T1 strict-scoped reap; FFHC_LAST_WINPID tracks the in-flight
# child for the EXIT-trap), exposing FFHC_LAST_OUT / FFHC_LAST_RC to the caller. Clears
# FFHC_LAST_WINPID on return so the EXIT-trap never reaps a completed phase's dead winpid.
run_bounded_phase() {
    local label="$1"; shift
    progress "$label"
    local _t0=$SECONDS
    FFHC_HEARTBEAT_LABEL="$label"
    ffhc_run_bounded "$FF_PHASE_TIMEOUT" "$@"
    # D14.1: per-phase wall time on STDERR (progress() precedent :112) — stdout parse
    # contracts (strict summary, ^PASS:/^FAIL: counting) stay byte-clean.
    printf '[run-tests] %s took %ss\n' "$label" "$((SECONDS - _t0))" >&2
    FFHC_LAST_WINPID=""; FFHC_LAST_CHILD_PID=""   # phase returned => child reaped; no stale sweep on exit
}

pass=0
fail=0
total=0
report_rows=""
diag_blocks=""

# emit_phase_diagnostics <label> <captured-phase-output> <fail-count>
# C4 / FR-27: every phase parser prints and rows ONLY the lines matching its
# `^(PASS|FAIL): <tag>` contract. A test that writes its failure reason anywhere else — its own
# stderr, which ffhc_run_bounded merges into the tempfile capture — had that reason silently
# dropped, so a gate FAIL was undiagnosable from the log OR from RESULTS_FILE. On a FAILING phase
# only, replay the unparsed remainder to STDERR (stdout stays byte-clean for the strict summary
# and the ^PASS:/^FAIL: counting) and record it in the artifact's diagnostics section.
emit_phase_diagnostics() {
    [ "${3:-0}" -gt 0 ] || return 0
    local rest
    rest="$(printf '%s\n' "$2" | grep -vE '^(PASS|FAIL|INCONCLUSIVE):' | sed '/^[[:space:]]*$/d')"
    [ -n "$rest" ] || return 0
    {
        printf '[run-tests] --- %s diagnostics (unparsed phase output, replayed because the phase FAILED) ---\n' "$1"
        printf '%s\n' "$rest"
        printf '[run-tests] --- end %s diagnostics ---\n' "$1"
    } >&2
    diag_blocks="$diag_blocks### $1"$'\n\n```\n'"$rest"$'\n```\n\n'
}

mkdir -p "$(dirname "$RESULTS_FILE")"

# Loud banner: a subset run is NEVER a full gate, and no local run is release evidence —
# make both impossible to miss.
if [ "$FF_SCOPED" -eq 1 ]; then
  {
    echo "============================================================"
    echo "  SCOPED RUN — FF_ONLY=${FF_ONLY}"
    echo "  This is a SUBSET, not a full gate. Results -> ${RESULTS_FILE#"$ROOT/"}"
    echo "  No local run is release evidence — the CI verify job on the tagged SHA is."
    echo "============================================================"
  } >&2
elif [ "$FF_ATTESTING" -eq 0 ]; then
  {
    echo "============================================================"
    echo "  FAST LOCAL DEFAULT — ${#FF_FAST_TAGS[@]} of ${#FF_TAGS[@]} phases"
    echo "  NOT release evidence. Release evidence is the CI 'verify' job"
    echo "  on the tagged SHA (.github/workflows/fusebase-flow-release.yml"
    echo "  -> needs: verify). See PUBLISHING.md § Release evidence authority."
    echo "  Heavy phases are skipped here and run in CI."
    echo "  Full local set: FF_FULL=1 bash hooks/tests/run-tests.sh"
    echo "  Results -> ${RESULTS_FILE#"$ROOT/"}"
    echo "============================================================"
  } >&2
fi

if ff_selected fixtures; then
    # F5/D6: ALL fixtures in ONE python process via the single-process runner
    # (hooks/tests/run_hook_tests.py). Same 21 fixtures + assertion semantics +
    # PASS:/FAIL: line shapes as the retired fork-loop, plus the synthetic
    # _parse-invariant row. Counted like run_shell_phase (^PASS:/^FAIL:); the
    # bounded phase is one spawn, not 21x(>=3) MSYS spawns.
    run_bounded_phase "fixture handler tests (single-process)" "$python_bin" "$ROOT/hooks/tests/run_hook_tests.py"
    fx_out="$FFHC_LAST_OUT"; fx_rc=$FFHC_LAST_RC
    echo "$fx_out" | grep -E '^(PASS|FAIL):' || true
    fx_pass="$(echo "$fx_out" | grep -c '^PASS:')"
    fx_failed="$(echo "$fx_out" | grep -c '^FAIL:')"
    total=$((total + fx_pass + fx_failed)); pass=$((pass + fx_pass)); fail=$((fail + fx_failed))
    while IFS= read -r line; do
        result="${line%%:*}"; rest="${line#*: }"
        report_rows="$report_rows| run_hook_tests.py | $rest | $result | single-process fixture |"$'\n'
    done < <(echo "$fx_out" | grep -E '^(PASS|FAIL):')
    # Crash guard (same contract as run_shell_phase): a non-zero exit with zero
    # parsed FAIL lines means the runner died before reporting a single fixture.
    if [ "$fx_rc" -ne 0 ] && [ "$fx_failed" -eq 0 ]; then
        total=$((total + 1)); fail=$((fail + 1))
        echo "FAIL: run_hook_tests.py crashed (exit $fx_rc) before reporting fixtures"
        report_rows="$report_rows| run_hook_tests.py | (harness) | FAIL | crashed with exit $fx_rc, no fixture output |"$'\n'
    fi
    fx_bad=$fx_failed; [ "$fx_rc" -eq 0 ] || fx_bad=$((fx_bad + 1))
    emit_phase_diagnostics "fixture handler tests" "$fx_out" "$fx_bad"
else
    ff_skip_note fixtures
fi

# Phase 2 — FR-25 module-size ratchet scenarios (shell-level; not handler fixtures).
MS_TEST="$ROOT/hooks/tests/test-module-size.sh"
if ! ff_selected module-size; then
    ff_skip_note module-size
elif [ -f "$MS_TEST" ]; then
    run_bounded_phase "module-size ratchet" bash "$MS_TEST"
    ms_out="$FFHC_LAST_OUT"; ms_fail=$FFHC_LAST_RC
    echo "$ms_out" | grep -E '^(PASS|FAIL): module-size' || true
    ms_pass="$(echo "$ms_out" | grep -c '^PASS: module-size')"
    ms_failed="$(echo "$ms_out" | grep -c '^FAIL: module-size')"
    total=$((total + ms_pass + ms_failed))
    pass=$((pass + ms_pass))
    fail=$((fail + ms_failed))
    while IFS= read -r line; do
        name="${line#*: module-size }"
        result="${line%%:*}"
        report_rows="$report_rows| test-module-size.sh | $name | $result | exit-code scenario |"$'\n'
    done < <(echo "$ms_out" | grep -E '^(PASS|FAIL): module-size')
    # Crash guard: a non-zero exit with zero parsed FAIL lines means the scenario
    # script died before running (mktemp/cp/syntax) — count it, don't go green.
    if [ "$ms_fail" -ne 0 ] && [ "$ms_failed" -eq 0 ]; then
        total=$((total + 1))
        fail=$((fail + 1))
        echo "FAIL: test-module-size.sh crashed (exit $ms_fail) before reporting scenarios"
        report_rows="$report_rows| test-module-size.sh | (harness) | FAIL | crashed with exit $ms_fail, no scenario output |"$'\n'
    fi
    ms_bad=$ms_failed; [ "$ms_fail" -eq 0 ] || ms_bad=$((ms_bad + 1))
    emit_phase_diagnostics "module-size ratchet" "$ms_out" "$ms_bad"
fi

# Phase 3 — health-check bounded-execution + verdict/exit contract scenarios
# (shell-level; spec docs/specs/health-check-fast-timeout). Same parse contract
# as Phase 2: count "PASS:/FAIL: health-check-timeout <name>" lines; a non-zero
# exit with zero parsed FAIL lines means the script crashed before reporting.
HT_TEST="$ROOT/hooks/tests/test-health-check-timeout.sh"
if ! ff_selected health-check-timeout; then
    ff_skip_note health-check-timeout
elif [ -f "$HT_TEST" ]; then
    run_bounded_phase "health-check-timeout scenarios" bash "$HT_TEST"
    ht_out="$FFHC_LAST_OUT"; ht_rc=$FFHC_LAST_RC
    echo "$ht_out" | grep -E '^(PASS|FAIL): health-check-timeout' || true
    ht_pass="$(echo "$ht_out" | grep -c '^PASS: health-check-timeout')"
    ht_failed="$(echo "$ht_out" | grep -c '^FAIL: health-check-timeout')"
    total=$((total + ht_pass + ht_failed))
    pass=$((pass + ht_pass))
    fail=$((fail + ht_failed))
    while IFS= read -r line; do
        name="${line#*: health-check-timeout }"
        result="${line%%:*}"
        report_rows="$report_rows| test-health-check-timeout.sh | $name | $result | timeout/verdict scenario |"$'\n'
    done < <(echo "$ht_out" | grep -E '^(PASS|FAIL): health-check-timeout')
    if [ "$ht_rc" -ne 0 ] && [ "$ht_failed" -eq 0 ]; then
        total=$((total + 1))
        fail=$((fail + 1))
        echo "FAIL: test-health-check-timeout.sh crashed (exit $ht_rc) before reporting scenarios"
        report_rows="$report_rows| test-health-check-timeout.sh | (harness) | FAIL | crashed with exit $ht_rc, no scenario output |"$'\n'
    fi
    ht_bad=$ht_failed; [ "$ht_rc" -eq 0 ] || ht_bad=$((ht_bad + 1))
    emit_phase_diagnostics "health-check-timeout scenarios" "$ht_out" "$ht_bad"
fi

# Phases 4-7 — upgrade-tooling-hardening shell scenarios (v3.24.x). Same parse
# contract as Phase 2/3: count "PASS:/FAIL: <tag> <name>" lines; a non-zero exit
# with zero parsed FAIL lines means the script crashed before reporting. One loop
# over (script, tag) pairs keeps run-tests under the FR-25 ceiling.
run_shell_phase() { # run_shell_phase <test-script> <tag>
    local script="$ROOT/hooks/tests/$1" tag="$2"
    ff_selected "$tag" || { ff_skip_note "$tag"; return 0; }
    [ -f "$script" ] || return 0
    local out rc p f
    run_bounded_phase "$tag" bash "$script"
    out="$FFHC_LAST_OUT"; rc=$FFHC_LAST_RC
    echo "$out" | grep -E "^(PASS|FAIL): $tag " || true
    p="$(echo "$out" | grep -c "^PASS: $tag ")"
    f="$(echo "$out" | grep -c "^FAIL: $tag ")"
    total=$((total + p + f)); pass=$((pass + p)); fail=$((fail + f))
    while IFS= read -r line; do
        name="${line#*: $tag }"; result="${line%%:*}"
        report_rows="$report_rows| $1 | $name | $result | shell scenario |"$'\n'
    done < <(echo "$out" | grep -E "^(PASS|FAIL): $tag ")
    if [ "$rc" -ne 0 ] && [ "$f" -eq 0 ]; then
        total=$((total + 1)); fail=$((fail + 1))
        echo "FAIL: $1 crashed (exit $rc) before reporting scenarios"
        report_rows="$report_rows| $1 | (harness) | FAIL | crashed with exit $rc, no scenario output |"$'\n'
    fi
    local bad=$f; [ "$rc" -eq 0 ] || bad=$((bad + 1))
    emit_phase_diagnostics "$tag" "$out" "$bad"
}
run_shell_phase test-git-hooks-smoke.sh      "git-smoke"
run_shell_phase test-hook-manifest.sh        "hook-manifest"
# Makes the EXISTING lightweight-lane eligibility gate executable for path-observable surfaces.
# Its FULL fixtures are the actual changed paths of cb0ff8b / 235f4a3 / 0e29ed5 — three changes
# self-classified Lightweight, shipped, reviewed, reverted (5f8004f). The rule was correct and
# was prose.
run_shell_phase test-lane-router.sh          "lane-router"
run_shell_phase test-newline-preserve.sh     "newline-preserve"
run_shell_phase test-baseline-merge.sh       "baseline-merge"
run_shell_phase test-sync-allowlist.sh       "sync-allowlist"
run_shell_phase test-policy-state-preserve.sh "policy-state"
run_shell_phase test-bootstrap-baseline-hop.sh "bootstrap-baseline-hop"
run_shell_phase test-fr22-delivery-guarantee.sh "fr22-delivery"
run_shell_phase test-po-verifiable-boot.sh     "po-verifiable-boot"
run_shell_phase test-po-investigate.sh         "po-investigate"
run_shell_phase test-liveness-bounded-run.sh   "liveness"
run_shell_phase test-codex-prompt-parity.sh    "codex-parity"
run_shell_phase test-codex-plugin-surface.sh   "codex-plugin"
run_shell_phase test-cli-0259-compat.sh        "cli-0259"
run_shell_phase test-secret-scan-staged.sh     "secret-scan-staged"
run_shell_phase test-bootstrap-exception.sh    "bootstrap-exception"
run_shell_phase test-trusted-enforcer.sh       "trusted-enforcer"
run_shell_phase test-hook-install-rc.sh        "hook-install-rc"
run_shell_phase test-msys-tree-cleanup.sh      "msys-tree-cleanup"
run_shell_phase test-ws5-upgrade-bounded.sh    "ws5-upgrade"
run_shell_phase test-ff-only.sh                "ff-only"
run_shell_phase test-return-budget.sh          "return-budget"
run_shell_phase test-supersede-primitive.sh    "supersede-primitive"
run_shell_phase test-rule-inventory.sh         "rule-inventory"
run_shell_phase test-boot-size.sh              "boot-size"
run_shell_phase test-prohibition-residency.sh  "prohibition-residency"
run_shell_phase test-token-waste-classify.sh   "token-waste-classify"
run_shell_phase test-budget-literals.sh        "budget-literals"
run_shell_phase test-history-extraction.sh     "history-extraction"
run_shell_phase test-approval-binding.sh       "approval-binding"
run_shell_phase test-approval-writer.sh        "approval-writer"
run_shell_phase test-command-policy.sh        "command-policy"
run_shell_phase test-upgrade-conflict-classification.sh "upgrade-classify"
run_shell_phase test-upgrade-source-boundary.sh         "upgrade-boundary"
run_shell_phase test-upgrade-preboundary-consumed-tree.sh "preboundary-consumed"
run_shell_phase test-upgrade-repair-managed.sh           "upgrade-repair"
run_shell_phase test-recovery-hint-honesty.sh            "recovery-hint"
run_shell_phase test-install-fusebase-cli-project-doc.sh "install-doc"
# Pins the shipped prose to the machinery: CI on the tagged SHA owns release evidence, no
# local run does. Grep-based by nature — the claim is textual (see that file's header).
run_shell_phase test-release-evidence-authority.sh      "release-authority"
# OPT-IN ONLY (FF_OPTIN_TAGS) — never in the default/required set. Drives the observability
# seam with synthetic milestones: it does NOT run the heavy cli-flow-recovery phase below, so
# it can never be read as evidence about that phase's result or runtime.
run_shell_phase test-cli-flow-recovery-profile.sh       "cli-flow-profile"
# S2 signal lifecycle (T4): the orphan-sentinel discriminator set. HEAVY + fault-injection, so it
# lives in the CI/FF_FULL tier, not the fast local default (architecture-review Q3/Q4: Windows/MSYS
# CI owns it). Off-MSYS it skips every row — the defect class is MSYS-only.
run_shell_phase test-run-tests-signal-reap.sh           "signal-reap"

# Exit-code phase — all-or-nothing shell tests that fail-fast (set -e + fail()→exit)
# and don't emit the run_shell_phase "PASS: <tag> <name>" contract. One row per test;
# PASS iff exit 0. test-cli-flow-recovery.sh is heavy (copies the skill tree + drives
# the health engine — minutes) and was UNBOUNDED, so it hung the whole harness on
# MSYS (the universal run-tests-never-completes defect). Now bounded via
# ffhc_run_bounded_stdout at FF_CLI_RECOVERY_TIMEOUT (default 900s) with an
# FF_SKIP_CLI_RECOVERY=1 opt-out; a timeout (rc 124/137) is reported INCONCLUSIVE —
# counted as a non-pass so the suite never goes silently green on a bound-hit.
# TRIPWIRE: the bound tracks repo SIZE, not this test's correctness — it copies the whole
# skill tree, so every added skill/test/fixture lengthens it (199s at T11 → 304s at T24 →
# 542s measured to completion on a quiet MSYS host at M13, 31/31 assertions, exit 0). Set it
# with headroom, never to the measured edge: 240s and then 480s were each the measured edge,
# and each was crossed by ordinary repo growth one ticket later.
run_exitcode_phase() { # run_exitcode_phase <test-script> <tag> <label>
    local script="$ROOT/hooks/tests/$1" tag="$2" label="$3"
    ff_selected "$tag" || { ff_skip_note "$tag"; return 0; }
    [ -f "$script" ] || return 0
    total=$((total + 1))
    if [ "${FF_SKIP_CLI_RECOVERY:-0}" = "1" ]; then
        # Operator opt-out of the heavy phase. Not a pass (keeps the count honest) —
        # a visible INCONCLUSIVE row, never a silent green.
        fail=$((fail + 1)); echo "INCONCLUSIVE: $label (skipped via FF_SKIP_CLI_RECOVERY=1)"
        report_rows="$report_rows| $1 | $label | INCONCLUSIVE | skipped (FF_SKIP_CLI_RECOVERY=1) |"$'\n'
        return 0
    fi
    progress "$label"
    local _t0=$SECONDS
    ffhc_run_bounded_stdout "${FF_CLI_RECOVERY_TIMEOUT:-900}" bash "$script"
    local rc=$FFHC_LAST_RC
    printf '[run-tests] %s took %ss\n' "$label" "$((SECONDS - _t0))" >&2   # D14.1 per-phase wall time
    FFHC_LAST_WINPID=""; FFHC_LAST_CHILD_PID=""   # phase returned => child reaped; no stale sweep on exit
    if [ "$rc" -eq 0 ]; then
        pass=$((pass + 1)); echo "PASS: $label (exit 0)"
        report_rows="$report_rows| $1 | $label | PASS | exit 0 |"$'\n'
    elif ffhc_timed_out "$rc"; then
        # Bound-hit on a loaded/slow host: INCONCLUSIVE, not FAIL and NOT silent-green.
        fail=$((fail + 1)); echo "INCONCLUSIVE: $label (bounded timeout rc $rc at ${FF_CLI_RECOVERY_TIMEOUT:-900}s — re-run on a quiet host or FF_SKIP_CLI_RECOVERY=1)"
        report_rows="$report_rows| $1 | $label | INCONCLUSIVE | bounded timeout rc $rc |"$'\n'
    else
        fail=$((fail + 1)); echo "FAIL: $label (exit $rc)"
        report_rows="$report_rows| $1 | $label | FAIL | exit $rc |"$'\n'
    fi
}
run_exitcode_phase test-cli-flow-recovery.sh "cli-flow-recovery" "cli-flow-recovery (0.25.9-era wired-set model; unchanged through 0.25.16)"

# Write report. Unscoped => byte-identical to today. Scoped => a distinct title +
# an FF_ONLY banner line so the scoped file can never be mistaken for a full-gate report.
{
    if [ "$FF_SCOPED" -eq 1 ]; then
        echo "# Hook test results — SCOPED (FF_ONLY=${FF_ONLY})"
        echo
        echo "SUBSET RUN — not a full gate. No local run is release evidence; the CI verify job on the tagged SHA is."
        echo
    elif [ "$FF_ATTESTING" -eq 0 ]; then
        echo "# Hook test results — FAST LOCAL DEFAULT (${#FF_FAST_TAGS[@]} of ${#FF_TAGS[@]} phases)"
        echo
        echo "SUBSET RUN — heavy phases skipped. No local run is release evidence; the CI verify job on the tagged SHA is. Full local set: FF_FULL=1."
        echo
    else
        echo "# Hook test results"
        echo
    fi
    echo "Run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "Total: $total — PASS: $pass — FAIL: $fail"
    echo
    echo "| Fixture | Test | Result | Detail |"
    echo "|---|---|---|---|"
    echo -n "$report_rows"
    # C4 / FR-27: a FAIL must be diagnosable from THIS artifact alone. Only present when a phase
    # failed, so a clean run's file stays byte-identical to before.
    if [ -n "$diag_blocks" ]; then
        echo
        echo "## Failure diagnostics"
        echo
        echo "Unparsed output of each FAILING phase (the reason strings the ^PASS:/^FAIL: parse drops)."
        echo
        printf '%s' "$diag_blocks"
    fi
} > "$RESULTS_FILE"

echo
# Summary line. ATTESTING (full unscoped) => the strict "[run-tests] N/N PASS" shape that
# ffhc_run_tests_pass_ok / ffhc_count_pass_lines accept as a clean full pass. Every subset
# form => a DELIBERATELY non-strict line (trailing parenthetical) so those classifiers read
# it as NOT a clean full pass — fail-closed by construction, not by convention.
if [ "$FF_SCOPED" -eq 1 ]; then
    echo "[run-tests] $pass/$total PASS (SCOPED FF_ONLY=${FF_ONLY} — subset, not a full gate)"
elif [ "$FF_ATTESTING" -eq 0 ]; then
    echo "[run-tests] $pass/$total PASS (FAST LOCAL DEFAULT — subset, not a full gate; FF_FULL=1 for the full set)"
else
    echo "[run-tests] $pass/$total PASS"
fi
echo "[run-tests] report written: $RESULTS_FILE"

if [ "$fail" -gt 0 ]; then
    exit 1
else
    exit 0
fi
