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

finish
