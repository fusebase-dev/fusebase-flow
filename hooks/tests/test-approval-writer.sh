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

# Traversal / unsafe slugs -> exit 2, NO file created, and the SLUG is the stated reason.
# TRIPWIRE (T32): pass a VALID --command here. Without it the K19 mandatory-command check
# also exits 2, so a build with slug validation deleted would still pass this block on the
# wrong rejection — the assertion would stop constraining slug safety entirely.
writer_err() { ( cd "$WRITER_REPO" && bash hooks/local/approve-local.sh "$@" 2>&1 >/dev/null ); }
slug_fails=""
for badslug in '../escape' 'a/b' 'has space' '' "$(printf 'x%.0s' $(seq 1 65))" 'semi;colon'; do
  if writer production_deploy "$badslug" 'x' --command 'fusebase deploy'; then
    slug_fails="$slug_fails [accepted:$badslug]"
  else
    # An EMPTY slug is caught one layer earlier, by the shell usage guard (a required
    # positional is absent); every other unsafe slug must hit the slug regex.
    want='ERROR: slug'; [ -z "$badslug" ] && want='Usage:'
    printf '%s' "$(writer_err production_deploy "$badslug" 'x' --command 'fusebase deploy')" \
      | grep -q "$want" ||
    slug_fails="$slug_fails [not-a-slug-rejection:$badslug]"
  fi
done
if [ -z "$slug_fails" ] && [ "$(approvals_count)" = "0" ]; then
  ok "ac10-unsafe-slug-rejected"
else
  bad "ac10-unsafe-slug-rejected" "$slug_fails count=$(approvals_count)"
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
    Verdict, compute_command_digest, compute_repo_id, evaluate_artifact, load, now_utc,
    parse_expiry,
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
        # M9: created_at is written by the writer and must parse through the SAME parser the
        # age report uses. Without it every new artifact reads as unknown-age forever.
        created = parse_expiry(d.get("created_at"))
        if created is None:
            fails.append(f"created_at absent or unparseable: {d.get('created_at')!r}")
        elif abs((now_utc() - created).total_seconds()) > 600:
            fails.append(f"created_at is not the mint time: {d.get('created_at')!r}")
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

# M9 tighten-only, days edition: LOWER days = TIGHTER. Lower/equal is accepted; a raised or
# invalid value must RAISE, never be silently coerced to the shipped value (a coercion is
# indistinguishable from acceptance to whoever wrote the override).
from shared.policy_loader import get_policy  # noqa: E402


def merged_with(local_value) -> object:
    """Returns the merged threshold, or the exception a rejected override raised."""
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        (tmp / "policies").mkdir(parents=True)
        (tmp / "policies" / "approval-policy.yml").write_text(
            yaml.safe_dump({"stale_approval_warn_after_days": 7,
                            "local_override_may_relax": False}), encoding="utf-8")
        (tmp / "policies" / "approval-policy.local.yml").write_text(
            yaml.safe_dump({"stale_approval_warn_after_days": local_value}), encoding="utf-8")
        reset_cache()
        try:
            return get_policy("approval-policy", root=tmp).get("stale_approval_warn_after_days")
        except Exception as e:                       # noqa: BLE001 — the rejection IS the result
            return e
        finally:
            reset_cache()


shipped = yaml.safe_load(
    (root / "policies" / "approval-policy.yml").read_text(encoding="utf-8")
).get("stale_approval_warn_after_days")
if shipped != 7:
    fails.append(f"shipped stale_approval_warn_after_days should be 7, got {shipped!r}")
for lower in (1, 3, 7):
    got = merged_with(lower)
    if got != lower:
        fails.append(f"tighten-only-days: a lowered/equal override ({lower}) was not honored: {got!r}")
for relaxing in (8, 30, 365, 0, -1, True, False, "7", 7.5, None, [7]):
    got = merged_with(relaxing)
    if not isinstance(got, Exception):
        fails.append(f"tighten-only-days: {relaxing!r} was ACCEPTED (merged={got!r}) — a raised "
                     f"or invalid threshold must be rejected with a policy error")
    elif "stale_approval_warn_after_days" not in str(got):
        fails.append(f"tighten-only-days: {relaxing!r} was rejected without naming the key: {got!r}")

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

# ---- 8. M9 / FR-07: an unloadable approval policy fails CLOSED in the CONSUMER ------
# Section 6 proves the loader RAISES on a raised/invalid threshold. This is the other half the
# review found fail-open: path_policy swallowed that raise and read strict=False, so a local file
# that ENABLES strict_approvals disabled its own strict mode. A loader-level test cannot see it —
# these assertions go through path_policy.evaluate / has_active_exception, with a VALID artifact
# on disk so the deny can only come from the policy error.
P5="$(mktemp -d)"
mkdir -p "$P5/hooks/shared" "$P5/policies" "$P5/state/approvals"
cp "$ROOT/hooks/shared/"*.py "$P5/hooks/shared/"
: > "$P5/hooks/shared/__init__.py"
cp "$ROOT/policies/approval-policy.yml" "$ROOT/policies/protected-paths.yml" "$P5/policies/"
( cd "$P5" && git init -q && git config user.email t@t.t && git config user.name t )
P5_NATIVE="$( cd "$P5" && { pwd -W 2>/dev/null || pwd; } )"
MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$P5_NATIVE" <<'PY'
import datetime, json, sys
from pathlib import Path
now = datetime.datetime.now(datetime.timezone.utc)
FMT = "%Y-%m-%dT%H:%M:%SZ"
art = {"schema_version": 2, "action": "protected_path_edit", "approved_by": "operator",
       "scope": "r5-consumer-failclosed", "reason": "fixture", "paths": [".env"],
       "created_at": now.strftime(FMT),
       "expires_at": (now + datetime.timedelta(days=2)).strftime(FMT)}
out = Path(sys.argv[1]) / "state" / "approvals" / "protected_path_edit-r5-20260730.json"
out.write_text(json.dumps(art, indent=2) + "\n", encoding="utf-8")
PY
r5_probe() {   # -> "<evaluate-decision>|<raised|no-raise>|<reason-names-the-policy>"
  ( cd "$P5" && MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - <<'PY' 2>&1
import sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd() / "hooks"))
from shared.path_policy import evaluate, has_active_exception
try:                                  # absent in a pre-fix build: keep the probe on the
    from shared.path_policy import ApprovalPolicyError   # SUBSTANTIVE assertion, not an ImportError
except ImportError:
    class ApprovalPolicyError(Exception):
        pass
d = evaluate(".env")
try:
    has_active_exception(".env", Path.cwd(), category="env_and_secrets")
    raised = "no-raise"
except ApprovalPolicyError:
    raised = "raised"
print(f"{d.decision}|{raised}|{'approval-policy' in (d.reason or '')}")
PY
)
}
R5_CONTROL="$(r5_probe)"
printf 'strict_approvals: true\nstale_approval_warn_after_days: 30\n' > "$P5/policies/approval-policy.local.yml"
R5_BROKEN="$(r5_probe)"
r5_fail=""
[ "$R5_CONTROL" = "allow|no-raise|False" ] \
  || r5_fail="$r5_fail [PRECONDITION: with a loadable policy the artifact must AUTHORIZE .env, got '$R5_CONTROL' — otherwise the deny below proves nothing]"
case "$R5_BROKEN" in
  "deny|raised|True") ;;
  *) r5_fail="$r5_fail [an unloadable approval policy did not fail closed: got '$R5_BROKEN', want 'deny|raised|True' (a local file that ENABLES strict_approvals must never end up disabling it)]" ;;
esac
rm -rf "$P5"
if [ -z "$r5_fail" ]; then
  ok "m9-consumer-fails-closed-on-an-unloadable-approval-policy (path_policy denies + raises; the same artifact authorizes when the policy loads)"
else
  bad "m9-consumer-fails-closed-on-an-unloadable-approval-policy" "$r5_fail"
fi

# ---- 9. MAJOR 11: the DOCUMENTED protected-path approval path must actually authorize ----
# final-architecture-review finding 11: no shipped writer could mint the Step-6 FR-07 approval
# as documented. approve-local.sh emitted no `paths` (so path_policy's membership test could
# never match) AND recorded a `repo_id` the consumer never passed (so evaluate_artifact returned
# BINDING_MISMATCH for every artifact it wrote). Both failures were SILENT — the writer printed
# "artifact written + re-verified". These rows are red against that tree.
P6="$(mktemp -d)"
mkdir -p "$P6/hooks/local" "$P6/hooks/shared" "$P6/policies" "$P6/.github/workflows"
cp "$ROOT/hooks/local/approve-local.sh" "$ROOT/hooks/local/write-bootstrap-approval.sh" "$P6/hooks/local/"
cp "$ROOT/hooks/shared/"*.py "$P6/hooks/shared/"
: > "$P6/hooks/shared/__init__.py"
cp "$ROOT/policies/approval-policy.yml" "$ROOT/policies/protected-paths.yml" \
   "$ROOT/policies/command-policy.yml" "$P6/policies/"
( cd "$P6" && git init -q && git config user.email t@t.t && git config user.name t )

p6_allows() {   # p6_allows <path> -> 0 iff path_policy would ALLOW editing it
  ( cd "$P6" && MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$1" <<'PY' >/dev/null 2>&1
import sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd() / "hooks"))
from shared.path_policy import evaluate
sys.exit(0 if evaluate(sys.argv[1], root=Path.cwd()).decision == "allow" else 1)
PY
  )
}

# 9a. DISCRIMINATOR — the writer's own artifact must be accepted by the consumer that reads it.
# Pre-fix this was False for BOTH reasons above; the artifact existed and authorized nothing.
( cd "$P6" && bash hooks/local/approve-local.sh protected_path_edit m11 'fixture' \
    --path vercel.json >/dev/null 2>&1 )
if p6_allows vercel.json; then
  ok "m11-approve-local-artifact-is-honored-by-path-policy [DISCRIMINATOR] (writer emits \`paths\`; consumer verifies the recorded repo_id instead of rejecting it)"
else
  bad "m11-approve-local-artifact-is-honored-by-path-policy" "the documented writer produced an artifact path_policy still refuses — the sanctioned FR-07 path does not work"
fi

# 9b. CONTROL — repo binding still means something: the same artifact must not travel.
P6_OTHER="$(mktemp -d)"
mkdir -p "$P6_OTHER/hooks" "$P6_OTHER/policies" "$P6_OTHER/state/approvals"
cp -R "$P6/hooks/shared" "$P6_OTHER/hooks/"
cp "$P6/policies/"*.yml "$P6_OTHER/policies/"
cp "$P6/state/approvals/"protected_path_edit-m11-*.json "$P6_OTHER/state/approvals/" 2>/dev/null
( cd "$P6_OTHER" && git init -q && git config user.email t@t.t && git config user.name t )
if ( cd "$P6_OTHER" && MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - <<'PY' >/dev/null 2>&1
import sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd() / "hooks"))
from shared.path_policy import evaluate
sys.exit(0 if evaluate("vercel.json", root=Path.cwd()).decision == "allow" else 1)
PY
); then
  bad "m11-repo-binding-still-rejects-a-foreign-checkout" "an artifact minted in another repository authorized an edit here — repo_id became decorative"
else
  ok "m11-repo-binding-still-rejects-a-foreign-checkout [CONTROL] (the recorded repo_id is verified, not ignored)"
fi
rm -rf "$P6_OTHER"

# 9c. DISCRIMINATOR — a pathless protected_path_edit must be REFUSED, not written.
if ( cd "$P6" && bash hooks/local/approve-local.sh protected_path_edit m11b 'fixture' >/dev/null 2>&1 ); then
  bad "m11-pathless-protected-approval-refused" "the writer produced a protected_path_edit artifact with no \`paths\` — a gate-shaped file that gates nothing"
elif ls "$P6/state/approvals/"protected_path_edit-m11b-*.json >/dev/null 2>&1; then
  bad "m11-pathless-protected-approval-refused" "exit was nonzero but an artifact was written anyway"
else
  ok "m11-pathless-protected-approval-refused [DISCRIMINATOR] (no --path => exit 2, no file, and the reason names the membership contract)"
fi

# 9d. DISCRIMINATOR — a digest-bound category must be redirected, never plain-minted.
# TRIPWIRE: capture stderr to a VARIABLE, never `cmd | grep` — this file runs under
# `pipefail`, so the writer's (correct) exit 2 would become the pipeline status and the
# assertion would report "no redirect" for a redirect that was printed.
m11c_err="$( cd "$P6" && bash hooks/local/approve-local.sh protected_path_edit m11c 'fixture' \
               --path .github/workflows/x.yml 2>&1 >/dev/null )"
m11c_rc=$?
if [ "$m11c_rc" -eq 0 ]; then
  bad "m11-digest-bound-category-redirected" "approve-local minted a REUSABLE artifact for a digest-bound category"
elif printf '%s' "$m11c_err" | grep -q "write-bootstrap-approval.sh --category ci_cd_config"; then
  ok "m11-digest-bound-category-redirected [DISCRIMINATOR] (a workflow path is refused here and routed to the single-use writer by name)"
else
  bad "m11-digest-bound-category-redirected" "refused, but without naming the writer that CAN mint it — the documented path stays broken and silent"
fi

# 9e. DISCRIMINATOR — the single-use writer must cover ci_cd_config, and bind to THIS changeset.
# Before this change it collected fusebase_flow_internals paths only, so the published
# protocol ("mint the digest-bound approval for a .github/workflows edit") had no implementation.
printf 'name: x\non: workflow_dispatch\njobs: {}\n' > "$P6/.github/workflows/x.yml"
( cd "$P6" && git add .github/workflows/x.yml >/dev/null 2>&1 )
( cd "$P6" && bash hooks/local/write-bootstrap-approval.sh --category ci_cd_config >/dev/null 2>&1 )
m11_minted=0
if ! ls "$P6/state/approvals/"protected_path_edit-ci-workflow-*.json >/dev/null 2>&1; then
  bad "m11-workflow-approval-mintable" "write-bootstrap-approval.sh --category ci_cd_config minted nothing for a staged workflow edit"
elif p6_allows .github/workflows/x.yml; then
  m11_minted=1
  ok "m11-workflow-approval-mintable [DISCRIMINATOR] (a staged .github/workflows edit gets a digest-bound, single-use approval the gate honors)"
else
  bad "m11-workflow-approval-mintable" "an artifact was minted but path_policy still denies the staged workflow edit"
fi

# 9f. DISCRIMINATOR — single-use: change the staged content and the SAME artifact must deny.
# TRIPWIRE: gated on 9e. Without the precondition this row is VACUOUSLY green on any tree
# where no artifact was minted at all — "still denies" would prove nothing about the binding.
printf 'name: x\non: workflow_dispatch\njobs: {}\n# drifted after approval\n' > "$P6/.github/workflows/x.yml"
( cd "$P6" && git add .github/workflows/x.yml >/dev/null 2>&1 )
if [ "$m11_minted" -ne 1 ]; then
  bad "m11-workflow-approval-is-single-use" "no honored workflow approval existed to invalidate, so this row could not discriminate (reported red, never as a pass)"
elif p6_allows .github/workflows/x.yml; then
  bad "m11-workflow-approval-is-single-use" "the workflow approval survived a change to the staged content — it is a reusable FR-07 bypass, not a digest binding"
else
  ok "m11-workflow-approval-is-single-use [DISCRIMINATOR] (staged content changed => tree_digest no longer matches => still DENIES)"
fi
rm -rf "$P6"

finish
