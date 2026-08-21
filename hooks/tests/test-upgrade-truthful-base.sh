#!/usr/bin/env bash
# Fusebase Flow — N6: the base must not record entries the run did not earn.
# Spec: docs/specs/half-apply-self-seals/spec.md · decision N6-D1 (LOCKED).
#
# THE DEFECT, reproduced live against the v4.12.0 engine before this test existed:
# a consumer with no base upgrades; differing pre-existing paths classify `unknown-base`
# and are PRESERVED; the run then copies upstream's manifest wholesale as the new base.
# The base therefore records UPSTREAM's bytes for paths the engine just admitted it could
# not classify. One release later:
#
#   run 1  rc 0 · applied 2 · preserved 9 · VERSION 9.9.9-fork -> 4.11.0 · base written
#          hooks/local/control.sh          base==upstream:True  base==local:False
#   run 2  consumer-only (1)   hooks/shared/command_policy.py    <- misattributed
#          changed-by-both (1) hooks/local/control.sh            <- NEVER touched by the
#                                                                   consumer; aborts rc 3
#
# WHY NOT A REFUSAL (N6-D1 § "Why not the refusal the spec originally proposed"): keying on
# "no trustworthy base" is keying on CAUSE, which is N3's rejected alternative verbatim
# ("strands the forked consumer who still received files"). This ticket keys on OUTCOME:
# what the run actually delivered decides what the base may claim.
#
# TRIPWIRE — `n5-delivery n2-forked-still-proceeds` must stay GREEN AND UNCHANGED. It asserts
# rc 0 + VERSION advanced + no refusal on this EXACT fixture shape. If N6 work ever needs that
# row inverted, the fix has stopped being reversal-free and N2/N3 are back in play: STOP.
#
# ROW CLASSES:
#   DISCRIMINATOR  n6-base-omits-unclassified    — preserved-unclassified paths are absent
#   PAYOFF         n6-no-freeze-next-release     — the next release does not misattribute/abort
#   DEGRADATION    n6-degrades-to-honest-refusal — with nothing to deliver: N3's rc 4, not rc 3
#   CONTROL        n6-classified-base-complete   — a run that COULD classify prunes nothing
#   INTEGRITY      n6-pruned-base-still-verifies — pruning must not yield a BROKEN manifest
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: n6-truthful-base <name>" / "FAIL: n6-truthful-base <name>"; exit = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: n6-truthful-base $1"; }
bad() { fail=$((fail + 1)); local w="${2:-}"; [ -z "$w" ] || w=" ($(printf '%s' "$w" | tr '\n\r\t' '   ' | cut -c1-400))"; echo "FAIL: n6-truthful-base $1$w"; }
skip(){ pass=$((pass + 1)); echo "PASS: n6-truthful-base $1 [SKIP — $2]"; }
finish() { echo "[test-upgrade-truthful-base] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v git >/dev/null 2>&1 || { skip setup "no git"; finish; }
command -v python3 >/dev/null 2>&1 || { skip setup "no python3"; finish; }

BASE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-n6.XXXXXX" 2>/dev/null)"
[ -n "$BASE_TMP" ] || { bad setup "no temp dir"; finish; }
cleanup() { rm -rf "$BASE_TMP" 2>/dev/null; }
trap cleanup EXIT

LIBS="materialize-managed-source.sh backup-hygiene.sh synthesize-base.sh upgrade-delivery-guard.sh truthful-base.sh"
BASE_REL="audit/managed-content-manifest.json"

# base_has <local-dir> <path> -> rc 0 when the base manifest lists <path>
base_has() {
  python3 - "$1/$BASE_REL" "$2" <<'PY'
import json, sys
try:
    doc = json.load(open(sys.argv[1], encoding="utf-8"))
except OSError:
    sys.exit(2)
sys.exit(0 if any(a["path"] == sys.argv[2] for a in doc["assets"]) else 1)
PY
}

# make_consumer <dir> <version> <with-base:0|1>
#   Consumer tree: one file upstream WILL change (control.sh), one the consumer edited
#   (command_policy.py, SENTINEL), one identical to upstream (wf.md).
make_consumer() {
  local D="$1" cver="$2" withbase="$3" L
  L="$D/local"
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
  [ "$withbase" = "1" ] && ( cd "$L" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null 2>&1 )
  # the consumer's own edit, made AFTER any base was recorded
  printf 'validator v1\n# SENTINEL local hardening\n' > "$L/hooks/shared/command_policy.py"
  echo "$L"
}

# publish <local-dir> <version> <control-content> <new-paths|-> <tag:0|1> [tag-version]
#   <new-paths> is a space-separated list of repo-relative paths upstream ADDS this release.
#   Builds/advances the staging clone the consumer upgrades from. tag=0 models the FORKED or
#   unreleased VERSION: the source repo carries no tag matching the consumer's VERSION, so no
#   base can be reconstructed — the population N2 protects and the one N6 poisons.
publish() {
  local L="$1" v="$2" ctl="$3" extra="$4" tag="$5" tagver="${6:-}" U="$1/.fusebase-flow-source"
  mkdir -p "$U/hooks/shared" "$U/hooks/local/lib" "$U/workflows"
  if [ ! -d "$U/.git" ]; then
    ( cd "$U" && git init -q && git config user.email t@t.t && git config user.name t \
        && git config core.autocrlf false && git checkout -q -b main 2>/dev/null || true )
  fi
  echo "$v" > "$U/VERSION"
  printf 'validator v1\n' > "$U/hooks/shared/command_policy.py"   # upstream never changed it
  printf '%s\n' "$ctl"    > "$U/hooks/local/control.sh"
  printf 'wf v1\n'        > "$U/workflows/wf.md"
  if [ "$extra" != "-" ]; then
    for e in $extra; do mkdir -p "$U/$(dirname "$e")"; printf 'new upstream file\n' > "$U/$e"; done
  fi
  cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$U/hooks/local/lib/"
  cp "$ROOT/hooks/local/upgrade.sh" "$U/hooks/local/"
  for f in $LIBS; do [ -f "$ROOT/hooks/local/lib/$f" ] && cp "$ROOT/hooks/local/lib/$f" "$U/hooks/local/lib/"; done
  ( cd "$U" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null 2>&1 )
  # TRIPWIRE: the engine materializes managed content from GIT OBJECTS at the resolved ref, never
  # from the source worktree (decision M1). An uncommitted release is invisible to the run and
  # would look exactly like the defect under test — a false RED.
  ( cd "$U" && git add -A >/dev/null 2>&1 && git commit -qm "$v" >/dev/null 2>&1 )
  [ "$tag" = "1" ] && ( cd "$U" && git tag -a "v$tagver" -m "v$tagver" >/dev/null 2>&1 )
  return 0
}

run_upgrade() {   # run_upgrade <local-dir> <log> [extra-args...]
  local L="$1" log="$2"; shift 2
  ( cd "$L" && bash hooks/local/upgrade.sh --auto-yes "$@" ) > "$log" 2>&1
  echo $?
}

###############################################################################
# DISCRIMINATOR — the base must not claim paths the run could not classify
###############################################################################
D1="$BASE_TMP/d1"; L1="$(make_consumer "$D1" 9.9.9-fork 0)"; LOG1="$D1/up.log"
publish "$L1" 4.11.0 "control v2" hooks/shared/brand_new.py 0
RC1="$(run_upgrade "$L1" "$LOG1")"
f=""
[ "$RC1" = "0" ] || f="$f [expected rc 0 — N6-D1 must not turn this into a refusal (that is T1-A, which N3 rejected); got $RC1]"
[ "$(tr -d '\n\r' < "$L1/VERSION")" = "4.11.0" ] || f="$f [VERSION did not advance — the forked consumer must still proceed (N2)]"
[ -f "$L1/hooks/shared/brand_new.py" ] || f="$f [upstream-added file not delivered, so this row proves nothing about proceeding]"
grep -q SENTINEL "$L1/hooks/shared/command_policy.py" || f="$f [the consumer's own edit was OVERWRITTEN]"
grep -q "unknown-base" "$LOG1" || f="$f [precondition not reproduced: no unknown-base paths]"
[ -f "$L1/$BASE_REL" ] || f="$f [no base written at all — N6-D1 prunes entries, it does not suppress the base]"
base_has "$L1" "hooks/local/control.sh" \
  && f="$f [base RECORDS hooks/local/control.sh — a path this run PRESERVED as unknown-base; that is the N6 poison]"
base_has "$L1" "hooks/shared/command_policy.py" \
  && f="$f [base RECORDS hooks/shared/command_policy.py — preserved as unknown-base; the next run will call it consumer-only]"
base_has "$L1" "hooks/shared/brand_new.py" \
  || f="$f [base OMITS hooks/shared/brand_new.py, which this run DID deliver — pruning overreached]"
base_has "$L1" "workflows/wf.md" \
  || f="$f [base OMITS workflows/wf.md, which was already current — pruning overreached]"
[ -z "$f" ] && ok "n6-base-omits-unclassified (no base + unresolvable tag => run proceeds and delivers, but the base omits every path preserved as unknown-base and keeps every path it earned)" \
            || bad n6-base-omits-unclassified "rc=$RC1$f"

###############################################################################
# PAYOFF — the next release must not misattribute or freeze
###############################################################################
# TRIPWIRE — release 2 must SHIP something (workflows/wf2.md). With nothing to deliver the
# run legitimately lands on N3's refusal (rc 4) and this row would stop measuring the freeze;
# the `n6-degrades-to-honest-refusal` row below covers that shape deliberately.
#
# TRIPWIRE — grep the REPORT GROUP HEADER ("^  consumer-only (" / "^  changed-by-both ("),
# never the bare class name: ff_n5_report's own prose says "that is 'changed-by-both', exit 3",
# so a loose grep matches the honest refusal and reports a FALSE RED. It did exactly that here.
publish "$L1" 4.12.0 "control v3" "hooks/shared/brand_new.py workflows/wf2.md" 0
LOG1B="$D1/up2.log"
RC1B="$(run_upgrade "$L1" "$LOG1B")"
f=""
[ "$RC1B" = "0" ] || f="$f [expected rc 0 on a release that DID deliver, got $RC1B]"
[ "$RC1B" = "3" ] && f="$f [ABORTED rc 3 — the tree froze; this is exactly the N6 outcome]"
grep -qE "^  changed-by-both \(" "$LOG1B" && f="$f [a path the consumer never touched is reported changed-by-both]"
grep -qE "^  consumer-only \(" "$LOG1B" \
  && f="$f [the run blames the consumer for a path it preserved itself last time — 'YOU changed these' is the misattribution N6 is about]"
grep -qE "^  unknown-base \(" "$LOG1B" \
  || f="$f [the preserved paths are no longer reported as unknown-base — they must stay VISIBLE every run; that is what makes a missing entry recoverable]"
grep -q SENTINEL "$L1/hooks/shared/command_policy.py" || f="$f [the consumer's edit was overwritten on the second run]"
[ "$(tr -d '\n\r' < "$L1/VERSION")" = "4.12.0" ] || f="$f [VERSION did not advance on a release that delivered]"
[ -z "$f" ] && ok "n6-no-freeze-next-release (second release across the same tree: rc 0, VERSION advances, still reported unknown-base — no consumer-only misattribution, no changed-by-both, no abort; the seal does not form)" \
            || bad n6-no-freeze-next-release "rc=$RC1B$f"

###############################################################################
# DEGRADATION — with nothing to deliver, the freeze becomes N3's HONEST REFUSAL
###############################################################################
D3="$BASE_TMP/d3"; L3="$(make_consumer "$D3" 9.9.9-fork 0)"; LOG3="$D3/up.log"
publish "$L3" 4.11.0 "control v2" hooks/shared/brand_new.py 0
RC3="$(run_upgrade "$L3" "$LOG3")"
publish "$L3" 4.12.0 "control v3" hooks/shared/brand_new.py 0
LOG3B="$D3/up2.log"
V3_BEFORE="$(tr -d '\n\r' < "$L3/VERSION")"
RC3B="$(run_upgrade "$L3" "$LOG3B")"
f=""
[ "$RC3" = "0" ] || f="$f [first run did not proceed (rc $RC3) — precondition broken]"
[ "$RC3B" = "3" ] && f="$f [rc 3: still the changed-by-both FREEZE — the seal formed anyway]"
[ "$RC3B" = "4" ] || f="$f [expected N3's refusal (rc 4) on a release that delivered nothing, got $RC3B]"
grep -q "DELIVERED NOTHING" "$LOG3B" || f="$f [no refusal message]"
grep -qE "^  consumer-only \(" "$LOG3B" && f="$f [misattributed as consumer-only]"
[ "$(tr -d '\n\r' < "$L3/VERSION")" = "$V3_BEFORE" ] || f="$f [VERSION advanced on a run that delivered nothing]"
grep -q "release-fingerprints.md" "$LOG3B" || f="$f [recovery does not name release-fingerprints.md]"
[ -z "$f" ] && ok "n6-degrades-to-honest-refusal (nothing left to deliver => N3's exit 4 with runnable recovery, NOT the exit-3 freeze; 'no base could be reconstructed' replaces 'YOU changed these')" \
            || bad n6-degrades-to-honest-refusal "rc1=$RC3 rc2=$RC3B$f"

###############################################################################
# CONTROL — a run that COULD classify must write a COMPLETE base
###############################################################################
D2="$BASE_TMP/d2"; L2="$(make_consumer "$D2" 4.10.0 1)"; LOG2="$D2/up.log"
publish "$L2" 4.11.0 "control v2" hooks/shared/brand_new.py 1 4.10.0
RC2="$(run_upgrade "$L2" "$LOG2")"
f=""
[ "$RC2" = "0" ] || f="$f [expected rc 0, got $RC2]"
grep -qE "consumer-only" "$LOG2" || f="$f [precondition not reproduced: the consumer edit should classify consumer-only against a real base]"
grep -q "unknown-base" "$LOG2" && f="$f [precondition broken: nothing should be unknown-base when a base exists]"
for p in hooks/local/control.sh hooks/shared/command_policy.py workflows/wf.md hooks/shared/brand_new.py; do
  base_has "$L2" "$p" || f="$f [base OMITS $p on a run that classified every path — pruning must be a NO-OP here; a consumer-only path is EARNED (upstream did not change it) and must stay recorded]"
done
[ -z "$f" ] && ok "n6-classified-base-complete (base present => zero unknown-base => the new base is complete, incl. the consumer-only path; pruning never fires on a run that could tell)" \
            || bad n6-classified-base-complete "rc=$RC2$f"

###############################################################################
# INTEGRITY — a pruned base must still be a VALID manifest, not a BROKEN one
###############################################################################
f=""
V1="$( cd "$L1" && python3 hooks/local/lib/managed_content_manifest.py verify --root . 2>&1 )"
case "$V1" in
  *BROKEN*) f="$f [verify reports BROKEN after pruning — asset_count/manifest_self_sha256 were not recomputed; this would make every downstream integrity check useless]" ;;
  *ABSENT*) f="$f [verify reports ABSENT — the base was suppressed rather than pruned]" ;;
esac
# N6-D1 states the consequence explicitly: those paths become `extra`, not `modified`. Assert the
# STATED consequence so a drift away from it is a test failure, not a surprise in the field.
printf '%s' "$V1" | grep -q "extra: hooks/local/control.sh" \
  || f="$f [expected the pruned path to report as 'extra' (N6-D1 stated consequence); got: $(printf '%s' "$V1" | tr '\n' ' ')]"
printf '%s' "$V1" | grep -q "modified: hooks/local/control.sh" \
  && f="$f [pruned path still reports 'modified' — it is still listed, so it was not pruned]"
[ -z "$f" ] && ok "n6-pruned-base-still-verifies (pruned manifest re-hashes cleanly: verdict is DRIFT with the omitted paths reported 'extra', never BROKEN and never ABSENT)" \
            || bad n6-pruned-base-still-verifies "$f"

finish
