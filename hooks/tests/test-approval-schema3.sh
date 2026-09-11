#!/usr/bin/env bash
# Fusebase Flow — schema-3 command approvals + git_push_v1 ref-update binding (acceptance).
# Rows = docs/backlog/approval-binding-omits-head/ premise review item 9. Each row drives the
# REAL writer (approve-local.sh), command gate, pre_tool_use handler and pre-push hook inside a
# throwaway repository with a bare remote, so the same file discriminates against a tree
# without the contract: there the writer's artifact keeps authorizing after the change.
#
# Output contract (parsed by run-tests.sh run_shell_phase):
#   "PASS: approval-schema3 <row>" / "FAIL: approval-schema3 <row> (<detail>)"; exit = fails.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if ! command -v python3 >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "PASS: approval-schema3 skipped-no-python3-or-git"; exit 0
fi

MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 python3 - "$ROOT" <<'PY'
import json, os, shutil, subprocess, sys, tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(sys.argv[1])
sys.path.insert(0, str(ROOT / "hooks"))
from shared.approval_artifact import compute_command_digest, compute_repo_id  # noqa: E402
from shared.command_policy import evaluate  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402

FAILS = 0
NOW = datetime.now(timezone.utc)
STAMP = "%Y-%m-%dT%H:%M:%SZ"
CREATED, FUTURE = NOW.strftime(STAMP), (NOW + timedelta(days=1)).strftime(STAMP)
GIT_ENV = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "GIT_AUTHOR_NAME": "t",
           "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
HOOK = ROOT / "hooks" / "git" / "pre-push"
# TRIPWIRE (Windows): CreateProcess searches System32 before PATH, so a bare "bash" is the WSL
# shim there; resolve through PATH like the MSYS shell that launched this test.
BASH = shutil.which("bash") or "bash"


def row(name: str, problems: list[str]) -> None:
    global FAILS
    if problems:
        FAILS += 1
        print(f"FAIL: approval-schema3 {name} ({'; '.join(problems)[:600]})")
    else:
        print(f"PASS: approval-schema3 {name}")


def run(cwd: Path, *args: str, env=None, input_text=None) -> subprocess.CompletedProcess:
    return subprocess.run(list(args), cwd=str(cwd), capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=180,
                          env=env or GIT_ENV, input=input_text)


def git(repo: Path, *args: str) -> str:
    proc = run(repo, "git", *args)
    if proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} rc={proc.returncode}: {proc.stderr.strip()}")
    return proc.stdout.strip()


class Repo:
    """work/ (the consumer, code under test copied in) + bare remote.git/ and remote2.git/."""

    def __init__(self, tmp: Path, *, hook: bool = True):
        self.tmp, self.work = tmp, tmp / "work"
        for bare in ("remote.git", "remote2.git"):
            run(tmp, "git", "init", "-q", "--bare", bare)
        run(tmp, "git", "init", "-q", "-b", "main", "work")
        w = self.work
        for sub in ("hooks/shared", "hooks/handlers"):
            (w / sub).mkdir(parents=True, exist_ok=True)
            for f in (ROOT / sub).glob("*.py"):
                shutil.copy(f, w / sub / f.name)
        (w / "hooks/local/lib").mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / "hooks/local/approve-local.sh", w / "hooks/local/approve-local.sh")
        shutil.copy(ROOT / "hooks/local/lib/approval_inventory.py",
                    w / "hooks/local/lib/approval_inventory.py")
        (w / "policies").mkdir()
        for name in ("command-policy.yml", "approval-policy.yml", "protected-paths.yml",
                     "secret-patterns.yml"):
            if (ROOT / "policies" / name).is_file():
                shutil.copy(ROOT / "policies" / name, w / "policies" / name)
        (w / "state" / "approvals").mkdir(parents=True)
        (w / ".gitignore").write_text("state/\nhooks/\npolicies/\n", encoding="utf-8")
        git(w, "add", ".gitignore")
        git(w, "commit", "-q", "-m", "A")
        git(w, "remote", "add", "origin", "../remote.git")
        git(w, "push", "-q", "origin", "main")          # before the hook exists
        self.hooked = hook and HOOK.is_file()
        if self.hooked:
            target = w / ".git" / "hooks" / "pre-push"
            shutil.copy(HOOK, target)
            os.chmod(target, 0o755)

    def oid(self, rev: str) -> str:
        return git(self.work, "rev-parse", rev)

    def commit(self, msg: str) -> str:
        git(self.work, "commit", "-q", "--allow-empty", "-m", msg)
        return self.oid("HEAD")

    def gate(self, command: str):
        reset_cache()
        return evaluate(command, root=self.work)

    def mint(self, command: str, action: str = "production_deploy", slug: str = "t"):
        """The documented mint path. Returns (rc, artifact-json-or-None, stderr)."""
        for f in (self.work / "state" / "approvals").glob(f"{action}-{slug}-*.json"):
            f.unlink()
        proc = run(self.work, BASH, "hooks/local/approve-local.sh", action, slug,
                   "acceptance fixture", "--command", command)
        found = sorted((self.work / "state" / "approvals").glob(f"{action}-{slug}-*.json"))
        body = json.loads(found[0].read_text(encoding="utf-8")) if found else None
        return proc.returncode, body, proc.stderr + proc.stdout

    def write(self, body: dict, action: str = "production_deploy", slug: str = "t") -> Path:
        """Replace this slug's artifact (the writer's own file included) with `body`."""
        for f in (self.work / "state" / "approvals").glob(f"{action}-{slug}-*.json"):
            f.unlink()
        p = self.work / "state" / "approvals" / f"{action}-{slug}-20260911.json"
        p.write_text(json.dumps(body), encoding="utf-8")
        return p

    def push(self, *args: str) -> subprocess.CompletedProcess:
        return run(self.work, "git", "push", *args)

    def schema3(self, command: str, updates=None, **over) -> dict:
        body = {"schema_version": 3, "action": "production_deploy",
                "repo_id": compute_repo_id(self.work),
                "command_digest": compute_command_digest(command),
                "created_at": CREATED, "expires_at": FUTURE,
                "binding_profile": "git_push_v1" if updates is not None else "command_only_v1"}
        if updates is not None:
            body["updates"] = updates
        body.update(over)
        return body


def upd(dst: str, oid, endpoint: str = "../remote.git", op: str = "update") -> dict:
    return {"push_endpoint": endpoint, "destination_ref": dst, "source_oid": oid, "operation": op}


def expect(dec, want: str, verdict: str | None, label: str, out: list[str]) -> None:
    if dec.decision != want:
        out.append(f"{label}: expected {want} got {dec.decision} [{dec.approval_verdict}]")
    elif verdict and dec.approval_verdict != verdict:
        out.append(f"{label}: expected verdict {verdict} got {dec.approval_verdict}")


def case(name: str, fn, **kw) -> None:
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as d:
        try:
            problems: list[str] = []
            fn(Repo(Path(d), **kw), problems)
        except BaseException as e:                     # noqa: BLE001 — a crash is a FAIL
            problems = [f"raised {e!r}"]
        row(name, problems)


PUSH = "git push origin main"


def digest_omission(r: Repo, p: list[str]) -> None:
    rc, body, err = r.mint("fusebase deploy")
    if body is None:
        p.append(f"writer failed: {err.strip()[-200:]}")
        return
    expect(r.gate("fusebase deploy"), "allow", None, "writer-artifact", p)
    body.pop("command_digest", None)
    r.write(body)
    expect(r.gate("fusebase deploy"), "deny", None, "digest-omitted", p)
    body["command_digest"] = "   "
    r.write(body)
    expect(r.gate("fusebase deploy"), "deny", None, "digest-blank", p)


def schema_downgrade(r: Repo, p: list[str]) -> None:
    rc, body, err = r.mint(PUSH)
    if body is None:
        p.append(f"writer failed: {err.strip()[-200:]}")
        return
    expect(r.gate(PUSH), "allow", None, "writer-artifact", p)
    r.write({**body, "schema_version": 2})
    expect(r.gate(PUSH), "deny", "LEGACY_SCHEMA", "schema-2", p)
    for bad in (3.0, True, "3"):
        r.write({**body, "schema_version": bad})
        expect(r.gate(PUSH), "deny", None, f"schema-type[{bad!r}]", p)
    weaker = {k: v for k, v in body.items() if k != "updates"}
    weaker.update(schema_version=3, binding_profile="command_only_v1")
    r.write(weaker)
    expect(r.gate(PUSH), "deny", "PROFILE_MISMATCH", "profile-downgrade", p)


def legacy_rejection(r: Repo, p: list[str]) -> None:
    digest, rid = compute_command_digest("fusebase deploy"), compute_repo_id(r.work)
    bodies = {
        "absent": {"action": "production_deploy", "expires_at": FUTURE},
        "v1": {"schema_version": 1, "action": "production_deploy", "expires_at": FUTURE},
        "v2-bound": {"schema_version": 2, "action": "production_deploy", "expires_at": FUTURE,
                     "created_at": CREATED, "command_digest": digest, "repo_id": rid},
    }
    paths = {}
    for slug, body in bodies.items():
        for f in (r.work / "state" / "approvals").glob("*.json"):
            f.unlink()
        paths[slug] = r.write(body, slug=slug)
        before = paths[slug].read_bytes()
        expect(r.gate("fusebase deploy"), "deny", "LEGACY_SCHEMA", f"legacy-{slug}", p)
        if paths[slug].read_bytes() != before:
            p.append(f"legacy-{slug}: artifact was modified")
    for slug, body in bodies.items():
        r.write(body, slug=slug)
    inv = run(r.work, BASH, "hooks/local/approve-local.sh", "--inventory")
    for slug in bodies:
        name = f"production_deploy-{slug}-20260911.json"
        line = next((l for l in inv.stdout.splitlines() if l.strip().startswith(name + ":")), "")
        if "LEGACY_SCHEMA" not in line:
            p.append(f"inventory does not name {name} as LEGACY_SCHEMA")
    if len(list((r.work / "state" / "approvals").glob("*.json"))) != 3:
        p.append("inventory removed or added artifacts")


def branch_moved_head_fixed(r: Repo, p: list[str]) -> None:
    git(r.work, "checkout", "-q", "-b", "work")
    rc, body, err = r.mint(PUSH)
    expect(r.gate(PUSH), "allow", None, "before-move", p)
    head = r.oid("HEAD")
    moved = git(r.work, "commit-tree", "-p", head, "-m", "B", f"{head}^{{tree}}")
    git(r.work, "branch", "-f", "main", moved)        # main moves; HEAD (work) does not
    if r.oid("HEAD") != head or r.oid("main") != moved:
        p.append("fixture: expected main to move while HEAD stays fixed")
    expect(r.gate(PUSH), "deny", "UPDATE_MISMATCH", "main-moved-head-fixed", p)


def head_moved_branch_fixed(r: Repo, p: list[str]) -> None:
    git(r.work, "checkout", "-q", "-b", "work")
    rc, body, err = r.mint(PUSH)
    r.commit("unrelated")                             # HEAD moves, main does not
    expect(r.gate(PUSH), "allow", None, "unrelated-head-movement", p)


def identical_tree(r: Repo, p: list[str]) -> None:
    rc, body, err = r.mint(PUSH)
    first = r.oid("main")
    git(r.work, "commit", "-q", "--amend", "--allow-empty", "-m", "A-reworded")
    if r.oid("main^{tree}") != git(r.work, "rev-parse", f"{first}^{{tree}}") or r.oid("main") == first:
        p.append("fixture: expected an identical tree under a different commit")
    expect(r.gate(PUSH), "deny", "UPDATE_MISMATCH", "same-tree-new-commit", p)


def endpoint_change(r: Repo, p: list[str]) -> None:
    r.commit("B")
    rc, body, err = r.mint(PUSH)
    expect(r.gate(PUSH), "allow", None, "before", p)
    git(r.work, "remote", "set-url", "origin", "../remote2.git")
    expect(r.gate(PUSH), "deny", "UPDATE_MISMATCH", "endpoint-changed", p)
    # TRIPWIRE: assembled at runtime. A literal URL carrying credentials in its authority is a
    # real secret-scanner pattern, and a fixture must never need a whitelist to commit.
    token = "t0ken" + "-fixture"
    cred = "https://" + "u5er" + ":" + token + "@example.invalid/x.git"
    git(r.work, "remote", "set-url", "origin", cred)
    rc, body, err = r.mint(PUSH)
    blob = json.dumps(body or {})
    if rc == 0 and (token in blob or "u5er@" in blob or "u5er:" in blob):
        p.append("writer stored endpoint credentials")
    if rc == 0 and body and body.get("binding_profile") == "git_push_v1" and \
            body["updates"][0]["push_endpoint"] != "https://example.invalid/x.git":
        p.append(f"endpoint identity: {body['updates'][0]['push_endpoint']!r}")
    if body is not None:
        body.setdefault("updates", [upd("refs/heads/main", r.oid("main"))])
        body["updates"][0]["push_endpoint"] = cred
        r.write(body)
        expect(r.gate(PUSH), "deny", None, "credential-endpoint-artifact", p)


def extra_refs(r: Repo, p: list[str]) -> None:
    r.commit("B")
    rc, body, err = r.mint(PUSH)
    git(r.work, "branch", "feature")
    two = "git push origin main feature"
    r.write({**(body or {}), "command_digest": compute_command_digest(two)})
    expect(r.gate(two), "deny", "UPDATE_MISMATCH", "unbound-extra-refspec", p)
    rc, body, err = r.mint(PUSH)
    git(r.work, "config", "push.followTags", "true")
    expect(r.gate(PUSH), "deny", "BINDING_UNRESOLVED", "followTags-config", p)
    git(r.work, "tag", "-a", "v9", "-m", "v9")
    res = r.push("origin", "main")
    if res.returncode == 0:
        p.append("pre-push: a push carrying an unbound tag succeeded")


def compound_mutation(r: Repo, p: list[str]) -> None:
    compound = "git commit -q --allow-empty -m B && git push origin main"
    rc, body, err = r.mint(compound)
    if rc == 0 and body is not None and body.get("schema_version") == 3:
        p.append("writer minted an approval for a compound push")
    if body is None:
        body = r.schema3(compound, [upd("refs/heads/main", r.oid("main"))])
    r.write(body)
    expect(r.gate(compound), "deny", "BINDING_UNRESOLVED", "compound-command", p)
    git(r.work, "branch", "feature")
    for chained in ("git push origin main\ngit push origin feature",
                    "git push origin main; git push origin feature",
                    "git push origin main | cat", "git push origin main\techo"):
        r.write(r.schema3(chained, [upd("refs/heads/main", r.oid("main"))]))
        expect(r.gate(chained), "deny", None, f"chained[{chained!r}]", p)
    rc, body, err = r.mint(PUSH)                      # bound to main @ A
    expect(r.gate(PUSH), "allow", None, "pre-command-check", p)
    r.commit("B")                                     # the `commit &&` half, after the check
    res = r.push("origin", "main")
    if res.returncode == 0:
        p.append("pre-push: a commit made after the check was pushed on the old approval")


def lookup_failures(r: Repo, p: list[str]) -> None:
    main = r.oid("main")
    for cmd in ("git push nosuch main", "git push origin nosuchbranch:refs/heads/main",
                "git push origin HEAD:main", "git push origin main --force-if-includes",
                "git push origin +main"):
        rc, body, err = r.mint(cmd)
        if rc == 0 and body and body.get("schema_version") == 3:
            p.append(f"writer bound an unresolvable push: {cmd}")
        r.write(body or r.schema3(cmd, [upd("refs/heads/main", main)]))
        expect(r.gate(cmd), "deny", None, f"unresolved[{cmd}]", p)
    broken = r.tmp / "not-a-repo"
    (broken / "policies").mkdir(parents=True)
    (broken / ".git").mkdir()
    (broken / "state" / "approvals").mkdir(parents=True)
    for name in ("command-policy.yml", "approval-policy.yml"):
        shutil.copy(r.work / "policies" / name, broken / "policies" / name)
    (broken / "state" / "approvals" / "production_deploy-t-20260911.json").write_text(
        json.dumps({**r.schema3(PUSH, [upd("refs/heads/main", main)]),
                    "repo_id": compute_repo_id(broken)}), encoding="utf-8")
    reset_cache()
    dec = evaluate(PUSH, root=broken)
    if dec.decision != "deny":
        p.append(f"git-unusable: expected deny got {dec.decision}")


def unchanged_retry(r: Repo, p: list[str]) -> None:
    r.commit("B")
    rc, body, err = r.mint(PUSH)
    for attempt in (1, 2):
        expect(r.gate(PUSH), "allow", None, f"gate-attempt-{attempt}", p)
        res = r.push("origin", "main")
        if res.returncode != 0:
            p.append(f"push-attempt-{attempt} rc={res.returncode}: {res.stderr.strip()[-200:]}")


def replay_two_commits(r: Repo, p: list[str]) -> None:
    cmd = "git push origin HEAD:refs/heads/main"
    r.commit("B")
    rc, body, err = r.mint(cmd)
    expect(r.gate(cmd), "allow", None, "first-commit-gate", p)
    res = r.push("origin", "HEAD:refs/heads/main")
    if res.returncode != 0:
        p.append(f"first push rc={res.returncode}: {res.stderr.strip()[-200:]}")
    r.commit("C")
    expect(r.gate(cmd), "deny", "UPDATE_MISMATCH", "second-commit-gate", p)
    res = r.push("origin", "HEAD:refs/heads/main")
    if res.returncode == 0:
        p.append("second commit was pushed on the first commit's approval")
    remote_main = git(r.tmp / "remote.git", "rev-parse", "refs/heads/main")
    if remote_main == r.oid("HEAD"):
        p.append("remote main advanced to the unapproved commit")


def boundary_scope(r: Repo, p: list[str]) -> None:
    r.commit("B")
    git(r.work, "branch", "feature")
    res = r.push("origin", "feature")
    if res.returncode != 0:
        p.append(f"ungated destination blocked: {res.stderr.strip()[-160:]}")
    res = r.push("origin", "main")
    if res.returncode == 0:
        p.append("gated destination pushed with no approval")
    elif "BLOCKED (FR-12 pre-push)" not in res.stderr:
        p.append(f"denial text: {res.stderr.strip()[-160:]}")
    (r.work / "policies" / "approval-policy.local.yml").write_text(
        "workflow_mode: branch_pr\n", encoding="utf-8")
    res = r.push("origin", "main")
    if res.returncode != 0:
        p.append("branch_pr mode: the direct_to_main rule gated a push")


def writer_refuses(r: Repo, p: list[str]) -> None:
    for cmd in ("echo hi", "git push", "git push origin main; rm -rf x"):
        rc, body, err = r.mint(cmd)
        if rc == 0:
            p.append(f"writer wrote an artifact for {cmd!r}")
    rc, body, err = r.mint("npx prisma migrate deploy", action="database_migration")
    if rc != 0 or not body or body.get("binding_profile") != "command_only_v1" \
            or "updates" in body:
        p.append(f"migration approval not command_only_v1: rc={rc} {err.strip()[-160:]}")


def resolver_config_remaps(r: Repo, p: list[str]) -> None:
    from shared.git_push_binding import resolve_command_updates   # absent before schema 3
    ok, why = resolve_command_updates(PUSH, r.work)
    if ok is None or len(ok) != 1 or ok[0][1:] != ("refs/heads/main", r.oid("main"), "update"):
        p.append(f"plain push did not resolve to main@HEAD: {ok} {why}")
    remaps = [("push.default", "upstream"), ("remote.origin.push", "refs/heads/main:refs/heads/prod"),
              ("push.recurseSubmodules", "on-demand"), ("remote.origin.mirror", "true")]
    for key, value in remaps:
        git(r.work, "config", key, value)
        got, why = resolve_command_updates(PUSH, r.work)
        if got is not None:
            p.append(f"{key}={value} still resolved: {got}")
        git(r.work, "config", "--unset-all", key)
    main = r.oid("main")
    for cmd, want in (("git push origin :refs/heads/old", ("refs/heads/old", None, "delete")),
                      (f"git push origin {main}:refs/heads/pinned", ("refs/heads/pinned", main, "update")),
                      ("git push -u origin HEAD", ("refs/heads/main", main, "update"))):
        got, why = resolve_command_updates(cmd, r.work)
        if not got or got[0][1:] != want:
            p.append(f"{cmd!r}: {got} {why}")
    # A value-less key is git-true and only settable by writing the config file itself.
    cfg = r.work / ".git" / "config"
    original = cfg.read_text(encoding="utf-8")
    cfg.write_text(original + "[push]\n\tfollowTags\n", encoding="utf-8")
    if resolve_command_updates(PUSH, r.work)[0] is not None:
        p.append("value-less push.followTags (true) still resolved")
    if resolve_command_updates(PUSH + " --no-follow-tags", r.work)[0] is None:
        p.append("--no-follow-tags did not override push.followTags")
    cfg.write_text(original, encoding="utf-8")


def dry_run_cannot_authorize(r: Repo, p: list[str]) -> None:
    """A dry run performs no update, so it must not be able to authorize one.

    git hands pre-push the SAME update lines for a dry run, and that boundary cannot see the
    command — so an approval minted for `git push --dry-run origin main` authorized the REAL
    push of those objects (independent review of 87ed0ff, blocker 1).
    """
    r.commit("B")
    for dry in ("git push --dry-run origin main", "git push -n origin main"):
        rc, body, err = r.mint(dry)
        if rc == 0 or body is not None:
            p.append(f"writer minted an execution-authorizing artifact for {dry!r}")
        if body is None and "dry" not in err.lower():
            p.append(f"refusal for {dry!r} does not say why: {err.strip()[-120:]}")
        # Even hand-written, a dry-run-bound artifact must not pass the command gate.
        r.write(r.schema3(dry, [upd("refs/heads/main", r.oid("main"))]))
        expect(r.gate(dry), "deny", "BINDING_UNRESOLVED", f"gate[{dry}]", p)
    # End to end: the documented mint path yields nothing, so the real push stays refused.
    for f in (r.work / "state" / "approvals").glob("*.json"):
        f.unlink()
    r.mint("git push --dry-run origin main")
    res = r.push("origin", "main")
    if res.returncode == 0:
        p.append("a real push succeeded after approving only a dry run")


def ssh_principal_binding(r: Repo, p: list[str]) -> None:
    """`alice@host:repo.git` and `bob@host:repo.git` are different repositories.

    Stripping the SSH login merged them (independent review of 87ed0ff, blocker 2); an HTTPS
    userinfo is authentication material and must still never be stored.
    """
    from shared.approval_artifact import canonical_endpoint
    from shared.command_policy import evaluate_push_boundary
    # Credential-bearing forms are assembled here, never written as literals (secret scanner).
    https_creds = "https://" + "u5er" + ":" + "t0k3n" + "@host/o/r.git"
    ssh_creds = "ssh://" + "alice" + ":" + "s3cret" + "@host/x.git"
    pairs = [("alice@host:repo.git", "alice@host:repo.git"),
             ("ssh://alice@host/~/repo.git", "ssh://alice@host/~/repo.git"),
             (https_creds, "https://host/o/r.git"),
             (ssh_creds, None)]
    for raw, want in pairs:
        got = canonical_endpoint(raw)
        if got != want:
            p.append(f"canonical_endpoint({raw!r}) = {got!r}, expected {want!r}")
    if canonical_endpoint("alice@host:repo.git") == canonical_endpoint("bob@host:repo.git"):
        p.append("two SSH logins still collapse to one endpoint")

    # Gate 1 — the command gate, through the real writer and a changed remote.
    r.commit("B")
    git(r.work, "remote", "set-url", "origin", "alice@host:repo.git")
    rc, body, err = r.mint(PUSH)
    if body is None:
        p.append(f"writer could not bind an ssh remote: {err.strip()[-160:]}")
        return
    if body["updates"][0]["push_endpoint"] != "alice@host:repo.git":
        p.append(f"endpoint not bound as minted: {body['updates'][0]['push_endpoint']!r}")
    expect(r.gate(PUSH), "allow", None, "same-principal", p)
    git(r.work, "remote", "set-url", "origin", "bob@host:repo.git")
    expect(r.gate(PUSH), "deny", "UPDATE_MISMATCH", "changed-principal", p)

    # Gate 2 — the pre-push boundary, given the updates git would hand it for bob's remote.
    line = f"refs/heads/main {r.oid('main')} refs/heads/main {'0' * 40}"
    for endpoint, want in (("alice@host:repo.git", "allow"), ("bob@host:repo.git", "deny")):
        decision = evaluate_push_boundary(endpoint, [line], root=r.work)
        if decision.decision != want:
            p.append(f"boundary[{endpoint}]: expected {want} got {decision.decision} "
                     f"[{decision.approval_verdict}]")


def handler_route(r: Repo, p: list[str]) -> None:
    def hook(command: str) -> str:
        proc = run(r.work, sys.executable, str(r.work / "hooks/handlers/pre_tool_use.py"),
                   input_text=json.dumps({"event": "pre_tool_use", "cwd": str(r.work),
                                          "tool_name": "Bash", "tool_input": {"command": command}}))
        try:
            return json.loads(proc.stdout).get("decision", "")
        except Exception:
            return f"unparseable({proc.stdout[-120:]!r})"
    r.write({"schema_version": 2, "action": "production_deploy", "expires_at": FUTURE,
             "command_digest": compute_command_digest("fusebase deploy"),
             "repo_id": compute_repo_id(r.work)}, slug="legacy")
    if hook("fusebase deploy") != "deny":
        p.append("pre_tool_use accepted a schema-2 artifact")
    r.mint("fusebase deploy")
    if hook("fusebase deploy") != "allow":
        p.append("pre_tool_use rejected a writer-minted schema-3 artifact")


case("digest-omission-denies", digest_omission)
case("schema-and-profile-downgrade-denies", schema_downgrade)
case("legacy-rejected-preserved-and-inventoried", legacy_rejection)
case("branch-moved-head-fixed-denies", branch_moved_head_fixed)
case("head-moved-branch-fixed-allows", head_moved_branch_fixed)
case("identical-tree-different-commit-denies", identical_tree)
case("endpoint-change-denies-and-no-credentials", endpoint_change)
case("extra-refs-deny", extra_refs)
case("compound-command-mutation-denies", compound_mutation)
case("lookup-failures-fail-closed", lookup_failures)
case("unchanged-input-retry-allows", unchanged_retry)
case("replay-two-commits-authorizes-only-first", replay_two_commits)
case("pre-push-gates-destinations-only", boundary_scope)
case("writer-refuses-unbindable-and-labels-command-only", writer_refuses)
case("resolver-config-remaps-fail-closed", resolver_config_remaps)
case("dry-run-approval-cannot-authorize-a-real-push", dry_run_cannot_authorize)
case("ssh-principal-change-denies-at-both-gates", ssh_principal_binding)
case("pre-tool-use-handler-route", handler_route)
sys.exit(FAILS)
PY
PY_FAILS=$?

# ---- The health report must agree with the gate (bash: the lib fills the CALLER's arrays) --
# A legacy command approval authorizes nothing, so it must not be reported ACTIVE; it surfaces
# as a warning naming the file. Path/deferral artifacts keep their own carrier's contract.
AA_DIR="$(mktemp -d)"
mkdir -p "$AA_DIR/state/approvals" "$AA_DIR/policies"
cp "$ROOT/policies/approval-policy.yml" "$ROOT/policies/command-policy.yml" "$AA_DIR/policies/"
cat > "$AA_DIR/state/approvals/production_deploy-legacy-20260728.json" <<'EOFL'
{"schema_version":2,"action":"production_deploy","scope":"legacy","expires_at":"2099-01-01T00:00:00Z"}
EOFL
cat > "$AA_DIR/state/approvals/health_check_deferral-x-20260728.json" <<'EOFD'
{"action":"health_check_deferral","scope":"x","expires_at":"2099-01-01T00:00:00Z","deferred_checks":["mirror_drift"]}
EOFD
AA_OUT="$(
  cd "$AA_DIR" || exit 1
  # shellcheck source=/dev/null
  . "$ROOT/hooks/local/lib/active-approvals.sh"
  ACTIVE_ARTIFACTS=(); ARTIFACT_NOTES=(); DEFERRED_CHECKS=(); DEFERRED_BY_ARTIFACT=(); APPROVAL_WARNINGS=()
  ffhc_collect_active_approvals
  printf 'ART:%s\n' "${ACTIVE_ARTIFACTS[@]:-}"
  printf 'WARN:%s\n' "${APPROVAL_WARNINGS[@]:-}"
  echo "DEFERRED=${DEFERRED_CHECKS[*]:-}"
)"
rm -rf "$AA_DIR"
aa_fail=""
case "$AA_OUT" in *"ART:production_deploy-legacy"*) aa_fail="$aa_fail [a legacy command approval was reported ACTIVE]" ;; *) ;; esac
case "$AA_OUT" in *"WARN:production_deploy-legacy-20260728.json: no longer authorizes commands"*) ;; *) aa_fail="$aa_fail [no warning naming the artifact]" ;; esac
case "$AA_OUT" in *"DEFERRED=mirror_drift"*) ;; *) aa_fail="$aa_fail [the deferral carrier stopped working]" ;; esac
if [ -z "$aa_fail" ]; then
  echo "PASS: approval-schema3 health-report-drops-legacy-command-approvals"
  AA_FAILS=0
else
  echo "FAIL: approval-schema3 health-report-drops-legacy-command-approvals ($aa_fail :: $AA_OUT)"
  AA_FAILS=1
fi

TOTAL_FAILS=$((PY_FAILS + AA_FAILS))
echo "[test-approval-schema3] $((19 - TOTAL_FAILS))/19 PASS"
exit "$TOTAL_FAILS"
