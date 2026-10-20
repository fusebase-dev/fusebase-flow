#!/usr/bin/env python3
"""One Flow commit at a time per repository (6.0.0-m6 item 5): `commit.py -m <subject> <path>...` takes the
repository's Flow commit lock (flow-commit.lock in git's common directory), waits while another Flow commit or a
git index lock holds the repository, stages exactly the named paths and commits only them (`git commit --only`),
then releases the lock. The planner and every builder commit through it, in one work tree and one git index:
a planner commit during a builder run neither fails on .git/index.lock nor carries a builder's staged paths, and no
commit loses its ref update to another landing while its hooks run. The git hooks run as for any commit.
Exit: git's own; 3 when the repository stays held past --wait seconds (default 1800).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

LIVE = 10    # seconds between the holder's touches of the lock
STALE = 120  # a lock untouched this long has lost its holder (killed, crashed) and is taken over


def git(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                          timeout=600)


def held(lock: Path, index_lock: Path) -> str:
    """Who holds the repository now, "" when nobody: a live Flow commit lock, or git's own index lock."""
    try:
        if time.time() - lock.stat().st_mtime > STALE:
            lock.unlink(missing_ok=True)  # its holder stopped touching it: gone
        else:
            return f"another Flow commit ({lock.read_text(encoding='utf-8').strip()})"
    except OSError:
        pass
    return f"a git process ({index_lock.name})" if index_lock.exists() else ""


def take(lock: Path, index_lock: Path, wait: float) -> bool:
    deadline, said = time.monotonic() + wait, ""
    while True:
        if not (who := held(lock, index_lock)):
            try:
                fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            except FileExistsError:
                continue
            os.write(fd, json.dumps({"pid": os.getpid(), "since": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
                     .encode("utf-8"))
            os.close(fd)
            return True
        if who != said:
            print(f"[flow commit] waiting: {who} holds the repository", file=sys.stderr, flush=True)
            said = who
        if time.monotonic() > deadline:
            return False
        time.sleep(1)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="commit.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("-m", "--message", required=True, help="the commit message (its subject first)")
    ap.add_argument("paths", nargs="+", help="the files this commit stages and commits, and nothing else")
    ap.add_argument("--wait", type=float, default=1800, help="seconds to wait for the repository (default 1800)")
    args = ap.parse_args(argv)
    here = Path.cwd()
    common = Path(git(here, "rev-parse", "--git-common-dir").stdout.strip() or ".git")
    common = common if common.is_absolute() else here / common
    index_lock = Path(git(here, "rev-parse", "--git-path", "index.lock").stdout.strip() or ".git/index.lock")
    lock = common / "flow-commit.lock"
    if not take(lock, index_lock if index_lock.is_absolute() else here / index_lock, args.wait):
        print(f"[flow commit] STOPPED: the repository was still held after {args.wait:.0f} s; nothing was staged or "
              f"committed. Commit again when the other commit has finished.", file=sys.stderr)
        return 3
    try:
        deadline = time.monotonic() + args.wait
        # a git process outside Flow can take the index lock between the wait and the add: wait and retry
        while (add := git(here, "add", "--", *args.paths)).returncode and "index.lock" in add.stderr \
                and time.monotonic() < deadline:
            time.sleep(1)
        if add.returncode:
            print(add.stdout + add.stderr, end="", file=sys.stderr)
            return add.returncode
        # TRIPWIRE: --only commits the named paths from HEAD plus the work tree, never what else sits in the index.
        proc = subprocess.Popen(["git", "commit", "-m", args.message, "--only", "--", *args.paths], cwd=here)
        while True:
            try:
                return proc.wait(timeout=LIVE)
            except subprocess.TimeoutExpired:
                os.utime(lock)  # still committing: the lock stays live
    finally:
        lock.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
