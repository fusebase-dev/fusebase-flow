#!/usr/bin/env python3
"""Agent tool profile contract (task-delegation § Agent tool reach).

Shell rows run only with --with-shell (bash + python3); cli-flow-recovery passes it, a bare local run does not.
"""
from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import inspect
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

sys.dont_write_bytecode = True

REPO = Path(__file__).resolve().parents[2]
LIB_REL = "hooks/local/lib/agent_tool_profile.py"
COPIES = ("hooks/local/mirror-agents.sh", LIB_REL)
OWNED_WRITE_REL = "hooks/local/lib/recovery-owned-write.py"
# mirror-agents.sh still calls the maintainer writer; only the shell rows carry it (ask 11a).
SHELL_EXTRA = (OWNED_WRITE_REL, "hooks/local/fusebase-flow-overlays/agent-surface-ownership.json")
HELPER_COPIES = ("native_path", "lf_form", "atomic_bytes", "reject_symlinks", "recovery_lock")
TOOL = "mcp__example__read_file"
AD, PO = ".claude/agents/ai-developer-project.md", ".claude/agents/product-owner-project.md"
PROFILE = "policies/agent-tools.yml"
MANIFEST = "audit/agent-mirror-manifest.txt"
FAILS = 0


def report(name: str, ok: bool, detail: str = "") -> None:
    global FAILS
    FAILS += 0 if ok else 1
    print(f"{'PASS' if ok else 'FAIL'}: agent-tool-profile {name}" + ("" if ok else f" ({detail})"))


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


atp = load(REPO / LIB_REL, "agent_tool_profile_under_test")


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def put(root: Path, rel: str, value: bytes | str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(value.encode("utf-8") if isinstance(value, str) else value)


def git(root: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, timeout=60)


def commit(root: Path, *rels: str) -> None:
    git(root, "add", "--", *rels)
    git(root, "commit", "-qm", "fixture")


@contextlib.contextmanager
def workdir():
    path = Path(tempfile.mkdtemp(prefix="ff-atp-"))
    try:
        yield path
    finally:
        def unlock(func, target, _exc):
            os.chmod(target, stat.S_IWRITE)
            func(target)
        if sys.version_info >= (3, 12):
            shutil.rmtree(path, onexc=unlock)
        else:
            shutil.rmtree(path, onerror=unlock)


def fixture(tmp: Path, mirrors: bool = True, name: str = "repo", extra: tuple[str, ...] = ()) -> Path:
    root = tmp / name
    for agent_dir in sorted((REPO / "agents").iterdir()):
        canon = agent_dir / "AGENT.md"
        if not canon.is_file():
            continue
        put(root, f"agents/{agent_dir.name}/AGENT.md", canon.read_bytes())
        if mirrors:
            put(root, f".claude/agents/{agent_dir.name}.md", canon.read_bytes())
            put(root, f".codex/agents/{agent_dir.name}.md", canon.read_bytes())
    for rel in COPIES + extra:
        put(root, rel, (REPO / rel).read_bytes())
    git(root, "init", "-q")
    git(root, "config", "user.name", "atp fixture")
    git(root, "config", "user.email", "atp@example.invalid")
    return root.resolve()


def profile(root: Path, agents: dict, rel: str = PROFILE) -> None:
    put(root, rel, json.dumps({"schema_version": 1, "agents": {
        name: {"add_tools": tools} for name, tools in agents.items()}}) + "\n")


def call(fn, root: Path) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = fn(root)
    return rc, out.getvalue(), err.getvalue()


def cli(root: Path, command: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    return subprocess.run([sys.executable, str(root / LIB_REL), command, "--root", str(root)],
                          capture_output=True, text=True, timeout=120, env=env)


def rows(text: str, kind: str) -> list[str]:
    return [line for line in text.splitlines() if line.startswith(kind + " ")]


def frontmatter(raw: bytes) -> tuple[dict, list[str], int]:
    lines = raw.replace(b"\r\n", b"\n").decode("utf-8").split("\n")
    k = lines.index("---", 1)
    return yaml.safe_load("\n".join(lines[1:k])), lines, k


def variants(root: Path) -> list[str]:
    return sorted(p.name for p in (root / ".claude/agents").glob("*-project.md"))


def row_compose_shape() -> None:
    canon = (REPO / "agents/ai-developer/AGENT.md").read_bytes()
    meta, lines, k = frontmatter(canon)
    out = atp.compose("ai-developer", canon, ["Read", TOOL])
    got, out_lines, ok_k = frontmatter(out)
    base = [t.strip() for t in meta["tools"].split(",")]
    problems = []
    if got["name"] != "ai-developer-project":
        problems.append(f"name {got['name']}")
    if got["tools"] != ", ".join(base + [TOOL]):
        problems.append(f"tools {got['tools']}")
    if not got["description"].startswith(meta["description"] + " Project variant with added tools " + TOOL):
        problems.append("description suffix")
    if out_lines[ok_k + 3:] != lines[k + 1:]:
        problems.append("body differs from the canonical body")
    if not atp.owned(out, "ai-developer") or atp.owned(out, "product-owner"):
        problems.append("marker ownership")
    lf = out.replace(b"\r\n", b"\n")
    tampered_tools = lf.replace(f", {TOOL}\n".encode(), b", WebFetch\n", 1)
    tampered_body = lf + b"extra line\n"
    if tampered_tools == lf:
        problems.append("tools-line tamper did not apply")
    if atp.owned(tampered_tools, "ai-developer") or atp.owned(tampered_body, "ai-developer"):
        problems.append("tampered variant still verifies")
    report("compose-shape", not problems, "; ".join(problems))


def row_apply_cycle() -> None:
    with workdir() as tmp:
        root = fixture(tmp)
        put(root, MANIFEST, (REPO / MANIFEST).read_bytes())
        watched = [p for p in sorted(root.glob(".claude/agents/*.md")) if not p.name.endswith("-project.md")]
        watched += sorted(root.glob(".codex/agents/*")) + [root / MANIFEST]
        before = {str(p): sha(p.read_bytes()) for p in watched}
        base_ok = []
        profile(root, {"ai-developer": [TOOL]})
        first = cli(root, "apply")
        base_ok.append(before == {str(p): sha(p.read_bytes()) for p in watched})
        stamp = ((root / AD).read_bytes(), (root / AD).stat().st_mtime_ns)
        second = cli(root, "apply")
        again = ((root / AD).read_bytes(), (root / AD).stat().st_mtime_ns)
        report("apply-idempotent", first.returncode == 0 and "generated 1;" in first.stdout
               and second.returncode == 0 and "current 1;" in second.stdout and stamp == again,
               f"rc {first.returncode}/{second.returncode}: {first.stdout!r} {second.stdout!r} {first.stderr!r}")

        canon = root / "agents/ai-developer/AGENT.md"
        canon.write_bytes(canon.read_bytes() + b"\nUpgraded body line.\n")
        rc, out, err = call(atp.apply, root)
        base_ok.append(before == {str(p): sha(p.read_bytes()) for p in watched})
        variant = (root / AD).read_bytes()
        commit(root, PROFILE, AD)
        _rc, checked, _err = call(atp.check, root)
        report("upgrade-regenerates", rc == 0 and "generated 1;" in out and b"Upgraded body line." in variant
               and atp.owned(variant, "ai-developer") and not rows(checked, "WARN") + rows(checked, "ERROR"),
               f"rc {rc} {out!r} {err!r} check {checked!r}")

        profile(root, {})
        rc, out, _err = call(atp.apply, root)
        base_ok.append(before == {str(p): sha(p.read_bytes()) for p in watched})
        report("base-untouched", all(base_ok) and rc == 0 and "removed 1;" in out and not (root / AD).exists(),
               f"base unchanged per step {base_ok}; rc {rc} {out!r}")


def row_hand_edit() -> None:
    with workdir() as tmp:
        root = fixture(tmp)
        profile(root, {"ai-developer": [TOOL]})
        problems = []
        for label, edit in (("tools", lambda b: re.sub(rb"(?m)^tools: .*$", b"tools: Read", b, count=1)),
                            ("body", lambda b: b + b"hand edit\n")):
            (root / AD).unlink(missing_ok=True)
            call(atp.apply, root)
            edited = edit((root / AD).read_bytes())
            (root / AD).write_bytes(edited)
            result = cli(root, "apply")
            _rc, checked, _err = call(atp.check, root)
            if result.returncode != 1 or (root / AD).read_bytes() != edited \
                    or f"[mirror-agents] preserved {AD}" not in result.stderr \
                    or not any(f"edited by hand: {AD}" in line for line in rows(checked, "WARN")):
                problems.append(f"{label}: rc {result.returncode} {result.stderr!r} {checked!r}")
        report("hand-edit-preserved", not problems, "; ".join(problems))


INVALID = (
    ("AskUserQuestion", {"ai-developer": ["AskUserQuestion"]}),
    ("askuserquestion", {"ai-developer": ["askuserquestion"]}),
    ("Agent", {"ai-developer": ["Agent"]}),
    ("Task", {"ai-developer": ["Task"]}),
    ("unknown-agent", {"ai-dev": [TOOL]}),
    ("cli-agent", {"app-architect": [TOOL]}),
    ("reserved-suffix-key", {"ai-developer-project": [TOOL]}),
    ("not-a-list", {"ai-developer": "WebFetch"}),
    ("empty-list", {"ai-developer": []}),
    ("duplicate", {"ai-developer": ["WebFetch", "WebFetch"]}),
    ("comma-list", {"ai-developer": ["WebFetch, AskUserQuestion"]}),
    ("trailing-newline", {"ai-developer": ["WebFetch\n"]}),
    ("frontmatter-injection", {"ai-developer": ["mcp__x\nname: evil"]}),
    ("scoped-bash", {"ai-developer": ["Bash(rm:*)"]}),
    ("server-level-mcp", {"ai-developer": ["mcp__srv"]}),
    ("star", {"ai-developer": ["*"]}),
    ("33-tools", {"ai-developer": [f"Tool{i}" for i in range(33)]}),
)
RAW_INVALID = (
    ("remove-tools", '{"schema_version": 1, "agents": {"ai-developer": {"remove_tools": ["Bash"]}}}\n'),
    ("top-level-tools", '{"schema_version": 1, "agents": {}, "tools": ["WebFetch"]}\n'),
    ("schema-2", "schema_version: 2\nagents: {}\n"),
    ("schema-true", "schema_version: true\nagents: {}\n"),
    ("non-mapping-root", "- schema_version\n- agents\n"),
    ("over-64KiB", "schema_version: 1\nagents: {}\n" + "#" * 70000 + "\n"),
)


def row_invalid_profiles() -> None:
    problems = []
    with workdir() as tmp:
        root = fixture(tmp)
        cases = [(name, json.dumps({"schema_version": 1, "agents": {
            agent: {"add_tools": tools} for agent, tools in agents.items()}}) + "\n")
            for name, agents in INVALID] + list(RAW_INVALID)
        for name, text in cases:
            put(root, PROFILE, text)
            rc, _out, err = call(atp.apply, root)
            _rc, checked, _err = call(atp.check, root)
            if rc != 2 or variants(root) or "agent tool profile invalid" not in err or not rows(checked, "ERROR"):
                problems.append(f"{name}: rc {rc} variants {variants(root)} {err!r} {checked!r}")
        (root / PROFILE).unlink()
        real = root / "elsewhere.yml"
        real.write_text(f"schema_version: 1\nagents:\n  ai-developer:\n    add_tools: [{TOOL}]\n", encoding="utf-8")
        try:
            os.symlink(real, root / PROFILE)
        except (OSError, NotImplementedError):
            print("INFO agent-tool-profile symlink row not exercised on this host")
        else:
            rc, _out, _err = call(atp.apply, root)
            if rc != 2 or variants(root):
                problems.append(f"symlinked-profile: rc {rc} variants {variants(root)}")
    report("invalid-profiles", not problems, "; ".join(problems))


def row_dup_and_orphans() -> None:
    with workdir() as tmp:
        root = fixture(tmp)
        profile(root, {"ai-developer": [TOOL]})
        call(atp.apply, root)
        profile(root, {"ai-developer": ["Read"]})
        rc, out, err = call(atp.apply, root)
        report("dup-only-no-variant", rc == 0 and "removed 1;" in out and not (root / AD).exists()
               and "no added tools" in err, f"rc {rc} {out!r} {err!r}")

        profile(root, {"ai-developer": [TOOL], "product-owner": [TOOL]})
        call(atp.apply, root)
        stale_po = (root / PO).read_bytes()
        mine = b"---\nname: marketing-project\ndescription: x\ntools: Read\n---\nmine\n"
        put(root, ".claude/agents/marketing-project.md", mine)
        profile(root, {"ai-developer": [TOOL]})
        rc1, out1, _err = call(atp.apply, root)
        hand = stale_po + b"hand edit\n"
        put(root, PO, hand)
        rc2, out2, err2 = call(atp.apply, root)
        _rc, checked, _err = call(atp.check, root)
        warns = rows(checked, "WARN")
        report("orphan", rc1 == 0 and "removed 1;" in out1 and rc2 == 0 and (root / PO).read_bytes() == hand
               and any(f"reserved agent name: {PO}" in w for w in warns)
               and (root / ".claude/agents/marketing-project.md").read_bytes() == mine
               and "marketing" not in checked + err2 + out2,
               f"rc {rc1}/{rc2} {out1!r} {out2!r} {err2!r} {checked!r}")


def row_canonical_removed_orphan() -> None:
    with workdir() as tmp:
        root = fixture(tmp)
        profile(root, {"product-owner": [TOOL]})
        call(atp.apply, root)
        generated = (root / PO).is_file()
        shutil.rmtree(root / "agents" / "product-owner")
        profile(root, {})
        _rc, checked, _err = call(atp.check, root)
        rc, out, err = call(atp.apply, root)
        report("canonical-removed-orphan-removed", generated and rc == 0 and "removed 1;" in out
               and not (root / PO).exists() and any(PO in w for w in rows(checked, "WARN")),
               f"rc {rc} {out!r} {err!r} {checked!r}")


def row_no_profile_and_twin() -> None:
    with workdir() as tmp:
        root = fixture(tmp)
        before = sorted(str(p) for p in root.rglob("*") if ".git" not in p.parts)
        applied, checked = cli(root, "apply"), cli(root, "check")
        after = sorted(str(p) for p in root.rglob("*") if ".git" not in p.parts)
        report("no-profile-noop", applied.returncode == 0 and not applied.stdout and not applied.stderr
               and checked.returncode == 0 and not checked.stdout and before == after,
               f"{applied.returncode} {applied.stdout!r} {applied.stderr!r} {checked.stdout!r}")

        profile(root, {"ai-developer": [TOOL]})
        profile(root, {"ai-developer": [TOOL, "WebFetch"]}, rel="policies/agent-tools.local.yml")
        call(atp.apply, root)
        meta = frontmatter((root / AD).read_bytes())[0]
        _rc, checked_out, _err = call(atp.check, root)
        report("local-twin-ignored", "WebFetch" not in meta["tools"]
               and any("agent-tools.local.yml" in w for w in rows(checked_out, "WARN")), checked_out)


def row_crlf() -> None:
    with workdir() as tmp:
        root = fixture(tmp)
        canon = root / "agents/ai-developer/AGENT.md"
        canon.write_bytes(canon.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
        profile(root, {"ai-developer": [TOOL]})
        rc, _out, _err = call(atp.apply, root)
        variant = (root / AD).read_bytes()
        commit(root, PROFILE, AD)
        _rc, checked, _err = call(atp.check, root)
        report("crlf-canonical", rc == 0 and variant.count(b"\n") == variant.count(b"\r\n")
               and atp.owned(variant, "ai-developer") and not rows(checked, "WARN"), checked)


def row_managed_set() -> None:
    mcm = load(REPO / "hooks/local/lib/managed_content_manifest.py", "managed_content_manifest_atp")
    with workdir() as tmp, contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        local, upstream = tmp / "local", tmp / "upstream"
        for tree in (local, upstream):
            put(tree, "policies/command-policy.yml", "rules: []\n")
            put(tree, "VERSION", "5.11.0\n")
        mcm.stamp(local)
        put(local, PROFILE, "schema_version: 1\nagents: {}\n")
        excluded = PROFILE not in mcm.collect_paths(local)
        verified = mcm.verify(local, False)
        classified = [r["path"] for r in mcm.classify(local / mcm.MANIFEST_REL, local, upstream)]
    report("managed-set-excludes-profile", excluded and verified == 0 and PROFILE not in classified,
           f"excluded={excluded} verify rc={verified} classified={classified}")


def row_check_states() -> None:
    with workdir() as tmp:
        root = fixture(tmp)
        profile(root, {"ai-developer": [TOOL], "product-owner": [TOOL]})
        call(atp.apply, root)
        _rc, untracked, _err = call(atp.check, root)
        commit(root, PROFILE, AD, PO)
        _rc, clean, _err = call(atp.check, root)
        report("uncommitted-warn", any("is not committed" in w for w in rows(untracked, "WARN"))
               and "is not committed" not in clean, f"{untracked!r} {clean!r}")
        report("check-clean", not rows(clean, "WARN") and not rows(clean, "ERROR")
               and "agent variants current: 2" in clean, clean)


def row_maintainer_guards() -> None:
    problems = []
    tracked = subprocess.run(["git", "ls-files", "--", PROFILE], cwd=REPO, capture_output=True,
                             text=True, timeout=60).stdout.strip()
    if tracked:
        problems.append(f"Flow ships {PROFILE}")
    names = atp.canonical_agents(REPO)
    clash = sorted(set(names) & atp.cli_reserved(REPO))
    if clash:
        problems.append(f"canonical agent named like a CLI agent: {clash}")
    for name in names:
        if name.endswith(atp.SUFFIX):
            problems.append(f"canonical agent with the reserved suffix: {name}")
            continue
        try:
            out = atp.compose(name, (REPO / "agents" / name / "AGENT.md").read_bytes(), [TOOL])
            if not atp.owned(out, name) or frontmatter(out)[0]["name"] != f"{name}-project":
                problems.append(f"{name}: composed variant does not verify")
        except Exception as exc:
            problems.append(f"{name}: {exc}")
    report("maintainer-guards", not problems, "; ".join(problems))


def row_helper_copy_parity() -> None:
    original = load(REPO / OWNED_WRITE_REL, "recovery_owned_write_atp")
    drift = [name for name in HELPER_COPIES
             if inspect.getsource(getattr(atp, name)) != inspect.getsource(getattr(original, name))]
    report("helper-copy-parity", not drift, f"copies differ from {OWNED_WRITE_REL}: {drift}")


def _git_bash():
    spec = importlib.util.spec_from_file_location("git_bash", Path(__file__).resolve().parent / "lib" / "git_bash.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bash_executable() -> str:
    return _git_bash().bash_executable()


def sh(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([bash_executable(), *args], cwd=root, capture_output=True, text=True,
                          timeout=600, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))


MIRRORED_RE = re.compile(r"\[mirror-agents\] mirrored \d+ files \(across 2 mirrors\); copied \d+; "
                         r"\d+ had pre-existing drift\.")


def shell_rows() -> None:
    with workdir() as tmp:
        plain = fixture(tmp, mirrors=False, name="plain", extra=SHELL_EXTRA)
        put(plain, ".claude/agents/marketing-project.md", "---\nname: marketing-project\n---\nmine\n")
        bare = sh(plain, "hooks/local/mirror-agents.sh")
        lines = bare.stdout.splitlines()
        report("mirror-agents-no-profile-identical", bare.returncode == 0 and len(lines) == 2
               and MIRRORED_RE.fullmatch(lines[0]) is not None and lines[1].startswith("[mirror-agents] manifest: ")
               and not bare.stderr, f"rc {bare.returncode} {bare.stdout!r} {bare.stderr!r}")

        root = fixture(tmp, mirrors=False, extra=SHELL_EXTRA)
        profile(root, {"ai-developer": [TOOL]})
        first, second = sh(root, "hooks/local/mirror-agents.sh"), sh(root, "hooks/local/mirror-agents.sh")
        lines = first.stdout.splitlines()
        canon_equal = all((root / f"{m}/{p.parent.name}.md").read_bytes() == p.read_bytes()
                          for p in (root / "agents").glob("*/AGENT.md") for m in (".claude/agents", ".codex/agents"))
        report("mirror-agents-wiring", first.returncode == 0 and len(lines) == 3 and MIRRORED_RE.fullmatch(lines[0])
               and lines[1].startswith("[mirror-agents] manifest: ") and "project variants: generated 1;" in lines[2]
               and canon_equal and (root / MANIFEST).read_bytes() == (plain / MANIFEST).read_bytes()
               and second.returncode == 0 and "copied 0;" in second.stdout and "current 1;" in second.stdout,
               f"{first.returncode}/{second.returncode} {first.stdout!r} {second.stdout!r} {first.stderr!r}")

        (root / AD).write_bytes((root / AD).read_bytes() + b"hand edit\n")
        kept = sh(root, "hooks/local/mirror-agents.sh")
        report("mirror-agents-preserve", kept.returncode == 1
               and f"[mirror-agents] preserved {AD}" in kept.stderr, f"rc {kept.returncode} {kept.stderr!r}")

        (root / AD).unlink()
        profile(root, {"ai-developer": [TOOL], "product-owner": [TOOL]})
        sh(root, "hooks/local/mirror-agents.sh")
        commit(root, PROFILE)
        canon = root / "agents/product-owner/AGENT.md"
        canon.write_bytes(canon.read_bytes() + b"\nUpgraded body line.\n")
        preflight = (REPO / "hooks/local/preflight.sh").as_posix()
        stale = sh(root, preflight)
        found = [line for line in (stale.stdout + stale.stderr).splitlines() if "agent tool profile:" in line]
        drift = [line for line in found if f"agent variant drift: {PO}" in line]
        put(root, PROFILE, json.dumps({"schema_version": 1, "agents": {"ai-developer": {"add_tools": ["Agent"]}}}))
        broken = sh(root, preflight)
        report("preflight-5d", len(drift) == 1 and "warn:" in drift[0]
               and not any("ai-developer-project" in line for line in found)
               and "ERROR: agent tool profile:" in broken.stdout + broken.stderr,
               f"found {found!r}; invalid run tail {(broken.stdout + broken.stderr)[-400:]!r}")


def main() -> int:
    for row in (row_compose_shape, row_apply_cycle, row_hand_edit, row_invalid_profiles, row_dup_and_orphans,
                row_canonical_removed_orphan, row_no_profile_and_twin, row_crlf, row_managed_set, row_check_states, row_maintainer_guards,
                row_helper_copy_parity):
        try:
            row()
        except Exception as exc:
            report(row.__name__.replace("row_", "").replace("_", "-"), False, f"crashed: {exc!r}")
    if "--with-shell" in sys.argv[1:]:
        try:
            shell_rows()
        except Exception as exc:
            report("shell-rows", False, f"crashed: {exc!r}")
    return FAILS


if __name__ == "__main__":
    raise SystemExit(main())
