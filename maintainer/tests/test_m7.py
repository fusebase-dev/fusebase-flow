#!/usr/bin/env python3
"""The 6.0.0-m7 pass: `python maintainer/tests/test_m7.py`; test_migrate.py's load_tests runs it too, so core-verify
carries it."""
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import zlib
from pathlib import Path

import test_m6
from synthetic import git, migrate, no_auto_gc, scratch_clone

CORE = Path(__file__).resolve().parents[2]
WINDOWS = os.name == "nt"


def short_name(path: Path) -> str:
    """The 8.3 alias of an existing path (Windows), or the path as given when the volume makes none."""
    import ctypes
    buf = ctypes.create_unicode_buffer(1024)
    n = ctypes.windll.kernel32.GetShortPathNameW(str(path), buf, len(buf))
    return buf.value if 0 < n < len(buf) else str(path)


def git_bytes(repo: Path, *args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=repo, capture_output=True, timeout=600).stdout


class ToolTimePaths(test_m6.Project):
    """m7 item 1: the wired PreToolUse handler judges the path git names, whatever spelling the tool sends: an 8.3
    short name, another case, `..`, `./`, a symlink, a path relative to the session's folder, NotebookEdit's
    notebook_path. Before, `Path(target).relative_to(root)` raised on any of them and the edit was allowed."""

    def decide(self, name: str, tool_input: dict, cwd: str | None = None) -> str:
        settings = json.loads((self.repo / ".claude/settings.json").read_text(encoding="utf-8"))
        command = next(h["command"] for group in settings["hooks"]["PreToolUse"] for h in group["hooks"]
                       if "pre_tool_use.py" in h["command"])
        payload = {"session_id": "m7", "cwd": cwd or str(self.repo), "hook_event_name": "PreToolUse",
                   "tool_name": name, "tool_input": tool_input}
        out = test_m6.sh(self.repo, test_m6.BASH, "-c", command, stdin=json.dumps(payload),
                         CLAUDE_PROJECT_DIR=str(self.repo))
        decision = json.loads(out.stdout or "{}").get("flow_decision")
        self.assertEqual(out.returncode, 2 if decision == "deny" else 0, out.stderr)
        return decision

    def test_dot_dot_dot_slash_relative_and_notebook_forms_of_a_protected_file_are_denied(self) -> None:
        (self.repo / "src").mkdir()
        for form in ("src/../policies/command-policy.yml", "./policies/command-policy.yml",
                     str(self.repo / "src" / ".." / "FLOW_RULES.md"), str(self.repo / "." / "hooks/shared/path_policy.py")):
            self.assertEqual(self.decide("Write", {"file_path": form, "content": "x\n"}), "deny", form)
        self.assertEqual(self.decide("Edit", {"file_path": "../FLOW_RULES.md", "old_string": "a", "new_string": "b"},
                                     cwd=str(self.repo / "src")), "deny", "a path relative to the session's folder")
        self.assertEqual(self.decide("NotebookEdit", {"notebook_path": str(self.repo / "hooks/shared/probe.ipynb"),
                                                      "new_source": "x = 1"}), "deny", "NotebookEdit's notebook_path")
        self.assertEqual(self.decide("Write", {"file_path": "src/app.ts", "content": "x\n"}), "allow")
        self.assertEqual(self.decide("Write", {"file_path": "policies/x.yml", "content": "x\n"},
                                     cwd=str(self.repo / "src")), "allow", "src/policies/x.yml is no Flow file")

    @unittest.skipUnless(WINDOWS, "8.3 short names and case-blind paths are Windows'")
    def test_an_8_3_short_name_and_another_case_of_a_protected_file_are_denied(self) -> None:
        target = self.repo / "policies" / "command-policy.yml"
        short = short_name(target)
        forms = [str(target).upper(), str(target).lower()]
        if short != str(target):
            forms.insert(0, short)
        else:
            print("\n[m7] this volume makes no 8.3 names here; the short-name form is GoAheadShortTemp's")
        for form in forms:
            self.assertEqual(self.decide("Edit", {"file_path": form, "old_string": "a", "new_string": "b"}), "deny", form)
        self.assertEqual(self.decide("Write", {"file_path": str(self.repo / "notes.md").upper(), "content": "x\n"}),
                         "allow")

    def test_a_symlinked_path_to_a_protected_file_is_denied(self) -> None:
        link = self.repo / "linked"
        try:
            os.symlink(self.repo / "policies", link, target_is_directory=True)
        except (OSError, NotImplementedError) as exc:
            self.skipTest(f"no symlink here ({exc})")
        self.assertEqual(self.decide("Write", {"file_path": str(link / "command-policy.yml"), "content": "x\n"}), "deny")
        self.assertEqual(self.decide("Write", {"file_path": "linked/command-policy.yml", "content": "x\n"}), "deny")


@unittest.skipUnless(WINDOWS, "an 8.3 temp folder is Windows' (the runner's C:\\Users\\RUNNER~1)")
class GoAheadShortTemp(test_m6.GoAhead):
    """The three test_m6.GoAhead tests with TMP and TEMP at an 8.3 alias, as on GitHub's Windows runner (core-verify
    run 39487718435): the payload names the project by its short name, git by its long one."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.long = Path(tempfile.mkdtemp(prefix="flow-m7-a-folder-with-a-long-name-"))
        cls.short = short_name(cls.long)
        if cls.short == str(cls.long):
            shutil.rmtree(cls.long, ignore_errors=True)
            raise unittest.SkipTest("this volume makes no 8.3 names")

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.long, ignore_errors=True)

    def setUp(self) -> None:
        self.saved = tempfile.tempdir
        tempfile.tempdir = self.short
        try:
            super().setUp()
        finally:
            tempfile.tempdir = self.saved
        self.assertNotEqual(str(self.repo), str(self.repo.resolve()), "the project is not spelled by its 8.3 name")


# Onboarding's .gitattributes at b176a73d, its 5.x part: the comment and pin lines Flow 5.x left there
PINS_5X = """\
# FuseBase Flow line-ending pins, scoped to Flow-owned paths only (so existing
# app files are not renormalized). core.autocrlf=true would otherwise check these
# out as CRLF and break the bash/python hooks and Flow's byte-hash integrity checks.
hooks/**            text eol=lf
flow-skills/**      text eol=lf
agents/**           text eol=lf
policies/**         text eol=lf
templates/**        text eol=lf
workflows/**        text eol=lf
audit/**            text eol=lf
state/**            text eol=lf
.agents/skills/**   text eol=lf
.codex/agents/**    text eol=lf
.claude/commands/** text eol=lf
.claude/agents/ai-developer.md   text eol=lf
VERSION             text eol=lf
FLOW_RULES.md       text eol=lf
GEMINI.md           text eol=lf
# Flow skill mirrors in .claude/skills (CLI provider skills there are left alone)
.claude/skills/code-review/** text eol=lf
.claude/skills/zoom-out/** text eol=lf
"""
PROJECT_LINES = "*.sql               text eol=lf\n*.sketch binary\n.claude/skills/our-own/** text eol=lf\n"


def png() -> bytes:
    """A real PNG whose compressed data holds CRLF pairs, as r1-03's fixture builds it."""
    raw = b"".join(b"\x00" + bytes((x * 7 + y * 13) % 256 for x in range(320 * 3)) for y in range(200))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 320, 200, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


class EolPins(unittest.TestCase):
    """m7 item 2 (M6-1, review r1-03): 5.x's folder-wide `text eol=lf` lines made git rewrite the CRLF bytes of a
    binary committed under those folders. migrate replaces them with 6.0's exact-path block (backed up, listed in the dry
    run); install removes them on an upgrade and names them; the project's own lines stay."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-m7-eol-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def assert_png_kept(self, repo: Path, rel: str) -> None:
        data = png()
        self.assertGreater(data.count(b"\r\n"), 0)
        (repo / rel).parent.mkdir(parents=True, exist_ok=True)
        (repo / rel).write_bytes(data)
        git(repo, "add", "--", rel)
        attrs = git(repo, "check-attr", "text", "eol", "--", rel).stdout
        stored = git_bytes(repo, "cat-file", "blob", f":{rel}")
        self.assertEqual(stored, data, f"git stored {len(stored)} of {len(data)} bytes; attributes:\n{attrs}")

    def test_migrate_replaces_the_5x_pins_lists_them_backs_them_up_and_a_png_under_templates_keeps_its_bytes(self) -> None:
        clone = scratch_clone(self.tmp, {".gitattributes": PINS_5X + PROJECT_LINES})
        dry = migrate(clone, "--providers", "claude,codex")
        self.assertEqual(dry.returncode, 0, dry.stdout + dry.stderr)
        run = migrate(clone, "--providers", "claude,codex", "--apply", "--go-ahead")
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assert_png_kept(clone, "templates/img/header.png")
        self.assert_png_kept(clone, "state/runs/P1/run1/login.png")
        self.assertIn(".gitattributes: 21 Flow 5.x line-ending pin lines go", dry.stdout)
        self.assertIn("hooks/**            text eol=lf", dry.stdout)
        text = (clone / ".gitattributes").read_text(encoding="utf-8")
        for line in PINS_5X.splitlines():
            self.assertNotIn(line + "\n", text)
        for line in PROJECT_LINES.splitlines():
            self.assertIn(line + "\n", text)
        self.assertIn("/hooks/git/pre-commit text eol=lf", text)
        backup = next(clone.glob(".flow-migrate-*/.gitattributes"))
        self.assertEqual(backup.read_text(encoding="utf-8"), PINS_5X + PROJECT_LINES)

    def test_an_upgrade_removes_them_names_them_keeps_the_projects_lines_and_the_flow_commit_carries_the_removal(self) -> None:
        repo = self.tmp / "project"
        repo.mkdir()
        git(repo, "init", "-q", "-b", "main")
        no_auto_gc(repo)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(test_m6.flow.install(repo, {"claude", "codex"}), 0)
        attributes = repo / ".gitattributes"
        attributes.write_text(PINS_5X + PROJECT_LINES + "\n" + attributes.read_text(encoding="utf-8"), encoding="utf-8")
        git(repo, "add", "-A")
        self.assertEqual(git(repo, "commit", "-q", "--no-verify", "-m", "init").returncode, 0)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(test_m6.flow.install(repo, {"claude", "codex"}), 0)
        self.assert_png_kept(repo, "templates/img/header.png")
        git(repo, "rm", "-q", "--cached", "--", "templates/img/header.png")
        self.assertIn("[flow] .gitattributes: removed 21 Flow 5.x line-ending pin lines", out.getvalue())
        self.assertIn("[flow]   templates/**        text eol=lf", out.getvalue())
        text = attributes.read_text(encoding="utf-8")
        self.assertNotIn("templates/**", text)
        for line in PROJECT_LINES.splitlines():
            self.assertIn(line + "\n", text)
        git(repo, "add", "--", ".gitattributes")
        sys.path.insert(0, str(CORE / "hooks/local/lib"))
        import flow_owned
        self.assertEqual(flow_owned.foreign(repo, [("M", ".gitattributes")]), [], "the flow: commit refuses the removal")
        attributes.write_text(text.replace("*.sketch binary\n", ""), encoding="utf-8")
        git(repo, "add", "--", ".gitattributes")
        self.assertEqual(flow_owned.foreign(repo, [("M", ".gitattributes")]), [".gitattributes"], "a project line went too")


class RangeCheck(unittest.TestCase):
    """m7 item 3 (M6-2, review r1-23, r2-25, r3-25..27): git runs no pre-commit for a clean merge, a cherry-pick, a
    rebase's replays or a revert. pre-merge-commit checks what a merge brings in; pre-push checks every commit the remote
    lacks: secret patterns, and protected-path changes with no approval on record."""

    KEY = "AKIA" + "IOSFODNN7EXAMPLE"  # assembled at run time, so no scanner sees the literal in this file

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-m7-range-"))
        self.repo, self.remote = self.tmp / "project", self.tmp / "remote.git"
        self.repo.mkdir()
        for args in (("init", "-q", "-b", "main", str(self.repo)), ("init", "-q", "--bare", "-b", "main", str(self.remote))):
            git(self.tmp, *args)
        no_auto_gc(self.repo)
        for key, value in (("user.name", "flow-test"), ("user.email", "flow-test@example.invalid")):
            git(self.repo, "config", key, value)
        (self.repo / "README.md").write_text("demo\n", encoding="utf-8")
        self.git("add", "README.md")
        self.git("commit", "-q", "--no-verify", "-m", "init")
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "-q", "--no-verify", "origin", "main")  # the remote's history: before any Flow hook
        self.git("checkout", "-q", "-b", "work")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(test_m6.flow.install(self.repo, {"claude"}), 0)
        self.git("add", "-A")
        # Flow's own install commit, made here without the hooks: a `flow:` commit flow_owned.py accepts
        self.git("commit", "-q", "--no-verify", "-m", "flow: install Fusebase Flow")

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def git(self, *args: str, ok: bool = True) -> subprocess.CompletedProcess:
        out = subprocess.run(["git", *args], cwd=self.repo, capture_output=True, text=True, encoding="utf-8",
                             errors="replace", timeout=900)
        if ok:
            self.assertEqual(out.returncode, 0, f"git {' '.join(args)}: {out.stdout}{out.stderr}")
        return out

    def commit(self, rel: str, text: str, subject: str, *flags: str) -> str:
        (self.repo / rel).parent.mkdir(parents=True, exist_ok=True)
        (self.repo / rel).write_text(text, encoding="utf-8")
        self.git("add", "--", rel)
        self.git("commit", "-q", *flags, "-m", subject)
        return self.git("rev-parse", "HEAD").stdout.strip()

    def side_secret(self, branch: str = "side") -> str:
        self.git("checkout", "-q", "-b", branch, "work")
        sha = self.commit("config/settings.txt", f"aws_access_key_id = {self.KEY}\n", "T1: settings", "--no-verify")
        self.git("checkout", "-q", "work")
        return sha

    def test_a_merge_bringing_in_a_secret_is_refused_and_a_merge_of_the_remotes_work_is_not(self) -> None:
        self.side_secret()
        merged = self.git("merge", "--no-ff", "--no-edit", "side", ok=False)
        self.assertNotEqual(merged.returncode, 0, "the merge carrying a token landed")
        self.assertIn("[fusebase-flow:pre-merge-commit] BLOCK", merged.stderr)
        self.assertIn("aws_access_key_id", merged.stderr)
        self.git("merge", "--abort", ok=False)
        # a teammate's approved protected change arrives through the remote: merging it is not refused
        self.git("checkout", "-q", "-b", "team", "work")
        self.commit("FLOW_RULES.md", (self.repo / "FLOW_RULES.md").read_text(encoding="utf-8") + "\nteam note\n",
                    "T2: a teammate's rule note", "--no-verify")
        self.git("push", "-q", "--no-verify", "origin", "team")
        self.git("checkout", "-q", "work")
        self.commit("docs/notes.md", "a note\n", "T3: a note", "--no-verify")
        self.git("fetch", "-q", "origin")
        self.git("merge", "--no-ff", "--no-edit", "origin/team")

    def test_a_cherry_picked_or_rebased_secret_is_refused_at_push_and_a_clean_push_passes(self) -> None:
        sha = self.side_secret()
        self.git("cherry-pick", sha)
        pushed = self.git("push", "origin", "work", ok=False)
        self.assertNotEqual(pushed.returncode, 0, "the cherry-picked token reached the remote")
        self.assertIn("[fusebase-flow:pre-push] BLOCK", pushed.stderr)
        self.assertIn("secret pattern aws_access_key_id", pushed.stderr)
        self.git("checkout", "-q", "-b", "rebased", "side")
        self.git("rebase", "-q", "main")
        pushed = self.git("push", "origin", "rebased", ok=False)
        self.assertNotEqual(pushed.returncode, 0, "the rebased token reached the remote")
        self.assertIn("secret pattern aws_access_key_id", pushed.stderr)
        self.git("checkout", "-q", "-b", "clean", "work~1")
        self.commit("docs/notes.md", "a note\n", "T1: a note")  # through the hooks
        for n in range(50):
            self.commit(f"docs/n{n}.md", f"note {n}\n", f"T{n + 2}: note {n}", "--no-verify")
        started = time.monotonic()
        pushed = self.git("push", "origin", "clean", ok=False)
        print(f"\n[m7] pre-push range check over 52 commits (the flow: install commit included): "
              f"{time.monotonic() - started:.1f} s")
        self.assertEqual(pushed.returncode, 0, pushed.stderr)

    def test_a_revert_of_an_approved_flow_rules_edit_is_refused_at_push(self) -> None:
        (self.repo / "FLOW_RULES.md").write_text((self.repo / "FLOW_RULES.md").read_text(encoding="utf-8") + "\nx\n",
                                                 encoding="utf-8")
        self.git("add", "--", "FLOW_RULES.md")
        mint = test_m6.sh(self.repo, test_m6.BASH, "hooks/local/write-bootstrap-approval.sh", FF_BOOTSTRAP_TTL_MIN="30")
        self.assertEqual(mint.returncode, 0, mint.stderr)
        self.git("commit", "-q", "-m", "T1: an approved rule edit")
        test_m6.sh(self.repo, test_m6.BASH, "hooks/local/write-bootstrap-approval.sh", "--consume")
        pushed = self.git("push", "origin", "work", ok=False)
        self.assertEqual(pushed.returncode, 0, f"the approved edit was refused: {pushed.stderr}")
        self.git("revert", "--no-edit", "HEAD")
        pushed = self.git("push", "origin", "work", ok=False)
        self.assertNotEqual(pushed.returncode, 0, "the revert of an approved FLOW_RULES.md edit reached the remote")
        self.assertIn("FLOW_RULES.md changed with no approval on record", pushed.stderr)


class CheckoutBytes(unittest.TestCase):
    """m7 item 3, found by the one-step upgrade rehearsed on a copy: a Windows clone of the release (core.autocrlf=true)
    checked hooks/git/pre-merge-commit out with CRLF, since the core's .gitattributes pinned only the three older hooks;
    the install recorded those bytes, and the `flow:` upgrade commit, whose staged blob git had made LF, was refused."""

    def test_every_script_the_install_copies_is_checked_out_with_lf(self) -> None:
        sys.path.insert(0, str(CORE / "maintainer"))
        import flow
        scripts = [p for p in flow.core_files() if flow.matches(p, flow.EXECUTABLE) or p.endswith(".py")]
        self.assertIn("hooks/git/pre-merge-commit", scripts)
        out = subprocess.run(["git", "check-attr", "eol", "--", *scripts], cwd=CORE, capture_output=True, text=True,
                             timeout=600).stdout
        self.assertEqual([ln.split(":")[0] for ln in out.splitlines() if not ln.endswith(": eol: lf")], [],
                         "checked out with the platform's line endings (CRLF under core.autocrlf=true)")


class CrlfCheckout(unittest.TestCase):
    """The coordinator's follow-up to T324: a release already cloned with CRLF bytes (an older clone, a file a pin missed)
    installs LF bytes and records their sha, so the `flow:` commit that stages them (git makes them LF) is Flow's."""

    def test_a_crlf_checkout_installs_and_records_lf_and_the_flow_commit_accepts_it(self) -> None:
        tmp = Path(tempfile.mkdtemp(prefix="flow-m7-crlf-"))
        self.addCleanup(shutil.rmtree, tmp, True)
        core = tmp / "fusebase-flow"
        shutil.copytree(CORE, core, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        crlf = ("hooks/git/pre-merge-commit", "hooks/local/lib/eol_pins.py", "flow-skills/plan/SKILL.md")
        for rel in crlf:
            (core / rel).write_bytes((core / rel).read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
        project = tmp / "project"
        project.mkdir()
        git(project, "init", "-q", "-b", "main")
        no_auto_gc(project)
        out = subprocess.run([sys.executable, str(core / "maintainer/flow.py"), "install", "--target", str(project),
                              "--providers", "claude"], capture_output=True, text=True, timeout=900)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        manifest = {e["path"]: e["sha256"] for e in json.loads((project / "audit/flow-install.json").read_text())["files"]}
        for rel in (*crlf, ".claude/skills/plan/SKILL.md"):
            data = (project / rel).read_bytes()
            self.assertNotIn(b"\r\n", data, rel)
            self.assertEqual(manifest[rel], hashlib.sha256(data).hexdigest(), rel)
        git(project, "add", "-A")
        pairs = [ln.split("\t", 1) for ln in git(project, "diff", "--cached", "--name-status").stdout.splitlines()]
        found = subprocess.run([sys.executable, "-c", "import sys, json; sys.path.insert(0, 'hooks/local/lib'); "
                                "import flow_owned; from pathlib import Path; "
                                "print(json.dumps(flow_owned.foreign(Path('.'), json.loads(sys.argv[1]))))",
                                json.dumps(pairs)], cwd=project, capture_output=True, text=True, timeout=600)
        self.assertEqual(json.loads(found.stdout or "null"), [], found.stderr)


class Installed(unittest.TestCase):
    """A git project with Flow installed (claude and codex), nothing committed, no tool hooks wired."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-m7-inst-"))
        self.repo = self.tmp / "project"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        no_auto_gc(self.repo)
        self.install()

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def install(self, **kwargs) -> str:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(test_m6.flow.install(self.repo, {"claude", "codex"}, **kwargs), 0)
        return out.getvalue()


class HealthTruth(Installed):
    """m7 item 4 (M6-3, review r1-21, r2-92): health said healthy in three states where Flow does not hold:
    core.hooksPath pointing away from Flow's hooks (Husky writes it), a hooks.json that names a handler without
    registering it, and a Flow file an upgrade kept (the project's edit) beside the new release's files."""

    def health(self) -> tuple[int, str]:
        import health
        rc, lines = health.report(self.repo)
        return rc, "\n".join(lines)

    def test_core_hookspath_to_an_empty_folder_is_not_healthy_and_install_warns_and_writes_nothing_there(self) -> None:
        self.assertEqual(self.health()[0], 0)
        empty = self.tmp / "husky"
        empty.mkdir()
        git(self.repo, "config", "core.hooksPath", str(empty))
        rc, text = self.health()
        self.assertEqual(rc, 1, text)
        self.assertIn("core.hooksPath makes git run the hooks in", text)
        self.assertIn("HEALTH: NOT healthy", text)
        out = self.install()
        self.assertIn("[flow] WARNING: core.hooksPath makes git run the hooks in", out)
        self.assertEqual(list(empty.iterdir()), [], "install wrote into the hook manager's folder")

    def test_a_hooks_json_that_names_a_handler_without_registering_it_is_not_wired(self) -> None:
        (self.repo / ".codex").mkdir(exist_ok=True)
        (self.repo / ".codex/hooks.json").write_text('{"note": "see hooks/handlers/pre_tool_use.py", "hooks": {}}\n',
                                                     encoding="utf-8")
        self.assertIn("wiring: codex unenforced (.codex/hooks.json)", self.health()[1])
        import wire
        (self.repo / ".codex/hooks.json").write_text(json.dumps({"hooks": {k: [v] for k, v in wire.entries("codex").items()}}),
                                                     encoding="utf-8")
        self.assertIn("wiring: codex wired (.codex/hooks.json)", self.health()[1])

    def test_a_kept_older_flow_file_is_listed_as_not_current_and_a_kept_hook_file_is_not_healthy(self) -> None:
        checks = self.repo / "hooks/local/checks.py"
        checks.write_bytes(checks.read_bytes() + b"# the project's edit, kept by the upgrade\n")
        self.assertIn("[flow]   hooks/local/checks.py (differs; not a Flow-owned unedited file)", self.install())
        rc, text = self.health()
        self.assertEqual(rc, 1, text)
        self.assertIn("kept, not current: hooks/local/checks.py", text)
        self.assertIn("a hook-layer file kept from an earlier release: hooks/local/checks.py", text)


class LocalTightens(Installed):
    """m7 item 5 (M6-4, review r2-34): a gitignored *.local.yml only ever tightens. Written through Bash, `deny: []` in
    command-policy.local.yml emptied the deny list: the handler then allowed `git commit --no-verify`. A Bash write into
    policies/ or state/approvals/ is denied; Flow's own scripts write there."""

    def decide(self, tool: str, tool_input: dict) -> str:
        payload = {"session_id": "m7", "cwd": str(self.repo), "hook_event_name": "PreToolUse", "tool_name": tool,
                   "tool_input": tool_input}
        out = subprocess.run([sys.executable, "hooks/handlers/pre_tool_use.py"], cwd=self.repo, input=json.dumps(payload),
                             capture_output=True, text=True, encoding="utf-8", timeout=300)
        return json.loads(out.stdout or "{}").get("flow_decision", f"no decision: {out.stderr}")

    def bash(self, command: str) -> str:
        return self.decide("Bash", {"command": command})

    def local(self, name: str, text: str) -> None:
        (self.repo / "policies" / f"{name}.local.yml").write_text(text, encoding="utf-8")

    def test_an_emptied_deny_list_in_the_local_command_policy_leaves_no_verify_denied(self) -> None:
        self.local("command-policy", "deny: []\nrequire_approval: []\ndefault: allow\nallow:\n"
                                     "  - pattern: '.*'\n    reason: everything\n    rule_id: LOCAL\n")
        for command in ("git commit --no-verify -m x", "git config core.hooksPath /dev/null", "git reset --hard HEAD"):
            self.assertEqual(self.bash(command), "deny", command)
        self.assertEqual(self.bash("npx prisma migrate deploy"), "deny", "a shipped approval rule went")

    def test_a_local_file_that_adds_a_deny_rule_takes_effect_beside_the_shipped_ones(self) -> None:
        self.local("command-policy", "deny:\n  - pattern: '\\bcurl\\b'\n    reason: no curl in this project\n"
                                     "    rule_id: LOCAL-1\n")
        self.assertEqual(self.bash("curl https://example.com"), "deny")
        self.assertEqual(self.bash("git commit --no-verify -m x"), "deny")
        self.assertEqual(self.bash("ls -la"), "allow")

    def test_a_shell_write_into_policies_or_state_approvals_is_denied_and_reading_them_is_not(self) -> None:
        for command in ("printf 'deny: []\\n' > policies/command-policy.local.yml",
                        "echo '{}' >> state/approvals/protected_path_edit-x.json",
                        "tee -a policies/command-policy.local.yml < /dev/null",
                        "cp /tmp/x.yml policies/command-policy.local.yml", "mv x.json state/approvals/",
                        "cp -t policies x.yml", "sed -i s/deny/allow/ policies/command-policy.yml",
                        "python -c \"open('policies/command-policy.local.yml', 'w').write('deny: []')\"",
                        "python3 -c \"from pathlib import Path; Path('state/approvals/a.json').write_text('{}')\"",
                        "cat > ./policies/secret-patterns.local.yml <<'EOF'\nwhitelist: []\nEOF",
                        "echo x > .git/flow/approved-changes.tsv"):
            self.assertEqual(self.bash(command), "deny", command)
        for command in ("cat policies/command-policy.yml", "git add -- policies/module-size-baseline.project.txt",
                        "if [ -f policies/module-size-baseline.project.txt ]; then git add -- "
                        "policies/module-size-baseline.project.txt; fi",
                        "FF_BOOTSTRAP_TTL_MIN=30 bash hooks/local/write-bootstrap-approval.sh",
                        "bash hooks/local/write-bootstrap-approval.sh --consume",
                        "cp policies/command-policy.yml /tmp/backup.yml", "grep -n deny policies/*.yml > /tmp/out.txt",
                        "ls state/approvals/", "git status --short"):
            self.assertEqual(self.bash(command), "allow", command)

    def test_an_existing_projects_local_tightening_still_works_and_nothing_it_holds_loosens(self) -> None:
        shipped = (self.repo / "policies/secret-patterns.yml").read_text(encoding="utf-8")
        start = shipped.index("\npatterns:\n")
        stop = shipped.index("\n# Per-tool overrides")
        # the field's form (paperclip+hermes): the whole shipped list copied, two patterns added at the end
        self.local("secret-patterns", "schema_version: 1\n" + shipped[start:stop] + "\n"
                   "  - id: json_token_value\n    category: generic\n    pattern: '\"token\":\\s*\"[0-9a-f]{64}\"'\n"
                   "    confidence: high\n"
                   "whitelist:\n  - id: aws_fixture\n    pattern: 'AKIA'\n    reason: loosening, dropped\n")
        token = '{"token": "' + "ab" * 32 + '"}\n'
        self.assertEqual(self.decide("Write", {"file_path": str(self.repo / "out.json"), "content": token}), "deny")
        self.assertEqual(self.decide("Write", {"file_path": str(self.repo / "a.txt"),
                                               "content": "id = AKIA" + "IOSFODNN7EXAMPLE\n"}), "deny")
        self.local("protected-paths", "categories:\n  worker_undisturbed:\n    paths: ['src/billing/**']\n"
                                      "  fusebase_flow_internals:\n    paths: []\non_unapproved_edit: warn\n")
        self.assertEqual(self.decide("Write", {"file_path": "src/billing/x.ts", "content": "x\n"}), "deny")
        self.assertEqual(self.decide("Write", {"file_path": "FLOW_RULES.md", "content": "x\n"}), "deny")
        self.local("approval-policy", "on_missing_artifact: warn\nworkflow_mode: branch_pr\n")
        self.assertEqual(self.bash("npx prisma migrate deploy"), "deny")
        self.local("module-size", "exempt_globs: ['src/**']\nsource_globs: ['extra/**/*.py']\n")
        probe = ("import sys; from pathlib import Path; sys.path.insert(0, 'hooks'); from shared import module_size as m; "
                 "p = m._load_policy(Path('.')); print('src/**' in (p.get('exempt_globs') or []), "
                 "'extra/**/*.py' in (p.get('source_globs') or []))")
        out = subprocess.run([sys.executable, "-c", probe], cwd=self.repo, capture_output=True, text=True, timeout=300)
        self.assertEqual(out.stdout.split(), ["False", "True"], out.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
