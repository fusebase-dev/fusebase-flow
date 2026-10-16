"""Git process plumbing for checks.py --retro: pinned argv, one no-progress watchdog over every git child, the log
stream parser, ls-tree, and a bounded `cat-file --batch` reader. Stdlib only.
"""
from __future__ import annotations

import re
import subprocess
import threading
import time

# Flow team definition 2026-10-16: a git child that produces no output for this long is hung. About 6x the slowest
# process start measured on the owner's host (46 s, retro-hist.md 2.2). Fixture R19 lowers it in-process.
STALL_SECONDS = 300
DRAIN_CHUNK = 65536

# TRIPWIRE: user git config rewrites log output and hunk choice (prefixes, colour, quoting, root diff, diff
# algorithm, indent heuristic). Fixture R18 reruns under a hostile config and must produce the same TSV bytes.
GIT_PINS = ("-c", "core.quotepath=off", "-c", "diff.noprefix=false", "-c", "diff.mnemonicprefix=false",
            "-c", "color.ui=never", "-c", "log.showSignature=false", "-c", "log.showRoot=true",
            "-c", "diff.srcPrefix=a/", "-c", "diff.dstPrefix=b/", "-c", "diff.relative=false",
            "-c", "diff.algorithm=myers", "-c", "diff.indentHeuristic=true")
# TRIPWIRE: without --no-abbrev, --raw prints abbreviated blob ids and every cat-file lookup breaks.
LOG_ARGS = ("log", "--topo-order", "--reverse", "--no-renames", "--no-ext-diff", "--no-textconv", "--no-color",
            "--diff-algorithm=myers", "--raw", "--no-abbrev", "-p", "-U0", "--format=%x1eC %H %P%x1f%aI%x1f%s")

HUNK_RE = re.compile(rb"@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
SHA_RE = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?")
TASK_RE = re.compile(r"\bT\d+[a-z]?\b")
C_ESCAPES = {ord("a"): 7, ord("b"): 8, ord("t"): 9, ord("n"): 10, ord("v"): 11, ord("f"): 12, ord("r"): 13,
             ord('"'): 34, ord("\\"): 92}


class Fail(Exception):
    """An exit code with a fixed label; labels never carry repository content."""

    def __init__(self, code: int, label: str):
        super().__init__(label)
        self.code, self.label = code, label


class Git:
    """Every git child of one run. A watchdog thread kills them all once no progress is seen for STALL_SECONDS."""

    def __init__(self, repo: str):
        self.repo, self.procs, self.fired, self.last = repo, [], False, time.monotonic()
        self.done = threading.Event()
        threading.Thread(target=self._watch, daemon=True).start()

    def argv(self, *args: str) -> list:
        return ["git", "-C", self.repo, *GIT_PINS, *args]

    def tick(self) -> None:
        self.last = time.monotonic()

    def spawn(self, args, stdin=subprocess.DEVNULL):
        try:
            p = subprocess.Popen(self.argv(*args), stdin=stdin, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            raise Fail(3, "git not found") from None
        self.procs.append(p)
        self.tick()
        return p

    def run(self, *args: str):
        """A finite command, bounded by STALL_SECONDS."""
        p = self.spawn(args)
        try:
            out, _ = p.communicate(timeout=STALL_SECONDS)
        except subprocess.TimeoutExpired:
            self.fired = True
            p.kill()
            p.communicate()
        self.check()
        self.tick()
        return p.returncode, out

    def _watch(self) -> None:
        while not self.done.wait(0.5):
            if self.fired or (time.monotonic() - self.last > STALL_SECONDS
                              and any(p.poll() is None for p in self.procs)):
                self.fired = True
                self.kill()

    def kill(self) -> None:
        for p in self.procs:
            if p.poll() is None:
                try:
                    p.kill()
                except OSError:
                    pass

    def check(self) -> None:
        if self.fired:
            raise Fail(4, f"git made no progress for {STALL_SECONDS} s; git children killed")

    def close(self) -> None:
        self.done.set()
        self.kill()
        for p in self.procs:
            p.wait()


def unquote(b: bytes) -> str:
    if b.startswith(b'"'):
        if len(b) < 2 or not b.endswith(b'"'):
            raise Fail(4, "quoted path parse")
        out, i, end = bytearray(), 1, len(b) - 1
        while i < end:
            ch = b[i]
            if ch != 92:
                out.append(ch)
                i += 1
            elif b[i + 1] in C_ESCAPES:
                out.append(C_ESCAPES[b[i + 1]])
                i += 2
            elif 48 <= b[i + 1] <= 55:
                out.append(int(b[i + 1:i + 4], 8))
                i += 4
            else:
                raise Fail(4, "quoted path parse")
        b = bytes(out)
    return b.decode("utf-8", "surrogateescape")


def patch_path(b: bytes):
    if b == b"/dev/null":
        return None
    if b.endswith(b"\t"):
        b = b[:-1]
    p = unquote(b)
    if not p.startswith("b/"):
        raise Fail(4, "patch path parse")
    return p[2:]


class Commit:
    __slots__ = ("sha", "parents", "task", "entries", "added", "wanted")

    def __init__(self, sha: str, parents: list, task: str):
        self.sha, self.parents, self.task = sha, parents, task
        self.entries, self.added, self.wanted = [], {}, {}


def _header(line: bytes, commits: list, seen: set):
    head, _, rest = line[1:].decode("utf-8", "replace").partition("\x1f")
    ids = head.split()
    if len(ids) < 2 or ids[0] != "C" or not all(SHA_RE.fullmatch(x) for x in ids[1:]):
        raise Fail(4, "log header parse")
    if ids[1] in seen:
        return None
    seen.add(ids[1])
    tasks = sorted(set(TASK_RE.findall(rest.partition("\x1f")[2])))
    commit = Commit(ids[1], ids[2:], tasks[0] if len(tasks) == 1 else ("multi" if tasks else ""))
    commits.append(commit)
    return commit


def _raw_entry(line: bytes):
    meta, _, p = line.partition(b"\t")
    f = meta[1:].split(b" ")
    if len(f) != 5 or not p or not SHA_RE.fullmatch(f[3].decode("ascii", "replace")):
        raise Fail(4, "raw line parse")
    return f[1].decode("ascii"), f[3].decode("ascii"), f[4][:1].decode("ascii"), unquote(p)


def parse_log(stream, record, tick) -> list:
    """Pass A: per-commit raw entries, plus added raw line ranges for every path where record(path) is true."""
    commits, seen = [], set()
    cur, skip, adds = None, True, None
    old_left = new_left = new_no = 0
    for line in stream:
        tick()
        if line.endswith(b"\n"):
            line = line[:-1]
        # TRIPWIRE: hunk bodies can start with "+++"/"---"; consume them by the @@ counts, never by prefix.
        if old_left > 0 or new_left > 0:
            c = line[:1]
            if c == b"+":
                if adds is not None:
                    if adds and adds[-1][1] == new_no - 1:
                        adds[-1][1] = new_no
                    else:
                        adds.append([new_no, new_no])
                new_no += 1
                new_left -= 1
            elif c == b"-":
                old_left -= 1
            elif c in (b" ", b""):
                new_no += 1
                old_left -= 1
                new_left -= 1
            elif c != b"\\":
                raise Fail(4, "hunk body parse")
            if old_left < 0 or new_left < 0:
                raise Fail(4, "hunk count parse")
            continue
        if line[:1] == b"\x1e":
            cur = _header(line, commits, seen)
            skip, adds = cur is None or len(cur.parents) > 1, None
            continue
        if not commits:
            raise Fail(4, "log stream parse")
        if skip:
            continue
        if line[:1] == b":":
            cur.entries.append(_raw_entry(line))
        elif line.startswith(b"diff "):
            adds = None
        elif line.startswith(b"+++ "):
            p, adds = patch_path(line[4:]), None
            if p is not None and record(p):
                adds = cur.added.setdefault(p, [])
        elif line.startswith(b"@@ "):
            m = HUNK_RE.match(line)
            if not m:
                raise Fail(4, "hunk header parse")
            old_left = 1 if m.group(1) is None else int(m.group(1))
            new_no = int(m.group(2))
            new_left = 1 if m.group(3) is None else int(m.group(3))
    if old_left or new_left:
        raise Fail(4, "truncated hunk")
    return commits


def read_log(git: Git, rng: str, record) -> list:
    proc = git.spawn((*LOG_ARGS, rng, "--"))
    try:
        commits = parse_log(proc.stdout, record, git.tick)
    finally:
        proc.stdout.close()
        rc = proc.wait()
        git.check()
    if rc != 0:
        raise Fail(4, "git log failed")
    return commits


def ls_tree(git: Git, sha: str) -> dict:
    rc, out = git.run("ls-tree", "-r", "-z", "--full-tree", sha)
    if rc != 0:
        raise Fail(4, "ls-tree failed")
    tree = {}
    for rec in out.split(b"\0"):
        if rec:
            meta, tab, p = rec.partition(b"\t")
            f = meta.split(b" ")
            if not tab or len(f) != 3:
                raise Fail(4, "ls-tree parse")
            if f[1] == b"blob" and f[0].startswith(b"100"):
                tree[p.decode("utf-8", "surrogateescape")] = f[2].decode("ascii")
    return tree


class CatFile:
    """One long-lived `git cat-file --batch`, one request per blob."""

    def __init__(self, git: Git):
        self.proc, self.tick = git.spawn(("cat-file", "--batch"), subprocess.PIPE), git.tick

    def get(self, sha: str, limit: int):
        """The blob bytes, or None when missing or larger than limit (drained in chunks, protocol kept in sync)."""
        want = sha.encode("ascii")
        self.proc.stdin.write(want + b"\n")
        self.proc.stdin.flush()
        f = self.proc.stdout.readline().split()
        self.tick()
        if len(f) == 2 and f[1] == b"missing" and f[0] == want:
            return None
        if len(f) != 3 or f[0] != want or f[1] != b"blob" or not f[2].isdigit():
            raise Fail(4, "cat-file desync")
        left = int(f[2])
        data = self.proc.stdout.read(left) if left <= limit else None
        if data is not None:
            left -= len(data)
            if left:
                raise Fail(4, "cat-file desync")
        while left > 0:
            chunk = self.proc.stdout.read(min(DRAIN_CHUNK, left))
            if not chunk:
                raise Fail(4, "cat-file desync")
            left -= len(chunk)
            self.tick()
        if self.proc.stdout.read(1) != b"\n":
            raise Fail(4, "cat-file desync")
        self.tick()
        return data

    def close(self) -> None:
        for pipe in (self.proc.stdin, self.proc.stdout):
            try:
                pipe.close()
            except OSError:
                pass
        self.proc.wait()
