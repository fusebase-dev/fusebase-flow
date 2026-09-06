#!/usr/bin/env python3
"""Parity and mutation controls for the batched artifact manifest."""

from __future__ import annotations

import hashlib
import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "hooks/tests/lib/artifact-manifest.py"
HARNESS = ROOT / "hooks/tests/test-pre-commit-python3-version-mutation.sh"
SPEC = importlib.util.spec_from_file_location("artifact_manifest", HELPER)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def reference_manifest(root: Path, excluded: set[str]) -> list[str]:
    records: list[str] = []
    for directory, names, files in os.walk(root, topdown=True, followlinks=False):
        rel_directory = Path(directory).relative_to(root)
        if rel_directory == Path("."):
            names[:] = [name for name in names if name != ".git"]
        for name in files:
            path = Path(directory, name)
            if path.is_symlink() or not path.is_file():
                continue
            rel = "./" + path.relative_to(root).as_posix()
            if rel in excluded:
                continue
            data = path.read_bytes()
            records.append(f"{rel}|file|{len(data)}|{hashlib.sha256(data).hexdigest()}")
    return sorted(records, key=lambda row: os.fsencode(row.split("|", 1)[0]))


def old_shell_manifest(root: Path) -> list[str]:
    script = r'''cd "$1" && find . -path ./.git -prune -o -type f -print 2>/dev/null \
| grep -v '^\./hooks/git/pre-commit$' | LC_ALL=C sort \
| while IFS= read -r f; do
    printf '%s|file|%s|%s\n' "$f" "$(wc -c < "$f" 2>/dev/null | tr -d ' ')" \
      "$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)"
  done'''
    bash = shutil.which("bash") or "bash"
    git = shutil.which("git")
    if os.name == "nt" and git:
        git_bash = Path(git).resolve().parent.parent / "bin/bash.exe"
        if git_bash.is_file():
            bash = os.fspath(git_bash)
    result = subprocess.run(
        [bash, "-c", script, "artifact-manifest-reference", root.as_posix()],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    return result.stdout.splitlines()


class ArtifactManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="artifact-manifest-test-")
        self.root = Path(self.temp.name)
        (self.root / "nested").mkdir()
        fixtures = {
            "empty": b"",
            "binary.bin": bytes(range(256)),
            "crlf.txt": b"a\r\nb\r\n",
            "space name.txt": b"space",
            "unicode-\N{SNOWMAN}.txt": b"snow\n",
            "nested/value.txt": b"nested",
            "hooks/git/pre-commit": b"mutation input",
            ".git/ignored": b"git metadata",
        }
        for name, data in fixtures.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        try:
            (self.root / "regular-link").symlink_to(self.root / "empty")
        except OSError:
            pass

    def tearDown(self) -> None:
        self.temp.cleanup()

    def manifest(self) -> list[str]:
        return MODULE.build_manifest(self.root, {"./hooks/git/pre-commit"})

    def test_reference_parity_and_exclusions(self) -> None:
        expected = reference_manifest(self.root, {"./hooks/git/pre-commit"})
        self.assertEqual(expected, old_shell_manifest(self.root))
        self.assertEqual(expected, self.manifest())
        rendered = "\n".join(expected)
        self.assertNotIn(".git", rendered)
        self.assertNotIn("pre-commit", rendered)
        self.assertNotIn("regular-link", rendered)

    def test_same_size_mutation_changes_hash(self) -> None:
        before = self.manifest()
        (self.root / "crlf.txt").write_bytes(b"c\r\nd\r\n")
        after = self.manifest()
        self.assertNotEqual(before, after)
        self.assertEqual([row.split("|")[:3] for row in before], [row.split("|")[:3] for row in after])

    def test_added_and_deleted_artifacts_are_visible(self) -> None:
        before = self.manifest()
        (self.root / "added").write_bytes(b"new")
        added = self.manifest()
        self.assertEqual(len(before) + 1, len(added))
        (self.root / "empty").unlink()
        deleted = self.manifest()
        self.assertEqual(len(before), len(deleted))
        self.assertNotEqual(before, deleted)

    def test_change_after_enumeration_fails_closed(self) -> None:
        rel, path, expected = next(
            item for item in MODULE._regular_files(self.root, set()) if item[0] == "./empty"
        )
        path.write_bytes(b"changed")
        with self.assertRaisesRegex(RuntimeError, "changed after enumeration"):
            MODULE._file_record(rel, path, expected)

    def test_cli_matches_library_and_uses_no_process_api(self) -> None:
        result = subprocess.run(
            [os.fspath(Path(os.sys.executable)), os.fspath(HELPER), "--root", os.fspath(self.root),
             "--exclude", "./hooks/git/pre-commit"],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(self.manifest(), result.stdout.splitlines())
        source = HELPER.read_text(encoding="utf-8")
        self.assertNotIn("subprocess", source)
        self.assertNotIn("os.system", source)
        harness = HARNESS.read_text(encoding="utf-8")
        self.assertEqual(1, harness.count('"$REALPY" "$MANIFEST_HELPER"'))
        self.assertNotIn("while IFS= read -r f", harness)


if __name__ == "__main__":
    unittest.main(verbosity=2)
