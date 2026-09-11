#!/usr/bin/env python3
"""T89 consumer-condition fixture. TRIPWIRE: this repository pins `text eol=lf`, so the defect
reproduces only in a separate repository with no .gitattributes and a core.autocrlf=true checkout."""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "hooks/local/lib/recovery-owned-write.py"
TOOLS = (HELPER, ROOT / "hooks/local/mirror-skills.sh", ROOT / "hooks/local/mirror-agents.sh")
REPO_LOCATORS = (
    "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_PREFIX", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
)


def load_path(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BOOT = load_path(ROOT / "hooks/tests/test-recovery-owned-bootstrap.py", "eol_fixture_helpers")
sha, put, bash_executable = BOOT.sha, BOOT.put, BOOT.bash_executable


def crlf(value: bytes) -> bytes:
    return value.replace(b"\n", b"\r\n")


def body(name: str, version: str) -> bytes:
    return f"---\nname: {name}\n---\n# {name}\n\n{name}-{version} rule.\n".encode()


AGENT_V1, AGENT_V2, AGENT_V3 = (f"# builder\nagent-{v}\n".encode() for v in ("v1", "v2", "v3"))
BINARY_V1 = b"binary\0v1\nline two\n"
NEGATIVES = ("edit", "mixed", "binary", "notext", "eollf", "filter", "filtereol", "filterunset",
             "filterunspec", "staged")
SENTINEL_FILTERS = {"filterunset": "unset", "filterunspec": "unspecified"}
LOCAL_LINE = b"LOCAL: preserve my instruction\r\n"


def skill_targets(name: str) -> list[str]:
    return [f"{provider}/skills/{name}/SKILL.md" for provider in (".agents", ".claude")]


AGENT_TARGETS = [".claude/agents/builder.md", ".codex/agents/builder.md"]


class EolEquivalenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.holder = tempfile.TemporaryDirectory()
        cls.base = Path(cls.holder.name).resolve()
        attributes = cls.base / "global-attributes"
        attributes.write_bytes(b"")
        config = cls.base / "gitconfig"
        config.write_text(
            "[user]\n\tname = EOL fixture\n\temail = eol@example.invalid\n"
            f"[core]\n\tattributesFile = {attributes.as_posix()}\n"
            "[init]\n\tdefaultBranch = main\n[safe]\n\tdirectory = *\n",
            encoding="utf-8",
        )
        env = {k: v for k, v in os.environ.items() if k not in REPO_LOCATORS}
        env.update({
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_ATTR_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": str(config), "HOME": str(cls.base),
        })
        cls.env = env
        cls.upstream = cls.base / "upstream-main"
        cls.build_upstream(cls.upstream, {name: body(name, "v1") for name in ("alpha", "steady", "legacy")})
        cls.negatives = cls.base / "upstream-negatives"
        skills = {name: body(name, "v1") for name in ("control", *NEGATIVES)}
        skills["binary"] = BINARY_V1
        cls.build_upstream(cls.negatives, skills)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.holder.cleanup()

    @classmethod
    def git(cls, root: Path, *args: str, check: bool = True, **kwargs) -> subprocess.CompletedProcess:
        result = subprocess.run(
            ["git", *args], cwd=root, env=cls.env, capture_output=True, timeout=60, **kwargs,
        )
        if check and result.returncode:
            raise AssertionError(f"git {' '.join(args)}: {result.stderr!r}")
        return result

    @classmethod
    def build_upstream(cls, root: Path, skills: dict[str, bytes]) -> None:
        files: dict[str, bytes] = {}
        skill_rows = []
        for name, value in skills.items():
            files[f"flow-skills/{name}/SKILL.md"] = value
            for rel in skill_targets(name):
                files[rel] = value
                stamped = crlf(value) if name == "legacy" else value
                skill_rows.append(f"{rel}  {sha(stamped)}")
        files["agents/builder/AGENT.md"] = AGENT_V1
        for rel in AGENT_TARGETS:
            files[rel] = AGENT_V1
        files["hooks/local/fusebase-flow-overlays/commands/flow.md"] = body("command", "v1")
        files[".claude/commands/flow.md"] = body("command", "v1")
        files["audit/skill-mirror-manifest.txt"] = ("\n".join(sorted(skill_rows)) + "\n").encode()
        files["audit/agent-mirror-manifest.txt"] = "".join(
            f"{rel}  {sha(AGENT_V1)}\n" for rel in sorted(AGENT_TARGETS)
        ).encode()
        for rel, value in files.items():
            put(root, rel, value)
        cls.git(root, "init", "-q")
        cls.git(root, "config", "core.autocrlf", "false")
        cls.git(root, "add", ".")
        cls.git(root, "commit", "-qm", "LF baseline")

    def clone(self, autocrlf: str = "true", upstream: Path | None = None) -> Path:
        root = Path(tempfile.mkdtemp(dir=self.base)) / "repo"
        source = str(upstream or self.upstream)
        self.git(self.base, "clone", "-q", "-c", f"core.autocrlf={autocrlf}", source, str(root))
        for tool in TOOLS:
            put(root, tool.relative_to(ROOT).as_posix(), tool.read_bytes())
        return root

    def blob(self, root: Path, spec: str) -> bytes:
        return self.git(root, "cat-file", "blob", spec).stdout

    def bash(self, root: Path, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [bash_executable(), *args], cwd=root, env=self.env, capture_output=True,
            text=True, timeout=180,
        )

    def module(self, name: str):
        return load_path(HELPER, f"eol_writer_{name}")

    def apply(self, root: Path, rows: list[tuple[str, str]], surface: str = "skill", module=None):
        module = module or self.module(surface)
        plan = root.parent / "plan.tsv"
        result = root.parent / "result.tsv"
        plan.write_text("".join(f"{root / src}\t{dst}\n" for src, dst in rows), encoding="utf-8")
        with mock.patch.dict(os.environ, self.env, clear=True):
            rc = module.apply(root, plan, result, surface)
        statuses = {}
        for line in result.read_text(encoding="utf-8").splitlines():
            status, rel, detail, _backup = line.split("\t")
            statuses[rel] = (status, detail)
        return rc, statuses

    def receipt(self, root: Path) -> dict:
        path = root / "state/audit/recovery-owned-targets.json"
        return json.loads(path.read_text(encoding="utf-8"))["targets"] if path.exists() else {}

    def assert_manifest_witnesses_blobs(self, root: Path, manifest: str) -> None:
        for line in self.blob(root, f"HEAD:{manifest}").decode().splitlines():
            rel, digest = line.split("  ")
            self.assertEqual(digest, sha(self.blob(root, f"HEAD:{rel}")), f"{manifest}: {rel}")

    def test_rule_collapses_crlf_pairs_only(self) -> None:
        module = self.module("rule")
        self.assertEqual(module.lf_form(b"4.15.\r\n3"), b"4.15.\n3")
        self.assertNotIn(sha(b"4.15.3"), module.eol_class_digests(b"4.15.\r\n3"))
        strip_all = lambda value: value.replace(b"\r", b"").replace(b"\n", b"")
        self.assertEqual(strip_all(b"4.15.\r\n3"), strip_all(b"4.15.3"), "the rejected rule merges them")
        pair = {sha(b"a\nb\n"), sha(b"a\r\nb\r\n")}
        self.assertEqual(module.eol_class_digests(b"a\nb\n"), pair)
        self.assertEqual(module.eol_class_digests(b"a\r\nb\r\n"), pair)
        for raw in (b"a\r\nb\n", b"a\rb\n", b"a\0\r\nb\r\n", b"a\r\r\nb\r\n", b"no-newline"):
            self.assertEqual(module.lf_form(raw), raw)
            self.assertEqual(module.eol_class_digests(raw), {sha(raw)})
        self.assertIsNone(module.crlf_form(b"a\r\nb\n"))
        self.assertNotIn(sha(b"a\nb\n"), module.eol_class_digests(b"a\nLOCAL: x\nb\n"))

    def test_positive_crlf_checkout_repairs_and_stays_consistent(self) -> None:
        root = self.clone()
        self.assertEqual(self.git(root, "config", "core.autocrlf").stdout.strip(), b"true")
        for rel in ("flow-skills/alpha/SKILL.md", *skill_targets("alpha"), "audit/skill-mirror-manifest.txt"):
            self.assertIn(b"\r\n", (root / rel).read_bytes(), f"checkout did not write CRLF: {rel}")
            self.assertNotIn(b"\r", self.blob(root, f"HEAD:{rel}"))
        fresh = self.bash(root, "hooks/local/mirror-skills.sh", "--check")
        self.assertEqual(fresh.returncode, 0, "fresh CRLF checkout reported drift:\n" + fresh.stderr)
        put(root, "flow-skills/alpha/SKILL.md", body("alpha", "v2"))
        put(root, "agents/builder/AGENT.md", AGENT_V2)
        before = {rel: (root / rel).read_bytes() for rel in (*skill_targets("alpha"), *AGENT_TARGETS)}
        steady_before = {rel: (root / rel).read_bytes() for rel in skill_targets("steady")}
        skills = self.bash(root, "hooks/local/mirror-skills.sh")
        agents = self.bash(root, "hooks/local/mirror-agents.sh")
        self.assertEqual(skills.returncode, 0, skills.stdout + skills.stderr)
        self.assertEqual(agents.returncode, 0, agents.stdout + agents.stderr)
        self.assertIn("copied 2;", skills.stdout)
        self.assertIn("copied 2;", agents.stdout)
        receipt = self.receipt(root)
        for rel, expected in [(r, body("alpha", "v2")) for r in skill_targets("alpha")] + \
                [(r, AGENT_V2) for r in AGENT_TARGETS]:
            self.assertEqual((root / rel).read_bytes(), expected, rel)
            self.assertEqual((root / f"{rel}.pre-flow-repair").read_bytes(), before[rel], rel)
            self.assertEqual(receipt[rel]["sha256"], sha(expected), rel)
        for rel, value in steady_before.items():
            self.assertEqual((root / rel).read_bytes(), value)
            self.assertFalse((root / f"{rel}.pre-flow-repair").exists())
        rows = dict(line.split("  ") for line in (root / "audit/skill-mirror-manifest.txt").read_text().splitlines())
        for name in ("alpha", "steady", "legacy"):
            expected = sha(body(name, "v2" if name == "alpha" else "v1"))
            for rel in skill_targets(name):
                self.assertEqual(rows[rel], expected, f"manifest row is not the LF content digest: {rel}")
        after = self.bash(root, "hooks/local/mirror-skills.sh", "--check")
        self.assertEqual(after.returncode, 0, after.stderr)
        tracked = ["flow-skills", "agents", "audit"] + [
            rel for name in ("alpha", "steady", "legacy") for rel in skill_targets(name)
        ] + AGENT_TARGETS
        self.git(root, "add", "--", *tracked)
        self.git(root, "commit", "-qm", "consumer commits the repaired mirrors")
        self.assert_manifest_witnesses_blobs(root, "audit/skill-mirror-manifest.txt")
        self.assert_manifest_witnesses_blobs(root, "audit/agent-mirror-manifest.txt")
        for rel in tracked[3:] + ["flow-skills/alpha/SKILL.md", "agents/builder/AGENT.md",
                                  "audit/skill-mirror-manifest.txt", "audit/agent-mirror-manifest.txt"]:
            (root / rel).unlink()
        self.git(root, "checkout", "--", *tracked)
        self.assertEqual((root / skill_targets("alpha")[0]).read_bytes(), crlf(body("alpha", "v2")))
        again = self.bash(root, "hooks/local/mirror-skills.sh", "--check")
        self.assertEqual(again.returncode, 0, "re-checkout reported drift:\n" + again.stderr)
        owned = json.loads((root / "state/audit/recovery-owned-targets.json").read_text())
        for rel in AGENT_TARGETS:
            del owned["targets"][rel]
        (root / "state/audit/recovery-owned-targets.json").write_text(json.dumps(owned))
        put(root, "flow-skills/alpha/SKILL.md", body("alpha", "v3"))
        put(root, "agents/builder/AGENT.md", AGENT_V3)
        skills = self.bash(root, "hooks/local/mirror-skills.sh")
        agents = self.bash(root, "hooks/local/mirror-agents.sh")
        self.assertEqual((skills.returncode, agents.returncode), (0, 0), skills.stderr + agents.stderr)
        for rel, expected in [(r, body("alpha", "v3")) for r in skill_targets("alpha")] + \
                [(r, AGENT_V3) for r in AGENT_TARGETS]:
            self.assertEqual((root / rel).read_bytes(), expected, rel)
            self.assertEqual((root / f"{rel}.pre-flow-repair.1").read_bytes(),
                             crlf(body("alpha", "v2")) if "skills" in rel else crlf(AGENT_V2), rel)
        final = self.bash(root, "hooks/local/mirror-skills.sh", "--check")
        self.assertEqual(final.returncode, 0, final.stderr)

    def test_positive_crlf_stamped_manifest_row(self) -> None:
        root = self.clone()
        rows = dict(line.split("  ") for line in self.blob(root, "HEAD:audit/skill-mirror-manifest.txt").decode().splitlines())
        self.assertEqual(rows[skill_targets("legacy")[0]], sha(crlf(body("legacy", "v1"))))
        put(root, "flow-skills/legacy/SKILL.md", body("legacy", "v2"))
        result = self.bash(root, "hooks/local/mirror-skills.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rows = dict(line.split("  ") for line in (root / "audit/skill-mirror-manifest.txt").read_text().splitlines())
        for rel in skill_targets("legacy"):
            self.assertEqual((root / rel).read_bytes(), body("legacy", "v2"))
            self.assertEqual(rows[rel], sha(body("legacy", "v2")))

    def test_positive_attribute_crlf_without_autocrlf(self) -> None:
        root = self.clone(autocrlf="false")
        target = skill_targets("alpha")[0]
        put(root, ".git/info/attributes", f"/{target} text eol=crlf\n".encode())
        (root / target).unlink()
        self.git(root, "checkout", "--", target)
        self.assertEqual((root / target).read_bytes(), crlf(body("alpha", "v1")))
        put(root, "flow-skills/alpha/SKILL.md", body("alpha", "v2"))
        rc, statuses = self.apply(root, [("flow-skills/alpha/SKILL.md", target)])
        self.assertEqual((rc, statuses[target][0]), (0, "owned-repair"), statuses)
        self.assertEqual((root / target).read_bytes(), body("alpha", "v2"))

    def test_positive_receipt_only_surface(self) -> None:
        root = self.clone()
        target = ".claude/commands/flow.md"
        self.assertEqual((root / target).read_bytes(), crlf(body("command", "v1")))
        put(root, "state/audit/recovery-owned-targets.json", json.dumps({
            "schema": 1, "targets": {target: {"sha256": sha(body("command", "v1")), "surface": "command"}},
        }).encode())
        source = "hooks/local/fusebase-flow-overlays/commands/flow.md"
        put(root, source, body("command", "v2"))
        rc, statuses = self.apply(root, [(source, target)], "command")
        self.assertEqual((rc, statuses[target][0]), (0, "owned-repair"), statuses)
        self.assertEqual((root / target).read_bytes(), body("command", "v2"))

    def test_negatives_are_preserved(self) -> None:
        root = self.clone(upstream=self.negatives)
        agents = {name: f".agents/skills/{name}/SKILL.md" for name in ("control", *NEGATIVES)}
        put(root, ".git/info/attributes", (
            f"/{agents['notext']} -text\n/{agents['eollf']} text eol=lf\n/{agents['filter']} filter=local\n"
            f"/{agents['filtereol']} filter=local\n"
            + "".join(f"/{agents[n]} text eol=crlf filter={d}\n" for n, d in SENTINEL_FILTERS.items())
        ).encode())
        markers = {name: root.parent / f"smudge-{driver}.ran" for name, driver in SENTINEL_FILTERS.items()}
        for name, driver in SENTINEL_FILTERS.items():
            self.git(root, "config", f"filter.{driver}.smudge", f'touch "{markers[name].as_posix()}" && cat')
            self.assertEqual((root / agents[name]).read_bytes(), crlf(body(name, "v1")))
            named = self.git(root, "check-attr", "filter", "--", agents[name]).stdout.decode()
            self.assertTrue(named.rstrip().endswith(f": filter: {driver}"), f"precondition: sentinel-valued {named!r}")
        self.assertEqual((root / agents["filtereol"]).read_bytes(), crlf(body("filtereol", "v1")))
        self.git(root, "config", "filter.local.clean", "sed '/^LOCAL:/d'")
        v1 = {name: body(name, "v1") for name in agents}
        v1["binary"] = BINARY_V1
        put(root, agents["edit"], crlf(v1["edit"] + b"LOCAL: my added instruction\n"))
        put(root, agents["mixed"], v1["mixed"].replace(b"\n", b"\r\n", 2))
        self.assertEqual((root / agents["binary"]).read_bytes(), BINARY_V1, "binary must not convert")
        put(root, agents["binary"], crlf(BINARY_V1))
        put(root, agents["filter"], crlf(v1["filter"]) + LOCAL_LINE)
        put(root, agents["staged"], crlf(v1["staged"] + b"STAGED: my edit\n"))
        self.git(root, "add", "--", agents["staged"])
        for name in ("notext", "eollf", "binary"):
            self.assertEqual(self.git(root, "cat-file", "--filters", f"HEAD:{agents[name]}").stdout,
                             v1[name], f"{name}: git's checkout must not write CRLF here")
        filtered = self.git(root, "hash-object", "--", agents["filter"]).stdout.strip()
        self.assertEqual(filtered, self.git(root, "rev-parse", f"HEAD:{agents['filter']}").stdout.strip(),
                         "precondition: unrestricted hash-object equality would authorize replacement")
        self.assertEqual(self.git(root, "diff", "--quiet", "--", agents["staged"], check=False).returncode, 0)
        self.assertEqual(self.git(root, "diff", "--cached", "--quiet", "--", agents["staged"], check=False).returncode, 1)
        for name in agents:
            put(root, f"flow-skills/{name}/SKILL.md", body(name, "v2"))
        put(root, "hooks/local/fusebase-flow-overlays/commands/flow.md", body("command", "v2"))
        put(root, "state/audit/recovery-owned-targets.json", json.dumps({"schema": 1, "targets": {
            ".claude/commands/flow.md": {"sha256": sha(b"other bytes\n"), "surface": "command"},
        }}).encode())
        before = {rel: (root / rel).read_bytes() for rel in agents.values()}
        rc, statuses = self.apply(root, [(f"flow-skills/{name}/SKILL.md", rel) for name, rel in agents.items()])
        crc, cstatuses = self.apply(
            root, [("hooks/local/fusebase-flow-overlays/commands/flow.md", ".claude/commands/flow.md")], "command",
        )
        self.assertEqual((rc, crc), (1, 1), (statuses, cstatuses))
        receipt = self.receipt(root)
        for name in NEGATIVES:
            rel = agents[name]
            with self.subTest(case=name):
                self.assertEqual(statuses[rel][0], "unowned-collision", statuses[rel])
                self.assertEqual((root / rel).read_bytes(), before[rel])
                self.assertFalse((root / f"{rel}.pre-flow-repair").exists())
                self.assertNotIn(rel, receipt)
                print(f"PRESERVED {name}: {statuses[rel][1]}")
        for name, marker in markers.items():
            with self.subTest(case=f"{name}-smudge-never-ran"):
                self.assertFalse(marker.exists(), f"{name}: the ownership proof executed a consumer smudge filter")
                self.assertIn("attribute makes checkout unverifiable", statuses[agents[name]][1])
        for name, marker in markers.items():
            with self.subTest(case=f"{name}-smudge-is-live"):
                self.git(root, "cat-file", "--filters", f"HEAD:{agents[name]}")
                self.assertTrue(marker.exists(), f"{name}: the smudge never runs, so an absent marker proves nothing")
        with self.subTest(case="filtereol-reason"):
            self.assertIn("attribute makes checkout unverifiable", statuses[agents["filtereol"]][1])
        with self.subTest(case="receipt-mismatch"):
            self.assertEqual(cstatuses[".claude/commands/flow.md"][0], "unowned-collision")
            self.assertEqual((root / ".claude/commands/flow.md").read_bytes(), crlf(body("command", "v1")))
            print(f"PRESERVED receipt-mismatch: {cstatuses['.claude/commands/flow.md'][1]}")
        with self.subTest(case="control-repaired"):
            self.assertEqual(statuses[agents["control"]][0], "owned-repair", statuses)
            self.assertEqual((root / agents["control"]).read_bytes(), body("control", "v2"))

    def test_negative_concurrent_target_change(self) -> None:
        for case in ("content", "eol-only"):
            root = self.clone()
            target = skill_targets("alpha")[0]
            put(root, "flow-skills/alpha/SKILL.md", body("alpha", "v2"))
            changed = crlf(body("alpha", "v1")) + b"RACE\r\n" if case == "content" else body("alpha", "v1")
            module = self.module(f"race_{case}")
            original = module.prepare_rows
            seen = {}

            def race(*args):
                baseline, prepared = original(*args)
                seen.update({item.row.target_rel: item.status for item in prepared})
                (root / target).write_bytes(changed)
                return baseline, prepared

            with mock.patch.object(module, "prepare_rows", race):
                rc, statuses = self.apply(root, [("flow-skills/alpha/SKILL.md", target)], module=module)
            with self.subTest(case=case, check="preserved"):
                self.assertEqual(rc, 1, statuses)
                self.assertIn(statuses[target][0], {"unsafe", "unowned-collision"}, statuses)
                self.assertEqual((root / target).read_bytes(), changed)
                self.assertFalse((root / f"{target}.pre-flow-repair").exists())
                self.assertEqual(self.receipt(root), {})
                print(f"PRESERVED race-{case}: {statuses[target][0]}: {statuses[target][1]}")
            with self.subTest(case=case, check="ownership-was-granted-before-the-change"):
                self.assertEqual(seen.get(target), "owned-repair")
                self.assertEqual(statuses[target], ("unsafe", "target changed after ownership classification"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
