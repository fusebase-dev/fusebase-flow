from datetime import datetime, timedelta, timezone
from decimal import Decimal
import json
from pathlib import Path
import re
import sys

root, temp = [Path(p).resolve() for p in sys.argv[1:3]]
sys.path.insert(0, str(root / "hooks/local"))
from token_waste_audit import parsing
from token_waste_audit.costing import (attribution, advisor_iterations, break_even, context_section,
    cost_section, rewrite_share)
from token_waste_audit.parsing import parse_session, usage_totals
from token_waste_audit.reporting import build_report
from token_waste_audit.timing import DELEGATION, STALL, TOOL_WAIT, span_class, span_seconds

passed = failed = 0
T0 = datetime(2026, 10, 8, tzinfo=timezone.utc)


def check(name, condition):
    global passed, failed
    passed += bool(condition)
    failed += not condition
    print(("PASS: " if condition else "FAIL: ") + "token-waste-classify " + name)


def at(seconds):
    return (T0 + timedelta(seconds=seconds)).isoformat()


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    return path


def parse(name, rows):
    s = parse_session(write(temp / (name + ".jsonl"), rows))
    s.update(agent_id=name, workflow_id=None, label=name + ".jsonl")
    return s


def report(session):
    return build_report([session], root, "fixture")


def section(text, heading, following):
    return text.split(heading, 1)[1].split(following, 1)[0]


temp.mkdir(parents=True, exist_ok=True)

# v5.11 O16: request shape and token counts copied from a local transcript (2026-10-08).
ITERATIONS = [
    {"input_tokens": 2, "output_tokens": 296, "cache_read_input_tokens": 183806,
     "cache_creation_input_tokens": 3392, "type": "message",
     "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 3392}},
    {"input_tokens": 189112, "output_tokens": 7290, "cache_read_input_tokens": 0,
     "cache_creation_input_tokens": 0, "type": "advisor_message", "model": "claude-fable-5-1",
     "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 0}},
    {"input_tokens": 2, "output_tokens": 1645, "cache_read_input_tokens": 187198,
     "cache_creation_input_tokens": 2715, "type": "message",
     "cache_creation": {"ephemeral_5m_input_tokens": 2715, "ephemeral_1h_input_tokens": 0}}]


def advisor_line(seconds, block, advisor_model):
    iterations = json.loads(json.dumps(ITERATIONS))
    iterations[1]["model"] = advisor_model
    return {"type": "assistant", "requestId": "req-adv", "timestamp": at(seconds),
        "message": {"model": "claude-opus-5-5", "content": [block], "usage": {
            "input_tokens": 4, "cache_creation_input_tokens": 6107, "cache_read_input_tokens": 371004,
            "output_tokens": 1941, "iterations": iterations,
            "cache_creation": {"ephemeral_1h_input_tokens": 3392, "ephemeral_5m_input_tokens": 0}}}}


def advisor_rows(advisor_model="claude-fable-5-1"):
    call = {"type": "server_tool_use", "id": "srvtoolu_A", "name": "advisor", "input": {}}
    result = {"type": "advisor_tool_result", "tool_use_id": "srvtoolu_A", "content": {
        "type": "advisor_redacted_result", "encrypted_content": "PRIVATE-ADVISOR-CONTENT"}}
    return [advisor_line(0, {"type": "thinking", "thinking": "", "signature": "PRIVATE-SIGNATURE"}, advisor_model),
            advisor_line(0.031, call, advisor_model), advisor_line(0.031, call, advisor_model),
            advisor_line(106.187, result, advisor_model),
            advisor_line(110, {"type": "text", "text": "PRIVATE-TEXT"}, advisor_model)]


adv = parse("adv", advisor_rows())
adv_cost = attribution([adv])
expected_total = sum(adv_cost["costs"].values()) + Decimal("2.25562")
check("a3-advisor-request-counted-once", len(adv["advisor_calls"]) == 1
      and len(advisor_iterations(adv)) == 1
      and usage_totals(adv) == {"requests": 1, "output_tokens": 1941, "cache_read": 371004,
                                "cache_creation": 6107})
check("a3-advisor-priced-at-iteration-model", adv_cost["advisor_cost"] == Decimal("2.25562")
      and adv_cost["advisor_tokens"] == 196402 and adv_cost["total"] == expected_total
      and not adv_cost["advisor_unpriced"])
adv_report = report(adv)
check("a3-advisor-cost-row-and-totals", "| main | advisor | 196402 | $2.255620 |" in adv_report
      and "advisor iterations 1 (output 7290; not in top-level usage)." in adv_report)
waits = span_seconds(adv, ("advisor",))
check("a3-advisor-wait-observed", len(waits) == 1 and abs(waits[0][0] - 106.156) < 1e-3
      and "| adv.jsonl | main | 1 | 1 | 1.8 | 1.8 |" in adv_report
      and "(observed on one local transcript shape)" in adv_report)
check("a3-advisor-model-row", "| adv.jsonl | main | claude-fable-5-1 | 1 | 189112 | 7290 | $2.255620 |"
      in adv_report)
check("a3-advisor-section-placement", adv_report.index("## Cache rewrite after expiry")
      < adv_report.index("## Advisor calls") < adv_report.index("## Per-session totals"))
check("a3-advisor-private-content-absent", all(value not in adv_report for value in (
    "PRIVATE-ADVISOR-CONTENT", "PRIVATE-SIGNATURE", "PRIVATE-TEXT")))
odd = parse("adv-unknown", advisor_rows("unknown-advisor-model"))
odd_cost = attribution([odd])
odd_report = report(odd)
check("a3-advisor-unknown-model-unpriced", odd_cost["advisor_cost"] == 0
      and odd_cost["advisor_tokens"] == 196402
      and odd_cost["advisor_unpriced"] == {"unknown-advisor-model": 1}
      and "1 advisor iterations unpriced (model unknown-advisor-model) — tokens only; excluded from USD"
      in odd_report and "| unknown-advisor-model | 1 | 189112 | 7290 | unpriced |" in odd_report)
host = parse("host", [{"type": "assistant", "requestId": "h", "timestamp": at(0), "message": {
    "model": "claude-opus-5-5", "content": [], "usage": {"output_tokens": 1}}}])
host["subagents"] = [parse("agent-adv", advisor_rows())]
host_cost = "\n".join(cost_section([host]))
check("a3-advisor-sub-agent-scope", "| sub-agents | advisor | 196402 | $2.255620 |" in host_cost
      and "| main | advisor | 0 | $0.000000 |" in host_cost)
check("a3-advisor-none-says-so", "No advisor calls or advisor iterations in the parsed transcripts."
      in report(parse("plain", [{"type": "assistant", "requestId": "p", "timestamp": at(0), "message": {
          "model": "claude-opus-5-5", "content": [], "usage": {"output_tokens": 1}}}])))

source = Path(parsing.__file__).read_text(encoding="utf-8")
adv_path = temp / "adv.jsonl"


def mutant_total(anchor, replacement):
    if source.count(anchor) != 1:
        return None
    namespace = {"__package__": "token_waste_audit", "__name__": "token_waste_audit.mutant"}
    exec(compile(source.replace(anchor, replacement), "parsing-mutant", "exec"), namespace)
    return attribution([namespace["parse_session"](adv_path)])["total"]


ignored = mutant_total('it.get("type") == "advisor_message"', 'False')
check("a3-mutation-ignored-iteration-fails-totals", ignored is not None and ignored != expected_total)
per_line = mutant_total('s["advisor_by_request"][request_key] = advisor',
                        's["advisor_by_request"][(request_key, seq)] = advisor')
check("a3-mutation-per-line-iterations-fails-totals", per_line is not None and per_line != expected_total)


def span(tid, name, start, seconds, data=None, stamped=True):
    use = {"type": "assistant", "requestId": "r-" + tid, "timestamp": at(start), "message": {
        "model": "claude-opus-5-5", "usage": {"output_tokens": 1},
        "content": [{"type": "tool_use", "id": tid, "name": name, "input": data or {"command": "fixture-" + tid}}]}}
    done = {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": tid, "content": "ok"}]}}
    if stamped:
        done["timestamp"] = at(start + seconds)
    return [use, done]


check("a3-wall-classes", [span_class(n) for n in ("Bash", "PowerShell", "Task", "Agent", "advisor", "Read")]
      == [STALL, STALL, DELEGATION, DELEGATION, DELEGATION, TOOL_WAIT])
wall = parse("wall", span("bash40", "Bash", 0, 2400) + span("task40", "Task", 0, 2400, {"description": "x"})
             + span("agent15", "Agent", 0, 900, {"description": "x"}) + span("ps600", "PowerShell", 0, 600)
             + span("bash594", "Bash", 0, 594) + span("read12", "Read", 0, 720, {"file_path": "/fixture-read"})
             + span("nots", "Bash", 0, 3000, stamped=False))
wall_report = report(wall)
lens = section(wall_report, "## Wall time (FR-27 lens; candidates, not verdicts)", "## Findings")
check("a3-wall-bash-40min-stall-candidate", "| stall candidate (FR-27) | 40.0 | Bash | fixture-bash40 | wall.jsonl |"
      in lens)
check("a3-wall-task-40min-delegation-not-stall", "| delegation wait | 40.0 | Task | Task | wall.jsonl |" in lens
      and "| stall candidate (FR-27) | 40.0 | Task |" not in lens
      and "| delegation wait | 15.0 | Agent | Agent | wall.jsonl |" in lens)
check("a3-wall-span-min-inclusive", "| stall candidate (FR-27) | 10.0 | PowerShell | fixture-ps600 |" in lens
      and "fixture-bash594" not in lens)
check("a3-wall-other-tool-wait", "| tool wait | 12.0 | Read | /fixture-read | wall.jsonl |" in lens)
check("a3-wall-missing-timestamp-skipped", "fixture-nots" not in lens)
check("a3-wall-never-hang-verdict", "A long span is never a hang verdict" in lens
      and len(re.findall(r"(?i)\bhang", lens)) == 1)
check("a3-wall-section-placement", wall_report.index("## Top 10 largest tool results")
      < wall_report.index("## Wall time (FR-27 lens") < wall_report.index("## Findings"))
check("a3-wall-class-summary", "- stall candidate (FR-27): spans 2, 50.0 min in flight" in lens
      and "- delegation wait: spans 2, 55.0 min in flight" in lens)
flood = parse("wall-flood", [row for i in range(12) for row in span("b%02d" % i, "Bash", 0, 60 * (11 + i))])
flood_lens = section(report(flood), "## Wall time", "## Findings")
check("a3-wall-top10-per-class", flood_lens.count("| stall candidate (FR-27) |") == 10
      and "- stall candidate (FR-27): spans 12, 198.0 min in flight; 2 more beyond the top 10" in flood_lens
      and "fixture-b00" not in flood_lens and "fixture-b01" not in flood_lens)
nested = parse("wall-main", [])
nested["subagents"] = [parse("agent-w", span("sub", "Bash", 0, 1200))]
check("a3-wall-names-transcript", "| stall candidate (FR-27) | 20.0 | Bash | fixture-sub | agent-w.jsonl |"
      in section(report(nested), "## Wall time", "## Findings")
      and "No tool call in flight ≥10 min." in section(report(adv), "## Wall time", "## Findings"))


# decision F; premise review F12
def writes(rid, seconds, tokens, model, long=False, read=0):
    return {"type": "assistant", "requestId": rid, "timestamp": at(seconds), "message": {
        "model": model, "content": [], "usage": {
            "cache_creation_input_tokens": tokens, "cache_read_input_tokens": read,
            "input_tokens": 0, "output_tokens": 0, "cache_creation": {
                "ephemeral_5m_input_tokens": 0 if long else tokens,
                "ephemeral_1h_input_tokens": tokens if long else 0}}}}


def agent(name, first, second, gap_minutes, model="claude-opus-5-5", long=False):
    return parse(name, [writes("a", 0, first, model, long), writes("b", 60 * gap_minutes, second, model, long)])


def share_text(name, agents, main_only=False):
    session = parse(name, [])
    session.update(subagents=agents, main_only=main_only)
    return "\n".join(context_section([session]))


thresholds = {m: ("%g" % break_even(m)[0], "%.1f" % (100 * break_even(m)[1])) for m in (
    "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5", "claude-fable-5-1", "claude-haiku-4-5")}
check("a3-share-break-even-per-model", thresholds == {
    "claude-opus-5-5": ("0.05", "38.5"), "claude-opus-5": ("0.1", "39.5"), "claude-sonnet-5": ("0.1", "39.5"),
    "claude-fable-5-1": ("0.025", "38.0"), "claude-haiku-4-5": ("0.1", "39.5")})
LINE = ("Sub-agent rewrites at 5-60 min gaps (share.jsonl): 100000 of 300000 cache-write tokens (33.3%); "
        "a 1h TTL pays above 38.5% at claude-opus-5-5 rates (0.75/(2 - r), r = cache-read/input = 0.05); "
        "rewrites count only the prefix cached before the gap; "
        "lower bound: rewrites under 100k creation not counted (token-economy § Measure it, operator-lever table)")
check("a3-share-single-model-line", LINE in share_text("share", [agent("s1", 100_000, 200_000, 6)]))
grown = rewrite_share([agent("grown", 100_000, 200_000, 6)])
check("a3-share-new-turn-tokens-not-avoidable", grown["rewritten"] == 100_000
      and grown["cost_1h"] > grown["cost_5m"] and (grown["cost_1h"], grown["cost_5m"]) == (Decimal("1.62"), Decimal("1.5")))
shared = rewrite_share([parse("shared", [writes("a", 0, 100_000, "claude-opus-5-5", read=30_000),
                                         writes("b", 360, 150_000, "claude-opus-5-5", read=20_000)])])
check("a3-share-prefix-less-own-read", shared["rewritten"] == 110_000)
check("a3-share-gap-over-hour-excluded", "0 of 300000 cache-write tokens (0.0%)"
      in share_text("share-70", [agent("s70", 100_000, 200_000, 70)]))
check("a3-share-under-100k-excluded", "0 of 199999 cache-write tokens (0.0%)"
      in share_text("share-small", [agent("ssmall", 100_000, 99_999, 6)]))
check("a3-share-1h-writes-bound", "1h writes present, so rewrites they avoided are not counted either"
      in share_text("share-1h", [agent("s1h", 100_000, 200_000, 70, long=True)]))
check("a3-share-mixed-cost-weighted", "200000 of 500000 cache-write tokens (40.0%); mixed models, "
      "cost-weighted over priced writes: 1h TTL $2.670000 vs 5m $2.750000 (1h pays only when lower; "
      "0 unpriced requests excluded)" in share_text("share-mixed", [agent("m1", 100_000, 200_000, 6),
          agent("m2", 100_000, 100_000, 6, model="claude-opus-5")]))
check("a3-share-one-priced-model-keeps-threshold", "(33.3%); a 1h TTL pays above 39.5% at claude-opus-5 rates "
      "(0.75/(2 - r), r = cache-read/input = 0.1); share includes 2 requests of unpriced models"
      in share_text("share-partial", [agent("p1", 100_000, 200_000, 6, model="claude-opus-5"),
          agent("p2", 100_000, 200_000, 6, model="claude-haiku-4-5-20251001")]))
above = rewrite_share([agent("above", 610_000, 390_000, 6)])
below = rewrite_share([agent("below", 620_000, 380_000, 6)])
check("a3-share-threshold-counts-replacement-reads", above["cost_1h"] < above["cost_5m"]
      and below["cost_1h"] > below["cost_5m"] and below["rewritten"] / below["written"] > 0.375)
check("a3-share-no-writes", "Sub-agent rewrites at 5-60 min gaps (share-none.jsonl): 0 of 0 cache-write tokens "
      "(no sub-agent cache writes)" in share_text("share-none", []))
check("a3-share-main-only-omitted", "Sub-agent rewrites at 5-60 min gaps"
      not in share_text("share-main-only", [agent("smo", 100_000, 200_000, 6)], main_only=True))
check("a3-share-unknown-models", "break-even unpriced (unknown models)"
      in share_text("share-unknown", [agent("su", 100_000, 200_000, 6, model="unknown")]))

skill = (root / "flow-skills/token-economy/SKILL.md").read_text(encoding="utf-8")
measure = skill.split("## Measure it\n", 1)[1].split("## Growth rule\n", 1)[0]
check("a3-doc-skill-measure-rows", all(text in measure for text in (
    "| Advisor calls |", "`advisor_message`", "priced at the iteration's own `model`",
    "| Wall time |", "stall candidate (FR-27", "delegation wait", "never a hang verdict",
    "Sub-agent rewrites at 5-60 min gaps", "0.75/(2 - r)")))
command = (root / "hooks/local/fusebase-flow-overlays/commands/token-waste-audit.md").read_text(encoding="utf-8")
check("a3-doc-command-sections", all(text in command for text in (
    "**Advisor calls**", "**Wall time (FR-27 lens; candidates, not verdicts)**",
    "Sub-agent rewrites at 5-60 min gaps", "0.75/(2 - r)")))
print("[token-waste-a3-native] %d/%d PASS" % (passed, passed + failed))
raise SystemExit(bool(failed))
