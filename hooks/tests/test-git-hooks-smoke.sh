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
cleanup() { case "$TMP" in "${TMPDIR:-/tmp}"/ffhc-git-smoke.*) rm -rf -- "$TMP" ;; esac; }
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
# (an `if` with no else) and §3 printed a WARN and committed with FR-07 unenforced. Both rows
# below are red against that tree: the first committed cleanly, the second warned and returned 0.
# Build the interpreter-less PATH with a GIT-PRESERVING FILTERED MIRROR (same technique as
# test-bootstrap-exception.sh row 8), never by dropping whole PATH entries: python3 and git
# share /usr/bin on Linux, so dropping that dir takes git with it and the hook exits 0 at its
# top `rev-parse` guard — the row then reports an environment ERROR instead of measuring the
# contract (observed on the hosted Windows runner). A dir holding no interpreter passes
# through; a dir holding one is mirrored into a temp bin, symlinking all but the interpreters.
# TRIPWIRE — exclude `py`/`pyw` too: the Windows launcher sits in its own dir with no python*,
# so a python*-only filter leaves `py -3` discoverable and the hook takes the DISCOVERY branch.
# TRIPWIRE — a system-wide launcher install puts py.exe in C:\Windows; refuse to mirror a dir
# that large rather than symlink (or, where `ln -s` is unavailable, COPY) thousands of entries.
NOPY_BIN="$TMP/nopy-bin"; mkdir -p "$NOPY_BIN"
NOPY_PATH="$NOPY_BIN"
nopy_toobig=""
_old_ifs="$IFS"; IFS=":"
for d in $PATH; do
  [ -d "$d" ] || continue
  if [ -e "$d/python3" ] || [ -e "$d/python" ] || [ -e "$d/python3.exe" ] || [ -e "$d/python.exe" ] \
     || [ -e "$d/py" ] || [ -e "$d/py.exe" ]; then
    _n="$(ls -1 "$d" 2>/dev/null | wc -l)"
    if [ "${_n:-0}" -gt 2000 ]; then nopy_toobig="$d (${_n} entries)"; break; fi
    for e in "$d"/*; do
      [ -e "$e" ] || continue
      b="$(basename "$e")"
      case "$b" in python|python3|python2*|python3.*|python.exe|python3.exe|py|py.exe|pyw|pyw.exe) continue ;; esac
      [ -e "$NOPY_BIN/$b" ] || ln -s "$e" "$NOPY_BIN/$b" 2>/dev/null || cp -p "$e" "$NOPY_BIN/$b" 2>/dev/null || true
    done
  else
    NOPY_PATH="$NOPY_PATH:$d"
  fi
done
IFS="$_old_ifs"
nopy_precondition=1
[ -n "$nopy_toobig" ] && nopy_precondition=0
PATH="$NOPY_PATH" command -v python3 >/dev/null 2>&1 && nopy_precondition=0
PATH="$NOPY_PATH" command -v python  >/dev/null 2>&1 && nopy_precondition=0
PATH="$NOPY_PATH" command -v py      >/dev/null 2>&1 && nopy_precondition=0
PATH="$NOPY_PATH" command -v git     >/dev/null 2>&1 || nopy_precondition=0
nopy_out="$( cd "$CONSUMER" \
  && printf '# staged under a python-less PATH\n' > nopy.md \
  && git add nopy.md >/dev/null 2>&1 \
  && PATH="$NOPY_PATH" bash "$PC" 2>&1 )"
nopy_rc=$?
if [ "$nopy_precondition" -ne 1 ]; then
  fail_case "pre-commit blocks when no python3 interpreter exists" \
            "could not construct an interpreter-less PATH that still has git${nopy_toobig:+ (refused to mirror oversized dir: $nopy_toobig)} — the row did not measure the interpreter contract"
elif [ "$nopy_rc" -eq 0 ]; then
  fail_case "pre-commit blocks when no python3 interpreter exists" \
            "rc=0 — the commit proceeded with the FR-12 secret scan and the FR-07 check both unenforced"
elif printf '%s' "$nopy_out" | grep -q "no supported Python 3.10+ interpreter found"; then
  pass_case "pre-commit blocks when no python3 interpreter exists"
else
  fail_case "pre-commit blocks when no python3 interpreter exists" \
            "rc=$nopy_rc but the reason does not name the interpreter contract, so the block is not attributable to it"
fi

# ... and when python3 is merely UNNAMED (Git Bash ships `python`, not `python3`), the hook
# must DISCOVER it and still enforce, rather than block a perfectly capable environment.
PY_REAL="$(command -v python 2>/dev/null || true)"
if [ -n "$PY_REAL" ] && [ "$nopy_precondition" -eq 1 ]; then
  # Put ONLY `python` back (a copy under its own dir), leaving python3 still unreachable.
  UNNAMED_BIN="$TMP/unnamed-py"; mkdir -p "$UNNAMED_BIN"
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$PY_REAL" > "$UNNAMED_BIN/python"
  chmod +x "$UNNAMED_BIN/python"
  shim_out="$( cd "$CONSUMER" && PATH="$UNNAMED_BIN:$NOPY_PATH" bash "$PC" 2>&1 )"
  shim_rc=$?
  if [ "$shim_rc" -eq 0 ] && printf '%s' "$shim_out" | grep -q "using discovered 'python'"; then
    pass_case "pre-commit discovers an unnamed python3 instead of blocking"
  else
    fail_case "pre-commit discovers an unnamed python3 instead of blocking" \
              "rc=$shim_rc — a host with a usable Python 3 under the name \`python\` must not be refused"
  fi
else
  # Not a skip-as-pass: state plainly that the discovery half was not measured here.
  echo "N/A: git-smoke pre-commit discovers an unnamed python3 — no bare \`python\` on this host to discover" >&2
fi

exit "$fail"
