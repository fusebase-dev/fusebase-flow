#!/usr/bin/env bash
# Fusebase Flow — self-test for hooks/tests/lib/minimal-path-fixture.sh (AC2, AC7).
# Spec: docs/specs/msys-test-fixture-rework/spec.md.
#
# Positive half: the fixture resolves git + the shell absolutely, masks every interpreter name
# §1b of hooks/git/pre-commit can discover, keeps git and bash executable, and builds its bin
# from the explicit allowlist alone (never a host-directory mirror).
# Negative half: each cause of spec.md § Diagnostic injection matrix is INJECTED, and its row
# passes only after capturing exactly that one cause — the other three must be absent.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: minimal-path-fixture <name>" / "FAIL: minimal-path-fixture <name>"; exit = fail count.
#
# TRIPWIRE — inner fixture failures are captured into a file and into MPF_REASON; they must never
# reach this phase's stdout as a bare PASS:/FAIL: row (an uncaptured row is an unattributed row).

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FIXTURE="$ROOT/hooks/tests/lib/minimal-path-fixture.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: minimal-path-fixture $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: minimal-path-fixture $1 (${2:-})"; }
finish() { echo "[test-minimal-path-fixture] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$FIXTURE" ] || { bad "fixture-present" "missing $FIXTURE"; finish; }
# shellcheck source=/dev/null
. "$FIXTURE"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffmpf-selftest.XXXXXX")"
cleanup() { mpf_destroy; case "$TMP" in "${TMPDIR:-/tmp}"/ffmpf-selftest.*) rm -rf -- "$TMP" ;; esac; }
trap cleanup EXIT

# ---- 1. Source-level AC7: no PATH-directory enumeration, mirroring, symlinking or copying. ----
if grep -qE 'for[[:space:]]+[A-Za-z_]+[[:space:]]+in[[:space:]]+\$PATH' "$FIXTURE"; then
  bad "fixture-no-path-enumeration-loop" "the fixture splits \$PATH into directories"
else ok "fixture-no-path-enumeration-loop"; fi
if grep -qE '(^|[^A-Za-z_])IFS=|ln[[:space:]]+-s' "$FIXTURE"; then
  bad "fixture-no-mirroring-primitives" "the fixture uses IFS splitting or ln -s (host-directory mirroring)"
else ok "fixture-no-mirroring-primitives"; fi

# ---- 2. Positive construction. ----
if mpf_build; then ok "fixture-builds"
else bad "fixture-builds" "${MPF_REASON:-unknown}"; finish; fi

case "$MPF_GIT" in /*|[A-Za-z]:[/\\]*) ok "fixture-git-resolved-absolute ($MPF_GIT)" ;;
  *) bad "fixture-git-resolved-absolute" "resolved git path is not absolute: '$MPF_GIT'" ;; esac
case "$MPF_SHELL" in /*|[A-Za-z]:[/\\]*) ok "fixture-shell-resolved-absolute ($MPF_SHELL)" ;;
  *) bad "fixture-shell-resolved-absolute" "resolved shell path is not absolute: '$MPF_SHELL'" ;; esac

for name in python3 python py; do
  if PATH="$MPF_PATH" command -v "$name" >/dev/null 2>&1; then
    bad "fixture-${name}-absent" "'$name' still resolves under the fixture PATH — §1b would discover it"
  else ok "fixture-${name}-absent"; fi
done

if PATH="$MPF_PATH" git --version >/dev/null 2>&1; then ok "fixture-git-executable"
else bad "fixture-git-executable" "a git-less PATH makes the hook exit 0 at its rev-parse guard — an environment artifact, not a contract"; fi
if PATH="$MPF_PATH" bash -c ':' >/dev/null 2>&1; then ok "fixture-shell-executable"
else bad "fixture-shell-executable" "bash does not execute under the fixture PATH"; fi

# Behavioral AC7: the bin holds ONLY allowlisted names, so it cannot be a host-directory mirror.
allow_n="$(printf '%s\n' $MPF_TOOLS | wc -l)"
bin_n="$(ls -1 "$MPF_BIN" 2>/dev/null | wc -l)"
extra=""
while IFS= read -r e; do
  [ -n "$e" ] || continue
  case " $MPF_TOOLS " in *" $e "*) ;; *) extra="$extra $e" ;; esac
done < <(ls -1 "$MPF_BIN" 2>/dev/null)
if [ -z "$extra" ] && [ "${bin_n:-0}" -le "${allow_n:-0}" ]; then
  ok "fixture-bin-holds-only-allowlisted-shims ($bin_n of $allow_n allowlisted names)"
else
  bad "fixture-bin-holds-only-allowlisted-shims" "unexpected entries:${extra:-none}; count=$bin_n allowlist=$allow_n"
fi

# The native-exec variant is optional by construction; when present it must be interpreter-free.
if mpf_exec_path; then
  if PATH="$MPF_PATH_EXEC" command -v python3 >/dev/null 2>&1 \
     || PATH="$MPF_PATH_EXEC" command -v python >/dev/null 2>&1 \
     || PATH="$MPF_PATH_EXEC" command -v py >/dev/null 2>&1; then
    bad "fixture-exec-path-interpreter-free" "MPF_PATH_EXEC exposes an interpreter"
  else ok "fixture-exec-path-interpreter-free"; fi
else
  echo "N/A: minimal-path-fixture exec-path — ${MPF_EXEC_REASON:-unavailable on this host}" >&2
fi

mpf_destroy
if [ -z "$MPF_BIN" ]; then ok "fixture-destroy-clears-state"
else bad "fixture-destroy-clears-state" "MPF_BIN still set after mpf_destroy"; fi

# ---- 3. Diagnostic injection matrix — one row per cause, each capturing exactly its own. ----
# negative_row <row> <inject> <expected-cause>
negative_row() {
  local row="$1" inject="$2" want="$3" cap="$TMP/$1.out" rc=0 other
  MPF_INJECT="$inject" mpf_build >"$cap" 2>&1 || rc=$?
  MPF_INJECT=""
  if [ "$rc" -eq 0 ]; then
    mpf_destroy
    bad "$row" "the injected cause did not fail the fixture (rc 0)"
    return 0
  fi
  mpf_destroy
  case "$MPF_REASON" in
    *"$want"*) ;;
    *) bad "$row" "expected cause '$want', captured '${MPF_REASON:-<empty>}'"; return 0 ;;
  esac
  for other in "interpreter leakage" "Git unavailable" "shell unavailable" "fixture construction failed"; do
    [ "$other" = "$want" ] && continue
    case "$MPF_REASON" in *"$other"*)
      bad "$row" "captured more than one cause ('$want' and '$other'): $MPF_REASON"; return 0 ;;
    esac
  done
  if grep -qE '^(PASS|FAIL):' "$cap" 2>/dev/null; then
    bad "$row" "the inner failure leaked an uncaptured top-level PASS:/FAIL: row"
    return 0
  fi
  ok "$row (captured: $MPF_REASON)"
}

negative_row "fixture-negative-interpreter-leakage"    interpreter-leak   "interpreter leakage"
negative_row "fixture-negative-missing-git"            missing-git        "Git unavailable"
negative_row "fixture-negative-missing-shell"          missing-shell      "shell unavailable"
negative_row "fixture-negative-construction-failure"   construction-fail  "fixture construction failed"

finish
