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
#                              CLI_VERSION_UNSUPPORTED / CLI_VERSION_ADVISORY in the
#                              CALLER's scope (sourced => shared scope).
#
#   Verdict mapping:
#     exactly the bundled snapshot  -> LOCAL_OK                 (HEALTHY / 0)
#     below the incompatible line   -> LOCAL_DRIFT + CLI_VERSION_UNSUPPORTED
#                                                               (NOT HEALTHY / exit 1)
#     any other version             -> CLI_VERSION_ADVISORY     (verdict-neutral / 0)
#     rc != 0 / unreadable / absent -> CLI_VERSION_ADVISORY     (verdict-neutral / 0)
#
#   WHY ONLY ONE HARD FAIL (superseded design, kept because the reasoning matters):
#   this check first hard-failed anything outside a reviewed range, then softened to
#   PARTIAL_UNVERIFIED (exit 4) for everything unreviewed. Both were wrong for the same
#   reason, visible only when you ask what the adopter's tree actually looks like:
#
#     After a FULL `fusebase update`, the CLI rewrites the adopter's provider skills from
#     its OWN current template. Their local documents are then CORRECT for their installed
#     CLI — yet Flow would still report a problem, purely because no FLOW release has
#     reviewed that version. That measures Flow's maintainer review status, not the
#     adopter's compatibility, and it is not the adopter's problem to resolve.
#
#   Exit 4 was also the wrong channel on its own terms: PARTIAL_UNVERIFIED's documented
#   remediation is re-running an incomplete check (fusebase-flow-health-check/SKILL.md),
#   and "supply an upstream CLI tree for review" is a different condition entirely.
#
#   What survives is the ONE claim backed by evidence: below 0.29.0 the vendored documents
#   are known-incompatible (verified at 0.25.16 — `--app` resolves by local path, and the
#   commands Flow ships were unrendered ETA templates). Everything else is advisory.
#
# BLAST RADIUS (deliberate): exactly one verdict-affecting condition. The four pre-existing
#   CLI advisories (CLI_SNAPSHOT_STALE, CLI_CUSTOM_AT_RISK, CLI_STOP_UNVERIFIED,
#   CLI_STOP_BASELINE_DRIFT) stay informational, and the newer/unreadable/absent cases join
#   them rather than becoming a fifth blocker.

# TRIPWIRE (FR-07-adjacent): these are DELIBERATELY not env-overridable. An env knob here is
# a silent kill switch — moving the incompatibility line without evidence for the version
# being excused is exactly the failure mode this check exists to prevent. Changing it is a
# code change, in a commit, with the re-vendor that earns it. Tests simulate versions by
# putting a `fusebase` stub on PATH, never by moving these.
#
# The CLI snapshot these vendored assets were taken from. Reported in every advisory so the
# operator can compare it against what they have installed.
FFHC_CLI_BUNDLED_VERSION="0.29.8"

# Below this, the vendored guidance is INCOMPATIBLE, not merely unreviewed (exit 1).
# Verified at 0.25.16: `--app` resolves by local path only, and Flow's vendored commands were
# unrendered ETA templates. The minor boundary is the conservative generalization of that
# verified point — never widen it without evidence for the version you are excusing.
FFHC_CLI_INCOMPATIBLE_BELOW="0.29.0"
FFHC_CLI_VERSION_TIMEOUT="${FFHC_CLI_VERSION_TIMEOUT:-10}"

# ffhc_cli_range_text: the one human-readable policy string, so every message quotes the SAME
# policy (every outcome must state version found + the bundled snapshot + next step).
ffhc_cli_range_text() {
  printf 'Vendored CLI snapshot: %s. Below %s is known-incompatible (the only hard failure); anything else is advisory' \
    "$FFHC_CLI_BUNDLED_VERSION" "$FFHC_CLI_INCOMPATIBLE_BELOW"
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
    CLI_VERSION_ADVISORY+=("CLI version: not determined — \`fusebase\` is not on PATH. $range. Next step: none required on a host that never runs the CLI (CI, containers, a machine that only edits the framework); install or activate the CLI if you expected it here.")
    return 0
  fi

  ffhc_run_bounded_stdout "$FFHC_CLI_VERSION_TIMEOUT" fusebase --version
  raw="$FFHC_LAST_OUT"; rc="$FFHC_LAST_RC"
  if [ "$FFHC_LAST_TIMED_OUT" -eq 1 ] || [ "$FFHC_LAST_SKIPPED" -eq 1 ]; then
    CLI_VERSION_ADVISORY+=("CLI version: not determined — \`fusebase --version\` timed out after ${FFHC_CLI_VERSION_TIMEOUT}s or was skipped (no timeout binary). $range. Next step: run \`fusebase --version\` directly, raise FFHC_CLI_VERSION_TIMEOUT, or install coreutils.")
    return 0
  fi

  # TRIPWIRE: a non-zero exit invalidates the output, whatever it printed. The runner has
  # always recorded FFHC_LAST_RC (run-with-timeout.sh); the first version of this function
  # never read it, so a `fusebase` that failed while printing a version string still produced
  # LOCAL_OK -> HEALTHY. Trusting stdout from a failed process stays forbidden even though the
  # outcome is now advisory: an advisory that reports a version nobody established is a lie
  # with a softer exit code.
  if [ "$rc" -ne 0 ]; then
    CLI_VERSION_ADVISORY+=("CLI version: not determined — \`fusebase --version\` exited $rc, so its output cannot be trusted (printed: $(printf '%s' "$raw" | tr '\n' ' ' | cut -c1-80)). $range. Next step: run \`fusebase --version\` directly and fix the CLI install.")
    return 0
  fi

  found="$(ffhc_cli_version_parse "$raw")"
  if [ -z "$found" ]; then
    CLI_VERSION_ADVISORY+=("CLI version: not determined — \`fusebase --version\` declared no single unambiguous version in a documented shape (bare \`X.Y.Z\`, or a \`FuseBase CLI X.Y.Z\` line). Output: $(printf '%s' "$raw" | tr '\n' ' ' | cut -c1-80). $range. Next step: run \`fusebase --version\` directly and report the output.")
    return 0
  fi

  if [ "$found" = "$FFHC_CLI_BUNDLED_VERSION" ]; then
    LOCAL_OK+=("CLI version: installed $found matches the vendored CLI snapshot ($range)")
    return 0
  fi

  if ffhc_semver_lt "$found" "$FFHC_CLI_INCOMPATIBLE_BELOW"; then
    CLI_VERSION_UNSUPPORTED+=("CLI VERSION UNSUPPORTED — installed FuseBase Apps CLI is $found, below $FFHC_CLI_INCOMPATIBLE_BELOW. The CLI documents this Flow edition vendors are incompatible with it: verified at 0.25.16, \`--app\` is matched by local path (not app id) and the command templates Flow now ships are rendered against the newer CLI. $range. Next step: upgrade the CLI, then re-run this check:")
    CLI_VERSION_UNSUPPORTED+=("  npm install -g fusebase-apps-cli@latest   # or your team's install route")
    LOCAL_DRIFT+=("CLI version compatibility: installed $found is below $FFHC_CLI_INCOMPATIBLE_BELOW and incompatible with the vendored guidance ($range)")
    return 0
  fi

  # Not the bundled snapshot, but not known-incompatible either — ADVISORY, exit 0.
  # TRIPWIRE: do NOT escalate this. After a full `fusebase update` the adopter's provider
  # skills were rewritten by their own CLI, so their local documents are correct for their
  # installed version; the only thing "unverified" is whether a FLOW maintainer reviewed it.
  # That is Flow's status, not the adopter's problem, and reporting it as a non-green verdict
  # asks them to fix something that is not broken.
  if ffhc_semver_lt "$found" "$FFHC_CLI_BUNDLED_VERSION"; then
    CLI_VERSION_ADVISORY+=("CLI version: installed $found is OLDER than the vendored CLI snapshot $FFHC_CLI_BUNDLED_VERSION. $range. Nothing is known to be broken; the vendored documents may describe behaviour your CLI does not have yet. Next step: upgrade the CLI, or ignore if your workflow does not use the newer surfaces.")
  else
    CLI_VERSION_ADVISORY+=("CLI version: installed $found is NEWER than the vendored CLI snapshot $FFHC_CLI_BUNDLED_VERSION. $range. Nothing is known to be broken — a full \`fusebase update\` refreshes these documents from your own CLI. Next step: none required; supply the $found CLI tree to the Flow maintainers if you want the bundled snapshot advanced.")
  fi
}
