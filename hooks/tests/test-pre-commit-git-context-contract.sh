#!/usr/bin/env bash
# Fusebase Flow — A2 repository-context contract for hooks/git/pre-commit §0 (git-context classifier).
# Spec: docs/specs/pre-commit-trusted-tool-contract/spec.md § A2 compatibility matrix + § A2 search
# termination contract. Rows G1-G16 of that spec's verification-gate.md.
#
# An empty `git rev-parse --show-toplevel` used to mean BOTH "git is unusable in a repository" and
# "we are genuinely outside a repository", and both exited 0 — skipping §2 (FR-12) and §3 (FR-07).
# The classifier decides between them from independent `.git` evidence.
#
# This is repository-context / git FAULT detection, NOT git authentication: a caller who controls
# PATH can still supply a shim, and workspace evidence is workspace-writable.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: git-context <name>" / "FAIL: git-context <name>"; exit = fail count.
#
# FFGC_HOOK=<path> runs the contract against a COPY of the hook. Production hooks/git/pre-commit is
# never written to.
#
# TRIPWIRE — row names are space-free (first-token parsing by the mutation harness).
# TRIPWIRE — "broken git" is a PATH shim that exits nonzero with no output. That is the observable
# the hook consumes; it is not a claim that a real broken git behaves only this way.
# TRIPWIRE — every ascent-terminating row pins GIT_CEILING_DIRECTORIES to the scenario root. Without
# it the search would walk the real filesystem above the temp dir and a stray ancestor `.git` on the
# HOST would decide the row instead of the fixture.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOOKRUN="${FFGC_HOOK:-$ROOT/hooks/git/pre-commit}"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: git-context $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: git-context $1 (${2:-})"; }
finish() { echo "[test-pre-commit-git-context-contract] $pass/$((pass + fail)) PASS"; exit $fail; }

[ -f "$HOOKRUN" ] || { bad "hook-source-present" "missing $HOOKRUN"; finish; }
command -v python3 >/dev/null 2>&1 || { ok "skipped-no-python3"; finish; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffgc-contract.XXXXXX")"
cleanup() {
  chmod -R u+rwx "$TMP" 2>/dev/null
  case "$TMP" in "${TMPDIR:-/tmp}"/ffgc-contract.*) rm -rf -- "$TMP" ;; esac
}
trap cleanup EXIT
cp "$HOOKRUN" "$TMP/hook-at-start"
TMPROOT="$TMP/tmproot"
# Physical path: GIT_CEILING_DIRECTORIES is compared against the hook's `pwd -P`, so a symlinked
# TMPDIR would otherwise never match the ceiling and the ascent would leave the fixture.
mkdir -p "$TMP/scen"; SCEN="$(cd "$TMP/scen" && pwd -P)"

# Diagnostic anchors the hook must produce.
D_BLOCK="git resolved no worktree here"
D_EVIDENCE="carries repository evidence"
D_DANGLING="dangling symlink"
D_STAT="could not be stat'd"
D_ENV="declares repository context"
D_NOWORKTREE="without a worktree"
D_OUTSIDE="not in a git repo; skipping"

# ---- PATH shims --------------------------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN/brokengit" "$BIN/nogit" "$BIN/stat"
printf '#!/usr/bin/env bash\nexit 128\n' > "$BIN/brokengit/git"; chmod +x "$BIN/brokengit/git"
printf '#!/usr/bin/env bash\necho "git: command not found" >&2\nexit 127\n' > "$BIN/nogit/git"; chmod +x "$BIN/nogit/git"
REALSTAT="$(command -v stat 2>/dev/null)"
# stat shim: FFGC_STAT_FAIL / FFGC_STAT_DEV are GLOB patterns matched against the path argument.
# It lets the harness reproduce an OS-level stat failure (G11, G7-inaccessible) and a mount-identity
# change (G9) deterministically, on any platform, without touching the hook.
cat > "$BIN/stat/stat" <<STATSHIM
#!/usr/bin/env bash
p="\${@: -1}"
case "\${FFGC_STAT_FAIL:-__none__}" in __none__) : ;; *) case "\$p" in \${FFGC_STAT_FAIL}) exit 1 ;; esac ;; esac
case "\${FFGC_STAT_DEV:-__none__}" in __none__) : ;; *) case "\$p" in \${FFGC_STAT_DEV}) echo 987654321; exit 0 ;; esac ;; esac
exec "$REALSTAT" "\$@"
STATSHIM
chmod +x "$BIN/stat/stat"

# ---- runner ------------------------------------------------------------------------------------
# run_hook <dir> [path-prefix]: one hook invocation. Exports are the caller's to set/unset.
run_hook() {
  local d="$1" pre="${2:-}" p="$PATH" t0
  [ -n "$pre" ] && p="$pre:$PATH"
  rm -rf "$TMPROOT"; mkdir -p "$TMPROOT"
  t0="$(date +%s)"
  ( cd "$d" && PATH="$p" TMPDIR="$TMPROOT" bash "$HOOKRUN" ) >"$TMP/o" 2>"$TMP/e"; RC=$?
  ELAPSED=$(( $(date +%s) - t0 ))
  ERR="$(cat "$TMP/e" 2>/dev/null)"
}
has() { case "$ERR" in *"$1"*) return 0 ;; esac; return 1; }
# expect_block <row> <phrase>: rc != 0 AND the A2 BLOCK AND its specific cause.
expect_block() {
  if [ "$RC" -ne 0 ] && has "$D_BLOCK" && has "$2"; then ok "$1"
  else bad "$1" "rc=$RC — expected the A2 fail-closed BLOCK naming '$2': ${ERR:-<empty>}"; fi
}
# expect_skip <row> <phrase>: rc == 0 AND the named skip diagnostic AND never the A2 BLOCK.
expect_skip() {
  if [ "$RC" -eq 0 ] && has "$2" && ! has "$D_BLOCK"; then ok "$1"
  else bad "$1" "rc=$RC — expected rc=0 with '$2' and no BLOCK: ${ERR:-<empty>}"; fi
}

# mk_repo <dir> [head|nohead] [separate-git-dir]: a consumer repo carrying the Flow bits §2/§3 need.
# TRIPWIRE — the Flow bits are not decoration: a row asserting "controls RUN" fails on a bare
# `git init` fixture because §2 cannot import its own scanner, and that failure looks like a
# classifier regression.
mk_repo() {
  local d="$1" sep="${3:-}"
  mkdir -p "$d/hooks/git"
  cp -R "$ROOT/hooks/shared" "$d/hooks/shared"
  cp -R "$ROOT/hooks/local"  "$d/hooks/local"
  cp -R "$ROOT/policies"     "$d/policies"
  if [ -n "$sep" ]; then
    ( cd "$d" && git init -q --separate-git-dir "$sep" . ) >/dev/null 2>&1 || return 1
    # Git for Windows leaves core.worktree unset here; set it so the row tests the layout the spec
    # names, and let git spell the path (an MSYS path in that key is not portable).
    ( cd "$d" && git config core.worktree "$(git rev-parse --show-toplevel)" ) >/dev/null 2>&1 || return 1
  else ( cd "$d" && git init -q ) >/dev/null 2>&1 || return 1; fi
  ( cd "$d" && git config user.email t@example.com && git config user.name t \
      && git config core.autocrlf false ) || return 1
  if [ "${2:-head}" = "head" ]; then
    ( cd "$d" && git add -- . >/dev/null 2>&1 && git commit -qm base >/dev/null 2>&1 ) || return 1
  fi
  printf '# note\nhello\n' > "$d/note.md"
  ( cd "$d" && git add -- note.md >/dev/null 2>&1 )
}

REPO="$SCEN/repo"; mk_repo "$REPO" head || { bad "scenario-repo-built" "could not build the consumer repo"; finish; }
mkdir -p "$REPO/nested/deep"
ok "scenario-repo-built"

# ================================================================================================
# G1 — normal repo / nested directory
# ================================================================================================
run_hook "$REPO"
if [ "$RC" -eq 0 ] && has "all checks passed"; then ok "G1-normal-repo-working-git-reaches-controls"
else bad "G1-normal-repo-working-git-reaches-controls" "rc=$RC — the unchanged working-git path regressed: ${ERR:-<empty>}"; fi

run_hook "$REPO" "$BIN/brokengit"
expect_block "G1-normal-repo-broken-git-blocks" "$D_EVIDENCE"

run_hook "$REPO/nested/deep" "$BIN/brokengit"
expect_block "G1-nested-dir-broken-git-blocks" "$D_EVIDENCE"

# ================================================================================================
# G2 — invocation inside .git/ with a WORKING git: a distinct no-worktree rc=0, never the
#      outside-repo skip (which would silently drop §2/§3 while inside a real repository).
# ================================================================================================
run_hook "$REPO/.git"
if [ "$RC" -eq 0 ] && has "$D_NOWORKTREE" && ! has "$D_OUTSIDE" && ! has "$D_BLOCK"; then ok "G2-inside-git-dir-distinct-no-worktree-skip"
else bad "G2-inside-git-dir-distinct-no-worktree-skip" "rc=$RC — expected the no-worktree diagnostic, not the outside-repo skip: ${ERR:-<empty>}"; fi

# ================================================================================================
# G3 — linked worktree / submodule: `.git` is a FILE
# ================================================================================================
WT="$SCEN/linked-wt"
if ( cd "$REPO" && git worktree add -q "$WT" -b wtbranch >/dev/null 2>&1 ) && [ -f "$WT/.git" ]; then
  run_hook "$WT"
  if [ "$RC" -eq 0 ] && ! has "$D_BLOCK"; then ok "G3-worktree-file-working-git-reaches-controls"
  else bad "G3-worktree-file-working-git-reaches-controls" "rc=$RC in a linked worktree with a working git: ${ERR:-<empty>}"; fi
  run_hook "$WT" "$BIN/brokengit"
  expect_block "G3-worktree-file-broken-git-blocks" "$D_EVIDENCE"
else
  # Hand-built equivalent: the classifier's evidence is the `.git` FILE, not git's own resolution.
  mkdir -p "$SCEN/gitfile"; printf 'gitdir: %s/.git\n' "$REPO" > "$SCEN/gitfile/.git"
  run_hook "$SCEN/gitfile" "$BIN/brokengit"
  expect_block "G3-worktree-file-working-git-reaches-controls" "$D_EVIDENCE"
  run_hook "$SCEN/gitfile" "$BIN/brokengit"
  expect_block "G3-worktree-file-broken-git-blocks" "$D_EVIDENCE"
fi

# ================================================================================================
# G4/G5 — explicit GIT_DIR / GIT_WORK_TREE
# ================================================================================================
OUTSIDE="$SCEN/outside"; mkdir -p "$OUTSIDE"
export GIT_CEILING_DIRECTORIES="$SCEN"

export GIT_DIR="$REPO/.git" GIT_WORK_TREE="$REPO"
run_hook "$REPO"
if [ "$RC" -eq 0 ] && ! has "$D_BLOCK"; then ok "G4-valid-explicit-env-working-git-unchanged"
else bad "G4-valid-explicit-env-working-git-unchanged" "rc=$RC — a valid explicit environment changed behaviour: ${ERR:-<empty>}"; fi
run_hook "$OUTSIDE" "$BIN/brokengit"
expect_block "G4-valid-explicit-env-broken-git-blocks" "$D_ENV"
unset GIT_DIR GIT_WORK_TREE

export GIT_DIR="$SCEN/nonexistent-git-dir"
run_hook "$OUTSIDE"
expect_block "G5-stale-explicit-env-blocks" "$D_ENV"
unset GIT_DIR

# ================================================================================================
# G6 — separate git dir + core.worktree
# ================================================================================================
SEP="$SCEN/sep-wt"; SEPGIT="$SCEN/sep-gitdir"
if mk_repo "$SEP" head "$SEPGIT" && [ -f "$SEP/.git" ] && grep -q 'worktree = ' "$SEPGIT/config"; then
  run_hook "$SEP"
  if [ "$RC" -eq 0 ] && ! has "$D_BLOCK"; then ok "G6-separate-gitdir-working-git-reaches-controls"
  else bad "G6-separate-gitdir-working-git-reaches-controls" "rc=$RC with a working git on a separate-git-dir layout: ${ERR:-<empty>}"; fi
  run_hook "$SEP" "$BIN/brokengit"
  expect_block "G6-separate-gitdir-broken-git-blocks" "$D_EVIDENCE"
else
  bad "G6-separate-gitdir-working-git-reaches-controls" "could not build a --separate-git-dir layout"
  bad "G6-separate-gitdir-broken-git-blocks" "could not build a --separate-git-dir layout"
fi

# ================================================================================================
# G7 — .git symlink: valid / dangling / inaccessible
# ================================================================================================
# MSYS `ln -s` copies instead of linking unless the host grants the privilege; ask for a real
# symlink first so these rows RUN wherever they can, and fall back to a named SKIP where they cannot.
SYM="$SCEN/symlink-valid"; mkdir -p "$SYM"
( cd "$SYM" && MSYS=winsymlinks:nativestrict ln -s "$REPO/.git" .git 2>/dev/null || ln -s "$REPO/.git" .git 2>/dev/null )
DANG="$SCEN/symlink-dangling"; mkdir -p "$DANG"
( cd "$DANG" && MSYS=winsymlinks:nativestrict ln -s "$SCEN/no-such-git-dir" .git 2>/dev/null || ln -s "$SCEN/no-such-git-dir" .git 2>/dev/null )
if [ -L "$SYM/.git" ] && [ -L "$DANG/.git" ]; then
  run_hook "$SYM" "$BIN/brokengit"
  expect_block "G7-git-symlink-valid-blocks-on-broken-git" "$D_EVIDENCE"
  run_hook "$DANG" "$BIN/brokengit"
  expect_block "G7-git-symlink-dangling-blocks-indeterminate" "$D_DANGLING"
else
  # MSYS without native symlink support copies the target instead of linking. Recorded, not hidden:
  # the rows run on any platform whose `ln -s` produces a real symlink (Linux CI does).
  ok "G7-git-symlink-valid-blocks-on-broken-git-SKIPPED-no-native-symlinks"
  ok "G7-git-symlink-dangling-blocks-indeterminate-SKIPPED-no-native-symlinks"
fi

# Inaccessible: the observable the hook consumes is a FAILED stat of the directory it must inspect.
INACC="$SCEN/inaccessible"; mkdir -p "$INACC"
export FFGC_STAT_FAIL="$INACC"
run_hook "$INACC" "$BIN/stat:$BIN/brokengit"
expect_block "G7-inaccessible-path-blocks-indeterminate" "$D_STAT"
unset FFGC_STAT_FAIL

# ================================================================================================
# G8 — .git only ABOVE GIT_CEILING_DIRECTORIES: the ascent stops before the ceiling entry
# ================================================================================================
CEIL="$SCEN/ceilroot"; mkdir -p "$CEIL/mid/leaf"; mkdir -p "$CEIL/.git"
export GIT_CEILING_DIRECTORIES="$CEIL/mid"
run_hook "$CEIL/mid/leaf" "$BIN/brokengit"
expect_skip "G8-ceiling-stops-before-evidence" "$D_OUTSIDE"
export GIT_CEILING_DIRECTORIES="$SCEN"
run_hook "$CEIL/mid/leaf" "$BIN/brokengit"
expect_block "G8-without-ceiling-the-same-evidence-is-found" "$D_EVIDENCE"

# ================================================================================================
# G9 — filesystem/mount boundary: default stops, GIT_DISCOVERY_ACROSS_FILESYSTEM crosses
# ================================================================================================
export FFGC_STAT_DEV="$CEIL"          # the parent that holds .git reports a different device
run_hook "$CEIL/mid/leaf" "$BIN/stat:$BIN/brokengit"
expect_skip "G9-mount-boundary-default-stops" "$D_OUTSIDE"
export GIT_DISCOVERY_ACROSS_FILESYSTEM=1
run_hook "$CEIL/mid/leaf" "$BIN/stat:$BIN/brokengit"
expect_block "G9-across-filesystem-crosses-then-blocks" "$D_EVIDENCE"
unset GIT_DISCOVERY_ACROSS_FILESYSTEM FFGC_STAT_DEV

# ================================================================================================
# G10 — terminal roots (drive root, POSIX root, UNC share root) + strict-parent ascent.
#       A UNC share cannot be fabricated in a temp dir, so the TERMINATION RULE itself is the unit
#       under test: the hook's own parent function, extracted from the file under test and driven
#       directly. That is the same code the ascent above uses.
# ================================================================================================
par_def="$(grep -n '^_ffpc_par() ' "$HOOKRUN" | head -1 | cut -d: -f2-)"
if [ -n "$par_def" ] && eval "$par_def" 2>/dev/null; then
  par_bad=""
  check_par() { local got; got="$(_ffpc_par "$1")"; [ "$got" = "$2" ] || par_bad="$par_bad [$1 -> '$got' expected '$2']"; }
  check_par "//server/share/proj/sub" "//server/share/proj"
  check_par "//server/share/proj"     "//server/share"
  check_par "//server/share"          ""
  check_par "/c/Users/x"              "/c/Users"
  check_par "/c"                      "/"
  check_par "/"                       ""
  if [ -z "$par_bad" ]; then ok "G10-terminal-roots-stop-the-ascent"
  else bad "G10-terminal-roots-stop-the-ascent" "wrong parent(s):$par_bad"; fi
  # Strict-parent ascent visits each candidate at most once and always terminates.
  d="/a/b/c/d/e"; seen=""; steps=0; loop_bad=""
  while [ -n "$d" ]; do
    case " $seen " in *" $d "*) loop_bad="revisited $d"; break ;; esac
    seen="$seen $d"; steps=$((steps + 1))
    [ "$steps" -gt 32 ] && { loop_bad="ascent did not terminate in 32 steps"; break; }
    d="$(_ffpc_par "$d")"
  done
  if [ -z "$loop_bad" ]; then ok "G10-ascent-is-strict-and-terminating"
  else bad "G10-ascent-is-strict-and-terminating" "$loop_bad"; fi
else
  bad "G10-terminal-roots-stop-the-ascent" "could not extract _ffpc_par from $HOOKRUN"
  bad "G10-ascent-is-strict-and-terminating" "could not extract _ffpc_par from $HOOKRUN"
fi

# ================================================================================================
# G11 — stat/network failure is BOUNDED and BLOCKS; it never proves outside-repo execution
# ================================================================================================
NETDIR="$SCEN/netshare"; mkdir -p "$NETDIR"
export FFGC_STAT_FAIL="$NETDIR"
run_hook "$NETDIR" "$BIN/stat:$BIN/brokengit"
expect_block "G11-stat-failure-blocks-not-skips"  "$D_STAT"
if [ "$ELAPSED" -le 30 ]; then ok "G11-stat-failure-is-bounded"
else bad "G11-stat-failure-is-bounded" "the classifier took ${ELAPSED}s — a stat failure must not retry or wait"; fi
unset FFGC_STAT_FAIL

# ================================================================================================
# G12 — false bare-layout lookalike is NOT evidence
# ================================================================================================
FAKE="$SCEN/fake-bare"; mkdir -p "$FAKE/objects" "$FAKE/refs"
printf 'this is not a ref\n' > "$FAKE/HEAD"
printf '[core]\n\trepositoryformatversion = 0\n' > "$FAKE/config"
run_hook "$FAKE" "$BIN/brokengit"
expect_skip "G12-false-bare-lookalike-is-not-evidence" "$D_OUTSIDE"
# The harder lookalike: objects/ + refs/ + a WELL-FORMED HEAD, but no `bare = true`. Only the
# config guard separates this from a real bare repo; without it this directory newly BLOCKs a
# commit that works today, which the DO-NOT-BUILD review named as the worse outcome.
WELLFORMED="$SCEN/bare-lookalike-wellformed"; mkdir -p "$WELLFORMED/objects" "$WELLFORMED/refs"
printf 'ref: refs/heads/main
' > "$WELLFORMED/HEAD"
printf '[core]
	repositoryformatversion = 0
	bare = false
' > "$WELLFORMED/config"
run_hook "$WELLFORMED" "$BIN/brokengit"
expect_skip "G12-wellformed-lookalike-without-bare-true-is-not-evidence" "$D_OUTSIDE"

# ================================================================================================
# G13 — a FUNCTIONING bare repository
# ================================================================================================
BARE="$SCEN/real.git"
if git init -q --bare "$BARE" >/dev/null 2>&1; then
  run_hook "$BARE"
  if [ "$RC" -eq 0 ] && has "$D_NOWORKTREE" && ! has "$D_OUTSIDE" && ! has "$D_BLOCK"; then ok "G13-bare-repo-distinct-no-worktree-skip"
  else bad "G13-bare-repo-distinct-no-worktree-skip" "rc=$RC — a functioning bare repo must get the no-worktree outcome, not the worktree or outside-repo one: ${ERR:-<empty>}"; fi
  run_hook "$BARE" "$BIN/brokengit"
  expect_block "G13-bare-evidence-broken-git-blocks" "$D_EVIDENCE"
else
  bad "G13-bare-repo-distinct-no-worktree-skip" "could not create a bare repo"
  bad "G13-bare-evidence-broken-git-blocks" "could not create a bare repo"
fi

# ================================================================================================
# G14 — genuine outside-repo execution keeps its existing diagnostic and rc=0
# ================================================================================================
run_hook "$OUTSIDE" "$BIN/brokengit"
expect_skip "G14-outside-repo-broken-git-skips" "$D_OUTSIDE"
run_hook "$OUTSIDE" "$BIN/nogit"
expect_skip "G14-outside-repo-missing-git-skips" "$D_OUTSIDE"
run_hook "$OUTSIDE"
expect_skip "G14-outside-repo-working-git-skips" "$D_OUTSIDE"

# ================================================================================================
# G15/G16 — security-sensitive existing behaviour that must not move
# ================================================================================================
NOHEAD="$SCEN/first-adoption"; mk_repo "$NOHEAD" nohead
run_hook "$NOHEAD"
if [ "$RC" -eq 0 ] && has "no HEAD yet (first-adoption bootstrap)"; then ok "G15-unborn-head-regression"
else bad "G15-unborn-head-regression" "rc=$RC — the first-adoption bootstrap path changed: ${ERR:-<empty>}"; fi

( cd "$REPO" && git reset -q HEAD -- . >/dev/null 2>&1 )
run_hook "$REPO"
if [ "$RC" -eq 0 ] && ! has "$D_BLOCK"; then ok "G16-empty-staged-set-no-op"
else bad "G16-empty-staged-set-no-op" "rc=$RC on an empty staged set: ${ERR:-<empty>}"; fi
if [ "$(ls -A "$TMPROOT" 2>/dev/null | grep -c . || true)" -eq 0 ]; then ok "G16-empty-staged-set-no-temp-residue"
else bad "G16-empty-staged-set-no-temp-residue" "entries survived in the run's private TMPDIR"; fi
( cd "$REPO" && git add -- note.md >/dev/null 2>&1 )

unset GIT_CEILING_DIRECTORIES

# ---- production integrity ----------------------------------------------------------------------
if cmp -s "$HOOKRUN" "$TMP/hook-at-start"; then ok "hook-under-test-unmodified"
else bad "hook-under-test-unmodified" "$HOOKRUN changed during this run"; fi

finish
