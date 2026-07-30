#!/usr/bin/env bash
# Fusebase Flow — managed-content manifest + three-way upgrade classification tests.
# Spec: docs/specs/approval-binding-and-upgrade-classification/spec.md (AC13, AC13b, AC13c, AC15, AC16).
#
# Drives the REAL hooks/local/lib/managed_content_manifest.py and (from T12) the REAL
# hooks/local/upgrade.sh against throwaway trees.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: upgrade-classify <name>" / "FAIL: upgrade-classify <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: upgrade-classify $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: upgrade-classify $1 (${2:-})"; }
finish() { echo "[test-upgrade-conflict-classification] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: upgrade-classify skipped-no-python3"; pass=1; finish; }

# ---- 1. Manifest: byte-stable stamp, drift detection, exclusions, K14 single home ----
STAMP_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PYSTAMP' 2>&1
import json, subprocess, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks" / "local" / "lib"))
import managed_content_manifest as mcm  # noqa: E402
fails = []
MODULE = str(root / "hooks" / "local" / "lib" / "managed_content_manifest.py")

# stamp()/verify() print progress; only the JSON verdict may reach the harness.
import io  # noqa: E402
_real_stdout, sys.stdout = sys.stdout, io.StringIO()


def tree(tmp: Path, files) -> Path:
    for rel, body in files.items():
        p = tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")
    (tmp / "VERSION").write_text("4.6.1\n", encoding="utf-8")
    return tmp


BASE_FILES = {
    "hooks/shared/command_policy.py": "upstream v1\n",
    "hooks/local/upgrade.sh": "engine v1\n",
    "workflows/greenlight-deploy.md": "wf v1\n",
    "FLOW_RULES.md": "rules v1\n",
}

with tempfile.TemporaryDirectory() as d:
    t = tree(Path(d), dict(BASE_FILES))
    mcm.stamp(t)
    first = (t / mcm.MANIFEST_REL).read_bytes()
    mcm.stamp(t)
    if (t / mcm.MANIFEST_REL).read_bytes() != first:
        fails.append("stamp is not byte-stable across runs (a timestamp leaked in?)")
    doc = json.loads(first.decode("utf-8"))
    if any(a["path"] == mcm.MANIFEST_REL for a in doc["assets"]):
        fails.append("the manifest hashes ITSELF — that can never settle")
    if mcm.verify(t, False) != 0:
        fails.append("verify on a freshly stamped tree should be MATCH (rc 0)")
    (t / "hooks" / "shared" / "command_policy.py").write_text("tampered\n", encoding="utf-8")
    if mcm.verify(t, False) != 1:
        fails.append("verify should report DRIFT (rc 1) after a covered file changed")
    (t / mcm.MANIFEST_REL).write_text("{not json", encoding="utf-8")
    if mcm.verify(t, False) != 2:
        fails.append("verify should report BROKEN (rc 2) on an unparseable manifest")
    (t / mcm.MANIFEST_REL).unlink()
    if mcm.verify(t, False) != 4:
        fails.append("verify should report ABSENT (rc 4) when the manifest is missing")

# Operator overrides / build noise / backup twins are NEVER managed content.
with tempfile.TemporaryDirectory() as d:
    extra = {
        "hooks/local/upgrade.local.sh": "operator override\n",
        "hooks/shared/__pycache__/x.cpython-311.pyc": "noise\n",
        "policies/command-policy.yml.pre-upgrade-20260101T000000Z": "backup\n",
    }
    t = tree(Path(d), dict(BASE_FILES, **extra))
    paths = mcm.collect_paths(t)
    for leaked in extra:
        if leaked in paths:
            fails.append("excluded path leaked into the managed set: " + leaked)

# K14: `list-managed` IS the definition — module constants and CLI must agree exactly.
for flag, expected in (("--dirs", list(mcm.MANAGED_DIRS)), ("--files", list(mcm.MANAGED_FILES))):
    out = subprocess.run([sys.executable, MODULE, "list-managed", flag],
                         capture_output=True, text=True)
    got = [ln for ln in out.stdout.split() if ln]
    if got != expected:
        fails.append("list-managed " + flag + " disagrees with the module constants (K14)")

sys.stdout = _real_stdout
print(json.dumps(fails))
PYSTAMP
)"
if [ "$STAMP_OUT" = "[]" ]; then
  ok "manifest-byte-stable-drift-and-single-home"
else
  bad "manifest-byte-stable-drift-and-single-home" "$STAMP_OUT"
fi

# ---- 2. The FULL K9 ten-state truth table + --auto-yes containment -------------------
K9_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PYK9' 2>&1
import json, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks" / "local" / "lib"))
import managed_content_manifest as mcm  # noqa: E402
fails = []

# stamp() prints progress; only the JSON verdict may reach the harness.
import io  # noqa: E402
_real_stdout, sys.stdout = sys.stdout, io.StringIO()

# (label, base, local, upstream, expected) — None means the file is absent in that tree.
CASES = [
    ("row1-current",                "v1", "v2", "v2", "current"),
    ("row2-upstream-only",          "v1", "v1", "v2", "upstream-only"),
    ("row3-consumer-only",          "v1", "v2", "v1", "consumer-only"),
    ("row4-changed-by-both",        "v1", "v2", "v3", "changed-by-both"),
    ("row5-upstream-deleted-clean", "v1", "v1", None, "upstream-deleted-clean"),
    ("row6-upstream-deleted-dirty", "v1", "v2", None, "upstream-deleted-dirty"),
    ("row7-consumer-added",         None, "v2", None, "consumer-added"),
    ("row8-upstream-added",         None, None, "v2", "upstream-added"),
    ("row9-consumer-deleted",       "v1", None, "v1", "consumer-deleted"),
    ("row10-unknown-base",          None, "v2", "v3", "unknown-base"),
]
REL = "hooks/shared/probe.py"

for label, b, loc, up, expected in CASES:
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        base_root, local_root, up_root = tmp / "base", tmp / "local", tmp / "up"
        for r, content in ((base_root, b), (local_root, loc), (up_root, up)):
            (r / "hooks" / "shared").mkdir(parents=True)
            (r / "VERSION").write_text("4.6.1\n", encoding="utf-8")
            if content is not None:
                (r / REL).write_text(content + "\n", encoding="utf-8")
        base_manifest = None
        if b is not None:
            mcm.stamp(base_root)
            base_manifest = base_root / mcm.MANIFEST_REL
        rows = {r["path"]: r["classification"]
                for r in mcm.classify(base_manifest, local_root, up_root)}
        got = rows.get(REL, "(absent from the classification)")
        if got != expected:
            fails.append(label + ": expected " + expected + " got " + got)

produced = {c for _, _, _, _, c in CASES}
missing = produced - set(mcm.CLASSIFICATIONS)
if missing:
    fails.append("classifications with no action row: " + repr(sorted(missing)))

# --auto-yes must never overwrite the four protected classes; only one may abort.
for c in ("consumer-only", "changed-by-both", "upstream-deleted-dirty", "unknown-base"):
    if mcm.CLASSIFICATIONS[c]["auto_overwrite"]:
        fails.append("--auto-yes would overwrite " + c + " — K9 forbids it")
    if not mcm.CLASSIFICATIONS[c]["report"]:
        fails.append(c + " must be REPORTED, never silently preserved (AC15)")
aborts = {c for c, cfg in mcm.CLASSIFICATIONS.items() if cfg["abort"]}
if aborts != {"changed-by-both"}:
    fails.append("exactly changed-by-both may abort; got " + repr(sorted(aborts)))
# Row 7 is the ONE preserve case that stays silent (a consumer's own untracked file).
if mcm.CLASSIFICATIONS["consumer-added"]["report"]:
    fails.append("consumer-added must stay silent (K9 row 7)")

sys.stdout = _real_stdout
print(json.dumps(fails))
PYK9
)"
if [ "$K9_OUT" = "[]" ]; then
  ok "k9-ten-state-truth-table-and-auto-yes-containment"
else
  bad "k9-ten-state-truth-table-and-auto-yes-containment" "$K9_OUT"
fi

# ---- 3. END-TO-END through the REAL upgrade.sh -------------------------------------
# Builds a 4.6.1 consumer tree with a recorded base, a local edit, and a 4.7.0 staging
# clone, then runs the shipped engine. This is the direct regression for the incident
# that produced this ticket (AC16) plus AC13b/AC13c.
E2E_ROOT="$(mktemp -d)"

# The 4.7.0+ source-boundary libs — staged so these end-to-end cases exercise the real
# boundary. `[ -f ]`-guarded so the fixture still builds against a pre-boundary tree.
# Byte-model / boundary assertions live in test-upgrade-source-boundary.sh.
copy_boundary_libs() {   # <lib-dest-dir>
  local f
  for f in materialize-managed-source.sh backup-hygiene.sh; do
    [ -f "$ROOT/hooks/local/lib/$f" ] && cp "$ROOT/hooks/local/lib/$f" "$1/"
  done
  return 0
}

# build_case <dir> <upstream-validator-content>
#   Upstream content equal to the base  => consumer-only (row 3)
#   Upstream content different          => changed-by-both (row 4)
build_case() {
  local D="$1" up_validator="$2" L U
  L="$D/local"; U="$L/.fusebase-flow-source"
  mkdir -p "$L/hooks/shared" "$L/hooks/local/lib" "$L/workflows"
  ( cd "$L" && git init -q && git config user.email t@t.t && git config user.name t )
  echo "4.6.1" > "$L/VERSION"
  printf 'validator v1\n' > "$L/hooks/shared/command_policy.py"
  printf 'control v1\n'   > "$L/hooks/local/control.sh"
  printf 'wf v1\n'        > "$L/workflows/wf.md"
  cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$L/hooks/local/lib/"
  cp "$ROOT/hooks/local/upgrade.sh" "$L/hooks/local/"
  cp "$ROOT/hooks/local/bootstrap-upgrade.sh" "$L/hooks/local/"
  copy_boundary_libs "$L/hooks/local/lib"
  ( cd "$L" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  # The consumer's local hardening, applied AFTER the base was recorded.
  printf 'validator v1\n# SENTINEL local hardening\n' > "$L/hooks/shared/command_policy.py"
  mkdir -p "$U/hooks/shared" "$U/hooks/local/lib" "$U/workflows"
  echo "4.7.0" > "$U/VERSION"
  printf '%s\n' "$up_validator" > "$U/hooks/shared/command_policy.py"
  printf 'control v2\n'          > "$U/hooks/local/control.sh"
  printf 'wf v1\n'               > "$U/workflows/wf.md"
  printf 'new upstream file\n'   > "$U/hooks/shared/brand_new.py"
  cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$U/hooks/local/lib/"
  cp "$ROOT/hooks/local/upgrade.sh" "$U/hooks/local/"
  cp "$ROOT/hooks/local/bootstrap-upgrade.sh" "$U/hooks/local/"
  copy_boundary_libs "$U/hooks/local/lib"
  ( cd "$U" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  echo "$L"
}

# --- 3a. AC16: upstream ALSO rewrote the file -> changed-by-both -> --auto-yes ABORTS.
CB="$(build_case "$E2E_ROOT/cb" "validator v2 upstream rewrite")"
CB_LOG="$E2E_ROOT/cb.log"
( cd "$CB" && bash hooks/local/upgrade.sh --auto-yes ) > "$CB_LOG" 2>&1
CB_RC=$?
cb_fail=""
[ "$CB_RC" -eq 3 ] || cb_fail="$cb_fail [expected clean-abort rc 3, got $CB_RC]"
grep -q "changed-by-both" "$CB_LOG" || cb_fail="$cb_fail [report never says changed-by-both]"
grep -q -- "- hooks/shared/command_policy.py" "$CB_LOG" || cb_fail="$cb_fail [the conflicting path is not listed LITERALLY (AC15)]"
grep -q "ABORTED" "$CB_LOG" || cb_fail="$cb_fail [no abort notice]"
grep -q "pre-upgrade-" "$CB_LOG" || cb_fail="$cb_fail [backup dir not named (AC15)]"
tail -1 "$CB_LOG" | grep -q "upgrade.sh" || cb_fail="$cb_fail [resume command is not last (AC15)]"
grep -q SENTINEL "$CB/hooks/shared/command_policy.py" || cb_fail="$cb_fail [the consumer edit was LOST — the reported defect]"
grep -q "control v1" "$CB/hooks/local/control.sh" || cb_fail="$cb_fail [abort was not clean: content was written anyway]"
if [ -z "$cb_fail" ]; then
  ok "ac16-changed-by-both-aborts-auto-yes-and-preserves-the-patch"
else
  bad "ac16-changed-by-both-aborts-auto-yes-and-preserves-the-patch" "$cb_fail"
fi

# --- 3b. AC13c + AC13b: consumer-only preserved while the rest of the SAME directory
#         refreshes, and the base is refreshed so a SECOND upgrade is not a no-op.
CO="$(build_case "$E2E_ROOT/co" "validator v1")"
CO_LOG="$E2E_ROOT/co.log"
( cd "$CO" && bash hooks/local/upgrade.sh --auto-yes ) > "$CO_LOG" 2>&1
co_fail=""
grep -q -- "- hooks/shared/command_policy.py" "$CO_LOG" || co_fail="$co_fail [consumer-only path not enumerated (AC15)]"
grep -q SENTINEL "$CO/hooks/shared/command_policy.py" || co_fail="$co_fail [consumer-only file was overwritten]"
grep -q "control v2" "$CO/hooks/local/control.sh" || co_fail="$co_fail [upstream-only sibling was NOT refreshed — partial apply broken (AC13c)]"
[ -f "$CO/hooks/shared/brand_new.py" ] || co_fail="$co_fail [upstream-added file was not installed]"
[ "$(tr -d '\n\r' < "$CO/VERSION")" = "4.7.0" ] || co_fail="$co_fail [VERSION did not advance]"
NEW_BASE_VER="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['flow_version'])" "$CO/audit/managed-content-manifest.json" 2>/dev/null)"
[ "$NEW_BASE_VER" = "4.7.0" ] || co_fail="$co_fail [base manifest was NOT refreshed to 4.7.0 (K13b) — got '$NEW_BASE_VER']"
if [ -z "$co_fail" ]; then
  ok "ac13c-partial-apply-preserves-one-refreshes-siblings"
else
  bad "ac13c-partial-apply-preserves-one-refreshes-siblings" "$co_fail"
fi

# --- 3c. AC13b second half: a SECOND consecutive upgrade must still deliver content
#         and must NOT invent consumer-only rows for files it just installed itself.
U2="$CO/.fusebase-flow-source"
echo "4.7.1" > "$U2/VERSION"
printf 'control v3\n' > "$U2/hooks/local/control.sh"
( cd "$U2" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
CO2_LOG="$E2E_ROOT/co2.log"
( cd "$CO" && bash hooks/local/upgrade.sh --auto-yes ) > "$CO2_LOG" 2>&1
co2_fail=""
grep -q "control v3" "$CO/hooks/local/control.sh" || co2_fail="$co2_fail [second upgrade delivered NO content — the classifier is single-shot]"
grep -q SENTINEL "$CO/hooks/shared/command_policy.py" || co2_fail="$co2_fail [the genuine consumer edit was lost on run 2]"
# Exactly ONE consumer-only path may appear: the file the consumer really edited.
CO2_CONSUMER_ONLY="$(grep -c "^    - " "$CO2_LOG" 2>/dev/null || echo 0)"
[ "$CO2_CONSUMER_ONLY" = "1" ] || co2_fail="$co2_fail [run 2 flagged $CO2_CONSUMER_ONLY divergent paths, expected exactly 1]"
if [ -z "$co2_fail" ]; then
  ok "ac13b-base-refresh-keeps-the-classifier-correct-on-the-next-upgrade"
else
  bad "ac13b-base-refresh-keeps-the-classifier-correct-on-the-next-upgrade" "$co2_fail"
fi
# --- 3d. AC23 / K20(a): classifier EXPECTED but unavailable -> abort, write NOTHING.
# T25 discriminator: pre-correction the engine warned and fell back to the whole-directory
# copy, overwriting the consumer's edit — the pre-4.7.0 behaviour, reachable on any
# hooks-off Windows install without python3.
FC="$(build_case "$E2E_ROOT/fc" "validator v2 upstream rewrite")"
# Make the classifier unusable while the SOURCE still SHIPS the module (so "classifier
# expected" is true). Snapshot AFTER the sabotage, so the no-write assertion measures the
# upgrade run and nothing else.
mv "$FC/.fusebase-flow-source/hooks/local/lib/managed_content_manifest.py" \
   "$FC/.fusebase-flow-source/hooks/local/lib/managed_content_manifest.py.disabled"
: > "$FC/.fusebase-flow-source/hooks/local/lib/managed_content_manifest.py"   # present, lists nothing
mv "$FC/hooks/local/lib/managed_content_manifest.py" "$FC/hooks/local/lib/mcm.disabled"
# TRIPWIRE (M10 fail-closed): the source must be PRE-manifest here, or the source boundary
# refuses it first (a manifest-bearing source whose verifier cannot report MATCH aborts before
# any classification) and this case would assert the boundary's abort instead of the classifier
# gate's. The sabotaged module IS the verifier, so no re-stamp can make it self-verify.
rm -f "$FC/.fusebase-flow-source/audit/managed-content-manifest.json"
fc_tree_before="$( cd "$FC" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum )"
FC_LOG="$E2E_ROOT/fc.log"
( cd "$FC" && bash hooks/local/upgrade.sh --auto-yes ) > "$FC_LOG" 2>&1
FC_RC=$?
fc_tree_after="$( cd "$FC" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum )"
fc_fail=""
[ "$FC_RC" -ne 0 ] || fc_fail="$fc_fail [classifier-less run exited 0 — it proceeded]"
grep -q "ABORT" "$FC_LOG" || fc_fail="$fc_fail [no abort diagnostic]"
grep -q "NOTHING was written" "$FC_LOG" || fc_fail="$fc_fail [abort does not state nothing was written]"
grep -q -- "--unsafe-legacy-copy" "$FC_LOG" && fc_fail="$fc_fail [a diagnostic SUGGESTED the unsafe flag (K20a forbids)]"
[ "$fc_tree_before" = "$fc_tree_after" ] || fc_fail="$fc_fail [tree changed during a fail-closed abort]"
grep -q SENTINEL "$FC/hooks/shared/command_policy.py" || fc_fail="$fc_fail [consumer edit overwritten]"
if [ -z "$fc_fail" ]; then
  ok "ac23-classifier-unavailable-fails-closed-and-writes-nothing"
else
  bad "ac23-classifier-unavailable-fails-closed-and-writes-nothing" "rc=$FC_RC$fc_fail"
fi

# --- 3e. AC23: --unsafe-legacy-copy is the ONLY route back to the legacy copy.
( cd "$FC" && bash hooks/local/upgrade.sh --auto-yes --unsafe-legacy-copy ) > "$E2E_ROOT/fc2.log" 2>&1
if grep -q "control v2" "$FC/hooks/local/control.sh"; then
  ok "ac23-unsafe-legacy-copy-is-the-only-legacy-route"
else
  bad "ac23-unsafe-legacy-copy-is-the-only-legacy-route" "$(tail -5 "$E2E_ROOT/fc2.log" | tr '\n' '|')"
fi

# --- 3f. AC23: a genuinely PRE-classifier source tree still upgrades (no false abort).
PRE="$(build_case "$E2E_ROOT/pre" "validator v1")"
# A GENUINELY pre-classifier source ships neither the module nor the manifest. Leaving the
# manifest behind models an impossible tree (manifest with no verifier), which M10 fail-closed
# correctly refuses — the compatibility contract under test is the manifest-ABSENT one.
rm -f "$PRE/.fusebase-flow-source/hooks/local/lib/managed_content_manifest.py" \
      "$PRE/.fusebase-flow-source/audit/managed-content-manifest.json" \
      "$PRE/hooks/local/lib/managed_content_manifest.py"
( cd "$PRE" && bash hooks/local/upgrade.sh --auto-yes ) > "$E2E_ROOT/pre.log" 2>&1
PRE_RC=$?
if [ "$PRE_RC" -eq 0 ] && grep -q "control v2" "$PRE/hooks/local/control.sh"; then
  ok "ac23-pre-classifier-source-still-upgrades"
else
  bad "ac23-pre-classifier-source-still-upgrades" "rc=$PRE_RC $(tail -5 "$E2E_ROOT/pre.log" | tr '\n' '|')"
fi

rm -rf "$E2E_ROOT"

# ---- 4. AC13b/AC16 base SYNTHESIS through the real bootstrap-upgrade.sh -------------
# The adoption hop for a consumer arriving from <= 4.6.1 with NO base manifest. Without
# synthesis every path reads `unknown-base`, K9 preserves all of them, and the upgrade
# reports success while installing NOTHING — a green run that preserved everything is a
# FAIL, which is exactly what the control-file assertion below exists to catch.
SYN_ROOT="$(mktemp -d)"
UPREPO="$SYN_ROOT/upstream"
mkdir -p "$UPREPO/hooks/shared" "$UPREPO/hooks/local/lib" "$UPREPO/workflows"
( cd "$UPREPO" && git init -q && git config user.email t@t.t && git config user.name t \
    && git config core.autocrlf false )
# --- upstream v4.6.1 (what the consumer was shipped) ---
echo "4.6.1" > "$UPREPO/VERSION"
printf 'validator v1\n' > "$UPREPO/hooks/shared/command_policy.py"
printf 'control v1\n'   > "$UPREPO/hooks/local/control.sh"
printf 'wf v1\n'        > "$UPREPO/workflows/wf.md"
cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$UPREPO/hooks/local/lib/"
cp "$ROOT/hooks/local/upgrade.sh" "$UPREPO/hooks/local/"
cp "$ROOT/hooks/local/bootstrap-upgrade.sh" "$UPREPO/hooks/local/"
( cd "$UPREPO" && git add -A && git commit -qm 'v4.6.1' && git branch -M main && git tag v4.6.1 )
# --- upstream 4.7.0 on main: control.sh changes; the validator does NOT ---
# DELIBERATE, and NOT the AC16 abort case: this fixture proves the upgrade still DELIVERS
# content (an abort writes nothing, so one run cannot prove both). The `changed-by-both`
# half of AC16 — upstream rewrites the validator, --auto-yes ABORTS, sentinel survives, the
# path is named literally — is section 6 (ac25-aborted-bootstrap-hop-writes-nothing) and
# section 3a. Same split the PO applied to smoke S4a/S4b.
echo "4.7.0" > "$UPREPO/VERSION"
printf 'control v2\n'        > "$UPREPO/hooks/local/control.sh"
printf 'new upstream file\n' > "$UPREPO/hooks/shared/brand_new.py"
( cd "$UPREPO" && git add -A && git commit -qm 'v4.7.0' )

# --- the consumer: 4.6.1 content, a local edit, and NO base manifest ---
CONS="$SYN_ROOT/consumer"
mkdir -p "$CONS/hooks/shared" "$CONS/hooks/local/lib" "$CONS/workflows"
( cd "$CONS" && git init -q && git config user.email t@t.t && git config user.name t     && git config core.autocrlf false )
echo "4.6.1" > "$CONS/VERSION"
printf 'validator v1\n# SENTINEL local hardening\n' > "$CONS/hooks/shared/command_policy.py"
printf 'control v1\n' > "$CONS/hooks/local/control.sh"
printf 'wf v1\n'      > "$CONS/workflows/wf.md"
cp "$ROOT/hooks/local/bootstrap-upgrade.sh" "$CONS/hooks/local/"
CONTROL_BEFORE="$( ( cd "$CONS" && sha256sum hooks/local/control.sh ) | cut -d' ' -f1)"
SYN_LOG="$SYN_ROOT/bootstrap.log"
( cd "$CONS" && bash hooks/local/bootstrap-upgrade.sh --repo "$UPREPO" --ref main -- --auto-yes ) \
    > "$SYN_LOG" 2>&1
SYN_RC=$?
CONTROL_AFTER="$( ( cd "$CONS" && sha256sum hooks/local/control.sh ) | cut -d' ' -f1)"

syn_fail=""
grep -q "synthesized the classifier base from upstream tag v4.6.1" "$SYN_LOG" \
  || syn_fail="$syn_fail [no base was synthesized from the v4.6.1 tag]"
[ -f "$CONS/audit/managed-content-manifest.json" ] || syn_fail="$syn_fail [base manifest absent after the hop]"
grep -q SENTINEL "$CONS/hooks/shared/command_policy.py" \
  || syn_fail="$syn_fail [the consumer's local hardening was OVERWRITTEN — the reported defect]"
grep -q -- "- hooks/shared/command_policy.py" "$SYN_LOG" \
  || syn_fail="$syn_fail [preserved-but-UNREPORTED: the consumer is not told which file diverged (AC15)]"
# The control file is the anti-no-op assertion: if synthesis silently failed, everything
# would be `unknown-base`, everything preserved, and this hash would NOT have moved.
[ "$CONTROL_BEFORE" != "$CONTROL_AFTER" ] \
  || syn_fail="$syn_fail [control file NOT refreshed — base synthesis failed and the 'successful' upgrade installed nothing]"
grep -q "control v2" "$CONS/hooks/local/control.sh" || syn_fail="$syn_fail [control file content is not upstream 4.7.0]"
[ -f "$CONS/hooks/shared/brand_new.py" ] || syn_fail="$syn_fail [upstream-added file not installed]"
grep -q "unknown-base" "$SYN_LOG" && syn_fail="$syn_fail [paths still fell through to unknown-base despite a synthesized base]"
if [ -z "$syn_fail" ]; then
  ok "ac13b-base-synthesis-from-the-version-tag-delivers-content"
else
  bad "ac13b-base-synthesis-from-the-version-tag-delivers-content" \
      "rc=$SYN_RC$syn_fail :: $(tail -25 "$SYN_LOG" | tr '\n' '|')"
fi

# --- 4b. Unresolvable tag (forked/unreleased VERSION) degrades to preserve, never loss.
FORK="$SYN_ROOT/forked"
mkdir -p "$FORK/hooks/shared" "$FORK/hooks/local/lib" "$FORK/workflows"
( cd "$FORK" && git init -q && git config user.email t@t.t && git config user.name t     && git config core.autocrlf false )
echo "4.6.1-mycompany" > "$FORK/VERSION"
printf 'validator v1\n# SENTINEL local hardening\n' > "$FORK/hooks/shared/command_policy.py"
printf 'control v1\n' > "$FORK/hooks/local/control.sh"
cp "$ROOT/hooks/local/bootstrap-upgrade.sh" "$FORK/hooks/local/"
FORK_LOG="$SYN_ROOT/forked.log"
( cd "$FORK" && bash hooks/local/bootstrap-upgrade.sh --repo "$UPREPO" --ref main -- --auto-yes ) \
    > "$FORK_LOG" 2>&1
fork_fail=""
grep -q "could not be resolved" "$FORK_LOG" || fork_fail="$fork_fail [no diagnosis for the unresolvable tag]"
grep -q SENTINEL "$FORK/hooks/shared/command_policy.py" \
  || fork_fail="$fork_fail [unknown-base must PRESERVE, never overwrite (K9 row 10)]"
grep -q "unknown-base" "$FORK_LOG" || fork_fail="$fork_fail [unknown-base paths were not REPORTED]"
if [ -z "$fork_fail" ]; then
  ok "k9-row10-unresolvable-tag-preserves-and-reports-never-aborts"
else
  bad "k9-row10-unresolvable-tag-preserves-and-reports-never-aborts" "$fork_fail"
fi
rm -rf "$SYN_ROOT"

# ---- 5. AC24 / K20(b): no Flow tooling advises restamping a base from the local tree --
# T26 discriminator: preflight named stamp-managed-content-manifest.sh as the fix on BOTH
# the missing-base and the stale-base path. Following that advice records the consumer's
# local edits as "upstream base", and the next upstream change to those files classifies
# upstream-only and overwrites them — the original incident, via the machinery built to
# prevent it. The check is on the CONSUMER-FACING advice lines only; the upstream/CI
# stamp tool itself keeps its name.
adv_fail=""
ADV_LINES="$(grep -n "warn \"" "$ROOT/hooks/local/preflight.sh" | grep -i "managed-content base manifest")"
case "$ADV_LINES" in
  *stamp-managed-content-manifest.sh*) adv_fail="$adv_fail [preflight still advises the self-restamp]" ;;
esac
case "$ADV_LINES" in
  *bootstrap-upgrade.sh*) ;; *) adv_fail="$adv_fail [preflight does not name the tag-sourced recovery]" ;;
esac
# Every consumer-facing carrier of the advice must be corrected, not just the reported one.
grep -q "never restamp\|NEVER advise stamping\|Do NOT restamp\|never be advised" \
  "$ROOT/hooks/local/stamp-managed-content-manifest.sh" \
  || adv_fail="$adv_fail [the stamp tool does not warn that it is not consumer base-recovery]"
grep -qi "consumer must NEVER restamp\|never restamp a missing or drifted base" "$ROOT/audit/README.md" \
  || adv_fail="$adv_fail [audit/README.md still presents restamping as the consumer's fix]"
if [ -z "$adv_fail" ]; then
  ok "ac24-no-self-restamp-advice-in-any-carrier"
else
  bad "ac24-no-self-restamp-advice-in-any-carrier" "$adv_fail"
fi

# Behavioural half: a base restamped FROM a diverged tree makes the consumer edit look
# like upstream's own content, so the next upstream change silently overwrites it. The
# tag-synthesized base (the corrected advice) classifies and PRESERVES it instead.
RS_ROOT="$(mktemp -d)"
rs_case() {   # $1 = base-source: "self" (restamp from the diverged tree) | "tag"
  local D="$RS_ROOT/$1" L U
  L="$D/local"; U="$L/.fusebase-flow-source"
  mkdir -p "$L/hooks/shared" "$L/hooks/local/lib" "$U/hooks/shared" "$U/hooks/local/lib"
  ( cd "$L" && git init -q && git config user.email t@t.t && git config user.name t )
  echo "4.6.1" > "$L/VERSION"
  printf 'validator v1\n' > "$L/hooks/shared/command_policy.py"
  cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$L/hooks/local/lib/"
  cp "$ROOT/hooks/local/upgrade.sh" "$L/hooks/local/"
  # The consumer is a 4.7.0 install (it carries the 4.7 engine + classifier), so it also carries
  # the boundary lib: the direct engine sources that TRUSTED LOCAL copy and refuses to run
  # pre-boundary rather than falling back to the source worktree's copy.
  [ -f "$ROOT/hooks/local/lib/materialize-managed-source.sh" ] \
    && cp "$ROOT/hooks/local/lib/materialize-managed-source.sh" "$L/hooks/local/lib/"
  if [ "$1" = "tag" ]; then    # the base upstream ACTUALLY shipped (pre-edit)
    ( cd "$L" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  fi
  printf 'validator v1\n# SENTINEL local hardening\n' > "$L/hooks/shared/command_policy.py"
  if [ "$1" = "self" ]; then   # the advice under test: stamp from the DIVERGED tree
    ( cd "$L" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  fi
  echo "4.7.0" > "$U/VERSION"
  printf 'validator v2 upstream rewrite\n' > "$U/hooks/shared/command_policy.py"
  cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$U/hooks/local/lib/"
  cp "$ROOT/hooks/local/upgrade.sh" "$U/hooks/local/"
  ( cd "$U" && python3 hooks/local/lib/managed_content_manifest.py stamp --root . >/dev/null )
  ( cd "$L" && bash hooks/local/upgrade.sh --auto-yes ) >/dev/null 2>&1
  grep -q SENTINEL "$L/hooks/shared/command_policy.py" && echo preserved || echo lost
}
SELF_RESULT="$(rs_case self)"
TAG_RESULT="$(rs_case tag)"
if [ "$SELF_RESULT" = "lost" ] && [ "$TAG_RESULT" = "preserved" ]; then
  ok "ac24-self-restamped-base-loses-the-edit-tag-sourced-base-preserves-it"
else
  bad "ac24-self-restamped-base-loses-the-edit-tag-sourced-base-preserves-it" \
      "self=$SELF_RESULT (want lost) tag=$TAG_RESULT (want preserved)"
fi
rm -rf "$RS_ROOT"

# ---- 6. AC25 / K10+K20: the bootstrap hop writes NOTHING before classification -------
# T27 discriminator: Step 2 used to copy the fetched engine scripts and the whole
# hooks/local/lib/ into the consumer, then exec the INSTALLED copy — so a later
# changed-by-both abort could not truthfully claim "nothing was written", and a consumer's
# own engine customization was already replaced. The sentinel below lives in
# hooks/local/upgrade.sh precisely because that is the file Step 2 overwrote first.
NW_ROOT="$(mktemp -d)"
NW_UP="$NW_ROOT/up"
mkdir -p "$NW_UP/hooks/shared" "$NW_UP/hooks/local/lib" "$NW_UP/workflows"
( cd "$NW_UP" && git init -q && git config user.email t@t.t && git config user.name t \
    && git config core.autocrlf false )
echo "4.6.1" > "$NW_UP/VERSION"
printf 'validator v1\n' > "$NW_UP/hooks/shared/command_policy.py"
printf 'wf v1\n'        > "$NW_UP/workflows/wf.md"
cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$NW_UP/hooks/local/lib/"
cp "$ROOT/hooks/local/upgrade.sh" "$NW_UP/hooks/local/"
cp "$ROOT/hooks/local/bootstrap-upgrade.sh" "$NW_UP/hooks/local/"
( cd "$NW_UP" && git add -A && git commit -qm 'v4.6.1' && git branch -M main && git tag v4.6.1 )
echo "4.7.0" > "$NW_UP/VERSION"
printf 'validator v2 upstream rewrite\n' > "$NW_UP/hooks/shared/command_policy.py"
( cd "$NW_UP" && git add -A && git commit -qm 'v4.7.0' )

NW_C="$NW_ROOT/cons"
mkdir -p "$NW_C/hooks/shared" "$NW_C/hooks/local/lib" "$NW_C/workflows"
( cd "$NW_C" && git init -q && git config user.email t@t.t && git config user.name t \
    && git config core.autocrlf false )
echo "4.6.1" > "$NW_C/VERSION"
printf 'validator v1\n# SENTINEL local hardening\n' > "$NW_C/hooks/shared/command_policy.py"
printf 'wf v1\n' > "$NW_C/workflows/wf.md"
cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$NW_C/hooks/local/lib/"
cp "$ROOT/hooks/local/bootstrap-upgrade.sh" "$NW_C/hooks/local/"
# The consumer's OWN customization of the engine — Step 2's first casualty pre-correction.
cp "$ROOT/hooks/local/upgrade.sh" "$NW_C/hooks/local/"
printf '\n# ENGINE-SENTINEL consumer customization\n' >> "$NW_C/hooks/local/upgrade.sh"
# Snapshot everything except .git and the transient source clone.
nw_hash() { ( cd "$NW_C" && find . -path ./.git -prune -o -path ./.fusebase-flow-source -prune \
  -o -path ./audit -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum ); }
NW_BEFORE="$(nw_hash)"
( cd "$NW_C" && bash hooks/local/bootstrap-upgrade.sh --repo "$NW_UP" --ref main -- --auto-yes ) \
    > "$NW_ROOT/log" 2>&1
NW_RC=$?
NW_AFTER="$(nw_hash)"
nw_fail=""
[ "$NW_RC" -ne 0 ] || nw_fail="$nw_fail [expected an abort on changed-by-both, got rc 0]"
grep -q "changed-by-both" "$NW_ROOT/log" || nw_fail="$nw_fail [no changed-by-both classification]"
grep -q "ENGINE-SENTINEL" "$NW_C/hooks/local/upgrade.sh" \
  || nw_fail="$nw_fail [the consumer's engine customization was replaced BEFORE classification]"
grep -q "SENTINEL local hardening" "$NW_C/hooks/shared/command_policy.py" \
  || nw_fail="$nw_fail [the consumer's validator patch was lost]"
[ "$NW_BEFORE" = "$NW_AFTER" ] \
  || nw_fail="$nw_fail [tree changed during an aborted hop — 'NOTHING was written' is false]"
if [ -z "$nw_fail" ]; then
  ok "ac25-aborted-bootstrap-hop-writes-nothing"
else
  bad "ac25-aborted-bootstrap-hop-writes-nothing" "rc=$NW_RC$nw_fail"
fi

# The non-abort path must still upgrade end-to-end with the engine run from source.
NW_C2="$NW_ROOT/cons2"
mkdir -p "$NW_C2/hooks/shared" "$NW_C2/hooks/local/lib" "$NW_C2/workflows"
( cd "$NW_C2" && git init -q && git config user.email t@t.t && git config user.name t \
    && git config core.autocrlf false )
echo "4.6.1" > "$NW_C2/VERSION"
printf 'validator v1\n' > "$NW_C2/hooks/shared/command_policy.py"
printf 'wf v1\n' > "$NW_C2/workflows/wf.md"
cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$NW_C2/hooks/local/lib/"
cp "$ROOT/hooks/local/upgrade.sh" "$NW_C2/hooks/local/"
cp "$ROOT/hooks/local/bootstrap-upgrade.sh" "$NW_C2/hooks/local/"
( cd "$NW_C2" && bash hooks/local/bootstrap-upgrade.sh --repo "$NW_UP" --ref main -- --auto-yes ) \
    > "$NW_ROOT/log2" 2>&1
NW2_RC=$?
if [ "$NW2_RC" -eq 0 ] && grep -q "validator v2 upstream rewrite" "$NW_C2/hooks/shared/command_policy.py"; then
  ok "ac25-source-executed-engine-still-upgrades-end-to-end"
else
  bad "ac25-source-executed-engine-still-upgrades-end-to-end" \
      "rc=$NW2_RC $(tail -6 "$NW_ROOT/log2" | tr '\n' '|')"
fi
rm -rf "$NW_ROOT"

# ---- 7. T29(c): classification is EOL-stable with core.autocrlf=true ----------------
# Every other fixture pins core.autocrlf=false, so CRLF behaviour was unproven — and the
# base is synthesized via `git archive`, which DOES apply core.autocrlf (measured; the
# bootstrap tripwire depends on it). A consumer on autocrlf=true must still see an
# untouched file as current/upstream-only, never consumer-divergent.
EOL_ROOT="$(mktemp -d)"
EOL_UP="$EOL_ROOT/up"
mkdir -p "$EOL_UP/hooks/shared" "$EOL_UP/hooks/local/lib" "$EOL_UP/workflows"
( cd "$EOL_UP" && git init -q && git config user.email t@t.t && git config user.name t \
    && git config core.autocrlf false )
echo "4.6.1" > "$EOL_UP/VERSION"
printf 'validator v1\n' > "$EOL_UP/hooks/shared/command_policy.py"
printf 'wf v1\n'        > "$EOL_UP/workflows/wf.md"
cp "$ROOT/hooks/local/lib/managed_content_manifest.py" "$EOL_UP/hooks/local/lib/"
cp "$ROOT/hooks/local/upgrade.sh" "$EOL_UP/hooks/local/"
cp "$ROOT/hooks/local/bootstrap-upgrade.sh" "$EOL_UP/hooks/local/"
# TRIPWIRE (platform): mirrors the SHIPPED .gitattributes pin for executables only.
# Unpinned, `clone -c core.autocrlf=true` lands *.sh CRLF and Linux bash refuses the
# script ("set: pipefail: invalid option name") — MSYS bash tolerates CR, so this was
# green locally and red on CI. Do NOT widen to *.md: wf.md must stay CRLF, it is the measurand.
printf '*.sh text eol=lf\n' > "$EOL_UP/.gitattributes"
( cd "$EOL_UP" && git add -A && git commit -qm 'v4.6.1' && git branch -M main && git tag v4.6.1 )
echo "4.7.0" > "$EOL_UP/VERSION"
printf 'validator v2\n' > "$EOL_UP/hooks/shared/command_policy.py"
( cd "$EOL_UP" && git add -A && git commit -qm 'v4.7.0' )

# The consumer checks out with core.autocrlf=TRUE — every text file lands CRLF on disk.
EOL_C="$EOL_ROOT/cons"
git -c core.autocrlf=true clone -q --branch main "$EOL_UP" "$EOL_C" 2>/dev/null
( cd "$EOL_C" && git config core.autocrlf true && git checkout -q v4.6.1 -- . 2>/dev/null || true )
echo "4.6.1" > "$EOL_C/VERSION"
( cd "$EOL_C" && git -c core.autocrlf=true checkout -q v4.6.1 2>/dev/null || true )
EOL_LOG="$EOL_ROOT/log"
( cd "$EOL_C" && bash hooks/local/bootstrap-upgrade.sh --repo "$EOL_UP" --ref main -- --auto-yes ) \
    > "$EOL_LOG" 2>&1
eol_fail=""
grep -q "synthesized the classifier base" "$EOL_LOG" || eol_fail="$eol_fail [no base synthesis]"
# wf.md was NEVER touched by anyone: on an EOL-stable classifier it is current/upstream-only,
# never consumer-only / changed-by-both / unknown-base.
for wrong in "consumer-only" "changed-by-both" "unknown-base"; do
  sed -n "/$wrong/,/^\$/p" "$EOL_LOG" | grep -q "workflows/wf.md" \
    && eol_fail="$eol_fail [untouched wf.md classified $wrong under core.autocrlf=true]"
done
if [ -z "$eol_fail" ]; then
  ok "t29c-classification-eol-stable-under-autocrlf-true"
else
  bad "t29c-classification-eol-stable-under-autocrlf-true" "$eol_fail :: $(tail -18 "$EOL_LOG" | tr '\n' '|')"
fi
rm -rf "$EOL_ROOT"

finish
