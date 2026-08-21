#!/usr/bin/env bash
# Fusebase Flow — cli-flow-recovery: MAIN HEALTH ENGINE module (sourced, never run).
# WHY-home: docs/specs/backlog-triage-execution/architecture-review.md § Q2 (step 4).
#
# TRIPWIRE — "two engines agree" is the whole point of this module: the main engine folds only
# the conflict reporter's MISSING/DRIFT, so every INFO class the classify module proves benign
# must ALSO stay out of the engine's verdict. Deleting a scenario here without deleting its
# classify twin leaves the two engines free to disagree again.
#
# TRIPWIRE — each tree is built fresh and stamped before the engine runs; the stamp is what makes
# hook-manifest-verify an integrity-critical MATCH rather than an UNVERIFIED that masks the
# verdict under test.

ffcf_engine_tree() {
  local d="$1"
  ffcf_conflict_tree "$d"
  cp hooks/local/fusebase-flow-health-check.sh hooks/local/stamp-hook-manifest.sh \
     hooks/local/verify-hook-manifest.sh "$d/hooks/local/"
  cp VERSION "$d/VERSION"   # the engine reads VERSION at repo root
  # Same reason the hook manifest is stamped above (see this file's second tripwire): the engine
  # now also inspects the MANAGED-CONTENT base, and an absent base is a real, reportable state
  # (N6-D2 State 1 — the pre-exposure tree that must be routed to bootstrap-upgrade.sh). Without
  # this stamp every scenario here would carry an unrelated missing-base finding and the verdict
  # under test would be masked by fixture incompleteness — finding F-N5-2's lesson exactly: a
  # fixture that omits what a real install has does not test a weaker system, it tests a
  # different one.
  cp hooks/local/lib/managed_content_manifest.py "$d/hooks/local/lib/" 2>/dev/null || true
  ( cd "$d" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null 2>&1 ) || true
}

# Generous per-check budgets: this asserts the VERDICT, never the host's speed. `|| true` plus
# the budgets keep an exit 4 (UNVERIFIED) from aborting the suite before the assertion runs.
ffcf_engine_out() { # ffcf_engine_out <tree> <out-file>
  ( cd "$1" || exit 1
    bash hooks/local/stamp-hook-manifest.sh >/dev/null 2>&1
    FFHC_PREFLIGHT_TIMEOUT=600 FFHC_TESTS_TIMEOUT=600 FFHC_CONFLICT_TIMEOUT=600 \
    FFHC_MANIFEST_TIMEOUT=600 FFHC_FETCH_TIMEOUT=30 \
    bash hooks/local/fusebase-flow-health-check.sh > "$2" 2>&1 ) || true
}

ffcf_engine_verdict() { # ffcf_engine_verdict <tree> -> the Verdict line
  ffcf_engine_out "$1" "$TMP_BASE/engine.out"
  grep -m1 "^Verdict:" "$TMP_BASE/engine.out" || echo "Verdict: (none captured)"
}

ffcf_engine_run() {
  local d v

  # F2 (U16) — the MAIN engine (not just the conflict checker) must read deliberate hooks-off as
  # benign (U11 consistency): an overlay-only install (CLI hooks present, no Flow stop.py, no
  # clobber) must NOT be SHARED_MERGE_DRIFT.
  d="$TMP_BASE/f2-engine-hooksoff"; ffcf_engine_tree "$d"; ffcf_settings_hooksoff "$d"
  ffcf_engine_out "$d" "$TMP_BASE/f2.out"
  grep -q "Verdict: SHARED_MERGE_DRIFT" "$TMP_BASE/f2.out" && { sed -n '/Verdict/,$p' "$TMP_BASE/f2.out" >&2; fail "F2: main health engine verdict SHARED_MERGE_DRIFT for deliberate hooks-off (should be benign)"; } || true
  grep -qE "lifecycle events wired \(stop.py present|stop.py missing from Stop chain" "$TMP_BASE/f2.out" && fail "F2: main engine recorded a settings.json drift for the opt-in-off state" || true
  grep -q "Flow lifecycle hooks not wired (opt-in" "$TMP_BASE/f2.out" || fail "F2: main engine did not emit the benign opt-in note for hooks-off"
  pass "F2 (U16): main health engine reads deliberate hooks-off as benign (no SHARED_MERGE_DRIFT)"

  # U17 — flag-gated absence (the U10 class) must not surface as engine drift.
  d="$TMP_BASE/u17-engine-flaggated"; ffcf_engine_tree "$d"
  rm -rf "$d/.claude/skills/managed-integrations" "$d/.agents/skills/managed-integrations"
  v="$(ffcf_engine_verdict "$d")"
  case "$v" in
    *CLI_LAYER_DRIFT*) fail "U17: main engine $v for a flag-gated absence (should be benign)";;
    *HEALTHY*) : ;;
    *) fail "U17: unexpected main-engine '$v' (expected HEALTHY)";;
  esac
  pass "U17: main health engine reads a flag-gated CLI skill absence as benign (HEALTHY)"

  # U18 — the .agents/.codex CLI-provider gap (the U13 class) must not surface as engine drift.
  d="$TMP_BASE/u18-engine-agentsgap"; ffcf_engine_tree "$d"
  rm -rf "$d/.agents/skills/app-backend" "$d/.agents/skills/app-routing" \
         "$d/.agents/skills/app-secrets" "$d/.agents/skills/app-sidecar" \
         "$d/.agents/skills/app-ui-design"
  v="$(ffcf_engine_verdict "$d")"
  case "$v" in
    *CLI_LAYER_DRIFT*) fail "U18: main engine $v for a .agents CLI-provider gap (should be benign)";;
    *HEALTHY*) : ;;
    *) fail "U18: unexpected main-engine '$v' (expected HEALTHY)";;
  esac
  pass "U18: main health engine reads a non-authoritative .agents CLI-provider gap as benign (HEALTHY)"
}
