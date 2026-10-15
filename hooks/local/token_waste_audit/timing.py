from .common import SPAN_MIN, TOP_SINKS
from .costing import timestamp

STALL = "stall candidate (FR-27)"
DELEGATION = "delegation wait"
TOOL_WAIT = "tool wait"
CLASSES = (STALL, DELEGATION, TOOL_WAIT)


def span_class(name):
    if name in ("Bash", "PowerShell"):
        return STALL
    return DELEGATION if name in ("Task", "Agent", "advisor") else TOOL_WAIT


def span_seconds(s, names=None):
    out = []
    for name, target, start, end, _seq in s.get("tool_spans", ()):
        begin, finish = timestamp(start), timestamp(end)
        if begin is not None and finish is not None and (names is None or name in names):
            out.append((finish - begin, name, target))
    return out


def wall_time_lens(sessions):
    minutes = SPAN_MIN // 60
    lines = ["## Wall time (FR-27 lens; candidates, not verdicts)", "",
             "Tool calls in flight ≥%d min, from the tool_use line to its result line. Bash/PowerShell = "
             "%s, see `liveness-discipline`; Task/Agent/advisor = %s; other tools = %s. A long span is "
             "never a hang verdict: suites, builds and delegated work can legitimately run long. Top %d "
             "per class per session." % (minutes, STALL, DELEGATION, TOOL_WAIT, TOP_SINKS)]
    for session in sessions:
        rows = [(seconds, span_class(name), name, target, t.get("label", t["file"]))
                for t in [session, *session.get("subagents", [])]
                for seconds, name, target in span_seconds(t) if seconds >= SPAN_MIN]
        lines += ["", "### %s" % session["file"], ""]
        if not rows:
            lines.append("No tool call in flight ≥%d min." % minutes)
            continue
        lines += ["| Class | Minutes | Tool | Target | Transcript |", "|---|---|---|---|---|"]
        totals = []
        for cls in CLASSES:
            hits = sorted((r for r in rows if r[1] == cls), key=lambda r: (-r[0], r[4], r[3]))
            for seconds, _cls, name, target, label in hits[:TOP_SINKS]:
                lines.append("| %s | %.1f | %s | %s | %s |" % (cls, seconds / 60, name, target, label))
            if hits:
                totals.append("- %s: spans %d, %.1f min in flight%s" % (
                    cls, len(hits), sum(r[0] for r in hits) / 60,
                    "; %d more beyond the top %d" % (len(hits) - TOP_SINKS, TOP_SINKS)
                    if len(hits) > TOP_SINKS else ""))
        lines += ["", *totals]
    return lines
