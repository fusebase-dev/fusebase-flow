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


finish
