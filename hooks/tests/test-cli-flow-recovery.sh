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

# S3A observability seam: pass()/fail() and the timed milestone trace live here, so this
# baselined file gains instrumentation without gaining lines (FR-25). Contract + trace schema:
# docs/specs/backlog-triage-execution/execution-plan.md § S3A.
. "$ROOT/hooks/tests/lib/cli-flow-recovery-profile.sh"
ffcp_init test-cli-flow-recovery.sh

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

ffcf_e2e_run
ffcf_classify_run
ffcf_engine_run
ffcf_direct_run
