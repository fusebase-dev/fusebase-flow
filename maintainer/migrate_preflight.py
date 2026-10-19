#!/usr/bin/env python3
"""The preflight of `flow.py migrate --apply` (owner, 2026-10-17): every check that could stop the migration
commit runs before the first write, so a migration either goes through or stops with the tree as it was. The
dry run prints the same checks but runs only the structural ones; it names lint and typecheck as not run."""
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
    wrote: tuple[str, ...] = ()  # paths the project's lint or typecheck changed while the preflight ran it
    by_hand: tuple[str, ...] = ()  # set when not run: the commands to run by hand instead
    not_run: bool = False


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


def attributes(inv: m.Inventory, name: str = flow.ATTRIBUTES) -> Check:
    path = inv.target / name
    found = flow.block_markers(path.read_bytes().decode("utf-8", "surrogateescape"), name) if path.is_file() else (-1, -1)
    if isinstance(found, str):
        return Check(name, found, True, flow.ATTR_FIX)
    what = flow.BLOCKS[name][2]
    return Check(name, f"no Flow {what} block: install appends one" if found[0] < 0 else
                 f"the Flow {what} block, lines {found[0] + 1} to {found[1] + 1}: install replaces it")


def ignores(inv: m.Inventory) -> Check:
    return attributes(inv, flow.IGNORE)


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


# The pre-commit's interpreter rule (hooks/git/pre-commit section 1b, T269), in bash as the hook runs it: python3, then
# python, then py -3, each proved 3.10+ by `-S -c`, else by `-S <file>`, within 10 s where `timeout` exists, in the
# hook's environment (hook()). The first that passes runs everything, so PyYAML must import there in all three ways
# (T272): `-S` plus the site re-add in the hook's environment (sections 2 and 3), `-E` (commit-msg), and plainly with
# PYTHONPATH set to hooks/ (the mint). One line per candidate tried.
PICK = r"""
src='import sys; print("FFPCVER %d %d" % sys.version_info[:2])'
yml='import site, sys; sys.path[1:1] = [*site.getsitepackages(), site.getusersitepackages()]; '
yml="${yml}import yaml; print(sys.version.split()[0])"
env='import sys; print("%d|%s" % (sys.prefix != sys.base_prefix, getattr(sys, "_base_executable", sys.executable)))'
hook() { ( unset PYTHONPATH PYTHONSTARTUP PYTHONHOME; PYTHONNOUSERSITE=1 PYTHONSAFEPATH=1 "$@" ); }
v=$(mktemp) && printf '%s\n' "$src" > "$v" || exit 3
t=; command -v timeout >/dev/null 2>&1 && t="timeout 10"
for py in python3 python "py -3"; do
  at=$(command -v "${py%% *}") || continue
  out=$(hook $t $py -S -c "$src" 2>/dev/null)
  case $out in FFPCVER*) ;; *) out=$(hook $t $py -S "$v" 2>/dev/null) ;; esac
  set -- $(printf '%s\n' "$out" | sed -n 's/^FFPCVER \([0-9][0-9]*\) \([0-9][0-9]*\)$/\1 \2/p' | head -1)
  if [ $# -eq 2 ] && { [ "$1" -gt 3 ] || { [ "$1" -eq 3 ] && [ "$2" -ge 10 ]; }; }; then
    rm -f "$v"; bad=; err=
    got=$(hook $py -S -c "$yml" 2>&1) || { bad="$bad -S"; err=$got; }
    e=$($py -E -c 'import yaml' 2>&1) || { bad="$bad -E"; err=$e; }
    p=$(PYTHONPATH="$PWD/hooks" $py -c 'import yaml' 2>&1) || { bad="$bad plain"; err=$p; }
    [ -n "$bad" ] || { printf 'use\t%s\t%s\t%s\n' "$py" "$at" "$got"; exit 0; }
    info=$($py -c "$env" 2>/dev/null)
    printf 'noyaml\t%s\t%s\t%s\t%s\t%s\t%s\n' "$py" "$at" "${bad# }" "${info%%|*}" "${info#*|}" \
      "$(printf '%s\n' "$err" | tail -1)"; exit 1
  fi
  printf 'failed\t%s\t%s\n' "$py" "$at"
done
rm -f "$v"; exit 1
"""
IMPORTS = {"-S": "the pre-commit's", "-E": "commit-msg's", "plain": "the mint's"}


def interpreter(inv: m.Inventory) -> Check:
    bash = shutil.which("bash")
    if not bash:
        return Check("Python for the hooks", "no bash on PATH: the git hooks and the approval scripts need it", True,
                     "install Git for Windows (Git Bash) or bash, then re-run")
    probe = subprocess.run([bash, "-c", PICK], cwd=inv.target, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=600)
    rows = [line.split("\t") for line in probe.stdout.splitlines() if line.count("\t") in (2, 3, 6)]
    failed = "".join(f"; {r[1]} ({r[2]}{', the Microsoft Store shortcut' if 'WindowsApps' in r[2].split('/') else ''})"
                     " fails the 3.10+ probe" for r in rows if r[0] == "failed")
    pip = f"-m pip install -r \"{(flow.CORE / 'hooks/requirements.txt').as_posix()}\""
    last = rows[-1] if rows and len(rows[-1]) in (4, 7) else ["none"]
    if last[0] == "use":
        return Check("Python for the hooks", f"{last[1]} ({last[2]}), Python {last[3]} with PyYAML: the pre-commit, "
                     f"commit-msg and the approval scripts run it{failed}")
    if last[0] == "noyaml":
        py, at, modes, venv, base, why = last[1:]
        found = (f"{py} ({at}) is the Python 3.10+ the hooks run, but {' and '.join(IMPORTS[k] for k in modes.split())}"
                 f" import of PyYAML fails ({why[:160]})")
        if venv == "1":
            return Check("Python for the hooks", f"{found}; it runs a venv whose base interpreter is {base}", True,
                         f"deactivate the venv, or install PyYAML into both: `{py} {pip}` and `\"{base}\" {pip}`; "
                         "then re-run")
        return Check("Python for the hooks", found, True, f"run `{py} {pip}`, then re-run")
    return Check("Python for the hooks", f"bash finds no Python 3.10+ (tried: python3, python, py -3{failed})", True,
                 "if python3 or python is the Microsoft Store shortcut, turn off the python.exe and python3.exe App "
                 "execution aliases (Windows Settings), or install Python 3.10+ and put it on bash's PATH; then run "
                 f"`<that interpreter> {pip}` and re-run")


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


def watched(inv: m.Inventory) -> dict[str, str]:
    """sha256 ("" when absent) of each path the apply reads or writes, and of each untracked file in their folders."""
    paths = ({p for p in inv.removals() if not p.startswith(".git/")} | set(inv.replace) | set(inv.new)
             | set(inv.foreign) | set(m.REWRITTEN) | set(m.DOCS))
    folders = tuple({p.rsplit("/", 1)[0] + "/" for p in paths if "/" in p})
    others = m.git(inv.target, "ls-files", "-z", "--others", "--exclude-standard").stdout.decode("utf-8", "replace")
    paths |= {p for p in others.split("\0") if p.startswith(folders)}
    return {p: flow.sha256((inv.target / p).read_bytes()) if (inv.target / p).is_file() else "" for p in paths}


def written(inv: m.Inventory, before: dict[str, str]) -> list[str]:
    """What a command changed: any tracked path (the preflight found none changed), and the watched paths."""
    tracked = m.git(inv.target, "diff", "--name-only", "-z", "HEAD", "--").stdout.decode("utf-8", "replace")
    after = watched(inv)
    return sorted({p for p in tracked.split("\0") if p} | {p for p in before.keys() | after.keys()
                                                         if before.get(p, "") != after.get(p, "")})


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
        return Check("lint and typecheck", "the dry run does not run them; --apply runs them once before any change, "
                     f"as the migration commit's pre-commit will ({why}); to know now, run them by hand from the "
                     "project's top level:", by_hand=tuple(cmd for _, cmd in cmds), not_run=True)
    bash = shutil.which("bash") or "bash"
    env = {k: v for k, v in os.environ.items() if k not in HOOK_ENV_DROP} | HOOK_ENV_SET
    before = watched(inv)
    for name, cmd in cmds:
        print(f"[flow migrate] preflight: running {name}: {cmd}")
        sys.stdout.flush()
        try:  # as the hook runs it: eval under set -uo pipefail, from the top level
            rc = subprocess.run([bash, "-c", 'set -uo pipefail; eval "$1"', "flow-preflight", cmd],
                                cwd=inv.target, env=env, timeout=3600).returncode
        except subprocess.TimeoutExpired:
            rc = 124
        changed = written(inv, before)
        if changed:
            return Check("lint and typecheck", f"{name}: `{cmd}`{f' exited {rc} and' if rc else ''} changed "
                         f"{len(changed)} path(s) the migration reads, writes or needs clean: {', '.join(changed[:10])}"
                         + (" ..." if len(changed) > 10 else ""), True,
                         "commit what it changed or undo it, so the tree is clean again; make the command pass without "
                         "writing (Flow's pre-commit runs it at the migration commit; run its fix mode by hand first); "
                         "then re-run", tuple(changed))
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
    for check in (tracked_tree, git_hooks, hooks_path, baseline, attributes, ignores, staging, interpreter):
        stops += show(check(inv))
    checked = validators(inv, apply) if not stops else Check("lint and typecheck", "a check above stops the apply",
                                                              not_run=True)
    stops += show(checked)
    if not stops and checked.by_hand:
        print("[flow migrate] dry run: no structural check stops --apply; it runs lint and typecheck before any change, "
              "so this dry run means the migration will go through only once those two also pass by hand")
    return stops


def show(c: Check) -> list[Check]:
    print(f"[flow migrate]   {'STOP' if c.stop else 'not run' if c.not_run else 'ok'}: {c.name}: {c.found}")
    for cmd in c.by_hand:
        print(f"[flow migrate]     $ {cmd}")
    if c.stop:
        print(f"[flow migrate]     what to do: {c.fix}")
    sys.stdout.flush()
    return [c] if c.stop else []
