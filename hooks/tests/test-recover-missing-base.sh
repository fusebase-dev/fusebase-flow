#!/usr/bin/env bash
# Fusebase Flow — N6 recovery: establish the last truthful version BEFORE rebuilding anything.
# Spec: docs/specs/half-apply-self-seals/spec.md · decision N6-D2 § Consequence (recovery scope).
#
# WHY THE ORDERING IS THE WHOLE PROCEDURE: every shortcut that skips it reconstructs the same
# wrong base. `synthesize-base.sh:57-75` keys synthesis off `v$(cat VERSION)`, and the bad run
# already ADVANCED VERSION (upgrade.sh:674-681). So on a poisoned tree, deleting the base and
# re-synthesising rebuilds upstream's CURRENT content as the "historical" base — the poison,
# again. Restoring the last truthful VERSION first is what makes the existing, proven
# machinery correct instead of self-defeating.
#
# WHAT THIS CAN RECOVER, and what it must refuse:
#   RECOVERABLE   the tree still carries external ground truth — VERSION.pre-upgrade-<TS>
#                 (or base_provenance.prior_version) AND a source clone carrying that tag.
#   NOT           anything else. There is no local signal that identifies the prior release
#                 (N6-D2), so a tree without those inputs cannot be repaired automatically.
#                 Say so; do NOT guess a baseline. A wrong baseline misclassifies every path
#                 it disagrees with — the same damage, applied deliberately.
#   AMBIGUOUS     more than one distinct pre-upgrade VERSION => more than one run may have
#                 been bad. Refuse and make the operator name it; picking one is a guess.
#
# ROW CLASSES:
#   DRY-RUN        n6r-dry-run-writes-nothing     — default mode changes not one byte
#   ORDERING       n6r-version-restored-first     — VERSION precedes any base rebuild
#   PAYOFF         n6r-recovered-tree-upgrades    — the ordinary upgrade works again after
#   REFUSAL        n6r-refuses-without-truth      — no prior version => refuse, name why
#   REFUSAL        n6r-refuses-without-tag        — no tag in the clone => refuse, name why
#   REFUSAL        n6r-refuses-when-ambiguous     — two candidate versions => refuse, list them
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: n6-recover <name>" / "FAIL: n6-recover <name>"; exit = failure count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: n6-recover $1"; }
bad() { fail=$((fail + 1)); local w="${2:-}"; [ -z "$w" ] || w=" ($(printf '%s' "$w" | tr '\n\r\t' '   ' | cut -c1-400))"; echo "FAIL: n6-recover $1$w"; }
skip(){ pass=$((pass + 1)); echo "PASS: n6-recover $1 [SKIP — $2]"; }
finish() { echo "[test-recover-missing-base] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v git >/dev/null 2>&1 || { skip setup "no git"; finish; }
command -v python3 >/dev/null 2>&1 || { skip setup "no python3"; finish; }

TOOL="hooks/local/recover-missing-base.sh"
BASE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ffhc-n6rec.XXXXXX" 2>/dev/null)"
[ -n "$BASE_TMP" ] || { bad setup "no temp dir"; finish; }
cleanup() { rm -rf "$BASE_TMP" 2>/dev/null; }
trap cleanup EXIT

LIBS="materialize-managed-source.sh backup-hygiene.sh synthesize-base.sh upgrade-delivery-guard.sh truthful-base.sh"
BASE_REL="audit/managed-content-manifest.json"

# poisoned <dir> [with-version-backup:0|1] [with-tag:0|1] [extra-version-backup]
#   Builds a tree in the state a PRE-N6 engine leaves behind: VERSION advanced to 4.11.0, a
#   base that is upstream's 4.11.0 manifest, and local paths still holding 4.9.2 content.
poisoned() {
  local D="$1" vbak="${2:-1}" tag="${3:-1}" extra="${4:-}" L U
  L="$D/local"; U="$L/.fusebase-flow-source"
  mkdir -p "$L/hooks/local/lib" "$L/workflows" "$L/audit"
  ( cd "$L" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config core.autocrlf false )
  cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$L/hooks/local/lib/"
  for f in $LIBS; do [ -f "$ROOT/hooks/local/lib/$f" ] && cp "$ROOT/hooks/local/lib/$f" "$L/hooks/local/lib/"; done
  cp "$ROOT/hooks/local/upgrade.sh" "$L/hooks/local/"
  cp "$ROOT/hooks/local/recover-missing-base.sh" "$L/hooks/local/" 2>/dev/null || true

  # --- the source clone, carrying v4.9.2 and then 4.11.0 -----------------------------
  mkdir -p "$U/hooks/local/lib" "$U/workflows"
  cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$U/hooks/local/lib/"
  for f in $LIBS; do [ -f "$ROOT/hooks/local/lib/$f" ] && cp "$ROOT/hooks/local/lib/$f" "$U/hooks/local/lib/"; done
  cp "$ROOT/hooks/local/upgrade.sh" "$U/hooks/local/"
  ( cd "$U" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config core.autocrlf false && git checkout -q -b main 2>/dev/null || true )
  echo "4.9.2" > "$U/VERSION"; printf 'control v1\n' > "$U/hooks/local/control.sh"
  printf 'wf v1\n' > "$U/workflows/wf.md"
  ( cd "$U" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null 2>&1 )
  ( cd "$U" && git add -A >/dev/null 2>&1 && git commit -qm 4.9.2 >/dev/null 2>&1 )
  [ "$tag" = "1" ] && ( cd "$U" && git tag -a v4.9.2 -m v4.9.2 >/dev/null 2>&1 )
  echo "4.11.0" > "$U/VERSION"; printf 'control v2\n' > "$U/hooks/local/control.sh"
  ( cd "$U" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null 2>&1 )
  ( cd "$U" && git add -A >/dev/null 2>&1 && git commit -qm 4.11.0 >/dev/null 2>&1 )

  # --- the poisoned consumer: 4.9.2 CONTENT, 4.11.0 VERSION, 4.11.0 BASE -------------
  printf 'control v1\n' > "$L/hooks/local/control.sh"     # never refreshed (was unknown-base)
  printf 'wf v1\n'      > "$L/workflows/wf.md"
  echo "4.11.0" > "$L/VERSION"
  cp "$U/$BASE_REL" "$L/$BASE_REL"                        # upstream's 4.11.0 manifest
  [ "$vbak" = "1" ] && echo "4.9.2" > "$L/VERSION.pre-upgrade-20260820T000000Z"
  [ -n "$extra" ] && echo "$extra" > "$L/VERSION.pre-upgrade-20260819T000000Z"
  echo "$L"
}

# snap: hash the CONSUMER TREE — managed content, VERSION, the base, backups. Git metadata and
# the transient staging clone are deliberately out of scope: resolving the tag legitimately
# writes .fusebase-flow-source/.git/FETCH_HEAD (synthesize-base.sh does the same fetch), and
# that is the clone's bookkeeping, not the consumer's tree. Measured: on the no-tag refusal
# that FETCH_HEAD is the ONLY difference — VERSION, the base and every managed path are
# untouched, which is the property these rows exist to pin.
snap() { ( cd "$1" && find . \( -name .git -o -name .fusebase-flow-source \) -prune -o -type f -print | sort | xargs sha256sum 2>/dev/null | sha256sum ); }
run_tool() { local L="$1"; shift; ( cd "$L" && bash hooks/local/recover-missing-base.sh "$@" ) 2>&1; }

###############################################################################
# DRY-RUN — the default must be read-only
###############################################################################
D1="$BASE_TMP/d1"; L1="$(poisoned "$D1")"
BEFORE="$(snap "$L1")"
OUT1="$(run_tool "$L1")"; RC1=$?
AFTER="$(snap "$L1")"
f=""
[ -f "$TOOL" ] || f="$f [$TOOL does not exist]"
[ "$BEFORE" = "$AFTER" ] || f="$f [the DEFAULT run mutated the tree — recovery must preview before it touches anything]"
printf '%s' "$OUT1" | grep -qiE "dry|would|preview" || f="$f [the default run does not announce itself as a preview]"
printf '%s' "$OUT1" | grep -q "4.9.2" || f="$f [the preview does not name the last truthful version it identified]"
[ -z "$f" ] && ok "n6r-dry-run-writes-nothing (default mode identifies 4.9.2 as the last truthful version and changes not one byte)" \
            || bad n6r-dry-run-writes-nothing "rc=$RC1$f"

###############################################################################
# ORDERING + PAYOFF — VERSION first, then the base; then the ordinary path works
###############################################################################
OUT2="$(run_tool "$L1" --apply)"; RC2=$?
f=""
[ "$RC2" = "0" ] || f="$f [--apply exited $RC2]"
[ "$(tr -d '\n\r' < "$L1/VERSION")" = "4.9.2" ] \
  || f="$f [VERSION is $(tr -d '\n\r' < "$L1/VERSION"), not the last truthful 4.9.2 — synthesis keys off VERSION, so rebuilding the base while it still reads 4.11.0 reconstructs the SAME poison]"
[ -f "$L1/$BASE_REL" ] || f="$f [no base was rebuilt]"
python3 - "$L1/$BASE_REL" "$L1/hooks/local/control.sh" <<'PY' || f="$f [the rebuilt base does NOT match the tree's actual 4.9.2 content — it is still upstream's 4.11.0 manifest, i.e. the poison survived]"
import json, sys, hashlib, pathlib
doc = json.load(open(sys.argv[1], encoding="utf-8"))
want = hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest()
got = {a["path"]: a["sha256"] for a in doc["assets"]}.get("hooks/local/control.sh")
sys.exit(0 if got == want else 1)
PY
[ -z "$f" ] && ok "n6r-version-restored-first (--apply restores VERSION to 4.9.2 BEFORE rebuilding, so the base it stamps describes the tree the consumer actually has)" \
            || bad n6r-version-restored-first "rc=$RC2$f"

f=""
UPLOG="$D1/up.log"
( cd "$L1" && bash hooks/local/upgrade.sh --auto-yes ) > "$UPLOG" 2>&1; RC3=$?
[ "$RC3" = "0" ] || f="$f [the ordinary upgrade still fails after recovery (rc $RC3) — the tree is not actually recovered]"
grep -qE "^  changed-by-both \(" "$UPLOG" && f="$f [still reports changed-by-both — the misattribution survived recovery]"
grep -qE "^  consumer-only \(" "$UPLOG" && f="$f [still blames the consumer for a path they never touched]"
grep -q "control v2" "$L1/hooks/local/control.sh" \
  || f="$f [the upstream change STILL was not delivered — recovery restored classification but the file never refreshed]"
[ -z "$f" ] && ok "n6r-recovered-tree-upgrades (after recovery the ordinary upgrade runs clean and finally delivers the change the poisoned tree had frozen)" \
            || bad n6r-recovered-tree-upgrades "rc=$RC3$f"

###############################################################################
# REFUSALS — no ground truth, no repair. Never a guess.
###############################################################################
D2="$BASE_TMP/d2"; L2="$(poisoned "$D2" 0 1)"
BEFORE="$(snap "$L2")"; OUT4="$(run_tool "$L2" --apply)"; RC4=$?; AFTER="$(snap "$L2")"
f=""
[ "$RC4" = "0" ] && f="$f [it exited 0 with no way to know the prior version — that means it GUESSED a baseline]"
[ "$BEFORE" = "$AFTER" ] || f="$f [it modified the tree despite having no ground truth]"
printf '%s' "$OUT4" | grep -qiE "cannot|refus" || f="$f [it does not say plainly that this tree cannot be repaired automatically]"
printf '%s' "$OUT4" | grep -q "release-fingerprints.md" \
  || f="$f [it does not point at docs/release-fingerprints.md, the only way an operator can identify the release by hand]"
[ -z "$f" ] && ok "n6r-refuses-without-truth (no VERSION.pre-upgrade-* and no base_provenance => refuses, changes nothing, and names the manual route)" \
            || bad n6r-refuses-without-truth "rc=$RC4$f"

D3="$BASE_TMP/d3"; L3="$(poisoned "$D3" 1 0)"
BEFORE="$(snap "$L3")"; OUT5="$(run_tool "$L3" --apply)"; RC5=$?; AFTER="$(snap "$L3")"
f=""
[ "$RC5" = "0" ] && f="$f [it exited 0 without a tag to reconstruct from — the base it wrote cannot be a reconstruction of fact]"
[ "$BEFORE" = "$AFTER" ] || f="$f [it modified the tree with no tag available]"
printf '%s' "$OUT5" | grep -qE "v4\.9\.2" || f="$f [it does not name the tag it needs]"
[ -z "$f" ] && ok "n6r-refuses-without-tag (prior version known but the clone carries no matching tag => refuses and names the tag required)" \
            || bad n6r-refuses-without-tag "rc=$RC5$f"

D4="$BASE_TMP/d4"; L4="$(poisoned "$D4" 1 1 4.7.1)"
BEFORE="$(snap "$L4")"; OUT6="$(run_tool "$L4" --apply)"; RC6=$?; AFTER="$(snap "$L4")"
f=""
[ "$RC6" = "0" ] && f="$f [two distinct candidate versions and it picked one anyway — that is a guess, and a wrong baseline misclassifies every path it disagrees with]"
[ "$BEFORE" = "$AFTER" ] || f="$f [it modified the tree while the prior version was ambiguous]"
printf '%s' "$OUT6" | grep -q "4.9.2" && printf '%s' "$OUT6" | grep -q "4.7.1" \
  || f="$f [it does not list BOTH candidates, so the operator cannot resolve it]"
printf '%s' "$OUT6" | grep -q -- "--prior-version" || f="$f [it does not name the flag that lets the operator resolve the ambiguity]"
[ -z "$f" ] && ok "n6r-refuses-when-ambiguous (two pre-upgrade VERSIONs => refuses, lists both, and names --prior-version so the operator decides)" \
            || bad n6r-refuses-when-ambiguous "rc=$RC6$f"

finish
