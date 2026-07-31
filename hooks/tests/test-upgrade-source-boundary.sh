#!/usr/bin/env bash
# Fusebase Flow — canonical source boundary + byte-model tests (T1 / AC1, AC2; decisions M1, M2,
# M10, M11). Spec: docs/specs/upgrade-source-integrity-and-observability/.
#
# Two responsibility seams around this file: test-upgrade-conflict-classification.sh owns K9
# classification, test-upgrade-repair-managed.sh owns AC3's deliberate byte repair, and this one
# owns WHICH BYTES enter the consumer — and, per the source-shape matrix below, which source
# shapes are admitted at all. Fixture builders are shared from lib/upgrade-fixtures.sh. The three
# byte models
# are not interchangeable and the whole point of these cases is that collapsing them is silent:
#   U  incoming  — forced core.autocrlf=false + core.eol=lf on EVERY OS, from git OBJECTS
#   L  local     — consumer bytes exactly as found
#   B  K13 base  — the CONSUMER's EOL convention (it models the consumer's own tree)
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: upgrade-boundary <name>" / "FAIL: upgrade-boundary <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: upgrade-boundary $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: upgrade-boundary $1 (${2:-})"; }
# A platform that cannot BUILD a fixture reports an honest visible SKIP — never a silent
# green and never a claimed proof (same shape as test-msys-tree-cleanup.sh).
skip() { pass=$((pass + 1)); echo "PASS: upgrade-boundary $1 [SKIP — $2]"; }
finish() { echo "[test-upgrade-source-boundary] $pass/$((pass + fail)) PASS"; exit $fail; }

# ---- source-shape matrix -------------------------------------------------------------------
# The bootstrap hop behaves differently along three axes, and the round that produced this file
# shipped two BLOCKERs in cells nobody had named. Every cell is therefore dispositioned here:
#   transport  plain | git
#   source     A manifest + materializer · B manifest + verifier only (the shipped v4.7.0 tag)
#              C no manifest, no materializer (genuine pre-4.7.0)
#   consumer   H+ trusted local materialize-managed-source.sh installed · H- old install
# RUN cells name the case that exercises them and must actually run; WAIVE cells carry a reason.
# The closing assertion re-derives the 12 combinations, so dropping or renaming a cell is visible.
#
# The four H+ cells were once WAIVEd on "with a trusted installed helper, shapes B and C collapse
# onto A". That is true of the VERDICT and false of the ROUTE: the helper decides which code
# materializes and judges a tree, never which tree a PRE-boundary engine then reads — and the
# verified-tree/consumed-tree split lived entirely in that second half (git/B/H+ failed exactly
# like git/B/H- before Step 2c). A waiver that reasons about one half of a route cannot cover the
# other, so every cell now RUNs.
MX_ROWS=(
  "plain/A/H+|RUN|m10-manifest-bearing-source-drift-aborts-before-writes + ac2-boundary-never-sourced-from-the-mutable-source-worktree"
  "plain/A/H-|RUN|k10-embedded-boundary-still-upgrades-a-pre-boundary-install-plain + r3-old-install-cannot-be-verified-by-the-source-own-helper"
  "plain/B/H+|RUN|m11-verifier-only-source-still-aborts-on-drift-plain-H+"
  "plain/B/H-|RUN|m11-manifest-plus-verifier-without-materializer-is-provable-plain + m11-verifier-only-source-still-aborts-on-drift-plain-H-"
  "plain/C/H+|RUN|m10-pre-boundary-source-completes-the-unverified-legacy-route-plain-H+"
  "plain/C/H-|RUN|m10-pre-boundary-source-completes-the-unverified-legacy-route-plain-H-"
  "git/A/H+|RUN|ac1-incoming-U-materialized-from-objects-forced-LF"
  "git/A/H-|RUN|k10-embedded-boundary-still-upgrades-a-pre-boundary-install-git"
  "git/B/H+|RUN|m11-verifier-only-source-still-aborts-on-drift-git-H+"
  "git/B/H-|RUN|m11-manifest-plus-verifier-without-materializer-is-provable-git + m11-verifier-only-source-still-aborts-on-drift-git-H-"
  "git/C/H+|RUN|m10-pre-boundary-source-completes-the-unverified-legacy-route-git-H+"
  "git/C/H-|RUN|m10-pre-boundary-source-completes-the-unverified-legacy-route-git-H-"
)
MX_SEEN=""
mx_ran() { MX_SEEN="$MX_SEEN
$1"; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: upgrade-boundary skipped-no-python3"; pass=1; finish; }
command -v git >/dev/null 2>&1 || { echo "PASS: upgrade-boundary skipped-no-git"; pass=1; finish; }

# shellcheck source=lib/upgrade-fixtures.sh
. "$ROOT/hooks/tests/lib/upgrade-fixtures.sh"

# ---- 1. AC1 (F2): incoming U comes from git OBJECTS, never the staging WORKTREE ------------
# THE reported defect. A persistent staging worktree populated at commit A (before an EOL pin
# landed) keeps its pre-pin bytes forever — changing .gitattributes does NOT rewrite an
# unchanged file — so an engine that copies that worktree ships CRLF where the shipped
# byte-exact manifest expects LF: permanent FLOW_LAYER_DRIFT the consumer cannot clear.
# SYNTHETIC two-commit upstream on purpose: nothing here depends on real repository history.
#
# Two measurands, one per half of M1's incoming-U rule:
#   policies/data.jsonl   pinned `text eol=lf` at commit B  -> proves objects-not-worktree
#   policies/unpinned.dat never pinned                      -> proves the FORCED autocrlf=false
# One negative control: workflows/wf.md is touched by nobody, so K13's base B must keep the
# CONSUMER's EOL and leave it un-misclassified. Forcing LF for B instead would make this
# untouched CRLF file read as a local edit — the exact collapse M1 forbids.
F2_ROOT="$(mktemp -d)"
F2_UP="$F2_ROOT/up"
mkdir -p "$F2_UP/hooks/local/lib" "$F2_UP/hooks/shared" "$F2_UP/policies" "$F2_UP/workflows"
( cd "$F2_UP" && git init -q && git config user.email t@t.t && git config user.name t \
    && git config core.autocrlf false )
# TRIPWIRE (platform, problem-catalog pitfall 5): pin *.sh even at commit A — an unpinned
# synthetic fixture checked out under core.autocrlf=true lands CRLF scripts, which MSYS bash
# tolerates and Linux bash refuses ("set: pipefail: invalid option name"). NEVER widen this
# pin to the measurands: their un-pinned/late-pinned state IS the experiment.
printf '*.sh text eol=lf\n' > "$F2_UP/.gitattributes"
echo "4.6.1" > "$F2_UP/VERSION"
printf '{"a":1}\n{"b":2}\n'          > "$F2_UP/policies/data.jsonl"
printf 'plain payload\nsecond line\n' > "$F2_UP/policies/unpinned.dat"
printf 'wf v1\n'                     > "$F2_UP/workflows/wf.md"
printf 'validator v1\n'              > "$F2_UP/hooks/shared/command_policy.py"
cp "$ROOT/hooks/local/upgrade.sh" "$ROOT/hooks/local/bootstrap-upgrade.sh" "$F2_UP/hooks/local/"
cp "$MCM" "$F2_UP/hooks/local/lib/"
copy_boundary_libs "$F2_UP/hooks/local/lib"
( cd "$F2_UP" && git add -A && git commit -qm 'v4.6.1' && git branch -M main && git tag v4.6.1 )
# commit B: the *.jsonl EOL pin lands; the blob itself is byte-identical to A.
echo "4.7.0" > "$F2_UP/VERSION"
printf '*.sh text eol=lf\n*.jsonl text eol=lf\n' > "$F2_UP/.gitattributes"
printf 'validator v2\n' > "$F2_UP/hooks/shared/command_policy.py"
( cd "$F2_UP" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
( cd "$F2_UP" && git add -A && git commit -qm 'v4.7.0' )

# The consumer installed at 4.6.1 under core.autocrlf=true -> CRLF on disk, LF scripts.
F2_C="$F2_ROOT/cons"
git -c core.autocrlf=true clone -q --branch v4.6.1 "$F2_UP" "$F2_C" 2>/dev/null
( cd "$F2_C" && git config core.autocrlf true )
# The AFFECTED staging clone: populated at A (pre-pin), then advanced to B. git leaves the
# unchanged .jsonl blob alone, so the worktree keeps CRLF while the object is LF — and
# `git status` stays CLEAN, which is why this is invisible in the field.
F2_SRC="$F2_C/.fusebase-flow-source"
git -c core.autocrlf=true clone -q --branch v4.6.1 "$F2_UP" "$F2_SRC" 2>/dev/null
( cd "$F2_SRC" && git config core.autocrlf true && git fetch -q origin main \
    && git checkout -q -B main FETCH_HEAD )

f2_fail=""
# Preconditions: without them the fixture does not model F2 and any green result is vacuous.
has_cr "$F2_SRC/policies/data.jsonl" || f2_fail="$f2_fail [PRECONDITION: staging worktree .jsonl is not CRLF — fixture does not model F2]"
has_cr "$F2_C/policies/data.jsonl"   || f2_fail="$f2_fail [PRECONDITION: consumer .jsonl is not CRLF]"
has_cr "$F2_C/workflows/wf.md"       || f2_fail="$f2_fail [PRECONDITION: consumer wf.md is not CRLF]"
F2_LOG="$F2_ROOT/log"
( cd "$F2_C" && bash hooks/local/bootstrap-upgrade.sh --ref main -- --auto-yes ) > "$F2_LOG" 2>&1
F2_RC=$?
[ "$F2_RC" -eq 0 ] || f2_fail="$f2_fail [upgrade exited $F2_RC]"
has_cr "$F2_C/policies/data.jsonl" && f2_fail="$f2_fail [PINNED .jsonl installed with CRLF — the engine copied the staging WORKTREE, not the git object (F2)]"
has_cr "$F2_C/policies/unpinned.dat" && f2_fail="$f2_fail [UNPINNED file installed with CRLF — incoming U inherited the consumer's core.autocrlf instead of forcing false (M1)]"
python3 "$MCM" verify --root "$F2_C" >/dev/null 2>&1 \
  || f2_fail="$f2_fail [managed-content manifest does NOT verify MATCH after the upgrade :: $(python3 "$MCM" verify --root "$F2_C" 2>&1 | tr '\n' '|')]"
# NEGATIVE CONTROL (K13 base B keeps the CONSUMER's EOL): a file nobody touched must never
# read as a consumer edit or a conflict.
for wrong in "consumer-only" "changed-by-both" "unknown-base"; do
  sed -n "/$wrong/,/^\$/p" "$F2_LOG" | grep -q "workflows/wf.md" \
    && f2_fail="$f2_fail [untouched CRLF wf.md classified $wrong — K13 base B was not synthesized with the CONSUMER's EOL]"
done
if [ -z "$f2_fail" ]; then
  ok "ac1-incoming-U-materialized-from-objects-forced-LF"
else
  bad "ac1-incoming-U-materialized-from-objects-forced-LF" "$f2_fail :: $(tail -12 "$F2_LOG" | tr '\n' '|')"
fi
mx_ran "git/A/H+"
rm -rf "$F2_ROOT"

# ---- 1b. AC2: the handoff is asserted on the engine's ACTUAL ARGV -------------------------
# Log text only proves the boundary logged something. A RECORDER engine in the source tree writes
# its "$@" to disk, so the internal flags, their ABSOLUTE values and the full-OID commit are read
# from the real handoff. The recorder carries the `--source-tree)` token bootstrap greps for
# before it passes the flags, and it is stamped INTO the source manifest so the source still
# verifies MATCH.
ARGV_ROOT="$(mktemp -d)"
AV="$(bnd_plain_case "$ARGV_ROOT/case")"
AV_SRC="$AV/.fusebase-flow-source"
cat > "$AV_SRC/hooks/local/upgrade.sh" <<'REC'
#!/usr/bin/env bash
# Not an engine: it records the argv the boundary handed over. The `--source-tree)` token below
# is what bootstrap-upgrade.sh greps for before passing the internal flags — do not remove it.
case "${1:-}" in --source-tree) : ;; esac
printf '%s\n' "$@" > "$PWD/../engine-argv.txt"
exit 0
REC
( cd "$AV_SRC" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
( cd "$AV_SRC" && git init -q && git config user.email t@t.t && git config user.name t \
    && git config core.autocrlf false && git add -A && git commit -qm recorder && git branch -M main )
AV_LOG="$ARGV_ROOT/handoff.log"
( cd "$AV" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source --ref main \
    -- --auto-yes ) > "$AV_LOG" 2>&1
av_fail=""
AV_ARGV_FILE="$ARGV_ROOT/case/engine-argv.txt"
if [ ! -f "$AV_ARGV_FILE" ]; then
  av_fail=" [the engine was never invoked — no argv recorded :: $(tail -6 "$AV_LOG" | tr '\n' '|')]"
else
  mapfile -t AV_ARGV < "$AV_ARGV_FILE"
  av_val() { local k="$1" i; for i in "${!AV_ARGV[@]}"; do [ "${AV_ARGV[$i]}" = "$k" ] \
    && { printf '%s' "${AV_ARGV[$((i + 1))]:-}"; return 0; }; done; return 1; }
  av_has() { local x; for x in "${AV_ARGV[@]}"; do [ "$x" = "$1" ] && return 0; done; return 1; }
  AV_TREE="$(av_val --source-tree || true)"
  AV_REPO="$(av_val --source-repo || true)"
  AV_OID="$(av_val --source-commit || true)"
  case "$AV_TREE" in
    /*|[A-Za-z]:[/\\]*) ;;
    *) av_fail="$av_fail [--source-tree is not ABSOLUTE: '$AV_TREE']" ;;
  esac
  case "$AV_REPO" in
    /*|[A-Za-z]:[/\\]*) ;;
    *) av_fail="$av_fail [--source-repo is not ABSOLUTE: '$AV_REPO']" ;;
  esac
  [ -n "$AV_TREE" ] && [ "$AV_TREE" != "$AV_REPO" ] \
    || av_fail="$av_fail [--source-tree equals --source-repo — the engine was pointed at the mutable worktree, not a materialized tree]"
  case "$AV_TREE" in
    *.fusebase-flow-source*) av_fail="$av_fail [--source-tree points INTO the staging clone: '$AV_TREE']" ;;
  esac
  case "$AV_OID" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
      [ "${#AV_OID}" -eq 40 ] || av_fail="$av_fail [--source-commit is not a full 40-char OID: '$AV_OID']" ;;
    *) av_fail="$av_fail [--source-commit missing or not a hex OID: '$AV_OID']" ;;
  esac
  av_has --source-tree-owned || av_fail="$av_fail [--source-tree-owned not passed: the engine would not clean up the temp tree]"
  av_has --auto-yes || av_fail="$av_fail [the operator passthrough flag did not survive the handoff]"
  # The recorder is not the engine, so nobody consumed the transferred ownership — remove it here.
  case "${AV_TREE##*/}" in ff-source-*) [ -d "$AV_TREE" ] && rm -rf -- "$AV_TREE" ;; esac
fi
if [ -z "$av_fail" ]; then
  ok "ac2-absolute-source-tree-handoff-reaches-the-engine (asserted on the recorded engine argv)"
else
  bad "ac2-absolute-source-tree-handoff-reaches-the-engine" "$av_fail"
fi
rm -rf "$ARGV_ROOT"

# ---- 2. AC2 / M10: the non-git source compatibility contract ------------------------------
M10_ROOT="$(mktemp -d)"
# 2a. A manifest-bearing plain-dir source that does not match its OWN manifest must ABORT
#     BEFORE any write, and name the offending path.
D_SRC="$(bnd_plain_case "$M10_ROOT/drift")"
printf 'tampered in transport\n' > "$D_SRC/.fusebase-flow-source/hooks/local/control.sh"
D_LOG="$M10_ROOT/drift.log"
( cd "$D_SRC" && bash hooks/local/upgrade.sh --auto-yes ) > "$D_LOG" 2>&1
D_RC=$?
d_fail=""
[ "$D_RC" -ne 0 ] || d_fail="$d_fail [a DRIFTed source upgraded anyway (rc 0)]"
grep -q "ABORT" "$D_LOG" || d_fail="$d_fail [no abort diagnostic]"
grep -q "DRIFT" "$D_LOG" || d_fail="$d_fail [the abort does not name the DRIFT verdict]"
grep -q "hooks/local/control.sh" "$D_LOG" || d_fail="$d_fail [the offending path is not named]"
grep -q "NOTHING was written" "$D_LOG" || d_fail="$d_fail [the abort does not state nothing was written]"
grep -q "control v1" "$D_SRC/hooks/local/control.sh" || d_fail="$d_fail [content WAS written during an abort]"
if [ -z "$d_fail" ]; then
  ok "m10-manifest-bearing-source-drift-aborts-before-writes"
else
  bad "m10-manifest-bearing-source-drift-aborts-before-writes" "rc=$D_RC$d_fail :: $(tail -8 "$D_LOG" | tr '\n' '|')"
fi
mx_ran "plain/A/H+"

# 2b. A genuinely PRE-manifest source keeps upgrading, through a NAMED logged fallback —
#     never silently, and never labelled verified. Revoking this breaks every pre-4.7.0 source.
L_SRC="$(bnd_plain_case "$M10_ROOT/legacy")"
rm -f "$L_SRC/.fusebase-flow-source/audit/managed-content-manifest.json"
L_LOG="$M10_ROOT/legacy.log"
( cd "$L_SRC" && bash hooks/local/upgrade.sh --auto-yes ) > "$L_LOG" 2>&1
L_RC=$?
l_fail=""
[ "$L_RC" -eq 0 ] || l_fail="$l_fail [pre-manifest source failed to upgrade (rc $L_RC) — the compatibility contract broke]"
grep -q "control v2" "$L_SRC/hooks/local/control.sh" || l_fail="$l_fail [no content delivered]"
grep -q "UNVERIFIED_LEGACY_SOURCE" "$L_LOG" || l_fail="$l_fail [the unverified state was not NAMED in the log]"
if [ -z "$l_fail" ]; then
  ok "m10-pre-manifest-source-upgrades-as-named-unverified-legacy"
else
  bad "m10-pre-manifest-source-upgrades-as-named-unverified-legacy" "rc=$L_RC$l_fail :: $(tail -8 "$L_LOG" | tr '\n' '|')"
fi

# 2c. M10 fail-closed: once a source SHIPS a manifest, the only success is an explicit MATCH.
# Every mutation below leaves the manifest PRESENT and breaks the VERIFIER (or the manifest
# itself) instead of the payload — the 2a case mutates the payload with the verifier intact, so
# it cannot reach any of these branches. Falling back to UNVERIFIED_LEGACY_SOURCE here would
# install bytes nobody can prove upstream shipped, which is exactly what M10 reserves for a
# manifest-ABSENT source.
r1_fail=""
r1_mut_missing_verifier() { rm -f "$1/hooks/local/lib/managed_content_manifest.py"; }
r1_mut_empty_verifier()   { : > "$1/hooks/local/lib/managed_content_manifest.py"; }
r1_mut_unexpected_rc()    { printf 'import sys\nsys.exit(9)\n' > "$1/hooks/local/lib/managed_content_manifest.py"; }
r1_mut_broken_manifest()  { printf 'not json at all\n' > "$1/audit/managed-content-manifest.json"; }
r1_case() {   # <label> <mutator-fn>
  local label="$1" mut="$2" S LOG rc
  S="$(bnd_plain_case "$M10_ROOT/r1-$label")"
  "$mut" "$S/.fusebase-flow-source"
  LOG="$M10_ROOT/r1-$label.log"
  ( cd "$S" && bash hooks/local/upgrade.sh --auto-yes ) > "$LOG" 2>&1; rc=$?
  [ "$rc" -ne 0 ] || r1_fail="$r1_fail [$label: a manifest-bearing source whose verifier cannot report MATCH upgraded anyway (rc 0)]"
  grep -q "ABORT" "$LOG" || r1_fail="$r1_fail [$label: no abort diagnostic]"
  grep -q "audit/managed-content-manifest.json" "$LOG" \
    || r1_fail="$r1_fail [$label: the abort does not name audit/managed-content-manifest.json]"
  grep -q "UNVERIFIED_LEGACY_SOURCE" "$LOG" \
    && r1_fail="$r1_fail [$label: fell back to UNVERIFIED_LEGACY_SOURCE with a manifest PRESENT — M10 allows that fallback ONLY when the manifest is absent]"
  grep -q "control v1" "$S/hooks/local/control.sh" || r1_fail="$r1_fail [$label: content WAS written during an abort]"
}
r1_case "missing-verifier"  r1_mut_missing_verifier
r1_case "empty-verifier"    r1_mut_empty_verifier
r1_case "unexpected-rc"     r1_mut_unexpected_rc
r1_case "broken-manifest"   r1_mut_broken_manifest
if [ -z "$r1_fail" ]; then
  ok "m10-manifest-bearing-source-requires-a-usable-verifier-and-MATCH (missing / empty / unexpected-rc verifier + BROKEN manifest all abort)"
else
  bad "m10-manifest-bearing-source-requires-a-usable-verifier-and-MATCH" "$r1_fail"
fi
rm -rf "$M10_ROOT"

# ---- 2d. AC2 / R3: the boundary is never bootstrapped FROM the mutable source worktree ------
# Both entry points used to `source` the materializer out of $SOURCE_REPO/$SOURCE_CLONE before
# anything was materialized or verified, so the code deciding whether the source is canonical was
# itself unverified. The tampered worktree copy below does exactly what that allows: it redefines
# ff_source_open to report VERIFIED while pointing straight back at the worktree, and drops a
# marker OUTSIDE the consumer root so "was it sourced?" is directly observable.
B3_ROOT="$(mktemp -d)"
b3_tamper() {   # <consumer root>
  cat >> "$1/.fusebase-flow-source/hooks/local/lib/materialize-managed-source.sh" <<'TAMPER'
ff_source_open() {
  FF_SOURCE_REPO="$PWD/.fusebase-flow-source"; FF_SOURCE_TREE="$PWD/.fusebase-flow-source"
  FF_SOURCE_COMMIT=""; FF_SOURCE_KIND="plain"; FF_SOURCE_STATE="VERIFIED"; FF_SOURCE_TREE_TEMP=0
  touch "$PWD/../worktree-helper-was-sourced"
  return 0
}
TAMPER
  printf 'control TAMPERED\n' > "$1/.fusebase-flow-source/hooks/local/control.sh"
}
b3_fail=""
b3_case() {   # <label> <entry command...>
  local label="$1"; shift
  local S LOG rc
  S="$(bnd_plain_case "$B3_ROOT/$label")"
  b3_tamper "$S"
  LOG="$B3_ROOT/$label.log"
  ( cd "$S" && "$@" ) > "$LOG" 2>&1; rc=$?
  [ ! -e "$B3_ROOT/$label/worktree-helper-was-sourced" ] \
    || b3_fail="$b3_fail [$label: the SOURCE WORKTREE's materialize-managed-source.sh was sourced — the boundary bootstrapped itself from unverified source code]"
  grep -q "control v1" "$S/hooks/local/control.sh" \
    || b3_fail="$b3_fail [$label: tampered source bytes were installed :: $(tail -4 "$LOG" | tr '\n' '|')]"
  [ "$rc" -ne 0 ] || b3_fail="$b3_fail [$label: a tampered source upgraded anyway (rc 0)]"
}
b3_case "hop"    bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source -- --auto-yes
b3_case "direct" bash hooks/local/upgrade.sh --auto-yes
if [ -z "$b3_fail" ]; then
  ok "ac2-boundary-never-sourced-from-the-mutable-source-worktree (bootstrap hop + direct engine)"
else
  bad "ac2-boundary-never-sourced-from-the-mutable-source-worktree" "$b3_fail"
fi

# 2e. AC2 / R3: the direct engine REFUSES a pre-boundary execution rather than falling back to the
# worktree copy, and names the supported route.
NB="$(bnd_plain_case "$B3_ROOT/no-installed-lib")"
rm -f "$NB/hooks/local/lib/materialize-managed-source.sh"
NB_LOG="$B3_ROOT/no-installed-lib.log"
( cd "$NB" && bash hooks/local/upgrade.sh --auto-yes ) > "$NB_LOG" 2>&1
NB_RC=$?
nb_fail=""
[ "$NB_RC" -ne 0 ] || nb_fail="$nb_fail [an install with no trusted boundary lib upgraded anyway (rc 0) — it fell back to the worktree copy]"
grep -q "bootstrap-upgrade.sh" "$NB_LOG" || nb_fail="$nb_fail [the refusal does not name the supported route]"
grep -q "control v1" "$NB/hooks/local/control.sh" || nb_fail="$nb_fail [content was written during the refusal]"
if [ -z "$nb_fail" ]; then
  ok "ac2-direct-engine-refuses-pre-boundary-execution"
else
  bad "ac2-direct-engine-refuses-pre-boundary-execution" "rc=$NB_RC$nb_fail :: $(tail -6 "$NB_LOG" | tr '\n' '|')"
fi

# 2f. K10 non-regression: an install that predates the boundary lib must STILL upgrade through the
# bootstrap hop — the hop materializes with its own minimal embedded logic (plain snapshot AND git
# objects), sources the shared lib from THAT tree, verifies, then runs the new engine from it.
for k10 in plain git; do
  K="$(bnd_plain_case "$B3_ROOT/k10-$k10")"
  rm -f "$K/hooks/local/lib/materialize-managed-source.sh"    # consumer predates the boundary lib
  K_REF=()
  if [ "$k10" = "git" ]; then
    ( cd "$K/.fusebase-flow-source" && git init -q && git config user.email t@t.t \
        && git config user.name t && git config core.autocrlf false \
        && git add -A && git commit -qm src && git branch -M main )
    K_REF=(--ref main)
  fi
  K_LOG="$B3_ROOT/k10-$k10.log"
  ( cd "$K" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
      ${K_REF[@]+"${K_REF[@]}"} -- --auto-yes ) > "$K_LOG" 2>&1
  K_RC=$?
  k_fail=""
  [ "$K_RC" -eq 0 ] || k_fail="$k_fail [rc $K_RC — the hop no longer upgrades an install without the boundary lib (K10 regression)]"
  grep -q "control v2" "$K/hooks/local/control.sh" || k_fail="$k_fail [no content delivered]"
  grep -q "embedded boundary" "$K_LOG" || k_fail="$k_fail [the embedded materialization did not run — the hop found the lib somewhere it should not have]"
  if [ "$k10" = "git" ]; then
    grep -q "materialized git source @" "$K_LOG" || k_fail="$k_fail [the git-objects path did not run]"
  fi
  # No post-upgrade MATCH assertion here: this fixture DELETES a managed file to model the
  # pre-boundary install, and K9 legitimately preserves that deletion. Post-upgrade MATCH is the
  # AC1 case's job.
  if [ -z "$k_fail" ]; then
    ok "k10-embedded-boundary-still-upgrades-a-pre-boundary-install-$k10"
  else
    bad "k10-embedded-boundary-still-upgrades-a-pre-boundary-install-$k10" "$k_fail :: $(tail -8 "$K_LOG" | tr '\n' '|')"
  fi
  mx_ran "$k10/A/H-"
done

# 2g. M10 end to end: a source with NEITHER manifest NOR materializer — the genuine pre-4.7.0
# shape — must COMPLETE the named UNVERIFIED_LEGACY_SOURCE route, not merely enter it. 2f above
# cannot see this: its source still ships the new materializer AND the new engine, so the hop takes
# the --source-tree handoff. Here the source engine predates that flag, which is what makes
# "release the canonical tree, then exec the engine inside it" a 127 instead of an upgrade.
for helper in "H-" "H+"; do for kind in plain git; do
  P="$(bnd_plain_case "$B3_ROOT/legacyroute-$kind-$helper")"
  PS="$P/.fusebase-flow-source"
  # H- models the pre-boundary consumer; H+ keeps the trusted installed lib, so the verdict is
  # reached by DIFFERENT code (the lib, not the embedded pair) on the same manifest-less source.
  [ "$helper" = "H-" ] && rm -f "$P/hooks/local/lib/materialize-managed-source.sh"
  rm -f "$PS/hooks/local/lib/materialize-managed-source.sh" "$PS/audit/managed-content-manifest.json"
  bnd_legacy_engine "$PS"
  P_REF=()
  if [ "$kind" = "git" ]; then bnd_git_source "$PS"; P_REF=(--ref main); fi
  P_LOG="$B3_ROOT/legacyroute-$kind-$helper.log"
  ( cd "$P" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
      ${P_REF[@]+"${P_REF[@]}"} -- --auto-yes ) > "$P_LOG" 2>&1
  P_RC=$?
  p_fail=""
  [ "$P_RC" -eq 0 ] || p_fail="$p_fail [rc $P_RC — a source with neither manifest nor materializer did not upgrade]"
  [ -f "$P/legacy-engine-argv.txt" ] || p_fail="$p_fail [the source engine never ran]"
  grep -q "control v2" "$P/hooks/local/control.sh" 2>/dev/null || p_fail="$p_fail [no content delivered]"
  grep -q "UNVERIFIED_LEGACY_SOURCE" "$P_LOG" || p_fail="$p_fail [the unverified state was not NAMED in the log]"
  if [ -f "$P/legacy-engine-argv.txt" ]; then
    grep -q -- "--source-tree" "$P/legacy-engine-argv.txt" \
      && p_fail="$p_fail [internal boundary flags were handed to an engine that cannot parse them]"
    grep -q -- "--auto-yes" "$P/legacy-engine-argv.txt" \
      || p_fail="$p_fail [the operator passthrough flag did not survive the handoff]"
  fi
  if [ -z "$p_fail" ]; then
    ok "m10-pre-boundary-source-completes-the-unverified-legacy-route-$kind-$helper"
  else
    bad "m10-pre-boundary-source-completes-the-unverified-legacy-route-$kind-$helper" "$p_fail :: $(tail -8 "$P_LOG" | tr '\n' '|')"
  fi
  mx_ran "$kind/C/$helper"
done; done

# 2h. M11: a source that ships audit/managed-content-manifest.json AND
# hooks/local/lib/managed_content_manifest.py but NO materialize-managed-source.sh — the shape the
# published v4.7.0 tag actually has, and one a prerelease tester already fetched. It carries its own
# verifier, so its bytes CAN be proven and it must upgrade; refusing it strands a real historical
# source. M11 is unweakened: the drift control below still aborts on the same shape.
for kind in plain git; do
  V="$(bnd_plain_case "$B3_ROOT/verifieronly-$kind")"
  VS="$V/.fusebase-flow-source"
  rm -f "$V/hooks/local/lib/materialize-managed-source.sh"     # consumer predates the boundary lib
  rm -f "$VS/hooks/local/lib/materialize-managed-source.sh"    # …and so does the source
  bnd_legacy_engine "$VS"
  ( cd "$VS" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  V_REF=()
  if [ "$kind" = "git" ]; then bnd_git_source "$VS"; V_REF=(--ref main); fi
  V_LOG="$B3_ROOT/verifieronly-$kind.log"
  ( cd "$V" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
      ${V_REF[@]+"${V_REF[@]}"} -- --auto-yes ) > "$V_LOG" 2>&1
  V_RC=$?
  v_fail=""
  [ "$V_RC" -eq 0 ] || v_fail="$v_fail [rc $V_RC — a source that SHIPS its own verifier was refused]"
  grep -q "control v2" "$V/hooks/local/control.sh" 2>/dev/null || v_fail="$v_fail [no content delivered]"
  grep -q "cannot be proven" "$V_LOG" \
    && v_fail="$v_fail [refused as unprovable although the source ships managed_content_manifest.py]"
  grep -q "UNVERIFIED_LEGACY_SOURCE" "$V_LOG" \
    && v_fail="$v_fail [a manifest-BEARING source was routed to the legacy fallback — M10/M11 reserve that for manifest-ABSENT sources]"
  grep -q "state=VERIFIED" "$V_LOG" || v_fail="$v_fail [the source was never reported VERIFIED]"
  if [ -z "$v_fail" ]; then
    ok "m11-manifest-plus-verifier-without-materializer-is-provable-$kind"
  else
    bad "m11-manifest-plus-verifier-without-materializer-is-provable-$kind" "$v_fail :: $(tail -8 "$V_LOG" | tr '\n' '|')"
  fi
  mx_ran "$kind/B/H-"
done

# NEGATIVE CONTROL for 2h: the same shape with drifted bytes still ABORTS. Without this, "the
# verifier-only shape upgrades" could be satisfied by simply not verifying it.
#
# THE TREE THAT WAS PROVEN MUST BE THE TREE THE ENGINE CONSUMES — and that is why transport is
# NOT interchangeable here (an earlier round waived git on the claim that it was):
#   plain  the materialized tree is a COPY of the worktree, so a tamper is caught at
#          materialization, before the pre-boundary engine is reached at all.
#   git    the materialized tree comes from COMMITTED OBJECTS. A source whose commit is clean
#          and whose WORKTREE is tampered therefore verifies MATCH — and the pre-boundary engine
#          then reads `.fusebase-flow-source` BY NAME (lib/upgrade-fixtures.sh), i.e. the
#          tampered worktree. VERIFIED followed by installing bytes nobody verified.
# Both consumer states run: the installed helper changes WHICH CODE materializes the tree, never
# WHICH TREE the legacy engine reads, so H+ is exposed to the same split as H-.
for helper in "H-" "H+"; do for kind in plain git; do
  VD="$(bnd_plain_case "$B3_ROOT/vdrift-$kind-$helper")"
  VDS="$VD/.fusebase-flow-source"
  [ "$helper" = "H-" ] && rm -f "$VD/hooks/local/lib/materialize-managed-source.sh"
  rm -f "$VDS/hooks/local/lib/materialize-managed-source.sh"
  bnd_legacy_engine "$VDS"
  ( cd "$VDS" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  VD_REF=()
  if [ "$kind" = "git" ]; then bnd_git_source "$VDS"; VD_REF=(--ref main); fi
  # AFTER the commit on purpose: the objects stay clean, so only a verdict reached on the tree
  # the engine actually consumes can see this.
  printf 'control TAMPERED\n' > "$VDS/hooks/local/control.sh"
  VD_LOG="$B3_ROOT/vdrift-$kind-$helper.log"
  ( cd "$VD" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
      ${VD_REF[@]+"${VD_REF[@]}"} -- --auto-yes ) > "$VD_LOG" 2>&1
  VD_RC=$?
  vd_fail=""
  [ "$VD_RC" -ne 0 ] || vd_fail="$vd_fail [a DRIFTed manifest-bearing source upgraded anyway (rc 0)]"
  grep -q "ABORT" "$VD_LOG" || vd_fail="$vd_fail [no abort diagnostic]"
  grep -q "DRIFT" "$VD_LOG" || vd_fail="$vd_fail [the abort does not name the DRIFT verdict]"
  grep -q "hooks/local/control.sh" "$VD_LOG" || vd_fail="$vd_fail [the offending path is not named]"
  grep -q "control v1" "$VD/hooks/local/control.sh" || vd_fail="$vd_fail [tampered bytes were installed]"
  [ ! -f "$VD/legacy-engine-argv.txt" ] || vd_fail="$vd_fail [the engine ran despite the abort]"
  if [ -z "$vd_fail" ]; then
    ok "m11-verifier-only-source-still-aborts-on-drift-$kind-$helper"
  else
    bad "m11-verifier-only-source-still-aborts-on-drift-$kind-$helper" "rc=$VD_RC$vd_fail :: $(tail -8 "$VD_LOG" | tr '\n' '|')"
  fi
  mx_ran "$kind/B/$helper"
done; done

# 2h-bis. The self-consistent HYBRID: manifest + verifier + a BOUNDARY-AWARE engine, but no
# materialize-managed-source.sh anywhere. The hop transfers temp-tree OWNERSHIP with
# --source-tree-owned; the engine then takes its warning-only path (no lib to arm
# ff_source_cleanup with), so the tree it now owns has nobody to release it. TMPDIR is
# fixture-owned here, which makes the leak an observable empty-or-not directory rather than a
# log claim. Not the published tag shape — but ownership must be deterministic for every shape
# the hop is willing to hand over to.
HY="$(bnd_plain_case "$B3_ROOT/hybrid-owned-tree")"
rm -f "$HY/hooks/local/lib/materialize-managed-source.sh"
rm -f "$HY/.fusebase-flow-source/hooks/local/lib/materialize-managed-source.sh"
( cd "$HY/.fusebase-flow-source" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
HY_TMP="$B3_ROOT/hybrid-tmp"; mkdir -p "$HY_TMP"
HY_LOG="$B3_ROOT/hybrid-owned-tree.log"
( cd "$HY" && TMPDIR="$HY_TMP" bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source \
    -- --auto-yes ) > "$HY_LOG" 2>&1
HY_RC=$?
hy_fail=""
[ "$HY_RC" -eq 0 ] || hy_fail="$hy_fail [rc $HY_RC — a manifest+verifier source with a boundary-aware engine did not upgrade]"
grep -q "control v2" "$HY/hooks/local/control.sh" 2>/dev/null || hy_fail="$hy_fail [no content delivered]"
HY_LEFT="$(find "$HY_TMP" -maxdepth 1 -name 'ff-source-*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$HY_LEFT" = "0" ] \
  || hy_fail="$hy_fail [$HY_LEFT transferred temp tree(s) left under TMPDIR — the engine accepted ownership on a path that releases nothing]"
if [ -z "$hy_fail" ]; then
  ok "m1-transferred-temp-tree-is-released-even-without-a-source-materializer"
else
  bad "m1-transferred-temp-tree-is-released-even-without-a-source-materializer" "$hy_fail :: $(tail -8 "$HY_LOG" | tr '\n' '|')"
fi

# 2i. R3 completed: the OLD-INSTALL half of the tamper matrix. 2d keeps the consumer's trusted
# helper installed, so the hop never had to decide the verdict from source-supplied shell. Here the
# consumer has NO local helper, so the hop must materialize and verify with its own embedded code —
# and the source's helper, which redefines ff_source_verify_tree to approve anything and drops a
# marker OUTSIDE the consumer root, must never be sourced at all.
T="$(bnd_plain_case "$B3_ROOT/selfapprove")"
rm -f "$T/hooks/local/lib/materialize-managed-source.sh"
cat >> "$T/.fusebase-flow-source/hooks/local/lib/materialize-managed-source.sh" <<'TAMPER'
ff_source_verify_tree() {
  FF_SOURCE_STATE="VERIFIED"; FF_SOURCE_REASON=""; FF_SOURCE_DRIFT=""
  touch "$PWD/../source-helper-approved-itself"
  return 0
}
TAMPER
printf 'control TAMPERED\n' > "$T/.fusebase-flow-source/hooks/local/control.sh"
T_LOG="$B3_ROOT/selfapprove.log"
( cd "$T" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source -- --auto-yes ) > "$T_LOG" 2>&1
T_RC=$?
t_fail=""
[ ! -e "$B3_ROOT/selfapprove/source-helper-approved-itself" ] \
  || t_fail="$t_fail [the SOURCE tree's own materialize-managed-source.sh decided the verdict — it redefined ff_source_verify_tree and approved itself]"
[ "$T_RC" -ne 0 ] || t_fail="$t_fail [a tampered source upgraded anyway (rc 0)]"
grep -q "control v1" "$T/hooks/local/control.sh" || t_fail="$t_fail [tampered source bytes were installed]"
grep -q "ABORT" "$T_LOG" || t_fail="$t_fail [no abort diagnostic]"
grep -q "audit/managed-content-manifest.json\|DRIFT" "$T_LOG" \
  || t_fail="$t_fail [the abort names neither the manifest nor the DRIFT verdict]"
if [ -z "$t_fail" ]; then
  ok "r3-old-install-cannot-be-verified-by-the-source-own-helper"
else
  bad "r3-old-install-cannot-be-verified-by-the-source-own-helper" "rc=$T_RC$t_fail :: $(tail -8 "$T_LOG" | tr '\n' '|')"
fi
mx_ran "plain/A/H-"

# ---- 2i-bis. B4: the tree the engine CONSUMES may not be judged by its OWN verifier ---------
# One level deeper than 2i/R3: Step 2c re-reaches the verdict on the mutable worktree, and doing
# that by executing the WORKTREE's managed_content_manifest.py lets a tamper that ALSO rewrites
# that file print MATCH for itself — B1 in Python instead of shell. GIT transport only: the
# canonical tree comes from CLEAN COMMITTED OBJECTS, so it verifies honestly and the lying
# worktree verifier is the only thing between the tampered payload and the consumer.
for helper in "H-" "H+"; do
  LV="$(bnd_plain_case "$B3_ROOT/liarverifier-$helper")"
  LVS="$LV/.fusebase-flow-source"
  [ "$helper" = "H-" ] && rm -f "$LV/hooks/local/lib/materialize-managed-source.sh"
  rm -f "$LVS/hooks/local/lib/materialize-managed-source.sh"
  bnd_legacy_engine "$LVS"
  ( cd "$LVS" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  bnd_git_source "$LVS"
  # BOTH mutations land AFTER the commit: the payload the consumer would receive, and the
  # verifier that would be asked about it.
  printf 'control TAMPERED\n' > "$LVS/hooks/local/control.sh"
  cat > "$LVS/hooks/local/lib/managed_content_manifest.py" <<'LIAR'
import sys
print('{"verdict": "MATCH", "listed": 0, "files": []}')
sys.exit(0)
LIAR
  LV_LOG="$B3_ROOT/liarverifier-$helper.log"
  ( cd "$LV" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source --ref main \
      -- --auto-yes ) > "$LV_LOG" 2>&1
  LV_RC=$?
  lv_fail=""
  [ "$LV_RC" -ne 0 ] || lv_fail="$lv_fail [a worktree that tampered its OWN verifier upgraded anyway (rc 0)]"
  grep -q "ABORT" "$LV_LOG" || lv_fail="$lv_fail [no abort diagnostic]"
  grep -q "audit/managed-content-manifest.json" "$LV_LOG" \
    || lv_fail="$lv_fail [the abort does not name audit/managed-content-manifest.json]"
  grep -q "hooks/local/control.sh" "$LV_LOG" \
    || lv_fail="$lv_fail [the offending payload path is not named]"
  grep -q "control v1" "$LV/hooks/local/control.sh" || lv_fail="$lv_fail [tampered bytes were installed]"
  [ ! -f "$LV/legacy-engine-argv.txt" ] || lv_fail="$lv_fail [the engine ran despite the abort]"
  if [ -z "$lv_fail" ]; then
    ok "b4-consumed-worktree-cannot-be-approved-by-its-own-verifier-git-$helper"
  else
    bad "b4-consumed-worktree-cannot-be-approved-by-its-own-verifier-git-$helper" "rc=$LV_RC$lv_fail :: $(tail -8 "$LV_LOG" | tr '\n' '|')"
  fi
  mx_ran "git/B/$helper"
done

# ---- 2i-ter. M10/M11 downgrade: hiding the worktree manifest must not buy the legacy route --
# The canonical tree is VERIFIED from committed objects; the WORKTREE's manifest is deleted after
# the commit. UNVERIFIED_LEGACY_SOURCE is M10's fallback for a source that has no manifest
# ANYWHERE — never for one whose worktree hides it, or a single `rm` downgrades "unprovable bytes
# abort" into "unprovable bytes install". The control flow already refused this at 7f173f3; what
# was missing is any case pinning it, and a diagnostic that names the file the consumed tree lacks.
for helper in "H-" "H+"; do
  MH="$(bnd_plain_case "$B3_ROOT/hidemanifest-$helper")"
  MHS="$MH/.fusebase-flow-source"
  [ "$helper" = "H-" ] && rm -f "$MH/hooks/local/lib/materialize-managed-source.sh"
  rm -f "$MHS/hooks/local/lib/materialize-managed-source.sh"
  bnd_legacy_engine "$MHS"
  ( cd "$MHS" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  bnd_git_source "$MHS"
  rm -f "$MHS/audit/managed-content-manifest.json"
  MH_LOG="$B3_ROOT/hidemanifest-$helper.log"
  ( cd "$MH" && bash hooks/local/bootstrap-upgrade.sh --source .fusebase-flow-source --ref main \
      -- --auto-yes ) > "$MH_LOG" 2>&1
  MH_RC=$?
  mh_fail=""
  [ "$MH_RC" -ne 0 ] || mh_fail="$mh_fail [hiding the worktree manifest upgraded anyway (rc 0)]"
  grep -q "ABORT" "$MH_LOG" || mh_fail="$mh_fail [no abort diagnostic]"
  grep -q "audit/managed-content-manifest.json" "$MH_LOG" \
    || mh_fail="$mh_fail [the abort does not name audit/managed-content-manifest.json — the operator cannot tell WHICH file the consumed tree is missing]"
  grep -q "UNVERIFIED_LEGACY_SOURCE" "$MH_LOG" \
    && mh_fail="$mh_fail [routed to the legacy fallback although the canonical tree ships the manifest — M10 reserves that for manifest-ABSENT sources]"
  [ ! -f "$MH/legacy-engine-argv.txt" ] || mh_fail="$mh_fail [the engine ran on the hidden-manifest worktree]"
  grep -q "control v1" "$MH/hooks/local/control.sh" || mh_fail="$mh_fail [content was written during the abort]"
  if [ -z "$mh_fail" ]; then
    ok "m10-hiding-the-worktree-manifest-does-not-downgrade-to-the-legacy-route-git-$helper"
  else
    bad "m10-hiding-the-worktree-manifest-does-not-downgrade-to-the-legacy-route-git-$helper" "rc=$MH_RC$mh_fail :: $(tail -8 "$MH_LOG" | tr '\n' '|')"
  fi
  mx_ran "git/B/$helper"
done
rm -rf "$B3_ROOT"

# ---- 2j. the matrix itself: every cell named, every RUN cell actually run ------------------
mx_fail=""; mx_run=0; mx_waive=0
for t in plain git; do for s in A B C; do for h in "H+" "H-"; do
  key="$t/$s/$h"; row=""
  for r in "${MX_ROWS[@]}"; do case "$r" in "$key|"*) row="$r" ;; esac; done
  if [ -z "$row" ]; then mx_fail="$mx_fail [$key: no matrix row — a source shape is undispositioned]"; continue; fi
  case "$row" in
    *"|RUN|"*)
      mx_run=$((mx_run + 1))
      case $'\n'"$MX_SEEN"$'\n' in
        *$'\n'"$key"$'\n'*) ;;
        *) mx_fail="$mx_fail [$key: declared RUN by '${row##*|}' but no case reported it — the cell was dropped]" ;;
      esac ;;
    *"|WAIVE|"*)
      mx_waive=$((mx_waive + 1))
      [ -n "${row##*|}" ] || mx_fail="$mx_fail [$key: WAIVE with no reason]" ;;
    *) mx_fail="$mx_fail [$key: row is neither RUN nor WAIVE]" ;;
  esac
  echo "[source-shape-matrix] $row"
done; done; done
if [ -z "$mx_fail" ]; then
  ok "source-shape-matrix-is-complete ($mx_run RUN + $mx_waive WAIVE = 12 cells; transport x source shape x consumer helper)"
else
  bad "source-shape-matrix-is-complete" "$mx_fail"
fi

# ---- 4. M2: the integrity hashers stay BYTE-EXACT ----------------------------------------
# BEHAVIOURAL, not a text scan: hash the SAME logical content as LF and as CRLF and require
# different digests. Normalizing before hashing would have silenced this whole ticket's true
# positive (the consumer's bytes really were wrong) and made every future transport
# corruption undiagnosable. Every CRLF assertion above is only detectable because of this.
M2_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PYM2' 2>&1
import json, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks" / "local" / "lib"))
import hook_manifest, managed_content_manifest  # noqa: E402
fails = []
with tempfile.TemporaryDirectory() as d:
    lf, crlf = Path(d) / "lf.txt", Path(d) / "crlf.txt"
    lf.write_bytes(b"line one\nline two\n")
    crlf.write_bytes(b"line one\r\nline two\r\n")
    for mod in (hook_manifest, managed_content_manifest):
        if mod.sha256_of(lf) == mod.sha256_of(crlf):
            fails.append(mod.__name__ + ".sha256_of normalizes line endings (M2 forbids: the "
                         "manifest would go blind to the exact corruption class it exists to catch)")
print(json.dumps(fails))
PYM2
)"
if [ "$M2_OUT" = "[]" ]; then
  ok "m2-integrity-hashers-remain-byte-exact"
else
  bad "m2-integrity-hashers-remain-byte-exact" "$M2_OUT"
fi

finish
