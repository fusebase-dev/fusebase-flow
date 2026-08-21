#!/usr/bin/env bash
# Fusebase Flow — N6: detect the state you CAN identify; point, never guess, at the one you cannot.
# Spec: docs/specs/half-apply-self-seals/spec.md · decision N6-D2 (LOCKED).
#
# WHY A POINTER AND NOT A VERDICT (N6-D2, measured): a poisoned tree and a healthy tree with a
# genuine consumer edit produce an IDENTICAL local signature — base present, self-hash valid,
# `verify` DRIFT/`modified`, base byte-identical to a published upstream manifest, rc 0,
# VERSION advanced, same backup artifacts. Every candidate discriminator failed:
#
#   fingerprint-row match     non-discriminating BY DESIGN — K13b installs the source tree's
#                             manifest as the new base after EVERY successful upgrade
#   VERSION vs content        true of both; that is what `consumer-only` means
#   backup artifacts          identical sets; audit/managed-content-manifest.json gets no
#                             backup twin at all (upgrade.sh twins top-level files only, and
#                             audit/ is not in list-managed --dirs)
#
# The distinguishing fact is HISTORY — did a base exist before the run that wrote this one —
# and nothing in the tree records it. So: State 1 (base ABSENT) is detected positively and
# routed; State 2 gets a conditional pointer that moves NO verdict; and the engine starts
# RECORDING the fact so the question is answerable from the next upgrade onward.
#
# DELIVERY LIMIT, asserted here so it cannot be quietly dropped: the health-check script is
# itself among the frozen files, so this check cannot reach installs already affected. It
# protects the not-yet-exposed. The already-affected are reached out-of-band by the advisory.
#
# ROW CLASSES:
#   DISCRIMINATOR  n6-state1-detected-and-routed  — base absent => named, routed to bootstrap
#   HONESTY        n6-state1-states-delivery-limit— the output does not overclaim its reach
#   NON-VERDICT    n6-state2-pointer-is-conditional — State 2 pointer never asserts poisoning
#   COUNTERFACTUAL n6-state2-moves-no-verdict     — same buckets with and without the lib
#   READ-ONLY      n6-health-never-repairs        — the check writes nothing, ever
#   FORWARD-ONLY   n6-provenance-recorded         — the base records what the run knew
#   ADDITIVE       n6-provenance-breaks-nothing   — verify still parses; self-hash intact
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: n6-missing-base <name>" / "FAIL: n6-missing-base <name>"; exit = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: n6-missing-base $1"; }
bad() { fail=$((fail + 1)); local w="${2:-}"; [ -z "$w" ] || w=" ($(printf '%s' "$w" | tr '\n\r\t' '   ' | cut -c1-400))"; echo "FAIL: n6-missing-base $1$w"; }
skip(){ pass=$((pass + 1)); echo "PASS: n6-missing-base $1 [SKIP — $2]"; }
finish() { echo "[test-missing-base-detection] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { skip setup "no python3"; finish; }

LIB="hooks/local/lib/missing-base-check.sh"
BASE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-n6mb.XXXXXX" 2>/dev/null)"
[ -n "$BASE_TMP" ] || { bad setup "no temp dir"; finish; }
cleanup() { rm -rf "$BASE_TMP" 2>/dev/null; }
trap cleanup EXIT

BASE_REL="audit/managed-content-manifest.json"

# tree <dir> <with-base:0|1> [drift:0|1] -> a minimal managed tree
tree_at() {
  local D="$1" withbase="$2" drift="${3:-0}"
  mkdir -p "$D/hooks/local/lib" "$D/workflows" "$D/audit"
  echo "4.11.0" > "$D/VERSION"
  printf 'control v1\n' > "$D/hooks/local/control.sh"
  printf 'wf v1\n'      > "$D/workflows/wf.md"
  cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$D/hooks/local/lib/"
  if [ "$withbase" = "1" ]; then
    ( cd "$D" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null 2>&1 )
    [ "$drift" = "1" ] && printf 'control v1\n# local edit\n' > "$D/hooks/local/control.sh"
  fi
  return 0
}

# findings <dir> -> the lib's output for that tree (empty when the lib is absent)
findings() {
  ( cd "$1" && FFMB_MCM="hooks/local/lib/managed_content_manifest.py" \
      bash -c '. "$0"/'"$LIB"' 2>/dev/null && ffmb_findings' "$ROOT" 2>/dev/null )
}

###############################################################################
# DISCRIMINATOR + HONESTY — State 1 is the one that can be known for certain
###############################################################################
T1D="$BASE_TMP/state1"; tree_at "$T1D" 0
OUT1="$(findings "$T1D")"
f=""
[ -n "$OUT1" ] || f="$f [no finding at all on a tree with NO base manifest — this is the one state that IS positively detectable (verify => ABSENT)]"
printf '%s' "$OUT1" | grep -q "bootstrap-upgrade.sh" \
  || f="$f [the finding does not route to bootstrap-upgrade.sh, which is the engine that reconstructs the base from the installed VERSION's tag]"
printf '%s' "$OUT1" | grep -qiE "do not|never" \
  || f="$f [no warning against the two moves the advisory forbids (re-running upgrade blind / stamping a base from the current tree, K13b)]"
[ -z "$f" ] && ok "n6-state1-detected-and-routed (base absent => named as the pre-exposure state and routed to bootstrap-upgrade.sh, with the forbidden moves called out)" \
            || bad n6-state1-detected-and-routed "$f"

f=""
printf '%s' "$OUT1" | grep -qiE "already|cannot reach|out-of-band|advisory" \
  || f="$f [the output does not state that this check cannot reach installs already affected — it is itself among the frozen files; claiming coverage it does not have is the failure N6-D2 forbids]"
[ -z "$f" ] && ok "n6-state1-states-delivery-limit (the check says plainly that it protects the not-yet-exposed and that already-affected installs are reached out-of-band)" \
            || bad n6-state1-states-delivery-limit "$f"

###############################################################################
# NON-VERDICT — State 2 may point, never accuse
###############################################################################
T2D="$BASE_TMP/state2"; tree_at "$T2D" 1 1
OUT2="$(findings "$T2D")"
f=""
[ -n "$OUT2" ] || f="$f [no pointer at all on base-present + DRIFT — the operator gets nothing to check]"
printf '%s' "$OUT2" | grep -qiE "^POINTER|if your|if the last|conditional" \
  || f="$f [the State-2 line is not marked conditional; N6-D2 forbids a verdict here because a healthy edited tree has an IDENTICAL signature]"
printf '%s' "$OUT2" | grep -qiE "poisoned|corrupt(ed)? tree|you are affected|detected a half-appl" \
  && f="$f [the line ASSERTS poisoning — that is the guess N6-D2 forbids; a wrong verdict here sends a healthy consumer down a path that makes the tree worse]"
[ -z "$f" ] && ok "n6-state2-pointer-is-conditional (base present + DRIFT => a conditional pointer the operator can evaluate, never an assertion that the tree is poisoned)" \
            || bad n6-state2-pointer-is-conditional "$f"

###############################################################################
# COUNTERFACTUAL — the pointer must not be able to move the verdict
###############################################################################
f=""
printf '%s' "$OUT2" | grep -qE "^(DRIFT|BROKEN)" \
  && f="$f [the State-2 line is emitted in a verdict-moving class; per N6-D2 it is VISIBILITY ONLY, like the M9 approval warnings — it must be able to change neither the verdict nor the exit code]"
printf '%s' "$OUT1" | grep -qE "^(DRIFT|POINTER)" \
  || f="$f [the State-1 line carries no class prefix, so the engine cannot tell a real finding from a pointer]"
[ -z "$f" ] && ok "n6-state2-moves-no-verdict (State 1 is classed as a real finding; State 2 is classed POINTER — visibility only, the M9 pattern)" \
            || bad n6-state2-moves-no-verdict "$f"

###############################################################################
# READ-ONLY — health never repairs (spec S1; the advisory forbids blind repair)
###############################################################################
f=""
# ANTI-VACUITY (F-N5-1): without this guard the row is GREEN BECAUSE THE LIB IS ABSENT —
# a check that never runs mutates nothing. A passing assertion must not be able to mean
# "the feature does not exist".
[ -f "$LIB" ] || f="$f [$LIB does not exist, so 'it changed nothing' proves nothing]"
[ -n "$OUT1" ] || f="$f [the check produced no output on this tree, so it cannot be shown to have run at all]"
SNAP_BEFORE="$(cd "$T1D" && find . -type f | sort | xargs sha256sum 2>/dev/null | sha256sum)"
findings "$T1D" >/dev/null
SNAP_AFTER="$(cd "$T1D" && find . -type f | sort | xargs sha256sum 2>/dev/null | sha256sum)"
[ "$SNAP_BEFORE" = "$SNAP_AFTER" ] || f="$f [the check MUTATED the tree — health is read-only and must never repair]"
[ -f "$T1D/$BASE_REL" ] && f="$f [the check CREATED a base manifest — synthesizing one here keys off the local VERSION and would rebuild the same poison (synthesize-base.sh:57-75)]"
[ -z "$f" ] && ok "n6-health-never-repairs (running the check twice leaves the tree byte-identical and creates no base)" \
            || bad n6-health-never-repairs "$f"

###############################################################################
# WIRING — the engine must actually source and call it
###############################################################################
f=""
ENGINE="hooks/local/fusebase-flow-health-check.sh"
grep -q "missing-base-check.sh" "$ENGINE" || f="$f [$ENGINE does not source the lib, so none of the above reaches an operator]"
grep -q "ffmb_collect" "$ENGINE" || f="$f [$ENGINE never calls ffmb_collect, so State 1 never reaches record_drift]"
grep -q "ffmb_print_pointers" "$ENGINE"   || f="$f [$ENGINE never calls ffmb_print_pointers, so the State-2 pointer is computed and then thrown away]"
[ -z "$f" ] && ok "n6-check-is-wired (the health-check engine sources the lib and calls it)" \
            || bad n6-check-is-wired "$f"

###############################################################################
# FORWARD-ONLY — the base records what the run knew, so the next tree can be judged
###############################################################################
f=""
PROV="$BASE_TMP/prov"; mkdir -p "$PROV"
tree_at "$PROV" 1
python3 hooks/local/lib/managed_content_manifest.py prune-base \
  --manifest "$PROV/$BASE_REL" --omit-file /dev/null \
  --prior-base absent --prior-version 4.9.2 >/dev/null 2>&1 \
  || f="$f [prune-base rejected the provenance arguments]"
PROVOUT="$(python3 - "$PROV/$BASE_REL" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    print("UNPARSEABLE " + str(e)); raise SystemExit
p = d.get("base_provenance")
print("MISSING" if not isinstance(p, dict) else
      "%s|%s|%s" % (p.get("prior_base"), p.get("prior_version"), p.get("preserved_unclassified")))
PY
)"
[ "$PROVOUT" = "absent|4.9.2|0" ] \
  || f="$f [base_provenance is '$PROVOUT', expected 'absent|4.9.2|0' — without prior_base recorded, a poisoned base cannot self-identify and N6-D2's forward-only fix does not exist]"
[ -z "$f" ] && ok "n6-provenance-recorded (the base carries prior_base / prior_version / preserved_unclassified, so from the next upgrade onward a poisoned base self-identifies with certainty)" \
            || bad n6-provenance-recorded "$f"

###############################################################################
# ADDITIVE — provenance must not disturb the manifest contract
###############################################################################
f=""
# ANTI-VACUITY (F-N5-1): "provenance broke nothing" is trivially true when no provenance was
# written. Require it present before judging its effect.
grep -q "base_provenance" "$PROV/$BASE_REL" 2>/dev/null   || f="$f [no base_provenance in the manifest, so this row is measuring a manifest without the feature]"
V="$(cd "$PROV" && python3 hooks/local/lib/managed_content_manifest.py verify --root . 2>&1)"
case "$V" in
  *BROKEN*) f="$f [verify BROKEN after stamping provenance — the self-hash covers schema_version/flow_version/assets only, so an additive top-level key must be invisible to it]" ;;
  *ABSENT*) f="$f [verify ABSENT — provenance stamping destroyed the manifest]" ;;
esac
python3 -c "
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
sys.exit(0 if d.get('asset_count')==len(d['assets']) else 1)" "$PROV/$BASE_REL" \
  || f="$f [asset_count no longer matches len(assets) — check-vendored-rendered.sh treats that disagreement as CANNOT RUN]"
[ -z "$f" ] && ok "n6-provenance-breaks-nothing (verify still returns a content verdict, never BROKEN; asset_count still agrees with the asset list)" \
            || bad n6-provenance-breaks-nothing "$f"

finish
