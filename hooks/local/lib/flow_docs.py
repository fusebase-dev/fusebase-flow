"""Shared reader for the milestone 3 scripts in hooks/local/: git, a policy as committed at HEAD, the fields of the four
documents the scripts use, and the kernel's glob dialect. Stdlib plus PyYAML (hooks/requirements.txt)."""
from __future__ import annotations

import importlib.util
import json
import re
import subprocess
from pathlib import Path

import yaml

PHASES, BACKLOG, LEDGER = "docs/flow/phases.md", "docs/flow/backlog.md", "docs/flow/ledger.md"
TASK = re.compile(r"\bT\d+\b")
SHA = re.compile(r"[0-9a-f]{7,40}")


def git(root: Path, *args: str) -> str:
    """git's stdout, or "" when git fails."""
    try:
        r = subprocess.run(["git", "-c", "core.quotepath=false", *args], cwd=root, capture_output=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else ""


def read(path: Path) -> str:
    """The text without HTML comments (the templates' examples live in them); "" when the file is absent."""
    try:
        return re.sub(r"<!--.*?-->", "", path.read_text(encoding="utf-8", errors="replace"), flags=re.S)
    except OSError:
        return ""


def policy(root: Path, name: str = "evidence-classes") -> dict:
    """policies/<name>.yml as committed at HEAD (no local twin); the working tree only while HEAD lacks the file."""
    rel = f"policies/{name}.yml"
    text = git(root, "show", f"HEAD:{rel}") or ((root / rel).read_text(encoding="utf-8") if (root / rel).is_file() else "")
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError:
        doc = None
    return doc if isinstance(doc, dict) else {}


def globber():
    """match(path, globs): the dialect of hooks/shared/module_size.py, full-matched (over-matching would fail open)."""
    spec = importlib.util.spec_from_file_location("_flow_glob", Path(__file__).resolve().parents[2] / "shared/module_size.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    cache: dict[str, re.Pattern] = {}

    def match(path: str, globs) -> bool:
        return any((cache.get(g) or cache.setdefault(g, mod._glob_to_regex(g))).fullmatch(path) for g in globs)
    return match


def tier(pol: dict, key: str | None = None) -> list[str]:
    """The trivial-tier globs of the policy: one list, or all three."""
    lists = pol.get("trivial") or {}
    return [g for k, v in lists.items() if key in (None, k) for g in (v or [])]


def phases(root: Path) -> dict[str, dict]:
    """{slice id: {phase, base, title, tasks: [{id, item, does, globs, minutes, files}]}} from phases.md."""
    slices: dict[str, dict] = {}
    phase = base = current = None
    for line in read(root / PHASES).splitlines():
        if m := re.match(r"##\s+(P\d+)\b", line):
            phase, base, current = m[1], None, None
        elif (m := re.match(r"-\s*base:\s*(\S+)", line)) and current is None:
            base = m[1]
        elif m := re.match(r"###\s+(P\d+-S\d+)\s*(.*)", line):
            current = slices.setdefault(m[1], {"phase": phase, "base": base, "title": m[2].strip(), "tasks": []})
        elif current is not None and (m := re.match(r"\|\s*(T\d+)\s*\|(.*)\|\s*$", line)):
            cells = [c.strip() for c in m[2].split("|")] + ["", "", "", ""]
            est = re.search(r"(\d+)m\s+(\d+)f", cells[3])
            current["tasks"].append({"id": m[1], "item": cells[0], "does": cells[1],
                                     "globs": re.findall(r"`([^`]+)`", cells[2]),
                                     "minutes": int(est[1]) if est else None, "files": int(est[2]) if est else None})
    return slices


def commits(root: Path, base: str, head: str = "HEAD") -> list[tuple[str, str, list[str]]]:
    """(sha, subject, paths) of each non-merge commit in base..head, oldest first."""
    out = git(root, "log", "--reverse", "--no-merges", "--no-renames", "--format=%x00%H%x1f%s", "--name-only",
              f"{base}..{head}", "--")
    found = []
    for record in out.split("\x00")[1:]:
        first, _, rest = record.partition("\n")
        sha, _, subject = first.partition("\x1f")
        found.append((sha, subject, [p for p in rest.splitlines() if p]))
    return found


def returns(root: Path, slice_id: str) -> tuple[dict | None, str]:
    """The builder's typed return, state/returns/<slice>.json (schema: slice, role, started, finished, tasks [{id, sha}],
    tool_calls, blocked_at, notes), or None and why."""
    rel = f"state/returns/{slice_id}.json"
    try:
        doc = json.loads((root / rel).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None, f"{rel} is missing: the builder writes it before its turn ends"
    except (OSError, ValueError):
        doc = None
    tasks = doc.get("tasks") if isinstance(doc, dict) else None
    if isinstance(tasks, list) and all(isinstance(t, dict) and {"id", "sha"} <= set(t) for t in tasks):
        return doc, ""
    return None, f"{rel} does not hold the returns schema (tasks: [{{id, sha}}])"
