#!/usr/bin/env bash
# Fusebase Flow — clone-durable deploy-approval receipt (S2 / AC10-AC13).
# Spec: docs/specs/consumer-escalation-v480/spec.md § "S2 closure C3 - LOCKED receipt contract".
#
# The defect under test: state/approvals/* is gitignored, so every committed deploy report that
# cited `state/approvals/<action>-<slug>-<date>.json` as its authorization evidence dangled on a
# fresh clone. These rows prove the receipt replaces that citation WITHOUT relaxing the gate.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: approval-receipt <name>" / "FAIL: approval-receipt <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: approval-receipt $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: approval-receipt $1 (${2:-})"; }
finish() { echo "[test-approval-receipt-durability] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: approval-receipt skipped-no-python3"; pass=1; finish; }

REPO="$(mktemp -d)"
OUT="$(mktemp -d)"
mkdir -p "$REPO/hooks/local/lib" "$REPO/hooks/shared" "$REPO/policies"
cp "$ROOT/hooks/local/approve-local.sh"        "$REPO/hooks/local/"
cp "$ROOT/hooks/local/lib/approval-receipt.sh" "$REPO/hooks/local/lib/"
cp "$ROOT/hooks/shared/"*.py                   "$REPO/hooks/shared/"
: > "$REPO/hooks/shared/__init__.py"
cp "$ROOT/policies/approval-policy.yml" "$ROOT/policies/command-policy.yml" "$REPO/policies/"
( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t )
# TRIPWIRE (MSYS): the python assertions run under WINDOWS python, which cannot resolve an
# MSYS "/tmp/..." path. Hand every python argv the native form or the reads silently fail.
REPO_NATIVE="$( cd "$REPO" && { pwd -W 2>/dev/null || pwd; } )"
OUT_NATIVE="$(  cd "$OUT"  && { pwd -W 2>/dev/null || pwd; } )"

CMD='fusebase deploy'
HASH='9fdb11abc'
sha_of() { python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1"; }

# ---- Phase A: drive the real scripts; capture stdout + rc for the assertions -------------
appr()    { ( cd "$REPO" && bash hooks/local/approve-local.sh "$@" ); }
receipt() { ( cd "$REPO" && bash hooks/local/lib/approval-receipt.sh "$@" ); }

appr production_deploy demo 'approve deploy now' --command "$CMD" >/dev/null 2>&1
ARTIFACT="$(ls "$REPO"/state/approvals/production_deploy-demo-*.json 2>/dev/null | head -1)"
ARTIFACT_NATIVE="$(ls "$REPO_NATIVE"/state/approvals/production_deploy-demo-*.json 2>/dev/null | head -1)"
[ -n "$ARTIFACT" ] && [ -n "$ARTIFACT_NATIVE" ] || { bad "setup-artifact-minted" "approve-local wrote nothing"; finish; }
sha_of "$ARTIFACT_NATIVE" > "$OUT/sha-before-emit.txt"

receipt emit production_deploy demo --deploy-hash "$HASH" --command "$CMD" --format json \
    > "$OUT/receipt.json" 2>/dev/null
receipt emit production_deploy demo --deploy-hash "$HASH" --command "$CMD" \
    > "$OUT/receipt.md" 2>/dev/null
sha_of "$ARTIFACT_NATIVE" > "$OUT/sha-after-emit.txt"

# Gate control (AC12): an approved command must still be allowed after evidence was emitted.
( cd "$REPO" && MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$CMD" <<'PY' 2>/dev/null
import sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd() / "hooks"))
from shared.command_policy import evaluate
from shared.policy_loader import reset_cache
reset_cache()
print(evaluate(sys.argv[1], root=Path.cwd()).decision)
PY
) > "$OUT/gate-after-emit.txt"

# Placeholder deploy hashes must be refused outright (DP.3) — no receipt at all.
: > "$OUT/placeholder-results.txt"
for ph in 'TBD' '<hash>' 'see commit' ''; do
  po="$(receipt emit production_deploy demo --deploy-hash "$ph" --command "$CMD" 2>/dev/null)"
  echo "rc=$?|stdout_len=${#po}|value=$ph" >> "$OUT/placeholder-results.txt"
done

# A command-bound artifact with no --command: the binding cannot be verified, so no receipt.
NOCMD="$(receipt emit production_deploy demo --deploy-hash "$HASH" 2>/dev/null)"
echo "rc=$?|stdout_len=${#NOCMD}" > "$OUT/nocommand.txt"

# Byte sensitivity: one appended byte must change the recorded digest.
cp "$ARTIFACT" "$OUT/artifact-original.json"
printf ' ' >> "$ARTIFACT"
receipt emit production_deploy demo --deploy-hash "$HASH" --command "$CMD" --format json \
    > "$OUT/receipt-mutated.json" 2>/dev/null
cp "$OUT/artifact-original.json" "$ARTIFACT"

# An EXPIRED approval must not be laundered into clean-looking evidence.
MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$REPO_NATIVE" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]) / "state" / "approvals" / "production_deploy-stale-20260101.json"
p.write_text(json.dumps({"schema_version": 2, "action": "production_deploy", "scope": "stale",
                         "created_at": "1999-12-31T00:00:00Z",
                         "expires_at": "2000-01-01T00:00:00Z",
                         "approved_by": "operator", "reason": "fixture"}, indent=2) + "\n",
             encoding="utf-8")
PY
STALE="$(receipt emit production_deploy stale --deploy-hash "$HASH" --format json 2>/dev/null)"
echo "rc=$?" > "$OUT/stale.rc"
printf '%s' "$STALE" > "$OUT/receipt-stale.json"

# ---- verify: the conforming report, the pre-fix shape, and four mutations ---------------
{ echo "# Deploy report — demo (T9)"; echo; cat "$OUT/receipt.md"; echo; echo "---"; echo;
  echo "## 2. Deploy command"; } > "$OUT/report-good.md"
# The exact pre-fix shape this ticket removes: an assertion plus a gitignored path.
printf '# Deploy report — demo (T9)\n\n**Approval artifact:** `state/approvals/production_deploy-demo-20260812.json` (expires `2026-11-10T03:30:47Z`)\n\n## 2. Deploy command\n' \
    > "$OUT/report-old-shape.md"
sed 's/`created_at`/`approved_at`/'    "$OUT/report-good.md" > "$OUT/report-approved-at.md"
sed 's/`remaining_ttl_seconds`/`ttl`/' "$OUT/report-good.md" > "$OUT/report-stored-ttl.md"
sed 's/`observed_verdict`/`verdict`/'  "$OUT/report-good.md" > "$OUT/report-stored-verdict.md"
sed 's/^\(| `observed_at` |[^|]*|\) computed at validation |/\1 stored (copied verbatim from the approval artifact) |/' \
    "$OUT/report-good.md" > "$OUT/report-mislabelled.md"

for r in good old-shape approved-at stored-ttl stored-verdict mislabelled; do
  vo="$(receipt verify "$OUT_NATIVE/report-$r.md" 2>&1)"
  { echo "rc=$?"; printf '%s\n' "$vo"; } > "$OUT/verify-$r.txt"
done

# ---- Phase B: one interpreter, one verdict object -------------------------------------
VERDICTS="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - \
    "$ROOT" "$REPO_NATIVE" "$OUT_NATIVE" "$CMD" "$HASH" <<'PY' 2>&1
import hashlib, json, re, sys
from datetime import datetime, timezone
from pathlib import Path

root, repo, out, cmd, want_hash = (Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]),
                                   sys.argv[4], sys.argv[5])
sys.path.insert(0, str(root / "hooks"))
from shared.approval_artifact import compute_command_digest, compute_repo_id  # noqa: E402

LOCKED = ["receipt_schema", "approval_artifact_schema", "approval_artifact_digest",
          "action", "repo_id", "command_digest", "scope", "created_at", "expires_at",
          "approved_by", "reason",
          "observed_at", "observed_verdict", "remaining_ttl_seconds",
          "deploy_hash"]
COPIED = LOCKED[3:11]
COMPUTED = LOCKED[11:14]
v = {}


def read(name):
    try:
        return (out / name).read_text(encoding="utf-8")
    except OSError as e:
        return f"<<unreadable: {e}>>"


artifact = sorted((repo / "state" / "approvals").glob("production_deploy-demo-*.json"))[0]
raw = artifact.read_bytes()
stored = json.loads(raw.decode("utf-8"))
try:
    receipt = json.loads(read("receipt.json"))
except ValueError:
    receipt = {}
md = read("receipt.md")

f = []
independent = "sha256:" + hashlib.sha256(raw).hexdigest()
if receipt.get("approval_artifact_digest") != independent:
    f.append(f"digest {receipt.get('approval_artifact_digest')!r} != the independently computed "
             f"{independent!r} over the validated artifact bytes")
if not re.fullmatch(r"sha256:[0-9a-f]{64}", receipt.get("approval_artifact_digest") or ""):
    f.append("digest is not `sha256:<64 lowercase hex>`")
try:
    mutated = json.loads(read("receipt-mutated.json")).get("approval_artifact_digest")
except ValueError:
    mutated = None
if mutated == receipt.get("approval_artifact_digest"):
    f.append("one appended byte did not change the digest — it does not cover the bytes")
v["ac11-digest-covers-the-exact-validated-bytes"] = f

f = []
if list(receipt.keys()) != LOCKED:
    f.append(f"field set/order drifted from the locked C3 contract: {list(receipt.keys())}")
if receipt.get("receipt_schema") != "fusebase-flow/deploy-approval-receipt/v1":
    f.append(f"receipt_schema is {receipt.get('receipt_schema')!r}")
if receipt.get("approval_artifact_schema") != stored.get("schema_version"):
    f.append("approval_artifact_schema is not the artifact's stored schema identifier value")
v["ac11-locked-field-set-complete-and-in-order"] = f

f = [f"{k}: receipt {receipt.get(k)!r} != stored {stored.get(k)!r}"
     for k in COPIED if receipt.get(k) != stored.get(k)]
if stored.get("repo_id") != compute_repo_id(repo):
    f.append("precondition: the fixture artifact is not repo-bound, so repo_id proves nothing")
if stored.get("command_digest") != compute_command_digest(cmd):
    f.append("precondition: the fixture artifact is not command-bound")
v["ac11-copied-fields-carry-the-stored-values"] = f

f = []
for ghost in ("approved_at", "ttl", "verdict"):
    if ghost in receipt:
        f.append(f"receipt carries `{ghost}`, which no approval writer stores")
    if re.search(rf"^\|\s*`{ghost}`\s*\|", md, re.M):
        f.append(f"markdown receipt has a `{ghost}` row")
if not receipt.get("created_at"):
    f.append("created_at absent — it is the stored name and must be carried")
for ghost in ("approved_at", "ttl", "verdict"):
    if ghost in stored:
        f.append(f"precondition broken: the artifact writer now stores `{ghost}`")
v["ac11-no-invented-stored-field-names"] = f

f = []
for k in COMPUTED:
    row = re.search(rf"^\|\s*`{k}`\s*\|[^|\n]*\|([^\n]*)$", md, re.M)
    if not row:
        f.append(f"no markdown row for {k}")
    elif "computed" not in row.group(1).lower():
        f.append(f"{k} is not labelled computed: {row.group(1).strip()!r}")
for k in COPIED:
    row = re.search(rf"^\|\s*`{k}`\s*\|[^|\n]*\|([^\n]*)$", md, re.M)
    if row and "stored" not in row.group(1).lower():
        f.append(f"{k} is not labelled stored: {row.group(1).strip()!r}")


def parse(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(timezone.utc)


if receipt.get("observed_verdict") != "VALID":
    f.append(f"observed_verdict {receipt.get('observed_verdict')!r} for a freshly minted artifact")
try:
    expect_ttl = int((parse(stored["expires_at"]) - parse(receipt["observed_at"])).total_seconds())
    if receipt.get("remaining_ttl_seconds") != expect_ttl:
        f.append(f"remaining_ttl_seconds {receipt.get('remaining_ttl_seconds')!r} != "
                 f"expires_at - observed_at ({expect_ttl})")
except (KeyError, TypeError, ValueError) as e:
    f.append(f"remaining_ttl_seconds could not be checked: {e!r}")
low = md.lower()
if "not authenticate the operator" not in low or "fabricated" not in low:
    f.append("the emitted block states no evidence limits — it reads as an authenticity claim")
v["ac11-computed-observations-labelled-and-correct"] = f

f = []
if receipt.get("deploy_hash") != want_hash:
    f.append(f"deploy_hash {receipt.get('deploy_hash')!r} != {want_hash!r}")
for line in read("placeholder-results.txt").splitlines():
    m = re.match(r"rc=(\d+)\|stdout_len=(\d+)\|value=(.*)$", line)
    if m and (int(m.group(1)) == 0 or int(m.group(2)) != 0):
        f.append(f"placeholder deploy hash {m.group(3)!r} produced a receipt "
                 f"(rc={m.group(1)}, {m.group(2)} bytes)")
v["ac11-deploy-hash-bound-and-placeholders-refused"] = f

f = []
for name, token in (("approved-at", "approved_at"), ("stored-ttl", "ttl"),
                    ("stored-verdict", "verdict")):
    text = read(f"verify-{name}.txt")
    if not text.startswith("rc=1"):
        f.append(f"a receipt naming `{token}` was accepted")
    elif "R5" not in text:
        f.append(f"`{token}` was rejected without naming the stored-vs-computed rule (R5)")
mis = read("verify-mislabelled.txt")
if not mis.startswith("rc=1"):
    f.append("a computed field relabelled 'stored' was accepted")
elif "R6" not in mis:
    f.append("the mislabel was rejected without naming the computed-label rule (R6)")
v["ac11-verifier-rejects-ghost-fields-and-mislabels"] = f

v["ac12-emitted-evidence-carries-no-local-path"] = [
    f"{n} contains a local approvals path"
    for n in ("receipt.json", "receipt.md") if "state/approvals" in read(n)]

old = read("verify-old-shape.txt")
f = []
if not old.startswith("rc=1"):
    f.append(f"the pre-fix assertion-only report was accepted: {old.splitlines()[:1]}")
if "R1" not in old:
    f.append("rejection did not name the missing receipt (R1)")
if "R7" not in old:
    f.append("rejection did not name the dangling local path (R7)")
v["ac12-old-assertion-only-shape-rejected"] = f

good = read("verify-good.txt")
v["ac12-conforming-report-accepted [CONTROL]"] = (
    [] if good.startswith("rc=0")
    else [f"a conforming report was rejected, so every rejection row above proves nothing: {good!r}"])

f = []
if read("gate-after-emit.txt").strip() != "allow":
    f.append("the command gate stopped allowing an approved command after evidence was emitted")
before, after = read("sha-before-emit.txt").strip(), read("sha-after-emit.txt").strip()
if not before or before != after:
    f.append(f"emitting the receipt changed the approval artifact ({before!r} -> {after!r})")
if hashlib.sha256(raw).hexdigest() != before:
    f.append("the artifact does not match its pre-emission bytes at the end of the run")
v["ac12-gate-and-artifact-unchanged-by-emission"] = f

f = []
if read("stale.rc").strip() != "rc=3":
    f.append(f"emit against an EXPIRED artifact did not exit 3: {read('stale.rc').strip()!r}")
try:
    stale = json.loads(read("receipt-stale.json"))
except ValueError as e:
    stale = {}
    f.append(f"no receipt emitted for the expired artifact ({e}) — silence is not evidence")
if stale.get("observed_verdict") != "EXPIRED":
    f.append(f"observed_verdict {stale.get('observed_verdict')!r} for an expired artifact")
if not isinstance(stale.get("remaining_ttl_seconds"), int) or stale["remaining_ttl_seconds"] >= 0:
    f.append(f"remaining_ttl_seconds {stale.get('remaining_ttl_seconds')!r} is not negative for "
             "an expired artifact")
v["ac12-expired-approval-not-laundered"] = f

nc = read("nocommand.txt").strip()
v["ac12-unverifiable-binding-emits-no-receipt"] = (
    [] if nc.startswith("rc=2") and nc.endswith("stdout_len=0")
    else [f"a command-bound artifact yielded a receipt without --command: {nc!r}"])

tpl = (root / "templates" / "deploy-report.md").read_text(encoding="utf-8")
f = []
if "state/approvals" in tpl:
    f.append("templates/deploy-report.md still cites a local approvals path")
if "fusebase-flow/deploy-approval-receipt/v1" not in tpl:
    f.append("templates/deploy-report.md does not carry the receipt schema")
if "--receipt verify" not in tpl:
    f.append("templates/deploy-report.md gives no self-check before the report is committed")
if "state/approvals" in (root / "templates" / "gate-report.md").read_text(encoding="utf-8"):
    f.append("templates/gate-report.md cites an approval path but got a no-change disposition")
v["ac13-deploy-report-template-carries-the-receipt"] = f

census = (root / "docs" / "backlog" / "provenance-and-single-seam-guarantees"
          / "README.md").read_text(encoding="utf-8")
CARRIERS = ["hooks/shared/approval_artifact.py", "hooks/shared/command_policy.py",
            "hooks/shared/path_policy.py", "hooks/handlers/permission_request.py",
            "hooks/local/lib/active-approvals.sh", "hooks/local/lib/approval_inventory.py",
            "hooks/local/fusebase-flow-health-check.sh", "hooks/local/approve-local.sh",
            "hooks/local/write-bootstrap-approval.sh", "hooks/local/lib/approval-receipt.sh",
            "templates/deploy-report.md", "templates/gate-report.md",
            "templates/handoff-deploy.md", "flow-skills/release-deploy-reporting/SKILL.md",
            "policies/gate-contracts.yml"]
f = [f"census omits {c}" for c in CARRIERS if c not in census]
if "not authenticate the operator" not in census.lower():
    f.append("census does not state the evidence limit — it reads as an authenticity claim")
v["ac13-census-records-every-reader-and-report-writer"] = f

print(json.dumps(v))
PY
)"

# ---- Phase C: one row per assertion; a MISSING row is a FAIL, never a silent skip -------
ROWS="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$VERDICTS" <<'PY'
import json, sys
EXPECTED = [
    "ac11-digest-covers-the-exact-validated-bytes",
    "ac11-locked-field-set-complete-and-in-order",
    "ac11-copied-fields-carry-the-stored-values",
    "ac11-no-invented-stored-field-names",
    "ac11-computed-observations-labelled-and-correct",
    "ac11-deploy-hash-bound-and-placeholders-refused",
    "ac11-verifier-rejects-ghost-fields-and-mislabels",
    "ac12-emitted-evidence-carries-no-local-path",
    "ac12-old-assertion-only-shape-rejected",
    "ac12-conforming-report-accepted [CONTROL]",
    "ac12-gate-and-artifact-unchanged-by-emission",
    "ac12-expired-approval-not-laundered",
    "ac12-unverifiable-binding-emits-no-receipt",
    "ac13-deploy-report-template-carries-the-receipt",
    "ac13-census-records-every-reader-and-report-writer",
]
raw = sys.argv[1]
try:
    v = json.loads(raw)
except ValueError:
    v = None
for row in EXPECTED:
    if v is None:
        print(f"FAIL: approval-receipt {row} (assertion block did not run: {raw[:300]!r})")
    elif row not in v:
        print(f"FAIL: approval-receipt {row} (MISSING ROW — the assertion never executed)")
    elif v[row]:
        print(f"FAIL: approval-receipt {row} ({'; '.join(v[row])})")
    else:
        print(f"PASS: approval-receipt {row}")
PY
)"
printf '%s\n' "$ROWS"
pass=$((pass + $(printf '%s\n' "$ROWS" | grep -c '^PASS: ')))
fail=$((fail + $(printf '%s\n' "$ROWS" | grep -c '^FAIL: ')))

rm -rf "$REPO" "$OUT"
finish
