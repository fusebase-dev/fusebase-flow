#!/usr/bin/env bash
# Fusebase Flow — approval WRITER + inventory tests (approve-local.sh, --inventory, AC19 docs).
# Spec: docs/specs/approval-binding-and-upgrade-classification/spec.md (AC10, AC12, AC19, AC22).
#
# Split out of test-approval-binding.sh on the loader-vs-writer seam (FR-25 ceiling).
# The loader/verdict/binding/denial-message half stays in test-approval-binding.sh.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: approval-writer <name>" / "FAIL: approval-writer <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: approval-writer $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: approval-writer $1 (${2:-})"; }
finish() { echo "[test-approval-writer] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: approval-writer skipped-no-python3"; pass=1; finish; }


# ---- 5. AC10: the writer survives adversarial input and validates before writing ---
# A REAL scratch git repo, because approve-local.sh resolves its root via git.
WRITER_REPO="$(mktemp -d)"
mkdir -p "$WRITER_REPO/hooks/local" "$WRITER_REPO/hooks/shared" "$WRITER_REPO/policies"
cp "$ROOT/hooks/local/approve-local.sh" "$WRITER_REPO/hooks/local/"
cp "$ROOT/hooks/shared/"*.py            "$WRITER_REPO/hooks/shared/"
: > "$WRITER_REPO/hooks/shared/__init__.py"
cp "$ROOT/policies/approval-policy.yml" "$WRITER_REPO/policies/"
cp "$ROOT/policies/command-policy.yml"  "$WRITER_REPO/policies/"
( cd "$WRITER_REPO" && git init -q && git config user.email t@t.t && git config user.name t )
# TRIPWIRE (MSYS): the python assertions below run under WINDOWS python, which cannot
# resolve an MSYS "/tmp/..." path. Hand them the native form or every glob silently
# returns nothing and the test passes/fails for the wrong reason.
WRITER_REPO_NATIVE="$( cd "$WRITER_REPO" && { pwd -W 2>/dev/null || pwd; } )"

writer() { ( cd "$WRITER_REPO" && bash hooks/local/approve-local.sh "$@" >/dev/null 2>&1 ); }
approvals_count() { find "$WRITER_REPO/state/approvals" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# Unknown action -> exit 2 and NO file created.
if writer not_a_real_action myslug 'x'; then
  bad "ac10-unknown-action-rejected" "exit 0 for an unknown action"
elif [ "$(approvals_count)" != "0" ]; then
  bad "ac10-unknown-action-rejected" "an artifact was written for an unknown action"
else
  ok "ac10-unknown-action-rejected"
fi

# Traversal / unsafe slugs -> exit 2 and NO file created.
slug_fails=""
for badslug in '../escape' 'a/b' 'has space' '' "$(printf 'x%.0s' $(seq 1 65))" 'semi;colon'; do
  if writer production_deploy "$badslug" 'x'; then slug_fails="$slug_fails [$badslug]"; fi
done
if [ -z "$slug_fails" ] && [ "$(approvals_count)" = "0" ]; then
  ok "ac10-unsafe-slug-rejected"
else
  bad "ac10-unsafe-slug-rejected" "accepted:$slug_fails count=$(approvals_count)"
fi

# AC22 / K19 discriminator: a command-gated action WITHOUT --command must exit 2 and
# write nothing. Pre-correction this exited 0 and wrote an unbound, replayable artifact.
if writer production_deploy s1 'r'; then
  bad "ac22-command-mandatory-for-gated-action" "exit 0 without --command"
elif [ "$(approvals_count)" != "0" ]; then
  bad "ac22-command-mandatory-for-gated-action" "an unbound artifact was written"
else
  ok "ac22-command-mandatory-for-gated-action"
fi

# ...and a NON command-gated action is unaffected (no false positive).
if writer secret_file_write s2 'r' && [ "$(approvals_count)" = "1" ]; then
  ok "ac22-non-gated-action-still-optional"
else
  bad "ac22-non-gated-action-still-optional" "count=$(approvals_count)"
fi
rm -f "$WRITER_REPO"/state/approvals/*.json

# Adversarial reason: quotes, backslash, newline, command substitution, unicode — the
# artifact must still parse and the value must round-trip EXACTLY.
ADV_REASON='he said "yes" \ then $(id) `whoami`
second line — приветÜñî 🚀'
( cd "$WRITER_REPO" && bash hooks/local/approve-local.sh production_deploy adv-slug "$ADV_REASON" \
    --command 'fusebase deploy' >/dev/null 2>&1 )
ADV_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" "$WRITER_REPO_NATIVE" "$ADV_REASON" <<'PY' 2>&1
import json, sys
from pathlib import Path
root, repo, expected_reason = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
sys.path.insert(0, str(root / "hooks"))
from shared.approval_artifact import (  # noqa: E402
    Verdict, compute_command_digest, compute_repo_id, evaluate_artifact, load,
)
fails = []
files = sorted((repo / "state" / "approvals").glob("production_deploy-adv-slug-*.json"))
if len(files) != 1:
    fails.append(f"expected exactly 1 artifact, found {len(files)}")
else:
    art = load(files[0])
    if art is None or art.data is None:
        fails.append("artifact did not parse as a JSON object")
    else:
        d = art.data
        if d.get("reason") != expected_reason:
            fails.append(f"reason did not round-trip exactly: {d.get('reason')!r}")
        if d.get("schema_version") != 2:
            fails.append(f"expected schema_version 2, got {d.get('schema_version')!r}")
        if d.get("action") != "production_deploy":
            fails.append("body action missing/disagrees with the filename")
        if d.get("repo_id") != compute_repo_id(repo):
            fails.append("repo_id absent or not bound to this repo")
        if d.get("command_digest") != compute_command_digest("fusebase deploy"):
            fails.append("command_digest absent or wrong")
        v = evaluate_artifact(d, expected_action="production_deploy",
                              command_digest=compute_command_digest("fusebase deploy"),
                              repo_id=compute_repo_id(repo))
        if v is not Verdict.VALID:
            fails.append(f"freshly written artifact is not VALID: {v}")
# No temp files left behind.
leftovers = list((repo / "state" / "approvals").glob(".approve-local-*"))
if leftovers:
    fails.append(f"temp files left behind: {[p.name for p in leftovers]}")
print(json.dumps(fails))
PY
)"
if [ "$ADV_OUT" = "[]" ]; then
  ok "ac10-adversarial-values-round-trip"
else
  bad "ac10-adversarial-values-round-trip" "$ADV_OUT"
fi
# AC22(c) end-to-end: run the EMITTED resolving invocation verbatim, then re-run the
# blocked command -> allow; a one-character-different command -> deny.
rm -f "$WRITER_REPO"/state/approvals/*.json
# The emitted invocation is rendered by python, then executed by THIS shell — a Windows
# python cannot spawn MSYS bash (it resolves to WSL), so the round-trip must cross back.
FIX_LINE="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" "$WRITER_REPO_NATIVE" <<'PY' 2>/dev/null
import sys
from pathlib import Path
root, repo = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(root / "hooks"))
from shared.command_policy import evaluate  # noqa: E402
from shared.denial_message import render_approval_denial  # noqa: E402
BLOCKED = "fusebase deploy --app 'safe  prod'"
dec = evaluate(BLOCKED, root=repo)
assert dec.decision == "deny", dec.decision
print(render_approval_denial(BLOCKED, dec.all_required_actions, dec.action_verdicts,
                             unsatisfied_actions=dec.required_actions,
                             slug="e2e").splitlines()[-1].strip())
PY
)"
( cd "$WRITER_REPO" && eval "$FIX_LINE" >/dev/null 2>&1 )
E2E_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" "$WRITER_REPO_NATIVE" "$FIX_LINE" <<'PY' 2>&1
import json, sys
from pathlib import Path
root, repo, fix = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
sys.path.insert(0, str(root / "hooks"))
from shared.command_policy import evaluate  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402
fails = []
BLOCKED = "fusebase deploy --app 'safe  prod'"
if "--command '" not in fix:
    fails.append(f"e2e-fix-line-unbound: {fix!r}")
reset_cache()
if evaluate(BLOCKED, root=repo).decision != "allow":
    fails.append("e2e-roundtrip: the emitted invocation did not authorize the blocked command")
reset_cache()
if evaluate("fusebase deploy --app 'safe prod'", root=repo).decision != "deny":
    fails.append("e2e-one-char-different: a different command was authorized")
print(json.dumps(fails))
PY
)"
if [ "$E2E_OUT" = "[]" ]; then
  ok "ac22-emitted-invocation-round-trips"
else
  bad "ac22-emitted-invocation-round-trips" "$E2E_OUT"
fi

rm -rf "$WRITER_REPO"

# ---- 6. AC12: the inventory names every artifact and the strict reject count -------
INV_REPO="$(mktemp -d)"
INV_REPO_NATIVE="$( cd "$INV_REPO" && { pwd -W 2>/dev/null || pwd; } )"
mkdir -p "$INV_REPO/state/approvals"
cat > "$INV_REPO/state/approvals/production_deploy-good-20260728.json" <<'EOF'
{"schema_version":2,"action":"production_deploy","expires_at":"2099-01-01T00:00:00Z"}
EOF
cat > "$INV_REPO/state/approvals/production_deploy-legacy-20260728.json" <<'EOF'
{"action":"production_deploy"}
EOF
cat > "$INV_REPO/state/approvals/production_deploy-stale-20260728.json" <<'EOF'
{"action":"production_deploy","expires_at":"2000-01-01T00:00:00Z"}
EOF
printf '[1,2,3]' > "$INV_REPO/state/approvals/production_deploy-broken-20260728.json"
INV="$(python3 "$ROOT/hooks/local/lib/approval_inventory.py" --root "$INV_REPO_NATIVE" 2>&1)"
inv_fail=""
for needle in "production_deploy-good-20260728.json" "production_deploy-legacy-20260728.json" \
              "production_deploy-stale-20260728.json" "production_deploy-broken-20260728.json" \
              "legacy-no-expiry" "expired" "MALFORMED" "MISSING_EXPIRY" "EXPIRED" \
              "3 would be REJECTED"; do
  case "$INV" in *"$needle"*) ;; *) inv_fail="$inv_fail [$needle]" ;; esac
done
case "$INV" in *"ACCEPT"*) ;; *) inv_fail="$inv_fail [no ACCEPT row]" ;; esac
if [ -z "$inv_fail" ]; then
  ok "ac12-inventory-four-verdicts-and-reject-count"
else
  bad "ac12-inventory-four-verdicts-and-reject-count" "missing:$inv_fail"
fi

# AC27 / T24 discriminator: the inventory must never print ACCEPT for something the gate
# rejects. Pre-correction BOTH binding fields were stripped on mismatch, so a foreign-repo
# artifact AND a command-bound artifact both printed ACCEPT.
INV2_REPO="$(mktemp -d)"
INV2_NATIVE="$( cd "$INV2_REPO" && { pwd -W 2>/dev/null || pwd; } )"
mkdir -p "$INV2_REPO/state/approvals"
MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" "$INV2_NATIVE" <<'PY' >/dev/null 2>&1
import json, sys
from pathlib import Path
root, repo = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(root / "hooks"))
from shared.approval_artifact import compute_command_digest, compute_repo_id  # noqa: E402
d = repo / "state" / "approvals"
base = {"schema_version": 2, "action": "production_deploy",
        "expires_at": "2099-01-01T00:00:00Z"}
(d / "production_deploy-foreignrepo-20260728.json").write_text(
    json.dumps(dict(base, repo_id=compute_repo_id(repo / "somewhere" / "else"))), encoding="utf-8")
(d / "production_deploy-cmdbound-20260728.json").write_text(
    json.dumps(dict(base, repo_id=compute_repo_id(repo),
                    command_digest=compute_command_digest("fusebase deploy"))), encoding="utf-8")
(d / "production_deploy-plain-20260728.json").write_text(
    json.dumps(dict(base, repo_id=compute_repo_id(repo))), encoding="utf-8")
PY
INV2="$(python3 "$ROOT/hooks/local/lib/approval_inventory.py" --root "$INV2_NATIVE" 2>&1)"
inv2_fail=""
case "$(echo "$INV2" | grep foreignrepo)" in
  *"REJECT (BINDING_MISMATCH)"*) ;; *) inv2_fail="$inv2_fail [foreign repo_id not REJECTed]" ;;
esac
case "$(echo "$INV2" | grep cmdbound)" in
  *"UNCHECKED (command-bound)"*) ;; *) inv2_fail="$inv2_fail [command-bound row not UNCHECKED]" ;;
esac
case "$(echo "$INV2" | grep 'plain')" in
  *ACCEPT*) ;; *) inv2_fail="$inv2_fail [valid repo-bound row is not ACCEPT]" ;;
esac
if [ -z "$inv2_fail" ]; then
  ok "ac27-inventory-never-accepts-a-gate-rejected-artifact"
else
  bad "ac27-inventory-never-accepts-a-gate-rejected-artifact" "$inv2_fail
$INV2"
fi
rm -rf "$INV2_REPO"

# Strict really denies what compat allows, and the compat acceptance is LOGGED (K7).
STRICT_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, shutil, sys, tempfile
from pathlib import Path
import yaml
root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks"))
from shared.command_policy import evaluate  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402
fails = []


def repo_with(tmp: Path, strict: bool) -> Path:
    (tmp / "policies").mkdir(parents=True)
    (tmp / "state" / "approvals").mkdir(parents=True)
    shutil.copy(root / "policies" / "command-policy.yml", tmp / "policies" / "command-policy.yml")
    appr = yaml.safe_load((root / "policies" / "approval-policy.yml").read_text(encoding="utf-8"))
    appr["strict_approvals"] = strict
    (tmp / "policies" / "approval-policy.yml").write_text(yaml.safe_dump(appr), encoding="utf-8")
    (tmp / "state" / "approvals" / "production_deploy-legacy-20260728.json").write_text(
        json.dumps({"action": "production_deploy"}), encoding="utf-8")
    reset_cache()
    return tmp


with tempfile.TemporaryDirectory() as d:
    repo = repo_with(Path(d), strict=False)
    dec = evaluate("fusebase deploy", root=repo)
    if dec.decision != "allow":
        fails.append(f"compat: expiry-less artifact should be allowed, got {dec.decision}")
    log = repo / "state" / "audit.log.jsonl"
    if not log.is_file():
        fails.append("compat: acceptance was SILENT — K7 requires an audit entry")
    else:
        text = log.read_text(encoding="utf-8")
        if "approval_legacy_accepted" not in text or "MISSING_EXPIRY" not in text:
            fails.append(f"compat: audit entry missing the legacy-acceptance record: {text[:200]}")

with tempfile.TemporaryDirectory() as d:
    repo = repo_with(Path(d), strict=True)
    dec = evaluate("fusebase deploy", root=repo)
    if dec.decision != "deny":
        fails.append(f"strict: expiry-less artifact must be rejected, got {dec.decision}")
    if dec.approval_verdict != "MISSING_EXPIRY":
        fails.append(f"strict: expected MISSING_EXPIRY verdict, got {dec.approval_verdict!r}")

# Tighten-only: a local override cannot turn strict back OFF once the base is ON.
with tempfile.TemporaryDirectory() as d:
    tmp = Path(d)
    (tmp / "policies").mkdir(parents=True)
    (tmp / "policies" / "approval-policy.yml").write_text(
        yaml.safe_dump({"strict_approvals": True, "local_override_may_relax": False}),
        encoding="utf-8")
    (tmp / "policies" / "approval-policy.local.yml").write_text(
        yaml.safe_dump({"strict_approvals": False}), encoding="utf-8")
    reset_cache()
    from shared.policy_loader import get_policy  # noqa: E402
    merged = get_policy("approval-policy", root=tmp)
    if merged.get("strict_approvals") is not True:
        fails.append("tighten-only: a local override relaxed strict_approvals back to false")
    reset_cache()

print(json.dumps(fails))
PY
)"
if [ "$STRICT_OUT" = "[]" ]; then
  ok "ac12-strict-vs-compat-and-audited-legacy-acceptance"
else
  bad "ac12-strict-vs-compat-and-audited-legacy-acceptance" "$STRICT_OUT"
fi
rm -rf "$INV_REPO"

# ---- 7. AC19: no authorship-enforcement claim survives in the canonical files ------
AC19_FILES=(
  "policies/approval-policy.yml"
  "flow-skills/role-discipline/references/deploy.md"
  "workflows/greenlight-deploy.md"
)
ac19_hits=""
for f in "${AC19_FILES[@]}"; do
  if grep -nEi "hooks? (check|enforce|verif)[a-z]* this against|against the self-attested role" "$ROOT/$f" >/dev/null 2>&1; then
    ac19_hits="$ac19_hits $f"
  fi
done
if [ -z "$ac19_hits" ]; then
  ok "ac19-no-authorship-enforcement-claim"
else
  bad "ac19-no-authorship-enforcement-claim" "claim survives in:$ac19_hits"
fi
if grep -q "enforced_by_hooks: false" "$ROOT/policies/approval-policy.yml"; then
  ok "ac19-approval-authors-marked-declarative"
else
  bad "ac19-approval-authors-marked-declarative" "approval_authors is not marked enforced_by_hooks: false"
fi

finish
