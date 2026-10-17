#!/usr/bin/env python3
"""The preflight of `flow.py migrate --apply` (owner, 2026-10-17): every check that could stop the migration
commit runs before the first write, so a migration either goes through or stops with the tree as it was. The
dry run prints the same checks, all but running lint and typecheck."""
from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import flow
import migrate as m

# hooks/git/pre-commit clears these and sets the two below before it runs lint and typecheck.
HOOK_ENV_DROP = ("PYTHONPATH", "PYTHONSTARTUP", "PYTHONHOME")
HOOK_ENV_SET = {"PYTHONNOUSERSITE": "1", "PYTHONSAFEPATH": "1"}
VALIDATORS = (("lint", "FUSEBASE_FLOW_LINT"), ("typecheck", "FUSEBASE_FLOW_TYPECHECK"))


@dataclass
class Check:
    name: str
    found: str  # what the check saw
    stop: bool = False
    fix: str = ""  # what to do when it stops


def out(proc: subprocess.CompletedProcess) -> str:
    return proc.stdout.decode("utf-8", "replace").strip()


def git_path(target: Path, rel: str) -> Path:
    p = Path(out(m.git(target, "rev-parse", "--git-path", rel)))
    return p if p.is_absolute() else target / p


def tracked_tree(inv: m.Inventory) -> Check:
    lines = [line for line in out(m.git(inv.target, "status", "--porcelain", "--untracked-files=no")).splitlines()
             if line.strip()]
    if not lines:
        return Check("tracked tree", "clean")
    return Check("tracked tree", f"{len(lines)} tracked changes: {'; '.join(lines[:5])}" + (" ..." if len(lines) > 5 else ""),
                 True, "commit or stash them first, so the migration commit holds the migration alone")


def git_hooks(inv: m.Inventory) -> Check:
    if not inv.custom_hooks and not inv.edited_hooks:
        return Check("git hooks", "pre-commit, commit-msg and pre-push in .git/hooks are Flow's or absent")
    found, fixes = [], []
    if inv.custom_hooks:
        found.append(f"{', '.join(f'.git/hooks/{h}' for h in inv.custom_hooks)}: the project's own (no "
                     "fusebase-flow-managed-hook marker in the first 5 lines); install keeps it, so the migration "
                     "commit would run it instead of Flow's")
    if inv.edited_hooks:
        found.append(f"{', '.join(f'.git/hooks/{h}' for h in inv.edited_hooks)}: Flow's marker, but the bytes match "
                     "no Flow 5.x release: an edit that install would overwrite")
        fixes.append("to drop the edit, restore Flow's copy: "
                     + "; ".join(f"cp hooks/git/{h} .git/hooks/{h}" for h in inv.edited_hooks))
    hooks = inv.custom_hooks + inv.edited_hooks
    fixes.append("to keep the hook, move it aside after carrying its pre-commit checks into the project's lint or "
                 "typecheck command (Flow's pre-commit runs those): "
                 + "; ".join(f"mv .git/hooks/{h} .git/hooks/{h}.pre-flow" for h in hooks)
                 + "; or stay on Flow 5.x until the hook's owner decides")
    return Check("git hooks", "; ".join(found), True,
                 "; ".join(fixes) + ". Then re-run. The migrator never replaces a hook it did not write")


def hooks_path(inv: m.Inventory) -> Check:
    value = out(m.git(inv.target, "config", "--get", "core.hooksPath"))
    if not value:
        return Check("core.hooksPath", "unset")
    if git_path(inv.target, "hooks").resolve() == m.hooks_dir(inv.target).resolve():
        return Check("core.hooksPath", f"{value}: the .git/hooks folder Flow installs its hooks into")
    origin = out(m.git(inv.target, "config", "--show-origin", "--get", "core.hooksPath")).split("\t")[0]
    return Check(
        "core.hooksPath", f"set to {value} ({origin}): git runs the hooks there, so the migration commit would run "
        "them and not the Flow hooks install writes to .git/hooks", True,
        "unset it where it is set (`git config --unset core.hooksPath`, with --global or --system when its origin "
        "says so; a Husky prepare script sets it again on the next npm install) and carry the checks those hooks run "
        "into the project's lint or typecheck command, which Flow's pre-commit runs; then re-run")


def baseline(inv: m.Inventory) -> Check:
    path = inv.target / m.BASELINE
    if not path.exists() and not path.is_symlink():
        return Check("baseline carry", f"no {m.BASELINE}: install writes the core's")
    if path.is_symlink() or not path.is_file():
        return Check("baseline carry", f"{m.BASELINE} is a symlink or not a regular file, which install refuses",
                     True, "replace it with the regular file it stands for, then re-run")
    try:
        path.read_bytes().decode("utf-8")
    except UnicodeDecodeError:
        return Check("baseline carry", f"{m.BASELINE} is not UTF-8, so the module-size check cannot read it",
                     True, "save it as UTF-8, then re-run")
    core = len(flow.baseline_rows((flow.CORE / m.BASELINE).read_bytes()))
    rows = (": " + ", ".join(inv.rows[:5]) + (" ..." if len(inv.rows) > 5 else "")) if inv.rows else ""
    return Check("baseline carry", f"the core's rows ({core}) plus the project's ({len(inv.rows)}){rows}")


def planned_paths(inv: m.Inventory) -> list[str]:
    """What the migration commit stages by name (migrate_apply.commit), before any of it exists."""
    index = set(m.git(inv.target, "ls-files", "-z").stdout.decode("utf-8", "replace").split("\0"))
    return sorted({p for p in inv.removals() if p in index} | set(inv.replace) | set(inv.new)
                  | set(m.REWRITTEN) | set(m.DOCS))


def changed_paths(inv: m.Inventory) -> list[str]:
    """The paths the migration commit changes, for the validator-free tier (an extra path can only make it stricter)."""
    index = set(m.git(inv.target, "ls-files", "-z").stdout.decode("utf-8", "replace").split("\0"))
    return sorted({p for p in inv.removals() if p in index} | (set(inv.replace) - set(inv.identical)) | set(inv.new)
                  | set(inv.overlays) | ({"VERSION"} if inv.version_is_flow else set()) | set(m.DOCS)
                  | {flow.ATTRIBUTES})


def staging(inv: m.Inventory) -> Check:
    lock = git_path(inv.target, "index.lock")
    if lock.exists():
        return Check("staging", f"{lock} exists: a git process holds the index", True,
                     "let that git process finish; if none runs, delete the lock file; then re-run")
    paths = planned_paths(inv)
    add = m.git(inv.target, "--literal-pathspecs", "add", "--dry-run", "--ignore-missing", "-f",
                "--pathspec-from-file=-", "--pathspec-file-nul", data="\0".join(paths).encode("utf-8"))
    if add.returncode:
        why = add.stderr.decode("utf-8", "replace").strip()[:400]
        return Check("staging", f"`git add --dry-run` of the {len(paths)} paths the commit stages exited "
                     f"{add.returncode}: {why}", True,
                     "fix what git names (a sparse checkout, a submodule or a symlink on a Flow path), then re-run")
    return Check("staging", f"the {len(paths)} paths the commit stages by name can be staged "
                 f"({len(inv.hidden)} hidden by .gitignore, staged with -f)")


def interpreter(inv: m.Inventory) -> Check:
    bash = shutil.which("bash")
    if not bash:
        return Check("python3 for the hooks", "no bash on PATH: the git hooks and the approval script need it", True,
                     "install Git for Windows (Git Bash) or bash, then re-run")
    probe = subprocess.run([bash, "-c", 'command -v python3 >/dev/null || { echo "no python3 on PATH"; exit 1; }; '
                            'python3 -c "import sys, yaml; print(sys.version.split()[0])"'],
                           cwd=inv.target, capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=600)
    if probe.returncode:
        why = (probe.stdout + probe.stderr).strip().splitlines()[-1:] or ["exit %d" % probe.returncode]
        return Check("python3 for the hooks", f"bash finds no python3 with PyYAML ({why[0][:200]}); the approval "
                     "and the hooks run python3", True,
                     "put Python 3.10+ on bash's PATH as python3 and run "
                     f"`python3 -m pip install -r {(flow.CORE / 'hooks/requirements.txt').as_posix()}`; then re-run")
    return Check("python3 for the hooks", f"python3 {probe.stdout.strip()} with PyYAML")


def validator_commands(target: Path) -> list[tuple[str, str]]:
    """The commands hooks/local/lib/precommit-validator-reuse.sh finds: FUSEBASE_FLOW_LINT or _TYPECHECK, else
    `npm run -s lint` or `npm run -s typecheck` when package.json carries the quoted name."""
    try:
        package = (target / "package.json").read_bytes()
    except OSError:
        package = b""
    found = []
    for name, env in VALIDATORS:
        cmd = os.environ.get(env) or (f"npm run -s {name}" if f'"{name}"'.encode() in package else "")
        if cmd:
            found.append((name, cmd))
    return found


def tier(inv: m.Inventory) -> tuple[bool, str]:
    """The kernel's validator-free tier (hooks/local/lib/validator_tier.py, read only) on the commit's paths."""
    try:
        spec = importlib.util.spec_from_file_location("_flow_validator_tier",
                                                      flow.CORE / "hooks/local/lib/validator_tier.py")
        vt = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(vt)
        blob, info = vt.read_declaration(inv.target)
        if blob is None:
            return False, info
        compile_glob = vt.load_glob(flow.CORE)
        patterns, why = vt.parse_declaration(blob, compile_glob)
        if not patterns:
            return False, f"{vt.DECLARATION}: {why}"
        verdict = vt.decide(changed_paths(inv), patterns, compile_glob)
        return verdict.skip, verdict.reason
    except Exception as exc:  # the hook runs the validators on every outcome but a skip
        return False, f"tier check error ({exc.__class__.__name__})"


def validators(inv: m.Inventory, run: bool) -> Check:
    cmds = validator_commands(inv.target)
    if not cmds:
        return Check("lint and typecheck", "none: no FUSEBASE_FLOW_LINT or FUSEBASE_FLOW_TYPECHECK and no "
                     '"lint" or "typecheck" in package.json, so Flow\'s pre-commit runs none')
    names = "; ".join(cmd for _, cmd in cmds)
    skip, why = tier(inv)
    if skip:
        return Check("lint and typecheck", f"{names}: not run, as the pre-commit will skip them ({why})")
    if not run:
        return Check("lint and typecheck", f"{names}: --apply runs them once before any change, as the "
                     f"migration commit's pre-commit will ({why})")
    bash = shutil.which("bash") or "bash"
    env = {k: v for k, v in os.environ.items() if k not in HOOK_ENV_DROP} | HOOK_ENV_SET
    for name, cmd in cmds:
        print(f"[flow migrate] preflight: running {name}: {cmd}")
        sys.stdout.flush()
        try:  # as the hook runs it: eval under set -uo pipefail, from the top level
            rc = subprocess.run([bash, "-c", 'set -uo pipefail; eval "$1"', "flow-preflight", cmd],
                                cwd=inv.target, env=env, timeout=3600).returncode
        except subprocess.TimeoutExpired:
            rc = 124
        if rc:
            return Check("lint and typecheck", f"{name} failed: `{cmd}` exited {rc} (its output is above); Flow's "
                         "pre-commit runs it before the migration commit and would block it", True,
                         f"make `{cmd}` pass on this tree (or point FUSEBASE_FLOW_{name.upper()} at the command the "
                         "project uses), then re-run")
    return Check("lint and typecheck", f"{names}: passed")


def run(inv: m.Inventory, apply: bool) -> list[Check]:
    """Prints each check as it completes; lint and typecheck run (with --apply) only when the rest pass."""
    print("[flow migrate] preflight (--apply runs it before it changes anything):")
    stops: list[Check] = []
    for check in (tracked_tree, git_hooks, hooks_path, baseline, staging, interpreter):
        stops += show(check(inv))
    stops += show(validators(inv, apply) if not stops
                  else Check("lint and typecheck", "not run: a check above stops the apply"))
    return stops


def show(c: Check) -> list[Check]:
    print(f"[flow migrate]   {'STOP' if c.stop else 'ok'}: {c.name}: {c.found}")
    if c.stop:
        print(f"[flow migrate]     what to do: {c.fix}")
    sys.stdout.flush()
    return [c] if c.stop else []
