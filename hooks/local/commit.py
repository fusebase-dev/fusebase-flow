#!/usr/bin/env python3
"""One Flow commit at a time per repository (6.0.0-m6 item 5): `commit.py -m <subject> <file>...` takes the
repository's Flow commit lock (flow-commit.lock in git's common directory), waits while another Flow commit or a
git index lock holds the repository, stages the named files that exist and commits exactly the named files
(`git commit --only`: a file staged as deleted or renamed is taken from the index), then releases the lock. The
planner and every builder commit through it, in one work tree and one git index: a planner commit during a builder
run neither fails on .git/index.lock nor carries a builder's staged paths, and no commit loses its ref update to
another landing while its hooks run. Names are literal (no glob); a folder is refused. The git hooks run as for any
commit. Exit: git's own; 2 a folder named; 3 when the repository stays held past --wait seconds (default 1800), or
an index.lock that no git process holds is left behind.
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
NO_WINDOW = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}


def git(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    # TRIPWIRE: --literal-pathspecs: a file name is never a pattern (`app[id].ts` must not also commit `appi.ts`).
    return subprocess.run(["git", "--literal-pathspecs", *args], cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=600, **NO_WINDOW)


def git_running() -> bool:
    """Whether any git process runs on this host (tasklist or ps); True when that cannot be told."""
    argv = ["tasklist", "/FI", "IMAGENAME eq git.exe", "/NH"] if os.name == "nt" else ["ps", "-A", "-o", "comm="]
    try:
        out = subprocess.run(argv, capture_output=True, text=True, errors="replace", timeout=60, **NO_WINDOW).stdout
    except (OSError, subprocess.TimeoutExpired):
        return True
    return any(line.strip().lower().split(" ")[0] in ("git", "git.exe") for line in out.splitlines() if line.strip())


def held(lock: Path, index_lock: Path) -> str:
    """Who holds the repository now, "" when nobody: a live Flow commit lock, or git's own index lock; "stale" when
    an index.lock older than STALE is there and no git process runs (a git that crashed left it)."""
    try:
        if time.time() - lock.stat().st_mtime > STALE:
            lock.unlink(missing_ok=True)  # its holder stopped touching it: gone
        else:
            return f"another Flow commit ({lock.read_text(encoding='utf-8').strip()})"
    except OSError:
        pass
    try:
        aged = time.time() - index_lock.stat().st_mtime > STALE
    except OSError:
        return ""
    return "stale" if aged and not git_running() else f"a git process ({index_lock.name})"


def take(lock: Path, index_lock: Path, wait: float) -> str:
    """"" once the lock is ours; else why not: "stale", or who still held the repository at the deadline."""
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
            return ""
        if who == "stale" or time.monotonic() > deadline:
            return who
        if who != said:
            print(f"[flow commit] waiting: {who} holds the repository", file=sys.stderr, flush=True)
            said = who
        time.sleep(1)


def release(lock: Path) -> bool:
    """Removes the lock if it is still ours (a takeover's holder keeps its own), retrying a while: on Windows a waiter
    reading it makes the delete fail (WinError 32). False when it could not be removed."""
    for _ in range(50):
        try:
            if json.loads(lock.read_text(encoding="utf-8")).get("pid") != os.getpid():
                return True
            lock.unlink()
            return True
        except FileNotFoundError:
            return True
        except (OSError, ValueError):
            time.sleep(0.1)
    return False


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="commit.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("-m", "--message", required=True, help="the commit message (its subject first)")
    ap.add_argument("paths", nargs="+", help="the files this commit stages and commits, and nothing else")
    ap.add_argument("--wait", type=float, default=1800, help="seconds to wait for the repository (default 1800)")
    args = ap.parse_args(argv)
    here = Path.cwd()
    if folders := [p for p in args.paths if os.path.isdir(p)]:
        print(f"[flow commit] STOPPED: {', '.join(folders)} is a folder; name each file. Nothing was staged or "
              "committed.", file=sys.stderr)
        return 2
    common = Path(git(here, "rev-parse", "--git-common-dir").stdout.strip() or ".git")
    common = common if common.is_absolute() else here / common
    index_lock = Path(git(here, "rev-parse", "--git-path", "index.lock").stdout.strip() or ".git/index.lock")
    index_lock = index_lock if index_lock.is_absolute() else here / index_lock
    lock = common / "flow-commit.lock"
    if why := take(lock, index_lock, args.wait):
        print(f"[flow commit] STOPPED: {index_lock} is over {STALE} s old and no git process runs: a git that stopped "
              f"left it. Remove it, then commit again. Nothing was staged or committed." if why == "stale" else
              f"[flow commit] STOPPED: {why} still held the repository after {args.wait:.0f} s; nothing was staged or "
              f"committed. Commit again when the other commit has finished.", file=sys.stderr)
        return 3
    try:
        deadline, present = time.monotonic() + args.wait, [p for p in args.paths if os.path.lexists(p)]
        # A git process outside Flow can take the index lock between the wait and the add: wait and retry, keeping our
        # lock live meanwhile. A named file that is gone is a staged delete or a rename's source: --only takes it.
        while present and (add := git(here, "add", "--", *present)).returncode and "index.lock" in add.stderr \
                and time.monotonic() < deadline:
            os.utime(lock)
            time.sleep(1)
        if present and add.returncode:
            print(add.stdout + add.stderr, end="", file=sys.stderr)
            return add.returncode
        # TRIPWIRE: --only commits the named paths from HEAD plus the work tree, never what else sits in the index.
        proc = subprocess.Popen(["git", "--literal-pathspecs", "commit", "-m", args.message, "--only", "--",
                                 *args.paths], cwd=here, **NO_WINDOW)
        while True:
            try:
                rc = proc.wait(timeout=LIVE)
                return rc
            except subprocess.TimeoutExpired:
                os.utime(lock)  # still committing: the lock stays live
    finally:
        if not release(lock):  # the commit's own result stands; only the next commit waits for the takeover
            print(f"[flow commit] note: {lock} could not be removed; the next Flow commit takes it over after {STALE} s",
                  file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
