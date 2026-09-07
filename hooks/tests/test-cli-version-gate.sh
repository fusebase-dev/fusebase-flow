#!/usr/bin/env bash
# Fusebase Flow — installed-CLI version gate (S1) verdict/exit contract tests.
# Spec: docs/specs/cli-0298-compatibility/spec.md § S1.
#
# WHAT IS BEING PROVEN
#   Before this ticket the health check could not fail on an incompatible CLI (F1):
#   source_cli_version was the "unknown" sentinel and every CLI signal was advisory, so
#   /fusebase-health returned HEALTHY against ANY installed CLI. The three arms whose
#   verdict CHANGED are therefore paired with a MUTATION CONTROL: the same engine with
#   the version-gate call neutered, on the same fixture, must read HEALTHY/0. A row that
#   passes with and without the gate proves nothing; the control is what makes it count.
#
# The five contract arms (spec § S1 Oracle):
#   simulated 0.25.16   -> CLI_VERSION_UNSUPPORTED, exit 1  (the ONE hard failure)
#   0.29.8              -> HEALTHY, exit 0                   (matches the bundled snapshot)
#   simulated 0.30.0    -> HEALTHY, exit 0 + ADVISORY text   (newer: not the adopter's defect)
#   unreadable version  -> HEALTHY, exit 0 + ADVISORY text
#   no fusebase on PATH -> HEALTHY, exit 0 + ADVISORY text
#
# The three advisory arms were exit 4 until the zoom-out review. After a full `fusebase
# update` the adopter's provider skills are rewritten from their OWN CLI, so their documents
# are correct and only FLOW's review status is unknown — reporting that as a non-green verdict
# asked them to fix something that is not broken, and overloaded PARTIAL_UNVERIFIED, whose
# documented remediation is re-running an incomplete check.
#
# ADVERSARIAL ROWS (added after review). The five arms above are the EXPECTED inputs, and a
# row set built only from expected inputs is how a fail-open survives: adversarial review
# found four reachable HEALTHY-when-it-should-not-be paths that all five arms passed over.
# Rows tagged [WAS-FAIL-OPEN] / [WAS-GREEN-UNDER-RANGE] each reproduce one of them:
#   a banner line mentioning an in-range version while the CLI reports an older one;
#   `0.29.8-beta.1` / `+build` / `.1` / `garbage` accepted as the reviewed 0.29.8;
#   a `fusebase` that exits non-zero while printing a version;
#   an unreviewed 0.29.x greened by the retired `>=0.29.0 <0.30.0` range.
#
# COST DISCIPLINE: an engine run on MSYS costs ~40-70s. Only rows whose subject is the
#   ENGINE's verdict/exit plumbing spawn the engine (8 runs). Parser/boundary/override
#   rows drive ffhc_cli_version_check directly — same code, no spawn.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: cli-version <name>" / "FAIL: cli-version <name>"; exit code = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

CVG_ONLY=""
case "$#" in
  0) ;;
  2) [ "$1" = "--only" ] && [ "$2" = "below-incompatible-0.25.16" ] || exit 2
     CVG_ONLY="$2" ;;
  *) exit 2 ;;
esac

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: cli-version $1"; }
# TRIPWIRE (C4): the reason goes on the SAME stdout line as the FAIL marker and newlines are
# flattened — run-tests.sh rows ONLY lines matching `^(PASS|FAIL): cli-version `, so a reason
# on a continuation line or on stderr reaches neither the log nor hook-test-results.md.
bad() { fail=$((fail + 1)); local w="${2:-}"; [ -z "$w" ] || w=" ($(printf '%s' "$w" | tr '\n\r\t' '   ' | cut -c1-400))"; echo "FAIL: cli-version $1$w"; }
finish() { echo "[test-cli-version-gate] $pass/$((pass + fail)) PASS"; exit $fail; }

TMP_BASE="${TMPDIR:-/tmp}/fusebase-flow-cli-version.$$"
mkdir -p "$TMP_BASE"
cleanup() {
  case "$TMP_BASE" in
    /tmp/fusebase-flow-cli-version.*|*/tmp/fusebase-flow-cli-version.*|*/Temp/fusebase-flow-cli-version.*)
      rm -rf "$TMP_BASE" ;;
  esac
}
trap cleanup EXIT

# shellcheck source=../local/lib/run-with-timeout.sh
. hooks/local/lib/run-with-timeout.sh
ffhc_detect_timeout
# shellcheck source=../local/lib/cli-version-check.sh
. hooks/local/lib/cli-version-check.sh

RANGE="Vendored CLI snapshot: 0.29.8. Below 0.29.0 is known-incompatible (the only hard failure); anything else is advisory"

# stub_bin <dir> <output>: a `fusebase` shim printing <output> for --version.
stub_bin() {
  mkdir -p "$1"
  { printf '#!/usr/bin/env bash\n'; printf 'cat <<%s\n%s\nEOF_V\n' "'EOF_V'" "$2"; } > "$1/fusebase"
  chmod +x "$1/fusebase"
}

# path_without_fusebase: the ambient PATH minus every dir that actually provides a
# `fusebase` executable. Needed so the not-on-PATH arm is deterministic on a host that
# HAS the CLI installed — dropping PATH entirely would take python3/git with it.
path_without_fusebase() {
  local out="" d
  local OLD_IFS="$IFS"; IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/fusebase" ] || [ -x "$d/fusebase.exe" ] || [ -x "$d/fusebase.cmd" ] || [ -x "$d/fusebase.bat" ]; then
      continue
    fi
    out="${out:+$out:}$d"
  done
  IFS="$OLD_IFS"
  printf '%s' "$out"
}
BASE_PATH="$(path_without_fusebase)"

###############################################################################
# Part 1 — unit rows (no engine spawn)
###############################################################################

sem_expect() {  # sem_expect <a> <b> <lt|ge>
  local got
  if ffhc_semver_lt "$1" "$2"; then got=lt; else got=ge; fi
  [ "$got" = "$3" ] || { bad "semver-$1-vs-$2" "expected $3, got $got"; return 1; }
  return 0
}
sem_f=0
sem_expect 0.25.16 0.29.0 lt || sem_f=1
sem_expect 0.29.0  0.29.0 ge || sem_f=1
sem_expect 0.29.8  0.30.0 lt || sem_f=1
sem_expect 0.30.0  0.30.0 ge || sem_f=1
sem_expect 0.9.0   0.29.0 lt || sem_f=1     # component-numeric, not lexicographic
sem_expect 0.29.10 0.29.2 ge || sem_f=1     # 10 > 2 numerically; "0.29.10" < "0.29.2" as strings
[ "$sem_f" -eq 0 ] && ok "semver-comparator (6 orderings incl. the two lexicographic traps)"

# ---- parser rows: the two documented shapes, and every adversarial input ------
# ADVERSARIAL-FIRST. The first version of this parser took the FIRST three-component token
# anywhere in the output, and every row marked [WAS-FAIL-OPEN] below returned 0.29.8 =>
# HEALTHY under it — including a real installed 0.25.16 hidden behind a banner line that
# happened to mention 0.29.8. Those five rows are the RED this hardening was built against;
# they are the reason the row set is not just the happy path.
parse_row() {  # parse_row <name> <raw> <expected|__NONE__>
  local got; got="$(ffhc_cli_version_parse "$2")"
  local want="$3"; [ "$want" = "__NONE__" ] && want=""
  [ "$got" = "$want" ] && ok "$1" || bad "$1" "expected '${want:-<none>}', got '${got:-<none>}'"
}
parse_row parse-bare              '0.29.8' 0.29.8
parse_row parse-launcher-block    'FuseBase CLI 0.29.8
Launcher 1.4.2
Channel prod' 0.29.8
# The REAL shape this host prints: an update notice BEFORE the version line.
parse_row parse-real-host-notice-first 'A launcher update is available. Run `fusebase update --launcher` when convenient.

FuseBase CLI 0.29.8' 0.29.8
# [WAS-FAIL-OPEN] the installed CLI is 0.25.16; only a banner mentions 0.29.8. The old
# first-token parser answered 0.29.8 and greened an incompatible install.
parse_row parse-banner-must-not-win 'update available: 0.29.8
FuseBase CLI 0.25.16' 0.25.16
# [WAS-FAIL-OPEN] x4 — a suffixed or extra-component version is NOT the reviewed 0.29.8.
parse_row parse-prerelease-suffix  '0.29.8-beta.1'  __NONE__
parse_row parse-build-suffix       '0.29.8+build'   __NONE__
parse_row parse-four-components    '0.29.8.1'       __NONE__
parse_row parse-trailing-garbage   '0.29.8garbage'  __NONE__
# Two different declared versions: picking one would be a guess.
parse_row parse-ambiguous          '0.29.8
FuseBase CLI 0.25.16' __NONE__
parse_row parse-empty              ''                  __NONE__
parse_row parse-junk               'command not found' __NONE__

# lib_classify <version-output|__ABSENT__> [env-assignments...]
#   -> "UNSUPPORTED|UNVERIFIED|OK<TAB><first message>". Drives the SAME function the engine
#   calls, in a subshell with the engine's four arrays declared. No engine spawn.
lib_classify() {
  local ver="$1"; shift
  local d="$TMP_BASE/lib.$RANDOM" p="$BASE_PATH"
  if [ "$ver" != "__ABSENT__" ]; then stub_bin "$d" "$ver"; p="$d:$BASE_PATH"; fi
  (
    export PATH="$p"
    [ "$#" -eq 0 ] || export "$@"
    # TRIPWIRE: re-source INSIDE the subshell, after the env assignments. The engine sources
    # the lib in its own process too, so the constants' source-time assignment is what makes
    # the range non-overridable. Reusing the outer shell's already-sourced copy would let an
    # exported var win and the env-override row would assert the opposite of the truth.
    . hooks/local/lib/run-with-timeout.sh; ffhc_detect_timeout
    . hooks/local/lib/cli-version-check.sh
    LOCAL_OK=(); LOCAL_DRIFT=(); LOCAL_UNVERIFIED=(); CLI_VERSION_UNSUPPORTED=(); CLI_VERSION_ADVISORY=()
    ffhc_cli_version_check
    if   [ "${#CLI_VERSION_UNSUPPORTED[@]}" -gt 0 ]; then printf 'UNSUPPORTED\t%s' "${CLI_VERSION_UNSUPPORTED[0]}"
    elif [ "${#LOCAL_UNVERIFIED[@]}"        -gt 0 ]; then printf 'UNVERIFIED\t%s'  "${LOCAL_UNVERIFIED[0]}"
    elif [ "${#CLI_VERSION_ADVISORY[@]}"    -gt 0 ]; then printf 'ADVISORY\t%s'    "${CLI_VERSION_ADVISORY[0]}"
    elif [ "${#LOCAL_OK[@]}"                -gt 0 ]; then printf 'OK\t%s'          "${LOCAL_OK[0]}"
    else printf 'NONE\t(no classification recorded)'
    fi
  )
}

lib_row() {  # lib_row <name> <version> <expected-class> [required substrings...]
  local name="$1" ver="$2" want="$3"; shift 3
  local got s
  got="$(lib_classify "$ver")"
  [ "${got%%$'\t'*}" = "$want" ] || { bad "$name" "expected $want, got: $got"; return; }
  for s in "$@"; do
    printf '%s' "$got" | grep -qF -- "$s" || { bad "$name" "message missing '$s': $got"; return; }
  done
  ok "$name"
}

# Classification rows: reviewed SET semantics, not a range.
# Only 0.29.8 was ever compared against these vendored assets. Everything else that is not
# below the incompatibility line is ADVISORY (exit 0): it names the gap without asserting the
# adopter has a problem. [WAS-GREEN-UNDER-RANGE] 0.29.0/0.29.9 were silently HEALTHY under the
# retired `>=0.29.0 <0.30.0` range — they must still be distinguishable from a snapshot match.
lib_row older-than-snapshot     "0.29.0"  ADVISORY    "installed 0.29.0 is OLDER than the vendored CLI snapshot" "$RANGE"
lib_row newer-than-snapshot     "0.29.9"  ADVISORY    "installed 0.29.9 is NEWER than the vendored CLI snapshot" "none required"
lib_row matches-snapshot-0.29.8 "0.29.8"  OK          "installed 0.29.8 matches the vendored CLI snapshot"
lib_row below-incompatible-line "0.28.99" UNSUPPORTED "installed FuseBase Apps CLI is 0.28.99" "$RANGE"
lib_row launcher-block "FuseBase CLI 0.29.8
Launcher 1.4.2
Channel prod" OK "installed 0.29.8 matches the vendored CLI snapshot"
# A much newer CLI is not merely "not red" — it is exit 0, because a full `fusebase update`
# has already refreshed those documents from the adopter's own CLI.
lib_row far-above-0.31.0 "0.31.0" ADVISORY "installed 0.31.0 is NEWER than the vendored CLI snapshot" "supply the 0.31.0 CLI tree"

# [WAS-FAIL-OPEN] a `fusebase` that FAILS while printing a valid version string. The first
# version of this check never read FFHC_LAST_RC, so this produced LOCAL_OK => HEALTHY.
rcfail_dir="$TMP_BASE/rcfail"
mkdir -p "$rcfail_dir"
printf '#!/usr/bin/env bash\necho 0.29.8\nexit 3\n' > "$rcfail_dir/fusebase"
chmod +x "$rcfail_dir/fusebase"
rcout="$(
  export PATH="$rcfail_dir:$BASE_PATH"
  . hooks/local/lib/run-with-timeout.sh; ffhc_detect_timeout
  . hooks/local/lib/cli-version-check.sh
  LOCAL_OK=(); LOCAL_DRIFT=(); LOCAL_UNVERIFIED=(); CLI_VERSION_UNSUPPORTED=(); CLI_VERSION_ADVISORY=()
  ffhc_cli_version_check
  if [ "${#CLI_VERSION_ADVISORY[@]}" -gt 0 ]; then printf 'ADVISORY\t%s' "${CLI_VERSION_ADVISORY[0]}"
  elif [ "${#LOCAL_OK[@]}" -gt 0 ];          then printf 'OK\t%s' "${LOCAL_OK[0]}"
  else printf 'NONE\t'; fi
)"
# Softening the OUTCOME does not soften this: an advisory that reports a version nobody
# established is a lie with a gentler exit code. rc!=0 must never reach the snapshot-match arm.
if [ "${rcout%%$'\t'*}" = "ADVISORY" ] && printf '%s' "$rcout" | grep -qF "exited 3"; then
  ok "nonzero-exit-is-not-trusted (a failing \`fusebase\` printing 0.29.8 => 'not determined', never a snapshot match)"
else
  bad "nonzero-exit-is-not-trusted" "output of a rc=3 probe was trusted: $rcout"
fi

# The incompatibility line is NOT env-overridable — an env kill switch would let a consumer
# excuse a version nobody has evidence for, which is the failure mode this gate exists to
# prevent. It is the one remaining hard failure, so it is the one that must not be movable.
ov="$(lib_classify "0.25.16" FFHC_CLI_BUNDLED_VERSION=0.25.16 FFHC_CLI_INCOMPATIBLE_BELOW=0.1.0)"
if [ "${ov%%$'\t'*}" = "UNSUPPORTED" ]; then
  ok "env-override-rejected (FFHC_CLI_BUNDLED_VERSION / _INCOMPATIBLE_BELOW cannot move the incompatibility line)"
else
  bad "env-override-rejected" "an env var moved the incompatibility line: $ov"
fi

###############################################################################
# Part 2 — end-to-end engine rows (verdict + exit code)
###############################################################################

GOLDEN="$TMP_BASE/_golden"
build_golden() {
  local dir="$GOLDEN"
  mkdir -p "$dir/hooks/local/lib" "$dir/hooks/tests" "$dir/audit" \
           "$dir/.claude/skills/fusebase-flow-health-check" "$dir/.claude/agents" \
           "$dir/hooks/local/fusebase-flow-overlays" \
           "$dir/hooks/shared" "$dir/policies" "$dir/state/approvals"
  cp hooks/local/fusebase-flow-health-check.sh "$dir/hooks/local/"
  cp hooks/local/lib/run-with-timeout.sh hooks/local/lib/hook-integrity-check.sh \
     hooks/local/lib/hook_manifest.py hooks/local/lib/active-approvals.sh \
     hooks/local/lib/cli-version-check.sh hooks/local/lib/health-recommendations.sh \
     hooks/local/lib/health-stage-progress.sh \
     "$dir/hooks/local/lib/"
  cp hooks/shared/__init__.py hooks/shared/approval_artifact.py \
     hooks/shared/policy_loader.py hooks/shared/audit_logger.py "$dir/hooks/shared/"
  cp policies/approval-policy.yml "$dir/policies/"
  cp hooks/local/verify-hook-manifest.sh hooks/local/stamp-hook-manifest.sh "$dir/hooks/local/"
  cp VERSION "$dir/VERSION"
  printf '# AGENTS\n\n## Fusebase Flow — workflow lifecycle overlay\n' > "$dir/AGENTS.md"
  : > "$dir/.claude/skills/fusebase-flow-health-check/SKILL.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/hooks/local/post-fusebase-update.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/hooks/local/preflight.sh"
  printf '#!/usr/bin/env bash\necho "[run-tests] 1/1 PASS"\nexit 0\n' > "$dir/hooks/tests/run-tests.sh"
  printf '#!/usr/bin/env bash\nprintf %%s "{\\"verdict\\": \\"HEALTHY\\", \\"findings\\": []}"\nexit 0\n' > "$dir/hooks/local/check-cli-flow-conflicts.sh"
  chmod +x "$dir/hooks/local/post-fusebase-update.sh" "$dir/hooks/local/preflight.sh" \
           "$dir/hooks/tests/run-tests.sh" "$dir/hooks/local/check-cli-flow-conflicts.sh"
  ( cd "$dir" && bash hooks/local/stamp-hook-manifest.sh >/dev/null 2>&1 )   # ONE stamp
}
fx() { rm -rf "$1"; cp -R "$GOLDEN" "$1"; }

# neuter_gate <fixture>: the MUTATION CONTROL. Replace the two lines that invoke the S1
# gate wrapper with `:` so the engine runs every OTHER check unchanged and has no CLI-version
# signal at all — i.e. the pre-ticket engine's behaviour, reproduced from the current one.
# Returns nonzero if the mutation did not apply (a control that silently didn't mutate is
# worse than no control).
neuter_gate() {
  local e="$1/hooks/local/fusebase-flow-health-check.sh"
  sed -e 's/^ffhc_run_cli_version_stage "\$FFHC_CLIVER_LIB"$/:/' \
      -e 's|^  LOCAL_UNVERIFIED+=("CLI version compatibility: UNVERIFIED — missing.*|  :|' \
      "$e" > "$e.mut" || return 1
  grep -q '^ffhc_run_cli_version_stage "\$FFHC_CLIVER_LIB"$' "$e.mut" && return 1
  cmp -s "$e" "$e.mut" && return 1                               # byte-identical => not mutated
  mv "$e.mut" "$e" || return 1
  bash -n "$e" || return 1                                       # mutant must still be valid bash
  ( cd "$1" && bash hooks/local/stamp-hook-manifest.sh >/dev/null 2>&1 )   # re-stamp the covered edit
  return 0
}

run_hc() {  # run_hc <dir> <path>
  local dir="$1" p="$2" out rc
  out="$(cd "$dir" && PATH="$p" FFHC_PREFLIGHT_TIMEOUT=10 FFHC_CONFLICT_TIMEOUT=10 \
        bash hooks/local/fusebase-flow-health-check.sh --no-upstream 2>&1)"; rc=$?
  printf '%s\nEXIT=%s\n' "$out" "$rc"
}

# scenario <name> <version|__ABSENT__> <verdict> <exit> <control:yes|no> [required substrings...]
scenario() {
  local name="$1" ver="$2" verdict="$3" xit="$4" ctl="$5"; shift 5
  local D="$TMP_BASE/$name" P="$BASE_PATH" OUT s
  fx "$D"
  if [ "$ver" != "__ABSENT__" ]; then stub_bin "$D/_bin" "$ver"; P="$D/_bin:$BASE_PATH"; fi
  OUT="$(run_hc "$D" "$P")"
  echo "$OUT" | grep -q "Verdict: $verdict" || { bad "$name" "expected Verdict: $verdict -- $OUT"; return; }
  echo "$OUT" | grep -q "^EXIT=$xit$"       || { bad "$name" "expected EXIT=$xit -- $OUT"; return; }
  for s in "$@"; do
    echo "$OUT" | grep -qF -- "$s" || { bad "$name" "output missing required text '$s' -- $OUT"; return; }
  done
  if [ "$ctl" = "no" ]; then ok "$name"; return; fi
  local C="$TMP_BASE/$name-control" COUT
  fx "$C"
  neuter_gate "$C" || { bad "$name-control" "mutation did not apply — the control is not a control"; return; }
  COUT="$(run_hc "$C" "$P")"
  # TRIPWIRE: for an ADVISORY arm the verdict is HEALTHY/0 on BOTH sides, so "neutered reads
  # HEALTHY/0" discriminates nothing. The control must instead prove the advisory TEXT is
  # absent without the gate — otherwise these rows would pass against a gate that does nothing.
  if [ "$verdict" = "HEALTHY" ]; then
    if echo "$COUT" | grep -qF -- "$1"; then
      bad "$name-control" "the advisory text survives with the gate neutered, so this row proves nothing -- $COUT"
    else
      ok "$name (+ control: gate neutered => the advisory text disappears, verdict HEALTHY/0 either way)"
    fi
    return
  fi
  if echo "$COUT" | grep -q "Verdict: HEALTHY" && echo "$COUT" | grep -q "^EXIT=0$"; then
    ok "$name (+ mutation control: gate neutered => same fixture reads HEALTHY/0)"
  else
    bad "$name-control" "gate-neutered engine did not read HEALTHY/0, so the row above proves nothing -- $COUT"
  fi
}

build_golden

# A1 — below the established incompatibility line: the ONE hard failure. States version,
# policy and the remediation command.
scenario below-incompatible-0.25.16 "0.25.16" CLI_VERSION_UNSUPPORTED 1 yes \
  "installed FuseBase Apps CLI is 0.25.16, below 0.29.0" "$RANGE" "npm install -g fusebase-apps-cli@latest"
[ -z "$CVG_ONLY" ] || finish

# A2 — matches the bundled snapshot: HEALTHY, exit 0. No control: the pre-ticket engine also
# read HEALTHY here, so a control would assert nothing. This row guards that the gate did not
# make the compatible case red.
scenario matches-snapshot-0.29.8 "0.29.8" HEALTHY 0 no \
  "CLI version: installed 0.29.8 matches the vendored CLI snapshot"

# A3 — NEWER than the snapshot: HEALTHY, exit 0, advisory only. Was exit 4; a full
# `fusebase update` already refreshed those documents from the adopter's own CLI, so a
# non-green verdict reported Flow's review status as their defect.
scenario newer-0.30.0 "0.30.0" HEALTHY 0 yes \
  "installed 0.30.0 is NEWER than the vendored CLI snapshot" "$RANGE" "supply the 0.30.0 CLI tree"

# A4 — version unreadable: advisory, exit 0 — but it must NOT claim a version.
scenario unreadable-version "fusebase: command failed" HEALTHY 0 yes \
  "declared no single unambiguous version" "$RANGE"

# A5 — fusebase absent from PATH: advisory, exit 0. This is the state of CI, containers, and
# any machine that only edits the framework; none of them has a problem to fix.
scenario absent-from-path "__ABSENT__" HEALTHY 0 yes \
  "is not on PATH" "$RANGE"

finish
