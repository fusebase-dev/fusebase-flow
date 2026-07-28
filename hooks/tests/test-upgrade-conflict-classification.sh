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
rm -rf "$E2E_ROOT"

finish
