from .common import DEFAULT_LAST, CLASSIFIED, git_root, locate_transcript_dir, munge
from .parsing import parse_selected_session, usage_totals, transcripts
from .classification import selected_findings
from .costing import cost_section, context_section
from .reporting import (build_report, fallback_summary, terminal_state, TERMINAL_NO_DATA,
                        combined_totals)
import argparse
import datetime
import sys
from pathlib import Path

def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="FR-26 token-waste audit (deterministic transcript parser)")
    ap.add_argument("--last", type=int, default=DEFAULT_LAST, metavar="N",
                    help="audit the N most recently modified sessions (default %d)" % DEFAULT_LAST)
    ap.add_argument("--dir", default=None, metavar="PATH",
                    help="transcript directory override (default: auto-locate under ~/.claude/projects)")
    ap.add_argument("--main-only", action="store_true",
                    help="exclude sub-agent and workflow-agent transcripts (old scope)")
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

    sessions = [parse_selected_session(p, args.main_only) for p in files[: max(args.last, 1)]]
    report = build_report(sessions, root, today, probe_cmds)

    report_path = root / "state" / "audit" / ("token-waste-audit-%s.md" % today)
    try:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(report, encoding="utf-8", newline="\n")
        wrote = str(report_path)
    except OSError as exc:
        wrote = "(write failed: %s)" % exc

    print("\n".join(cost_section(sessions)))
    print("\n".join(context_section(sessions)))
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
        if args.main_only:
            print("Sub-agents: not parsed (--main-only)")
            continue
        agents = s.get("subagents", [])
        t = combined_totals(agents)
        workflows = len({a["workflow_id"] for a in agents if a["workflow_id"]})
        print("Sub-agents: %d | workflows: %d | requests: %d | output: %d | cache read: %d | cache creation: %d" % (
            len(agents), workflows, t["requests"], t["output_tokens"], t["cache_read"], t["cache_creation"]))
    flat = transcripts(sessions)
    images = [image for s in flat for image in s["images"]]
    print("Images: %d | tokens: %d (estimate)" % (len(images), sum(i["tokens"] for i in images)))
    selected, suppressed = selected_findings(sessions, probe_cmds)
    for _session, found in selected:
        for s, f in found:
            if f.status == CLASSIFIED:
                dismissed.append((s.get("label", s["file"]), f))
            else:
                counts[f.cls] = counts.get(f.cls, 0) + 1
    print("")
    print("LIVE candidates (MAY indicate -- see report header for false-positive classes): "
          "re-read %d | polling %d | whole-file-rewrite %d | large-output %d | repeat-output %d | image-reread %d | context-residency %d | cache-rewrite %d" % (
              counts["re-read"], counts["polling"], counts["rewrite"],
              counts["large-output"], counts["repeat-output"], counts.get("image-reread", 0),
              counts.get("context-residency", 0), counts.get("cache-rewrite", 0)))
    for session, cls, count in suppressed:
        print("%s | %s: %d more suppressed (session cap)" % (session["file"], cls, count))
    # AC17/AC18: dismissals are counted apart from live findings and every one prints the
    # rule that fired AND its evidence. A silent dismissal is a false negative nobody sees.
    print("Auto-classified (dismissed, NOT counted above): %d" % len(dismissed))
    for fname, f in dismissed:
        print("  - %s | %s | auto-classified: %s | evidence: %s" % (fname, f.cls, f.label, f.evidence))
    print("")
    print(terminal_state(sessions, sum(counts.values()), len(dismissed)))
    return 0
