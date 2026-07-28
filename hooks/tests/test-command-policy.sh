#!/usr/bin/env bash
# Fusebase Flow — command-policy fail-closed + all-match tests.
# Spec: docs/specs/approval-binding-and-upgrade-classification/spec.md (AC5..AC8).
#
# Drives the REAL hooks/shared/command_policy.py against throwaway policy trees, so a
# rule-matching regression fails here rather than at a consumer's deploy gate.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: command-policy <name>" / "FAIL: command-policy <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: command-policy $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: command-policy $1 (${2:-})"; }
finish() { echo "[test-command-policy] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: command-policy skipped-no-python3"; pass=1; finish; }

# ---- AC5 fail-closed · AC6 all-match · AC7 SQL · K16 fallthrough removal ----------
OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, shutil, sys, tempfile
from pathlib import Path
import yaml

root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks"))
from shared.command_policy import POLICY_ERROR_RULE_ID, evaluate  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402

FUTURE = "2099-01-01T00:00:00Z"
fails = []


def make_repo(tmp: Path, *, command_policy=None) -> Path:
    (tmp / "policies").mkdir(parents=True)
    (tmp / "state" / "approvals").mkdir(parents=True)
    shutil.copy(root / "policies" / "approval-policy.yml", tmp / "policies" / "approval-policy.yml")
    if command_policy is None:
        shutil.copy(root / "policies" / "command-policy.yml", tmp / "policies" / "command-policy.yml")
    elif isinstance(command_policy, str):
        (tmp / "policies" / "command-policy.yml").write_text(command_policy, encoding="utf-8")
    else:
        (tmp / "policies" / "command-policy.yml").write_text(
            yaml.safe_dump(command_policy), encoding="utf-8")
    reset_cache()
    return tmp


def mint(repo: Path, action: str, slug: str = "t") -> None:
    (repo / "state" / "approvals" / f"{action}-{slug}-20260728.json").write_text(
        json.dumps({"action": action, "expires_at": FUTURE}), encoding="utf-8")


def decide(repo: Path, command: str):
    reset_cache()
    return evaluate(command, root=repo)


def expect(label, dec, decision=None, rule_id=None, required=None, reason_has=()):
    if decision is not None and dec.decision != decision:
        fails.append(f"{label}: expected {decision} got {dec.decision} ({dec.reason})")
    if rule_id is not None and dec.rule_id != rule_id:
        fails.append(f"{label}: expected rule_id {rule_id} got {dec.rule_id}")
    if required is not None and sorted(dec.required_actions) != sorted(required):
        fails.append(f"{label}: expected required {sorted(required)} got {sorted(dec.required_actions)}")
    for needle in reason_has:
        if needle not in dec.reason:
            fails.append(f"{label}: reason missing {needle!r} -> {dec.reason}")


BROKEN = "(unclosed"

# AC5(a): a broken regex in EACH stage denies with the policy-error id, never skips.
for stage, extra in (
    ("deny", {}),
    ("require_approval", {"action": "production_deploy"}),
    ("allow", {}),
):
    pol = {"schema_version": 1,
           "deny": [], "require_approval": [], "allow": [],
           "match_order": ["deny", "require_approval", "allow"], "default": "allow"}
    pol[stage] = [dict({"pattern": BROKEN, "reason": "x", "rule_id": "X"}, **extra)]
    with tempfile.TemporaryDirectory() as d:
        repo = make_repo(Path(d), command_policy=pol)
        expect(f"ac5-broken-regex-{stage}", decide(repo, "echo hello"),
               decision="deny", rule_id=POLICY_ERROR_RULE_ID)

# AC5(a): a rule with no usable pattern denies too.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d), command_policy={
        "schema_version": 1, "deny": [{"reason": "no pattern", "rule_id": "X"}],
        "require_approval": [], "allow": [], "default": "allow"})
    expect("ac5-rule-without-pattern", decide(repo, "echo hello"),
           decision="deny", rule_id=POLICY_ERROR_RULE_ID)

# AC5(b): missing / empty / rule-less / unparseable policy all DENY, never default-allow.
for label, body in (
    ("empty-file", ""),
    ("empty-mapping", "{}\n"),
    ("no-rules", "schema_version: 1\ndefault: allow\n"),
    ("unparseable", "deny: [ this is not: valid: yaml\n"),
):
    with tempfile.TemporaryDirectory() as d:
        repo = make_repo(Path(d), command_policy=body)
        expect(f"ac5-policy-{label}", decide(repo, "echo hello"),
               decision="deny", rule_id=POLICY_ERROR_RULE_ID)

with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    (repo / "policies" / "command-policy.yml").unlink()
    reset_cache()
    expect("ac5-policy-absent-file", decide(repo, "echo hello"),
           decision="deny", rule_id=POLICY_ERROR_RULE_ID)

# AC6: compound command needs BOTH actions, named in ONE message.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    mint(repo, "production_deploy")
    expect("ac6-compound-migration-not-smuggled",
           decide(repo, "fusebase deploy && npx prisma migrate deploy"),
           decision="deny", required=["database_migration"],
           reason_has=("database_migration",))
    # ... and the same command with BOTH artifacts is allowed.
    mint(repo, "database_migration")
    expect("ac6-compound-both-artifacts",
           decide(repo, "fusebase deploy && npx prisma migrate deploy"), decision="allow")

# K16 accepted consequence: `rm` now contributes destructive_file_delete to the set.
# NOTE: the shipped rm pattern needs a flag or a double space (`rm build.log` alone
# matches nothing) — an independent pre-existing gap, filed as
# docs/backlog/rm-rule-pattern-single-space-gap/. Asserted with a form the rule
# actually matches so this case tests all-match, not the pattern.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    mint(repo, "production_deploy")
    expect("k16-compound-rm-requires-destructive-delete",
           decide(repo, "fusebase deploy && rm -r build/"),
           decision="deny", required=["destructive_file_delete"],
           reason_has=("destructive_file_delete",))

# Stage order unchanged: a denied command never reaches all-match.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    expect("k16-deny-still-short-circuits", decide(repo, "rm -rf /tmp/x"),
           decision="deny", rule_id="FR-06")

# AC7: destructive/schema SQL is case-insensitive and ALTER TABLE is gated.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    for sql in ('psql -c "drop table users"',
                'psql -c "DROP TABLE users"',
                'psql -c "DrOp TaBlE users"',
                'psql -c "ALTER TABLE users ADD COLUMN x int"',
                'psql -c "alter table users add column x int"',
                'psql -c "truncate orders"',
                'psql -c "delete from orders"'):
        expect(f"ac7-sql[{sql[:28]}]", decide(repo, sql),
               decision="deny", required=["database_migration"])
    # A non-destructive statement is still not gated.
    dec = decide(repo, 'psql -c "select 1"')
    if dec.decision != "allow":
        fails.append(f"ac7-sql-select-not-gated: got {dec.decision}")

# AC5: an unsupported per-rule flag fails CLOSED rather than being ignored.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d), command_policy={
        "schema_version": 2, "deny": [],
        "require_approval": [{"pattern": "x", "action": "production_deploy", "flags": ["s"]}],
        "allow": [], "default": "allow"})
    expect("ac5-unsupported-flag", decide(repo, "x"),
           decision="deny", rule_id=POLICY_ERROR_RULE_ID)

# AC8/K5: `any_of` is satisfied by EITHER action; neither present -> deny naming the
# rule's display action (the first listed).
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    expect("ac8-neither-artifact", decide(repo, "fusebase deploy"),
           decision="deny", required=["production_deploy"])
    mint(repo, "lightweight_deploy")
    expect("ac8-lightweight-satisfies", decide(repo, "fusebase deploy"), decision="allow")
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    mint(repo, "production_deploy")
    expect("ac8-production-still-satisfies", decide(repo, "fusebase deploy"), decision="allow")

# A rule declaring both `action` and `any_of` is a policy error, not a silent pick.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d), command_policy={
        "schema_version": 2, "deny": [],
        "require_approval": [{"pattern": r"\bfusebase\s+deploy\b", "action": "production_deploy",
                              "any_of": ["production_deploy", "lightweight_deploy"]}],
        "allow": [], "default": "allow"})
    expect("k5-action-and-any_of-mutually-exclusive", decide(repo, "fusebase deploy"),
           decision="deny", rule_id=POLICY_ERROR_RULE_ID)

# The dead key is gone from the shipped policy (K16).
shipped = yaml.safe_load((root / "policies" / "command-policy.yml").read_text(encoding="utf-8"))
if any("fallthrough" in r for r in (shipped.get("require_approval") or [])):
    fails.append("k16-fallthrough-key-still-present in the shipped command-policy.yml")

print(json.dumps(fails))
PY
)"
if [ "$OUT" = "[]" ]; then
  ok "failclosed-and-all-match"
else
  bad "failclosed-and-all-match" "$OUT"
fi

# ---- AC8 through BOTH handler entry points (not just command_policy) --------------
# The permission_request path was never covered; testing pre_tool_use alone would miss
# exactly the surface a Codex-style host uses.
HANDLER_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, shutil, subprocess, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1])
fails = []
FUTURE = "2099-01-01T00:00:00Z"
CMD = "fusebase deploy"

HANDLER_DIRS = ("hooks/handlers", "hooks/shared")


def build(tmp: Path) -> Path:
    for sub in HANDLER_DIRS:
        (tmp / sub).mkdir(parents=True, exist_ok=True)
        for f in (root / sub).iterdir():
            if f.is_file() and f.suffix == ".py":
                shutil.copy(f, tmp / sub / f.name)
    (tmp / "hooks" / "shared" / "__init__.py").touch()
    (tmp / "policies").mkdir(parents=True, exist_ok=True)
    for name in ("command-policy.yml", "approval-policy.yml", "protected-paths.yml",
                 "secret-patterns.yml"):
        src = root / "policies" / name
        if src.is_file():
            shutil.copy(src, tmp / "policies" / name)
    (tmp / "state" / "approvals").mkdir(parents=True, exist_ok=True)
    (tmp / ".git").mkdir(exist_ok=True)          # find_git_root anchor; no real repo needed
    return tmp


def mint(repo: Path, action: str) -> None:
    (repo / "state" / "approvals" / f"{action}-smoke-20260728.json").write_text(
        json.dumps({"schema_version": 2, "action": action, "expires_at": FUTURE}),
        encoding="utf-8")


def run(repo: Path, handler: str, payload: dict) -> tuple[int, dict]:
    proc = subprocess.run(
        [sys.executable, str(repo / "hooks" / "handlers" / handler)],
        input=json.dumps(payload).encode("utf-8"), capture_output=True, cwd=str(repo))
    out = proc.stdout.decode("utf-8", errors="replace")
    try:
        data = json.loads(out) if out.strip().startswith("{") else {}
    except Exception:
        data = {}
    return proc.returncode, data


def both(repo: Path, label: str, expected: str) -> None:
    rc, data = run(repo, "pre_tool_use.py",
                   {"event": "pre_tool_use", "cwd": str(repo), "tool_name": "Bash",
                    "tool_input": {"command": CMD}})
    if data.get("decision") != expected:
        fails.append(f"{label}/pre_tool_use: expected {expected} got {data.get('decision')!r}")
    rc, data = run(repo, "permission_request.py",
                   {"event": "permission_request", "cwd": str(repo),
                    "permission_request": {"tool_name": "Bash",
                                           "tool_input": {"command": CMD}}})
    if data.get("decision") != expected:
        fails.append(f"{label}/permission_request: expected {expected} got {data.get('decision')!r}")


with tempfile.TemporaryDirectory() as d:
    repo = build(Path(d))
    both(repo, "ac8-no-artifact", "deny")
    mint(repo, "lightweight_deploy")
    both(repo, "ac8-lightweight_deploy", "allow")

with tempfile.TemporaryDirectory() as d:
    repo = build(Path(d))
    mint(repo, "production_deploy")
    both(repo, "ac8-production_deploy", "allow")

print(json.dumps(fails))
PY
)"
if [ "$HANDLER_OUT" = "[]" ]; then
  ok "ac8-lightweight-parity-both-handlers"
else
  bad "ac8-lightweight-parity-both-handlers" "$HANDLER_OUT"
fi

finish
