"""The approval record of the range check (range_check.py; split out of it in 6.0.0-m8, its 300-line ceiling):
`<git common dir>/flow/approved-changes.tsv`, one `path, old, new, time` row per approved protected-path change, shared
by every worktree; a change passes when recorded steps lead from its old bytes to its new ones."""
from __future__ import annotations

import subprocess
import time
from pathlib import Path

NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)  # no console window when the caller has none (pythonw)


def git(root: Path, *args: str) -> str:
    out = subprocess.run(["git", *args], cwd=root, capture_output=True, creationflags=NO_WINDOW, timeout=600)
    if out.returncode:
        raise RuntimeError(f"git {' '.join(args[:4])} failed: {out.stderr.decode('utf-8', 'replace').strip()}")
    return out.stdout.decode("utf-8", "surrogateescape")


def record_path(root: Path) -> Path:
    common = Path(git(root, "rev-parse", "--git-common-dir").strip())
    return (common if common.is_absolute() else root / common) / "flow" / "approved-changes.tsv"


def steps(root: Path) -> dict[str, dict[str, set[str]]]:
    """{path: {old side: {new sides}}}, the record."""
    graph: dict[str, dict[str, set[str]]] = {}
    try:
        rows = record_path(root).read_text(encoding="utf-8").splitlines()
    except OSError:
        rows = []
    for row in rows:
        cells = row.split("\t")
        if len(cells) >= 3:
            graph.setdefault(cells[0], {}).setdefault(cells[1], set()).add(cells[2])
    return graph


def approved(graph: dict, path: str, old: str, new: str) -> bool:
    """A chain of recorded steps leads from `old` to `new` for `path`."""
    seen, todo = {old}, [old]
    while todo:
        for nxt in graph.get(path, {}).get(todo.pop(), ()):
            if nxt == new:
                return True
            if nxt not in seen:
                seen.add(nxt)
                todo.append(nxt)
    return False


def protected(path: str) -> bool:
    from shared.path_policy import is_protected
    return is_protected(path)[0]


def write_record(root: Path, changes: list[tuple[str, str, str, str]]) -> list[str]:
    when = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    rows = [f"{p}\t{old}\t{new}\t{when}" for p, _, old, new in changes
            if old != new and "\t" not in p and "\n" not in p and protected(p)]
    if rows:
        path = record_path(root)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8", newline="\n") as f:
            f.write("".join(r + "\n" for r in rows))
    return rows
