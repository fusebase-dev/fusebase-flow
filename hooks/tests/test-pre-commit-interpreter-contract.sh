#!/usr/bin/env bash
# Fusebase Flow — direct missing-interpreter contract for hooks/git/pre-commit §1b (AC3, AC4).
# Spec: docs/specs/msys-test-fixture-rework/spec.md. Relocated out of test-bootstrap-exception.sh,
# which owned it as scenario 8 while carrying its own copy of the PATH mask.
#
# Proves, on ONE hook invocation per claim:
#   - the SAME staged state PASSES on the normal PATH (so no other gate can supply the rc), and
#   - BLOCKS under the shared minimal PATH, terminally, naming the interpreter contract.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: interpreter-contract <name>" / "FAIL: interpreter-contract <name>"; exit = fail count.
#
# FFIC_HOOK=<path> runs the whole contract against a COPY of the hook instead of the tracked one.
# That is the oracle test-pre-commit-interpreter-mutation.sh drives; production hooks/git/pre-commit
# is never written to.
#
# TRIPWIRE — row names are space-free: the mutation harness compares baseline/mutant result sets by
# first token, so a parenthetical inside a name would silently split a row.
# TRIPWIRE — the staged path is BENIGN. Scenario 8 used to stage policies/protected-paths.yml, a
# PROTECTED path, so its `rc != 0` could come from the FR-07 check rather than from §1b.
# TRIPWIRE — 8-interpreter-absent-block-message deliberately does NOT re-assert rc. rc and message
# must flip independently, or a mutation that changes both collapses two rows into one delta and
# the one-row-delta oracle can no longer localize it.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FIXTURE="$ROOT/hooks/tests/lib/minimal-path-fixture.sh"
HOOK_SRC="${FFIC_HOOK:-$ROOT/hooks/git/pre-commit}"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: interpreter-contract $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: interpreter-contract $1 (${2:-})"; }
finish() { echo "[test-pre-commit-interpreter-contract] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$FIXTURE" ]  || { bad "fixture-present" "missing $FIXTURE"; finish; }
[ -f "$HOOK_SRC" ] || { bad "hook-source-present" "missing $HOOK_SRC"; finish; }
# shellcheck source=/dev/null
. "$FIXTURE"

command -v python3 >/dev/null 2>&1 || { ok "skipped-no-python3"; finish; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffic-contract.XXXXXX")"
cleanup() { mpf_destroy; case "$TMP" in "${TMPDIR:-/tmp}"/ffic-contract.*) rm -rf -- "$TMP" ;; esac; }
trap cleanup EXIT

# ---- 1. Shared fixture prerequisites, each reported on its own cause. ----
if mpf_build; then ok "fixture-prerequisites"
else bad "fixture-prerequisites" "${MPF_REASON:-unknown}"; finish; fi

leaked=""
for name in python3 python py; do
  PATH="$MPF_PATH" command -v "$name" >/dev/null 2>&1 && leaked="$leaked $name"
done
if [ -z "$leaked" ]; then ok "interpreter-absence-precondition"
else bad "interpreter-absence-precondition" "still resolvable:$leaked — §1b would discover and shim instead of blocking"; fi

if PATH="$MPF_PATH" git --version >/dev/null 2>&1; then ok "git-executable-precondition"
else bad "git-executable-precondition" "git is not executable under the fixture PATH — a git-less hook exits 0 at its rev-parse guard"; fi
if PATH="$MPF_PATH" bash -c ':' >/dev/null 2>&1; then ok "shell-executable-precondition"
else bad "shell-executable-precondition" "bash is not executable under the fixture PATH"; fi

# ---- 2. Consumer repo carrying the Flow bits §2/§3 need, plus the hook under test. ----
D="$TMP/consumer"
mkdir -p "$D/hooks/git"
cp -R "$ROOT/hooks/shared" "$D/hooks/shared"
cp -R "$ROOT/hooks/local"  "$D/hooks/local"
cp -R "$ROOT/policies"     "$D/policies"
cp "$HOOK_SRC" "$D/hooks/git/pre-commit"
( cd "$D" && git init -q && git config user.email t@example.com && git config user.name t \
    && git config core.autocrlf false )
printf '# consumer note\nhello world\n' > "$D/note.md"
( cd "$D" && git add note.md >/dev/null 2>&1 )

# ---- 3. AC4 wrong-reason guard: this exact staged state passes on the normal PATH. ----
( cd "$D" && bash hooks/git/pre-commit >/dev/null 2>&1 ); ctrl_rc=$?
if [ "$ctrl_rc" -eq 0 ]; then ok "8-normal-path-control-passes"
else bad "8-normal-path-control-passes" "rc=$ctrl_rc on the NORMAL PATH — another gate blocks this staged state, so a fixture-PATH rc!=0 would not be attributable to §1b"; fi

# ---- 4. The masked git still sees the staged file (else the hook has nothing to protect). ----
staged_seen="$(PATH="$MPF_PATH" git -C "$D" diff --cached --name-only 2>/dev/null)"
case "$staged_seen" in
  *note.md*) ok "8-git-mask-lists-staged-file" ;;
  *) bad "8-git-mask-lists-staged-file" "masked git could not list the staged benign file (saw: ${staged_seen:-<empty>})" ;;
esac

# ---- 5. AC3: ONE invocation supplies both rc and stderr. ----
NOPY_ERR="$TMP/nopy.err"
( cd "$D" && PATH="$MPF_PATH" bash hooks/git/pre-commit ) >/dev/null 2>"$NOPY_ERR"; nopy_rc=$?
nopy_out="$(cat "$NOPY_ERR" 2>/dev/null)"

# Terminality: §1b's refusal is the hook's LAST action. Without this clause, deleting §1b's
# `exit 1` still leaves rc != 0 (an empty FFPC_FOUND writes `exec  "$@"` and a later python3 call
# fails), so the row would pass against a hook that no longer blocks here.
post_marker=""
case "$nopy_out" in
  *"using discovered"*)                        post_marker="using discovered" ;;
  *"could not provision a python3 shim"*)      post_marker="could not provision a python3 shim" ;;
esac
if [ "$nopy_rc" -eq 0 ]; then
  bad "8-interpreter-absent-blocks" "rc=0 with NO interpreter — the commit proceeded with the FR-12 secret scan and the FR-07 check both unenforced (fail-open)"
elif [ -n "$post_marker" ]; then
  bad "8-interpreter-absent-blocks" "execution continued past §1b ('$post_marker') — rc=$nopy_rc came from a later stage, not from the interpreter block"
else
  case "$nopy_out" in
    *"no supported Python 3.10+ interpreter found"*) ok "8-interpreter-absent-blocks" ;;
    *) bad "8-interpreter-absent-blocks" "rc=$nopy_rc but §1b's diagnostic is absent, so the refusal is not attributable to the interpreter contract" ;;
  esac
fi

case "$nopy_out" in
  *"no supported Python 3.10+ interpreter found"*) ok "8-interpreter-absent-block-message" ;;
  *) bad "8-interpreter-absent-block-message" "stderr does not name the interpreter contract and the two controls it protects" ;;
esac

finish
