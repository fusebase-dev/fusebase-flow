#!/usr/bin/env bash
# Fusebase Flow — S2d contract for hooks/git/pre-commit §1b-v: the RESOLVED `python3` must prove
# Python 3.10+ before §2 (FR-12 secret scan) and §3 (FR-07 protected paths) run under it.
# Spec: docs/specs/pre-commit-trusted-tool-contract/spec.md § S2d compatibility contract.
# Rows PY1-PY7 of docs/specs/pre-commit-trusted-tool-contract/verification-gate.md.
#
# This is fault/context detection, NOT interpreter authentication: a caller who controls PATH can
# return any version string. The rows below prove version SYMMETRY with the discovered fallbacks.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: python3-version <name>" / "FAIL: python3-version <name>"; exit = fail count.
#
# FFPV_HOOK=<path> runs the whole contract against a COPY of the hook; that is the oracle
# test-pre-commit-python3-version-mutation.sh drives. Production hooks/git/pre-commit is never
# written to.
#
# TRIPWIRE — row names are space-free: the mutation harness compares result sets by first token.
# TRIPWIRE — the staged path is BENIGN (note.md). A protected or secret-like path would let §1/§3
# supply the nonzero rc, so a BLOCK would not be attributable to §1b-v.
# TRIPWIRE — PY4/PY6 shims exist because `-S -c` support is NOT a consumer requirement: a wrapper
# that only honours `-S <file>` must still reach the controls (decisions.md § S2d).

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOOK_SRC="${FFPV_HOOK:-$ROOT/hooks/git/pre-commit}"
FIXTURE="$ROOT/hooks/tests/lib/minimal-path-fixture.sh"
BLOCK_DIAG="did not prove Python 3.10+"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: python3-version $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: python3-version $1 (${2:-})"; }
finish() { echo "[test-pre-commit-python3-version-contract] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$HOOK_SRC" ] || { bad "hook-source-present" "missing $HOOK_SRC"; finish; }
command -v python3 >/dev/null 2>&1 || { ok "skipped-no-python3"; finish; }
REALPY="$(command -v python3)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffpv-contract.XXXXXX")"
cleanup() {
  command -v mpf_destroy >/dev/null 2>&1 && mpf_destroy
  case "$TMP" in "${TMPDIR:-/tmp}"/ffpv-contract.*) rm -rf -- "$TMP" ;; esac
}
trap cleanup EXIT
cp "$HOOK_SRC" "$TMP/hook-at-start"

# ---- consumer repos --------------------------------------------------------------------------
# mk_consumer <dir> <with-head>: a repo carrying the Flow bits §2/§3 need plus the hook under test.
mk_consumer() {
  local d="$1" with_head="$2"
  mkdir -p "$d/hooks/git"
  cp -R "$ROOT/hooks/shared" "$d/hooks/shared"
  cp -R "$ROOT/hooks/local"  "$d/hooks/local"
  cp -R "$ROOT/policies"     "$d/policies"
  cp "$HOOK_SRC" "$d/hooks/git/pre-commit"
  ( cd "$d" && git init -q && git config user.email t@example.com && git config user.name t \
      && git config core.autocrlf false ) || return 1
  if [ "$with_head" = "head" ]; then
    printf '# base\n' > "$d/base.md"
    # No hook is installed in .git/hooks, so this commit does not invoke the hook under test.
    ( cd "$d" && git add -- . >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 ) || return 1
  fi
  printf '# consumer note\nhello world\n' > "$d/note.md"
  ( cd "$d" && git add -- note.md >/dev/null 2>&1 )
}

# shim <dir> <name> <body...>: an executable PATH entry.
shim() { local d="$1" n="$2"; shift 2; mkdir -p "$d"; printf '%s\n' "$@" > "$d/$n"; chmod +x "$d/$n"; }

B="$TMP/bin"
# ver39: a python3 that reports 3.9 for every invocation (below the floor, well-formed).
shim "$B/ver39" python3 '#!/usr/bin/env bash' 'echo "FFPCVER 3 9"' 'exit 0'
# cishim: byte-shape of the CI Windows provisioning shim (.github/workflows/fusebase-flow-verify.yml).
shim "$B/cishim" python3 '#!/usr/bin/env bash' 'exec python "$@"'
shim "$B/cishim" python  '#!/usr/bin/env bash' "exec \"$REALPY\" \"\$@\""
# noc: honours `-S <file>` but REJECTS `-c` (the wrapper class S2d must not break).
shim "$B/noc" python3 '#!/usr/bin/env bash' \
  'for a in "$@"; do [ "$a" = "-c" ] && { echo "ffpv-wrapper: -c is not supported" >&2; exit 2; }; done' \
  "exec \"$REALPY\" \"\$@\""
# boom: every attempt errors, with an attributable rc and stderr.
shim "$B/boom" python3 '#!/usr/bin/env bash' 'echo "ffpv-boom" >&2' 'exit 7'
# hang: every attempt blocks past the 10s per-attempt bound.
shim "$B/hang" python3 '#!/usr/bin/env bash' 'sleep 60'
# junk: exits 0 with malformed (unparseable) version output.
shim "$B/junk" python3 '#!/usr/bin/env bash' 'echo "not-a-version"' 'exit 0'
# log: a real interpreter that records every argv it is handed. The version probe is then a DIRECT
# observable ("was python3 asked for FFPCVER?") instead of a wall-clock proxy — §2 runs whether or
# not anything is staged, so elapsed time cannot tell the two apart.
PYLOG="$TMP/pyargs.log"
shim "$B/log" python3 '#!/usr/bin/env bash' "printf '%s\\n' \"\$*\" >> \"$PYLOG\"" "exec \"$REALPY\" \"\$@\""

# run_hook <consumer> <path> -> RC, ELAPSED, RESIDUE; stderr in $TMP/last.err.
# TMPDIR is redirected to a PRIVATE, emptied dir so "temp residue" is this run's own leftovers,
# never a concurrent process's.
TMPROOT="$TMP/tmproot"
run_hook() {
  local d="$1" p="$2" t0 t1
  rm -rf "$TMPROOT"; mkdir -p "$TMPROOT"
  t0="$(date +%s)"
  ( cd "$d" && PATH="$p" TMPDIR="$TMPROOT" bash hooks/git/pre-commit ) >"$TMP/last.out" 2>"$TMP/last.err"; RC=$?
  t1="$(date +%s)"; ELAPSED=$((t1 - t0))
  ERR="$(cat "$TMP/last.err" 2>/dev/null)"
  RESIDUE="$(ls -A "$TMPROOT" 2>/dev/null | grep -c . || true)"
}
has() { case "$ERR" in *"$1"*) return 0 ;; esac; return 1; }

C1="$TMP/c1"; mk_consumer "$C1" head || { bad "consumer-repo-built" "could not build the HEAD consumer"; finish; }
C0="$TMP/c0"; mk_consumer "$C0" nohead || { bad "consumer-repo-built" "could not build the unborn-HEAD consumer"; finish; }
ok "consumer-repo-built"

# ---- PY1: real CPython >=3.10 ------------------------------------------------------------------
run_hook "$C1" "$PATH"
if [ "$RC" -eq 0 ] && has "all checks passed"; then ok "PY1-real-cpython-passes"
else bad "PY1-real-cpython-passes" "rc=$RC on the normal PATH; the same staged state must pass, or no BLOCK below is attributable to §1b-v"; fi
# Positive control for the PY7 observable: with something staged, the `-S -c` probe IS issued.
: > "$PYLOG"; run_hook "$C1" "$B/log:$PATH"
if [ "$RC" -eq 0 ] && grep -q -- '-S -c .*FFPCVER' "$PYLOG" 2>/dev/null; then ok "PY1-primary-probe-issued"
else bad "PY1-primary-probe-issued" "rc=$RC and no '-S -c' FFPCVER probe in the recorded argv — the bounded primary probe did not run"; fi

# ---- PY2: real CPython <3.10 -------------------------------------------------------------------
run_hook "$C1" "$B/ver39:$PATH"
py2_err="$ERR"; py2_rc=$RC
if [ "$py2_rc" -ne 0 ]; then ok "PY2-below-floor-blocks"
else bad "PY2-below-floor-blocks" "rc=0 with a python3 reporting 3.9 — §2/§3 ran under an unsupported interpreter"; fi
if has "$BLOCK_DIAG" && has "version=3.9"; then ok "PY2-below-floor-message"
else bad "PY2-below-floor-message" "stderr does not attribute the refusal to the version probe: ${py2_err:-<empty>}"; fi
if ! has "all checks passed" && ! has "first-adoption bootstrap" && ! has "trusted HEAD"; then ok "PY2-blocks-before-controls"
else bad "PY2-blocks-before-controls" "execution reached §2/§3 before the refusal — the BLOCK is not 'before sections 2/3'"; fi

# ---- PY3: the CI-provisioned Windows shim contract ---------------------------------------------
# Hosted proof is the exact-SHA verify-windows-msys job (gate row P3); this asserts the same shim
# SHAPE locally so a regression is caught before dispatch.
run_hook "$C1" "$B/cishim:$PATH"
if [ "$RC" -eq 0 ] && ! has "$BLOCK_DIAG"; then ok "PY3-ci-shim-contract"
else bad "PY3-ci-shim-contract" "rc=$RC under the CI shim shape (exec python \"\$@\") — the hosted Windows job would go red: ${ERR:-<empty>}"; fi

# ---- PY4: `-c`-rejecting, `-S <file>`-honouring wrapper ----------------------------------------
run_hook "$C1" "$B/noc:$PATH"
if [ "$RC" -eq 0 ]; then ok "PY4-c-rejecting-wrapper-passes"
else bad "PY4-c-rejecting-wrapper-passes" "rc=$RC — a wrapper that supports the existing -S <file> interface was newly refused: ${ERR:-<empty>}"; fi
if ! has "$BLOCK_DIAG" && has "all checks passed"; then ok "PY4-c-support-not-a-requirement"
else bad "PY4-c-support-not-a-requirement" "the bounded file-script fallback did not prove the version; -S -c became a consumer requirement"; fi

# ---- PY5: probe/fallback error, timeout, malformed output --------------------------------------
run_hook "$C1" "$B/boom:$PATH"
if [ "$RC" -ne 0 ]; then ok "PY5-both-attempts-fail-blocks"
else bad "PY5-both-attempts-fail-blocks" "rc=0 although neither probe proved a version"; fi
if has "rc=7" && has "ffpv-boom"; then ok "PY5-failure-rc-and-stderr-retained"
else bad "PY5-failure-rc-and-stderr-retained" "the BLOCK dropped the probe rc or its bounded stderr: ${ERR:-<empty>}"; fi

run_hook "$C1" "$B/hang:$PATH"
hang_elapsed=$ELAPSED
timeouts="$(printf '%s' "$ERR" | grep -o 'TIMEOUT@10s' | grep -c .)"
if [ "$RC" -ne 0 ] && [ "${timeouts:-0}" -eq 2 ]; then ok "PY5-timeout-class-attributed"
else bad "PY5-timeout-class-attributed" "rc=$RC with ${timeouts:-0} bounded-attempt markers (expected rc!=0 and 2): ${ERR:-<empty>}"; fi
# <=10s per attempt, <=20s total (spec.md § S2d). The wall below also carries hook startup and the
# staged-set listing, so the assertion is the budget plus a fixed allowance, never the budget alone.
if [ "$hang_elapsed" -ge 16 ] && [ "$hang_elapsed" -le 26 ]; then ok "PY5-probe-budget-bounded"
else bad "PY5-probe-budget-bounded" "two bounded attempts took ${hang_elapsed}s (expected 16-26s: 2x<=10s probe budget plus hook startup)"; fi

run_hook "$C1" "$B/junk:$PATH"
if [ "$RC" -ne 0 ] && has "version=unproven"; then ok "PY5-malformed-output-blocks"
else bad "PY5-malformed-output-blocks" "rc=$RC — unparseable version output was not treated as unproven"; fi

# ---- PY6: the discovered `python` / `py -3` fallbacks keep their existing behaviour -------------
if [ ! -f "$FIXTURE" ]; then
  bad "PY6-python-fallback-retained" "missing $FIXTURE"
  bad "PY6-py3-fallback-retained" "missing $FIXTURE"
else
  # shellcheck source=/dev/null
  . "$FIXTURE"
  if mpf_build && mpf_exec_path; then
    printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$REALPY" > "$MPF_BIN/python"; chmod +x "$MPF_BIN/python"
    run_hook "$C1" "$MPF_PATH_EXEC"
    if [ "$RC" -eq 0 ] && has "using discovered 'python'" && ! has "$BLOCK_DIAG"; then ok "PY6-python-fallback-retained"
    else bad "PY6-python-fallback-retained" "rc=$RC — the §1b `python` discovery path changed: ${ERR:-<empty>}"; fi
    rm -f "$MPF_BIN/python"
    printf '#!/usr/bin/env bash\n[ "$1" = "-3" ] && shift\nexec "%s" "$@"\n' "$REALPY" > "$MPF_BIN/py"; chmod +x "$MPF_BIN/py"
    run_hook "$C1" "$MPF_PATH_EXEC"
    if [ "$RC" -eq 0 ] && has "using discovered 'py -3'" && ! has "$BLOCK_DIAG"; then ok "PY6-py3-fallback-retained"
    else bad "PY6-py3-fallback-retained" "rc=$RC — the §1b `py -3` discovery path changed: ${ERR:-<empty>}"; fi
    rm -f "$MPF_BIN/py"
  else
    bad "PY6-python-fallback-retained" "${MPF_REASON:-${MPF_EXEC_REASON:-fixture unavailable}}"
    bad "PY6-py3-fallback-retained" "${MPF_REASON:-${MPF_EXEC_REASON:-fixture unavailable}}"
  fi
fi

# ---- PY7: empty staged set -> early no-op, no probe, no residue ---------------------------------
( cd "$C1" && git reset -q HEAD -- . >/dev/null 2>&1 )
: > "$PYLOG"; run_hook "$C1" "$B/log:$PATH"
py7_calls="$(grep -c . "$PYLOG" 2>/dev/null || true)"
py7_probe="$(grep -c -e 'FFPCVER' -e '/v\.py' "$PYLOG" 2>/dev/null || true)"
if [ "$RC" -eq 0 ] && [ "${py7_probe:-1}" -eq 0 ] && [ "${py7_calls:-0}" -gt 0 ] && ! has "$BLOCK_DIAG"; then ok "PY7-empty-staged-set-no-probe"
else bad "PY7-empty-staged-set-no-probe" "rc=$RC probe_calls=${py7_probe:-?} total_python_calls=${py7_calls:-?} — expected rc=0, zero version-probe argv, and a non-zero total (so the absence is the STAGED_ANY guard, not a python-less run)"; fi
if [ "${RESIDUE:-1}" -eq 0 ]; then ok "PY7-empty-staged-set-no-temp-residue"
else bad "PY7-empty-staged-set-no-temp-residue" "${RESIDUE} entr(y|ies) survived in the run's private TMPDIR"; fi
( cd "$C1" && git add -- note.md >/dev/null 2>&1 )
# The probing paths must clean up too: a BLOCK never leaks its probe temp dir.
run_hook "$C1" "$B/boom:$PATH"
if [ "${RESIDUE:-1}" -eq 0 ]; then ok "PY5-block-leaves-no-temp-residue"
else bad "PY5-block-leaves-no-temp-residue" "${RESIDUE} entr(y|ies) survived in the run's private TMPDIR after a probe BLOCK"; fi

# ---- AC6 regression: first adoption / unborn HEAD -----------------------------------------------
run_hook "$C0" "$PATH"
if [ "$RC" -eq 0 ] && has "no HEAD yet (first-adoption bootstrap)"; then ok "AC6-unborn-head-regression"
else bad "AC6-unborn-head-regression" "rc=$RC — the unborn-HEAD bootstrap path changed: ${ERR:-<empty>}"; fi

# ---- production integrity: the harness never writes to the hook it exercises ---------------------
if cmp -s "$HOOK_SRC" "$TMP/hook-at-start"; then ok "hook-under-test-unmodified"
else bad "hook-under-test-unmodified" "$HOOK_SRC changed during this run"; fi

finish
