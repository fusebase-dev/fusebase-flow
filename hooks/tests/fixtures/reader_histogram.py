#!/usr/bin/env python3
"""reader-histogram fixtures H1-H6, H10-H13. Usage: reader_histogram.py <root> <tmp>; exit = failure count.

All transcripts and audit rows are synthetic. Every run passes --transcripts and --audit, so the tool
never auto-locates real transcripts.
"""
import builtins
import contextlib
import io
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace

root, temp = (Path(arg) for arg in sys.argv[1:3])
sys.dont_write_bytecode = True
sys.path.insert(0, str(root / "hooks/local/lib"))
import reader  # noqa: E402

GROUP = "reader-histogram"
T0 = datetime(2026, 10, 10, 8, 0, 0, tzinfo=timezone.utc)
NUMBER = re.compile(r"[0-9]+(?:\.[0-9]+)?")
ISO = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
SECRETS = ("sk-planted-CMD-1f9a", "planted-PATH-77c3", "mcp__planted_secret__x", "planted-CWD-5b21",
           "planted-SID-0e44", "planted-EVENT-3c1d", "planted-DEC-aa02")
failed = 0


def check(name, ok, reason="assertion failed"):
    global failed
    if ok:
        print("PASS: %s %s" % (GROUP, name))
    else:
        failed += 1
        print("FAIL: %s %s: %s" % (GROUP, name, reason))


def stamp(minutes, ms=True):
    moment = T0 + timedelta(minutes=minutes)
    return moment.isoformat(timespec="milliseconds" if ms else "seconds").replace("+00:00", "Z")


def prompt(m, text="go", **extra):
    return dict({"type": "user", "timestamp": stamp(m),
                 "message": {"role": "user", "content": text}}, **extra)


def say(m, *blocks, mid="m0", **extra):
    content = list(blocks) or [{"type": "text", "text": "ok"}]
    return dict({"type": "assistant", "timestamp": stamp(m),
                 "message": {"id": mid, "role": "assistant", "content": content}}, **extra)


def use(tid, name, **tool_input):
    return {"type": "tool_use", "id": tid, "name": name, "input": tool_input}


def result(m, tid, **extra):
    return dict({"type": "user", "timestamp": stamp(m), "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": tid, "content": "ok"}]}}, **extra)


def call(m, done, tid, name, **tool_input):
    return [say(m, use(tid, name, **tool_input), mid="m-" + tid), result(done, tid)]


def reads(start, count, prefix):
    return [line for i in range(count)
            for line in call(start + i, start + i + 0.1, "%s%d" % (prefix, i), "Read",
                             file_path="f%d.txt" % i)]


def bash(start, prefix, commands):
    return [line for i, cmd in enumerate(commands)
            for line in call(start + i, start + i + 0.1, "%s%d" % (prefix, i), "Bash", command=cmd)]


def audit_row(m, event="pre_tool_use", tool="Bash", decision="allow", session=None, **extra):
    row = {"ts": stamp(m, ms=False), "event_id": "e%s" % m, "event": event, "decision": decision,
           "reason": "", "rule_id": None, "session_id": session, "host_tool": None}
    if tool:
        row["tool_name"] = tool
    row.update(extra)
    return row


def jsonl(path, objs, raw_lines=()):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "".join(json.dumps(obj) + "\n" for obj in objs) + "".join(line + "\n" for line in raw_lines)
    path.write_text(text, encoding="utf-8", newline="\n")
    return path


def case_dir(name):
    path = temp / name
    (path / "t").mkdir(parents=True, exist_ok=True)
    audit = path / "audit.jsonl"
    if not audit.exists():
        audit.write_text("", encoding="utf-8")
    return path


def histogram(path, *extra, transcripts=None, audit=None):
    out = path / "out.txt"
    argv = ["--histogram", "--out", str(out), "--transcripts", str(transcripts or path / "t"),
            "--audit", str(audit or path / "audit.jsonl"), *extra]
    return invoke(argv, out)


def invoke(argv, out=None, stdout=None, stderr=None):
    so, se = stdout or io.StringIO(), stderr or io.StringIO()
    with contextlib.redirect_stdout(so), contextlib.redirect_stderr(se):
        code = reader.main(argv)
    stdout_text = so.getvalue() if isinstance(so, io.StringIO) else ""
    text = out.read_text(encoding="utf-8") if out is not None and out.exists() else None
    return SimpleNamespace(code=code, stdout=stdout_text,
                           stderr=se.getvalue() if isinstance(se, io.StringIO) else "", file=text,
                           rows=[line.split("\t") for line in stdout_text.splitlines()])


@contextlib.contextmanager
def patched(name, value):
    missing = object()
    saved = reader.__dict__.get(name, missing)
    setattr(reader, name, value)
    try:
        yield
    finally:
        if saved is missing:
            delattr(reader, name)
        else:
            setattr(reader, name, saved)


def row(rows, *labels):
    for fields in rows:
        if fields[:len(labels)] == list(labels):
            return fields
    return None


def value(rows, *labels):
    fields = row(rows, *labels)
    return fields[len(labels)] if fields is not None and len(fields) > len(labels) else None


def pairs(rows, *labels):
    fields = row(rows, *labels)
    if fields is None or "n" not in fields[len(labels):]:
        return {}
    i = fields.index("n", len(labels))
    return dict(zip(fields[i::2], fields[i + 1::2]))


def expect(got, want):
    bad = {k: (got.get(k), v) for k, v in want.items() if got.get(k) != v}
    return not bad, "got/want %s" % bad


def scan(path, kind="agent"):
    acc = reader.Acc(None, None)
    reader.scan_transcript(path, kind, acc)
    return acc


def leaks(*texts):
    return [s for s in SECRETS + ("planted", "mcp__", "Traceback") for t in texts if t and s in t]


class Broken(io.StringIO):
    def __init__(self, fail_write=True):
        super().__init__()
        self.fail_write = fail_write

    def write(self, text):
        if self.fail_write:
            raise OSError("stream write failed " + SECRETS[1])
        return super().write(text)

    def flush(self):
        raise OSError("stream flush failed " + SECRETS[1])


class FakeOut:
    def __init__(self, fail):
        self.fail = fail

    def write(self, text):
        if self.fail == "write":
            raise OSError("write failed " + SECRETS[1])
        return len(text)

    def close(self):
        if self.fail == "close":
            raise OSError("close failed " + SECRETS[1])


class Flaky:
    def __init__(self, fh):
        self.fh, self.reads = fh, 0

    def readline(self, size=-1):
        self.reads += 1
        if self.reads > 1:
            raise OSError("read failed " + SECRETS[1])
        return self.fh.readline(size)

    def close(self):
        self.fh.close()


def fake_open(out_behaviour=None, input_behaviour=None, match=""):
    def opener(path, mode="r", *args, **kwargs):
        if "w" in mode and out_behaviour is not None:
            if out_behaviour == "raise":
                raise ValueError("cannot open " + SECRETS[1])
            return FakeOut(out_behaviour)
        if "b" in mode and input_behaviour is not None and match in str(path):
            if input_behaviour == "deny":
                raise PermissionError("locked " + SECRETS[1])
            return Flaky(builtins.open(path, mode, *args, **kwargs))
        return builtins.open(path, mode, *args, **kwargs)
    return opener


def h1():
    d = case_dir("h1")
    jsonl(d / "audit.jsonl", [audit_row(0), audit_row(0), audit_row(2), audit_row(12, event="stop", tool=None),
                              audit_row(57, event="post_tool_use", tool="Edit")])
    r = histogram(d)
    check("H1 exit 0 on an audit file only", r.code == 0, "exit %s" % r.code)
    ok, why = expect(pairs(r.rows, "S5", "raw", "all", "min"), {
        "n": "4", "p50": "2.0", "max": "45.0", "ge1m": "3", "ge2m": "3", "ge5m": "2", "ge10m": "2",
        "ge15m": "1", "ge20m": "1", "ge25m": "1", "ge30m": "1", "ge45m": "1", "ge60m": "0", "ge480m": "0"})
    check("H1 S5 all-row gaps 0, 2, 10, 45 give the tail counts (same-second row kept)", ok, why)
    ok, why = expect(pairs(r.rows, "S5", "raw", "tool", "min"), {"n": "3", "p50": "2.0", "max": "55.0"})
    check("H1 S5 tool rows exclude the stop row", ok, why)
    check("H1 null session_id counted, not fatal",
          value(r.rows, "audit", "session_id", "null") == "5"
          and value(r.rows, "audit", "session_id", "present") == "0", r.stdout)
    check("H1 event and tool vocabulary counts", value(r.rows, "audit", "event", "pre_tool_use") == "3"
          and value(r.rows, "audit", "event", "stop") == "1"
          and value(r.rows, "audit", "tool", "command") == "3"
          and value(r.rows, "audit", "tool", "edit") == "1", r.stdout)
    b = case_dir("h1b")
    jsonl(b / "audit.jsonl", [audit_row(0), audit_row(0), audit_row(2)])
    ok, why = expect(pairs(histogram(b).rows, "S5", "raw", "all", "min"), {"n": "2", "p50": "0.0", "max": "2.0"})
    check("H1 rows at 08:00:00, 08:00:00, 08:02:00 give gaps 0 and 2", ok, why)


def h2():
    d = case_dir("h2")
    jsonl(d / "t/s1.jsonl", [
        prompt(0), say(0.5, use("b1", "Bash", command="sleep 2400"), mid="m1"), result(40.5, "b1"),
        say(43.5, mid="m2"), prompt(103.5), say(104, mid="m3")])
    jsonl(d / "t/s1/subagents/agent-a.jsonl", [
        prompt(0), say(1, {"type": "thinking", "thinking": "plan"}, mid="a1"),
        say(3, use("r1", "Read", file_path="x.txt"), mid="a1"), result(3.1, "r1"),
        say(3.2, use("k1", "Task", prompt="go"), mid="a2"), result(28.2, "k1"), say(28.3, mid="a3")])
    r = histogram(d)
    check("H2 exit 0", r.code == 0, "exit %s" % r.code)
    ok, why = expect(pairs(r.rows, "S1", "command", "main", "min"), {"n": "1", "max": "40.0"})
    check("H2 Bash open 40 min is S1 command 40", ok, why)
    ok, why = expect(pairs(r.rows, "S1", "idle", "main", "min"), {"n": "1", "max": "60.0"})
    check("H2 60-min end-of-turn wait is S1 idle", ok, why)
    ok, why = expect(pairs(r.rows, "S1", "model", "main", "min"), {"n": "3", "max": "3.0"})
    check("H2 3-min model wait is S1 model", ok, why)
    check("H2 long list has the command gap and no idle gap",
          ["long", "S1", "command", "main", "2026-10-10T08:00:30Z", "40.0"] in r.rows
          and not any(f[:3] == ["long", "S1", "idle"] for f in r.rows), r.stdout)
    ok, why = expect(pairs(r.rows, "S1", "model", "agent", "min"), {"n": "4", "max": "2.0"})
    check("H2 blocks of the same response (same message id) are model, not idle",
          ok and pairs(r.rows, "S1", "idle", "agent", "min").get("n") == "0", why)
    ok, why = expect(pairs(r.rows, "S1", "delegate", "agent", "min"), {"n": "1", "max": "25.0"})
    check("H2 Task open 25 min is S1 delegate, listed long",
          ok and ["long", "S1", "delegate", "agent", "2026-10-10T08:03:12Z", "25.0"] in r.rows, why)
    ok, why = expect(pairs(r.rows, "S6", "delegate", "agent", "sec"), {"n": "1", "max": "1500.0"})
    check("H2 S6 spans by class", ok and pairs(r.rows, "S6", "other", "agent", "sec").get("max") == "6.0"
          and pairs(r.rows, "S6", "command", "main", "sec").get("max") == "2400.0", why)
    b = case_dir("h2b")
    jsonl(b / "t/s1.jsonl", [prompt(0), say(1, mid="x1"), say(61, mid="x2")])
    r = histogram(b)
    check("H2 two different responses 60 min apart are idle, not model",
          pairs(r.rows, "S1", "idle", "main", "min").get("max") == "60.0"
          and pairs(r.rows, "S1", "model", "main", "min").get("n") == "1"
          and not any(f[:3] == ["long", "S1", "model"] for f in r.rows), r.stdout)
    c = case_dir("h2c")
    lines, t, lengths = [prompt(0)], 0.0, []
    for i in range(40):
        lines += call(t + 0.1, t + 0.1 + 20 + i, "b%d" % i, "Bash", command="sleep 1")
        lengths.append(20.0 + i)
        t += 20.3 + i
    jsonl(c / "t/s1.jsonl", lines)
    lines, t = [], 0.0
    for j in range(30):
        lines += [prompt(t), say(t + 20.5 + j, mid="a%d" % j)]
        lengths.append(20.5 + j)
        t += 20.6 + j
    jsonl(c / "t/s1/subagents/agent-a.jsonl", lines)
    r = histogram(c)
    longs = [f for f in r.rows if f[0] == "long"]
    want = ["%.1f" % m for m in sorted(lengths, reverse=True)[:50]]
    check("H2 long list is capped at 50 per series with one accurate more count",
          [f[5] for f in longs] == want and [f for f in r.rows if f[0] == "more"] == [["more", "S1", "20"]]
          and {tuple(f[2:4]) for f in longs} == {("command", "main"), ("model", "agent")},
          "%d long rows" % len(longs))


def h3():
    d = case_dir("h3")
    jsonl(d / "t/s1.jsonl", [prompt(0), say(1)])
    jsonl(d / "t/s1/subagents/agent-a.jsonl", [prompt(0), say(2)])
    jsonl(d / "t/s1/subagents/workflows/wf_x/agent-b.jsonl", [prompt(0), say(3)])
    noise = [prompt(i) for i in range(5)]
    jsonl(d / "t/journal.jsonl", noise)
    jsonl(d / "t/s1/subagents/workflows/wf_x/journal.jsonl", noise)
    jsonl(d / "t/s1/subagents/journal.jsonl", noise)
    jsonl(d / "audit.jsonl", [audit_row(0)])
    r = histogram(d)
    check("H3 main, subagent and workflow agent files are read",
          value(r.rows, "input", "transcripts", "main") == "1"
          and value(r.rows, "input", "transcripts", "agent") == "2", r.stdout)
    check("H3 journal.jsonl is skipped", value(r.rows, "input", "lines", "timed") == "6"
          and pairs(r.rows, "S1", "model", "agent", "min").get("max") == "3.0", r.stdout)
    (d / "t/s2.jsonl").mkdir(exist_ok=True)
    r = histogram(d)
    check("H3 an unreadable transcript is skipped and counted", r.code == 0
          and value(r.rows, "input", "files", "unreadable") == "1"
          and value(r.rows, "input", "lines", "timed") == "6", r.stdout)
    with patched("open", fake_open(input_behaviour="flaky", match="agent-a")):
        r = histogram(d)
    check("H3 a read failure mid-file keeps the lines read and is counted partial", r.code == 0
          and value(r.rows, "input", "files", "partial") == "1"
          and value(r.rows, "input", "lines", "timed") == "5" and not leaks(r.stdout, r.stderr), r.stdout)
    with patched("open", fake_open(input_behaviour="deny", match="audit.jsonl")):
        r = histogram(d)
    check("H3 a locked audit file is skipped and counted", r.code == 0
          and value(r.rows, "audit", "unreadable") == "1" and value(r.rows, "audit", "rows") == "0"
          and not leaks(r.stdout, r.stderr), r.stdout)


def h4():
    d = case_dir("h4")
    dup = say(1, use("x", "Bash", command="ls"), mid="m1")
    jsonl(d / "t/s1.jsonl", [prompt(0), dup, dup, result(2, "x"), result(2, "x"), say(3, mid="m2")])
    r = histogram(d)
    check("H4 repeated tool_use and tool_result count once",
          pairs(r.rows, "S6", "command", "main", "sec").get("n") == "1"
          and pairs(r.rows, "S7", "total", "readonly", "main", "calls").get("max") == "1"
          and value(r.rows, "input", "tool_calls") == "1"
          and value(r.rows, "input", "results", "unmatched") == "0", r.stdout)
    jsonl(d / "t/s1/subagents/agent-x.jsonl", [
        prompt(0), say(0, use("bash1", "Bash", command="sleep 2400"), mid="m1"),
        say(1, use("read1", "Read", file_path="a.txt"), mid="m2"), result(2, "read1"),
        result(40, "bash1"), say(41, mid="m3")])
    jsonl(d / "t/s1/subagents/agent-o.jsonl", [
        prompt(0), say(1, use("o1", "Bash", command="sleep 9"), mid="m1")])
    r = histogram(d)
    ok, why = expect(pairs(r.rows, "S6", "command", "agent", "sec"), {"n": "1", "max": "2400.0"})
    check("H4 a call stays open across another message and closes on its own result",
          ok and pairs(r.rows, "S1", "command", "agent", "min").get("max") == "38.0"
          and value(r.rows, "input", "results", "unmatched") == "0", why)
    check("H4 a call with no result is an orphan at transcript end",
          value(r.rows, "S6", "orphans", "command", "agent") == "1", r.stdout)


def h5():
    d = case_dir("h5")
    base = d / "t/s1/subagents"
    a = jsonl(base / "agent-a.jsonl", [prompt(0)] + reads(1, 12, "a") + call(20, 20.1, "e", "Edit",
                                                                            file_path="a.txt"))
    b = jsonl(base / "agent-b.jsonl", [prompt(0)] + reads(1, 3, "b")
              + call(5, 5.1, "c", "Bash", command="git -C repo commit -m step"))
    c = jsonl(base / "agent-c.jsonl", [prompt(0)] + reads(1, 2, "c")
              + call(5, 5.1, "h", "Bash", command="cat > f.txt <<'EOF'\nx\nEOF"))
    e = jsonl(base / "agent-e.jsonl", [prompt(0)] + reads(1, 4, "e"))
    g = jsonl(base / "agent-g.jsonl", [prompt(0)] + reads(1, 2, "g") + bash(
        5, "n", ["git show --format=commit HEAD", "git log --grep=commit", "echo git commit"]))
    check("H5 12 Reads then an Edit gives 12", scan(a).s7[("before", "working", "agent")] == [12])
    check("H5 git commit counts as work", scan(b).s7[("before", "working", "agent")] == [3])
    check("H5 cat > f <<EOF counts as work", scan(c).s7[("before", "working", "agent")] == [2])
    acc = scan(e)
    check("H5 an agent with no work call is read-only",
          acc.s7[("before", "readonly", "agent")] == [4] and acc.s7[("total", "readonly", "agent")] == [4]
          and not acc.s7[("before", "working", "agent")])
    acc = scan(g)
    check("H5 git show/log mentioning commit and echo git commit are not work",
          acc.s7[("total", "readonly", "agent")] == [5] and not acc.s7[("before", "working", "agent")])
    k = jsonl(base / "agent-k.jsonl", [prompt(0)] + reads(1, 2, "k") + call(
        5, 5.1, "k9", "Bash", command="cat <<'EOF'\ngit commit -m example\nEOF"))
    acc = scan(k)
    check("H5 a heredoc-only transcript whose body says git commit stays read-only",
          acc.s7[("total", "readonly", "agent")] == [3] and not acc.s7[("before", "working", "agent")])
    q = jsonl(base / "agent-q.jsonl", [prompt(0)] + reads(1, 1, "q") + call(
        5, 5.1, "q9", "Bash", command="echo ';' git commit"))
    acc = scan(q)
    check("H5 a transcript running echo ';' git commit stays read-only",
          acc.s7[("total", "readonly", "agent")] == [2] and not acc.s7[("before", "working", "agent")])
    positive = ["git commit -m x", "git -C repo commit -m x", "git --no-pager -c user.name=a commit",
                "cd x && git commit -am y", "GIT_AUTHOR_DATE=now git commit", '& git commit -m "a b"',
                'git -C "C:/a b" --git-dir=.git commit', "/usr/bin/git commit",
                "git commit -F - <<'EOF'\nfix: x; y && z\nEOF", "git status; git commit -F - <<'EOF'\nmsg\nEOF",
                "cat <<'EOF' > m.txt\ngit log\nEOF\ngit commit -F m.txt", "cat <<-EOF\n\tbody\n\tEOF\ngit commit -m x",
                "git add a && git commit -m 'x; y'", "git commit -m x 2>&1 | tail -1"]
    negative = ["git show --format=commit", "git log --grep=commit", "echo git commit", "git commit-tree x",
                'echo "x; git commit"', "grep -r 'git commit' docs", "git log | grep commit",
                "git -c commit=1 status", "cat <<'EOF'\ngit commit -m example\nEOF", "echo ';' git commit",
                'cat <<"EOF"\ngit commit\nEOF', "cat <<EOF\ngit commit\nEOF", "cat <<-EOF\n\tgit commit -m x\n\tEOF",
                "echo '&&' git commit", 'echo "|" git commit', "echo \\; git commit",
                'echo "unterminated git commit', 'git commit -m "unterminated', 'echo "unbalanced\ngit commit -m x']
    for cmd in positive:
        check("H5 runs git commit: %r" % cmd, reader.runs_git_commit(cmd) is True)
    for cmd in negative:
        check("H5 does not run git commit: %r" % cmd, reader.runs_git_commit(cmd) is False)
    r = histogram(d)
    ok, why = expect(pairs(r.rows, "S7", "before", "working", "agent", "calls"),
                     {"n": "3", "p50": "3", "max": "12"})
    check("H5 S7 before rows", ok and pairs(r.rows, "S7", "total", "readonly", "agent", "calls")
          .get("n") == "4", why)


def h6():
    d = case_dir("h6")
    lines = [prompt(0)] + call(1, 1.1, "c1", "Bash", command="git commit -m t")
    lines += reads(2, 4, "x") + call(7, 7.1, "x9", "Bash", command="git log --grep=commit")
    lines += call(8, 8.1, "c2", "Bash", command="git -C repo --no-pager commit -m t")
    lines += reads(9, 6, "y") + call(16, 16.1, "y9", "Bash", command="git show --format=commit")
    lines += call(17, 17.1, "c3", "Bash", command="cd repo && git commit -am t")
    lines += reads(18, 2, "z") + call(20.5, 20.6, "z9", "Bash", command="echo git commit")
    lines += call(22, 22.1, "c4", "Bash", command="git commit -m t")
    path = jsonl(d / "t/s1.jsonl", lines)
    check("H6 calls between commits are 5, 7, 3 (commit-mentioning commands do not split)",
          scan(path, "main").s7[("between", "working", "main")] == [5, 7, 3])
    cases = (("heredoc", "cat <<'EOF'\ngit commit -m example\nEOF"), ("quoted ;", "echo ';' git commit"))
    for number, (name, data) in enumerate(cases):
        lines = [prompt(0)] + call(1, 1.1, "c1", "Bash", command="git commit -m t") + reads(2, 1, "r")
        lines += call(3, 3.1, "h", "Bash", command=data) + reads(4, 1, "s")
        lines += call(5, 5.1, "c2", "Bash", command="git commit -m t")
        acc = scan(jsonl(d / "extra" / ("between-%d.jsonl" % number), lines), "main")
        check("H6 commit, Read, %s, Read, commit gives between [3]" % name,
              acc.s7[("between", "working", "main")] == [3], "got %r" % acc.s7[("between", "working", "main")])
    r = histogram(d)
    ok, why = expect(pairs(r.rows, "S7", "between", "working", "main", "calls"), {
        "n": "3", "p50": "5", "p75": "7", "p90": "7", "p95": "7", "p99": "7", "max": "7"})
    check("H6 S7 between percentiles (nearest rank)", ok, why)
    hundred = list(range(1, 101))
    check("H6 nearest-rank percentile table",
          [reader.pct(hundred, p) for p in (50, 75, 90, 95, 99)] == [50, 75, 90, 95, 99]
          and reader.pct([4], 99) == 4 and reader.pct([3, 5, 7], 50) == 5
          and reader.pct(list(range(1, 21)), 95) == 19)
    check("H6 percentile method is printed", ["histogram", "percentile", "nearest_rank"] in r.rows)


def h10():
    cmd, path, tool, cwd, sid, event, decision = SECRETS
    d = case_dir("h10")
    tdir = d / ("t-" + cwd)
    extra = {"cwd": "C:/" + cwd + "/repo", "sessionId": sid}
    lines = [prompt(0, text="token " + cmd, **extra),
             say(1, use("s1", "Bash", command="curl -H 'Authorization: Bearer %s' https://x" % cmd),
                 mid="m1", **extra), result(2, "s1", **extra),
             say(3, use("s2", "Edit", file_path="C:/" + cwd + "/state/" + path + ".txt"), mid="m2",
                 **extra), result(4, "s2", **extra),
             say(5, use("s3", tool, query=cmd), mid="m3", **extra), result(40, "s3", **extra),
             dict(say(41, mid="m4"), type="planted-" + tool)]
    jsonl(tdir / (sid + ".jsonl"), lines, raw_lines=['{"broken": "%s"' % cmd])
    jsonl(tdir / sid / "subagents" / ("agent-" + sid + ".jsonl"), lines)
    audit = jsonl(d / ("audit-" + sid + ".jsonl"), [
        audit_row(0, session=sid, tool=tool, reason=cmd, path=path, cwd=cwd),
        audit_row(2, event=event, decision=decision, session=sid, tool="Bash", command=cmd),
        audit_row(30, session=sid, tool=tool, cmd_sha256=cmd, tool_use_id=sid, agent_id=sid)],
        raw_lines=["not json " + cmd])
    out = d / ("out-" + sid + ".txt")
    script = str(root / "hooks/local/lib/reader.py")
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")

    def cli(*argv):
        return subprocess.run([sys.executable, script, *argv], cwd=str(temp), env=env, capture_output=True,
                              text=True, encoding="utf-8", timeout=300)
    proc = cli("--histogram", "--out", str(out), "--transcripts", str(tdir), "--audit", str(audit))
    written = out.read_text(encoding="utf-8") if out.exists() else ""
    check("H10 planted run exits 0 with data", proc.returncode == 0 and "S1\tcommand" in proc.stdout,
          "exit %s" % proc.returncode)
    bad = leaks(proc.stdout, proc.stderr, written)
    check("H10 no planted secret reaches stdout, stderr or --out", not bad, "leaked %s" % bad)
    fields = [f for line in proc.stdout.splitlines() for f in line.split("\t")]
    odd = [f for f in fields if not (f in reader.VOCAB or NUMBER.fullmatch(f) or ISO.fullmatch(f))]
    check("H10 every output field is VOCAB, a number or an ISO second", fields and not odd,
          "%d odd fields" % len(odd))
    check("H10 --out equals stdout", written == proc.stdout)
    for name, argv in (("unknown option", ["--histogram", "--out", str(d / "x.txt"), "--planted-secret=" + cmd]),
                       ("value on a flag", ["--histogram=" + cmd, "--out", str(d / "x.txt")])):
        proc = cli(*argv)
        check("H10 CLI usage error (%s) prints a fixed diagnostic, no argument value" % name,
              proc.returncode == 2 and proc.stdout == "" and proc.stderr == reader.USAGE_DIAG
              and not leaks(proc.stderr), "exit %s" % proc.returncode)
    child = subprocess.Popen([sys.executable, script, "--histogram", "--out", str(d / "z.txt"), "--transcripts",
                              str(tdir), "--audit", str(audit)], cwd=str(temp), env=env,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    child.stdout.close()
    err = child.stderr.read().decode("utf-8", "replace").replace("\r\n", "\n")
    code = child.wait(timeout=300)
    check("H10 a closed stdout pipe exits 4 with only the fixed diagnostic, no traceback",
          code == 4 and err == reader.EMIT_DIAG and not leaks(err), "exit %s, %d stderr chars" % (code, len(err)))
    original = reader.build_rows
    breaches = {
        "vocabulary": ["S1", tool, 1],
        "digit-only string": ["input", "tool_calls", "12345678901234567890"],
        "ISO-shaped string": ["long", "S1", "command", "main", "2026-10-10T08:48:31Z", 25.0],
        "timestamp outside a timestamp column": ["input", "tool_calls", reader.Stamp(0.0)],
        "unknown row schema": ["S1", 5],
        "bool as a number": ["input", "tool_calls", True],
        "NaN": ["histogram", "elapsed", float("nan")],
        "missing stat value": ["S7", "total", "working", "main", "calls", "n", 1, "p50", 1],
    }
    for name, bad_row in breaches.items():
        def breached(acc, audit_data, bad_row=bad_row):
            rows, code = original(acc, audit_data)
            return rows + [bad_row], code
        with patched("build_rows", breached):
            r = histogram(d, transcripts=tdir, audit=audit)
        check("H10 forced breach (%s) exits 4 with only aborted guard" % name,
              r.code == 4 and r.stdout == reader.ABORT_GUARD == "histogram\taborted\tguard\n"
              and r.file == r.stdout and not leaks(r.stdout, r.stderr, r.file), "exit %s" % r.code)

    def broken(*args):
        raise RuntimeError("cannot parse " + cmd + " at " + path)
    with patched("scan_audit", broken):
        r = histogram(d, transcripts=tdir, audit=audit)
    check("H10 internal error in run exits 4 with only aborted internal, no message",
          r.code == 4 and r.stdout == "histogram\taborted\tinternal\n" and r.file == r.stdout
          and not leaks(r.stdout, r.stderr, r.file), "exit %s" % r.code)
    with patched("parse_args", broken):
        r = histogram(d, transcripts=tdir, audit=audit)
    check("H10 argument parsing failure exits 4 with no message", r.code == 4
          and r.stdout == reader.ABORT_INTERNAL and r.stderr == "" and not leaks(r.stdout, r.stderr),
          "exit %s" % r.code)
    with patched("open", fake_open(out_behaviour="raise")):
        r = histogram(d, transcripts=tdir, audit=audit)
    check("H10 --out open failure exits 2 with a fixed diagnostic", r.code == 2 and r.stdout == ""
          and r.stderr == reader.OUT_DIAG and not leaks(r.stdout, r.stderr), "exit %s" % r.code)
    for failure in ("write", "close"):
        with patched("open", fake_open(out_behaviour=failure)):
            r = histogram(d, transcripts=tdir, audit=audit)
        check("H10 --out %s failure exits 4 with no message" % failure, r.code == 4
              and r.stdout == reader.ABORT_INTERNAL and not leaks(r.stdout, r.stderr), "exit %s" % r.code)
    argv = ["--histogram", "--out", str(d / "y.txt"), "--transcripts", str(tdir), "--audit", str(audit)]
    for name, so in (("write", Broken()), ("flush", Broken(fail_write=False))):
        r = invoke(argv, stdout=so)
        check("H10 stdout %s failure exits 4 with a fixed diagnostic" % name, r.code == 4
              and r.stderr == reader.EMIT_DIAG and not leaks(r.stderr), "exit %s" % r.code)
    try:
        r = invoke(argv, stdout=Broken(), stderr=Broken())
        ok = r.code == 4
    except BaseException:
        ok = False
    check("H10 stdout and stderr both failing exits 4 without raising", ok)


def h11():
    d = case_dir("h11")
    r = histogram(d)
    check("H11 no input exits 3 with no-data", r.code == 3 and r.rows[-1] == ["histogram", "no-data"]
          and r.file == r.stdout, "exit %s" % r.code)
    w = case_dir("h11w")
    jsonl(w / "t/s1.jsonl", [prompt(0), say(1)])
    jsonl(w / "audit.jsonl", [audit_row(0)])
    r = histogram(w, "--since", "2026-10-11T00:00:00Z")
    check("H11 a window with no rows exits 3 with no-data",
          r.code == 3 and r.rows[-1] == ["histogram", "no-data"], "exit %s" % r.code)
    m = case_dir("h11m")
    jsonl(m / "t/s1.jsonl", [], raw_lines=["{not json", "[1, 2]"])
    jsonl(m / "audit.jsonl", [], raw_lines=["garbage"])
    r = histogram(m)
    check("H11 malformed lines are counted", r.code == 3
          and value(r.rows, "input", "lines", "malformed") == "2"
          and value(r.rows, "audit", "malformed") == "1", r.stdout)
    jsonl(m / "t/s1.jsonl", [prompt(0), say(1)], raw_lines=["{not json"])
    r = histogram(m)
    check("H11 malformed lines are counted beside data", r.code == 0
          and value(r.rows, "input", "lines", "malformed") == "1", r.stdout)
    o = case_dir("h11o")
    exact = say(2, mid="pad")
    exact["pad"] = ""
    exact["pad"] = "x" * (1024 - len(json.dumps(exact)))
    over = dict(exact, pad=exact["pad"] + "y")
    jsonl(o / "t/s1.jsonl", [prompt(0), {"type": "user", "pad": "z" * 5000}, exact, over, say(3, mid="end")])
    jsonl(o / "audit.jsonl", [{"ts": stamp(0, ms=False), "pad": "z" * 2000}, audit_row(1)])
    with patched("MAX_LINE_BYTES", 1024):
        r = histogram(o)
    check("H11 lines over MAX_LINE_BYTES are drained, skipped and counted; a line at the cap is read",
          r.code == 0 and len(json.dumps(exact)) == 1024 and value(r.rows, "input", "lines", "oversized") == "2"
          and value(r.rows, "input", "lines", "timed") == "3" and value(r.rows, "audit", "oversized") == "1"
          and value(r.rows, "audit", "rows") == "1", r.stdout)
    out = str(d / "usage.txt")
    secret = SECRETS[0]
    usage = {
        "missing --out": (["--histogram", "--transcripts", str(d / "t")], reader.USAGE_DIAG),
        "missing --histogram": (["--out", out], reader.USAGE_DIAG),
        "unknown option with a value": (["--histogram", "--out", out, "--planted-secret=" + secret],
                                        reader.USAGE_DIAG),
        "value given to --histogram": (["--histogram=" + secret, "--out", out], reader.USAGE_DIAG),
        "bad --since": (["--histogram", "--out", out, "--since", secret], reader.USAGE_DIAG),
        "--since after --until": (["--histogram", "--out", out, "--since", "2026-10-11T00:00:00Z",
                                   "--until", "2026-10-10T00:00:00Z"], reader.USAGE_DIAG),
        "missing --transcripts dir": (["--histogram", "--out", out, "--transcripts", str(d / secret)],
                                      reader.INPUT_DIAG),
        "missing --audit file": (["--histogram", "--out", out, "--audit", str(d / (secret + ".jsonl"))],
                                 reader.INPUT_DIAG),
        "unwritable --out": (["--histogram", "--out", str(d / secret / "x.txt"), "--transcripts", str(d / "t"),
                              "--audit", str(d / "audit.jsonl")], reader.OUT_DIAG),
    }
    for name, (argv, diag) in usage.items():
        r = invoke(argv)
        check("H11 usage exit 2, fixed stderr: " + name, r.code == 2 and r.stdout == "" and r.stderr == diag
              and not leaks(r.stderr), "exit %s" % r.code)
    r = invoke(["--help"])
    check("H11 --help exits 0 with the static help text", r.code == 0 and r.stdout == reader.HELP
          and r.stderr == "", "exit %s" % r.code)


def h12():
    want = datetime(2026, 10, 10, 8, 48, 31, 123000, tzinfo=timezone.utc).timestamp()
    got = reader.parse_ts("2026-10-10T08:48:31.123Z")
    check("H12 Z timestamp with milliseconds parses", got is not None and abs(got - want) < 1e-6)

    class Py310(datetime):
        @classmethod
        def fromisoformat(cls, text):
            if text.endswith("Z"):
                raise ValueError("Python 3.10 rejects Z")
            return datetime.fromisoformat(text)
    rejects = False
    try:
        Py310.fromisoformat("2026-10-10T08:48:31.123Z")
    except ValueError:
        rejects = True
    with patched("datetime", Py310):
        got310 = reader.parse_ts("2026-10-10T08:48:31.123Z")
    check("H12 parses under an emulated 3.10 fromisoformat (Z replaced)",
          rejects and got310 is not None and abs(got310 - want) < 1e-6)
    check("H12 a naive timestamp in data is not parsed", reader.parse_ts("2026-10-10T08:48:31") is None)
    d = case_dir("h12")
    jsonl(d / "t/s1.jsonl", [
        {"type": "user", "timestamp": "2026-10-10T08:48:00.500Z", "message": {"content": "go"}},
        {"type": "assistant", "timestamp": "2026-10-10T08:48:31.123Z", "message": {
            "id": "m1", "content": [use("b", "Bash", command="sleep 1500")]}},
        {"type": "user", "timestamp": "2026-10-10T09:13:31.123Z", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "b", "content": "ok"}]}}])
    r = histogram(d)
    check("H12 long list prints the ISO UTC second of the gap start",
          ["long", "S1", "command", "main", "2026-10-10T08:48:31Z", "25.0"] in r.rows, r.stdout)


def h13():
    d = case_dir("h13")
    main = [prompt(m) if m % 2 == 0 else say(m, mid="m%d" % m) for m in range(11)]
    jsonl(d / "t/s1.jsonl", main)
    jsonl(d / "t/s1/subagents/agent-a.jsonl", [
        prompt(0), say(1.5, use("b1", "Bash", command="make"), mid="a1"), result(2.5, "b1"),
        say(3, use("b2", "Bash", command="make"), mid="a2"), result(4, "b2"), say(4.5, mid="a3")])
    jsonl(d / "t/s1/subagents/agent-o.jsonl", [
        prompt(0.5), say(1, use("o_out", "Bash", command="sleep 9"), mid="o1"),
        say(3, use("o_in", "Bash", command="sleep 9"), mid="o2")])
    jsonl(d / "audit.jsonl", [audit_row(m) for m in range(11)])
    r = histogram(d, "--since", stamp(2, ms=False), "--until", "2026-10-10T08:08:00")
    check("H13 window rows", ["histogram", "since", "2026-10-10T08:02:00Z"] in r.rows
          and ["histogram", "until", "2026-10-10T08:08:00Z"] in r.rows, r.stdout)
    check("H13 lines outside the window are trimmed, edges inclusive",
          value(r.rows, "input", "lines", "timed") == "20"
          and value(r.rows, "input", "lines", "in_window") == "12", r.stdout)
    check("H13 S1 counts only gaps inside the window",
          pairs(r.rows, "S1", "model", "main", "min").get("n") == "3"
          and pairs(r.rows, "S1", "idle", "main", "min").get("n") == "3"
          and pairs(r.rows, "S1", "command", "agent", "min").get("n") == "1"
          and pairs(r.rows, "S1", "model", "agent", "min").get("n") == "2", r.stdout)
    check("H13 a span starting before the window is dropped",
          pairs(r.rows, "S6", "command", "agent", "sec").get("n") == "1"
          and pairs(r.rows, "S6", "command", "agent", "sec").get("max") == "60.0", r.stdout)
    check("H13 S7 counts only calls inside the window; an orphan counts only if it starts inside",
          pairs(r.rows, "S7", "total", "readonly", "agent", "calls").get("n") == "2"
          and pairs(r.rows, "S7", "total", "readonly", "agent", "calls").get("max") == "1"
          and value(r.rows, "S6", "orphans", "command", "agent") == "1", r.stdout)
    check("H13 audit rows are trimmed", value(r.rows, "audit", "rows") == "7"
          and pairs(r.rows, "S5", "raw", "all", "min").get("n") == "6", r.stdout)


for case in (h1, h2, h3, h4, h5, h6, h10, h11, h12, h13):
    try:
        case()
    except Exception as exc:  # a crashing case is one failure; the rest still run
        check(case.__name__.upper() + " crashed", False, "%s: %s" % (type(exc).__name__, exc))
raise SystemExit(failed)
