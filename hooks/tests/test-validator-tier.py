#!/usr/bin/env python3
"""FR-13 validator-free tier unit (workflows/git-discipline.md § Validator-free paths).

Windows python is enough (PyYAML + git on PATH; no bash). Run by test-validator-evidence.sh row tier-unit.
"""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TIER_PY = ROOT / "hooks/local/lib/validator_tier.py"
SPEC = importlib.util.spec_from_file_location("validator_tier", TIER_PY)
assert SPEC and SPEC.loader
VT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VT)
GLOB = VT.load_glob(ROOT)
DECL = VT.DECLARATION


def yml(*patterns: str, extra: str = "") -> bytes:
    body = "schema_version: 1\nvalidator_free_paths:\n" + "".join('  - "%s"\n' % p for p in patterns)
    return (body + extra).encode("utf-8")


def pats(*patterns: str):
    got, why = VT.parse_declaration(yml(*patterns), GLOB)
    assert got, why
    return got


class MatcherSemantics(unittest.TestCase):
    def m(self, pat, path):
        return bool(GLOB(pat).fullmatch(path))

    def test_segment_aware(self):
        self.assertTrue(self.m("docs/**", "docs/a/b.md"))
        self.assertFalse(self.m("docs/**", "docsite/app.ts"))
        self.assertFalse(self.m("docs/**", "docs-internal/x.ts"))
        self.assertFalse(self.m("*.md", "a/b.md"))
        self.assertTrue(self.m("**/*.md", "README.md"))
        self.assertTrue(self.m("**/*.md", "a/b.md"))
        self.assertFalse(self.m("docs/*", "docs/sub/evil.ts"))

    def test_case_sensitive(self):
        self.assertFalse(self.m("docs/**", "Docs/x.md"))

    def test_full_string_only(self):
        self.assertTrue(self.m("release-notes.md", "release-notes.md"))
        self.assertFalse(self.m("release-notes.md", "release-notes.md\n"))


class Declaration(unittest.TestCase):
    def bad(self, blob: bytes, needle: str):
        got, why = VT.parse_declaration(blob, GLOB)
        self.assertIsNone(got, why)
        self.assertIn(needle, why)

    def test_valid_and_bom(self):
        self.assertEqual([p for p, _ in pats("docs/**", "**/*.png")], ["docs/**", "**/*.png"])
        got, _ = VT.parse_declaration(b"\xef\xbb\xbf" + yml("docs/**"), GLOB)
        self.assertTrue(got)

    def test_empty_runs(self):
        for blob in (b"schema_version: 1\nvalidator_free_paths: []\n",
                     b"schema_version: 1\nvalidator_free_paths:\n"):
            got, why = VT.parse_declaration(blob, GLOB)
            self.assertEqual(got, [])
            self.assertIn("declares no paths", why)

    def test_malformed(self):
        self.bad(b"schema_version: 1\nvalidator_free_paths: [\n", "not valid YAML")
        self.bad(b"- docs/**\n", "exactly the keys")
        self.bad(yml("docs/**", extra="extra_key: 1\n"), "exactly the keys")
        self.bad(b"schema_version: 2\nvalidator_free_paths: ['docs/**']\n", "schema_version")
        self.bad(b"schema_version: true\nvalidator_free_paths: ['docs/**']\n", "schema_version")
        self.bad(b"schema_version: 1\nvalidator_free_paths: docs/**\n", "must be a list")
        self.bad(b"schema_version: 1\nvalidator_free_paths: [1]\n", "not a string")
        self.bad(b"\xff\xfe", "not UTF-8")
        self.bad(b"#" * (VT.MAX_BLOB + 1), "larger than")

    def test_pattern_syntax(self):
        for p, needle in (("/docs/**", "repo-relative"), ("!docs/**", "repo-relative"),
                          ("docs\\\\x.md", "not supported"), ("[ab].md", "not supported"),
                          ("{a,b}.md", "not supported"), ("docs/", "dir/**"),
                          ("../x.md", "segment"), ("docs//x.md", "segment"),
                          ("docs**", "whole path segment"), ("docs/**x", "whole path segment"),
                          (" docs/**", "whitespace"), ("docs/\\u007f.md", "control character")):
            with self.subTest(p=p):
                self.bad(yml(p), needle)

    def test_breadth_guard(self):
        for p in ("**", "*", "**/*", "**/**", "*.json", "**/*.json", "**/*.yaml", "*.js", "**/.*"):
            with self.subTest(p=p):
                self.bad(yml(p), "covers validator config")
        self.assertTrue(pats("**/*.md", "docs/**", "assets/**/*.png", "**/*.txt"))


class Decide(unittest.TestCase):
    P = None

    @classmethod
    def setUpClass(cls):
        cls.P = pats("docs/**", "**/*.md", "assets/**")

    def d(self, *staged):
        return VT.decide(list(staged), self.P, GLOB)

    def test_all_declared_skips(self):
        v = self.d("docs/a.md", "README.md", "assets/logo.png")
        self.assertTrue(v.skip, v.reason)
        self.assertIn("all 3 staged", v.reason)

    def test_one_undeclared_runs(self):
        v = self.d("docs/a.md", "src/app.ts", "src/b.ts")
        self.assertFalse(v.skip)
        self.assertIn("src/app.ts is not declared validator-free (+1 more)", v.reason)

    def test_rename_both_sides(self):
        self.assertFalse(self.d("docs/a.md", "src/a.ts").skip)

    def test_never_qualify(self):
        for path in (DECL, "package.json", "apps/web/package.json", "apps/web/tsconfig.app.json",
                     ".eslintrc.cjs", "eslint.config.mjs", "docs/.markdownlint.json", ".gitignore",
                     "docs/.gitignore", "pnpm-lock.yaml", "pyproject.toml",
                     "hooks/local/lib/validator_tier.py", "hooks/shared/module_size.py",
                     "hooks/local/lib/precommit-validator-reuse.sh", "hooks/git/pre-commit"):
            with self.subTest(path=path):
                v = VT.decide(["docs/a.md", path], pats("docs/**", "**/*.md", "hooks/**", "apps/**/*.md"), GLOB)
                self.assertFalse(v.skip, path)

    def test_nothing_staged_runs(self):
        self.assertFalse(self.d().skip)

    def test_control_character_path_runs(self):
        declared = pats("release-notes.md")
        self.assertTrue(VT.decide(["release-notes.md"], declared, GLOB).skip)
        for path in ("release-notes.md\n", "release-notes.md\r", "release\tnotes.md",
                     "release-notes.md\x7f", "release-notes.md\x85"):
            with self.subTest(path=path):
                v = VT.decide([path], declared, GLOB)
                self.assertFalse(v.skip, v.reason)
                self.assertIn("control character", v.reason)


class Reserved(unittest.TestCase):
    def test_flow_ships_no_declaration(self):
        if not (ROOT / "docs/release-fingerprints.md").is_file():
            self.skipTest("publisher-only: a consumer may create the declaration")
        doc = json.loads((ROOT / "audit/managed-content-manifest.json").read_text(encoding="utf-8"))
        self.assertNotIn(DECL, {a["path"] for a in doc["assets"]})
        self.assertFalse((ROOT / DECL).exists())

    def test_upgrade_classifier_ignores_reserved_name(self):
        spec = importlib.util.spec_from_file_location(
            "ff_mcm", ROOT / "hooks/local/lib/managed_content_manifest.py")
        mcm = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mcm)
        self.assertTrue(mcm._excluded(DECL))
        self.assertFalse(mcm._excluded("policies/protected-paths.yml"))


class GitBacked(unittest.TestCase):
    def setUp(self):
        if not shutil.which("git"):
            self.skipTest("git not on PATH")
        self.dir = Path(tempfile.mkdtemp(prefix="ff-tier-"))
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.git("init", "-q")
        self.git("config", "user.email", "t@example.test")
        self.git("config", "user.name", "t")
        self.git("config", "core.autocrlf", "false")
        (self.dir / "hooks/shared").mkdir(parents=True)
        shutil.copy(ROOT / "hooks/shared/module_size.py", self.dir / "hooks/shared/module_size.py")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def git(self, *args, env=None):
        return subprocess.run(["git", *args], cwd=self.dir, env=env or self.env,
                              capture_output=True, check=True).stdout

    def blob(self, data: bytes) -> str:
        return subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=self.dir, env=self.env,
                              input=data, capture_output=True, check=True).stdout.decode().strip()

    def write(self, rel, text):
        p = self.dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(text.encode("utf-8") if isinstance(text, str) else text)

    def base(self, declaration=b'schema_version: 1\nvalidator_free_paths:\n  - "docs/**"\n'):
        self.write("src/a.ts", "export const a = 1;\n")
        self.write("docs/old.md", "old\n")
        if declaration is not None:
            self.write(DECL, declaration)
        self.git("add", "-A")
        self.git("commit", "-qm", "base")

    def ev(self):
        saved = dict(os.environ)
        try:
            os.environ.clear()
            os.environ.update(self.env)
            return VT.evaluate(self.dir)
        finally:
            os.environ.clear()
            os.environ.update(saved)

    def test_docs_only_skips_and_rc_contract(self):
        self.base()
        self.write("docs/new.md", "x\n")
        self.git("add", "docs/new.md")
        self.git("rm", "-q", "docs/old.md")
        self.assertTrue(self.ev().skip)
        env = dict(self.env, PYTHONNOUSERSITE="1", PYTHONSAFEPATH="1")
        env.pop("PYTHONPATH", None)
        r = subprocess.run([sys.executable, "-S", str(TIER_PY), "--root", str(self.dir)],
                           env=env, capture_output=True, text=True)
        self.assertEqual(r.returncode, VT.SKIP_RC, r.stderr)
        self.assertIn("tier=validator-free", r.stderr)
        self.write("src/b.ts", "export const b = 2;\n")
        self.git("add", "src/b.ts")
        r = subprocess.run([sys.executable, "-S", str(TIER_PY), "--root", str(self.dir)],
                           env=env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("tier=full", r.stderr)

    def test_widening_in_worktree_or_index_never_counts(self):
        self.base()
        self.write(DECL, 'schema_version: 1\nvalidator_free_paths:\n  - "docs/**"\n  - "src/**"\n')
        self.write("src/a.ts", "export const a = 2;\n")
        self.git("add", "src/a.ts")
        v = self.ev()
        self.assertFalse(v.skip)
        self.assertIn("src/a.ts is not declared", v.reason)
        self.git("add", DECL)
        v = self.ev()
        self.assertFalse(v.skip)
        self.assertIn(DECL, v.reason)

    def test_rename_lists_both_sides(self):
        self.base()
        self.git("mv", "src/a.ts", "docs/a.md")
        v = self.ev()
        self.assertFalse(v.skip)
        self.assertIn("src/a.ts", v.reason)

    def test_unborn_head_and_absent_declaration(self):
        self.write("docs/a.md", "x\n")
        self.git("add", "docs/a.md")
        self.assertIn("unborn", self.ev().reason)
        self.git("commit", "-qm", "first")
        self.write("docs/b.md", "y\n")
        self.git("add", "docs/b.md")
        v = self.ev()
        self.assertFalse(v.skip)
        self.assertIn("absent at HEAD", v.reason)

    def test_symlink_declaration_is_not_regular(self):
        self.base(declaration=None)
        oid = self.blob(b"elsewhere.yml")
        self.git("update-index", "--add", "--cacheinfo", "120000,%s,%s" % (oid, DECL))
        self.git("commit", "-qm", "symlink decl")
        self.write("docs/b.md", "y\n")
        self.git("add", "docs/b.md")
        self.assertIn("not a regular file", self.ev().reason)

    def test_alternate_index_is_honoured(self):
        self.base()
        self.write("docs/b.md", "y\n")
        self.git("add", "docs/b.md")
        self.assertTrue(self.ev().skip)
        alt = str(self.dir / ".git" / "alt-index")
        alt_env = dict(self.env, GIT_INDEX_FILE=alt)
        self.git("read-tree", "HEAD", env=alt_env)
        self.write("src/c.ts", "export const c = 3;\n")
        self.git("add", "src/c.ts", env=alt_env)
        saved_env, self.env = self.env, alt_env
        try:
            self.assertFalse(self.ev().skip)
        finally:
            self.env = saved_env

    @unittest.skipIf(os.name == "nt", "Git for Windows rejects control characters in paths")
    def test_newline_suffixed_path_runs(self):
        self.base(declaration=b'schema_version: 1\nvalidator_free_paths:\n  - "release-notes.md"\n')
        self.write("release-notes.md", "notes\n")
        self.git("add", "release-notes.md")
        self.assertTrue(self.ev().skip)
        oid = self.blob(b"x\n")
        self.git("update-index", "--add", "--cacheinfo", "100644,%s,release-notes.md\n" % oid)
        v = self.ev()
        self.assertFalse(v.skip)
        self.assertIn("control character", v.reason)


if __name__ == "__main__":
    unittest.main(verbosity=1)
