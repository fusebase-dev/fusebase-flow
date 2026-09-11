#!/usr/bin/env bash
# Fusebase Flow — invocation preconditions for hooks/tests/run-tests.sh (sourced; shares its
# globals). Each check returns non-zero BEFORE any phase runs and the runner exits 2.
# Suite: hooks/tests/test-run-preconditions.sh (tag run-preconditions).

# ff_hosted: the ONE definition of a hosted CI run. TRIPWIRE: it both selects the full tier by
# default AND exempts ff_require_evidence_gap — two copies could disagree and redden release CI.
# GitHub Actions sets GITHUB_ACTIONS=true and CI=true on every step, Git Bash included.
ff_hosted() { [ "${GITHUB_ACTIONS:-}" = "true" ] || [ "${CI:-}" = "true" ]; }

# ff_parse_release_mode: sets FF_RELEASE_RUN; FF_RELEASE is 0/1 and never combined with a selector.
ff_parse_release_mode() {
  FF_RELEASE_RUN=0
  case "${FF_RELEASE:-0}" in
    0|'') ;;
    1) FF_RELEASE_RUN=1 ;;
    *) echo "[run-tests] ERROR: FF_RELEASE must be 0 or 1" >&2; return 2 ;;
  esac
  if [ "$FF_RELEASE_RUN" -eq 1 ] \
      && { [ "$FF_SCOPED" -eq 1 ] || [ "${FF_FULL:-0}" != "0" ]; }; then
    echo "[run-tests] ERROR: FF_RELEASE cannot be combined with FF_ONLY or FF_FULL" >&2
    return 2
  fi
}

# ff_require_evidence_gap: a LOCAL full or release-profile run in the maintainer tree must name
# the evidence gap focused groups cannot answer (docs/maintainer-testing.md § Execution and
# completion). The reason is recorded, never judged. Consumer trees (no maintainer doc — the
# preflight §11 scope) and hosted CI are exempt, so the health deep run and release CI are unchanged.
ff_require_evidence_gap() {
  { [ "$FF_ATTESTING" -eq 1 ] || [ "$FF_RELEASE_RUN" -eq 1 ]; } || return 0
  [ -f "$ROOT/docs/maintainer-testing.md" ] || return 0
  ff_hosted && return 0
  local gap="${FF_EVIDENCE_GAP:-}"
  if [ -n "${gap//[[:space:]]/}" ]; then
    printf '[run-tests] FF_EVIDENCE_GAP: %s\n' "$gap" >&2
    return 0
  fi
  {
    echo "[run-tests] REFUSED: local FF_FULL/FF_RELEASE needs a nonempty FF_EVIDENCE_GAP (maintainer tree)."
    echo "  Run the affected groups:  FF_ONLY=tag1,tag2 bash hooks/tests/run-tests.sh   (FF_LIST=1 lists tags)"
    echo "  Or name the gap:          FF_EVIDENCE_GAP=\"<why focused groups cannot answer this>\" FF_FULL=1 bash hooks/tests/run-tests.sh"
    echo "  No local run is release evidence; the tagged-SHA CI gate is. See docs/maintainer-testing.md."
  } >&2
  return 2
}
