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

TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-cli-sim.$$"
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
pass() { echo "PASS: cli-flow-recovery $*"; }
fail() { echo "FAIL: cli-flow-recovery $*" >&2; exit 1; }

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

if [ "${FFCF_T1_ONLY:-0}" = "1" ]; then
  ffcf_t1_overlay_spans
  exit 0
fi
if [ "${FFCF_T14_ONLY:-0}" = "1" ]; then
  ffcf_t14_preflight
  ffcf_t14_progress_ledger
  exit 0
fi

ffcf_e2e_run
ffcf_classify_run
ffcf_engine_run
ffcf_direct_run
