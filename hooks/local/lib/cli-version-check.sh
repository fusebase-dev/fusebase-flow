#!/usr/bin/env bash
# Fusebase Flow — installed-CLI version compatibility check (S1 / spec
# docs/specs/cli-0298-compatibility/spec.md).
#
# PROVENANCE:
#   New in the cli-0298-compatibility ticket. Lives at hooks/local/lib/ — outside
#   the FuseBase CLI refresh manifest. Sourced by fusebase-flow-health-check.sh;
#   never run standalone in production.
#
# WHY (F1): before this check, `audit/cli-vendor-manifest.json` carried
#   source_cli_version "unknown" and every CLI advisory was informational, so
#   /fusebase-health returned HEALTHY against ANY installed CLI — including one
#   whose flag semantics Flow's own vendored documents contradict. Four CLI minors
#   drifted (0.25.16 -> 0.29.8) with nothing asserting anything; that silence is
#   what let B1 (`--app <appId>`) and B2 (unrendered `<%=` templates) survive.
#
# CONTRACT (the engine relies on these):
#   ffhc_cli_version_check  -> appends to LOCAL_OK / LOCAL_DRIFT /
#                              CLI_VERSION_UNSUPPORTED / LOCAL_UNVERIFIED in the
#                              CALLER's scope (sourced => shared scope).
#
#   Verdict mapping (the engine's call, mirroring the PARTIAL_UPGRADE precedent):
#     in range          -> LOCAL_OK                       (HEALTHY / 0)
#     below the floor   -> LOCAL_DRIFT + CLI_VERSION_UNSUPPORTED
#                                                         (NOT HEALTHY / exit 1)
#     above the ceiling -> LOCAL_UNVERIFIED               (PARTIAL_UNVERIFIED / 4)
#     unreadable        -> LOCAL_UNVERIFIED               (PARTIAL_UNVERIFIED / 4)
#     not on PATH       -> LOCAL_UNVERIFIED               (PARTIAL_UNVERIFIED / 4)
#
#   Why above-range is 4 and not 1: the CLI ships ~4 minors per 5 weeks and Flow's
#   vendoring is operator-supplied trees, so Flow ALWAYS trails. A hard red on every
#   CLI release day — with a remediation that cannot work yet, because no Flow
#   release has reviewed the new version — trains operators to widen the range
#   unreviewed, which kills the check outright. Exit 4 also keeps CI and the
#   maintainer repo (no `fusebase` installed) from being permanently red.
#
# BLAST RADIUS (deliberate): only THIS signal is verdict-affecting. The four
#   pre-existing CLI advisories (CLI_SNAPSHOT_STALE, CLI_CUSTOM_AT_RISK,
#   CLI_STOP_UNVERIFIED, CLI_STOP_BASELINE_DRIFT) stay informational — flipping four
#   signals fail-closed at once reds every adopter's first health run.

# Reviewed-compatible range, half-open: FLOOR <= installed < CEILING_EXCL.
# TRIPWIRE (FR-07-adjacent): these are DELIBERATELY not env-overridable. An env knob
# here is a silent kill switch — widening the range without re-reviewing a CLI tree is
# exactly the failure mode this check exists to prevent. Widening is a code change, in
# a commit, with the re-vendor that earns it. Tests simulate versions by putting a
# `fusebase` stub on PATH, never by moving these.
FFHC_CLI_REVIEWED_FLOOR="0.29.0"
FFHC_CLI_REVIEWED_CEILING_EXCL="0.30.0"
FFHC_CLI_REVIEWED_AT="0.29.8"          # the exact tree this Flow edition was vendored from
FFHC_CLI_VERSION_TIMEOUT="${FFHC_CLI_VERSION_TIMEOUT:-10}"

# ffhc_cli_range_text: the one human-readable range string, so every message quotes
# the SAME range (a non-green outcome must state version found + reviewed range + next step).
ffhc_cli_range_text() {
  printf '>= %s and < %s (vendored from %s)' \
    "$FFHC_CLI_REVIEWED_FLOOR" "$FFHC_CLI_REVIEWED_CEILING_EXCL" "$FFHC_CLI_REVIEWED_AT"
}

# ffhc_semver_lt A B -> rc 0 iff A < B. Numeric per component; missing components are 0.
ffhc_semver_lt() {
  local a="$1" b="$2" i av bv
  local -a A B
  IFS='.' read -r -a A <<< "${a%%[-+]*}"
  IFS='.' read -r -a B <<< "${b%%[-+]*}"
  for i in 0 1 2; do
    av="${A[$i]:-0}"; bv="${B[$i]:-0}"
    case "$av$bv" in *[!0-9]*) return 1 ;; esac
    [ "$av" -lt "$bv" ] && return 0
    [ "$av" -gt "$bv" ] && return 1
  done
  return 1
}

# ffhc_cli_version_parse <raw> -> echoes the first bare semver found, empty if none.
# TRIPWIRE: `fusebase --version` has TWO shapes (lib/version-output.ts) — a bare
# "0.29.8", or a 3-line launcher block whose first line is "FuseBase CLI 0.29.8".
# Matching the first semver token covers both; an exact-line match silently breaks
# on every Windows launcher install.
ffhc_cli_version_parse() {
  printf '%s' "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# ffhc_cli_version_check: probe the installed CLI and classify. Read-only; bounded
# (a wedged `fusebase` must not hang a read-only diagnostic — FR-27).
ffhc_cli_version_check() {
  local range found raw
  range="$(ffhc_cli_range_text)"

  if ! command -v fusebase >/dev/null 2>&1; then
    LOCAL_UNVERIFIED+=("CLI version compatibility: UNVERIFIED — \`fusebase\` is not on PATH, so the installed CLI version could not be read. Reviewed range: $range. Next step: install/activate the FuseBase Apps CLI in this environment and re-run, or ignore on a host that never runs the CLI (this is exit 4, not a failure).")
    return 0
  fi

  ffhc_run_bounded_stdout "$FFHC_CLI_VERSION_TIMEOUT" fusebase --version
  raw="$FFHC_LAST_OUT"
  if [ "$FFHC_LAST_TIMED_OUT" -eq 1 ] || [ "$FFHC_LAST_SKIPPED" -eq 1 ]; then
    LOCAL_UNVERIFIED+=("CLI version compatibility: UNVERIFIED — \`fusebase --version\` timed out after ${FFHC_CLI_VERSION_TIMEOUT}s or was skipped (no timeout binary). Reviewed range: $range. Next step: run \`fusebase --version\` directly, raise FFHC_CLI_VERSION_TIMEOUT, or install coreutils.")
    return 0
  fi

  found="$(ffhc_cli_version_parse "$raw")"
  if [ -z "$found" ]; then
    LOCAL_UNVERIFIED+=("CLI version compatibility: UNVERIFIED — \`fusebase --version\` returned no readable version (output: $(printf '%s' "$raw" | tr '\n' ' ' | cut -c1-80)). Reviewed range: $range. Next step: run \`fusebase --version\` directly and report the output.")
    return 0
  fi

  if ffhc_semver_lt "$found" "$FFHC_CLI_REVIEWED_FLOOR"; then
    # Known-incompatible: the vendored documents Flow ships were written against
    # $FFHC_CLI_REVIEWED_AT and instruct commands this CLI resolves differently.
    CLI_VERSION_UNSUPPORTED+=("CLI VERSION UNSUPPORTED — installed FuseBase Apps CLI is $found; this Fusebase Flow edition's vendored CLI documents were reviewed against $range. Below the floor the vendored guidance is known-incompatible (e.g. \`--app\` resolution and rendered command templates changed). Next step: upgrade the CLI, then re-run this check:")
    CLI_VERSION_UNSUPPORTED+=("  npm install -g fusebase-apps-cli@latest   # or your team's install route")
    LOCAL_DRIFT+=("CLI version compatibility: installed $found is BELOW the reviewed floor $FFHC_CLI_REVIEWED_FLOOR (reviewed range: $range)")
    return 0
  fi

  if ! ffhc_semver_lt "$found" "$FFHC_CLI_REVIEWED_CEILING_EXCL"; then
    LOCAL_UNVERIFIED+=("CLI version compatibility: UNVERIFIED — installed FuseBase Apps CLI is $found, ABOVE the reviewed ceiling. Reviewed range: $range. Nothing is known to be broken; this Flow edition simply has not reviewed $found. Next step: supply the $found CLI tree for review so Flow's vendored assets and this range can be re-stamped.")
    return 0
  fi

  LOCAL_OK+=("CLI version compatibility: installed $found is within the reviewed range ($range)")
}
