"""Fusebase Flow — throwaway-consumer fixture for the approval-schema3 phase.

Extracted from hooks/tests/test-approval-schema3.sh under FR-25 (the phase passed the 800-line
ceiling as rows accumulated). This half is the HARNESS: build a disposable repository carrying
the code under test, mint through the real writer, ask the real gate, run a real push, and
score a row. The rows themselves — what the contract requires — stay in the phase.

Imported by that phase only; run_hook_tests.py globs fixtures/*.json and ignores this file.
"""
import json, os, re, shutil, subprocess, sys, tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

# The repository under test, derived from THIS file's location: hooks/tests/fixtures/<me>.
ROOT = Path(__file__).resolve().parents[3]
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
        """A real push. TRIPWIRE: an MSYS fork/spawn failure also yields a nonzero rc, which
        would read as "the boundary refused it" — name that condition instead of scoring it."""
        res = run(self.work, "git", "push", *args)
        # TRIPWIRE: match the SPAWN diagnostic, not the errno text alone — a remote can report
        # "Resource temporarily unavailable" itself, and that is a real result, not environment noise.
        spawn = re.search(r"(line \d+: .*: Resource temporarily unavailable|"
                          r"fork: Resource temporarily unavailable|cannot fork)", res.stderr)
        if res.returncode != 0 and spawn:
            raise RuntimeError("ENVIRONMENT (not a gate result): MSYS could not spawn git; "
                               f"rerun this phase on a quieter machine - {res.stderr.strip()[-120:]}")
        return res

    def schema3(self, command: str, updates=None, **over) -> dict:
        body = {"schema_version": 3, "binding_revision": 1, "action": "production_deploy",
                "repo_id": compute_repo_id(self.work),
                "command_digest": compute_command_digest(command),
                "created_at": CREATED, "expires_at": FUTURE,
                "binding_profile": "git_push_v1" if updates is not None else "command_only_v1"}
        if updates is not None:
            body["updates"] = updates
        body.update(over)
        return body


def remote_refs(r: "Repo", bare: str = "remote.git") -> dict[str, str]:
    """{full ref: object} in one of the fixture's bare remotes - what a push actually wrote."""
    out = git(r.tmp / bare, "for-each-ref", "--format=%(refname) %(objectname)")
    return dict(line.split(" ", 1) for line in out.splitlines() if line)


def prefix_artifact(r: "Repo", command: str, updates: list) -> dict:
    """What the PRE-FIX writer produced: schema 3, no binding_revision (superseded semantics)."""
    body = r.schema3(command, updates)
    body.pop("binding_revision", None)
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


