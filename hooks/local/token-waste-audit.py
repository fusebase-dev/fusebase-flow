#!/usr/bin/env python3
"""FR-26 token-waste audit — deterministic, stdlib-only transcript parser.

Parses Claude Code project transcripts (~/.claude/projects/<munged-repo-path>/*.jsonl)
and reports per-session token totals plus leak-signature CANDIDATES mapped to
FR-26 rules (flow-skills/token-economy/SKILL.md). Operator tooling (preflight/
health-check class) — not part of the hook test harness; verified by live self-run.

Privacy: no message/thinking/tool-result text is emitted. Tool results appear as
(tool, target, size estimate); command snippets are one line, <=100 chars.

Usage: python hooks/local/token-waste-audit.py [--last N] [--dir PATH]
Exit 0 always when transcripts are merely missing/empty (degraded repo-side mode).
"""

import argparse
import datetime
import json
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_LAST = 10
READ_REPEAT_MIN = 3
BASH_REPEAT_MIN = 3
LARGE_WRITE_CHARS = 10_000
SNIPPET_MAX = 100
TOP_SINKS = 10
LINE_TYPES = {"assistant", "user"}
WRITE_TOOLS = {"Edit", "Write", "NotebookEdit"}

FALSE_POSITIVE_HEADER = (
    "Findings below are CANDIDATES that MAY indicate an FR-26 rule violation — "
    "not verdicts. Known false-positive classes: FR-18 supersede rewrites "
    "(whole-file replace is mandated), mirror/overlay regeneration (generated "
    "copies), deliberate FR-10 3/3 reproduction runs, test reruns after a real "
    "change, bounded labeled flaky-external retries."
)


def snippet(text):
    if not isinstance(text, str):
        text = str(text)
    one_line = " ".join(text.split())
    return one_line[:SNIPPET_MAX]


def git_root():
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=10,
        )
        if out.returncode == 0 and out.stdout.strip():
            return Path(out.stdout.strip())
    except Exception:
        pass
    return Path.cwd()


def munge(path_str):
    return re.sub(r"[^A-Za-z0-9]", "-", path_str)


def locate_transcript_dir(root):
    projects = Path.home() / ".claude" / "projects"
    munged = munge(str(root.resolve()))
    exact = projects / munged
    if exact.is_dir():
        return exact
    # Windows drive-letter munge edge: on-disk dir name may differ only by case.
    if projects.is_dir():
        for child in projects.iterdir():
            if child.is_dir() and child.name.lower() == munged.lower():
                return child
    return None


def tool_target(name, tool_input):
    if not isinstance(tool_input, dict):
        return snippet(name)
    if name == "Read":
        t = str(tool_input.get("file_path", ""))
        off, lim = tool_input.get("offset"), tool_input.get("limit")
        if off is not None or lim is not None:
            t += " [offset=%s limit=%s]" % (off, lim)
        return snippet(t)
    if name in ("Bash", "PowerShell"):
        return snippet(tool_input.get("command", ""))
    for key in ("file_path", "notebook_path", "pattern", "url", "query", "path", "skill"):
        if tool_input.get(key):
            return snippet(str(tool_input[key]))
    return snippet(name)


def result_chars(content):
    if isinstance(content, str):
        return len(content)
    if isinstance(content, list):
        total = 0
        for block in content:
            if isinstance(block, dict):
                if block.get("type") == "text":
                    total += len(block.get("text") or "")
                else:
                    try:
                        total += len(json.dumps(block, default=str))
                    except Exception:
                        total += 0
            else:
                total += len(str(block))
        return total
    return 0


def parse_session(path):
    s = {
        "file": path.name,
        "malformed": 0,
        "usage_by_request": {},       # requestId -> last usage seen
        "usage_no_request": [],
        "tool_result_chars": 0,
        "tool_results": [],           # (chars, tool, target)
        "read_counts": {},            # (file_path, offset, limit) -> count
        "bash_runs": {},              # norm cmd -> max consecutive-without-write run
        "large_writes": [],           # (path, content_chars)
        "seen_tool_ids": set(),
    }
    tool_meta = {}                    # tool_use id -> (name, target)
    bash_counts = {}
    seen_paths = set()
    with path.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                s["malformed"] += 1
                continue
            if not isinstance(obj, dict) or obj.get("type") not in LINE_TYPES:
                continue
            msg = obj.get("message")
            if not isinstance(msg, dict):
                continue
            if obj["type"] == "assistant":
                usage = msg.get("usage")
                if isinstance(usage, dict):
                    rid = obj.get("requestId")
                    # One API request streams many assistant lines repeating the same
                    # usage object — naive summing overcounts ~2.4x; keep last per requestId.
                    if rid:
                        s["usage_by_request"][rid] = usage
                    else:
                        s["usage_no_request"].append(usage)
                content = msg.get("content")
                if isinstance(content, list):
                    for block in content:
                        if not (isinstance(block, dict) and block.get("type") == "tool_use"):
                            continue
                        tid = block.get("id")
                        if tid in s["seen_tool_ids"]:
                            continue
                        if tid:
                            s["seen_tool_ids"].add(tid)
                        name = block.get("name") or "?"
                        tin = block.get("input") if isinstance(block.get("input"), dict) else {}
                        if tid:
                            tool_meta[tid] = (name, tool_target(name, tin))
                        if name == "Read":
                            key = (str(tin.get("file_path", "")), tin.get("offset"), tin.get("limit"))
                            s["read_counts"][key] = s["read_counts"].get(key, 0) + 1
                        if name in WRITE_TOOLS:
                            bash_counts.clear()
                        if name in ("Bash", "PowerShell"):
                            norm = " ".join(str(tin.get("command", "")).split())
                            bash_counts[norm] = bash_counts.get(norm, 0) + 1
                            if bash_counts[norm] > s["bash_runs"].get(norm, 0):
                                s["bash_runs"][norm] = bash_counts[norm]
                        fp = tin.get("file_path") or tin.get("notebook_path")
                        if name == "Write" and fp:
                            content_len = len(str(tin.get("content", "")))
                            if str(fp) in seen_paths and content_len >= LARGE_WRITE_CHARS:
                                s["large_writes"].append((snippet(str(fp)), content_len))
                        if fp:
                            seen_paths.add(str(fp))
            else:  # user line; tool results live in message.content, never top-level toolUseResult
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not (isinstance(block, dict) and block.get("type") == "tool_result"):
                        continue
                    chars = result_chars(block.get("content"))
                    s["tool_result_chars"] += chars
                    name, target = tool_meta.get(block.get("tool_use_id"), ("?", "?"))
                    s["tool_results"].append((chars, name, target))
    return s


def usage_totals(s):
    usages = list(s["usage_by_request"].values()) + s["usage_no_request"]
    out = {"requests": len(usages), "output_tokens": 0, "cache_read": 0, "cache_creation": 0}
    for u in usages:
        out["output_tokens"] += u.get("output_tokens") or 0
        out["cache_read"] += u.get("cache_read_input_tokens") or 0
        out["cache_creation"] += u.get("cache_creation_input_tokens") or 0
    return out


def session_findings(s):
    f = []
    for (fp, off, lim), n in sorted(s["read_counts"].items(), key=lambda kv: -kv[1]):
        if n >= READ_REPEAT_MIN and fp:
            win = "" if off is None and lim is None else " [offset=%s limit=%s]" % (off, lim)
            f.append(("re-read", "Read x%d identical window: %s%s" % (n, snippet(fp), win),
                      "FR-26 no re-reads of unchanged in-context files"))
    for cmd, n in sorted(s["bash_runs"].items(), key=lambda kv: -kv[1]):
        if n >= BASH_REPEAT_MIN and cmd:
            f.append(("polling", "Bash x%d (no intervening Edit/Write): %s" % (n, snippet(cmd)),
                      "FR-26 record-then-read (smoke-testing § Verification cost discipline)"))
    for fp, chars in s["large_writes"]:
        f.append(("rewrite", "Write %d chars to pre-existing path: %s" % (chars, fp),
                  "FR-26 targeted edits over whole-file rewrites"))
    return f


def fallback_summary(root):
    lines = ["", "## Repo-side fallback summary (transcript metrics unavailable)", ""]
    try:
        out = subprocess.run(["git", "ls-files"], capture_output=True, text=True,
                             cwd=str(root), timeout=30)
        sizes = []
        for rel in out.stdout.splitlines():
            p = root / rel
            try:
                if p.is_file():
                    sizes.append((p.stat().st_size, rel))
            except OSError:
                continue
        sizes.sort(reverse=True)
        lines.append("| Largest tracked files (top %d) | bytes |" % TOP_SINKS)
        lines.append("|---|---|")
        for size, rel in sizes[:TOP_SINKS]:
            lines.append("| %s | %d |" % (rel, size))
    except Exception as exc:
        lines.append("git ls-files unavailable: %s" % exc)
    handoff = root / "docs" / "tmp" / "handoff.md"
    if handoff.is_file():
        lines.append("")
        lines.append("docs/tmp/handoff.md: %d bytes" % handoff.stat().st_size)
    else:
        lines.append("")
        lines.append("docs/tmp/handoff.md: absent")
    lines.append("")
    lines.append("Optional deeper repo scan: bash hooks/local/check-module-size.sh --all")
    return "\n".join(lines)


def build_report(sessions, root, today):
    lines = ["# Token-waste audit — %s" % today, "",
             "Scope: %d session(s), dir-resolved from git root `%s`." % (len(sessions), root),
             "", FALSE_POSITIVE_HEADER, "", "## Per-session totals", "",
             "| Session | Requests | Output tokens | Cache read | Cache creation | Tool-result chars (~tokens) | Malformed lines skipped |",
             "|---|---|---|---|---|---|---|"]
    all_results = []
    for s in sessions:
        t = usage_totals(s)
        lines.append("| %s | %d | %d | %d | %d | %d (~%d) | %d |" % (
            s["file"], t["requests"], t["output_tokens"], t["cache_read"],
            t["cache_creation"], s["tool_result_chars"], s["tool_result_chars"] // 4,
            s["malformed"]))
        all_results.extend(s["tool_results"])
    lines += ["", "## Top %d largest tool results (tool, target, size estimate)" % TOP_SINKS, "",
              "| Chars (~tokens) | Tool | Target |", "|---|---|---|"]
    for chars, name, target in sorted(all_results, key=lambda r: -r[0])[:TOP_SINKS]:
        lines.append("| %d (~%d) | %s | %s |" % (chars, chars // 4, name, target))
    lines += ["", "## Findings — candidates that MAY indicate an FR-26 rule", ""]
    any_finding = False
    for s in sessions:
        found = session_findings(s)
        if not found:
            continue
        any_finding = True
        lines.append("### %s" % s["file"])
        lines.append("")
        lines.append("| Class | Candidate | FR-26 rule it MAY indicate |")
        lines.append("|---|---|---|")
        for cls, desc, rule in found:
            lines.append("| %s | %s | %s |" % (cls, desc, rule))
        lines.append("")
    if not any_finding:
        lines.append("No leak-signature candidates above thresholds.")
        lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="FR-26 token-waste audit (deterministic transcript parser)")
    ap.add_argument("--last", type=int, default=DEFAULT_LAST, metavar="N",
                    help="audit the N most recently modified sessions (default %d)" % DEFAULT_LAST)
    ap.add_argument("--dir", default=None, metavar="PATH",
                    help="transcript directory override (default: auto-locate under ~/.claude/projects)")
    args = ap.parse_args()

    root = git_root()
    today = datetime.date.today().isoformat()

    tdir = Path(args.dir) if args.dir else locate_transcript_dir(root)
    files = sorted(tdir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True) \
        if (tdir and tdir.is_dir()) else []
    if not files:
        where = str(tdir) if tdir else str(Path.home() / ".claude" / "projects" / munge(str(root.resolve())))
        print("[token-waste-audit] transcript metrics unavailable (no transcripts at: %s)" % where)
        print(fallback_summary(root))
        return 0

    sessions = [parse_session(p) for p in files[: max(args.last, 1)]]
    report = build_report(sessions, root, today)

    report_path = root / "state" / "audit" / ("token-waste-audit-%s.md" % today)
    try:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(report, encoding="utf-8", newline="\n")
        wrote = str(report_path)
    except OSError as exc:
        wrote = "(write failed: %s)" % exc

    print("[token-waste-audit] sessions: %d | report: %s" % (len(sessions), wrote))
    print("")
    print("| Session | Requests | Output tokens | Cache read | Cache creation | Tool-result chars (~tokens) |")
    print("|---|---|---|---|---|---|")
    counts = {"re-read": 0, "polling": 0, "rewrite": 0}
    for s in sessions:
        t = usage_totals(s)
        print("| %s | %d | %d | %d | %d | %d (~%d) |" % (
            s["file"], t["requests"], t["output_tokens"], t["cache_read"],
            t["cache_creation"], s["tool_result_chars"], s["tool_result_chars"] // 4))
        for cls, _, _ in session_findings(s):
            counts[cls] = counts.get(cls, 0) + 1
    print("")
    print("Candidates (MAY indicate -- see report header for false-positive classes): "
          "re-read %d | polling %d | whole-file-rewrite %d" % (
              counts["re-read"], counts["polling"], counts["rewrite"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
