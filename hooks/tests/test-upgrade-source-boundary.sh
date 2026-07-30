#!/usr/bin/env bash
# Fusebase Flow — canonical source boundary + byte-model tests (T1 / AC1-AC3).
# Spec: docs/specs/upgrade-source-integrity-and-observability/ (decisions M1, M2, M10).
#
# Separate from test-upgrade-conflict-classification.sh on a responsibility seam: that file
# owns K9 classification, this one owns WHICH BYTES enter the consumer. The three byte models
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
finish() { echo "[test-upgrade-source-boundary] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: upgrade-boundary skipped-no-python3"; pass=1; finish; }
command -v git >/dev/null 2>&1 || { echo "PASS: upgrade-boundary skipped-no-git"; pass=1; finish; }

MCM="$ROOT/hooks/local/lib/managed_content_manifest.py"

# has_cr <file>: 0 iff the file holds >=1 CR byte. THE measurand for every assertion here —
# `diff` normalizes line endings, so it can never answer this question (that is why the
# original report read a true-positive byte drift as a false positive).
has_cr() { [ -n "$(tr -dc '\r' < "$1" 2>/dev/null)" ]; }

# The 4.7.0+ boundary libs, `[ -f ]`-guarded so this fixture still BUILDS against a
# pre-boundary baseline tree — that is how these discriminators are observed RED.
copy_boundary_libs() {   # <lib-dest-dir>
  local f
  for f in materialize-managed-source.sh backup-hygiene.sh; do
    [ -f "$ROOT/hooks/local/lib/$f" ] && cp "$ROOT/hooks/local/lib/$f" "$1/"
  done
  return 0
}

# A plain-directory (non-git) source case: a consumer with a VALID recorded base and a
# copy-eligible upstream change (control.sh v1 -> v2), so a "nothing was written" assertion
# can never pass through unknown-base preservation instead of a real abort.
bnd_plain_case() {   # <dir> -> echoes the consumer root
  local D="$1" L U d
  L="$D/local"; U="$L/.fusebase-flow-source"
  mkdir -p "$L/hooks/local/lib" "$L/workflows" "$U/hooks/local/lib" "$U/workflows"
  ( cd "$L" && git init -q && git config user.email t@t.t && git config user.name t )
  echo "4.6.1" > "$L/VERSION"; printf 'control v1\n' > "$L/hooks/local/control.sh"
  echo "4.7.0" > "$U/VERSION"; printf 'control v2\n' > "$U/hooks/local/control.sh"
  printf 'wf v1\n' > "$L/workflows/wf.md"; printf 'wf v1\n' > "$U/workflows/wf.md"
  for d in "$L" "$U"; do
    cp "$ROOT/hooks/local/upgrade.sh" "$ROOT/hooks/local/bootstrap-upgrade.sh" "$d/hooks/local/"
    cp "$MCM" "$d/hooks/local/lib/"
    copy_boundary_libs "$d/hooks/local/lib"
    ( cd "$d" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  done
  echo "$L"
}

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
# AC2 half: the boundary really crossed into the engine as an internal absolute handoff.
if grep -q "materialized git source @" "$F2_LOG" && grep -q "caller-materialized canonical tree" "$F2_LOG"; then
  ok "ac2-absolute-source-tree-handoff-reaches-the-engine"
else
  bad "ac2-absolute-source-tree-handoff-reaches-the-engine" "$(tail -8 "$F2_LOG" | tr '\n' '|')"
fi
rm -rf "$F2_ROOT"

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
