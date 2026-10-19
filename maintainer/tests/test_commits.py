#!/usr/bin/env python3
"""The 6.0.0-m4 micro-pass fixtures: the commit-msg interpreter (O-19), the CLI's checkpoint subjects (O-20) and
the Microsoft Store shortcut first on PATH (T269).

`python maintainer/tests/test_commits.py`; test_migrate.py's load_tests runs it too, so core-verify carries it.
"""
from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

import test_scripts as m3
from synthetic import migrate, scratch_clone
from test_core import MSG_BACKLOG
from test_scripts import CORE, Workspace, write

sys.path.insert(0, str(CORE / "maintainer"))
import flow  # noqa: E402

PHASES = ("# Phases\n- reference: none\n\n## P1 First\n- base: pending\n\n### P1-S1 The slice\n"
          "| Task | Item | Does | Globs | Estimate |\n|---|---|---|---|---|\n"
          "| T1 | B1 | the sign-in | `src/**` | 30m 2f |\n")
# The CLI's own subjects: update-git-checkpoint.ts, `toLocaleString(undefined, {dateStyle: "medium", timeStyle:
# "medium"})`; en-US carries U+202F before PM under Node's ICU.
CLI_SUBJECTS = ("chore(update): pre app update (Oct 18, 2026, 7:51:03\u202fPM)",
                "chore(update): post app update (18.10.2026, 19:51:03)")


class NoPython3(Workspace):
    """A PATH that holds no python3: a folder for the shims, then git and the coreutils the scripts call."""

    TOOLS = ("git", "date", "mkdir", "rm", "sed")

    def setUp(self) -> None:
        super().setUp()
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        if os.name == "nt":  # Git\cmd and Git\usr\bin hold no Python; a native git is found only by its .exe
            dirs = dict.fromkeys(str(Path(shutil.which(t)).parent) for t in self.TOOLS)
            self.path = os.pathsep.join([str(self.bin), *dirs])
        else:  # /usr/bin holds python3 too: links to the tools alone
            for t in self.TOOLS:
                os.symlink(shutil.which(t), self.bin / t)
            self.path = str(self.bin)

    def shim(self, name: str, *flags: str) -> None:
        """`name` runs this Python; `py` drops the -3 it is called with."""
        drop = '[ "$1" = "-3" ] && shift\n' if name == "py" else ""
        exe = Path(sys.executable).as_posix()
        (self.bin / name).write_text(f'#!/bin/sh\n{drop}exec "{exe}" {" ".join(flags)} "$@"\n', encoding="utf-8",
                                     newline="\n")
        (self.bin / name).chmod(0o755)

    def bash(self, *argv: str, **env: str) -> subprocess.CompletedProcess:
        return subprocess.run([shutil.which("bash"), *argv], cwd=self.repo, capture_output=True, text=True,
                              env={**os.environ, **env, "PATH": self.path}, encoding="utf-8", errors="replace",
                              timeout=600)

    def no_python3(self) -> None:
        self.assertEqual(self.bash("-c", "command -v python3").stdout.strip(), "", "python3 must not be on PATH")


class Interpreter(NoPython3):
    """O-19: commit-msg finds Python as the pre-commit does (python3, then python, then py -3), and a missing PyYAML is
    one Flow line, never a traceback."""

    def setUp(self) -> None:
        super().setUp()
        for rel in ("hooks/local/lib/commit_msg.py", "hooks/local/lib/flow_docs.py", "hooks/local/lib/flow_owned.py"):
            write(self.repo, rel, (CORE / rel).read_text(encoding="utf-8"))
        m3.git(self.repo, "add", "--", "hooks")

    def hook(self, subject: str) -> subprocess.CompletedProcess:
        (self.tmp / "msg.txt").write_text(subject + "\n", encoding="utf-8")
        return self.bash(str(CORE / "hooks/git/commit-msg"), str(self.tmp / "msg.txt"))

    def test_python_alone_or_py_alone_checks_the_subject(self) -> None:
        for name in ("python", "py"):
            for old in self.bin.glob("py*"):
                old.unlink()
            self.shim(name)
            self.no_python3()
            good = self.hook("T1: the sign-in")
            self.assertEqual(good.returncode, 0, f"{name}: {good.stderr}")
            bad = self.hook("docs: a note")
            self.assertEqual(bad.returncode, 1, name)
            self.assertIn("must cite a T-number", bad.stderr, name)

    def test_a_missing_pyyaml_is_one_block_line_that_names_the_fix(self) -> None:
        self.shim("python3", "-S")  # no site-packages: PyYAML cannot be imported
        if subprocess.run([sys.executable, "-S", "-c", "import yaml"], capture_output=True).returncode == 0:
            self.skipTest("PyYAML importable without site-packages")
        out = self.hook("T1: the sign-in")
        self.assertEqual(out.returncode, 1)
        self.assertNotIn("Traceback", out.stderr)
        lines = out.stderr.strip().splitlines()
        self.assertEqual(len(lines), 1, out.stderr)
        self.assertIn("[fusebase-flow:commit-msg] BLOCK", lines[0])
        self.assertIn("-m pip install -r hooks/requirements.txt", lines[0])


class Approval(NoPython3):
    """T266: both approval scripts find Python as the hooks do, so an approval is minted with no python3 on PATH."""

    def setUp(self) -> None:
        super().setUp()
        for rel in ("hooks/shared", "policies"):
            shutil.copytree(CORE / rel, self.repo / rel, ignore=shutil.ignore_patterns("__pycache__"))
        m3.commit(self.repo, {"FLOW_RULES.md": "# rules\n"}, "init")
        self.shim("python")
        self.no_python3()

    def test_the_bootstrap_and_the_deploy_approval_are_minted_and_accepted(self) -> None:
        write(self.repo, "FLOW_RULES.md", "# rules, edited\n")  # fusebase_flow_internals: needs the bootstrap
        m3.git(self.repo, "add", "--", "FLOW_RULES.md")
        mint = self.bash(str(CORE / "hooks/local/write-bootstrap-approval.sh"), FF_BOOTSTRAP_TTL_MIN="30")
        self.assertEqual(mint.returncode, 0, mint.stdout + mint.stderr)
        made = sorted((self.repo / "state/approvals").glob("protected_path_edit-flow-bootstrap-*.json"))
        self.assertEqual(len(made), 1, mint.stdout + mint.stderr)
        artifact = json.loads(made[0].read_text(encoding="utf-8"))
        self.assertEqual((artifact["paths"], len(artifact["tree_digest"])), (["FLOW_RULES.md"], 64))
        used = self.bash(str(CORE / "hooks/local/write-bootstrap-approval.sh"), "--consume")
        self.assertIn("consumed 1 'flow-bootstrap' approval artifact(s)", used.stdout)
        command = "fusebase deploy --env dev"
        deploy = self.bash(str(CORE / "hooks/local/approve-local.sh"), "production_deploy", "t266", "the dev deploy",
                           "--command", command)
        self.assertEqual(deploy.returncode, 0, deploy.stdout + deploy.stderr)
        gate = m3.run("-c", "import sys; from pathlib import Path; sys.path.insert(0, 'hooks'); "
                      "from shared.command_policy import evaluate; d = evaluate(sys.argv[1], root=Path('.')); "
                      "print(d.decision, d.approval_artifact_present)", command, cwd=self.repo)
        self.assertEqual(gate.stdout.split(), ["allow", "True"], gate.stderr)


STORE = ("Python was not found; run without arguments to install from the Microsoft Store, or disable this shortcut "
         "from Settings > Manage App Execution Aliases.")


class StorePath(NoPython3):
    """A PATH with a fake Microsoft Store shortcut first: a python3 in a folder named WindowsApps that prints the
    Store's message and exits 49, as Windows' default App execution aliases resolve python3 on a host with python.org's
    Python (m4b review). The shims and the host's other commands follow; no Python is on it until a test adds a shim."""

    def setUp(self) -> None:
        super().setUp()
        if os.name != "nt":  # NoPython3 links five tools; the hooks need the host's other commands, minus Python
            host = self.tmp / "host"
            host.mkdir()
            for folder in (Path(d) for d in os.environ.get("PATH", "").split(os.pathsep) if d and Path(d).is_dir()):
                for entry in folder.iterdir():
                    interpreter = entry.name.startswith(("python", "pip")) or entry.name == "py"
                    if interpreter or os.path.lexists(host / entry.name):
                        continue
                    if entry.is_file() and os.access(entry, os.X_OK):
                        os.symlink(entry, host / entry.name)
            self.path = os.pathsep.join([self.path, str(host)])
        self.base = self.path
        store = self.tmp / "WindowsApps"
        store.mkdir()
        (store / "python3").write_text(f'#!/bin/sh\necho "{STORE}" >&2\nexit 49\n', encoding="utf-8", newline="\n")
        (store / "python3").chmod(0o755)
        self.path = os.pathsep.join([str(store), self.base])


class StoreShortcut(StorePath):
    """T269: the pre-commit falls through past a python3 that fails its 3.10+ probe to python, then py -3, and blocks
    only when none passes."""

    def setUp(self) -> None:
        super().setUp()
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(flow.install(self.repo, {"claude"}), 0)  # the real git hooks, as a project gets them

    def hook(self) -> subprocess.CompletedProcess:
        write(self.repo, "notes.md", "a note\n")
        m3.git(self.repo, "add", "--", "notes.md")
        return self.bash(".git/hooks/pre-commit")

    def test_a_commit_falls_through_the_store_shortcut_to_python(self) -> None:
        self.assertTrue(self.bash("-c", "command -v python3").stdout.strip().endswith("/WindowsApps/python3"))
        self.shim("python")
        names = m3.git(self.repo, "ls-files", "--others", "--exclude-standard").stdout.splitlines()
        m3.git(self.repo, "add", "--", *names)
        mint = self.bash("hooks/local/write-bootstrap-approval.sh", FF_BOOTSTRAP_TTL_MIN="30")
        self.assertEqual(mint.returncode, 0, mint.stdout + mint.stderr)
        out = subprocess.run([*m3.GIT, "commit", "-q", "-m", "T1: install Fusebase Flow"], cwd=self.repo,
                             env={**os.environ, "PATH": self.path}, capture_output=True, text=True, encoding="utf-8",
                             errors="replace", timeout=900)
        self.bash("hooks/local/write-bootstrap-approval.sh", "--consume")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("WindowsApps/python3, the Microsoft Store shortcut) failed the 3.10+ probe (version=unproven); "
                      "using discovered 'python' for §2/§3", out.stderr)
        for stage in ("stage=secret-scan", "stage=protected-paths", "all checks passed"):
            self.assertIn(stage, out.stderr)
        self.assertEqual(m3.git(self.repo, "log", "--format=%s").stdout.splitlines(), ["T1: install Fusebase Flow"])
        self.assertEqual(list((self.repo / "state/approvals").glob("*.json")), [], "consumed")

    def test_any_python3_that_fails_the_probe_falls_through_to_py_3(self) -> None:
        self.shim("python3", "-c", "'raise SystemExit(7)'")  # not under WindowsApps; every run exits 7
        self.shim("py")
        self.path = self.base
        out = self.hook()
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("failed the 3.10+ probe (version=unproven); using discovered 'py -3' for §2/§3", out.stderr)
        self.assertNotIn("Microsoft Store shortcut", out.stderr)
        self.assertIn("all checks passed", out.stderr)

    def test_the_store_shortcut_alone_blocks_and_names_the_aliases(self) -> None:
        out = self.hook()
        self.assertEqual(out.returncode, 1, out.stderr)
        self.assertIn("did not prove Python 3.10+ (version=unproven), and neither python nor py -3 did", out.stderr)
        self.assertIn(STORE, out.stderr, "the probe's own stderr is replayed")
        self.assertIn("turn off the python.exe and python3.exe App execution aliases", out.stderr)
        self.assertIn("or install Python 3.10+", out.stderr)
        self.assertNotIn("all checks passed", out.stderr)


class StorePreflight(StorePath):
    """T270: the migration preflight finds Python as the pre-commit does, so it never says ok to a commit the pre-commit
    then refuses; it names the interpreter the hooks will run, and the way out when there is none."""

    def preflight_line(self, out: str) -> str:
        found = [line for line in out.splitlines() if ": Python for the hooks: " in line]
        self.assertEqual(len(found), 1, out)
        return found[0]

    def test_behind_the_shortcut_it_names_python_and_the_migration_commits(self) -> None:
        self.shim("python")
        clone = scratch_clone(self.tmp / "m")
        run = migrate(clone, "--apply", "--go-ahead", env={**os.environ, "PATH": self.path})
        self.assertEqual(run.returncode, 0, run.stdout[-4000:] + run.stderr[-2000:])
        self.assertRegex(self.preflight_line(run.stdout),
                         r"ok: Python for the hooks: python \(\S+/python\), Python 3\.\d+\.\d+ with PyYAML: the "
                         r"pre-commit, commit-msg and the approval scripts run it; python3 "
                         r"\(\S+/WindowsApps/python3, the Microsoft Store shortcut\) fails the 3\.10\+ probe$")
        self.assertIn("using discovered 'python' for §2/§3", run.stderr, "the pre-commit took the same one")
        self.assertEqual(m3.git(clone, "log", "-1", "--format=%s").stdout.strip(),
                         "flow: migrate Fusebase Flow 5.6 to 6.0.0-m4")

    def test_with_the_shortcut_alone_it_stops_and_names_the_way_out(self) -> None:
        clone = scratch_clone(self.tmp / "m")
        dry = migrate(clone, env={**os.environ, "PATH": self.path})
        self.assertNotEqual(dry.returncode, 0, dry.stdout)
        line = self.preflight_line(dry.stdout)
        self.assertIn("STOP: Python for the hooks: bash finds no Python 3.10+", line)
        self.assertIn("WindowsApps/python3, the Microsoft Store shortcut) fails the 3.10+ probe", line)
        self.assertIn("turn off the python.exe and python3.exe App execution aliases", dry.stdout)
        self.assertIn("-m pip install -r", dry.stdout)


class StoreNote(unittest.TestCase):
    def test_the_note_installs_pyyaml_with_the_hooks_interpreter_and_names_the_store_aliases(self) -> None:
        """T270: a bare pip can belong to another Python than the one the hooks run."""
        version = (CORE / "VERSION").read_text(encoding="utf-8").strip()
        note = (CORE / "maintainer/release-notes" / f"{version}.md").read_text(encoding="utf-8")
        req = f"fusebase-flow-{version}/hooks/requirements.txt"
        self.assertNotRegex(note, r"(?m)^pip install|`pip install", "no bare pip")
        self.assertIn(f"\n<the interpreter Flow will use> -m pip install -r {req}\n", note)
        self.assertIn(f"`python -m pip install -r {req}`", note)
        self.assertIn("python.exe and python3.exe App execution aliases", note)


class Checkpoint(Workspace):
    """O-20: the FuseBase CLI's two update checkpoint subjects pass on the committed policy alone; nothing wider."""

    def setUp(self) -> None:
        super().setUp()
        self.policy = (CORE / "policies/evidence-classes.yml").read_text(encoding="utf-8")
        m3.commit(self.repo, {"policies/evidence-classes.yml": self.policy, "docs/flow/backlog.md": MSG_BACKLOG,
                              "docs/flow/phases.md": PHASES, "src/a.ts": "export const a = 1;\n"}, "init")

    def verdict(self, subject: str) -> subprocess.CompletedProcess:
        write(self.repo, "src/a.ts", "export const a = 2;\n")  # the CLI's `git add -A`: a project file
        m3.git(self.repo, "add", "--", "src/a.ts")
        (self.tmp / "msg.txt").write_text(subject + "\n", encoding="utf-8")
        return m3.run(str(CORE / "hooks/local/lib/commit_msg.py"), str(self.tmp / "msg.txt"), cwd=self.repo)

    def test_the_two_cli_subjects_pass_and_a_near_miss_or_a_local_widening_does_not(self) -> None:
        for subject in CLI_SUBJECTS:
            out = self.verdict(subject)
            self.assertEqual(out.returncode, 0, f"{subject}: {out.stderr}")
        wide = "exempt_subjects: ['^chore\\(update\\): .*$']\n"
        write(self.repo, "policies/evidence-classes.local.yml", wide)
        write(self.repo, "policies/evidence-classes.yml", self.policy.replace("exempt_subjects:", wide + "unused:"))
        m3.git(self.repo, "add", "--", "policies/evidence-classes.yml")  # staged and in the working tree, not at HEAD
        for subject in ("chore(update): something else", "chore(update): pre app update", "chore: pre app update (x)",
                        "chore(update): pre app update (Oct 18, 2026) and more"):
            out = self.verdict(subject)
            self.assertEqual(out.returncode, 1, f"{subject} passed")
            self.assertIn("must cite a T-number", out.stderr, subject)


class FlowSubject(Workspace):
    """O-21: Flow's own install, migration and upgrade commits use `flow:`, which passes on Flow's own files only."""

    def install(self) -> None:
        with mock.patch.object(flow, "install_hooks", return_value=(0, "git hooks: not in this fixture")), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(flow.install(self.repo, {"claude", "codex"}), 0)

    def stage(self, *rels: str) -> list[str]:
        """Stages the named paths, or every change; returns the staged paths."""
        names = rels or m3.git(self.repo, "ls-files", "-m", "-o", "-d", "--exclude-standard", "-z").stdout.split("\0")
        m3.git(self.repo, "add", "--", *[n for n in names if n])
        return m3.git(self.repo, "diff", "--cached", "--name-only", "-z").stdout.split("\0")[:-1]

    def verdict(self, subject: str) -> subprocess.CompletedProcess:
        (self.tmp / "msg.txt").write_text(subject + "\n", encoding="utf-8")
        return m3.run(str(CORE / "hooks/local/lib/commit_msg.py"), str(self.tmp / "msg.txt"), cwd=self.repo)

    def edit(self, rel: str, old: str, new: str) -> None:
        text = (self.repo / rel).read_text(encoding="utf-8")
        self.assertIn(old, text, rel)
        write(self.repo, rel, text.replace(old, new, 1))

    def test_an_upgrade_with_a_plan_at_head_passes_and_a_project_file_does_not(self) -> None:
        m3.commit(self.repo, {"AGENTS.md": "# AGENTS.md\n\nThe CLI's text.\n", ".gitignore": "node_modules/\n",
                              "src/app.ts": "export const app = 1;\n"}, "the project")
        self.install()
        self.stage()
        first = self.verdict("flow: install Fusebase Flow 6.0.0-m4")
        self.assertEqual(first.returncode, 0, first.stderr)
        m3.commit(self.repo, {}, "flow: install Fusebase Flow 6.0.0-m4")
        m3.commit(self.repo, {"docs/flow/backlog.md": MSG_BACKLOG, "docs/flow/phases.md": PHASES}, "plan: phase 1")
        # An older install: one Flow file and its record gone, and a line gone from two Flow blocks.
        manifest = json.loads((self.repo / flow.MANIFEST).read_text(encoding="utf-8"))
        manifest["files"] = [e for e in manifest["files"] if e["path"] != "hooks/local/reader.py"]
        write(self.repo, flow.MANIFEST, json.dumps(manifest, indent=2) + "\n")
        (self.repo / "hooks/local/reader.py").unlink()
        self.edit(".gitignore", "state/returns/\n", "")
        self.edit("AGENTS.md", "## FuseBase Flow — workflow lifecycle overlay\n", "")
        self.stage()
        m3.commit(self.repo, {}, "T1: the project as an older install left it")
        self.install()
        self.assertEqual(sorted(self.stage()), [".gitignore", "AGENTS.md", flow.MANIFEST, "hooks/local/reader.py"])
        upgrade = self.verdict("flow: upgrade Fusebase Flow 6.0.0-m3 to 6.0.0-m4")
        self.assertEqual(upgrade.returncode, 0, upgrade.stderr)
        for rel, old, new in (("src/app.ts", "= 1", "= 2"), (".gitignore", "node_modules/\n", "node_modules/\ndist/\n"),
                              ("hooks/local/gate.py", "\n", "\n# an edit\n"), ("AGENTS.md", "The CLI's", "Our")):
            self.edit(rel, old, new)
            self.stage(rel)
            out = self.verdict("flow: upgrade Fusebase Flow 6.0.0-m3 to 6.0.0-m4")
            self.assertEqual(out.returncode, 1, f"{rel} passed")
            self.assertIn(f"a `flow:` commit stages Flow's own files", out.stderr, rel)
            self.assertIn(f"this one also stages {rel}.", out.stderr, rel)
            m3.git(self.repo, "reset", "-q", "--", rel)
            m3.git(self.repo, "checkout", "-q", "--", rel)

    def test_the_migration_commit_alone_takes_agents_and_claude_whole_and_nothing_else(self) -> None:
        """The owner's decision of 2026-10-19 (relayed): AGENTS.md and CLAUDE.md are accepted whole on the migration
        commit only; every other staged path there is Flow's own or one of the four documents."""
        sys.path.insert(0, str(CORE / "hooks/local/lib"))
        import flow_owned
        import migrate
        self.assertLessEqual({*migrate.AUDIT_5X, *migrate.ROOT_5X, *migrate.ORPHANS}, set(flow_owned.RETIRED_5X))
        mirror = "# the onboard command\n"
        assets = [{"path": "hooks/local/fusebase-flow-overlays/commands/onboard.md",
                   "sha256": hashlib.sha256(mirror.encode()).hexdigest()}]
        m3.commit(self.repo, {migrate.MC_MANIFEST: json.dumps({"assets": assets}), "GEMINI.md": "5.x\n",
                              "install.sh": "5.x\n", "audit/README.md": "5.x\n", ".claude/commands/onboard.md": mirror,
                              ".claude/commands/ours.md": "the project's\n", "AGENTS.md": "## FuseBase Flow 5.x\n",
                              "CLAUDE.md": "## FuseBase Flow 5.x\n", ".gitignore": "node_modules/\n",
                              "src/app.ts": "1\n"}, "a 5.x project")
        retired = [migrate.MC_MANIFEST, "GEMINI.md", "install.sh", "audit/README.md", ".claude/commands/onboard.md"]
        m3.git(self.repo, "rm", "-q", "--", *retired)
        for name in ("AGENTS.md", "CLAUDE.md"):
            write(self.repo, name, (CORE / flow.OVERLAY[name]).read_text(encoding="utf-8"))
        write(self.repo, ".gitignore", "node_modules/\n\n" + flow.ignore_block())
        self.stage("AGENTS.md", "CLAUDE.md", ".gitignore")
        migration = "flow: migrate Fusebase Flow 5.6 to 6.0.0-m4"
        passed = self.verdict(migration)
        self.assertEqual(passed.returncode, 0, passed.stderr)
        for rel, change in ((".claude/commands/ours.md", None), ("src/app.ts", "2\n"),
                            (".gitignore", "node_modules/\ndist/\n\n" + flow.ignore_block())):
            if change is None:
                m3.git(self.repo, "rm", "-q", "--", rel)
            else:
                write(self.repo, rel, change)
                self.stage(rel)
            self.assertIn(f"this one also stages {rel}.", self.verdict(migration).stderr, rel)
            m3.git(self.repo, "reset", "-q", "--", rel)
            m3.git(self.repo, "checkout", "-q", "--", rel)
        # Without the 5.x manifest's deletion this is no migration: the overlays and the retired names do not pass.
        write(self.repo, ".gitignore", "node_modules/\n\n" + flow.ignore_block())
        self.stage(".gitignore")
        m3.git(self.repo, "reset", "-q", "--", migrate.MC_MANIFEST)
        out = self.verdict(migration)
        self.assertIn("this one also stages AGENTS.md, CLAUDE.md, GEMINI.md, audit/README.md, install.sh.", out.stderr)

if __name__ == "__main__":
    unittest.main(verbosity=2)
