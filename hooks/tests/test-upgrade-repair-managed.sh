#!/usr/bin/env bash
# Fusebase Flow — --repair-managed tests (T1 / AC3; decisions M1, M2, R2).
#
# Split from test-upgrade-source-boundary.sh on a responsibility seam: that phase owns WHICH
# BYTES may enter the consumer (materialize + verify + which source shapes are admitted); this
# one owns the deliberate, operator-named byte REPLACEMENT of paths a verifier already reported
# — its authority checks, its destination checks, and its write atomicity.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: upgrade-repair <name>" / "FAIL: upgrade-repair <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: upgrade-repair $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: upgrade-repair $1 (${2:-})"; }
# A platform that cannot BUILD a fixture reports an honest visible SKIP — never a silent
# green and never a claimed proof (same shape as test-msys-tree-cleanup.sh).
skip() { pass=$((pass + 1)); echo "PASS: upgrade-repair $1 [SKIP — $2]"; }
finish() { echo "[test-upgrade-repair-managed] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: upgrade-repair skipped-no-python3"; pass=1; finish; }
command -v git >/dev/null 2>&1 || { echo "PASS: upgrade-repair skipped-no-git"; pass=1; finish; }

# shellcheck source=lib/upgrade-fixtures.sh
. "$ROOT/hooks/tests/lib/upgrade-fixtures.sh"

# ---- 3. AC3: the already-corrupted consumer — preserve, then deliberate repair -------------
# Seeds the reported end state: base == upstream == LF, local == CRLF. An ordinary upgrade must
# call that consumer-only and PRESERVE it (it cannot know the CRLF was accidental); only an
# explicitly named repair may replace it. Exactly ONE path drifts, so the post-repair
# "manifest verifies MATCH" assertion is meaningful.
# M16 disposition (unchanged, by design not by retuning): this fixture's SOURCE declares only the
# managed layer and ships no verify wrapper, so the bound set is that one layer with no wrapper
# requirement — and the consumer carries its manifest. M16 refuses a partial CONSUMER; it does not
# invent a layer the source does not ship at that version.
RP_ROOT="$(mktemp -d)"
RP="$(bnd_plain_case "$RP_ROOT/case")"
printf 'wf v1\r\n' > "$RP/workflows/wf.md"        # the corruption: local CRLF, base+upstream LF
RP_LOG="$RP_ROOT/ordinary.log"
( cd "$RP" && bash hooks/local/upgrade.sh --auto-yes ) > "$RP_LOG" 2>&1
rp_fail=""
has_cr "$RP/workflows/wf.md" || rp_fail="$rp_fail [ordinary upgrade REPLACED the corrupted file — it must preserve and report it]"
grep -q -- "- workflows/wf.md" "$RP_LOG" || rp_fail="$rp_fail [the preserved path was not reported]"
python3 "$MCM" verify --root "$RP" >/dev/null 2>&1 \
  && rp_fail="$rp_fail [manifest verifies MATCH while the file is still CRLF — the fixture is not seeded]"
# A path named TWICE is refused up front: staging it over its own staging file would fail the
# second swap into a rollback instead of a clean "nothing was written".
( cd "$RP" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
    --repair-managed workflows/wf.md --repair-managed workflows/wf.md ) > "$RP_ROOT/dup.log" 2>&1
rc=$?
[ "$rc" -ne 0 ] || rp_fail="$rp_fail [repair ACCEPTED the same path twice]"
grep -q "named more than once" "$RP_ROOT/dup.log" || rp_fail="$rp_fail [the duplicate path was not refused by name :: $(tail -4 "$RP_ROOT/dup.log" | tr '\n' '|')]"
has_cr "$RP/workflows/wf.md" || rp_fail="$rp_fail [the duplicate-path run replaced the file anyway]"
# Staging residue only: the ordinary upgrade above legitimately left .pre-upgrade-<ts> twins.
[ -z "$(find "$RP" -name '*.ff-repair-*' 2>/dev/null)" ] \
  || rp_fail="$rp_fail [the duplicate-path refusal left staging residue behind]"
# Negative controls: repair refuses a path no verifier reported, an unmanaged path, and traversal.
for badpath in "hooks/local/control.sh" "docs/not-managed.md" "../escape.md"; do
  ( cd "$RP" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
      --repair-managed "$badpath" ) > "$RP_ROOT/refuse.log" 2>&1
  rc=$?
  [ "$rc" -ne 0 ] || rp_fail="$rp_fail [repair ACCEPTED unreported/unmanaged path $badpath]"
  grep -q "REFUSED" "$RP_ROOT/refuse.log" || rp_fail="$rp_fail [no refusal diagnostic for $badpath]"
done
grep -q "control v2" "$RP/hooks/local/control.sh" || rp_fail="$rp_fail [a refused repair still wrote something]"
# The authorized repair: the exact verifier-reported path, named explicitly on the CLI.
RP_FIX="$RP_ROOT/repair.log"
( cd "$RP" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
    --repair-managed workflows/wf.md ) > "$RP_FIX" 2>&1
RP_FIX_RC=$?
has_cr "$RP/workflows/wf.md" && rp_fail="$rp_fail [authorized repair did not replace the CRLF bytes]"
[ "$RP_FIX_RC" -eq 0 ] || rp_fail="$rp_fail [post-repair verification did not reach MATCH (rc $RP_FIX_RC)]"
python3 "$MCM" verify --root "$RP" >/dev/null 2>&1 \
  || rp_fail="$rp_fail [manifest still does not verify MATCH after repair]"
if [ -z "$rp_fail" ]; then
  ok "ac3-ordinary-upgrade-preserves-only-named-repair-replaces"
else
  bad "ac3-ordinary-upgrade-preserves-only-named-repair-replaces" "$rp_fail :: $(tail -10 "$RP_FIX" | tr '\n' '|')"
fi
rm -rf "$RP_ROOT"

# ---- 3c. AC3 / R2: repair never writes THROUGH a destination symlink ----------------------
# The verifier's own is_file()/hashing FOLLOW a consumer symlink, so a managed path linked to an
# external file is reported as drifted and used to be accepted — `cp` then overwrote the external
# target. Both fixtures are otherwise fully eligible (the exact path the verifier reported, shipped
# by the source), so symlink-ness is the ONLY reason either may be refused, and the assertions pin
# that reason. Coverage is all-or-nothing: MSYS `ln -s` silently COPIES unless winsymlinks is on,
# and a copy is a legitimate repair target, so an unchecked fixture would pass for the wrong reason.
R2_ROOT="$(mktemp -d)"
R2_OUT="$(mktemp -d)"
r2s_fail=""; r2s_ran=0; r2s_expected=2
r2_mk_symlink() {   # <link> <target> -> rc 1 if the platform made a copy instead
  ln -s "$2" "$1" 2>/dev/null || return 1
  [ -L "$1" ] || return 1
  return 0
}
for kind in leaf parent; do
  S="$(bnd_plain_case "$R2_ROOT/sym-$kind")"
  if [ "$kind" = "leaf" ]; then
    printf 'outside bytes\n' > "$R2_OUT/leaf-wf.md"
    rm -f "$S/workflows/wf.md"
    r2_mk_symlink "$S/workflows/wf.md" "$R2_OUT/leaf-wf.md" || { rm -rf "$S"; continue; }
    OUTFILE="$R2_OUT/leaf-wf.md"; LINK="$S/workflows/wf.md"
  else
    mkdir -p "$R2_OUT/wfdir"; printf 'outside bytes\n' > "$R2_OUT/wfdir/wf.md"
    rm -rf "$S/workflows"
    r2_mk_symlink "$S/workflows" "$R2_OUT/wfdir" || { rm -rf "$S"; continue; }
    OUTFILE="$R2_OUT/wfdir/wf.md"; LINK="$S/workflows"
  fi
  r2s_ran=$((r2s_ran + 1))
  # PRECONDITION: the path must actually be REPORTED, or the refusal proves nothing about symlinks.
  # TRIPWIRE (pipefail): capture first, match with `case` — never `producer | grep -q`. grep -q
  # exits at the first match, the producer takes SIGPIPE, and under `set -o pipefail` the PIPELINE
  # reports 141 even though the line WAS found (this precondition went falsely red on Linux).
  R2_VERIFY="$(python3 "$MCM" verify --root "$S" --json 2>/dev/null || true)"
  case "$R2_VERIFY" in
    *'"workflows/wf.md"'*) ;;
    *) r2s_fail="$r2s_fail [$kind: PRECONDITION — the verifier does not report workflows/wf.md, so this fixture cannot exercise the accepted-symlink path :: $(printf '%s' "$R2_VERIFY" | tr '\n' ' ' | cut -c1-200)]" ;;
  esac
  R2_LOG="$R2_ROOT/sym-$kind.log"
  ( cd "$S" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
      --repair-managed workflows/wf.md ) > "$R2_LOG" 2>&1
  r2_rc=$?
  [ "$r2_rc" -ne 0 ] || r2s_fail="$r2s_fail [$kind: repair ACCEPTED a symlinked destination (rc 0)]"
  grep -q "REFUSED" "$R2_LOG" || r2s_fail="$r2s_fail [$kind: no refusal diagnostic]"
  grep -q "symlink" "$R2_LOG" || r2s_fail="$r2s_fail [$kind: refused for the WRONG reason — no 'symlink' in the diagnostic :: $(tail -4 "$R2_LOG" | tr '\n' '|')]"
  grep -q "outside bytes" "$OUTFILE" || r2s_fail="$r2s_fail [$kind: the file OUTSIDE the repo was overwritten through the link]"
  [ -L "$LINK" ] || r2s_fail="$r2s_fail [$kind: the symlink itself was replaced]"
  [ -z "$(find "$S" -name '*.pre-upgrade-*' -o -name '*.ff-repair-*' 2>/dev/null)" ] \
    || r2s_fail="$r2s_fail [$kind: a refused repair left backup/staging artifacts behind]"
  [ -z "$(find "$R2_OUT" -name '*.pre-upgrade-*' 2>/dev/null)" ] \
    || r2s_fail="$r2s_fail [$kind: a backup twin was written OUTSIDE the repo]"
  rm -rf "$S"
done
[ "$r2s_ran" -eq 0 ] || [ "$r2s_ran" -eq "$r2s_expected" ] \
  || r2s_fail="$r2s_fail [PARTIAL COVERAGE: only $r2s_ran/$r2s_expected symlink classes were built — leaf AND parent are both required]"
if [ "$r2s_ran" -eq 0 ]; then
  skip "ac3-repair-refuses-symlinked-destinations" "this platform's ln -s copies instead of linking (MSYS winsymlinks off) — the fixture cannot be built, so the control is NOT claimed as proof (its proof home is the Linux/CI run)"
elif [ -z "$r2s_fail" ]; then
  ok "ac3-repair-refuses-symlinked-destinations ($r2s_ran/$r2s_expected classes: leaf + parent symlink to an outside target, each refused WITH a 'symlink' reason; the external file untouched)"
else
  bad "ac3-repair-refuses-symlinked-destinations" "$r2s_fail"
fi
rm -rf "$R2_OUT"

# ---- 3d/3e. AC3 / R2: a multi-path repair is WRITE-atomic, not just validation-atomic -------
# Shared fixture: TWO genuinely drifted, genuinely repairable managed paths, so "path 1 was left
# replaced" is the only way either case can go red.
rb_case() {   # <dir> -> echoes the consumer root; path1 = workflows/wf.md, path2 = workflows/extra.md
  local C
  C="$(bnd_plain_case "$1")"
  printf 'extra v1\n' > "$C/workflows/extra.md"
  printf 'extra v1\n' > "$C/.fusebase-flow-source/workflows/extra.md"
  ( cd "$C" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  ( cd "$C/.fusebase-flow-source" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  printf 'wf v1\r\n'    > "$C/workflows/wf.md"      # drift 1: CRLF corruption
  printf 'extra EDIT\n' > "$C/workflows/extra.md"   # drift 2: content divergence
  echo "$C"
}
rb_residue() {   # <root> -> echoes every artifact a clean refusal/rollback must not leave
  find "$1" -name '*.pre-upgrade-*' -o -name '*.ff-repair-*' 2>/dev/null
}

# 3d. PREFLIGHT (portable): path 2's destination is a DIRECTORY. `cp file dir` and `mv file dir`
# both write INSIDE it and report success, so this must be refused before anything is staged —
# path 1 included.
RB="$(rb_case "$R2_ROOT/preflight")"
rm -f "$RB/workflows/extra.md"; mkdir -p "$RB/workflows/extra.md"
printf 'blocker\n' > "$RB/workflows/extra.md/blocker"
RB_LOG="$R2_ROOT/preflight.log"
( cd "$RB" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
    --repair-managed workflows/wf.md --repair-managed workflows/extra.md ) > "$RB_LOG" 2>&1
RB_RC=$?
rb_fail=""
[ "$RB_RC" -ne 0 ] || rb_fail="$rb_fail [a batch whose second destination is a directory exited 0]"
grep -q "REFUSED" "$RB_LOG" || rb_fail="$rb_fail [no refusal diagnostic]"
has_cr "$RB/workflows/wf.md" || rb_fail="$rb_fail [PARTIAL APPLY: path 1 was replaced although path 2 was rejected]"
[ -f "$RB/workflows/extra.md/blocker" ] || rb_fail="$rb_fail [path 2's blocking directory was damaged]"
[ ! -e "$RB/workflows/extra.md/extra.md" ] || rb_fail="$rb_fail [repair wrote INSIDE the directory (cp/mv target-directory semantics) and called it a replacement]"
[ -z "$(rb_residue "$RB")" ] || rb_fail="$rb_fail [refusal left artifacts behind: $(rb_residue "$RB" | tr '\n' ' ')]"
if [ -z "$rb_fail" ]; then
  ok "ac3-repair-preflights-every-destination-before-writing-any"
else
  bad "ac3-repair-preflights-every-destination-before-writing-any" "rc=$RB_RC$rb_fail :: $(tail -8 "$RB_LOG" | tr '\n' '|')"
fi

# 3e. ROLLBACK (portable): drive ff_repair_managed directly with `mv` stubbed to fail on the
# SECOND staged swap. Once preflight rejects every PREDICTABLE failure, the apply-phase rollback
# is only reachable through an unpredictable one (ENOSPC, a permission race) — and an untested
# rollback is exactly the branch a later "simplification" deletes. A shell function shadows the
# external command inside the sourced lib, so no test-only hook exists in production code.
RB2="$(rb_case "$R2_ROOT/rollback")"
RB2_LOG="$R2_ROOT/rollback.log"
(
  set +e
  . "$ROOT/hooks/local/lib/materialize-managed-source.sh"
  _mv_swaps=0
  mv() {
    case "$*" in
      *.ff-repair-staged*)
        _mv_swaps=$((_mv_swaps + 1))
        [ "$_mv_swaps" -eq 2 ] && return 1 ;;
    esac
    command mv "$@"
  }
  ff_repair_managed "$RB2" "$RB2/.fusebase-flow-source" "20260730T120000Z" \
    workflows/wf.md workflows/extra.md
  echo "rc=$?"
) > "$RB2_LOG" 2>&1
rb2_fail=""
grep -q "^rc=0$" "$RB2_LOG" && rb2_fail="$rb2_fail [a failed swap reported success]"
has_cr "$RB2/workflows/wf.md" || rb2_fail="$rb2_fail [PARTIAL APPLY: path 1 stayed REPLACED after path 2's swap failed — no rollback]"
grep -q "extra EDIT" "$RB2/workflows/extra.md" || rb2_fail="$rb2_fail [path 2 was modified although its swap failed]"
grep -q "rolled back" "$RB2_LOG" || rb2_fail="$rb2_fail [no rollback diagnostic — the operator cannot tell the batch was undone]"
[ -z "$(rb_residue "$RB2")" ] || rb2_fail="$rb2_fail [rollback left artifacts behind: $(rb_residue "$RB2" | tr '\n' ' ')]"
if [ -z "$rb2_fail" ]; then
  ok "ac3-repair-rolls-the-whole-batch-back-when-a-swap-fails"
else
  bad "ac3-repair-rolls-the-whole-batch-back-when-a-swap-fails" "$rb2_fail :: $(tail -8 "$RB2_LOG" | tr '\n' '|')"
fi
rm -rf "$R2_ROOT"

# 3b. AC3 carrier: the integrity checker names the repair command and no longer offers
#     `git checkout -- <file>` for a BYTE mismatch (it restores the same wrong bytes).
HIC="$ROOT/hooks/local/lib/hook-integrity-check.sh"
hic_line="$(grep -n "FLOW_LAYER_DRIFT" "$HIC" | head -1)"
hic_fail=""
case "$hic_line" in
  *"--repair-managed"*) ;; *) hic_fail="$hic_fail [drift recovery text does not name --repair-managed]" ;;
esac
case "$hic_line" in
  *"git checkout -- "*) hic_fail="$hic_fail [drift recovery text still offers 'git checkout --' for a byte mismatch]" ;;
esac
if [ -z "$hic_fail" ]; then
  ok "ac3-integrity-checker-names-the-repair-not-git-checkout"
else
  bad "ac3-integrity-checker-names-the-repair-not-git-checkout" "$hic_fail"
fi

# ---- 3f. B8: the POST-REPAIR verdict is a verdict, and was reached by a bare interpreter ----
# Repair's entire product is the claim "these bytes are now provably what upstream shipped". The
# hop used to establish that by running hooks/local/verify-*.sh and branching on their EXIT
# CODES — and both wrappers exec a bare python3 (verify-hook-manifest.sh even took the
# interpreter from a caller-supplied $PYTHON). So the last step of the one operation that exists
# to restore provable bytes could be forged by the same startup-file trick B5 closed at the
# source boundary, one path further along.
#
# TWO drifted paths, ONE repaired: an honest verdict must still say DRIFT, so a run that reports
# success can only have got there by forging. That is what makes this a discriminator rather
# than a re-test of the happy path (case 3 already covers a genuine repair reaching MATCH).
B8_ROOT="$(mktemp -d)"
B8="$(bnd_plain_case "$B8_ROOT/case")"
printf 'wf v1\r\n'          > "$B8/workflows/wf.md"          # drift 1 — the one we will repair
printf 'control TAMPERED\n' > "$B8/hooks/local/control.sh"   # drift 2 — left alone on purpose
mkdir -p "$B8/hooks"
cat > "$B8/hooks/sitecustomize.py" <<'B8FORGE'
import os, sys
sys.stdout.write('{"verdict": "MATCH", "listed": 0, "files": []}\n')
sys.stdout.flush()
os._exit(0)
B8FORGE
B8_LOG="$B8_ROOT/repair.log"
( cd "$B8" && PYTHONPATH="$B8/hooks" bash hooks/local/bootstrap-upgrade.sh \
    --source .fusebase-flow-source --repair-managed workflows/wf.md ) > "$B8_LOG" 2>&1
B8_RC=$?
b8_fail=""
[ "$B8_RC" -ne 0 ] \
  || b8_fail="$b8_fail [a hostile python startup file forged the post-repair verdict: the hop reported a clean tree (rc 0) while hooks/local/control.sh was still drifted]"
grep -q "REPAIR UNVERIFIED" "$B8_LOG" \
  || b8_fail="$b8_fail [no REPAIR UNVERIFIED diagnostic — the operator is not told the repair is unconfirmed]"
grep -q "hooks/local/control.sh" "$B8_LOG" \
  || b8_fail="$b8_fail [the still-drifted path is not named]"
has_cr "$B8/workflows/wf.md" \
  && b8_fail="$b8_fail [the named path was not actually repaired — this case must fail for the VERDICT, not for a broken repair]"
if [ -z "$b8_fail" ]; then
  ok "b8-post-repair-verdict-cannot-be-forged-by-a-hostile-interpreter"
else
  bad "b8-post-repair-verdict-cannot-be-forged-by-a-hostile-interpreter" "rc=$B8_RC$b8_fail :: $(tail -8 "$B8_LOG" | tr '\n' '|')"
fi

# 3g. The wrapper itself: its exit code is consumed by the health engine, preflight, CI and the
# hop, so a caller-chosen interpreter must not be able to pick the verdict. `PYTHON=<anything
# that exits 0>` used to be enough, and so did a sitecustomize on an inherited PYTHONPATH.
# The fixture carries its OWN copy of the wrapper and the module: running the repo's copy against
# the repo would prove nothing (it is clean, so every interpreter agrees), and asserting on a
# path where the script does not exist would pass on bash's 127.
B8W="$B8_ROOT/wrapper"
mkdir -p "$B8W/hooks/local/lib" "$B8W/hooks/handlers"
( cd "$B8W" && git init -q && git config user.email t@t.t && git config user.name t )
cp "$ROOT/hooks/local/lib/hook_manifest.py" "$B8W/hooks/local/lib/"
cp "$ROOT/hooks/local/verify-hook-manifest.sh" "$B8W/hooks/local/"
printf 'handler v1\n' > "$B8W/hooks/handlers/session_start.py"
( cd "$B8W" && python3 hooks/local/lib/hook_manifest.py stamp --root . >/dev/null 2>&1 )
cat > "$B8_ROOT/fakepy" <<'FAKEPY'
#!/usr/bin/env bash
exit 0
FAKEPY
chmod +x "$B8_ROOT/fakepy"
b8w_fail=""
[ -f "$B8W/audit/hook-layer-manifest.json" ] \
  || b8w_fail="$b8w_fail [fixture did not stamp a hook-layer manifest — the case would prove nothing]"
b8w_rc() { local rc=0; ( cd "$B8W" && env "$@" bash hooks/local/verify-hook-manifest.sh >/dev/null 2>&1 ) || rc=$?; echo "$rc"; }
# Control FIRST, on a genuinely clean tree: the wrapper must still verify 0 under isolation.
# (The sitecustomize.py below is itself hook-layer drift — hook_manifest.py Scan B flags python
# startup files — so it cannot be dropped until after this check, or the control tests nothing.)
[ "$(b8w_rc FF_NOOP=1)" = "0" ] \
  || b8w_fail="$b8w_fail [the wrapper no longer verifies a CLEAN tree — isolation broke it]"
printf 'handler TAMPERED\n' > "$B8W/hooks/handlers/session_start.py"
[ "$(b8w_rc FF_NOOP=1)" != "0" ] \
  || b8w_fail="$b8w_fail [the wrapper does not report drift at all — the case is vacuous]"
# Now the forgeries, against that same drifted tree.
cat > "$B8W/hooks/sitecustomize.py" <<'B8WFORGE'
import os, sys
sys.stdout.write('[hook-manifest] verify: MATCH (listed=0 matched=0)\n')
sys.stdout.flush()
os._exit(0)
B8WFORGE
[ "$(b8w_rc PYTHON="$B8_ROOT/fakepy")" != "0" ] \
  || b8w_fail="$b8w_fail [PYTHON= chose the verdict: a drifted tree verified clean through a caller-supplied interpreter]"
[ "$(b8w_rc PYTHONPATH="$B8W/hooks")" != "0" ] \
  || b8w_fail="$b8w_fail [a sitecustomize on an inherited PYTHONPATH forged a clean verify-hook-manifest.sh exit]"
if [ -z "$b8w_fail" ]; then
  ok "b8-verify-wrapper-exit-code-is-not-caller-selectable"
else
  bad "b8-verify-wrapper-exit-code-is-not-caller-selectable" "$b8w_fail"
fi
rm -rf "$B8_ROOT"

# ---- 3h. M13/M16: the repair confirms the layer set the VERIFIED SOURCE declares --------------
# Decision M13 settles what "repair confirmed" means: the required set is bound BEFORE any write
# and cannot shrink; every bound layer must return rc 0 AND a parsed exact MATCH; a bound layer
# whose manifest or wrapper is gone at verification time FAILS rather than being skipped.
# Decision M16 settles what puts a layer IN that set: the VERIFIED SOURCE tree's own coverage
# list — $SOURCE_TREE/<manifest-rel> — never the consumer tree being repaired. M14's consumer-side
# rule ("either artifact present here") made "this install never carried the layer" and "both its
# artifacts were deleted a second ago" the same observation; 3h-6 is that exploit.
#
# The verifier doubles below live in the SOURCE tree and are re-stamped into its manifest,
# because that is exactly what a plain --source directory can do: snapshot, payload, verifier
# and manifest share ONE authority there, so a swap is self-consistent by construction (the
# plain-source trust disclosure this release carries). Each double delegates every call to the
# real module — the source verdict and the drift enumeration that authorizes the repair are
# unchanged — and adds its named behaviour only against a root that is NOT its own tree.
m13_double() {   # <source tree> <mode: liar|unlink-manifest|unlink-wrapper>
  local U="$1" mode="$2" L="$1/hooks/local/lib"
  mv "$L/managed_content_manifest.py" "$L/_ff_real_manifest.py"
  { echo "MODE = \"$mode\""; cat <<'PYDOUBLE'
import io, os, runpy, sys
from contextlib import redirect_stdout
HERE = os.path.dirname(os.path.abspath(__file__))
REAL = os.path.join(HERE, "_ff_real_manifest.py")
argv = sys.argv[1:]
root = ""
for i, a in enumerate(argv):
    if a == "--root" and i + 1 < len(argv):
        root = argv[i + 1]
buf = io.StringIO()
rc = 0
try:
    with redirect_stdout(buf):
        runpy.run_path(REAL, run_name="__main__")
except SystemExit as e:
    rc = e.code if isinstance(e.code, int) else 0
sys.stdout.write(buf.getvalue())
sys.stdout.flush()
own = bool(root) and os.path.realpath(HERE).startswith(os.path.realpath(root) + os.sep)
if argv[:1] == ["verify"] and not own:
    if MODE == "liar" and rc == 0:
        sys.exit(1)          # stdout says MATCH; the exit code says the run did not finish
    if MODE == "unlink-manifest":
        try:
            os.unlink(os.path.join(root, "audit", "managed-content-manifest.json"))
        except OSError:
            pass
    if MODE == "unlink-wrapper":
        try:
            os.unlink(os.path.join(root, "hooks", "local", "verify-managed-content-manifest.sh"))
        except OSError:
            pass
sys.exit(rc)
PYDOUBLE
  } > "$L/managed_content_manifest.py"
  # Re-stamp what the swap changed, hook layer first: audit/hook-layer-manifest.json is itself
  # managed content, so a stale one would abort the source verdict for the wrong reason.
  [ -f "$U/audit/hook-layer-manifest.json" ] \
    && ( cd "$U" && python3 hooks/local/lib/hook_manifest.py stamp --root . >/dev/null )
  ( cd "$U" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
}

# A consumer that carries BOTH manifest layers and both verify wrappers — the shape in which
# "which layers must confirm this repair" is a real question. hooks/handlers/session_start.py is
# covered by both layers; workflows/wf.md by the managed layer only, which is what makes an
# unnoticed managed-layer skip observable.
m13_dual_case() {   # <dir> -> echoes the consumer root
  local C d
  C="$(bnd_plain_case "$1")"
  for d in "$C" "$C/.fusebase-flow-source"; do
    mkdir -p "$d/hooks/handlers"
    printf 'handler v1\n' > "$d/hooks/handlers/session_start.py"
    cp "$ROOT/hooks/local/lib/hook_manifest.py" "$d/hooks/local/lib/"
    cp "$ROOT/hooks/local/verify-hook-manifest.sh" \
       "$ROOT/hooks/local/verify-managed-content-manifest.sh" "$d/hooks/local/"
    ( cd "$d" && python3 hooks/local/lib/hook_manifest.py stamp --root . >/dev/null )
    ( cd "$d" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  done
  echo "$C"
}

m13_repair() {   # <consumer root> <log> <path>... -> echoes rc
  local C="$1" LOG="$2"; shift 2
  local args=() p rc=0
  for p in "$@"; do args+=(--repair-managed "$p"); done
  ( cd "$C" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
      "${args[@]}" ) > "$LOG" 2>&1 || rc=$?
  echo "$rc"
}

M13_ROOT="$(mktemp -d)"

# 3h-1. rc is half the verdict. ff_boot_verify and _ff_mms_verify both require rc 0 AND an exact
# MATCH; the post-repair check parsed the verdict and never captured $?. A verifier that reports
# MATCH and then dies — truncated write, an error after the report, a signal — was therefore a
# confirmed repair. The double prints the REAL MATCH json and exits 1.
A1="$(bnd_plain_case "$M13_ROOT/rc")"
printf 'wf v1\r\n' > "$A1/workflows/wf.md"
m13_double "$A1/.fusebase-flow-source" liar
A1_LOG="$M13_ROOT/rc.log"
A1_RC="$(m13_repair "$A1" "$A1_LOG" workflows/wf.md)"
a1_fail=""
[ "$A1_RC" -ne 0 ] \
  || a1_fail="$a1_fail [the hop confirmed a repair on a verifier that printed MATCH and exited 1]"
grep -q "REPAIR UNVERIFIED" "$A1_LOG" || a1_fail="$a1_fail [no REPAIR UNVERIFIED diagnostic]"
has_cr "$A1/workflows/wf.md" \
  && a1_fail="$a1_fail [the named path was not repaired — this case must fail for the VERDICT, not for a broken repair]"
if [ -z "$a1_fail" ]; then
  ok "m13-a-parsed-match-with-a-nonzero-verifier-rc-is-not-a-confirmed-repair"
else
  bad "m13-a-parsed-match-with-a-nonzero-verifier-rc-is-not-a-confirmed-repair" "rc=$A1_RC$a1_fail :: $(tail -6 "$A1_LOG" | tr '\n' '|')"
fi

# 3h-2. The set is bound BEFORE the first write, so a layer cannot leave it mid-run. The double
# unlinks the consumer's managed-content manifest during the drift enumeration that authorizes
# the repair — after the bind, before the re-check. Keyed on the manifest, the re-check called
# that "this install ships no manifest" and exited 0.
B1="$(bnd_plain_case "$M13_ROOT/vanish")"
printf 'wf v1\r\n' > "$B1/workflows/wf.md"
m13_double "$B1/.fusebase-flow-source" unlink-manifest
B1_LOG="$M13_ROOT/vanish.log"
B1_RC="$(m13_repair "$B1" "$B1_LOG" workflows/wf.md)"
b1_fail=""
[ -f "$B1/audit/managed-content-manifest.json" ] \
  && b1_fail="$b1_fail [PRECONDITION: the manifest did not disappear, so nothing was exercised]"
[ "$B1_RC" -ne 0 ] \
  || b1_fail="$b1_fail [a bound layer left the set mid-run and the hop still confirmed the repair]"
grep -q "REPAIR UNVERIFIED" "$B1_LOG" || b1_fail="$b1_fail [no REPAIR UNVERIFIED diagnostic]"
grep -q "authoriz" "$B1_LOG" || b1_fail="$b1_fail [the diagnostic does not say the layer was bound at authorization]"
has_cr "$B1/workflows/wf.md" \
  && b1_fail="$b1_fail [the named path was not repaired — this case must fail for the VERDICT, not for a broken repair]"
if [ -z "$b1_fail" ]; then
  ok "m13-a-manifest-that-disappears-after-authorization-fails-instead-of-skipping"
else
  bad "m13-a-manifest-that-disappears-after-authorization-fails-instead-of-skipping" "rc=$B1_RC$b1_fail :: $(tail -6 "$B1_LOG" | tr '\n' '|')"
fi

# 3h-3. Consumer missing ONLY the manifest of a source-declared layer, with the wrapper still in
# place: the hook layer reports the drift (so the repair is authorized) while the managed manifest
# is already gone and unrelated managed-only drift sits in the tree. Keyed on the manifest, the
# managed layer was skipped, the hook layer said MATCH, and the hop exited 0 with the tree dirty.
# COVERAGE for the M16 delta — this already FAILed at 2d88844 (M14 bound the layer through its
# wrapper); under M16 it fails because the verified source declares the layer, wrapper or not.
C1="$(m13_dual_case "$M13_ROOT/anchor")"
printf 'handler TAMPERED\n' > "$C1/hooks/handlers/session_start.py"
printf 'wf v1\r\n'          > "$C1/workflows/wf.md"
rm -f "$C1/audit/managed-content-manifest.json"
c1_fail=""
[ -f "$C1/hooks/local/verify-managed-content-manifest.sh" ] \
  || c1_fail="$c1_fail [PRECONDITION: the wrapper that anchors the layer is not installed]"
C1_REPORT="$(python3 "$ROOT/hooks/local/lib/hook_manifest.py" verify --root "$C1" --json 2>/dev/null || true)"
case "$C1_REPORT" in
  *'"hooks/handlers/session_start.py"'*) ;;
  *) c1_fail="$c1_fail [PRECONDITION: the hook layer does not report the path, so the repair could not be authorized]" ;;
esac
C1_LOG="$M13_ROOT/anchor.log"
C1_RC="$(m13_repair "$C1" "$C1_LOG" hooks/handlers/session_start.py)"
[ "$C1_RC" -ne 0 ] \
  || c1_fail="$c1_fail [deleting the managed manifest bought a skip: the hop exited 0 with workflows/wf.md still drifted]"
grep -q "REPAIR UNVERIFIED" "$C1_LOG" || c1_fail="$c1_fail [no REPAIR UNVERIFIED diagnostic]"
grep -q "authoriz" "$C1_LOG" || c1_fail="$c1_fail [the diagnostic does not say the layer was bound at authorization]"
has_cr "$C1/workflows/wf.md" \
  || c1_fail="$c1_fail [PRECONDITION: the unrelated managed-only drift is not in the tree, so a skip would hide nothing]"
grep -q "handler v1" "$C1/hooks/handlers/session_start.py" \
  || c1_fail="$c1_fail [the named path was not repaired — this case must fail for the VERDICT, not for a broken repair]"
if [ -z "$c1_fail" ]; then
  ok "m16-a-source-declared-layer-whose-consumer-manifest-is-absent-fails [COVERAGE — already FAILed at 2d88844 via the wrapper anchor; the reason is now the source's coverage list]"
else
  bad "m16-a-source-declared-layer-whose-consumer-manifest-is-absent-fails" "rc=$C1_RC$c1_fail :: $(tail -6 "$C1_LOG" | tr '\n' '|')"
fi

# 3h-4. The mirror image, and an honest label: COVERAGE REPAIR, not a discriminator. Both verify
# wrappers are themselves covered by both manifests, so a wrapper that disappears mid-run already
# failed the re-check as `missing` drift. What is new is WHY it fails — the bound-set check fires
# before the verifier runs and names the shrink — so only the diagnostic is red at baseline.
D1="$(m13_dual_case "$M13_ROOT/wrapper-vanish")"
printf 'handler TAMPERED\n' > "$D1/hooks/handlers/session_start.py"
m13_double "$D1/.fusebase-flow-source" unlink-wrapper
D1_LOG="$M13_ROOT/wrapper-vanish.log"
D1_RC="$(m13_repair "$D1" "$D1_LOG" hooks/handlers/session_start.py)"
d1_fail=""
[ -f "$D1/hooks/local/verify-managed-content-manifest.sh" ] \
  && d1_fail="$d1_fail [PRECONDITION: the wrapper did not disappear, so nothing was exercised]"
[ "$D1_RC" -ne 0 ] || d1_fail="$d1_fail [a bound wrapper vanished mid-run and the hop confirmed the repair]"
grep -q "the bound layer set cannot shrink" "$D1_LOG" \
  || d1_fail="$d1_fail [the failure is not attributed to the bound set shrinking]"
if [ -z "$d1_fail" ]; then
  ok "m13-a-wrapper-that-disappears-after-authorization-fails-as-a-shrunk-bound-set [COVERAGE REPAIR — the FAIL already held via manifest coverage; only the attribution is new]"
else
  bad "m13-a-wrapper-that-disappears-after-authorization-fails-as-a-shrunk-bound-set" "rc=$D1_RC$d1_fail :: $(tail -6 "$D1_LOG" | tr '\n' '|')"
fi

# 3h-5. CONTROL: two layers present, one genuine drift, a genuine repair — still confirmed. Every
# case above fails closed, so without this the whole contract could be satisfied by refusing
# everything. Must be green at BOTH baselines.
E1="$(m13_dual_case "$M13_ROOT/control")"
printf 'handler TAMPERED\n' > "$E1/hooks/handlers/session_start.py"
E1_LOG="$M13_ROOT/control.log"
E1_RC="$(m13_repair "$E1" "$E1_LOG" hooks/handlers/session_start.py)"
e1_fail=""
[ "$E1_RC" -eq 0 ] || e1_fail="$e1_fail [a clean two-layer repair was not confirmed (rc $E1_RC)]"
grep -q "handler v1" "$E1/hooks/handlers/session_start.py" || e1_fail="$e1_fail [the drifted path was not repaired]"
python3 "$ROOT/hooks/local/lib/hook_manifest.py" verify --root "$E1" >/dev/null 2>&1 \
  || e1_fail="$e1_fail [the hook layer does not verify MATCH after the repair]"
python3 "$MCM" verify --root "$E1" >/dev/null 2>&1 \
  || e1_fail="$e1_fail [the managed layer does not verify MATCH after the repair]"
if [ -z "$e1_fail" ]; then
  ok "m13-a-clean-repair-with-both-layers-present-is-still-confirmed"
else
  bad "m13-a-clean-repair-with-both-layers-present-is-still-confirmed" "$e1_fail :: $(tail -8 "$E1_LOG" | tr '\n' '|')"
fi

# 3h-6. M16 HEADLINE DISCRIMINATOR — the pre-authorization downgrade that refuted M14. Nothing
# races: BOTH managed-layer artifacts are removed BEFORE the run, and the consumer's hook manifest
# is re-stamped so their absence is not hook-layer drift either — i.e. a tree that presents itself
# as "this install simply does not carry the managed layer". Under M14 that read as not-carried,
# the layer never joined the bound set, the hook layer returned MATCH after its repair, and the hop
# exited 0 while workflows/wf.md — managed-only drift — sat in the tree unverified and unreported.
# Under M16 membership is read from the VERIFIED SOURCE, which ships audit/managed-content-manifest.json
# at this version, so the layer is bound no matter what the consumer presents and its absent
# manifest is a failure.
F1="$(m13_dual_case "$M13_ROOT/dual-removal")"
rm -f "$F1/audit/managed-content-manifest.json" "$F1/hooks/local/verify-managed-content-manifest.sh"
( cd "$F1" && python3 hooks/local/lib/hook_manifest.py stamp --root . >/dev/null )
printf 'handler TAMPERED\n' > "$F1/hooks/handlers/session_start.py"
printf 'wf v1\r\n'          > "$F1/workflows/wf.md"
f1_fail=""
[ -f "$F1/.fusebase-flow-source/audit/managed-content-manifest.json" ] \
  || f1_fail="$f1_fail [PRECONDITION: the source does not declare the managed layer, so M16 binds nothing]"
[ -f "$F1/.fusebase-flow-source/hooks/local/verify-managed-content-manifest.sh" ] \
  || f1_fail="$f1_fail [PRECONDITION: the source ships no managed-layer wrapper]"
[ -e "$F1/audit/managed-content-manifest.json" ] \
  && f1_fail="$f1_fail [PRECONDITION: the consumer manifest was not removed]"
[ -e "$F1/hooks/local/verify-managed-content-manifest.sh" ] \
  && f1_fail="$f1_fail [PRECONDITION: the consumer wrapper was not removed]"
F1_REPORT="$(python3 "$ROOT/hooks/local/lib/hook_manifest.py" verify --root "$F1" --json 2>/dev/null || true)"
case "$F1_REPORT" in
  *'"hooks/handlers/session_start.py"'*) ;;
  *) f1_fail="$f1_fail [PRECONDITION: the hook layer does not report the path, so the repair could not be authorized]" ;;
esac
case "$F1_REPORT" in
  *'verify-managed-content-manifest.sh'*)
    f1_fail="$f1_fail [PRECONDITION: the removed wrapper is still hook-layer drift, so this case would go red without M16]" ;;
esac
F1_LOG="$M13_ROOT/dual-removal.log"
F1_RC="$(m13_repair "$F1" "$F1_LOG" hooks/handlers/session_start.py)"
[ "$F1_RC" -ne 0 ] \
  || f1_fail="$f1_fail [DOWNGRADE: removing BOTH managed-layer artifacts before authorization bought a skip — the hop exited 0 with workflows/wf.md still drifted and unverified]"
grep -q "REPAIR UNVERIFIED" "$F1_LOG" || f1_fail="$f1_fail [no REPAIR UNVERIFIED diagnostic]"
grep -q "declare" "$F1_LOG" \
  || f1_fail="$f1_fail [the failure is not attributed to the layer the VERIFIED SOURCE declares]"
has_cr "$F1/workflows/wf.md" \
  || f1_fail="$f1_fail [PRECONDITION: the managed-only drift is not in the tree, so the downgrade would hide nothing]"
grep -q "handler v1" "$F1/hooks/handlers/session_start.py" \
  || f1_fail="$f1_fail [the named path was not repaired — this case must fail for the VERDICT, not for a broken repair]"
if [ -z "$f1_fail" ]; then
  ok "m16-removing-both-artifacts-before-authorization-cannot-drop-a-source-declared-layer"
else
  bad "m16-removing-both-artifacts-before-authorization-cannot-drop-a-source-declared-layer" "rc=$F1_RC$f1_fail :: $(tail -6 "$F1_LOG" | tr '\n' '|')"
fi

# 3h-7. The wrapper half of the same rule, also pre-authorization. The consumer keeps a manifest
# that verifies MATCH — it is re-stamped after the wrapper is deleted, so the wrapper's absence is
# invisible to BOTH layers — and the verified source ships that wrapper. Under M14 the layer was
# bound with had_w=0 and the wrapper check was skipped, so the hop confirmed a repair on a tree
# whose own verification tool had been removed. Under M16 the source's coverage decides.
G1="$(m13_dual_case "$M13_ROOT/wrapper-missing")"
rm -f "$G1/hooks/local/verify-managed-content-manifest.sh"
( cd "$G1" && python3 hooks/local/lib/hook_manifest.py stamp --root . >/dev/null )
( cd "$G1" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
printf 'handler TAMPERED\n' > "$G1/hooks/handlers/session_start.py"
g1_fail=""
[ -f "$G1/.fusebase-flow-source/hooks/local/verify-managed-content-manifest.sh" ] \
  || g1_fail="$g1_fail [PRECONDITION: the source ships no managed-layer wrapper, so nothing requires one]"
[ -f "$G1/audit/managed-content-manifest.json" ] \
  || g1_fail="$g1_fail [PRECONDITION: the consumer manifest is gone too — that is 3h-6, not this case]"
[ -e "$G1/hooks/local/verify-managed-content-manifest.sh" ] \
  && g1_fail="$g1_fail [PRECONDITION: the consumer wrapper was not removed]"
G1_LOG="$M13_ROOT/wrapper-missing.log"
G1_RC="$(m13_repair "$G1" "$G1_LOG" hooks/handlers/session_start.py)"
[ "$G1_RC" -ne 0 ] \
  || g1_fail="$g1_fail [a layer whose wrapper the source ships was confirmed with that wrapper missing from the consumer]"
grep -q "REPAIR UNVERIFIED" "$G1_LOG" || g1_fail="$g1_fail [no REPAIR UNVERIFIED diagnostic]"
grep -q "verify-managed-content-manifest.sh" "$G1_LOG" \
  || g1_fail="$g1_fail [the missing wrapper is not named]"
if [ -z "$g1_fail" ]; then
  ok "m16-a-wrapper-the-source-ships-is-required-even-when-the-consumer-manifest-verifies"
else
  bad "m16-a-wrapper-the-source-ships-is-required-even-when-the-consumer-manifest-verifies" "rc=$G1_RC$g1_fail :: $(tail -6 "$G1_LOG" | tr '\n' '|')"
fi
# 3h-8. Layer-artifact SYMLINK SUBSTITUTION. R2 refuses symlinked repair TARGETS; the post-repair
# layer checks were plain `[ -f ]`, and both hashers open THROUGH a link — so a consumer manifest
# or wrapper linked to byte-identical content OUTSIDE the tree satisfied presence AND hash, and the
# hop confirmed "this tree carries the layer" about a file the tree does not own. Leaf and parent
# are both required: linking the audit/ DIRECTORY moves both manifests out with one call.
H_OUT="$(mktemp -d)"
h1_fail=""; h1_ran=0; h1_expected=3
for kind in manifest wrapper parent; do
  H="$(m13_dual_case "$M13_ROOT/sym-$kind")"
  case "$kind" in
    manifest) HLNK="audit/managed-content-manifest.json" ;;
    wrapper)  HLNK="hooks/local/verify-managed-content-manifest.sh" ;;
    parent)   HLNK="audit" ;;
  esac
  mkdir -p "$H_OUT/$kind/$(dirname "$HLNK")"
  mv "$H/$HLNK" "$H_OUT/$kind/$HLNK"
  r2_mk_symlink "$H/$HLNK" "$H_OUT/$kind/$HLNK" || { rm -rf "$H"; continue; }
  h1_ran=$((h1_ran + 1))
  # PRECONDITION: with the link in place BOTH layers still verify MATCH — that invisibility IS the
  # defect. Without it the case would go red for ordinary drift instead of for the substitution.
  python3 "$MCM" verify --root "$H" >/dev/null 2>&1 \
    || h1_fail="$h1_fail [$kind: PRECONDITION — the managed layer does not verify through the link]"
  python3 "$ROOT/hooks/local/lib/hook_manifest.py" verify --root "$H" >/dev/null 2>&1 \
    || h1_fail="$h1_fail [$kind: PRECONDITION — the hook layer does not verify through the link]"
  printf 'handler TAMPERED\n' > "$H/hooks/handlers/session_start.py"
  H_LOG="$M13_ROOT/sym-$kind.log"
  H_RC="$(m13_repair "$H" "$H_LOG" hooks/handlers/session_start.py)"
  [ "$H_RC" -ne 0 ] \
    || h1_fail="$h1_fail [$kind: a layer artifact SUBSTITUTED BY A SYMLINK confirmed the repair (rc 0) — the tree does not own $HLNK]"
  grep -q "REPAIR UNVERIFIED" "$H_LOG" || h1_fail="$h1_fail [$kind: no REPAIR UNVERIFIED diagnostic]"
  grep -q "symlink" "$H_LOG" \
    || h1_fail="$h1_fail [$kind: refused for the WRONG reason — no 'symlink' in the diagnostic :: $(tail -4 "$H_LOG" | tr '\n' '|')]"
  [ -L "$H/$HLNK" ] || h1_fail="$h1_fail [$kind: the symlink itself was replaced]"
  grep -q "handler v1" "$H/hooks/handlers/session_start.py" \
    || h1_fail="$h1_fail [$kind: the named path was not repaired — this case must fail for the VERDICT, not for a broken repair]"
  rm -rf "$H"
done
[ "$h1_ran" -eq 0 ] || [ "$h1_ran" -eq "$h1_expected" ] \
  || h1_fail="$h1_fail [PARTIAL COVERAGE: only $h1_ran/$h1_expected symlink classes were built]"
if [ "$h1_ran" -eq 0 ]; then
  skip "m16-a-symlink-cannot-stand-in-for-a-bound-layer-artifact" "this platform's ln -s copies instead of linking (MSYS winsymlinks off) — the fixture cannot be built, so the control is NOT claimed as proof (its proof home is the Linux/CI run)"
elif [ -z "$h1_fail" ]; then
  ok "m16-a-symlink-cannot-stand-in-for-a-bound-layer-artifact ($h1_ran/$h1_expected classes: manifest leaf, wrapper leaf, audit/ parent)"
else
  bad "m16-a-symlink-cannot-stand-in-for-a-bound-layer-artifact" "$h1_fail"
fi
rm -rf "$H_OUT"

# 3h-9. The remediation must be a command that RUNS. The manifest branch told the operator to name
# the missing artifact in --repair-managed — which repair REFUSES: it authorizes only paths a
# verifier REPORTED, an absent audit/managed-content-manifest.json makes its own verifier return
# ABSENT with an empty file list, and no other layer covers audit/. The WRAPPER half does work
# (hooks/local/*.sh is hook-layer content), so the advice has to be DERIVED from the live report,
# not assumed. Each case EXECUTES the emitted RECOVER line and requires the artifact back.
j_fail=""
for kind in manifest wrapper; do
  J="$(m13_dual_case "$M13_ROOT/recover-$kind")"
  case "$kind" in
    manifest) JART="audit/managed-content-manifest.json" ;;
    wrapper)  JART="hooks/local/verify-managed-content-manifest.sh" ;;
  esac
  rm -f "$J/$JART"
  printf 'handler TAMPERED\n' > "$J/hooks/handlers/session_start.py"
  J_LOG="$M13_ROOT/recover-$kind.log"
  J_RC="$(m13_repair "$J" "$J_LOG" hooks/handlers/session_start.py)"
  [ "$J_RC" -ne 0 ] || j_fail="$j_fail [$kind: PRECONDITION — the missing artifact did not fail the repair, so there is no remediation to check]"
  grep -q "REPAIR UNVERIFIED" "$J_LOG" || j_fail="$j_fail [$kind: no REPAIR UNVERIFIED diagnostic]"
  JCMD="$(sed -n 's/^.*RECOVER: //p' "$J_LOG" | head -1)"
  if [ -z "$JCMD" ]; then
    j_fail="$j_fail [$kind: the diagnostic emits no runnable RECOVER command :: $(tail -5 "$J_LOG" | tr '\n' '|')]"
  else
    # `y` is the confirmation a human would type at the content-upgrade prompt; nothing else is fed.
    ( cd "$J" && eval "timeout 600 $JCMD" <<< "y" ) > "$M13_ROOT/recover-$kind-run.log" 2>&1
    j_rc=$?
    [ "$j_rc" -eq 0 ] \
      || j_fail="$j_fail [$kind: the emitted remediation does NOT run (rc $j_rc): $JCMD :: $(tail -4 "$M13_ROOT/recover-$kind-run.log" | tr '\n' '|')]"
    [ -f "$J/$JART" ] || j_fail="$j_fail [$kind: the emitted remediation ran but did not restore $JART]"
  fi
  rm -rf "$J"
done
# GROUND TRUTH (holds at BOTH baselines — it pins WHY the old advice was impossible, not the fix):
# naming the managed manifest in --repair-managed is refused as unreported.
K9="$(m13_dual_case "$M13_ROOT/unreportable")"
rm -f "$K9/audit/managed-content-manifest.json"
K9_LOG="$M13_ROOT/unreportable.log"
K9_RC="$(m13_repair "$K9" "$K9_LOG" audit/managed-content-manifest.json)"
[ "$K9_RC" -ne 0 ] || j_fail="$j_fail [ground truth broke: --repair-managed accepted the absent managed manifest]"
grep -q "not reported as drifted" "$K9_LOG" \
  || j_fail="$j_fail [ground truth broke: the absent managed manifest was refused for another reason :: $(tail -4 "$K9_LOG" | tr '\n' '|')]"
if [ -z "$j_fail" ]; then
  ok "m16-the-missing-artifact-diagnostic-emits-a-remediation-that-actually-runs (manifest + wrapper; RECOVER line executed, artifact restored)"
else
  bad "m16-the-missing-artifact-diagnostic-emits-a-remediation-that-actually-runs" "$j_fail"
fi

# 3h-9b. The emitted remediation must survive a SOURCE PATH CONTAINING A SPACE. That value is
# operator-supplied (--source): interpolated unquoted it word-splits into a truncated --source plus
# a stray argument. Not exotic — this repo's own directory name carries two spaces. Asserted on the
# PARSED argv as well as on the run, so an eval cannot mask it behind another command's status.
JS="$M13_ROOT/staged source"; mkdir -p "$JS"
JQ="$(m13_dual_case "$M13_ROOT/spaced")"
mv "$JQ/.fusebase-flow-source" "$JS/flow source"
rm -f "$JQ/audit/managed-content-manifest.json"
printf 'handler TAMPERED\n' > "$JQ/hooks/handlers/session_start.py"
jq_fail=""; JQ_LOG="$M13_ROOT/spaced.log"
( cd "$JQ" && timeout 600 bash hooks/local/bootstrap-upgrade.sh --source "$JS/flow source" \
    --repair-managed hooks/handlers/session_start.py ) > "$JQ_LOG" 2>&1
JQ_RC=$?
[ "$JQ_RC" -ne 0 ] || jq_fail="$jq_fail [PRECONDITION: the missing manifest did not fail the repair, so no remediation was emitted]"
JQCMD="$(sed -n 's/^.*RECOVER: //p' "$JQ_LOG" | head -1)"
if [ -z "$JQCMD" ]; then
  jq_fail="$jq_fail [no RECOVER line :: $(tail -4 "$JQ_LOG" | tr '\n' '|')]"
else
  JQSRC=""; if eval "set -- $JQCMD" 2>/dev/null; then
    while [ "$#" -gt 0 ]; do [ "$1" = "--source" ] && { JQSRC="${2:-}"; break; }; shift; done
  else
    jq_fail="$jq_fail [the emitted RECOVER line does not parse as a shell command: $JQCMD]"
  fi
  [ "$JQSRC" = "$JS/flow source" ] \
    || jq_fail="$jq_fail [the emitted --source argument is '$JQSRC', not '$JS/flow source' — the operator's path was interpolated UNQUOTED]"
  ( cd "$JQ" && eval "timeout 600 $JQCMD" <<< "y" ) > "$M13_ROOT/spaced-run.log" 2>&1; jq_rc=$?
  [ "$jq_rc" -eq 0 ] \
    || jq_fail="$jq_fail [the emitted remediation does not run (rc $jq_rc): $JQCMD :: $(tail -3 "$M13_ROOT/spaced-run.log" | tr '\n' '|')]"
  [ -f "$JQ/audit/managed-content-manifest.json" ] \
    || jq_fail="$jq_fail [the remediation ran but did not restore the manifest]"
fi
if [ -z "$jq_fail" ]; then
  ok "m16-the-remediation-survives-a-source-path-containing-a-space"
else
  bad "m16-the-remediation-survives-a-source-path-containing-a-space" "$jq_fail"
fi
rm -rf "$JQ" "$JS"

# 3h-10. COVERAGE, not a discriminator — this behaviour already held; the CLAIM is what was wrong.
# "Bound before any repository write" is not literally true: a repair invoked with NO staging
# directory materializes one into .fusebase-flow-source/ first, and that is a write. The narrowed
# contract M13/M16 and the release note now state is what this pins — the only write that can
# precede the bind CREATES the staging directory and touches no pre-existing file.
if ! command -v sha256sum >/dev/null 2>&1; then
  skip "m13-the-only-write-before-the-bind-creates-the-staging-directory" "no sha256sum on this platform — the byte-snapshot cannot be built"
else
  L1="$(m13_dual_case "$M13_ROOT/no-staging")"
  L1_SRC="$M13_ROOT/gitsrc"
  mv "$L1/.fusebase-flow-source" "$L1_SRC"
  bnd_git_source "$L1_SRC"
  printf 'handler TAMPERED\n' > "$L1/hooks/handlers/session_start.py"
  l1_snap() {   # <root> <out> — hash + path for every file outside .git/ and the staging clone
    ( cd "$1" && find . -type f -not -path './.git/*' -not -path './.fusebase-flow-source/*' \
        -print0 | sort -z | xargs -0 sha256sum ) > "$2" 2>/dev/null
  }
  l1_fail=""
  [ -e "$L1/.fusebase-flow-source" ] \
    && l1_fail="$l1_fail [PRECONDITION: the staging directory is still present, so nothing forces the pre-bind clone]"
  l1_snap "$L1" "$M13_ROOT/l1-before.txt"
  L1_LOG="$M13_ROOT/no-staging.log"
  ( cd "$L1" && timeout 600 bash hooks/local/bootstrap-upgrade.sh --repo "$L1_SRC" --ref main \
      --repair-managed hooks/handlers/session_start.py ) > "$L1_LOG" 2>&1
  L1_RC=$?
  l1_snap "$L1" "$M13_ROOT/l1-after.txt"
  [ "$L1_RC" -eq 0 ] \
    || l1_fail="$l1_fail [a repair that had to clone its staging source was not confirmed (rc $L1_RC)]"
  [ -d "$L1/.fusebase-flow-source" ] \
    || l1_fail="$l1_fail [PRECONDITION: no staging clone was made, so this case did not exercise the pre-bind write]"
  grep -q "repair layer REQUIRED" "$L1_LOG" || l1_fail="$l1_fail [the layer set was never bound]"
  # Everything the run touched, minus the named path and its backup twin, must be EMPTY.
  L1_DIFF="$(diff "$M13_ROOT/l1-before.txt" "$M13_ROOT/l1-after.txt" | grep '^[<>]' \
    | grep -v 'session_start\.py' | grep -v '\.pre-upgrade-' || true)"
  [ -z "$L1_DIFF" ] \
    || l1_fail="$l1_fail [a pre-existing file OTHER than the named path changed: $(printf '%s' "$L1_DIFF" | tr '\n' '|')]"
  if [ -z "$l1_fail" ]; then
    ok "m13-the-only-write-before-the-bind-creates-the-staging-directory [COVERAGE — the behaviour already held at c77b139; the CONTRACT WORDING was the defect]"
  else
    bad "m13-the-only-write-before-the-bind-creates-the-staging-directory" "$l1_fail :: $(tail -5 "$L1_LOG" | tr '\n' '|')"
  fi
fi

rm -rf "$M13_ROOT"

finish
