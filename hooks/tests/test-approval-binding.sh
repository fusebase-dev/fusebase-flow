#!/usr/bin/env bash
# Fusebase Flow — approval-artifact schema, expiry, action-agreement and binding tests.
# Spec: docs/specs/approval-binding-and-upgrade-classification/spec.md (AC1..AC3, AC9..AC12, AC19).
#
# Drives the REAL hooks/shared/approval_artifact.py (and, from T3 on, command_policy)
# rather than a re-implementation, so a drift between the loader and its callers fails here.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: approval-binding <name>" / "FAIL: approval-binding <name>"; exit = fail count.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: approval-binding $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: approval-binding $1 (${2:-})"; }
finish() { echo "[test-approval-binding] $pass/$((pass + fail)) PASS"; exit $fail; }

command -v python3 >/dev/null 2>&1 || { echo "PASS: approval-binding skipped-no-python3"; pass=1; finish; }

# ---- 1. Verdict table (AC2, AC3): every state, and load() raises on nothing --------
VERDICT_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks"))
from shared.approval_artifact import (  # noqa: E402
    Verdict, evaluate_artifact, is_acceptable, load, parse_expiry, filename_action,
)

FUTURE = "2099-01-01T00:00:00Z"
PAST = "2000-01-01T00:00:00Z"
A = "production_deploy"

# (name, body, expected verdict) — body is evaluated against expected_action=A.
cases = [
    ("expiry-missing-key",      {"action": A},                              Verdict.MISSING_EXPIRY),
    ("expiry-empty-string",     {"action": A, "expires_at": ""},            Verdict.MISSING_EXPIRY),
    ("expiry-whitespace",       {"action": A, "expires_at": "   "},         Verdict.MISSING_EXPIRY),
    ("expiry-null",             {"action": A, "expires_at": None},          Verdict.MISSING_EXPIRY),
    ("expiry-integer",          {"action": A, "expires_at": 20991231},      Verdict.MALFORMED),
    ("expiry-bool",             {"action": A, "expires_at": True},          Verdict.MALFORMED),
    ("expiry-list",             {"action": A, "expires_at": [FUTURE]},      Verdict.MALFORMED),
    ("expiry-garbage",          {"action": A, "expires_at": "not-a-date"},  Verdict.MALFORMED),
    ("expiry-future-utc",       {"action": A, "expires_at": FUTURE},        Verdict.VALID),
    ("expiry-past-utc",         {"action": A, "expires_at": PAST},          Verdict.EXPIRED),
    ("expiry-future-offset",    {"action": A, "expires_at": "2099-01-01T00:00:00+02:00"}, Verdict.VALID),
    ("expiry-naive-future",     {"action": A, "expires_at": "2099-01-01T00:00:00"},       Verdict.VALID),
    ("action-mismatch",         {"action": "database_migration", "expires_at": FUTURE},   Verdict.ACTION_MISMATCH),
    ("action-absent-legacy-ok", {"expires_at": FUTURE},                     Verdict.VALID),
    ("action-non-string",       {"action": 7, "expires_at": FUTURE},        Verdict.MALFORMED),
    ("schema-v2-action-absent", {"schema_version": 2, "expires_at": FUTURE}, Verdict.MALFORMED),
    ("schema-unknown-version",  {"schema_version": 9, "action": A, "expires_at": FUTURE}, Verdict.MALFORMED),
    ("schema-non-int",          {"schema_version": "2", "action": A, "expires_at": FUTURE}, Verdict.MALFORMED),
    ("toplevel-array",          [1, 2, 3],                                  Verdict.MALFORMED),
    ("toplevel-string",         "approved",                                 Verdict.MALFORMED),
    ("toplevel-number",         42,                                         Verdict.MALFORMED),
    ("toplevel-null",           None,                                       Verdict.MALFORMED),
    ("unicode-fields-ok",       {"action": A, "expires_at": FUTURE, "reason": "приветÜñî 🚀"}, Verdict.VALID),
    # T17 discriminator (AC3): valid ISO stamps whose UTC conversion overflows the
    # datetime range. Pre-correction these raised OverflowError out of evaluate_artifact()
    # and the handler emitted NO deny.
    ("expiry-extreme-offset-hi", {"action": A, "expires_at": "9999-12-31T23:59:59-14:00"}, Verdict.MALFORMED),
    ("expiry-extreme-offset-lo", {"action": A, "expires_at": "0001-01-01T00:00:00+14:00"}, Verdict.MALFORMED),
    ("expiry-max-convertible",   {"action": A, "expires_at": "9999-12-31T23:59:59+00:00"}, Verdict.VALID),
    ("expiry-min-convertible",   {"action": A, "expires_at": "0001-01-01T00:00:00+00:00"}, Verdict.EXPIRED),
]
fails = []
for name, body, expected in cases:
    try:
        got = evaluate_artifact(body, expected_action=A)
    except BaseException as e:                      # noqa: BLE001 — the point of the test
        fails.append(f"{name}: RAISED {e!r}")
        continue
    if got is not expected:
        fails.append(f"{name}: expected {expected} got {got}")

# load() must never raise, for any file content.
with tempfile.TemporaryDirectory() as d:
    dd = Path(d)
    blobs = {
        "production_deploy-a-20260728.json": '{"action":"production_deploy"}',
        "production_deploy-b-20260728.json": "[1,2,3]",
        "production_deploy-c-20260728.json": "not json at all {{{",
        "production_deploy-d-20260728.json": "",
        "production_deploy-e-20260728.json": "\x00\x01\x02",
    }
    for fn, blob in blobs.items():
        (dd / fn).write_text(blob, encoding="utf-8", errors="replace")
    for fn in blobs:
        try:
            art = load(dd / fn)
        except BaseException as e:                  # noqa: BLE001
            fails.append(f"load-{fn}: RAISED {e!r}")
            continue
        if art is None:
            fails.append(f"load-{fn}: returned None for a readable file")
    try:
        if load(dd / "does-not-exist.json") is not None:
            fails.append("load-absent: expected None for a missing file")
    except BaseException as e:                      # noqa: BLE001
        fails.append(f"load-absent: RAISED {e!r}")

# parse_expiry never string-compares and never raises.
for bad_value in (None, 5, True, [], {}, "", "   ", "yesterday", "2026-13-45T99:99:99Z",
                  "9999-12-31T23:59:59-14:00", "0001-01-01T00:00:00+14:00"):
    try:
        if parse_expiry(bad_value) is not None:
            fails.append(f"parse_expiry({bad_value!r}) should be None")
    except BaseException as e:                      # noqa: BLE001
        fails.append(f"parse_expiry({bad_value!r}): RAISED {e!r}")

# K17 per-carrier pass-sets.
expect_accept = {
    (Verdict.VALID, False): True,   (Verdict.VALID, True): True,
    (Verdict.MISSING_EXPIRY, False): True, (Verdict.MISSING_EXPIRY, True): False,
    (Verdict.EXPIRED, False): False, (Verdict.EXPIRED, True): False,
    (Verdict.MALFORMED, False): False, (Verdict.MALFORMED, True): False,
    (Verdict.ACTION_MISMATCH, False): False, (Verdict.ACTION_MISMATCH, True): False,
    (Verdict.BINDING_MISMATCH, False): False, (Verdict.BINDING_MISMATCH, True): False,
}
for (v, strict), want in expect_accept.items():
    if is_acceptable(v, strict=strict) is not want:
        fails.append(f"is_acceptable({v},strict={strict}) expected {want}")
if any(m.name == "LEGACY_OK" for m in Verdict):
    fails.append("Verdict carries LEGACY_OK — K17 forbids mode-dependent members")

if filename_action("production_deploy-my-hyphenated-slug-20260728.json") != "production_deploy":
    fails.append("filename_action: hyphenated slug broke the action boundary")

print(json.dumps(fails))
PY
)"
if [ "$VERDICT_OUT" = "[]" ]; then
  ok "verdict-table-and-loader-total"
else
  bad "verdict-table-and-loader-total" "$VERDICT_OUT"
fi

# ---- 1b. AC3 through BOTH handlers: a far-boundary artifact denies, never tracebacks -
# The unit case above proves the verdict; this proves the handler still EMITS a decision.
# Pre-correction the OverflowError escaped and neither handler produced a deny.
BOUNDARY_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, shutil, subprocess, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1])
fails = []
CMD = "fusebase deploy"


def build(tmp: Path) -> Path:
    for sub in ("hooks/handlers", "hooks/shared"):
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
    (tmp / ".git").mkdir(exist_ok=True)
    return tmp


for stamp in ("9999-12-31T23:59:59-14:00", "0001-01-01T00:00:00+14:00"):
    with tempfile.TemporaryDirectory() as d:
        repo = build(Path(d))
        (repo / "state" / "approvals" / "production_deploy-edge-20260728.json").write_text(
            json.dumps({"schema_version": 2, "action": "production_deploy",
                        "expires_at": stamp}), encoding="utf-8")
        for handler, payload in (
            ("pre_tool_use.py", {"event": "pre_tool_use", "cwd": str(repo),
                                 "tool_name": "Bash", "tool_input": {"command": CMD}}),
            ("permission_request.py", {"event": "permission_request", "cwd": str(repo),
                                       "permission_request": {
                                           "tool_name": "Bash",
                                           "tool_input": {"command": CMD}}}),
        ):
            proc = subprocess.run([sys.executable, str(repo / "hooks" / "handlers" / handler)],
                                  input=json.dumps(payload).encode("utf-8"),
                                  capture_output=True, cwd=str(repo))
            out = proc.stdout.decode("utf-8", errors="replace")
            err = proc.stderr.decode("utf-8", errors="replace")
            if "OverflowError" in err or "Traceback" in err:
                fails.append(f"{handler}[{stamp}]: handler tracebacked -> {err.strip()[-160:]}")
            try:
                data = json.loads(out) if out.strip().startswith("{") else {}
            except Exception:
                data = {}
            if data.get("decision") != "deny":
                fails.append(f"{handler}[{stamp}]: expected deny got {data.get('decision')!r}")

print(json.dumps(fails))
PY
)"
if [ "$BOUNDARY_OUT" = "[]" ]; then
  ok "ac3-extreme-offset-denies-through-both-handlers"
else
  bad "ac3-extreme-offset-denies-through-both-handlers" "$BOUNDARY_OUT"
fi

# ---- 2. AC1 + AC4: command_policy consumes the loader; policy is root-anchored -----
CP_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, os, shutil, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks"))
from shared.command_policy import evaluate  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402

FUTURE = "2099-01-01T00:00:00Z"
fails = []


def make_repo(tmp: Path) -> Path:
    """A throwaway tree carrying the REAL shipped policies + an empty approvals dir."""
    (tmp / "policies").mkdir(parents=True)
    (tmp / "state" / "approvals").mkdir(parents=True)
    for name in ("command-policy.yml", "approval-policy.yml"):
        shutil.copy(root / "policies" / name, tmp / "policies" / name)
    return tmp


def write_artifact(repo: Path, filename: str, body) -> None:
    (repo / "state" / "approvals" / filename).write_text(
        json.dumps(body), encoding="utf-8")


DEPLOY = "fusebase deploy"

with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    reset_cache()
    # AC1: filename says production_deploy, body says database_migration -> DENY.
    write_artifact(repo, "production_deploy-x-20260728.json",
                   {"action": "database_migration", "expires_at": FUTURE})
    dec = evaluate(DEPLOY, root=repo)
    if dec.decision != "deny":
        fails.append(f"ac1-action-mismatch: expected deny got {dec.decision}")
    if dec.approval_verdict != "ACTION_MISMATCH":
        fails.append(f"ac1-verdict: expected ACTION_MISMATCH got {dec.approval_verdict!r}")
    if dec.required_actions != ["production_deploy"]:
        fails.append(f"ac1-required_actions: got {dec.required_actions!r}")

with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    reset_cache()
    # Agreeing body action -> ALLOW (the mismatch above is the discriminator, not the file).
    write_artifact(repo, "production_deploy-x-20260728.json",
                   {"action": "production_deploy", "expires_at": FUTURE})
    dec = evaluate(DEPLOY, root=repo)
    if dec.decision != "allow":
        fails.append(f"ac1-agreeing-action: expected allow got {dec.decision} ({dec.reason})")

with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    reset_cache()
    # AC3: a malformed artifact must not raise out of evaluate(), and must not authorize.
    for name, blob in (
        ("production_deploy-arr-20260728.json", "[1,2,3]"),
        ("production_deploy-num-20260728.json", "42"),
        ("production_deploy-nul-20260728.json", "null"),
        ("production_deploy-txt-20260728.json", "definitely not json"),
    ):
        (repo / "state" / "approvals" / name).write_text(blob, encoding="utf-8")
    try:
        dec = evaluate(DEPLOY, root=repo)
        if dec.decision != "deny":
            fails.append(f"ac3-malformed: expected deny got {dec.decision}")
        if dec.approval_verdict != "MALFORMED":
            fails.append(f"ac3-malformed-verdict: got {dec.approval_verdict!r}")
    except BaseException as e:                       # noqa: BLE001 — the point of AC3
        fails.append(f"ac3-malformed: evaluate() RAISED {e!r}")

with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as foreign:
    repo = make_repo(Path(d))
    reset_cache()
    write_artifact(repo, "production_deploy-x-20260728.json",
                   {"action": "production_deploy", "expires_at": FUTURE})
    here = os.getcwd()
    from_root = evaluate(DEPLOY, root=repo)
    migrate_from_root = evaluate("npx prisma migrate deploy", root=repo)
    try:
        os.chdir(foreign)                            # AC4: policy must not follow the CWD
        reset_cache()
        from_foreign = evaluate(DEPLOY, root=repo)
        migrate_from_foreign = evaluate("npx prisma migrate deploy", root=repo)
    finally:
        os.chdir(here)
        reset_cache()
    if (from_root.decision, from_root.rule_id) != (from_foreign.decision, from_foreign.rule_id):
        fails.append(f"ac4-parity-deploy: {from_root.decision}/{from_root.rule_id} vs "
                     f"{from_foreign.decision}/{from_foreign.rule_id}")
    if (migrate_from_root.decision, migrate_from_root.approval_verdict) != \
       (migrate_from_foreign.decision, migrate_from_foreign.approval_verdict):
        fails.append("ac4-parity-migrate: foreign-CWD decision diverged from repo-root")
    if migrate_from_root.decision != "deny":
        fails.append(f"ac4-migrate-baseline: expected deny got {migrate_from_root.decision}")

print(json.dumps(fails))
PY
)"
if [ "$CP_OUT" = "[]" ]; then
  ok "command-policy-action-agreement-and-root-anchoring"
else
  bad "command-policy-action-agreement-and-root-anchoring" "$CP_OUT"
fi

# ---- 3. AC9: command_digest / repo_id are enforced when present, absent = legacy ---
BIND_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, shutil, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks"))
from shared.approval_artifact import (  # noqa: E402
    Verdict, compute_command_digest, compute_repo_id, evaluate_artifact, is_acceptable,
)
from shared.command_policy import evaluate  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402

FUTURE = "2099-01-01T00:00:00Z"
DEPLOY = "fusebase deploy"
fails = []


def make_repo(tmp: Path) -> Path:
    (tmp / "policies").mkdir(parents=True)
    (tmp / "state" / "approvals").mkdir(parents=True)
    for name in ("command-policy.yml", "approval-policy.yml"):
        shutil.copy(root / "policies" / name, tmp / "policies" / name)
    reset_cache()
    return tmp


def mint(repo: Path, **extra) -> None:
    body = {"schema_version": 2, "action": "production_deploy", "expires_at": FUTURE}
    body.update(extra)
    (repo / "state" / "approvals" / "production_deploy-t-20260728.json").write_text(
        json.dumps(body), encoding="utf-8")


def decide(repo: Path, command: str = DEPLOY):
    reset_cache()
    return evaluate(command, root=repo)


# Digest binding: exact match allows; one character different denies.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    mint(repo, command_digest=compute_command_digest(DEPLOY), repo_id=compute_repo_id(repo))
    if decide(repo).decision != "allow":
        fails.append(f"digest-match: expected allow got {decide(repo).reason}")
    # K6 REVISED: leading/trailing trim is semantics-free, so it still matches...
    if decide(repo, "  fusebase deploy  ").decision != "allow":
        fails.append("digest-strip-only: leading/trailing whitespace must still match")
    # ...but INTERIOR whitespace is data and must NOT match any more.
    if decide(repo, "fusebase  deploy").approval_artifact_present:
        fails.append("digest-interior-whitespace: collapse-era matching is back (K6 revised)")
    for variant in ("fusebase deploy2", "fusebase deploy --prod", "fusebase  deploy x"):
        dec = decide(repo, variant)
        if dec.decision == "allow" and dec.approval_artifact_present:
            fails.append(f"digest-mismatch({variant!r}): unexpectedly authorized")

# T18 / K6 REVISED discriminator: interior whitespace inside a quoted argument is DATA.
# Pre-correction these two hashed identically, so one approval authorized a command
# targeting a different value.
if compute_command_digest('fusebase deploy --app "safe  prod"') == \
   compute_command_digest('fusebase deploy --app "safe prod"'):
    fails.append("k6-quoted-interior-collision: digests are equal (collapse is back)")
if compute_command_digest("  fusebase deploy  ") != compute_command_digest("fusebase deploy"):
    fails.append("k6-strip-retained: trimming the ends must remain semantics-free")
if compute_command_digest("cmd  arg") == compute_command_digest("cmd arg"):
    fails.append("k6-interior-run: interior whitespace runs must hash differently")

# End-to-end: an artifact bound to `x  y` must NOT authorize `x y`.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    bound_cmd = 'fusebase deploy --app "safe  prod"'
    mint(repo, command_digest=compute_command_digest(bound_cmd), repo_id=compute_repo_id(repo))
    if decide(repo, bound_cmd).decision != "allow":
        fails.append("k6-e2e-exact: the exact bound command must be authorized")
    dec = decide(repo, 'fusebase deploy --app "safe prod"')
    if dec.decision != "deny" or dec.approval_verdict != Verdict.BINDING_MISMATCH.value:
        fails.append(f"k6-e2e-collapsed: expected BINDING_MISMATCH deny, got "
                     f"{dec.decision}/{dec.approval_verdict!r}")

# Repo binding: an artifact minted for a different repo must not authorize here.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    mint(repo, repo_id=compute_repo_id(Path(d) / "some" / "other" / "repo"))
    dec = decide(repo)
    if dec.decision != "deny":
        fails.append(f"repo-mismatch: expected deny got {dec.decision}")
    if dec.approval_verdict != Verdict.BINDING_MISMATCH.value:
        fails.append(f"repo-mismatch-verdict: got {dec.approval_verdict!r}")

# K2 additive rule: an artifact carrying NEITHER binding field stays action-scoped.
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    mint(repo)
    if decide(repo).decision != "allow":
        fails.append("no-binding-fields: expected legacy action-scoped allow")

# Fail-closed: a bound artifact whose binding cannot be checked does NOT authorize.
bound = {"action": "production_deploy", "expires_at": FUTURE, "command_digest": "abc"}
if evaluate_artifact(bound, expected_action="production_deploy") is not Verdict.BINDING_MISMATCH:
    fails.append("unverifiable-binding: expected BINDING_MISMATCH when the digest is unknown")

# K7 two-stage cutover: an expiry-less legacy artifact is compat-allowed, strict-rejected.
legacy = {"action": "production_deploy"}
v = evaluate_artifact(legacy, expected_action="production_deploy")
if v is not Verdict.MISSING_EXPIRY:
    fails.append(f"legacy-no-expiry: expected MISSING_EXPIRY got {v}")
if not (is_acceptable(v, strict=False) and not is_acceptable(v, strict=True)):
    fails.append("legacy-no-expiry: compat must allow and strict must reject")

# Binding is checked ONLY after the artifact is otherwise sound (precedence).
stale_bound = {"action": "production_deploy", "expires_at": "2000-01-01T00:00:00Z",
               "command_digest": compute_command_digest(DEPLOY)}
if evaluate_artifact(stale_bound, expected_action="production_deploy",
                     command_digest=compute_command_digest(DEPLOY)) is not Verdict.EXPIRED:
    fails.append("expired-bound: expiry must be reported, not masked by the binding check")

print(json.dumps(fails))
PY
)"
if [ "$BIND_OUT" = "[]" ]; then
  ok "ac9-binding-enforced-when-present"
else
  bad "ac9-binding-enforced-when-present" "$BIND_OUT"
fi

# ---- 4. AC14: the denial message is specific, ordered and <= 8 lines --------------
UX_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, shutil, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks"))
from shared.approval_artifact import Verdict  # noqa: E402
from shared.command_policy import evaluate  # noqa: E402
from shared.denial_message import MAX_LINES, render_approval_denial  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402

PAST, FUTURE = "2000-01-01T00:00:00Z", "2099-01-01T00:00:00Z"
DEPLOY = "fusebase deploy"
fails = []

# Every verdict renders a DISTINCT message carrying its own stable token.
seen = {}
for verdict in [v.value for v in Verdict] + ["NO_ARTIFACT"]:
    msg = render_approval_denial(DEPLOY, ["production_deploy"], {"production_deploy": verdict})
    n = len(msg.splitlines())
    if n > MAX_LINES:
        fails.append(f"ac14-length({verdict}): {n} lines > {MAX_LINES}")
    if verdict not in msg:
        fails.append(f"ac14-token({verdict}): stable token absent from the message")
    if "production_deploy" not in msg:
        fails.append(f"ac14-action({verdict}): required action not named")
    if "approve-local.sh" not in msg:
        fails.append(f"ac14-fix({verdict}): no resolving command")
    if msg in seen:
        fails.append(f"ac14-distinct: {verdict} renders identically to {seen[msg]}")
    seen[msg] = verdict

# Ordering: blocked -> required actions -> per-artifact reason -> fix command.
lines = render_approval_denial(DEPLOY, ["production_deploy"],
                               {"production_deploy": "EXPIRED"}).splitlines()
if not lines[0].startswith("BLOCKED"):
    fails.append(f"ac14-order-1: {lines[0]!r}")
if not lines[1].startswith("Requires approval:"):
    fails.append(f"ac14-order-2: {lines[1]!r}")
if "EXPIRED" not in lines[2]:
    fails.append(f"ac14-order-3: {lines[2]!r}")
if "approve-local.sh" not in lines[-1]:
    fails.append(f"ac14-order-4: {lines[-1]!r}")

# Many actions still fit the budget and still name every one on line 2.
many = [f"action_{i}" for i in range(6)]
msg = render_approval_denial(DEPLOY, many, {a: "NO_ARTIFACT" for a in many})
if len(msg.splitlines()) > MAX_LINES:
    fails.append("ac14-length-many: exceeded the line budget")
for a in many:
    if a not in msg:
        fails.append(f"ac14-every-action-named: {a} missing")

# AC22 / K19 discriminator: the resolving invocation must be COMMAND-BOUND. Pre-correction
# the fix line read `approve-local.sh <action> <slug>` with no --command, so the documented
# copy-paste path minted the weaker, replayable artifact.
for probe in (DEPLOY, "fusebase deploy --app 'it's here'", "fusebase deploy --app \"safe  prod\""):
    fix = render_approval_denial(probe, ["production_deploy"],
                                 {"production_deploy": "NO_ARTIFACT"}).splitlines()[-1]
    if "--command '" not in fix:
        fails.append(f"ac22-bound-invocation: no --command in {fix!r}")
    # The command travels unelided and safely single-quoted.
    quoted = "'" + probe.replace("'", "'\\''") + "'"
    if quoted not in fix:
        fails.append(f"ac22-exact-command: {probe!r} not round-tripped in {fix!r}")

# No ANSI / emoji (explicit non-goal for MSYS + Windows consoles).
if "\x1b[" in msg or any(ord(c) > 0x2500 for c in msg):
    fails.append("ac14-plain-text: message carries ANSI or emoji")


def make_repo(tmp: Path) -> Path:
    (tmp / "policies").mkdir(parents=True)
    (tmp / "state" / "approvals").mkdir(parents=True)
    for name in ("command-policy.yml", "approval-policy.yml"):
        shutil.copy(root / "policies" / name, tmp / "policies" / name)
    reset_cache()
    return tmp


# The regression AC14 exists to kill: STALE must not read as ABSENT.
with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
    stale_repo = make_repo(Path(a))
    (stale_repo / "state" / "approvals" / "production_deploy-t-20260728.json").write_text(
        json.dumps({"action": "production_deploy", "expires_at": PAST}), encoding="utf-8")
    reset_cache()
    stale = evaluate(DEPLOY, root=stale_repo)
    absent_repo = make_repo(Path(b))
    reset_cache()
    absent = evaluate(DEPLOY, root=absent_repo)
    if stale.reason == absent.reason:
        fails.append("ac14-stale-vs-absent: identical messages (the exact defect AC14 kills)")
    if stale.approval_verdict != "EXPIRED" or absent.approval_verdict != "NO_ARTIFACT":
        fails.append(f"ac14-stale-vs-absent verdicts: {stale.approval_verdict} / "
                     f"{absent.approval_verdict}")
    if "EXPIRED" not in stale.reason:
        fails.append("ac14-stale-reason: message does not say the artifact expired")

# Action-mismatch (the S1 scenario) reports its own reason, not "no artifact found".
with tempfile.TemporaryDirectory() as d:
    repo = make_repo(Path(d))
    (repo / "state" / "approvals" / "production_deploy-unrelated-20260728.json").write_text(
        json.dumps({"action": "database_migration", "expires_at": FUTURE}), encoding="utf-8")
    reset_cache()
    dec = evaluate(DEPLOY, root=repo)
    if dec.decision != "deny" or "ACTION_MISMATCH" not in dec.reason:
        fails.append(f"ac14-action-mismatch-message: {dec.decision} / {dec.reason!r}")

print(json.dumps(fails))
PY
)"
if [ "$UX_OUT" = "[]" ]; then
  ok "ac14-denial-message-specific-and-bounded"
else
  bad "ac14-denial-message-specific-and-bounded" "$UX_OUT"
fi

# ---- 5. AC11 (tightened): compat acceptance is AUDITED in every carrier -------------
# T23 discriminator: path_policy compat-accepted an expiry-less artifact SILENTLY, so a
# consumer had no greppable record before the K7 strict flip.
CARRIER_OUT="$(MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY' 2>&1
import json, shutil, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1]); sys.path.insert(0, str(root / "hooks"))
from shared.path_policy import has_active_exception  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402
fails = []
TARGET = "docs/README.md"


def repo(tmp: Path) -> Path:
    (tmp / "policies").mkdir(parents=True)
    (tmp / "state" / "approvals").mkdir(parents=True)
    for name in ("protected-paths.yml", "approval-policy.yml"):
        shutil.copy(root / "policies" / name, tmp / "policies" / name)
    reset_cache()
    return tmp


with tempfile.TemporaryDirectory() as d:
    r = repo(Path(d))
    (r / "state" / "approvals" / "protected_path_edit-legacy-20260728.json").write_text(
        json.dumps({"action": "protected_path_edit", "paths": [TARGET]}), encoding="utf-8")
    reset_cache()
    accepted = has_active_exception(TARGET, root=r, category="documentation")
    log = r / "state" / "audit.log.jsonl"
    if accepted:
        if not log.is_file() or "approval_legacy_accepted" not in log.read_text(encoding="utf-8"):
            fails.append("path_policy compat acceptance was SILENT — AC11 requires an audit entry")
        elif "path_policy" not in log.read_text(encoding="utf-8"):
            fails.append("audit entry does not name the accepting carrier")

print(json.dumps(fails))
PY
)"
if [ "$CARRIER_OUT" = "[]" ]; then
  ok "ac11-compat-acceptance-audited-cross-carrier"
else
  bad "ac11-compat-acceptance-audited-cross-carrier" "$CARRIER_OUT"
fi

# ---- 6. AC11 (tightened): active-approvals.sh honors strict_approvals ---------------
# T23 discriminator: the health lib accepted MISSING_EXPIRY unconditionally, so under
# strict an expiry-less deferral still classified as active (EXCEPTION_IN_EFFECT).
STRICT_LIB_REPO="$(mktemp -d)"
mkdir -p "$STRICT_LIB_REPO/state/approvals" "$STRICT_LIB_REPO/policies"
printf '{"action":"health_check_deferral","deferred_checks":["X1"]}' \
  > "$STRICT_LIB_REPO/state/approvals/health_check_deferral-legacy-20260728.json"
strict_lib_probe() {   # $1 = strict_approvals value; echoes the ACTIVE_ARTIFACTS count
  printf 'strict_approvals: %s\n' "$1" > "$STRICT_LIB_REPO/policies/approval-policy.yml"
  ( cd "$STRICT_LIB_REPO" \
    && ACTIVE_ARTIFACTS=() ARTIFACT_NOTES=() DEFERRED_CHECKS=() DEFERRED_BY_ARTIFACT=() \
    && . "$ROOT/hooks/local/lib/active-approvals.sh" \
    && ffhc_collect_active_approvals >/dev/null 2>&1; echo "${#ACTIVE_ARTIFACTS[@]}" )
}
COMPAT_N="$(strict_lib_probe false)"
STRICT_LIB_LOG="$STRICT_LIB_REPO/state/audit.log.jsonl"
COMPAT_LOG="$( [ -f "$STRICT_LIB_LOG" ] && cat "$STRICT_LIB_LOG" || echo '' )"
STRICT_N="$(strict_lib_probe true)"
if [ "$COMPAT_N" = "1" ] && [ "$STRICT_N" = "0" ]; then
  ok "ac11-active-approvals-honors-strict"
else
  bad "ac11-active-approvals-honors-strict" "compat=$COMPAT_N (want 1) strict=$STRICT_N (want 0)"
fi

# T30 discriminator: the health lib accepted through BARE is_acceptable(), so its compat
# acceptance left no greppable trace at all — AC11 requires every carrier's compat
# acceptance to be audit-logged and to NAME the accepting carrier.
if printf '%s' "$COMPAT_LOG" | grep -q 'approval_legacy_accepted' \
  && printf '%s' "$COMPAT_LOG" | grep -q 'active-approvals'; then
  ok "ac11-active-approvals-compat-acceptance-audited"
else
  bad "ac11-active-approvals-compat-acceptance-audited" \
    "no approval_legacy_accepted entry naming the active-approvals carrier: ${COMPAT_LOG:-<no log>}"
fi
rm -rf "$STRICT_LIB_REPO"


finish
