#!/usr/bin/env python3
"""Split @fusebase/* install advisory (docs/changes/2026-09-30-ovation-escalation-f1-f4.md F1).

Usage: fusebase_package_split.py <repo-root>
TRIPWIRE: every stdout line becomes one health advisory (lib/cli-version-check.sh); print nothing else.
"""
from __future__ import annotations

import json
import os
import re
import sys

DEP_KEYS = ("dependencies", "devDependencies", "optionalDependencies")
PACKAGE = re.compile(r"@fusebase/[a-z0-9][a-z0-9._~-]*")


def _read_json(path: str):
    try:
        with open(path, encoding="utf-8-sig") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _installed_version(root: str, start: str, name: str):
    here = start
    while True:
        meta_path = os.path.join(here, "node_modules", *name.split("/"), "package.json")
        if os.path.isfile(meta_path):
            version = (_read_json(meta_path) or {}).get("version")
            return version if isinstance(version, str) and version else None
        parent = os.path.dirname(here)
        if here == root or parent == here:
            return None
        here = parent


def _version_key(version: str):
    return [int(part) for part in re.findall(r"\d+", version)[:3]], version


def split_lines(root: str) -> list[str]:
    root = os.path.abspath(root)
    if not os.path.isfile(os.path.join(root, "fusebase.json")):
        return []
    found: dict[str, dict[str, list[str]]] = {}
    for here, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d != "node_modules" and not d.startswith(".")]
        manifest = _read_json(os.path.join(here, "package.json")) if "package.json" in files else None
        if manifest is None:
            continue
        names = set()
        for key in DEP_KEYS:
            deps = manifest.get(key)
            if isinstance(deps, dict):
                names.update(n for n in deps if isinstance(n, str) and PACKAGE.fullmatch(n))
        rel = os.path.relpath(here, root).replace(os.sep, "/")
        for name in names:
            version = _installed_version(root, here, name)
            if version:
                found.setdefault(name, {}).setdefault(version, []).append(rel)
    lines = []
    for name in sorted(found):
        versions = found[name]
        if len(versions) < 2:
            continue
        groups = " · ".join(
            "%s: %s" % (v, ", ".join(sorted(versions[v], key=lambda r: (r != ".", r))))
            for v in sorted(versions, key=_version_key, reverse=True))
        lines.append(
            "%s resolves to %d versions — %s. Separate copies break instanceof checks (e.g. ApiError) "
            "across them. Owner: FuseBase CLI version management. Fix: align these package.json "
            "entries, then npm install in each root." % (name, len(versions), groups))
    return lines


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        sys.stderr.write("usage: fusebase_package_split.py <repo-root>\n")
        return 2
    # TRIPWIRE: bytes, not print() — `-I` ignores PYTHONIOENCODING and the lines carry non-ASCII.
    sys.stdout.buffer.write("".join(line + "\n" for line in split_lines(argv[1])).encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
