import base64
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import subprocess
import sys

root, temp = [Path(p).resolve() for p in sys.argv[1:3]]
sys.path.insert(0, str(root / "hooks/local"))
from token_waste_audit import classification as cl
from token_waste_audit.common import FALSE_POSITIVE_HEADER
from token_waste_audit.costing import (COST_LABEL, attribution, cache_rewrites,
    residency, residency_finding, polling_cost)
from token_waste_audit.parsing import parse_selected_session, parse_session
from token_waste_audit.reporting import build_report

passed = failed = 0


def check(name, condition):
    global passed, failed
    passed += bool(condition)
    failed += not condition
    print(("PASS: " if condition else "FAIL: ") + "token-waste-classify " + name)


def tool(tid, name, data):
    return {"type": "tool_use", "id": tid, "name": name, "input": data}


def assistant(rid, minute=0, model="claude-opus-5-5", read=0, creation=0,
              short=0, long=0, inp=0, out=0, tools=()):
    start = datetime(2026, 10, 8, tzinfo=timezone.utc) + timedelta(minutes=minute)
    return {"type": "assistant", "requestId": rid, "timestamp": start.isoformat(),
        "message": {"model": model, "content": list(tools), "usage": {
            "cache_read_input_tokens": read, "cache_creation_input_tokens": creation,
            "cache_creation": {"ephemeral_5m_input_tokens": short,
                               "ephemeral_1h_input_tokens": long},
            "input_tokens": inp, "output_tokens": out}}}


def result(tid, body):
    return {"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": tid, "content": body}]}}


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    return path


def parse(name, rows):
    s = parse_session(write(temp / (name + ".jsonl"), rows))
    s.update(agent_id=name, workflow_id=None)
    return s


def selected(session, selector=cl.selected_findings):
    return selector([session])[0][0][1]


temp.mkdir(parents=True, exist_ok=True)
models = ("claude-opus-5-5", "claude-opus-5", "claude-sonnet-5",
          "claude-fable-5-1", "claude-haiku-4-5")
expected = [Decimal(v) for v in ("0.20", "0.50", "0.20", "0.25", "0.10")]
mixed_path = write(temp / "mixed/sid.jsonl", [assistant(str(i), model=model,
    read=1_000_000, creation=350_000, short=100_000, long=200_000, inp=1000, out=100)
    for i, model in enumerate(models[:3])])
for i, model in enumerate(models[3:]):
    write(mixed_path.parent / ("sid/subagents/agent-%d.jsonl" % i), [assistant("sub",
        model=model, read=1_000_000, creation=350_000, short=100_000, long=200_000,
        inp=1000, out=100)])
mixed = parse_selected_session(mixed_path)
main = attribution([mixed])
sub = attribution(mixed["subagents"])
check("a2-mixed-main-exact-category-costs", main["costs"] == {
    "cache read": Decimal("0.9"), "cache write 5m": Decimal("2.0625"),
    "cache write 1h": Decimal("4.4"), "uncached input": Decimal("0.011"),
    "output": Decimal("0.0055")})
check("a2-mixed-sub-exact-category-costs", sub["costs"] == {
    "cache read": Decimal("0.35"), "cache write 5m": Decimal("2.0625"),
    "cache write 1h": Decimal("4.4"), "uncached input": Decimal("0.011"),
    "output": Decimal("0.0055")})
for i, model in enumerate(models):
    s = parse("rate-%d" % i, [assistant("rate", model=model, read=1_000_000)])
    check("a2-model-rate-%d" % i, attribution([s])["costs"]["cache read"] == expected[i])
unsplit = parse("unsplit", [assistant("u", creation=500_000)])
check("a2-unsplit-creation-priced-5m", attribution([unsplit])["costs"]["cache write 5m"] == Decimal("2.5")
      and attribution([unsplit])["costs"]["cache write 1h"] == 0)
unknown = parse("unknown", [assistant("known", read=1_000_000),
    assistant("unknown", model="PRIVATE-UNKNOWN-MODEL", read=8_000_000, creation=1_000_000),
    assistant("synthetic", model="<synthetic>", read=9_000_000)])
unknown_report = build_report([unknown], root, "fixture")
check("a2-unknown-token-only-no-dollar", attribution([unknown])["tokens"]["cache read"] == 18_000_000
      and attribution([unknown])["total"] == Decimal("0.2")
      and unknown_report.count("PRIVATE-UNKNOWN-MODEL") == 1
      and "1 requests unpriced (model PRIVATE-UNKNOWN-MODEL)" in unknown_report
      and "1 requests unpriced (model <synthetic>)" in unknown_report)
report = build_report([mixed], root, "fixture")
check("a2-cost-section-first-and-label", report.index("## Cost attribution") < report.index("## Context residency")
      < report.index("## Per-session totals") and COST_LABEL in report)
check("a2-cost-shares-and-ranked-categories", "| main | cache write 1h | 600000 | $4.400000 | 31.0% |" in report
      and report.index("| main | cache write 1h") < report.index("| main | uncached input"))
env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONDONTWRITEBYTECODE="1")
cli = [sys.executable, str(root / "hooks/local/token-waste-audit.py"), "--last", "1", "--dir", str(mixed_path.parent)]
run = subprocess.run(cli, cwd=temp, env=env, capture_output=True, encoding="utf-8", timeout=30)
check("a2-stdout-cost-first", run.returncode == 0 and run.stdout.startswith("## Cost attribution\n")
      and COST_LABEL in run.stdout and "| sub-agents | cache write 1h" in run.stdout)
run = subprocess.run(cli + ["--main-only"], cwd=temp, env=env, capture_output=True, encoding="utf-8", timeout=30)
check("a2-main-only-cost-scope", run.returncode == 0 and "| sub-agents |" not in run.stdout
      and "Sub-agents: not parsed (--main-only)" in run.stdout)
workhub = parse("workhub", [assistant("main", read=100_000)])
workhub["subagents"] = [parse("agent-peak", [assistant("p1", read=550_000, creation=40_000,
    short=40_000, inp=10_000), assistant("p2", read=100_000, inp=20_000)])]
peak = workhub["subagents"][0]
check("a2-context-peak-average-requests", residency(peak)["peak"] == 600_000
      and residency(peak)["average"] == 360_000 and residency(peak)["requests"] == 2)
finding = residency_finding(workhub)
check("a2-residency-workhub-fires-once", finding is not None
      and "1 transcripts peaked ≥500k and hold 86.7% of cache-read cost" == finding.desc
      and finding.cost == Decimal("0.13")
      and finding.rule == "FR-26 TE-19 — bounded residency: fresh worker per task group / rotate at milestones (token-economy)"
      and sum(f.cls == "context-residency" for _, f in selected(workhub)) == 1)
small = parse("small", [assistant(str(i), read=110_000, creation=9000, short=9000, inp=1000)
                       for i in range(50)])
check("a2-residency-50-at-120k-silent", residency(small)["average"] == 120_000
      and residency_finding(small) is None)
below_share = parse("low-share", [assistant("main", read=400_000) for _ in [0]])
below_share["subagents"] = [parse("brief-peak", [assistant("p", read=100_000, creation=400_000)])]
check("a2-residency-share-threshold", residency_finding(below_share) is None)
exact = parse("exact-peak", [assistant("a", read=250_000)])
exact["subagents"] = [parse("threshold-agent", [assistant("b", read=250_000, creation=250_000)])]
check("a2-residency-inclusive-thresholds", residency_finding(exact) is not None
      and "50.0%" in residency_finding(exact).desc)
comp = parse("comp", [assistant("c"), {"type": "system", "subtype": "compact_boundary",
    "compactMetadata": {"trigger": "auto"}}, {"type": "user", "isCompactSummary": True,
    "message": {"content": "PRIVATE-COMPACT-SUMMARY"}}])
check("a2-compaction-count-one-event", residency(comp)["compactions"] == 1)
context_report = build_report([workhub, comp], root, "fixture")
check("a2-context-table-peak-average-cost", "| agent-peak.jsonl | $0.130000 | 600000 | 360000.0 | 2 | 0 |" in context_report
      and "| comp.jsonl | $0.000000 | 0 | 0.0 | 1 | 1 |" in context_report)
many = parse("many", [assistant("main", read=10)])
many["subagents"] = [parse("top-%02d" % i, [assistant("r", model="claude-opus-5",
    read=1000 + i)]) for i in range(12)]
top = build_report([many], root, "fixture").split("## Context residency")[1].split("## Cache rewrite after expiry")[0]
check("a2-context-top-ten-price-ranked", sum(line.startswith("| ") for line in top.splitlines()) == 11
      and "top-11.jsonl" in top and "top-00.jsonl" not in top and "many.jsonl | $" not in top)

ttl_cases = [("1h-70", 70, 0, 500_000, 1), ("1h-20", 20, 0, 500_000, 0),
    ("5m-6", 6, 200_000, 0, 1), ("5m-small", 6, 50_000, 0, 0),
    ("1h-boundary", 60, 0, 500_000, 0), ("5m-boundary", 5, 200_000, 0, 0),
    ("5m-minimum", 6, 100_000, 0, 1), ("mixed-ttl", 20, 100_000, 100_000, 0)]
for name, minute, short, long, count in ttl_cases:
    s = parse(name, [assistant("prior"), assistant("next", minute, creation=short + long, short=short, long=long)])
    rows = cache_rewrites(s)
    check("a2-ttl-" + name, len(rows) == count)
    if name == "1h-70":
        hour = s
        check("a2-ttl-exact-1h-cost", rows[0]["cost"] == Decimal("4") and rows[0]["tokens"] == 500_000)
    if name == "5m-6":
        short_session = s
        check("a2-ttl-exact-5m-cost", rows[0]["cost"] == Decimal("1"))
no_ttl = parse("no-ttl", [assistant("a"), assistant("b", 70, creation=500_000)])
check("a2-ttl-unknown-skip", not cache_rewrites(no_ttl))
missing = assistant("b", 70, creation=500_000, long=500_000)
missing.pop("timestamp")
check("a2-ttl-missing-time-skip", not cache_rewrites(parse("no-time", [assistant("a"), missing])))
stream = parse("stream", [assistant("a", 0), assistant("a", 69, out=1),
    assistant("b", 70, creation=500_000, long=500_000)])
check("a2-stream-first-time-last-usage-dedup", len(stream["requests_by_id"]) == 2
      and cache_rewrites(stream)[0]["gap"] == 4200
      and stream["requests_by_id"]["a"]["usage"]["output_tokens"] == 1)
no_id = assistant(None, 60)
interleaved = parse("interleaved", [assistant("a"), no_id,
    assistant("b", 70, creation=500_000, long=500_000)])
check("a2-ttl-no-id-interleaved-order", not cache_rewrites(interleaved)
      and residency(interleaved)["requests"] == 3)
real_rows = [assistant("prior", read=200_000),
    assistant("next", 70.5, read=100_000, creation=500_000, long=500_000)]
synthetic = parse("synthetic-interleaved", [real_rows[0],
    assistant(None, 70, model="<synthetic>"), real_rows[1]])
check("a2-ttl-synthetic-interleaved", cache_rewrites(synthetic) == [
    {"tokens": 500_000, "gap": 4230, "ttl": 3600, "cost": Decimal("4")}]
      and sum(f.cls == "cache-rewrite" for _, f in selected(synthetic)) == 1)
check("a2-residency-synthetic-excluded", residency(synthetic)
      == residency(parse("synthetic-free", real_rows))
      and residency(synthetic)["requests"] == 2
      and residency(synthetic)["peak"] == 600_000
      and residency(synthetic)["average"] == 400_000)
check("a2-synthetic-still-unpriced", attribution([synthetic])["unpriced"]["<synthetic>"] == 1
      and "1 requests unpriced (model <synthetic>)" in build_report([synthetic], root, "fixture"))
hour["subagents"] = [short_session]
ttl_report = build_report([hour], root, "fixture")
check("a2-cache-rewrite-te20-rule", ttl_report.count(
    "FR-26 TE-20 — wait under the cache TTL / record-then-read (token-economy)") == 2
    and "FR-26 — wait under cache TTL / record-then-read (token-economy)" not in ttl_report)
check("a2-rewrite-summary-main-sub-split", "| 1h-70.jsonl | main | 1 | 500000 | $4.000000 | 0 |" in ttl_report
      and "| 1h-70.jsonl | sub-agents | 1 | 200000 | $1.000000 | 0 |" in ttl_report)
flood = parse("rewrite-flood", [assistant(str(i), 70 * i, creation=100_000 + 1000 * i,
                                       long=100_000 + 1000 * i) for i in range(13)])
flood_report = build_report([flood], root, "fixture")
check("a2-cache-rewrite-session-cap-and-full-summary", flood_report.count("| cache-rewrite |") == 10
      and "cache-rewrite: 2 more suppressed (session cap)" in flood_report
      and "| rewrite-flood.jsonl | main | 12 | 1278000 | $10.224000 | 0 |" in flood_report)
selected_flood, suppressed = cl.selected_findings([flood, flood])
check("a2-cache-rewrite-cap-resets-per-session", len(suppressed) == 2
      and all(sum(f.cls == "cache-rewrite" for _, f in fs) == 10 for _, fs in selected_flood))
unknown_ttl = parse("unknown-ttl", [assistant("a"), assistant("b", 70, model="unknown",
                                                        creation=500_000, long=500_000)])
check("a2-cache-rewrite-unpriced-retained", len(cache_rewrites(unknown_ttl)) == 1
      and cache_rewrites(unknown_ttl)[0]["cost"] is None
      and "| unknown-ttl.jsonl | main | 1 | 500000 | unpriced | 1 |" in build_report([unknown_ttl], root, "fixture"))

poll_rows = [assistant(str(i), model=model, read=100_000, creation=20_000, short=20_000, inp=5000,
    tools=[tool("p%d" % i, "Bash", {"command": "curl polling.invalid"})])
    for i, model in enumerate(("claude-opus-5-5", "claude-opus-5", "claude-sonnet-5", "unknown"))]
poll_rows.append(assistant("0", model="claude-opus-5-5", read=100_000, creation=20_000,
                           short=20_000, inp=5000))
poll = parse("polling", poll_rows)
wakes, tokens, cost = polling_cost(poll, "curl polling.invalid")
check("a2-polling-wakes-context-price-dedup", (wakes, tokens, cost) == (4, 500_000, Decimal("0.1125")))
poll_report = build_report([poll], root, "fixture")
check("a2-polling-row-displays-cost-and-wakes", "$0.112500; 4 wakes; context sum 500000 tokens (cache-read rate estimate)" in poll_report)
order = parse("ordering", [assistant("start", tools=[tool("small", "Read", {"file_path": "/small"})]),
    result("small", "PRIVATE-BODY-" * 2000), assistant("expensive", 70, creation=500_000, long=500_000),
    assistant("unpriced", 71, model="unknown", tools=[tool("u", "Read", {"file_path": "/unknown"})]),
    result("u", "PRIVATE-UNKNOWN-BODY-" * 2000)])
ordered = [f for _, f in selected(order)]
check("a2-live-order-heavy-before-light-unpriced-last", [f.cls for f in ordered] == ["cache-rewrite", "large-output", "large-output"]
      and ordered[0].cost == 4 and ordered[1].cost == Decimal("0.026") and ordered[-1].cost is None)
check("a2-report-order-and-cost-signal-header", build_report([order], root, "fixture").index("| cache-rewrite |")
      < build_report([order], root, "fixture").index("| large-output |")
      and "context-residency/cache-rewrite are cost signals, not proof that the work was unnecessary" in FALSE_POSITIVE_HEADER)
check("a2-report-private-content-absent", all(value not in build_report([order, comp], root, "fixture")
      for value in ("PRIVATE-BODY-", "PRIVATE-UNKNOWN-BODY-", "PRIVATE-COMPACT-SUMMARY")))

cap_rows = []
for i in range(12):
    for j in range(3):
        tid = "read-%d-%d" % (i, j)
        cap_rows += [assistant(tid, tools=[tool(tid, "Read", {"file_path": "/read-%d" % i})]),
                     result(tid, "same-small-body")]
    for j in range(2):
        tid = "image-%d-%d" % (i, j)
        data = base64.b64encode(("PRIVATE-IMAGE-%d" % i).encode()).decode()
        cap_rows += [assistant(tid, tools=[tool(tid, "Read", {"file_path": "/image-%d.png" % i})]),
            result(tid, [{"type": "image", "source": {"type": "base64", "data": data}}])]
        tid = "write-%d-%d" % (i, j)
        cap_rows += [assistant(tid, tools=[tool(tid, "Write", {
            "file_path": "/write-%d" % i, "content": "W" * 10000})])]
    tid = "large-%d" % i
    cap_rows += [assistant(tid, tools=[tool(tid, "Read", {"file_path": "/large-%d" % i})]),
                 result(tid, "L" * (20000 + i))]
cap = parse("cap-retention", cap_rows)
cap_report = build_report([cap], root, "fixture")
for cls in ("image-reread", "re-read", "rewrite"):
    check("a2-session-cap-retains-" + cls, sum(f.cls == cls for _, f in selected(cap)) == 12
          and cap_report.count("| %s |" % cls) == 12)
    source = Path(cl.__file__).read_text(encoding="utf-8")
    anchor = 'f.cls not in ("large-output", "repeat-output", "cache-rewrite")'
    assert source.count(anchor) == 1
    namespace = {"__package__": "token_waste_audit"}
    exec(compile(source.replace(anchor, anchor[:-1] + ', "%s")' % cls), "cap-mutant", "exec"), namespace)
    check("a2-cap-mutation-hiding-" + cls, sum(f.cls == cls for _, f in selected(cap,
          namespace["selected_findings"])) != 12)
check("a2-cap-retention-flood-active", cap_report.count("| large-output |") == 10
      and "large-output: 2 more suppressed (session cap)" in cap_report)
for name, doc in (("skill", root / "flow-skills/token-economy/SKILL.md"),
                  ("command", root / "hooks/local/fusebase-flow-overlays/commands/token-waste-audit.md")):
    body = doc.read_text(encoding="utf-8")
    if name == "skill":
        body = body.split("## Measure it")[1].split("## Growth rule")[0]
    check("a2-doc-%s-cost-sections-and-cap" % name, all(text in body for text in (
        "2026-10", "subscription billing differs", "context-residency", "cache-rewrite",
        "Polling", "unpriced", "N more suppressed (session cap)")))
check("a2-shell-checks-neutral-names", "round1-" not in (
      root / "hooks/tests/test-token-waste-classify.sh").read_text(encoding="utf-8"))
print("[token-waste-a2-native] %d/%d PASS" % (passed, passed + failed))
raise SystemExit(bool(failed))
