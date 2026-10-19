"""Shared reader for the milestone 3 scripts in hooks/local/: git, a policy as committed at HEAD, the fields of the four
documents the scripts use, and the kernel's glob dialect. Stdlib plus PyYAML (hooks/requirements.txt)."""
from __future__ import annotations

import importlib.util
import json
import re
import subprocess
from datetime import datetime
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


def stamp(text: object) -> float | None:
    """Epoch seconds of an ISO 8601 UTC time (2026-10-18T10:00:00Z, milliseconds allowed), else None."""
    try:
        return datetime.fromisoformat(str(text).strip().replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def uncomment(text: str) -> str:
    """The text without HTML comments: the templates' examples live in them."""
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def read(path: Path) -> str:
    """The file's text without HTML comments; "" when the file is absent."""
    try:
        return uncomment(path.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return ""


def backlog(text: str) -> tuple[dict[str, dict], dict[str, dict]]:
    """Items {B<n>: {id, title, source, criterion|test, risk, status, inputs: [...], answers: [A<n>...]}} and answers
    {A<n>: {id, title, answered, text: [quoted lines]}} from backlog.md's text."""
    items: dict[str, dict] = {}
    answers: dict[str, dict] = {}
    current, key = None, None
    for line in uncomment(text).splitlines():
        if m := re.match(r"##\s+(B\d+)\b\s*(.*)", line):
            current, key = items.setdefault(m[1], {"id": m[1], "title": m[2].strip(), "inputs": [], "answers": []}), None
        elif m := re.match(r"###\s+(A\d+)\b\s*(.*)", line):
            current, key = answers.setdefault(m[1], {"id": m[1], "title": m[2].strip(), "text": []}), None
        elif line.startswith("#"):
            current = None
        elif current is None:
            continue
        elif m := re.match(r"-\s*([a-z_]+):\s*(.*)", line):
            key, value = m[1], m[2].strip()
            if key == "inputs":
                current["inputs"] += [v.strip() for v in value.split(",") if v.strip()]
            elif key == "answers":
                current["answers"] = re.findall(r"A\d+", value)
            else:
                current[key] = value
        elif (m := re.match(r"\s+-\s+(.*)", line)) and key == "inputs":
            current["inputs"].append(m[1].strip())
        elif line.startswith(">") and "text" in current:
            current["text"].append(line[1:].strip())
    return items, answers


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


def phases(root: Path, text: str | None = None) -> dict[str, dict]:
    """{slice id: {phase, base, title, tasks: [{id, item, does, globs, minutes, files}]}} from phases.md, or from `text`."""
    slices: dict[str, dict] = {}
    phase = base = current = None
    for line in (read(root / PHASES) if text is None else text).splitlines():
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


def reference(root: Path) -> str:
    """phases.md's `- reference:` line (the reference project for every phase), or "none"."""
    m = re.search(r"^-\s*reference:\s*(.+?)\s*$", read(root / PHASES).split("\n## ")[0], re.M)
    return m[1] if m else "none"


def slice_log(root: Path, sl: dict) -> list[tuple[str, str, list[str], str]]:
    """(sha, subject, paths, task) of each commit since the phase's base whose subject carries a task of the slice."""
    base, ids = sl["base"] or "", {t["id"] for t in sl["tasks"]}
    if not SHA.fullmatch(base) or not git(root, "rev-parse", "--verify", "-q", f"{base}^{{commit}}"):
        return []
    return [(sha, s, paths, found[0]) for sha, s, paths in commits(root, base)
            if (found := [i for i in TASK.findall(s) if i in ids])]


def trivial(log: list, match, globs: list[str]) -> bool:
    """A trivial-tier slice: it has commits and every path of every one is in the policy's trivial lists."""
    return bool(log) and all(paths and all(match(p, globs) for p in paths) for _, _, paths, *_ in log)


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
