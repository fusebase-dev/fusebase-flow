#!/usr/bin/env bash
# Fusebase Flow — the MSYS capture-hang gate must be REAL, not a comment.
#
# The 2026-07-03 fix for msys-git-command-substitution-hang converted ONE call site and guarded
# it with a grep for that site's exact spelling. The class walked back in through wrapper
# functions and cost the v4.16.3 release. So this phase proves three things about
# hooks/local/check-git-capture.sh:
#   1. the gated surface is currently clean (the fix actually landed);
#   2. every reintroduction shape goes RED — direct, via a wrapper function, backtick, and a
#      whole-hook capture — i.e. the gate is not a string match and not vacuous;
#   3. legitimate non-git captures and file redirects stay GREEN (no false block).
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: git-capture-guard <name>" / "FAIL: git-capture-guard <name>"; exit = fail count.

set -uo pipefail

ROOT=""
_cap="$(mktemp 2>/dev/null || true)"
if [ -n "$_cap" ]; then
    git rev-parse --show-toplevel > "$_cap" 2>/dev/null || :
    IFS= read -r ROOT < "$_cap" 2>/dev/null || :
    rm -f "$_cap" 2>/dev/null
fi
[ -n "$ROOT" ] || ROOT="$(pwd)"

CHECK="$ROOT/hooks/local/check-git-capture.sh"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: git-capture-guard $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: git-capture-guard $1 (${2:-})"; }
finish() { echo "[test-git-capture-guard] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$CHECK" ] || { bad "gate-present" "missing $CHECK"; finish; }
ok "gate-present"
command -v python3 >/dev/null 2>&1 || { echo "PASS: git-capture-guard skipped-no-python3"; pass=$((pass + 1)); finish; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

# probe <name> <expect red|green> <shell source text>
probe() {
    local name="$1" expect="$2" body="$3" f rc
    f="$TMP/$name.sh"
    printf '%s\n' "$body" > "$f"
    bash "$CHECK" "$f" >"$TMP/$name.out" 2>&1; rc=$?
    if [ "$expect" = "red" ]; then
        if [ "$rc" -eq 1 ]; then ok "$name-is-rejected"
        else bad "$name-is-rejected" "the gate returned rc=$rc — a reintroduced capture was NOT caught: $(tr '\n' ' ' < "$TMP/$name.out" | cut -c1-160)"; fi
    else
        if [ "$rc" -eq 0 ]; then ok "$name-is-accepted"
        else bad "$name-is-accepted" "the gate FALSE-BLOCKED legitimate shell (rc=$rc): $(tr '\n' ' ' < "$TMP/$name.out" | cut -c1-160)"; fi
    fi
}

# 1. The shipped surface is clean. A gate whose own subject is dirty proves nothing.
if bash "$CHECK" >"$TMP/gated.out" 2>&1; then
    ok "gated-surface-is-clean"
else
    bad "gated-surface-is-clean" "$(tr '\n' ' ' < "$TMP/gated.out" | cut -c1-300)"
fi

# 2. The gated list is a real surface, not an empty allowlist that trivially passes.
gated_n="$(bash "$CHECK" --list | grep -c .)"
if [ "$gated_n" -ge 6 ] && bash "$CHECK" --list | grep -qx 'hooks/git/pre-commit' \
   && bash "$CHECK" --list | grep -qx 'hooks/tests/test-secret-scan-staged.sh'; then
    ok "gated-list-covers-the-commit-and-release-surface ($gated_n files)"
else
    bad "gated-list-covers-the-commit-and-release-surface" "list=$gated_n files; pre-commit or the release phase is missing"
fi

# 3. MUTATIONS — every reintroduction shape must go RED.
probe direct-capture red 'ROOT="$(git rev-parse --show-toplevel)"'
probe backtick-capture red 'ROOT=`git rev-parse --show-toplevel`'
# The one the previous guard could not see: no literal `$(git` anywhere in the file.
probe wrapper-function-capture red 'mkrepo() {
  local D; D="$(mktemp -d)"
  ( cd "$D" && git init -q && git commit -qm seed )
  echo "$D"
}
D="$(mkrepo)"'
# Two hops of indirection.
probe transitive-function-capture red 'inner() { git status --porcelain; }
outer() { inner; }
X="$(outer)"'
# Capturing the whole hook: the v4.16.3 shape.
probe hook-capture red 'ERR="$( ( cd "$D" && bash hooks/git/pre-commit ) 2>&1 >/dev/null )"'
# Nested inside another substitution.
probe nested-capture red 'X="$(printf "%s" "$(git rev-parse HEAD)")"'

# 4. NEGATIVES — the fixed patterns and ordinary shell must stay GREEN.
probe file-redirect-then-builtin-read green 'git rev-parse --show-toplevel > "$CAP" 2>/dev/null || :
IFS= read -r ROOT < "$CAP" || :'
probe non-git-capture green 'WL="$(grep -E "^whitelist:" "$F" | head -1)"
N="$(mktemp -d)"
V="$(python3 -c "print(1)")"'
probe git-mentioned-in-a-message green 'echo "unstage with \`git reset HEAD -- <file>\` first" >&2
bad "x" "still uses \$(git ls-tree ...) command substitution"'
probe git-inside-single-quotes green "printf '%s' 'run \$(git status) manually'"
probe file-read-substitution green 'git ls-tree HEAD -- "$s" > "$CAP" 2>/dev/null
OUT="$(<"$CAP")"'
probe quoted-heredoc-body green 'cat > "$T/x.py" <<'"'"'PY'"'"'
# $(git rev-parse HEAD) is inert python text here
PY'

# =============================================================================
# FAULT INJECTION — the mechanism, and the two properties the fix must have.
# A green run proves nothing here: these rows inject a descendant that RETAINS the inherited
# output handles past the hook's own exit, which is exactly what an MSYS native git grandchild
# does. Row A shows the capture shape blocking on that fault and the tempfile shape immune to
# it; row B shows a genuinely blocked hook bounded AT THE OPERATION and its tree reaped.
# =============================================================================
FAULT="$TMP/fault"; mkdir -p "$FAULT"
cat > "$FAULT/hook" <<'HOOK'
#!/usr/bin/env bash
# A descendant that outlives this script while holding its inherited stdout/stderr.
sleep 30 &
echo "$!" > "$(dirname "$0")/holder.pid"
printf '[fault-hook] BLOCK - secret pattern\n' >&2
exit 3
HOOK

# A. The capture shape BLOCKS on the retained handle; a bound around it is the only exit.
t0=$SECONDS
CAP_RC=0
timeout -k 5s 10 bash -c 'X="$( bash "$1" 2>&1 )"; printf "%s" "$X" >/dev/null' _ "$FAULT/hook" || CAP_RC=$?
CAP_EL=$((SECONDS - t0))
if [ "$CAP_RC" -eq 124 ] || [ "$CAP_RC" -eq 137 ]; then
  ok "retained-writer-blocks-a-command-substitution (capture still open ${CAP_EL}s after the hook exited 3 — the v4.16.3 mechanism, reproduced deterministically)"
else
  bad "retained-writer-blocks-a-command-substitution" "the capture returned rc=$CAP_RC in ${CAP_EL}s; this platform does not hold the substitution pipe, so row B carries the proof alone"
fi
[ -f "$FAULT/holder.pid" ] && { IFS= read -r hp < "$FAULT/holder.pid" || :; kill "$hp" 2>/dev/null; }
rm -f "$FAULT/holder.pid"

# A'. The SAME fault through the shipped tempfile capture: completes, keeps the diagnostics.
FFSS_LIB="$ROOT/hooks/local/lib/run-with-timeout.sh"
if [ -f "$FFSS_LIB" ]; then
  # shellcheck source=/dev/null
  . "$FFSS_LIB"; ffhc_detect_timeout
  t0=$SECONDS
  ffhc_run_bounded 60 bash "$FAULT/hook"
  BND_EL=$((SECONDS - t0))
  if [ "$FFHC_LAST_RC" -eq 3 ] && [ "$BND_EL" -lt 20 ] && echo "$FFHC_LAST_OUT" | grep -q 'BLOCK - secret pattern'; then
    ok "retained-writer-does-not-block-the-tempfile-capture (rc 3 in ${BND_EL}s with diagnostics intact)"
  else
    bad "retained-writer-does-not-block-the-tempfile-capture" "rc=$FFHC_LAST_RC elapsed=${BND_EL}s out='$(printf '%s' "$FFHC_LAST_OUT" | tr '\n' ' ' | cut -c1-120)'"
  fi
  [ -f "$FAULT/holder.pid" ] && { IFS= read -r hp < "$FAULT/holder.pid" || :; kill "$hp" 2>/dev/null; }

  # B. A hook that never returns: the OPERATION bound fires and the owned tree is reaped —
  #    the failure surfaces at its own call in seconds, not at an 1800s phase wall.
  cat > "$FAULT/stuck" <<'STUCK'
#!/usr/bin/env bash
printf '%s\n' "$$" > "$(dirname "$0")/stuck.pid"
sleep 600
STUCK
  t0=$SECONDS
  ffhc_run_bounded 8 bash "$FAULT/stuck"
  STUCK_EL=$((SECONDS - t0))
  if [ "$FFHC_LAST_TIMED_OUT" -eq 1 ] && [ "$STUCK_EL" -lt 30 ]; then
    ok "blocked-hook-is-bounded-at-the-operation (rc $FFHC_LAST_RC after ${STUCK_EL}s, deadline 8s)"
  else
    bad "blocked-hook-is-bounded-at-the-operation" "timed_out=$FFHC_LAST_TIMED_OUT rc=$FFHC_LAST_RC elapsed=${STUCK_EL}s — a block would only surface at the phase wall"
  fi
  sp=""; [ -f "$FAULT/stuck.pid" ] && { IFS= read -r sp < "$FAULT/stuck.pid" || :; }
  if [ -z "$sp" ]; then
    bad "blocked-hook-tree-is-reaped" "the stuck hook never recorded its pid, so cleanup is unproven"
  elif kill -0 "$sp" 2>/dev/null; then
    kill -9 "$sp" 2>/dev/null
    bad "blocked-hook-tree-is-reaped" "pid $sp survived the bound — the reap leaked a process tree"
  else
    ok "blocked-hook-tree-is-reaped (pid $sp gone after the deadline reap)"
  fi
else
  bad "retained-writer-does-not-block-the-tempfile-capture" "missing $FFSS_LIB"
fi

finish
