#!/usr/bin/env python3
"""Fusebase Flow reader. Built mode: --histogram (gap and tool-call distributions, numbers only).

Exit: 0 printed with data in the window; 2 usage; 3 no data in the window; 4 output guard or internal error.
TRIPWIRE: transcripts carry credentials. Rows hold typed cells (a fixed label str, an int or float, a
Stamp) and render() checks every row against SCHEMA before anything is written. Never put an input
string in a row, and never let an exception, an argparse message, a line, a key or a path reach a stream.
"""
from __future__ import annotations

import argparse
import bisect
import json
import math
import os
import re
import subprocess
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

EDGES_MIN = (1, 2, 5, 10, 15, 20, 25, 30, 45, 60, 120, 240, 480)  # display bins, not thresholds
LONG_GAP_LIST_MIN = 20  # display only (the report's proposed 20-min watchdog), not a threshold
LONG_CAP = 50  # long rows per series
PCTS = (50, 75, 90, 95, 99)
MAX_EPOCH = 32503680000  # year 3000: Windows gmtime rejects larger values
MAX_LINE_BYTES = 64 * 1024 * 1024  # definition, review round 1 2026-10-16: longer lines are drained and counted
DRAIN_BYTES = 1024 * 1024

COMMAND_TOOLS = frozenset(("Bash", "PowerShell"))
DELEGATE_TOOLS = frozenset(("Task", "Agent", "advisor"))
EDIT_TOOLS = frozenset(("Edit", "Write", "MultiEdit", "NotebookEdit"))
EVENTS = ("pre_tool_use", "post_tool_use", "permission_request", "stop", "session_start",
          "user_prompt_submit", "pre_compact")
DECISIONS = ("allow", "deny", "ask", "warn")
CALL_CLASSES = ("command", "delegate", "other")
CLASSES = CALL_CLASSES + ("model", "idle")
LONG_CLASSES = ("command", "delegate", "model")
KINDS = ("main", "agent")
WORK = ("working", "readonly")
MEASURES = ("total", "before", "between")
LINE_KEYS = ("timed", "in_window", "untimed", "malformed", "oversized", "skipped_type", "unordered")
FILE_KEYS = ("unreadable", "partial")
AUDIT_KEYS = ("rows", "malformed", "oversized", "untimed", "unreadable", "partial")

GIT_VALUE_OPTIONS = frozenset(("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"))
ENV_ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
TEE = re.compile(r"\btee\b")

STAT_KEYS = tuple("p%d" % p for p in PCTS) + ("max",)
TAIL_KEYS = tuple("ge%dm" % e for e in EDGES_MIN)
MIN_TAILS = tuple(zip(TAIL_KEYS, EDGES_MIN))
SEC_TAILS = tuple((key, edge * 60) for key, edge in MIN_TAILS)

HELP = """usage: reader.py --histogram --out FILE [--repo PATH] [--audit FILE]... [--transcripts DIR]...
                 [--since ISO] [--until ISO]

Flow reader. --histogram prints transcript and audit-log gap and tool-call distributions as
numbers only, to stdout and to --out.

  --histogram        the only mode built so far
  --out FILE         required; receives the same text as stdout
  --repo PATH        default: git toplevel of the cwd; only locates the default inputs
  --audit FILE       audit JSONL (repeatable); default <repo>/state/audit.log.jsonl if present
  --transcripts DIR  transcript directory (repeatable); any value turns auto-location off
  --since ISO        inclusive lower bound; UTC unless an offset is given
  --until ISO        inclusive upper bound; UTC unless an offset is given

exit: 0 data printed, 2 usage, 3 no data in the window, 4 output guard or internal error
"""
USAGE_DIAG = "reader.py: usage error (see --help)\n"
INPUT_DIAG = "reader.py: an --audit file or a --transcripts directory does not exist\n"
OUT_DIAG = "reader.py: --out cannot be opened for writing\n"
EMIT_DIAG = "reader.py: an output stream failed\n"
DIAGS = (USAGE_DIAG, INPUT_DIAG, OUT_DIAG)
ABORT_GUARD = "histogram\taborted\tguard\n"
ABORT_INTERNAL = "histogram\taborted\tinternal\n"


def _schema():
    shapes = {}

    def add(shape, *labels):
        shapes[labels] = shape
    add("number", "histogram", "elapsed")
    for edge in ("since", "until"):
        add("stamp", "histogram", edge)
        add("fixed", "histogram", edge, "none")
    for fixed in (("percentile", "nearest_rank"), ("no-data",), ("aborted", "guard"), ("aborted", "internal")):
        add("fixed", "histogram", *fixed)
    for path in ([("transcripts", k) for k in KINDS] + [("files", k) for k in FILE_KEYS]
                 + [("lines", k) for k in LINE_KEYS] + [("compactions",), ("tool_calls",),
                                                        ("results", "unmatched")]):
        add("count", "input", *path)
    for path in ([("files",)] + [(k,) for k in AUDIT_KEYS] + [("event", e) for e in EVENTS + ("other",)]
                 + [("decision", d) for d in DECISIONS + ("other",)]
                 + [("tool", t) for t in ("command", "edit", "other")]
                 + [("session_id", s) for s in ("null", "present")]):
        add("count", "audit", *path)
    for kind in KINDS:
        for cls in CLASSES:
            add("stat", "S1", cls, kind, "min", "n")
        for cls in LONG_CLASSES:
            add("long", "long", "S1", cls, kind)
        for cls in CALL_CLASSES:
            add("stat", "S6", cls, kind, "sec", "n")
            add("count", "S6", "orphans", cls, kind)
        for measure in MEASURES:
            for work in WORK:
                add("plain", "S7", measure, work, kind, "calls", "n")
    for rows in ("all", "tool"):
        add("stat", "S5", "raw", rows, "min", "n")
    add("count", "more", "S1")
    return shapes


SCHEMA = _schema()
VOCAB = frozenset(label for labels in SCHEMA for label in labels) | frozenset(STAT_KEYS + TAIL_KEYS)


class GuardError(Exception):
    pass


class UsageError(Exception):
    pass


class Stamp:
    """A computed epoch that render() prints as an ISO UTC second; only allowed in timestamp columns."""
    __slots__ = ("epoch",)

    def __init__(self, epoch):
        self.epoch = epoch


def parse_ts(raw, naive_utc=False):
    if not isinstance(raw, str) or not raw:
        return None
    text = raw[:-1] + "+00:00" if raw.endswith("Z") else raw  # Python 3.10 fromisoformat rejects "Z"
    try:
        parsed = datetime.fromisoformat(text)
        if parsed.tzinfo is None:
            if not naive_utc:
                return None
            parsed = parsed.replace(tzinfo=timezone.utc)
        value = parsed.timestamp()
    except (ValueError, OverflowError, OSError):
        return None
    return value if 0 <= value < MAX_EPOCH else None


def text_or_none(value):
    return value if isinstance(value, str) and value else None


def pct(ordered, p):
    return ordered[max(0, -(-p * len(ordered) // 100) - 1)]  # nearest rank


def is_count(cell):
    return type(cell) is int and cell >= 0


def is_number(cell):
    return is_count(cell) or (type(cell) is float and math.isfinite(cell) and cell >= 0)


def valid(shape, rest):
    if shape == "fixed":
        return not rest
    if shape in ("count", "number", "stamp"):
        check = {"count": is_count, "number": is_number, "stamp": lambda c: type(c) is Stamp}[shape]
        return len(rest) == 1 and check(rest[0])
    if shape == "long":
        return len(rest) == 2 and type(rest[0]) is Stamp and is_number(rest[1])
    if not rest or not is_count(rest[0]):
        return False
    keys = STAT_KEYS + (TAIL_KEYS if shape == "stat" else ())
    if rest[0] == 0:
        return len(rest) == 1
    return (len(rest) == 1 + 2 * len(keys) and tuple(rest[1::2]) == keys
            and all(is_number(v) for v in rest[2::2]))


def cell_text(cell):
    if type(cell) is str:
        return cell
    if type(cell) is Stamp:
        return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(cell.epoch))
    return str(cell) if type(cell) is int else "%.1f" % cell


def render(rows):
    lines = []
    for row in rows:
        if type(row) is not list:
            raise GuardError()
        n = 0
        while n < len(row) and type(row[n]) is str:
            n += 1
        shape = SCHEMA.get(tuple(row[:n]))
        if shape is None or not valid(shape, row[n:]):
            raise GuardError()
        lines.append("\t".join(cell_text(cell) for cell in row) + "\n")
    return "".join(lines)


def stat(labels, values, tails):
    ordered = sorted(values)
    row = list(labels) + ["n", len(ordered)]
    if ordered:
        for p in PCTS:
            row += ["p%d" % p, pct(ordered, p)]
        row += ["max", ordered[-1]]
        for key, edge in tails:
            row += [key, len(ordered) - bisect.bisect_left(ordered, edge)]
    return row


def _quoted(cmd, i):
    quote, j, out = cmd[i], i + 1, []
    while j < len(cmd) and cmd[j] != quote:
        if quote == '"' and cmd[j] == "\\" and j + 1 < len(cmd):
            j += 1
        out.append(cmd[j])
        j += 1
    return ("".join(out), j + 1) if j < len(cmd) else (None, j)


def _delimiter(cmd, i):
    out = []
    while i < len(cmd) and cmd[i] not in " \t\r\n;|&()<>":
        if cmd[i] in "'\"":
            text, i = _quoted(cmd, i)
            if text is None:
                return None, i
            out.append(text)
        elif cmd[i] == "\\":
            out.append(cmd[i + 1:i + 2])
            i += 2
        else:
            out.append(cmd[i])
            i += 1
    return "".join(out), i


def _skip_body(cmd, i, delim, strip_tabs):
    while i < len(cmd):
        end = cmd.find("\n", i)
        end = len(cmd) if end < 0 else end
        line = cmd[i:end].rstrip("\r")
        i = end + 1
        if (line.lstrip("\t") if strip_tabs else line) == delim:
            break
    return i


def shell_segments(cmd):
    """Words of each simple command the shell would run. TRIPWIRE: quoted text and heredoc bodies are
    data, never commands; only unquoted ; & | ( ) and newlines split; an unterminated quote never runs."""
    segments, words, word, heredocs = [], [], None, []
    i, n = 0, len(cmd)
    while i < n:
        ch = cmd[i]
        if ch in "'\"":
            text, i = _quoted(cmd, i)
            if text is None:
                return segments
            word = (word or "") + text
        elif ch == "\\":
            if cmd[i + 1:i + 2] != "\n":
                word = (word or "") + cmd[i + 1:i + 2]
            i += 2
        elif cmd.startswith("<<", i) and not cmd.startswith("<<<", i):
            if word is not None:
                words.append(word)
                word = None
            strip = cmd.startswith("<<-", i)
            i += 3 if strip else 2
            while i < n and cmd[i] in " \t":
                i += 1
            delim, i = _delimiter(cmd, i)
            if delim is None:
                return segments
            if delim:
                heredocs.append((delim, strip))
        elif ch == "&" and (cmd.startswith(">", i + 1) or (word or "").endswith((">", "<"))):
            word = (word or "") + ch
            i += 1
        elif ch in " \t\r\n;|&()":
            if word is not None:
                words.append(word)
                word = None
            if ch not in " \t\r":
                if words:
                    segments.append(words)
                words = []
            i += 1
            if ch == "\n":
                for delim, strip in heredocs:
                    i = _skip_body(cmd, i, delim, strip)
                heredocs = []
        else:
            word = (word or "") + ch
            i += 1
    if word is not None:
        words.append(word)
    if words:
        segments.append(words)
    return segments


def runs_git_commit(cmd):
    """True when a command the shell runs is git's commit subcommand (after env assignments and options)."""
    if "git" not in cmd or "commit" not in cmd:
        return False
    for words in shell_segments(cmd):
        i, n = 0, len(words)
        while i < n and ENV_ASSIGN.match(words[i]):
            i += 1
        if i < n and words[i].replace("\\", "/").rsplit("/", 1)[-1].lower() in ("git", "git.exe"):
            i += 1
            while i < n and words[i].startswith("-"):
                i += 2 if words[i] in GIT_VALUE_OPTIONS else 1
            if i < n and words[i] == "commit":
                return True
    return False


def git_root():
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                             text=True, encoding="utf-8", errors="replace", timeout=60)
        if out.returncode == 0 and out.stdout.strip():
            return Path(out.stdout.strip())
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    return Path.cwd()


def locate_transcripts(repo):
    projects = Path.home() / ".claude" / "projects"
    munged = re.sub(r"[^A-Za-z0-9]", "-", str(repo.resolve()))
    exact = projects / munged
    if exact.is_dir():
        return exact
    if projects.is_dir():  # Windows drive-letter munge: the on-disk name may differ only by case
        for child in sorted(projects.iterdir()):
            if child.is_dir() and child.name.lower() == munged.lower():
                return child
    return None


def discover(dirs, counts):
    found = []
    for base in dirs:
        try:
            hits = [(p, "main") for p in base.glob("*.jsonl")]
            hits += [(p, "agent") for p in base.glob("*/subagents/agent-*.jsonl")]
            hits += [(p, "agent") for p in base.glob("*/subagents/workflows/wf_*/agent-*.jsonl")]
        except OSError:
            counts["unreadable"] += 1
            continue
        found += sorted((p, kind) for p, kind in hits if p.name != "journal.jsonl")
    return found


def open_input(path, counts):
    try:
        return open(path, "rb")
    except (OSError, ValueError):
        counts["unreadable"] += 1
        return None


def close_quietly(fh):
    try:
        fh.close()
    except OSError:
        pass


def read_objects(fh, counts):
    while True:
        raw = fh.readline(MAX_LINE_BYTES + 1)
        if not raw:
            return
        if len(raw) > MAX_LINE_BYTES and not raw.endswith(b"\n"):
            counts["oversized"] += 1
            while raw and not raw.endswith(b"\n"):
                raw = fh.readline(DRAIN_BYTES)
            continue
        raw = raw.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw.decode("utf-8", "replace"))
        except (ValueError, RecursionError):
            obj = None
        if isinstance(obj, dict):
            yield obj
        else:
            counts["malformed"] += 1


def scan_file(path, counts, consume):
    fh = open_input(path, counts)
    if fh is None:
        return
    try:
        for obj in read_objects(fh, counts):
            consume(obj)
    except OSError:
        counts["partial"] += 1
    finally:
        close_quietly(fh)


class Acc:
    def __init__(self, since, until):
        self.lo, self.hi = since, until
        self.c, self.files, self.orphans = Counter(), Counter(), Counter()
        self.s1, self.s6, self.s7 = defaultdict(list), defaultdict(list), defaultdict(list)

    def inw(self, t):
        return (self.lo is None or t >= self.lo) and (self.hi is None or t <= self.hi)


class Scan:
    """Per-transcript state. TRIPWIRE: keeps no input text; an open call is (start, class)."""

    def __init__(self, kind, acc):
        self.kind, self.acc = kind, acc
        self.opened, self.seen_use, self.seen_res = {}, set(), set()
        self.calls = self.lines = 0
        self.before = self.since_commit = None
        self.between = []
        self.prev_t = self.prev_type = self.prev_mid = None
        self.prev_in = self.pending = False

    def gap_class(self, typ, mid):
        if self.opened:
            return self.opened[next(reversed(self.opened))][1]
        if self.pending:
            return "model"
        # One response is written one content block per line; only the same message id is generation.
        if typ == "assistant" and self.prev_type == "assistant" and mid is not None and mid == self.prev_mid:
            return "model"
        return "idle"

    def feed(self, obj):
        acc = self.acc
        typ = obj.get("type")
        if typ not in ("assistant", "user") and not (typ == "system"
                                                     and obj.get("subtype") == "compact_boundary"):
            acc.c["skipped_type"] += 1
            return
        t = parse_ts(obj.get("timestamp"))
        if t is None:
            acc.c["untimed"] += 1
            return
        acc.c["timed"] += 1
        now_in = acc.inw(t)
        if now_in:
            acc.c["in_window"] += 1
            self.lines += 1
            if typ == "system":
                acc.c["compactions"] += 1
        msg = obj.get("message") if isinstance(obj.get("message"), dict) else {}
        mid = None
        if typ == "assistant":
            mid = text_or_none(msg.get("id")) or text_or_none(obj.get("requestId"))
        if self.prev_t is not None:
            if t < self.prev_t:
                acc.c["unordered"] += 1
            elif self.prev_in and now_in:
                gap = (round((t - self.prev_t) / 60, 3), self.prev_t)
                acc.s1[(self.gap_class(typ, mid), self.kind)].append(gap)
        self.prev_t, self.prev_in = t, now_in
        if typ == "system":
            return
        content = msg.get("content")
        blocks = [b for b in content if isinstance(b, dict)] if isinstance(content, list) else []
        if typ == "user":
            self.pending = True
            for block in blocks:
                if block.get("type") == "tool_result":
                    self.finish(block.get("tool_use_id"), t)
        else:
            self.pending = False
            for block in blocks:
                self.assistant_block(block, t, now_in)
        self.prev_type, self.prev_mid = typ, mid

    def finish(self, rid, t):
        if not isinstance(rid, str) or rid in self.seen_res:
            return
        self.seen_res.add(rid)
        call = self.opened.pop(rid, None)
        if call is None:
            self.acc.c["unmatched"] += 1
            return
        start, cls = call
        if t >= start and self.acc.inw(start) and self.acc.inw(t):
            self.acc.s6[(cls, self.kind)].append(round(t - start, 3))

    def assistant_block(self, block, t, now_in):
        btype = block.get("type")
        if btype == "advisor_tool_result":
            self.finish(block.get("tool_use_id"), t)
        elif btype == "server_tool_use" and block.get("name") == "advisor":
            tid = block.get("id")
            if isinstance(tid, str) and tid not in self.seen_use:
                self.seen_use.add(tid)
                self.opened[tid] = (t, "delegate")
        elif btype == "tool_use":
            self.use(block, t, now_in)

    def use(self, block, t, now_in):
        tid = block.get("id")
        if not isinstance(tid, str) or tid in self.seen_use:
            return
        self.seen_use.add(tid)
        name = text_or_none(block.get("name")) or ""
        tool_input = block.get("input") if isinstance(block.get("input"), dict) else {}
        commit = work = False
        if name in EDIT_TOOLS:
            work = True
        elif name in COMMAND_TOOLS:
            cmd = text_or_none(tool_input.get("command")) or ""
            commit = runs_git_commit(cmd)
            work = commit or ("<<" in cmd and (">" in cmd or TEE.search(cmd) is not None))
        cls = "command" if name in COMMAND_TOOLS else "delegate" if name in DELEGATE_TOOLS else "other"
        self.opened[tid] = (t, cls)
        if not now_in:
            return
        self.acc.c["tool_calls"] += 1
        self.calls += 1
        if work and self.before is None:
            self.before = self.calls - 1
        if commit:
            if self.since_commit is not None:
                self.between.append(self.since_commit)
            self.since_commit = 0
        elif self.since_commit is not None:
            self.since_commit += 1

    def end(self):
        for start, cls in self.opened.values():
            if self.acc.inw(start):
                self.acc.orphans[(cls, self.kind)] += 1
        self.opened.clear()
        if not self.lines:
            return
        work = "working" if self.before is not None else "readonly"
        s7 = self.acc.s7
        s7[("total", work, self.kind)].append(self.calls)
        s7[("before", work, self.kind)].append(self.calls if self.before is None else self.before)
        s7[("between", work, self.kind)].extend(self.between)


def scan_transcript(path, kind, acc):
    scan = Scan(kind, acc)
    scan_file(path, acc.c, scan.feed)
    scan.end()


def scan_audit(paths, acc):
    counts = Counter()
    stamps = {"all": [], "tool": []}

    def consume(row):
        t = parse_ts(row.get("ts"))
        if t is None:
            counts["untimed"] += 1
            return
        if not acc.inw(t):
            return
        counts["rows"] += 1
        stamps["all"].append(t)
        event = row.get("event")
        event = event if event in EVENTS else "other"
        decision = row.get("decision")
        counts[("event", event)] += 1
        counts[("decision", decision if decision in DECISIONS else "other")] += 1
        counts[("session_id", "present" if text_or_none(row.get("session_id")) else "null")] += 1
        if event in ("pre_tool_use", "post_tool_use"):
            stamps["tool"].append(t)
            name = text_or_none(row.get("tool_name")) or ""
            tool = "command" if name in COMMAND_TOOLS else "edit" if name in EDIT_TOOLS else "other"
            counts[("tool", tool)] += 1
    for path in paths:
        scan_file(path, counts, consume)
    return {"files": len(paths), "counts": counts, **stamps}


def gap_minutes(stamps):
    ordered = sorted(stamps)  # keeps same-second rows: a 0-minute gap is a real gap
    return [round((b - a) / 60, 3) for a, b in zip(ordered, ordered[1:])]


def long_rows(s1):
    hits = sorted(((m, start, cls, kind) for cls in LONG_CLASSES for kind in KINDS
                   for m, start in s1[(cls, kind)] if m >= LONG_GAP_LIST_MIN),
                  key=lambda hit: (-hit[0], hit[1], hit[2], hit[3]))
    rows = [["long", "S1", cls, kind, Stamp(start), m] for m, start, cls, kind in hits[:LONG_CAP]]
    if len(hits) > LONG_CAP:
        rows.append(["more", "S1", len(hits) - LONG_CAP])
    return rows


def build_rows(acc, audit):
    counts = audit["counts"]
    rows = [["histogram", edge, Stamp(value)] if value is not None else ["histogram", edge, "none"]
            for edge, value in (("since", acc.lo), ("until", acc.hi))]
    rows.append(["histogram", "percentile", "nearest_rank"])
    rows += [["input", "transcripts", kind, acc.files[kind]] for kind in KINDS]
    rows += [["input", "files", key, acc.c[key]] for key in FILE_KEYS]
    rows += [["input", "lines", key, acc.c[key]] for key in LINE_KEYS]
    rows += [["input", key, acc.c[key]] for key in ("compactions", "tool_calls")]
    rows.append(["input", "results", "unmatched", acc.c["unmatched"]])
    rows.append(["audit", "files", audit["files"]])
    rows += [["audit", key, counts[key]] for key in AUDIT_KEYS]
    if not acc.c["in_window"] and not counts["rows"]:
        return rows + [["histogram", "no-data"]], 3
    rows += [["audit", "event", e, counts[("event", e)]] for e in EVENTS + ("other",)]
    rows += [["audit", "decision", d, counts[("decision", d)]] for d in DECISIONS + ("other",)]
    rows += [["audit", "tool", t, counts[("tool", t)]] for t in ("command", "edit", "other")]
    rows += [["audit", "session_id", s, counts[("session_id", s)]] for s in ("null", "present")]
    for cls in CLASSES:
        for kind in KINDS:
            rows.append(stat(["S1", cls, kind, "min"], [m for m, _ in acc.s1[(cls, kind)]], MIN_TAILS))
    rows += long_rows(acc.s1)
    rows.append(stat(["S5", "raw", "all", "min"], gap_minutes(audit["all"]), MIN_TAILS))
    rows.append(stat(["S5", "raw", "tool", "min"], gap_minutes(audit["tool"]), MIN_TAILS))
    for cls in CALL_CLASSES:
        for kind in KINDS:
            rows.append(stat(["S6", cls, kind, "sec"], acc.s6[(cls, kind)], SEC_TAILS))
    rows += [["S6", "orphans", cls, kind, acc.orphans[(cls, kind)]]
             for cls in CALL_CLASSES for kind in KINDS]
    for measure in MEASURES:
        for work in WORK:
            for kind in KINDS:
                rows.append(stat(["S7", measure, work, kind, "calls"], acc.s7[(measure, work, kind)], ()))
    return rows, 0


def run(args, started):
    acc = Acc(args.since, args.until)
    repo = None
    if not args.transcripts or not args.audit:
        repo = Path(args.repo) if args.repo else git_root()
    if args.transcripts:
        dirs = [Path(d) for d in args.transcripts]
    else:
        located = locate_transcripts(repo)
        dirs = [located] if located else []
    if args.audit:
        audits = [Path(f) for f in args.audit]
    else:
        default = repo / "state" / "audit.log.jsonl"
        audits = [default] if default.is_file() else []
    for path, kind in discover(dirs, acc.c):
        acc.files[kind] += 1
        scan_transcript(path, kind, acc)
    rows, code = build_rows(acc, scan_audit(audits, acc))
    return [["histogram", "elapsed", round(time.monotonic() - started, 1)]] + rows, code


class Parser(argparse.ArgumentParser):
    def error(self, message):  # TRIPWIRE: argparse messages quote argument values; never print them
        raise UsageError(USAGE_DIAG)


def iso_arg(text):
    value = parse_ts(text, naive_utc=True)
    if value is None:
        raise ValueError()
    return value


def exists(path, want_dir):
    try:
        return Path(path).is_dir() if want_dir else Path(path).is_file()
    except (OSError, ValueError):
        return False


def parse_args(argv):
    parser = Parser(prog="reader.py", add_help=False)
    parser.add_argument("--histogram", action="store_true", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--repo")
    parser.add_argument("--audit", action="append", default=[])
    parser.add_argument("--transcripts", action="append", default=[])
    parser.add_argument("--since", type=iso_arg)
    parser.add_argument("--until", type=iso_arg)
    args = parser.parse_args(argv)
    if args.since is not None and args.until is not None and args.since > args.until:
        raise UsageError(USAGE_DIAG)
    if not all(exists(f, False) for f in args.audit) or not all(exists(d, True) for d in args.transcripts):
        raise UsageError(INPUT_DIAG)
    return args


def execute(argv, started):
    if "-h" in argv or "--help" in argv:
        return 0, HELP, ""
    args = parse_args(argv)
    try:
        out = open(args.out, "w", encoding="utf-8", newline="\n")
    except Exception:
        raise UsageError(OUT_DIAG) from None
    try:
        try:
            rows, code = run(args, started)
            text = render(rows)
        except GuardError:
            text, code = ABORT_GUARD, 4
        except (Exception, KeyboardInterrupt):
            text, code = ABORT_INTERNAL, 4
        out.write(text)
    finally:
        out.close()
    return code, text, ""


def emit(code, text, diag):
    try:
        if text:
            sys.stdout.write(text)
            sys.stdout.flush()
        if diag:
            sys.stderr.write(diag)
            sys.stderr.flush()
        return code
    except BaseException:
        try:
            sys.stderr.write(EMIT_DIAG)
            sys.stderr.flush()
        except BaseException:
            pass
        return 4


def main(argv=None):
    started = time.monotonic()
    try:
        code, text, diag = execute(sys.argv[1:] if argv is None else list(argv), started)
    except UsageError as exc:
        code, text, diag = 2, "", exc.args[0] if exc.args and exc.args[0] in DIAGS else USAGE_DIAG
    except BaseException:  # TRIPWIRE: the sanitizing boundary; only fixed text leaves this function
        code, text, diag = 4, ABORT_INTERNAL, ""
    return emit(code, text, diag)


if __name__ == "__main__":
    status = main()
    try:
        sys.stdout.flush()
        sys.stderr.flush()
    except BaseException:
        os._exit(status)  # a broken stream must not print a shutdown traceback
    sys.exit(status)
