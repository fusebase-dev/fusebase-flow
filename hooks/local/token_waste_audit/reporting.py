from .common import (LIVE, CLASSIFIED, TOP_SINKS, LARGE_TOOL_RESULT_CHARS,
                     REPEAT_OUTPUT_MIN, FALSE_POSITIVE_HEADER, TERMINAL_NO_DATA,
                     TERMINAL_FOUND, TERMINAL_ALL_CLASSIFIED, TERMINAL_CLEAN,
                     snippet, is_output_heavy)
from .classification import selected_findings
from .parsing import usage_totals, transcripts
import subprocess

def combined_totals(items):
    out = {"requests": 0, "output_tokens": 0, "cache_read": 0, "cache_creation": 0}
    for item in items:
        for key, value in usage_totals(item).items():
            out[key] += value
    return out


def session_is_empty(s):
    return not (s["read_counts"] or s["bash_runs"] or s["tool_results"]
                or s["usage_by_request"] or s["usage_no_request"])


def terminal_state(sessions, live_n, classified_n):
    """QP-21: silence must never be indistinguishable from cleanliness."""
    if not sessions or all(session_is_empty(s) for s in transcripts(sessions)):
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
    for s in transcripts(sessions):
        session_id = s.get("session_id", s["file"])
        for (fp, _off, _lim), n in s["read_counts"].items():
            if not fp:
                continue
            file_sessions.setdefault(fp, set()).add(session_id)
            file_reads[fp] = file_reads.get(fp, 0) + n
        for cmd in s["bash_runs"]:
            if cmd:
                cmd_sessions.setdefault(cmd, set()).add(session_id)
    files = sorted(((len(ss), file_reads[fp], fp) for fp, ss in file_sessions.items() if len(ss) >= 2),
                   key=lambda r: (-r[0], -r[1]))
    cmds = sorted(((len(ss), c) for c, ss in cmd_sessions.items() if len(ss) >= 2),
                  key=lambda r: -r[0])
    return files[:TOP_SINKS], cmds[:TOP_SINKS]


def build_report(sessions, root, today, probe_cmds=()):
    lines = ["# Token-waste audit — %s" % today, "",
             "Scope: %d session(s), dir-resolved from git root `%s`." % (len(sessions), root),
             "", FALSE_POSITIVE_HEADER, "", "## Per-session totals", "",
             "| Session / scope | Agents | Workflows | Requests | Output tokens | Cache read | Cache creation | Tool-result chars (~tokens) | Malformed lines skipped |",
             "|---|---|---|---|---|---|---|---|---|"]
    all_results = []
    for s in sessions:
        t = usage_totals(s)
        lines.append("| %s | — | — | %d | %d | %d | %d | %d (~%d) | %d |" % (
            s["file"], t["requests"], t["output_tokens"], t["cache_read"],
            t["cache_creation"], s["tool_result_chars"], s["tool_result_chars"] // 4,
            s["malformed"]))
        if s.get("main_only"):
            continue
        agents = s.get("subagents", [])
        totals = combined_totals(agents)
        workflows = len({a["workflow_id"] for a in agents if a["workflow_id"]})
        chars = sum(a["tool_result_chars"] for a in agents)
        lines.append("| %s / sub-agents | %d | %d | %d | %d | %d | %d | %d (~%d) | %d |" % (
            s["file"], len(agents), workflows, totals["requests"], totals["output_tokens"],
            totals["cache_read"], totals["cache_creation"], chars, chars // 4,
            sum(a["malformed"] for a in agents)))
    flat = transcripts(sessions)
    totals = combined_totals(flat)
    scope = "main only" if all(s.get("main_only") for s in sessions) else "main + sub-agents"
    lines += ["", "Totals (%s): requests %d | output %d | cache read %d | cache creation %d." % (
        scope, totals["requests"], totals["output_tokens"], totals["cache_read"], totals["cache_creation"])]
    for s in sessions:
        if s.get("main_only"):
            lines += ["", "Sub-agents: not parsed (--main-only)"]
            continue
        lines += ["", "## Top %d agents by cache read — %s" % (TOP_SINKS, s["file"]), "",
                  "| Agent | Workflow | Requests | Cache read |", "|---|---|---|---|"]
        agents = sorted(s.get("subagents", []), key=lambda a: (
            -usage_totals(a)["cache_read"], a["agent_id"], a["workflow_id"] or ""))[:TOP_SINKS]
        for agent in agents:
            t = usage_totals(agent)
            lines.append("| %s | %s | %d | %d |" % (
                agent["agent_id"], agent["workflow_id"] or "—", t["requests"], t["cache_read"]))
    lines += ["", "## Images (token estimate; excluded from text size)", "",
              "| Transcript | Images | Estimated tokens | Unknown dimensions (1600 each) |",
              "|---|---|---|---|"]
    image_totals = [0, 0, 0]
    for s in flat:
        images = s.get("images", [])
        counts = [len(images), sum(i["tokens"] for i in images),
                  sum(i["dimensions"] is None for i in images)]
        if images:
            lines.append("| %s | %d | %d (estimate) | %d |" % (
                s.get("label", s["file"]), *counts))
        image_totals = [a + b for a, b in zip(image_totals, counts)]
        all_results.extend(r for r in s["tool_results"] if r.chars)
    lines.append("| Total | %d | %d (estimate) | %d |" % tuple(image_totals))
    lines += ["", "## Top %d largest tool results (tool, target, size estimate)" % TOP_SINKS, "",
              "| Chars (~tokens) | Tool | Target |", "|---|---|---|"]
    for r in sorted(all_results, key=lambda r: (-r.chars, r.name, r.target))[:TOP_SINKS]:
        lines.append("| %d (~%d) | %s | %s |" % (r.chars, r.chars // 4, r.name, r.target))
    per_session, suppressed = selected_findings(sessions, probe_cmds)
    live_n = sum(1 for _s, fs in per_session for _t, f in fs if f.status == LIVE)
    classified_n = sum(1 for _s, fs in per_session for _t, f in fs if f.status == CLASSIFIED)
    lines += ["", "## Findings — LIVE candidates that MAY indicate an FR-26 rule", "",
              "Auto-classified candidates are NOT listed here — they are in their own section "
              "below, so a dismissal neither buries nor inflates this count. Live: %d." % live_n, ""]
    any_finding = False
    for s, found in per_session:
        live = [(t, f) for t, f in found if f.status == LIVE]
        if not live:
            continue
        any_finding = True
        lines += ["### %s" % s.get("label", s["file"]), "",
                  "| Class | Candidate | Label | FR-26 rule it MAY indicate | Why it stayed live | Transcript |",
                  "|---|---|---|---|---|---|"]
        for t, f in live:
            lines.append("| %s | %s | %s | %s | %s | %s |" % (f.cls, f.desc, f.label or "—", f.rule,
                f.evidence or "threshold match", t.get("label", t["file"])))
        for session, cls, count in suppressed:
            if session is s:
                lines += ["", "%s: %d more suppressed (session cap)" % (cls, count)]
        lines.append("")
    if not any_finding:
        lines.append("No LIVE leak-signature candidates above thresholds.")
        lines.append("")
    lines += ["## Auto-classified (dismissed — counted separately, never silently dropped)", "",
              "Each row states the rule that fired AND the evidence that triggered it. "
              "Auto-classified: %d." % classified_n, ""]
    if classified_n:
        for s, found in per_session:
            dismissed = [(t, f) for t, f in found if f.status == CLASSIFIED]
            if not dismissed:
                continue
            lines += ["### %s" % s.get("label", s["file"]), "",
                      "| Class | Candidate | Rule that fired | Evidence that triggered it | Transcript |",
                      "|---|---|---|---|---|"]
            for t, f in dismissed:
                lines.append("| %s | %s | auto-classified: %s | %s | %s |"
                             % (f.cls, f.desc, f.label, f.evidence, t.get("label", t["file"])))
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
                lines.append("| %d | %d | %s |" % (ns, total, snippet(fp, keep_tail=True)))
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
        for s in flat:
            for r in s["tool_results"]:
                if r.chars >= LARGE_TOOL_RESULT_CHARS and is_output_heavy(r.name):
                    body_occ.setdefault(r.digest, []).append((r.chars, r.name, r.target))
                    body_sess.setdefault(r.digest, set()).add(s.get("session_id", s["file"]))
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
