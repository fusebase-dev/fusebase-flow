#!/usr/bin/env bash
# Fusebase Flow — git-wrapper smoke (D9). Single temp repo, 5 sequential scenarios.
# Proves the commit-msg + pre-commit WRAPPERS run and gate; it does NOT re-cover
# every branch — deep §2/§3 trusted-HEAD coverage stays in test-secret-scan-staged.sh
# / test-trusted-enforcer.sh.
#
# Contract (parsed by run-tests.sh run_shell_phase): "PASS: git-smoke <name>" /
# "FAIL: git-smoke <name>" lines; exit = fail count. Bounded-friendly: no unbounded
# waits; cleanup trap removes only its own mktemp root.
set -uo pipefail

REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CM="$REPO/hooks/git/commit-msg"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-git-smoke.XXXXXX")"
cleanup() {
  command -v mpf_destroy >/dev/null 2>&1 && mpf_destroy
  case "$TMP" in "${TMPDIR:-/tmp}"/ffhc-git-smoke.*) rm -rf -- "$TMP" ;; esac
}
trap cleanup EXIT

fail=0
pass_case() { echo "PASS: git-smoke $1"; }
fail_case() { echo "FAIL: git-smoke $1 ($2)"; fail=$((fail + 1)); }

# --- commit-msg scenarios (direct invocation with a message file; no git state) ---
run_cm() {  # run_cm <subject>  -> sets CM_RC
  printf '%s\n' "$1" > "$TMP/msg.txt"
  bash "$CM" "$TMP/msg.txt" >/dev/null 2>&1; CM_RC=$?
}

run_cm "feat: no ticket"
if [ "$CM_RC" -ne 0 ]; then pass_case "commit-msg blocks missing T-number"
else fail_case "commit-msg blocks missing T-number" "rc=$CM_RC expected nonzero"; fi

run_cm "docs(flow): clarify FR-12 approval semantics"
if [ "$CM_RC" -eq 0 ]; then pass_case "commit-msg allows docs prefix"
else fail_case "commit-msg allows docs prefix" "rc=$CM_RC expected 0"; fi

run_cm "feat(x): T9 add y"
if [ "$CM_RC" -eq 0 ]; then pass_case "commit-msg allows T-numbered subject"
else fail_case "commit-msg allows T-numbered subject" "rc=$CM_RC expected 0"; fi

# --- pre-commit scenarios: a fresh temp repo (unborn HEAD => §2/§3 take the
#     documented first-adoption fallback to the working-tree scanner/enforcer,
#     which needs the Flow hook layer + policies present in the tree). ---
CONSUMER="$TMP/consumer"
mkdir -p "$CONSUMER/hooks"
cp -R "$REPO/hooks/shared" "$CONSUMER/hooks/shared"
cp -R "$REPO/hooks/local"  "$CONSUMER/hooks/local"
cp -R "$REPO/hooks/git"    "$CONSUMER/hooks/git"
cp -R "$REPO/policies"     "$CONSUMER/policies"
( cd "$CONSUMER" && git init -q && git config user.email t@example.com && git config user.name t )
PC="$CONSUMER/hooks/git/pre-commit"

# Scenario 4: pre-commit §1 blocks a staged .env (bash-only path, before python).
(
  cd "$CONSUMER"
  printf 'API_KEY=placeholder\n' > .env
  git add .env >/dev/null 2>&1
  bash "$PC" >/dev/null 2>&1
); PC_RC=$?
if [ "$PC_RC" -ne 0 ]; then pass_case "pre-commit blocks staged .env"
else fail_case "pre-commit blocks staged .env" "rc=$PC_RC expected nonzero"; fi

# Scenario 5: pre-commit passes a benign staged file end-to-end (§1-§5 all clear).
(
  cd "$CONSUMER"
  git reset -q -- .env >/dev/null 2>&1 || true
  rm -f .env
  printf '# consumer note\nhello world\n' > note.md
  git add note.md >/dev/null 2>&1
  bash "$PC" >/dev/null 2>&1
); PC_RC2=$?
if [ "$PC_RC2" -eq 0 ]; then pass_case "pre-commit passes benign staged file"
else fail_case "pre-commit passes benign staged file" "rc=$PC_RC2 expected 0"; fi

# --- MAJOR 12: no interpreter => BLOCK, never a silent skip / warn-and-commit ---------------
# final-architecture-review finding 12: without python3 the §2 secret scan did not run at all
# (an `if` with no else) and §3 printed a WARN and committed with FR-07 unenforced.
# The interpreter-less PATH now comes from the ONE shared constructor; this file no longer
# builds its own (the host-directory mirror + 2000-entry cap lived here and in
# test-bootstrap-exception.sh in two copies).
# TRIPWIRE — every precondition is reported on its OWN cause. The retired `nopy_precondition`
# boolean merged oversized-dir, interpreter-leak and missing-git into one reason, so any one of
# them could read as any other.
# shellcheck source=/dev/null
. "$REPO/hooks/tests/lib/minimal-path-fixture.sh"

# gs_negative_row <row> <inject> <expected-cause>: drive one spec.md § Diagnostic injection
# matrix cause through the fixture; PASS only after capturing exactly that cause. The inner
# failure is captured, never emitted as a top-level PASS:/FAIL: row.
gs_negative_row() {
  local row="$1" inject="$2" want="$3" cap="$TMP/gsneg-$2.out" rc=0 other
  MPF_INJECT="$inject" mpf_build >"$cap" 2>&1 || rc=$?
  MPF_INJECT=""
  mpf_destroy
  if [ "$rc" -eq 0 ]; then fail_case "$row" "the injected cause did not fail the fixture (rc 0)"; return 0; fi
  case "$MPF_REASON" in
    *"$want"*) ;;
    *) fail_case "$row" "expected cause '$want', captured '${MPF_REASON:-<empty>}'"; return 0 ;;
  esac
  for other in "interpreter leakage" "Git unavailable" "shell unavailable" "fixture construction failed"; do
    [ "$other" = "$want" ] && continue
    case "$MPF_REASON" in *"$other"*)
      fail_case "$row" "captured more than one cause ('$want' and '$other'): $MPF_REASON"; return 0 ;;
    esac
  done
  if grep -qE '^(PASS|FAIL):' "$cap" 2>/dev/null; then
    fail_case "$row" "the inner failure leaked an uncaptured top-level PASS:/FAIL: row"; return 0
  fi
  pass_case "$row"
}

gs_negative_row "git-smoke-negative-interpreter-leakage"  interpreter-leak  "interpreter leakage"
gs_negative_row "git-smoke-negative-missing-git"          missing-git       "Git unavailable"
gs_negative_row "git-smoke-negative-missing-shell"        missing-shell     "shell unavailable"
gs_negative_row "git-smoke-negative-construction-failure" construction-fail "fixture construction failed"

if ! mpf_build; then
  fail_case "pre-commit blocks when no python3 interpreter exists" \
            "the shared minimal-PATH fixture reported: ${MPF_REASON:-unknown} — the row did not measure the interpreter contract"
else
  ( cd "$CONSUMER" && printf '# staged under a python-less PATH\n' > nopy.md \
      && git add nopy.md ) >/dev/null 2>&1
  nopy_err="$TMP/nopy.err"
  ( cd "$CONSUMER" && PATH="$MPF_PATH" bash "$PC" ) >/dev/null 2>"$nopy_err"; nopy_rc=$?
  nopy_out="$(cat "$nopy_err" 2>/dev/null)"
  if [ "$nopy_rc" -eq 0 ]; then
    fail_case "pre-commit blocks when no python3 interpreter exists" \
              "rc=0 — the commit proceeded with the FR-12 secret scan and the FR-07 check both unenforced"
  else
    case "$nopy_out" in
      *"no supported Python 3.10+ interpreter found"*)
        pass_case "pre-commit blocks when no python3 interpreter exists" ;;
      *) fail_case "pre-commit blocks when no python3 interpreter exists" \
                   "rc=$nopy_rc but the reason does not name the interpreter contract, so the block is not attributable to it" ;;
    esac
  fi

  # ... and when python3 is merely UNNAMED (Git Bash ships `python`, not `python3`), the hook
  # must DISCOVER it and still enforce, rather than block a perfectly capable environment.
  # This row runs the hook THROUGH §2/§3, whose python subprocesses call git themselves — hence
  # mpf_exec_path (a native child cannot exec a shell shim), which is measured, not assumed.
  PY_REAL="$(command -v python 2>/dev/null || true)"
  if [ -n "$PY_REAL" ] && mpf_exec_path; then
    UNNAMED_BIN="$TMP/unnamed-py"; mkdir -p "$UNNAMED_BIN"
    printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$PY_REAL" > "$UNNAMED_BIN/python"
    chmod +x "$UNNAMED_BIN/python"
    shim_out="$( cd "$CONSUMER" && PATH="$UNNAMED_BIN:$MPF_PATH_EXEC" bash "$PC" 2>&1 )"
    shim_rc=$?
    if [ "$shim_rc" -eq 0 ] && printf '%s' "$shim_out" | grep -q "using discovered 'python'"; then
      pass_case "pre-commit discovers an unnamed python3 instead of blocking"
    else
      fail_case "pre-commit discovers an unnamed python3 instead of blocking" \
                "rc=$shim_rc — a host with a usable Python 3 under the name \`python\` must not be refused"
    fi
  else
    # Not a skip-as-pass: state plainly that the discovery half was not measured here.
    echo "N/A: git-smoke pre-commit discovers an unnamed python3 — ${MPF_EXEC_REASON:-no bare \`python\` on this host to discover}" >&2
  fi
fi

exit "$fail"
