#!/usr/bin/env python3
"""FR-26 token-waste audit — deterministic, stdlib-only transcript parser.

Parses Claude Code project transcripts (~/.claude/projects/<munged-repo-path>/*.jsonl)
and reports per-session token totals plus leak-signature CANDIDATES mapped to
FR-26 rules (flow-skills/token-economy/SKILL.md). Operator tooling (preflight/
health-check class) — not part of the hook test harness; verified by live self-run.

Privacy: no message/thinking/tool-result text is emitted. Tool results appear as
(tool, target, size estimate); command snippets are one line, <=100 chars. A
one-way hash (never the content) fingerprints results to detect an identical large
body re-sent across turns.

Usage: python hooks/local/token-waste-audit.py [--last N] [--dir PATH]
Exit 0 always when transcripts are merely missing/empty (degraded repo-side mode).
"""

import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys
from collections import namedtuple
from pathlib import Path

DEFAULT_LAST = 10
READ_REPEAT_MIN = 3
BASH_REPEAT_MIN = 3
FR10_TRIPLE = 3                # exactly-3 runs: labeled, dismissed only when probe-shaped
LARGE_WRITE_CHARS = 10_000
SNIPPET_MAX = 100
TOP_SINKS = 10
LARGE_TOOL_RESULT_CHARS = 20_000
REPEAT_OUTPUT_MIN = 2          # an identical large body seen >= this many times = candidate
LINE_TYPES = {"assistant", "user"}
WRITE_TOOLS = {"Edit", "Write", "NotebookEdit"}

# TRIPWIRE: `key` is the FULL read key (path, offset, limit) and `seq` the event index.
# Both are the association A8/AC15 requires — `target` is a <=100-char display snippet
# and must never be used as a classification key.
ToolResult = namedtuple("ToolResult", "chars name target digest key seq err")
Finding = namedtuple("Finding", "cls desc rule status label evidence")

LIVE = "live"
CLASSIFIED = "auto-classified"

TERMINAL_FOUND = "TERMINAL STATE: candidates found (live candidates need adjudication)"
TERMINAL_ALL_CLASSIFIED = (
    "TERMINAL STATE: candidates found but all auto-classified (0 live; see the "
    "auto-classified section for the rule and evidence behind each dismissal)")
TERMINAL_CLEAN = "TERMINAL STATE: no candidates above thresholds (transcripts parsed successfully)"
TERMINAL_NO_DATA = (
    "TERMINAL STATE: no transcripts / parse failure (nothing was parsed — this is NOT "
    "evidence of cleanliness)")

# A8 probe-shaped predicate: a test runner, an explicit --dry-run, or a health/status/
# version verb. --probe-command adds the ticket's own documented gate probes.
PROBE_PATTERNS = (
    (r"\bpytest\b", "test runner (pytest)"),
    (r"\bnpm\s+test\b", "test runner (npm test)"),
    (r"\brun-tests\b", "test runner (run-tests)"),
    (r"bash\s+hooks/tests/", "test runner (bash hooks/tests/)"),
    (r"--dry-run\b", "explicit --dry-run"),
    (r"\bgit\s+status\b", "status verb (git status)"),
    (r"\bhealth-check\b", "health verb (health-check)"),
    (r"\bpreflight\b", "health verb (preflight)"),
    (r"--version\b", "version verb (--version)"),
    (r"\bstatus\b", "status verb (status)"),
)

# TRIPWIRE: matched against the whitespace-normalized result HEAD only, and only ever
# as a boolean — the head itself never leaves result_size_and_digest (no-content-emitted).
ERROR_SHAPE = re.compile(r"(?i)^\s*(error\b|<tool_use_error>|exception\b|traceback\b)")

FALSE_POSITIVE_HEADER = (
    "Findings below are CANDIDATES that MAY indicate an FR-26 rule violation — "
    "not verdicts. Known false-positive classes: a WARRANTED FR-18 full-Write "
    "supersede (structure/mode/ticket change, or most sections changed — FR-18 "
    "mandates the replaced semantics, not the rewrite tool; a targeted Edit is "
    "the default primitive), mirror/overlay regeneration (generated "
    "copies), deliberate FR-10 3/3 reproduction runs, test reruns after a real "
    "change, bounded labeled flaky-external retries. For large-output: an "
    "intentional first read of a large file needed to hold its invariants, a "
    "warranted FR-18 full-Write supersede or mirror regeneration, generated output "
    "that is itself the subject of the task, deliberate FR-10 reproduction "
    "evidence, and a one-time large diagnostic report written to disk then read once. "
    "For repeat-output: a deliberately re-run command's fresh (different) output and "
    "FR-10 reproduction reruns are not re-sends of the same body."
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
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=10,
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


def result_size_and_digest(content):
    """Return (char count, short one-way fingerprint of the result TEXT, error-shaped?).

    The digest detects an identical large body re-sent across turns. The raw body is
    hashed in memory only — never stored or emitted — preserving the no-content-emitted
    privacy invariant. Char count is byte-for-byte the same metric as before (key order
    in json.dumps does not change length; sort_keys only stabilizes the digest)."""
    parts = []
    if isinstance(content, str):
        parts.append(content)
    elif isinstance(content, list):
        for block in content:
            if isinstance(block, dict):
                if block.get("type") == "text":
                    parts.append(block.get("text") or "")
                else:
                    try:
                        parts.append(json.dumps(block, default=str, sort_keys=True))
                    except Exception:
                        pass
            else:
                parts.append(str(block))
    text = "".join(parts)
    norm = " ".join(text.split())
    digest = hashlib.sha256(norm.encode("utf-8", "replace")).hexdigest()[:16]
    return len(text), digest, bool(ERROR_SHAPE.match(norm[:200]))


def is_output_heavy(name):
    """A large result is a context-compression candidate when it came from an
    OUTPUT-producing tool — any built-in OR MCP (`mcp__*`) tool. Detected GENERICALLY by
    excluding write tools (their result is an edit confirmation; the bulk content is the
    edit itself, covered by the rewrite class) and the unmapped "?" sentinel (unknown
    provenance). An exclusion test, not an allowlist, so new built-ins and MCP servers
    are covered automatically instead of silently missed."""
    return name not in WRITE_TOOLS and name != "?"


def is_compaction_marker(obj):
    """A context compaction between two reads is an A8 contradictory event: the later
    read may be re-establishing dropped context rather than tailing a growing source."""
    if obj.get("isCompactSummary") is True or obj.get("compactMetadata"):
        return True
    for key in ("subtype", "type"):
        val = obj.get(key)
        if isinstance(val, str) and "compact" in val.lower():
            return True
    return False


def parse_session(path):
    s = {
        "file": path.name,
        "malformed": 0,
        "usage_by_request": {},       # requestId -> last usage seen
        "usage_no_request": [],
        "tool_result_chars": 0,
        "tool_results": [],           # ToolResult(chars, name, target, digest, key, seq, err)
        "read_counts": {},            # (file_path, offset, limit) -> count
        "read_events": {},            # full read key -> [(seq, chars, digest, err)] in order
        "write_events": [],           # (seq, full target path) for Edit/Write/NotebookEdit
        "compaction_seqs": [],        # event index of each compaction marker
        "bash_runs": {},              # norm cmd -> max consecutive-without-write run
        "large_writes": [],           # (path, content_chars)
        "seen_tool_ids": set(),
    }
    tool_meta = {}                    # tool_use id -> (name, target, full key, seq)
    bash_counts = {}
    seen_paths = set()
    seen_result_ids = set()           # tool_use_id of results already counted (no double-count)
    seq = 0                           # monotonic event index: line-level, then per block
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
            if not isinstance(obj, dict):
                continue
            seq += 1
            # Compaction markers are their own line type — checked BEFORE the
            # assistant/user filter, or the marker is never seen.
            if is_compaction_marker(obj):
                s["compaction_seqs"].append(seq)
            if obj.get("type") not in LINE_TYPES:
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
                        seq += 1
                        name = block.get("name") or "?"
                        tin = block.get("input") if isinstance(block.get("input"), dict) else {}
                        key = None
                        if name == "Read":
                            key = (str(tin.get("file_path", "")), tin.get("offset"), tin.get("limit"))
                            s["read_counts"][key] = s["read_counts"].get(key, 0) + 1
                        if tid:
                            tool_meta[tid] = (name, tool_target(name, tin), key, seq)
                        if name in WRITE_TOOLS:
                            wpath = tin.get("file_path") or tin.get("notebook_path")
                            if wpath:
                                s["write_events"].append((seq, str(wpath)))
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
                    rid_res = block.get("tool_use_id")
                    if rid_res and rid_res in seen_result_ids:
                        continue  # same result line repeated in the transcript — count once
                    if rid_res:
                        seen_result_ids.add(rid_res)
                    seq += 1
                    chars, digest, err = result_size_and_digest(block.get("content"))
                    err = err or block.get("is_error") is True
                    s["tool_result_chars"] += chars
                    name, target, key, use_seq = tool_meta.get(rid_res, ("?", "?", None, seq))
                    s["tool_results"].append(
                        ToolResult(chars, name, target, digest, key, use_seq, err))
                    if name == "Read" and key is not None:
                        s["read_events"].setdefault(key, []).append((use_seq, chars, digest, err))
    for evs in s["read_events"].values():
        evs.sort(key=lambda e: e[0])   # event order, not transcript-result arrival order
    return s


def usage_totals(s):
    usages = list(s["usage_by_request"].values()) + s["usage_no_request"]
    out = {"requests": len(usages), "output_tokens": 0, "cache_read": 0, "cache_creation": 0}
    for u in usages:
        out["output_tokens"] += u.get("output_tokens") or 0
        out["cache_read"] += u.get("cache_read_input_tokens") or 0
        out["cache_creation"] += u.get("cache_creation_input_tokens") or 0
    return out


def monotonic_growth(sizes):
    return all(a <= b for a, b in zip(sizes, sizes[1:])) and sizes[-1] > sizes[0]


def contradictory_event(s, key, events):
    """A8 contradictory-event predicate. Returns the evidence string, or "" if none."""
    lo, hi = events[0][0], events[-1][0]
    path = key[0]
    for wseq, wpath in s["write_events"]:
        if lo < wseq < hi and wpath == path:
            return "intervening write to the read path at event %d" % wseq
    for cseq in s["compaction_seqs"]:
        if lo < cseq < hi:
            return "context compaction between the reads at event %d" % cseq
    if any(e[3] for e in events):
        return "error-shaped tool_result for one of the reads"
    sizes = [e[1] for e in events]
    # TRIPWIRE: unreachable while the growth gate below requires ALL digests distinct
    # (identical digests already fail it). Kept because it is normative in A8 and becomes
    # load-bearing the moment "differing digests" is loosened to "not all identical".
    if any(b < a for a, b in zip(sizes, sizes[1:])) and len({e[2] for e in events}) == 1:
        return "non-monotonic size sequence with identical digests"
    return ""


def classify_re_read(s, key, n):
    """A8 growing-source-tail — CONJUNCTIVE: same full read key AND (monotonic growth OR
    differing digests) AND no contradictory event. Returns (status, evidence)."""
    events = s["read_events"].get(key, [])
    if len(events) != n:
        return LIVE, "result evidence for only %d of %d reads — not evaluable" % (len(events), n)
    sizes = [e[1] for e in events]
    digests = [e[2] for e in events]
    ndist = len(set(digests))
    grew = monotonic_growth(sizes)
    all_differ = ndist == len(digests)
    if not (grew or all_differ):
        return LIVE, ("sizes %s, %d distinct digest(s) — neither monotonic growth nor "
                      "all-differing digests (size difference alone is not sufficient)"
                      % (sizes, ndist))
    contra = contradictory_event(s, key, events)
    if contra:
        return LIVE, "growth signal present but contradicted — %s" % contra
    return CLASSIFIED, ("same full read key %s; %s (sizes %s, %d distinct digests); "
                        "no contradictory event"
                        % (snippet(str(key)), "monotonic growth" if grew else "all digests differ",
                           sizes, ndist))


def probe_shaped(cmd, probe_cmds=()):
    """A8 probe-shaped predicate, matched against the normalized command string."""
    low = " ".join(cmd.split()).lower()
    for pattern, label in PROBE_PATTERNS:
        if re.search(pattern, low):
            return label
    for extra in probe_cmds:
        if extra and " ".join(extra.split()).lower() in low:
            return "documented gate probe (--probe-command %s)" % snippet(extra)
    return ""


def classify_bash(cmd, n, probe_cmds=()):
    """A8 FR-10 triple — exactly 3 runs are LABELED; dismissed only when probe-shaped.
    Returns (status, label, evidence). `n` counts runs since the last write, not
    truly consecutive runs (parse_session clears the counter on Edit/Write)."""
    since = "%d runs since the last write (not necessarily consecutive)" % n
    if n != FR10_TRIPLE:
        return LIVE, "", since
    shape = probe_shaped(cmd, probe_cmds)
    if shape:
        return CLASSIFIED, "possible-FR-10-triple", "exactly %s; probe-shaped: %s" % (since, shape)
    return LIVE, "possible-FR-10-triple", (
        "exactly %s; command is NOT probe-shaped — 3 failed retries and 3 polls are "
        "count-identical to a genuine FR-10 reproduction triple, so this stays live" % since)


def session_findings(s, probe_cmds=()):
    f = []
    for key, n in sorted(s["read_counts"].items(), key=lambda kv: -kv[1]):
        fp, off, lim = key
        if n >= READ_REPEAT_MIN and fp:
            win = "" if off is None and lim is None else " [offset=%s limit=%s]" % (off, lim)
            status, evidence = classify_re_read(s, key, n)
            f.append(Finding("re-read", "Read x%d identical window: %s%s" % (n, snippet(fp), win),
                             "FR-26 TE-02 — no re-reads of unchanged in-context files",
                             status, "growing-source-tail" if status == CLASSIFIED else "",
                             evidence))
    for cmd, n in sorted(s["bash_runs"].items(), key=lambda kv: -kv[1]):
        if n >= BASH_REPEAT_MIN and cmd:
            status, label, evidence = classify_bash(cmd, n, probe_cmds)
            f.append(Finding("polling", "Bash x%d (no intervening Edit/Write): %s" % (n, snippet(cmd)),
                             "FR-26 TE-08 — record-then-read (smoke-testing § Verification cost discipline)",
                             status, label, evidence))
    for fp, chars in s["large_writes"]:
        f.append(Finding("rewrite", "Write %d chars to pre-existing path: %s" % (chars, fp),
                         "FR-26 TE-06 — targeted edits over whole-file rewrites", LIVE, "", ""))
    # large-output: oversized results from any output-producing tool (built-in OR MCP;
    # write tools + unmapped "?" excluded) — candidates for extract/scope/filter before
    # reasoning (§ Context compression discipline). Capped at TOP_SINKS per session
    # (largest first) so one noisy session can't flood. Only (size, tool, target) emitted.
    large = sorted(
        ((r.chars, r.name, r.target) for r in s["tool_results"]
         if r.chars >= LARGE_TOOL_RESULT_CHARS and is_output_heavy(r.name)),
        key=lambda r: (-r[0], r[1], r[2]),
    )[:TOP_SINKS]
    for chars, name, target in large:
        f.append(Finding("large-output",
                         "Tool result %d chars (~%d tokens): %s %s" % (chars, chars // 4, name, target),
                         "FR-26 TE-11/TE-17 — extract/scope/filter before reasoning over large output",
                         LIVE, "", ""))
    # repeat-output: the SAME large body re-sent across turns (identical fingerprint).
    # One finding per recurring digest (count = times seen) — references-not-re-sends.
    by_digest = {}
    for r in s["tool_results"]:
        if r.chars >= LARGE_TOOL_RESULT_CHARS and is_output_heavy(r.name):
            by_digest.setdefault(r.digest, []).append((r.chars, r.name, r.target))
    repeats = sorted(
        ((len(v), v[0][0], v[0][1], v[0][2]) for v in by_digest.values() if len(v) >= REPEAT_OUTPUT_MIN),
        key=lambda r: (-r[0], -r[1], r[2], r[3]),
    )[:TOP_SINKS]
    for n, chars, name, target in repeats:
        f.append(Finding("repeat-output",
                         "Identical large result x%d (~%d chars each): %s %s" % (n, chars, name, target),
                         "FR-26 TE-07 — reference an in-context body by its handle, don't re-send it",
                         LIVE, "", ""))
    return f


def session_is_empty(s):
    return not (s["read_counts"] or s["bash_runs"] or s["tool_results"]
                or s["usage_by_request"] or s["usage_no_request"])


def terminal_state(sessions, live_n, classified_n):
    """QP-21: silence must never be indistinguishable from cleanliness."""
    if not sessions or all(session_is_empty(s) for s in sessions):
        return TERMINAL_NO_DATA
    if live_n:
        return TERMINAL_FOUND
    if classified_n:
        return TERMINAL_ALL_CLASSIFIED
    return TERMINAL_CLEAN


def fallback_summary(root):
    lines = ["", "## Repo-side fallback summary (transcript metrics unavailable)", ""]
    try:
        out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, encoding="utf-8", errors="replace",
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


AGGREGATE_HEADER = (
    "> Read-tool/Bash visibility only — auto-injected always-on context never appears as transcript "
    "tool calls, so the dominant cross-session floor cost may be invisible here. Recurring rules/handoff "
    "reads and session-initiation Bash floor commands (git status, git log) are usually the session floor "
    "working as designed — an FR-23 session-floor surface (consider pre-cached IDs, pointers, smaller "
    "always-on files), NOT an FR-26 violation. Top %d rows by session-count." % TOP_SINKS)


def cross_session_aggregate(sessions):
    """Files/commands recurring in >=2 parsed sessions (path-keyed; window args ignored)."""
    file_sessions = {}   # path -> set(session file)
    file_reads = {}      # path -> total reads across sessions
    cmd_sessions = {}    # normalized command -> set(session file)
    for s in sessions:
        for (fp, _off, _lim), n in s["read_counts"].items():
            if not fp:
                continue
            file_sessions.setdefault(fp, set()).add(s["file"])
            file_reads[fp] = file_reads.get(fp, 0) + n
        for cmd in s["bash_runs"]:
            if cmd:
                cmd_sessions.setdefault(cmd, set()).add(s["file"])
    files = sorted(((len(ss), file_reads[fp], fp) for fp, ss in file_sessions.items() if len(ss) >= 2),
                   key=lambda r: (-r[0], -r[1]))
    cmds = sorted(((len(ss), c) for c, ss in cmd_sessions.items() if len(ss) >= 2),
                  key=lambda r: -r[0])
    return files[:TOP_SINKS], cmds[:TOP_SINKS]


def build_report(sessions, root, today, probe_cmds=()):
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
    for r in sorted(all_results, key=lambda r: (-r.chars, r.name, r.target))[:TOP_SINKS]:
        lines.append("| %d (~%d) | %s | %s |" % (r.chars, r.chars // 4, r.name, r.target))
    per_session = [(s, session_findings(s, probe_cmds)) for s in sessions]
    live_n = sum(1 for _s, fs in per_session for f in fs if f.status == LIVE)
    classified_n = sum(1 for _s, fs in per_session for f in fs if f.status == CLASSIFIED)
    lines += ["", "## Findings — LIVE candidates that MAY indicate an FR-26 rule", "",
              "Auto-classified candidates are NOT listed here — they are in their own section "
              "below, so a dismissal neither buries nor inflates this count. Live: %d." % live_n, ""]
    any_finding = False
    for s, found in per_session:
        live = [f for f in found if f.status == LIVE]
        if not live:
            continue
        any_finding = True
        lines += ["### %s" % s["file"], "",
                  "| Class | Candidate | Label | FR-26 rule it MAY indicate | Why it stayed live |",
                  "|---|---|---|---|---|"]
        for f in live:
            lines.append("| %s | %s | %s | %s | %s |" % (f.cls, f.desc, f.label or "—", f.rule,
                                                         f.evidence or "threshold match"))
        lines.append("")
    if not any_finding:
        lines.append("No LIVE leak-signature candidates above thresholds.")
        lines.append("")
    lines += ["## Auto-classified (dismissed — counted separately, never silently dropped)", "",
              "Each row states the rule that fired AND the evidence that triggered it. "
              "Auto-classified: %d." % classified_n, ""]
    if classified_n:
        for s, found in per_session:
            dismissed = [f for f in found if f.status == CLASSIFIED]
            if not dismissed:
                continue
            lines += ["### %s" % s["file"], "",
                      "| Class | Candidate | Rule that fired | Evidence that triggered it |",
                      "|---|---|---|---|"]
            for f in dismissed:
                lines.append("| %s | %s | auto-classified: %s | %s |"
                             % (f.cls, f.desc, f.label, f.evidence))
            lines.append("")
    else:
        lines += ["Nothing was auto-classified.", ""]
    lines += [terminal_state(sessions, live_n, classified_n), ""]
    if len(sessions) >= 2:
        agg_files, agg_cmds = cross_session_aggregate(sessions)
        lines += ["## Cross-session aggregate (%d sessions)" % len(sessions), "",
                  AGGREGATE_HEADER, ""]
        if agg_files:
            lines += ["| Sessions | Total reads | File |", "|---|---|---|"]
            for ns, total, fp in agg_files:
                lines.append("| %d | %d | %s |" % (ns, total, snippet(fp)))
            lines.append("")
        if agg_cmds:
            lines += ["| Sessions | Bash command (present in session) |", "|---|---|"]
            for ns, c in agg_cmds:
                lines.append("| %d | %s |" % (ns, snippet(c)))
            lines.append("")
        if not agg_files and not agg_cmds:
            lines.append("No file or command recurs in >=2 of the parsed sessions.")
            lines.append("")
        # repeated identical large bodies across the parsed sessions (digest-keyed) —
        # the same large content re-sent. Counts occurrences (and distinct sessions);
        # only (count, sessions, tool, target, size) is emitted, never the body.
        body_occ, body_sess = {}, {}
        for s in sessions:
            for r in s["tool_results"]:
                if r.chars >= LARGE_TOOL_RESULT_CHARS and is_output_heavy(r.name):
                    body_occ.setdefault(r.digest, []).append((r.chars, r.name, r.target))
                    body_sess.setdefault(r.digest, set()).add(s["file"])
        repeated = sorted(
            ((len(occ), len(body_sess[d]), occ[0][0], occ[0][1], occ[0][2])
             for d, occ in body_occ.items() if len(occ) >= REPEAT_OUTPUT_MIN),
            key=lambda r: (-r[0], -r[2], r[3], r[4]),
        )[:TOP_SINKS]
        if repeated:
            lines += ["**Repeated identical large bodies** (same content re-sent — reference it by handle):", "",
                      "| Times | Sessions | Chars (~tokens) | Tool | Target |", "|---|---|---|---|---|"]
            for times, nsess, chars, name, target in repeated:
                lines.append("| %d | %d | %d (~%d) | %s | %s |" % (times, nsess, chars, chars // 4, name, target))
            lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="FR-26 token-waste audit (deterministic transcript parser)")
    ap.add_argument("--last", type=int, default=DEFAULT_LAST, metavar="N",
                    help="audit the N most recently modified sessions (default %d)" % DEFAULT_LAST)
    ap.add_argument("--dir", default=None, metavar="PATH",
                    help="transcript directory override (default: auto-locate under ~/.claude/projects)")
    ap.add_argument("--probe-command", action="append", default=[], metavar="CMD",
                    help="a documented probe command from this ticket's gate; repeatable. "
                         "Extends the A8 probe-shaped predicate for FR-10-triple dismissal.")
    args = ap.parse_args()
    probe_cmds = tuple(args.probe_command or ())

    root = git_root()
    today = datetime.date.today().isoformat()

    tdir = Path(args.dir) if args.dir else locate_transcript_dir(root)
    files = sorted(tdir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True) \
        if (tdir and tdir.is_dir()) else []
    if not files:
        where = str(tdir) if tdir else str(Path.home() / ".claude" / "projects" / munge(str(root.resolve())))
        print("[token-waste-audit] transcript metrics unavailable (no transcripts at: %s)" % where)
        print(fallback_summary(root))
        print("")
        print(TERMINAL_NO_DATA)
        return 0

    sessions = [parse_session(p) for p in files[: max(args.last, 1)]]
    report = build_report(sessions, root, today, probe_cmds)

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
    counts = {"re-read": 0, "polling": 0, "rewrite": 0, "large-output": 0, "repeat-output": 0}
    dismissed = []
    for s in sessions:
        t = usage_totals(s)
        print("| %s | %d | %d | %d | %d | %d (~%d) |" % (
            s["file"], t["requests"], t["output_tokens"], t["cache_read"],
            t["cache_creation"], s["tool_result_chars"], s["tool_result_chars"] // 4))
        for f in session_findings(s, probe_cmds):
            if f.status == CLASSIFIED:
                dismissed.append((s["file"], f))
            else:
                counts[f.cls] = counts.get(f.cls, 0) + 1
    print("")
    print("LIVE candidates (MAY indicate -- see report header for false-positive classes): "
          "re-read %d | polling %d | whole-file-rewrite %d | large-output %d | repeat-output %d" % (
              counts["re-read"], counts["polling"], counts["rewrite"],
              counts["large-output"], counts["repeat-output"]))
    # AC17/AC18: dismissals are counted apart from live findings and every one prints the
    # rule that fired AND its evidence. A silent dismissal is a false negative nobody sees.
    print("Auto-classified (dismissed, NOT counted above): %d" % len(dismissed))
    for fname, f in dismissed:
        print("  - %s | %s | auto-classified: %s | evidence: %s" % (fname, f.cls, f.label, f.evidence))
    print("")
    print(terminal_state(sessions, sum(counts.values()), len(dismissed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
