#!/usr/bin/env bash
# Fusebase Flow — N5: the ordinary upgrade path must DELIVER, or say it did not.
# Spec: docs/specs/n5-upgrade-silent-no-op/spec.md · decisions N1/N2/N3.
#
# THE ORACLE IS THE CONSUMER'S REPRODUCTION. Same trees, one variable — whether
# audit/managed-content-manifest.json exists:
#
#   --base     upstream-only(refreshed)   unknown-base(silently kept)   consumer-only
#   absent               0                          26                        0
#   present             24                           0                        2
#
# 24 upstream changes silently dropped, and the 2 genuinely consumer-edited files lost their
# `consumer-only` protection into the same bucket. VERSION advanced anyway and the run exited
# 0, so nothing downstream could notice; it was found by hand-grepping for three known fixes.
#
# WHY upgrade.sh AND NOT bootstrap-upgrade.sh: synthesis (K13a) shipped only in bootstrap,
# and bootstrap is not the path most consumers take. AC13b in
# test-upgrade-conflict-classification.sh already covers the bootstrap hop; every row here
# drives the ORDINARY engine.
#
# ROW CLASSES:
#   DISCRIMINATOR  n1-synthesis-delivers      — the matrix above, through upgrade.sh
#   CONTROL        n1-base-present-unchanged  — synthesis must be a no-op when a base exists
#   K9 GUARD       n2-forked-still-proceeds   — unresolvable tag + files delivered => NO abort
#   NEW RULE       n3-refuses / n3-dry-run    — delivered nothing => exit 4, VERSION intact
#   ANTI-FALSE-POS n3-current-tree-quiet      — nothing to do must NOT trip the refusal
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: n5-delivery <name>" / "FAIL: n5-delivery <name>"; exit = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: n5-delivery $1"; }
bad() { fail=$((fail + 1)); local w="${2:-}"; [ -z "$w" ] || w=" ($(printf '%s' "$w" | tr '\n\r\t' '   ' | cut -c1-400))"; echo "FAIL: n5-delivery $1$w"; }
skip(){ pass=$((pass + 1)); echo "PASS: n5-delivery $1 [SKIP — $2]"; }
finish() { echo "[test-upgrade-delivers-or-refuses] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v git >/dev/null 2>&1 || { skip setup "no git"; finish; }
command -v python3 >/dev/null 2>&1 || { skip setup "no python3"; finish; }

BASE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-n5.XXXXXX" 2>/dev/null)"
[ -n "$BASE_TMP" ] || { bad setup "no temp dir"; finish; }
cleanup() { rm -rf "$BASE_TMP" 2>/dev/null; }
trap cleanup EXIT

LIBS="materialize-managed-source.sh backup-hygiene.sh synthesize-base.sh upgrade-delivery-guard.sh"

# make_case <dir> <consumer-version> <with-base:0|1> <source-is-git:0|1> <adds-file:0|1> [tag:0|1]
#   Consumer holds v4.6.1 content plus ONE local edit (the SENTINEL). Upstream is 4.7.0 and
#   changes control.sh. With a resolvable tag the engine can reconstruct the base; without
#   one it cannot, which is the fork case K9 protects.
#
#   TRIPWIRE — tag=0 models the FORKED/unreleased consumer: the source repo exists but carries
#   no tag matching their VERSION, so no base can be reconstructed. The first version of this
#   file tagged the "forked" fixtures too, which made synthesis SUCCEED — the refusal rows then
#   asserted against a tree that had legitimately delivered, and reported a false RED.
make_case() {
  local D="$1" cver="$2" withbase="$3" srcgit="$4" adds="$5" tag="${6:-1}" L U
  L="$D/local"; U="$L/.fusebase-flow-source"
  mkdir -p "$L/hooks/shared" "$L/hooks/local/lib" "$L/workflows"
  ( cd "$L" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config core.autocrlf false )
  echo "$cver" > "$L/VERSION"
  printf 'validator v1\n' > "$L/hooks/shared/command_policy.py"
  printf 'control v1\n'   > "$L/hooks/local/control.sh"
  printf 'wf v1\n'        > "$L/workflows/wf.md"
  cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$L/hooks/local/lib/"
  cp "$ROOT/hooks/local/upgrade.sh" "$L/hooks/local/"
  for f in $LIBS; do [ -f "$ROOT/hooks/local/lib/$f" ] && cp "$ROOT/hooks/local/lib/$f" "$L/hooks/local/lib/"; done
  [ "$withbase" = "1" ] && ( cd "$L" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  # the consumer's own edit, made AFTER any base was recorded
  printf 'validator v1\n# SENTINEL local hardening\n' > "$L/hooks/shared/command_policy.py"

  mkdir -p "$U/hooks/shared" "$U/hooks/local/lib" "$U/workflows"
  echo "4.7.0" > "$U/VERSION"
  printf 'validator v1\n' > "$U/hooks/shared/command_policy.py"   # upstream did NOT change it
  printf 'control v2\n'   > "$U/hooks/local/control.sh"           # upstream DID change it
  printf 'wf v1\n'        > "$U/workflows/wf.md"
  [ "$adds" = "1" ] && printf 'new upstream file\n' > "$U/hooks/shared/brand_new.py"
  cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$U/hooks/local/lib/"
  cp "$ROOT/hooks/local/upgrade.sh" "$U/hooks/local/"
  for f in $LIBS; do [ -f "$ROOT/hooks/local/lib/$f" ] && cp "$ROOT/hooks/local/lib/$f" "$U/hooks/local/lib/"; done
  ( cd "$U" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )

  if [ "$srcgit" = "1" ]; then
    # A REAL git source carrying the consumer's version as a tag — this is what makes
    # synthesis possible, and it is what a real staging clone looks like.
    ( cd "$U" && git init -q && git config user.email t@t.t && git config user.name t \
        && git config core.autocrlf false )
    ( cd "$U" && git checkout -q -b main 2>/dev/null || true )
    # the tag must hold the CONSUMER's v4.6.1 content, not 4.7.0's
    ( cd "$U" && echo "$cver" > VERSION && printf 'control v1\n' > hooks/local/control.sh \
        && printf 'validator v1\n' > hooks/shared/command_policy.py \
        && rm -f hooks/shared/brand_new.py \
        && git add -A >/dev/null 2>&1 && git commit -qm "v$cver" >/dev/null 2>&1 )
    [ "$tag" = "1" ] && ( cd "$U" && git tag -a "v$cver" -m "v$cver" >/dev/null 2>&1 )
    # then advance to 4.7.0 and COMMIT it. TRIPWIRE: the engine materializes managed content
    # from GIT OBJECTS at the resolved ref, never from the source worktree (decision M1 —
    # "NEVER from $SOURCE_REPO's mutable worktree: that copy could redefine itself"). Leaving
    # 4.7.0 uncommitted makes the engine read the v4.6.1 tree and deliver nothing, which looks
    # exactly like the defect under test and would have made every row here a false RED.
    echo "4.7.0" > "$U/VERSION"
    printf 'control v2\n' > "$U/hooks/local/control.sh"
    [ "$adds" = "1" ] && printf 'new upstream file\n' > "$U/hooks/shared/brand_new.py"
    ( cd "$U" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
    ( cd "$U" && git add -A >/dev/null 2>&1 && git commit -qm "4.7.0" >/dev/null 2>&1 )
  fi
  echo "$L"
}

run_upgrade() {   # run_upgrade <local-dir> <log> [extra-args...]
  local L="$1" log="$2"; shift 2
  ( cd "$L" && bash hooks/local/upgrade.sh --auto-yes "$@" ) > "$log" 2>&1
  echo $?
}

###############################################################################
# DISCRIMINATOR — the consumer's matrix, on the ORDINARY path
###############################################################################
D1="$BASE_TMP/d1"; L1="$(make_case "$D1" 4.6.1 0 1 1)"; LOG1="$D1/up.log"
RC1="$(run_upgrade "$L1" "$LOG1")"
f=""
grep -q "synthesized the classifier base from upstream tag v4.6.1" "$LOG1" \
  || f="$f [no base synthesized on the upgrade.sh path — this is N5 itself]"
grep -q "control v2" "$L1/hooks/local/control.sh" \
  || f="$f [upstream change NOT delivered: the 'successful' upgrade installed nothing]"
grep -q SENTINEL "$L1/hooks/shared/command_policy.py" \
  || f="$f [the consumer's own edit was OVERWRITTEN]"
grep -q "unknown-base" "$LOG1" \
  && f="$f [paths still fell through to unknown-base despite a synthesized base]"
grep -qE "consumer-only" "$LOG1" \
  || f="$f [the consumer edit lost its consumer-only protection into the unknown-base bucket]"
[ "$(tr -d '\n\r' < "$L1/VERSION")" = "4.7.0" ] || f="$f [VERSION did not advance on a run that DID deliver]"
[ -z "$f" ] && ok "n1-synthesis-delivers (base absent + resolvable tag => upstream change applied, consumer edit preserved AS consumer-only, 0 unknown-base, VERSION advanced)" \
            || bad n1-synthesis-delivers "rc=$RC1$f"

###############################################################################
# CONTROL — a base already present must be untouched by synthesis
###############################################################################
D2="$BASE_TMP/d2"; L2="$(make_case "$D2" 4.6.1 1 1 1)"; LOG2="$D2/up.log"
RC2="$(run_upgrade "$L2" "$LOG2")"
f=""
# upgrade.sh guards the call on the base being ABSENT, so with one present synthesis is never
# invoked and prints nothing. The contract that matters is that it did not re-synthesize.
grep -q "synthesized the classifier base" "$LOG2" && f="$f [it re-synthesized over an existing base]"
grep -q "control v2" "$L2/hooks/local/control.sh" || f="$f [upstream change not delivered]"
grep -q SENTINEL "$L2/hooks/shared/command_policy.py" || f="$f [consumer edit overwritten]"
[ -z "$f" ] && ok "n1-base-present-unchanged (existing base => synthesis is a no-op; delivery and preservation unchanged)" \
            || bad n1-base-present-unchanged "rc=$RC2$f"

###############################################################################
# K9 GUARD (N2) — a forked/unreleased VERSION must NOT abort while files still arrive
###############################################################################
D3="$BASE_TMP/d3"; L3="$(make_case "$D3" 9.9.9-fork 0 1 1 0)"; LOG3="$D3/up.log"
RC3="$(run_upgrade "$L3" "$LOG3")"
f=""
[ "$RC3" = "0" ] || f="$f [expected rc 0 (proceeds), got $RC3 — unknown-base must never abort (K9)]"
grep -q "brand_new.py" "$LOG3" || [ -f "$L3/hooks/shared/brand_new.py" ] \
  || f="$f [the new upstream file was not delivered, so this row proves nothing about proceeding]"
[ "$(tr -d '\n\r' < "$L3/VERSION")" = "4.7.0" ] || f="$f [VERSION did not advance though files WERE delivered]"
grep -q "DELIVERED NOTHING" "$LOG3" && f="$f [the refusal fired on a run that DID deliver files]"
[ -z "$f" ] && ok "n2-forked-still-proceeds (unresolvable tag + files delivered => proceeds, VERSION advances, no abort — K9 honoured, refusal keys on outcome not cause)" \
            || bad n2-forked-still-proceeds "rc=$RC3$f"

###############################################################################
# NEW RULE (N3) — delivered nothing => exit 4, VERSION untouched, recovery named
###############################################################################
D4="$BASE_TMP/d4"; L4="$(make_case "$D4" 9.9.9-fork 0 1 0 0)"; LOG4="$D4/up.log"
# nothing for upstream to add, and no base to classify against => all unknown-base, 0 applied
V4_BEFORE="$(tr -d '\n\r' < "$L4/VERSION")"
RC4="$(run_upgrade "$L4" "$LOG4")"
V4_AFTER="$(tr -d '\n\r' < "$L4/VERSION")"
f=""
[ "$RC4" = "4" ] || f="$f [expected exit 4, got $RC4 — 'delivered nothing' must be distinguishable from success (0) and from a changed-by-both conflict (3)]"
[ "$V4_AFTER" = "$V4_BEFORE" ] || f="$f [VERSION advanced to $V4_AFTER on a run that delivered nothing — the N5 defect]"
grep -q "DELIVERED NOTHING" "$LOG4" || f="$f [no refusal message]"
grep -q "release-fingerprints.md" "$LOG4" || f="$f [recovery does not name release-fingerprints.md]"
grep -q "bootstrap-upgrade.sh" "$LOG4" || f="$f [recovery does not name bootstrap-upgrade.sh]"
grep -q "unknown-base" "$LOG4" || f="$f [precondition not reproduced: no unknown-base paths]"
[ -z "$f" ] && ok "n3-refuses-and-says-so (0 refreshed + unknown-base + VERSION would change => exit 4, VERSION intact, recovery names both the tag source and the engine that can seed it)" \
            || bad n3-refuses-and-says-so "rc=$RC4$f"

###############################################################################
# N3 — the DRY RUN must surface the same condition (AC5)
###############################################################################
D5="$BASE_TMP/d5"; L5="$(make_case "$D5" 9.9.9-fork 0 1 0 0)"; LOG5="$D5/up.log"
RC5="$(run_upgrade "$L5" "$LOG5" --dry-run)"
f=""
[ "$RC5" = "4" ] || f="$f [dry run exited $RC5 — the consumer's complaint was that the dry run showed no conflicts]"
grep -q "DELIVERED NOTHING" "$LOG5" || f="$f [dry run did not surface the refusal]"
grep -q "a real run would REFUSE" "$LOG5" || f="$f [dry run did not say what a real run would do]"
[ -f "$L5/audit/managed-content-manifest.json" ] && f="$f [dry run WROTE a base manifest — it must not write]"
[ -z "$f" ] && ok "n3-dry-run-surfaces-it (the preview refuses too, and still writes nothing)" \
            || bad n3-dry-run-surfaces-it "rc=$RC5$f"

###############################################################################
# ANTI-FALSE-POSITIVE — the third clause earns its place
###############################################################################
D6="$BASE_TMP/d6"; L6="$(make_case "$D6" 4.7.0 1 1 0)"; LOG6="$D6/up.log"
# already at 4.7.0 with a base: nothing to refresh, no VERSION change, no unknown-base
RC6="$(run_upgrade "$L6" "$LOG6")"
f=""
[ "$RC6" = "0" ] || f="$f [a current tree exited $RC6 — refusing here would block every no-op upgrade]"
grep -q "DELIVERED NOTHING" "$LOG6" && f="$f [the refusal fired on a tree that simply had nothing to do]"
[ -z "$f" ] && ok "n3-current-tree-quiet (nothing to do != couldn't tell what to do; the unknown-base clause is what separates them)" \
            || bad n3-current-tree-quiet "rc=$RC6$f"

finish
