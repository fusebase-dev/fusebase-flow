#!/usr/bin/env bash
# Simulate a FuseBase CLI agent-asset refresh followed by Fusebase Flow recovery.
# The test proves ownership behavior, not exact CLI wording.
#
# Entry point only. The 32 predicates live in four sourced modules (step 4 of
# docs/specs/backlog-triage-execution/architecture-review.md § Q2 — "delete the monolithic phase
# after a 31-to-new-test coverage map proves every predicate has an owner"):
#
#   cli-flow-recovery-fixture.sh   reduced synthetic fixture builders (no per-file cp/mkdir loops)
#   cli-flow-recovery-e2e.sh       the ONE complete tree: recover -> wire -> refresh -> preserve
#   cli-flow-recovery-classify.sh  12 isolated read-only classification fixtures
#   cli-flow-recovery-engine.sh    3 isolated main-health-engine drives
#   cli-flow-recovery-direct.sh    direct-helper tests, legacy migration, and the U20 upgrade
#
# TRIPWIRE — the suite budget is FORK COUNT, not bytes: an MSYS process spawn costs ~0.6s, so the
# old 34-skill fixture made mirror-skills alone ~125s on EVERY recovery run. Adding a canonical
# skill, a per-file cp loop, or another `cp -R "$PROJECT"` puts the minutes straight back.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: cli-flow-recovery <name>" / "FAIL: cli-flow-recovery <name>"; exit = fail count.
# Step 7 moved this phase off the single-row exit-code treatment: 32 predicates now report as 32
# rows, so a red run names the predicate instead of one opaque "exit 1".

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

# Public diagnostic groups run the real fixture functions under the same tempfile-based timeout
# owner as the registered suite. TRIPWIRE: parse before TMP_BASE is created, and keep selected
# result rows SCOPED so they cannot satisfy run-tests.sh's full-phase PASS parser.
FFCF_GROUPS=(u14 legacy engine t1 t14 t15 t20)
ffcf_selector_error() { echo "[cli-flow-recovery] ERROR: $*" >&2; exit 2; }

FFCF_SELECTED=""
FFCF_CLI_SELECTED=""
FFCF_LIST=0
case "$#" in
  0) ;;
  1)
    [ "$1" = "--list" ] || ffcf_selector_error "unknown argument '$1'"
    FFCF_LIST=1
    ;;
  2)
    [ "$1" = "--only" ] || ffcf_selector_error "unknown argument '$1'"
    [ -n "$2" ] || ffcf_selector_error "--only requires a non-empty group"
    FFCF_CLI_SELECTED="$2"
    ;;
  *) ffcf_selector_error "usage: $0 [--list | --only <group>]" ;;
esac

FFCF_LEGACY_COUNT=0
FFCF_LEGACY_SELECTED=""
for ffcf_spec in FFCF_T1_ONLY:t1 FFCF_T14_ONLY:t14 FFCF_T15_ONLY:t15 FFCF_T20_ONLY:t20; do
  ffcf_var="${ffcf_spec%%:*}"
  if [ "${!ffcf_var:-0}" = "1" ]; then
    FFCF_LEGACY_COUNT=$((FFCF_LEGACY_COUNT + 1))
    FFCF_LEGACY_SELECTED="${ffcf_spec#*:}"
  fi
done

if [ -n "${FFCF_SELECTOR_CHILD:-}" ]; then
  [ -n "$FFCF_CLI_SELECTED" ] && [ "$FFCF_SELECTOR_CHILD" = "$FFCF_CLI_SELECTED" ] \
    || ffcf_selector_error "invalid internal selector identity"
  FFCF_SELECTED="$FFCF_CLI_SELECTED"
elif [ "$FFCF_LEGACY_COUNT" -gt 1 ]; then
  ffcf_selector_error "legacy selectors conflict; choose exactly one"
elif [ "$FFCF_LIST" -eq 1 ] && [ "$FFCF_LEGACY_COUNT" -ne 0 ]; then
  ffcf_selector_error "--list conflicts with a legacy selector"
elif [ -n "$FFCF_CLI_SELECTED" ] && [ "$FFCF_LEGACY_COUNT" -ne 0 ]; then
  ffcf_selector_error "--only conflicts with a legacy selector"
elif [ -n "$FFCF_CLI_SELECTED" ]; then
  FFCF_SELECTED="$FFCF_CLI_SELECTED"
elif [ "$FFCF_LEGACY_COUNT" -eq 1 ]; then
  FFCF_SELECTED="$FFCF_LEGACY_SELECTED"
fi

if [ "$FFCF_LIST" -eq 1 ]; then
  printf '%s\n' "${FFCF_GROUPS[@]}"
  exit 0
fi
if [ -n "$FFCF_SELECTED" ]; then
  case " ${FFCF_GROUPS[*]} " in
    *" $FFCF_SELECTED "*) ;;
    *) ffcf_selector_error "unknown group '$FFCF_SELECTED' (valid: ${FFCF_GROUPS[*]})" ;;
  esac
fi

ffcf_selector_cleanup() {
  case "$1" in
    /tmp/fusebase-flow-cli-sim.*|/tmp/*/fusebase-flow-cli-sim.*|*/tmp/fusebase-flow-cli-sim.*|*/tmp/*/fusebase-flow-cli-sim.*|*/Temp/fusebase-flow-cli-sim.*|*/Temp/*/fusebase-flow-cli-sim.*)
      rm -rf "$1"
      ;;
  esac
}

if [ -n "$FFCF_SELECTED" ] && [ -z "${FFCF_SELECTOR_CHILD:-}" ]; then
  FFCF_SELECTOR_TIMEOUT_SECS="${FFCF_SELECTOR_TIMEOUT_SECS:-900}"
  case "$FFCF_SELECTOR_TIMEOUT_SECS" in
    ''|*[!0-9]*|0) ffcf_selector_error "FFCF_SELECTOR_TIMEOUT_SECS must be a positive integer" ;;
  esac
  # shellcheck source=/dev/null
  . "$ROOT/hooks/local/lib/run-with-timeout.sh"
  ffhc_detect_timeout
  FFHC_HEARTBEAT_SECS="${FFCF_SELECTOR_HEARTBEAT_SECS:-30}"
  FFCF_SELECTOR_TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-cli-sim.$$.$FFCF_SELECTED"
  export FFCF_SELECTOR_CHILD="$FFCF_SELECTED" FFCF_SELECTOR_TMP_BASE
  ffcf_started="$(date +%s)"
  printf '[cli-flow-recovery] SCOPED group=%s START elapsed=0s timeout=%ss\n' \
    "$FFCF_SELECTED" "$FFCF_SELECTOR_TIMEOUT_SECS" >&2
  # run-with-timeout owns nonzero child/wait statuses. Keep errexit out of that owner so its
  # MSYS heartbeat reap can publish FFHC_LAST_RC before this wrapper decides the group verdict.
  set +e
  ffhc_run_bounded "$FFCF_SELECTOR_TIMEOUT_SECS" bash "$0" --only "$FFCF_SELECTED"
  ffcf_rc="$FFHC_LAST_RC"
  set -e
  [ -z "$FFHC_LAST_OUT" ] || printf '%s\n' "$FFHC_LAST_OUT"
  ffcf_elapsed=$(( $(date +%s) - ffcf_started ))
  printf '[cli-flow-recovery] SCOPED group=%s END elapsed=%ss rc=%s\n' \
    "$FFCF_SELECTED" "$ffcf_elapsed" "$ffcf_rc" >&2
  if [ "$ffcf_rc" -ne 0 ]; then
    ffcf_log="${TMPDIR:-/tmp}/fusebase-flow-cli-recovery-${FFCF_SELECTED}-$$.log"
    {
      printf 'group=%s rc=%s elapsed=%ss\n' "$FFCF_SELECTED" "$ffcf_rc" "$ffcf_elapsed"
      printf '%s\n' "$FFHC_LAST_OUT"
    } > "$ffcf_log"
    printf '[cli-flow-recovery] SCOPED diagnostic=%s\n' "$ffcf_log" >&2
  fi
  ffcf_selector_cleanup "$FFCF_SELECTOR_TMP_BASE"
  exit "$ffcf_rc"
fi

TMP_BASE="${FFCF_SELECTOR_TMP_BASE:-${TMPDIR:-/tmp}/fusebase-flow-cli-sim.$$}"
PROJECT="$TMP_BASE/project"
# The suite's ONE full-tree clone, taken from $PROJECT at the freshly-recovered point (E2E) and
# consumed by the U20 migration. See the tripwire in cli-flow-recovery-e2e.sh.
FFCF_SNAPSHOT="$TMP_BASE/recovered-snapshot"
OUT="$TMP_BASE/recovery.out"

cleanup() {
  case "$TMP_BASE" in
    /tmp/fusebase-flow-cli-sim.*|*/tmp/fusebase-flow-cli-sim.*|*/Temp/fusebase-flow-cli-sim.*)
      rm -rf "$TMP_BASE"
      ;;
  esac
}
trap cleanup EXIT

# S1 (cli-0298-compatibility): the health engine now probes `fusebase --version`; a CLI absent
# from PATH is PARTIAL_UNVERIFIED (exit 4). U17/U18 assert the MAIN engine reads specific CLI
# gaps as benign HEALTHY, so they need an in-range CLI present or they would measure the
# version gate instead of the ownership classification they exist to test.
# TRIPWIRE: prepend, never replace PATH — python3/git/timeout must stay reachable.
mkdir -p "$TMP_BASE/_clibin"
printf '#!/usr/bin/env bash\necho 0.29.8\n' > "$TMP_BASE/_clibin/fusebase"
chmod +x "$TMP_BASE/_clibin/fusebase"
export PATH="$TMP_BASE/_clibin:$PATH"

# Result reporters, shared by the five sourced modules. Ordinary per-test timing is sufficient
# now that the phase is decomposed — the S3A instrumentation seam that used to own these was a
# temporary diagnostic and was deleted in step 7 (architecture-review Q3: it proved trace schema,
# containment and redaction, never recovery correctness, and its own review produced truncation,
# secret-leak and symlink findings).
# TRIPWIRE: `fail` exits, so a red run stops at the FIRST failing predicate and the rows after it
# are absent rather than green. That is deliberate — these scenarios share a fixture tree, so a
# failure invalidates what follows. run_shell_phase's crash guard turns the nonzero exit into a
# counted FAIL even if no row was printed.
if [ -n "$FFCF_SELECTED" ]; then
  echo "SCOPED: cli-flow-recovery group=$FFCF_SELECTED; not full-suite evidence"
  pass() { echo "SCOPED PASS: cli-flow-recovery $*"; }
  fail() { echo "SCOPED FAIL: cli-flow-recovery $*" >&2; exit 1; }
else
  pass() { echo "PASS: cli-flow-recovery $*"; }
  fail() { echo "FAIL: cli-flow-recovery $*" >&2; exit 1; }
fi

sha_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  python_bin="python"
fi

mkdir -p "$PROJECT"

. "$ROOT/hooks/tests/cli-flow-recovery-fixture.sh"
. "$ROOT/hooks/tests/cli-flow-recovery-e2e.sh"
. "$ROOT/hooks/tests/cli-flow-recovery-classify.sh"
. "$ROOT/hooks/tests/cli-flow-recovery-engine.sh"
. "$ROOT/hooks/tests/cli-flow-recovery-direct.sh"

if [ -n "$FFCF_SELECTED" ]; then
  case "$FFCF_SELECTED" in
    u14) ffcf_u14_wire_stop ;;
    legacy) ffcf_legacy_overlays ;;
    engine) ffcf_engine_run ;;
    t1) ffcf_t1_overlay_spans ;;
    t14) ffcf_t14_preflight; ffcf_t14_progress_ledger ;;
    t15) ffcf_t15_verification ;;
    t20) ffcf_t20_repeated_noop ;;
  esac
  exit 0
fi

ffcf_e2e_run
ffcf_classify_run
ffcf_engine_run
ffcf_direct_run
