#!/usr/bin/env python3
"""The preflight of `flow.py migrate --apply` (owner, 2026-10-17): every check that could stop the migration
commit runs before the first write, so a migration either goes through or stops with the tree as it was. The
dry run prints the same checks."""
from __future__ import annotations

from dataclasses import dataclass

import migrate as m


@dataclass
class Check:
    name: str
    found: str  # what the check saw
    stop: bool = False
    fix: str = ""  # what to do when it stops


def tracked_tree(inv: m.Inventory) -> Check:
    out = m.git(inv.target, "status", "--porcelain", "--untracked-files=no").stdout.decode("utf-8", "replace")
    lines = [line for line in out.splitlines() if line.strip()]
    if not lines:
        return Check("tracked tree", "clean")
    return Check("tracked tree", f"{len(lines)} tracked changes: {'; '.join(lines[:5])}" + (" ..." if len(lines) > 5 else ""),
                 True, "commit or stash them first, so the migration commit holds the migration alone")


def git_hooks(inv: m.Inventory) -> Check:
    if not inv.custom_hooks:
        return Check("git hooks", "pre-commit, commit-msg and pre-push in .git/hooks are Flow's or absent")
    named = ", ".join(f".git/hooks/{h}" for h in inv.custom_hooks)
    moves = "; ".join(f"mv .git/hooks/{h} .git/hooks/{h}.pre-flow" for h in inv.custom_hooks)
    return Check(
        "git hooks",
        f"{named}: the project's own (no fusebase-flow-managed-hook marker in the first 5 lines); install keeps it, "
        "so the migration commit would run it instead of Flow's", True,
        "either move it aside and re-run, after carrying its pre-commit checks into the project's lint or typecheck "
        f"command (Flow's pre-commit runs those): {moves}; or keep it and stay on Flow 5.x until its owner decides. "
        "The migrator never replaces a hook it did not write")


def checks(inv: m.Inventory) -> list[Check]:
    return [tracked_tree(inv), git_hooks(inv)]


def report(results: list[Check]) -> list[Check]:
    """Prints each check; returns the ones that stop the apply."""
    print("[flow migrate] preflight (--apply runs it before it changes anything):")
    for c in results:
        print(f"[flow migrate]   {'STOP' if c.stop else 'ok'}: {c.name}: {c.found}")
        if c.stop:
            print(f"[flow migrate]     what to do: {c.fix}")
    return [c for c in results if c.stop]
