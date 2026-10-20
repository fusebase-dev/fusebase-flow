#!/usr/bin/env python3
"""The 6.0.0-m7 pass: `python maintainer/tests/test_m7.py`; test_migrate.py's load_tests runs it too, so core-verify
carries it."""
from __future__ import annotations

import contextlib
import io
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
