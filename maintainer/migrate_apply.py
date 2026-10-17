#!/usr/bin/env python3
"""The --apply half of `flow.py migrate` (handoff WP 12 steps 3 to 8): backup, removal, the overlay,
install and carry-over, the four documents with the migration report, and the migration commit."""
from __future__ import annotations

import datetime as dt
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

import flow
import migrate as m

BACKUP_PREFIX = ".flow-migrate-"
EXCLUDE_LINES = ("# Fusebase Flow migration backups (flow.py migrate): never stage them.", f"/{BACKUP_PREFIX}*/")


def say(line: str) -> None:
    print(f"[flow migrate] {line}".rstrip())


def source(target: Path, rel: str) -> Path:
    return m.hooks_dir(target) / rel.rsplit("/", 1)[-1] if rel.startswith(".git/hooks/") else target / rel


def backup_rel(rel: str) -> str:
    return ".git-hooks/" + rel.rsplit("/", 1)[-1] if rel.startswith(".git/hooks/") else rel


def exclude(target: Path, lines: tuple[str, ...]) -> None:
    path = Path(m.git(target, "rev-parse", "--git-path", "info/exclude").stdout.decode().strip())
    path = path if path.is_absolute() else target / path
    path.parent.mkdir(parents=True, exist_ok=True)
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    missing = [line for line in lines if line not in text.splitlines()]
    if missing:
        with open(path, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(("" if not text or text.endswith("\n") else "\n") + "\n".join(missing) + "\n")


def backup(inv: m.Inventory, stamp: str) -> tuple[Path, list[str]]:
    folder = inv.target / f"{BACKUP_PREFIX}{stamp}"
    exclude(inv.target, EXCLUDE_LINES)  # before the first copy, so git never lists the folder
    folder.mkdir()
    files = inv.removals() + inv.replace + [r for r in m.REWRITTEN if (inv.target / r).is_file()]
    for rel in files:
        dst = folder / backup_rel(rel)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source(inv.target, rel), dst)
    return folder, files


def remove(inv: m.Inventory, folder: Path) -> tuple[list[str], list[str], int]:
    """Deletes the remove list; a file the surface will not delete moves into the backup folder instead."""
    moved, failed, parents = [], [], set()
    for rel in inv.removals():
        src = source(inv.target, rel)
        try:
            try:
                src.unlink()
            except PermissionError:
                os.chmod(src, stat.S_IWRITE)  # a read-only file on Windows
                src.unlink()
        except OSError:
            try:
                os.replace(src, folder / backup_rel(rel))  # its copy is already there
                moved.append(rel)
            except OSError as exc:
                failed.append(f"{rel} ({exc.strerror or exc})")
                continue
        if not rel.startswith(".git/"):
            parents.update(p for p in src.parents if inv.target in p.parents)
    pruned = 0
    for d in sorted(parents, key=lambda p: len(p.parts), reverse=True):
        try:
            d.rmdir()  # only a folder the removal left empty
            pruned += 1
        except OSError:
            pass
    return moved, failed, pruned


def overlay_and_version(inv: m.Inventory) -> list[str]:
    """Replaces each 5.x Flow section by heading with the 6.0 block; the FLOW:PRESERVE region rides along verbatim."""
    done = []
    for name, o in inv.overlays.items():
        path = inv.target / name
        raw = path.read_bytes()
        block = (flow.CORE / flow.OVERLAY[name]).read_bytes()
        if o.crlf:
            block = block.replace(b"\n", b"\r\n")  # the file's own line endings (autocrlf checkouts)
        if o.preserve:
            block = block[:block.index(m.P_BEGIN)] + o.preserve + block[block.index(m.P_END):]
        flow.write_bytes(path, raw[:o.start] + block + raw[o.end:], False)
        done.append(f"{name}: the '{o.heading}' section ({o.end_lf - o.start_lf:,} bytes) replaced by the 6.0 block"
                    + (f", FLOW:PRESERVE ({o.preserve_lf():,} bytes) carried verbatim" if o.preserve else ""))
    if inv.version_is_flow:
        flow.write_bytes(inv.target / "VERSION", (flow.CORE / "VERSION").read_bytes(), False)
        done.append(f"VERSION: {inv.version} -> {(flow.CORE / 'VERSION').read_text(encoding='utf-8').strip()}")
    return done


def install_and_carry(inv: m.Inventory) -> list[str]:
    """Runs milestone 1's install with the 5.x records read before the removal, then carries the project's rows."""
    target = inv.target
    rc = flow.install(target, inv.providers, {p: {sha} for p, sha in inv.recorded.items() if sha})
    if rc != 0:
        raise m.Abort(f"install exited {rc} (its report above); the backup folder holds every file")
    plan = flow.planned_files(inv.providers)
    wrong = [p for p in inv.replace + inv.new if p in plan
             and not ((target / p).is_file() and flow.same_content((target / p).read_bytes(), flow.sha256(plan[p])))]
    if wrong:
        raise m.Abort(f"after install {len(wrong)} core paths do not hold the core's bytes: {', '.join(wrong[:10])}")
    done = [f"install: the {len(inv.replace)} replace and {len([p for p in inv.new if p in plan])} new files hold "
            f"the core's bytes; {flow.MANIFEST} says "
            f"{json.loads((target / flow.MANIFEST).read_text(encoding='utf-8'))['flow_version']}"]
    baseline = target / m.BASELINE
    text = baseline.read_text(encoding="utf-8")
    rows = [r for r in inv.rows if r not in text.splitlines()]
    if rows:
        flow.write_bytes(baseline, (text + ("" if text.endswith("\n") else "\n") + "\n".join(rows) + "\n")
                         .encode("utf-8"), False)
    stale = [line.split(None, 1)[1] for line in text.splitlines()
             if line[:1].isdigit() and len(line.split(None, 1)) == 2 and not (target / line.split(None, 1)[1]).exists()]
    done.append(f"carry-over: {m.BASELINE} is the core's plus {len(inv.rows)} project rows"
                + (f" (rows naming files the core does not carry: {', '.join(stale)})" if stale else "")
                + f"; local overrides left in place: {len(inv.keep.get('local overrides', []))}")
    hooks = m.hooks_dir(target)
    same = [h for h in m.GIT_HOOKS if (hooks / h).is_file()
            and (hooks / h).read_bytes() == (flow.CORE / "hooks/git" / h).read_bytes()]
    if len(same) != len(m.GIT_HOOKS):
        raise m.Abort(f"git hooks not byte-identical to the core's: {', '.join(sorted(set(m.GIT_HOOKS) - set(same)))}")
    done.append(f"git hooks: {', '.join(same)} in .git/hooks/ byte-identical to the core's")
    return done


def migration_report(inv: m.Inventory, stamp: str, folder: Path, backed: int, moved: list[str]) -> list[str]:
    core = (flow.CORE / "VERSION").read_text(encoding="utf-8").strip()
    when = dt.datetime.strptime(stamp, "%Y%m%dT%H%M%SZ").strftime("%Y-%m-%dT%H:%MZ")
    groups = "; ".join(f"{g} {len(inv.remove[g])}" for g in m.GROUPS)
    never = "; ".join(f"{k} {len(v)}" for k, v in inv.never.items())
    keep = "; ".join(f"{k}: {', '.join(v) if len(v) <= 12 else len(v)}" for k, v in inv.keep.items())
    refs = "; ".join(f"{rel} ({', '.join(found)})" for rel, found in inv.consumers.items()) or "none"
    lines = [
        "## Migration report",
        f"- {when} Fusebase Flow {inv.version} -> {core} by `flow.py migrate --apply --go-ahead` "
        f"(providers: {', '.join(sorted(inv.providers))})",
        f"- pre-migration commit: {inv.head} ({inv.branch}); rollback: `git checkout {inv.head[:8]}`",
        f"- backup folder: {folder.name}/ ({backed} files, excluded in .git/info/exclude; delete it once the "
        "migration is accepted)" + (f"; {len(moved)} files moved into it, deletion refused" if moved else ""),
        f"- remove: {len(inv.removals())} ({groups})",
        f"- replace: {len(inv.replace)} ({len(inv.identical)} already identical); new: {len(inv.new)}; rewritten: "
        f"{', '.join(list(inv.overlays) + (['VERSION'] if inv.version_is_flow else []))}; .gitignore unchanged",
        f"- never touch: {never}; {m.CLI_VENDOR} {inv.vendor[0]} listed, {inv.vendor[1]} present",
        f"- keep: {keep}",
        "- changed-by-both: 0",
        f"- consumer references ({len(inv.consumers)}): {refs}",
        f"- history mentions under {', '.join(m.HISTORY_DIRS)}/: {len(inv.history)} files, kept as written",
        f"- hidden by .gitignore: {', '.join(inv.hidden) or 'none'}",
        f"- hook wiring (left as is): {inv.wiring}",
        "- not run: check-cli-flow-conflicts.sh and the health check (neither is in the 6.0 core yet)",
    ]
    return lines


def documents(inv: m.Inventory, report: list[str]) -> list[str]:
    """Creates the four documents from the core's templates when absent; the report leads the ledger."""
    created = []
    for rel in m.DOCS:
        dest = inv.target / rel
        if not dest.exists():
            flow.write_bytes(dest, (flow.CORE / "templates" / Path(rel).name).read_bytes(), False)
            created.append(Path(rel).name)
    ledger = inv.target / "docs/flow/ledger.md"
    text = ledger.read_text(encoding="utf-8")
    head, sep, rest = text.partition("\n") if text.startswith("status:") else ("", "", text)
    block = "\n".join(report) + "\n"
    flow.write_bytes(ledger, (head + sep + "\n" + block + ("\n" if not rest.startswith("\n") else "") + rest)
                     .encode("utf-8"), False)
    return [f"documents: {', '.join(created) or 'none'} created from the core's templates in docs/flow/; "
            f"the migration report ({len(report) - 1} lines) leads ledger.md; backlog.md has no items"]


def apply(inv: m.Inventory) -> int:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    folder, files = backup(inv, stamp)
    say(f"backup: {folder.name}/ holds {len(files)} files: remove {len(inv.removals())} + replace "
        f"{len(inv.replace)} + {len(files) - len(inv.removals()) - len(inv.replace)} rewritten in place; "
        "listed in .git/info/exclude")
    moved, failed, pruned = remove(inv, folder)
    say(f"removed: {len(inv.removals()) - len(moved) - len(failed)} files deleted, {pruned} folders the removal "
        "left empty pruned")
    if moved:
        say(f"moved into {folder.name}/ because this surface refused the deletion: {len(moved)} files "
            "(delete the folder once the migration is accepted)")
    if failed:
        say(f"STOPPED: {len(failed)} files could be neither deleted nor moved; the backup holds every file:")
        for line in failed:
            say(f"  {line}")
        return 1
    for line in overlay_and_version(inv):
        say(line)
    try:
        for line in install_and_carry(inv):
            say(line)
    except m.Abort as exc:
        say(f"STOPPED: {exc}")
        return 1
    for line in documents(inv, migration_report(inv, stamp, folder, len(files), moved)):
        say(line)
    return commit(inv, folder)


def bash(target: Path, *args: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, FF_BOOTSTRAP_TTL_MIN="30")
    return subprocess.run([shutil.which("bash") or "bash", *args], cwd=target, env=env,
                          capture_output=True, text=True, timeout=600)


def commit(inv: m.Inventory, folder: Path) -> int:
    """Stages the migration by name, mints the single-use approval, commits through the hooks, consumes."""
    target = inv.target
    index = set(m.git(target, "ls-files", "-z").stdout.decode("utf-8", "replace").split("\0"))
    paths = [p for p in inv.removals() if p in index] + inv.replace + inv.new + list(m.REWRITTEN) + list(m.DOCS)
    paths = sorted({p for p in paths if p in index or (target / p).is_file()})
    hidden = set(inv.hidden)
    for force, group in ((False, [p for p in paths if p not in hidden]), (True, [p for p in paths if p in hidden])):
        if group:
            add = m.git(target, "--literal-pathspecs", "add", *(["-f"] if force else []), "--pathspec-from-file=-",
                        "--pathspec-file-nul", data="\0".join(group).encode("utf-8"))
            if add.returncode:
                say(f"STOPPED: git add exited {add.returncode}: {add.stderr.decode('utf-8', 'replace').strip()}")
                return 1
    staged = [p for p in m.git(target, "diff", "--cached", "--name-only", "-z").stdout.decode("utf-8").split("\0") if p]
    stray = sorted(set(staged) - set(paths))
    if stray:
        say(f"STOPPED: staged paths outside the migration: {', '.join(stray[:10])}; nothing committed")
        return 1
    say(f"staged by name: {len(staged)} paths" + (f" ({len(hidden)} with -f: hidden by .gitignore)" if hidden else ""))
    core = (flow.CORE / "VERSION").read_text(encoding="utf-8").strip()
    message = (f"chore(flow): {inv.task} migrate Fusebase Flow {inv.version} to {core}\n\n"
               f"flow.py migrate --apply --go-ahead: remove {len(inv.removals())}, replace {len(inv.replace)}, "
               f"new {len(inv.new)}; the migration report leads docs/flow/ledger.md.\n"
               f"Backup: {folder.name}/ (excluded). Rollback: git checkout {inv.head[:8]}.\n")
    mint = bash(target, "hooks/local/write-bootstrap-approval.sh", "--slug", "flow-migrate")
    say(f"approval: {(mint.stdout + mint.stderr).strip()}")
    try:
        if mint.returncode:
            say("STOPPED: the approval was not minted; nothing committed")
            return 1
        say(f"committing through the hooks: {message.splitlines()[0]}")
        sys.stdout.flush()
        try:
            done = subprocess.run(["git", "commit", "-q", "-F", "-"], cwd=target, input=message.encode("utf-8"),
                                  timeout=3600)
        except subprocess.TimeoutExpired:
            say(f"STOPPED: the commit did not finish within 3600 s; HEAD is still {inv.head[:8]}")
            return 1
    finally:
        used = bash(target, "hooks/local/write-bootstrap-approval.sh", "--consume", "--slug", "flow-migrate")
        say(f"approval: {(used.stdout + used.stderr).strip()}")
    left = sorted(p.name for p in (target / "state/approvals").glob("*") if p.name != ".gitkeep")
    say(f"state/approvals/: {', '.join(left) if left else 'empty'}")
    if done.returncode:
        say(f"STOPPED: the commit did not pass (exit {done.returncode}; the hook output is above). The migration is "
            f"applied and staged; HEAD is still {inv.head[:8]}, the backup folder holds every file")
        return 1
    say(f"committed: {m.git(target, 'log', '-1', '--format=%h %s').stdout.decode('utf-8').strip()}")
    return 0
