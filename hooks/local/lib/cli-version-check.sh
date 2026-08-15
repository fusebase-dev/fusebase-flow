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
#     exactly a reviewed version    -> LOCAL_OK                (HEALTHY / 0)
#     below the incompatible line   -> LOCAL_DRIFT + CLI_VERSION_UNSUPPORTED
#                                                              (NOT HEALTHY / exit 1)
#     any other version (unreviewed)-> LOCAL_UNVERIFIED        (PARTIAL_UNVERIFIED / 4)
#     `fusebase --version` rc != 0  -> LOCAL_UNVERIFIED        (PARTIAL_UNVERIFIED / 4)
#     no unambiguous version        -> LOCAL_UNVERIFIED        (PARTIAL_UNVERIFIED / 4)
#     not on PATH / timed out       -> LOCAL_UNVERIFIED        (PARTIAL_UNVERIFIED / 4)
#
#   Why unreviewed is 4 and not 1: the CLI ships ~4 minors per 5 weeks and Flow's
#   vendoring is operator-supplied trees, so Flow ALWAYS trails. A hard red on every
#   CLI release day — with a remediation that cannot work yet, because no Flow
#   release has reviewed the new version — trains operators to widen the reviewed set
#   unreviewed, which kills the check outright. Exit 4 also keeps CI and any host
#   without the CLI installed from being permanently red.
#
#   Everything that is not positively known is UNVERIFIED. This function must never
#   emit LOCAL_OK on a guess: an unreadable, ambiguous, failed or unreviewed probe is
#   exit 4, because the defect class this check closes (F1) was precisely a health
#   report that returned green when it had not established anything.
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
# The EXACT versions whose tree was reviewed against these vendored assets. Space-separated;
# a version earns a place here only by a re-vendor that actually compared it.
#
# TRIPWIRE — this is a SET, not a range, and the difference is load-bearing. A `>=0.29.0
# <0.30.0` range greened every future 0.29.x the moment it was written: a not-yet-released
# 0.29.9 would report HEALTHY against assets nobody had compared to it. On a pre-1.0 CLI
# shipping ~4 minors per 5 weeks, "every future patch of this minor is compatible" is not an
# earned guarantee — it is the same unbacked claim as the `source_cli_version: "unknown"`
# sentinel this ticket retired. Unreviewed is exit 4 (partial), never exit 0.
FFHC_CLI_REVIEWED_VERSIONS="0.29.8"

# Below this, the vendored guidance is INCOMPATIBLE, not merely unreviewed (exit 1).
# Verified at 0.25.16: `--app` resolves by local path only, and Flow's vendored commands were
# unrendered ETA templates. The minor boundary is the conservative generalization of that
# verified point — never widen it without evidence for the version you are excusing.
FFHC_CLI_INCOMPATIBLE_BELOW="0.29.0"
FFHC_CLI_VERSION_TIMEOUT="${FFHC_CLI_VERSION_TIMEOUT:-10}"

# ffhc_cli_range_text: the one human-readable policy string, so every message quotes the SAME
# policy (a non-green outcome must state version found + what is reviewed + next step).
ffhc_cli_range_text() {
  printf 'Reviewed version(s): %s (exact). Below %s is incompatible; every other version is unreviewed' \
    "$FFHC_CLI_REVIEWED_VERSIONS" "$FFHC_CLI_INCOMPATIBLE_BELOW"
}

# ffhc_cli_version_is_reviewed <version> -> rc 0 iff it is an exact member of the reviewed set.
ffhc_cli_version_is_reviewed() {
  local v
  for v in $FFHC_CLI_REVIEWED_VERSIONS; do
    [ "$v" = "$1" ] && return 0
  done
  return 1
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

# ffhc_cli_version_parse <raw> -> echoes the version, or empty when the output does not
# unambiguously declare exactly one.
#
# TRIPWIRE — WHOLE-LINE match, never an embedded token. `fusebase --version` has exactly
# two documented shapes (lib/version-output.ts): a bare "0.29.8", or a launcher block whose
# version line is "FuseBase CLI 0.29.8". An earlier version of this function took the FIRST
# three-component token anywhere in the output, which fails OPEN on real output: this host
# prints "A launcher update is available. Run `fusebase update --launcher` ..." BEFORE the
# version, so any line carrying an in-range-looking number — an update notice advertising
# 0.29.8 while the installed CLI is 0.25.16 — was read as the installed version and reported
# HEALTHY. Only full lines matching a documented shape count.
#
# TRIPWIRE — EXACTLY THREE numeric components, no suffix. `0.29.8-beta.1`, `0.29.8+build`,
# `0.29.8.1` and `0.29.8garbage` are NOT the reviewed 0.29.8; the old comparator stripped the
# suffix and greened them. They match no shape here, so they land in the unverified bucket.
#
# Ambiguity (two different versions both declared in a documented shape) is unverified too —
# picking one would be a guess, and a guess in this function is the fail-open.
ffhc_cli_version_parse() {
  local found
  found="$(printf '%s' "$1" | tr -d '\r' \
    | sed -nE 's/^[Ff]use[Bb]ase CLI ([0-9]+\.[0-9]+\.[0-9]+)$/\1/p; s/^([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' \
    | sort -u)"
  [ "$(printf '%s' "$found" | grep -c .)" = "1" ] || return 0
  printf '%s' "$found"
}

# ffhc_cli_version_check: probe the installed CLI and classify. Read-only; bounded
# (a wedged `fusebase` must not hang a read-only diagnostic — FR-27).
ffhc_cli_version_check() {
  local range found raw rc
  range="$(ffhc_cli_range_text)"

  if ! command -v fusebase >/dev/null 2>&1; then
    LOCAL_UNVERIFIED+=("CLI version compatibility: UNVERIFIED — \`fusebase\` is not on PATH, so the installed CLI version could not be read. $range. Next step: install/activate the FuseBase Apps CLI in this environment and re-run, or ignore on a host that never runs the CLI (this is exit 4, not a failure).")
    return 0
  fi

  ffhc_run_bounded_stdout "$FFHC_CLI_VERSION_TIMEOUT" fusebase --version
  raw="$FFHC_LAST_OUT"; rc="$FFHC_LAST_RC"
  if [ "$FFHC_LAST_TIMED_OUT" -eq 1 ] || [ "$FFHC_LAST_SKIPPED" -eq 1 ]; then
    LOCAL_UNVERIFIED+=("CLI version compatibility: UNVERIFIED — \`fusebase --version\` timed out after ${FFHC_CLI_VERSION_TIMEOUT}s or was skipped (no timeout binary). $range. Next step: run \`fusebase --version\` directly, raise FFHC_CLI_VERSION_TIMEOUT, or install coreutils.")
    return 0
  fi

  # TRIPWIRE: a non-zero exit invalidates the output, whatever it printed. The runner has
  # always recorded FFHC_LAST_RC (run-with-timeout.sh); the first version of this function
  # never read it, so a `fusebase` that failed while printing a version string still produced
  # LOCAL_OK -> HEALTHY. Trusting stdout from a failed process is the fail-open this whole
  # ticket exists to close.
  if [ "$rc" -ne 0 ]; then
    LOCAL_UNVERIFIED+=("CLI version compatibility: UNVERIFIED — \`fusebase --version\` exited $rc, so its output cannot be trusted (printed: $(printf '%s' "$raw" | tr '\n' ' ' | cut -c1-80)). $range. Next step: run \`fusebase --version\` directly and fix the CLI install before relying on this check.")
    return 0
  fi

  found="$(ffhc_cli_version_parse "$raw")"
  if [ -z "$found" ]; then
    LOCAL_UNVERIFIED+=("CLI version compatibility: UNVERIFIED — \`fusebase --version\` declared no single unambiguous version in a documented shape (bare \`X.Y.Z\`, or a \`FuseBase CLI X.Y.Z\` line). Output: $(printf '%s' "$raw" | tr '\n' ' ' | cut -c1-80). $range. Next step: run \`fusebase --version\` directly and report the output.")
    return 0
  fi

  if ffhc_cli_version_is_reviewed "$found"; then
    LOCAL_OK+=("CLI version compatibility: installed $found is a reviewed version ($range)")
    return 0
  fi

  if ffhc_semver_lt "$found" "$FFHC_CLI_INCOMPATIBLE_BELOW"; then
    CLI_VERSION_UNSUPPORTED+=("CLI VERSION UNSUPPORTED — installed FuseBase Apps CLI is $found, below $FFHC_CLI_INCOMPATIBLE_BELOW. The CLI documents this Flow edition vendors are incompatible with it: verified at 0.25.16, \`--app\` is matched by local path (not app id) and the command templates Flow now ships are rendered against the newer CLI. $range. Next step: upgrade the CLI, then re-run this check:")
    CLI_VERSION_UNSUPPORTED+=("  npm install -g fusebase-apps-cli@latest   # or your team's install route")
    LOCAL_DRIFT+=("CLI version compatibility: installed $found is below $FFHC_CLI_INCOMPATIBLE_BELOW and incompatible with the vendored guidance ($range)")
    return 0
  fi

  # Unreviewed but not known-incompatible: exit 4, never a green and never a red.
  LOCAL_UNVERIFIED+=("CLI version compatibility: UNVERIFIED — installed FuseBase Apps CLI is $found, which this Flow edition has NOT reviewed. $range. Nothing is known to be broken; the vendored assets were simply never checked against $found. Next step: supply the $found CLI tree for review so the vendored assets and the reviewed set can be re-stamped.")
}
