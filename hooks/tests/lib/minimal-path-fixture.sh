#!/usr/bin/env bash
# Fusebase Flow — deterministic minimal-PATH fixture: NO interpreter, git + shell intact.
# Spec: docs/specs/msys-test-fixture-rework/spec.md (AC2, AC7).
#
# Sourced (never executed) by hooks/tests/test-minimal-path-fixture.sh,
# test-pre-commit-interpreter-contract.sh, test-git-hooks-smoke.sh,
# test-pre-commit-interpreter-mutation.sh.
#
# API
#   mpf_build      0 -> MPF_BIN + MPF_PATH ready; nonzero -> MPF_REASON carries EXACTLY one cause
#   mpf_exec_path  0 -> MPF_PATH_EXEC, a minimal PATH a NATIVE (non-shell) child can exec git from
#   mpf_destroy    remove this fixture's bin dir
#   MPF_INJECT     interpreter-leak | missing-git | missing-shell | construction-fail
#
# The four causes, one per failed build (spec.md § Diagnostic injection matrix):
#   "interpreter leakage" · "Git unavailable" · "shell unavailable" · "fixture construction failed"
#
# TRIPWIRE — never enumerate, mirror, symlink or copy PATH directories (AC7). python3 and git
# share /usr/bin on Linux, and the Windows CI job provisions its own python3 dir: both are why
# tools are resolved BY NAME and re-exposed as absolute-exec shims only.
# TRIPWIRE — a failed build sets exactly ONE cause and returns immediately; a merged precondition
# boolean is the defect this fixture exists to replace.

# Explicit allowlist — the only names that may appear in the minimal bin. `git` and `bash` are
# mandatory; the rest are best-effort (a host lacking one is not a fixture failure).
MPF_TOOLS="${MPF_TOOLS:-git bash sh grep sed awk mktemp cat ls rm rmdir mkdir chmod cp mv wc basename dirname tr cut head tail sort env uname date}"
# Every name §1b of hooks/git/pre-commit can discover; all three must be unresolvable.
MPF_INTERPRETER_NAMES="${MPF_INTERPRETER_NAMES:-python3 python py}"

MPF_BIN=""
MPF_PATH=""
MPF_REASON=""
MPF_GIT=""
MPF_SHELL=""
MPF_SHIM_INTERP=""
MPF_PATH_EXEC=""
MPF_EXEC_REASON=""

# _mpf_pick_interp: absolute shebang interpreter for the shims. Absolute so shim execution never
# depends on the PATH the shims are about to replace.
# TRIPWIRE — a shebang cannot carry a space; an interpreter path with one is skipped, not quoted.
_mpf_pick_interp() {
  local c
  MPF_SHIM_INTERP=""
  for c in /bin/sh /bin/bash "$MPF_SHELL"; do
    case "$c" in ""|*" "*) continue ;; esac
    [ -x "$c" ] || continue
    MPF_SHIM_INTERP="$c"; return 0
  done
  return 1
}

# _mpf_shim <name> <absolute-target>: one exec shim. The target stays where it is — relocating a
# native binary breaks its adjacent DLL/library resolution on Windows.
_mpf_shim() {
  [ -n "$MPF_BIN" ] || return 1
  printf '#!%s\nexec "%s" "$@"\n' "$MPF_SHIM_INTERP" "$2" > "$MPF_BIN/$1" 2>/dev/null || return 1
  chmod +x "$MPF_BIN/$1" 2>/dev/null || return 1
  return 0
}

# _mpf_no_interpreter <path>: 0 iff none of MPF_INTERPRETER_NAMES resolves under <path>.
# MPF_LEAKED_NAME names the offender.
_mpf_no_interpreter() {
  local n
  MPF_LEAKED_NAME=""
  for n in $MPF_INTERPRETER_NAMES; do
    if PATH="$1" command -v "$n" >/dev/null 2>&1; then MPF_LEAKED_NAME="$n"; return 1; fi
  done
  return 0
}

mpf_build() {
  MPF_BIN=""; MPF_PATH=""; MPF_REASON=""; MPF_PATH_EXEC=""; MPF_EXEC_REASON=""
  local inject="${MPF_INJECT:-}" t abs

  # Resolve BEFORE masking — the fixture can only hand back what it captured while the host PATH
  # was still whole.
  MPF_GIT="$(command -v git 2>/dev/null || true)"
  MPF_SHELL="$(command -v bash 2>/dev/null || true)"
  [ -n "$MPF_GIT" ]   || { MPF_REASON="Git unavailable (no git on the host PATH before masking)"; return 1; }
  [ -n "$MPF_SHELL" ] || { MPF_REASON="shell unavailable (no bash on the host PATH before masking)"; return 1; }
  _mpf_pick_interp || { MPF_REASON="fixture construction failed (no space-free absolute shebang interpreter)"; return 1; }

  local root="${MPF_TMPROOT:-${TMPDIR:-/tmp}}"
  [ "$inject" = "construction-fail" ] && root="$root/ffmpf-absent-parent-$$"
  MPF_BIN="$(mktemp -d "$root/ffmpf.XXXXXX" 2>/dev/null)" || MPF_BIN=""
  if [ -z "$MPF_BIN" ] || [ ! -d "$MPF_BIN" ]; then
    MPF_BIN=""
    MPF_REASON="fixture construction failed (no temp bin under $root)"
    return 1
  fi

  for t in $MPF_TOOLS; do
    case "$inject:$t" in missing-git:git|missing-shell:bash) continue ;; esac
    abs="$(command -v "$t" 2>/dev/null || true)"
    [ -n "$abs" ] || continue
    _mpf_shim "$t" "$abs" || { MPF_REASON="fixture construction failed (could not write the '$t' shim)"; return 1; }
  done
  if [ "$inject" = "interpreter-leak" ]; then
    printf '#!%s\nexit 0\n' "$MPF_SHIM_INTERP" > "$MPF_BIN/python3" 2>/dev/null
    chmod +x "$MPF_BIN/python3" 2>/dev/null
  fi

  MPF_PATH="$MPF_BIN"
  _mpf_no_interpreter "$MPF_PATH" || {
    MPF_REASON="interpreter leakage ('$MPF_LEAKED_NAME' still resolves under the fixture PATH)"; return 1; }
  PATH="$MPF_PATH" git --version >/dev/null 2>&1 || {
    MPF_REASON="Git unavailable (git does not execute under the fixture PATH)"; return 1; }
  PATH="$MPF_PATH" bash -c ':' >/dev/null 2>&1 || {
    MPF_REASON="shell unavailable (bash does not execute under the fixture PATH)"; return 1; }
  return 0
}

# mpf_exec_path: the variant for rows whose hook run must reach the PYTHON stages. A native
# Windows child cannot exec a shell shim, so §3's `git` subprocess would vanish under MPF_PATH.
# Both candidates are MEASURED with the host interpreter, never assumed from the platform name,
# and the winner is re-proved interpreter-free.
mpf_exec_path() {
  MPF_PATH_EXEC=""; MPF_EXEC_REASON=""
  [ -n "$MPF_PATH" ] || { MPF_EXEC_REASON="fixture construction failed (build the fixture first)"; return 1; }
  local host_py cand
  host_py="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  [ -n "$host_py" ] || { MPF_EXEC_REASON="no host interpreter available to probe native exec with"; return 1; }
  for cand in "$MPF_PATH" "$MPF_PATH:$(dirname "$MPF_GIT")"; do
    _mpf_no_interpreter "$cand" || continue
    PATH="$cand" "$host_py" -c 'import subprocess,sys
try:
    sys.exit(subprocess.run(["git","--version"],capture_output=True).returncode)
except Exception:
    sys.exit(9)' >/dev/null 2>&1 || continue
    MPF_PATH_EXEC="$cand"; return 0
  done
  MPF_EXEC_REASON="no minimal PATH lets a native child exec git without exposing an interpreter"
  return 1
}

mpf_destroy() {
  case "${MPF_BIN:-}" in
    */ffmpf.*) rm -rf -- "$MPF_BIN" ;;
  esac
  MPF_BIN=""; MPF_PATH=""; MPF_PATH_EXEC=""
  return 0
}
