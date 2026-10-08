import base64
import json
import os
from pathlib import Path
import random
import re
import struct
import subprocess
import sys
import zlib

root, temp = map(Path, sys.argv[1:3])
sys.path.insert(0, str(root / "hooks/local"))
from token_waste_audit.classification import session_findings
from token_waste_audit.common import snippet, tool_target
from token_waste_audit.images import image_metadata
from token_waste_audit.parsing import parse_selected_session, parse_session, transcripts
from token_waste_audit.reporting import build_report, combined_totals, cross_session_aggregate

passed = failed = 0


def check(name, condition):
    global passed, failed
    if condition:
        passed += 1
        print("PASS: token-waste-classify " + name)
    else:
        failed += 1
        print("FAIL: token-waste-classify " + name)


def assistant(rid, output, read, creation, tools=(), timestamp="2026-10-08T00:00:00Z"):
    return {"type": "assistant", "requestId": rid, "timestamp": timestamp,
            "message": {"model": "fixture-model", "content": list(tools),
                        "usage": {"output_tokens": output, "cache_read_input_tokens": read,
                                  "cache_creation_input_tokens": creation,
                                  "cache_creation": {"ephemeral_5m_input_tokens": creation,
                                                     "ephemeral_1h_input_tokens": 0}}}}


def tool(tid, name, tin):
    return {"type": "tool_use", "id": tid, "name": name, "input": tin}


def result(tid, content):
    return {"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": tid, "content": content}]}}


def write(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")
    return path


def image(data):
    return {"type": "image", "source": {"type": "base64", "media_type": "image/png",
                                          "data": base64.b64encode(data).decode("ascii")}}


def png(width, height, seed):
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data)))
    pixels = random.Random(seed).randbytes(600 * 1024)
    pixels += bytes(width * height * 3 - len(pixels))
    scanlines = b"".join(b"\0" + pixels[row:row + width * 3]
                         for row in range(0, len(pixels), width * 3))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


def image_rows(blobs):
    rows = []
    for index, blob in enumerate(blobs):
        tid = "image-%d" % index
        rows += [assistant(tid, 1, 0, 0, [tool(tid, "Read", {"file_path": "/same/capture.png"})]),
                 result(tid, [image(blob)])]
    return rows


temp.mkdir(parents=True, exist_ok=True)
session = temp / "selected" / "sid.jsonl"
write(session, [assistant("main", 1, 1, 1), assistant("main", 11, 100, 20)])
subdir = session.parent / "sid/subagents"
commands = [tool("bash%d" % i, "Bash", {"command": "curl https://fixture.invalid"}) for i in range(3)]
write(subdir / "agent-x.jsonl", [assistant("x1", 5, 150, 10, commands), assistant("x2", 7, 250, 20)])
write(subdir / "workflows/wf_y/agent-z.jsonl", [
    assistant("z", 30, 900, 40, [tool("text", "Read", {"file_path": "/text.txt"})]),
    result("text", "PRIVATE-TEXT-" * 2000)])
write(subdir / "workflows/wf_y/journal.jsonl", [
    {"type": "launched"}, {"type": "started"}, {"type": "result"}, assistant("ignored", 999, 999, 999)])
write(subdir / "journal.jsonl", [assistant("ignored", 999, 999, 999)])
s = parse_selected_session(session)
check("a1-subagent-layout-and-journal-exclusion", len(s["subagents"]) == 2)
check("a1-workflow-identity", [(a["agent_id"], a["workflow_id"]) for a in s["subagents"]]
      == [("x", None), ("z", "wf_y")])
check("a1-main-plus-agent-totals", combined_totals(transcripts([s]))
      == {"requests": 4, "output_tokens": 53, "cache_read": 1400, "cache_creation": 90})
request = s["requests_by_id"]["main"]
check("a1-request-last-usage-model-time-ttl-retained", request["usage"]["output_tokens"] == 11
      and request["model"] == "fixture-model" and request["timestamp"] == "2026-10-08T00:00:00Z"
      and request["usage"]["cache_creation"]
      == {"ephemeral_5m_input_tokens": 20, "ephemeral_1h_input_tokens": 0})
rpt = build_report([s], root, "fixture")
check("a1-report-subaggregate", "| sid.jsonl / sub-agents | 2 | 1 | 3 | 42 | 1300 | 70 |" in rpt)
check("a1-report-top-agents-cache-order", rpt.index("| z | wf_y | 1 | 900 |")
      < rpt.index("| x | — | 2 | 400 |"))
check("a1-agent-findings-provenance", any(line.startswith("| polling |")
      and line.endswith("| sid.jsonl / agent x / workflow — |") for line in rpt.splitlines())
      and any(line.startswith("| large-output |")
      and line.endswith("| sid.jsonl / agent z / workflow wf_y |") for line in rpt.splitlines()))
check("a1-report-no-text-content", "PRIVATE-TEXT-" not in rpt)
check("a1-main-only-parser", len(parse_selected_session(session, True)["subagents"]) == 0)
env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONDONTWRITEBYTECODE="1")
cli = [sys.executable, str(root / "hooks/local/token-waste-audit.py"), "--last", "1",
       "--dir", str(session.parent)]
run = subprocess.run(cli, cwd=temp, env=env, capture_output=True, encoding="utf-8", timeout=30)
check("a1-cli-last-counts-main-sessions", run.returncode == 0 and "sessions: 1 |" in run.stdout
      and "Sub-agents: 2 | workflows: 1 | requests: 3" in run.stdout)
run = subprocess.run(cli + ["--main-only"], cwd=temp, env=env, capture_output=True,
                     encoding="utf-8", timeout=30)
check("a1-cli-main-only", run.returncode == 0
      and "Sub-agents: not parsed (--main-only)" in run.stdout and "Sub-agents: 0 |" not in run.stdout)
report_path = Path(next(line.split("| report: ", 1)[1] for line in run.stdout.splitlines()
                        if "| report: " in line))
main_report = report_path.read_text(encoding="utf-8")
check("a1-main-only-report-omits-agent-tables", "Sub-agents: not parsed (--main-only)" in main_report
      and " / sub-agents |" not in main_report and "agents by cache read" not in main_report
      and "Totals (main only):" in main_report)
for flag in ("env", "-P", "-I"):
    safe_cli = cli if flag == "env" else [cli[0], flag, *cli[1:]]
    safe_env = dict(env, PYTHONSAFEPATH="1")
    run = subprocess.run(safe_cli, cwd=temp, env=safe_env, capture_output=True,
                         encoding="utf-8", timeout=30)
    check("a1-cli-safe-path-" + flag.lstrip("-"), run.returncode == 0
          and "Sub-agents: 2 | workflows: 1 | requests: 3" in run.stdout)
other = write(session.parent / "older.jsonl", [assistant("older", 1000, 1000, 1000)])
os.utime(other, (1, 1))
run = subprocess.run(cli, cwd=temp, env=env, capture_output=True, encoding="utf-8", timeout=30)
check("a1-cli-last-does-not-count-agent-files", run.returncode == 0 and "sessions: 1 |" in run.stdout
      and "Sub-agents: 2 |" in run.stdout and "older.jsonl" not in run.stdout)
first, second = png(1024, 1280, 1), png(1024, 1280, 2)
single = parse_session(write(temp / "image.jsonl", image_rows([first])))
check("a1-image-600kb-png-text-zero", len(first) >= 600 * 1024 and single["tool_result_chars"] == 0)
check("a1-image-png-token-estimate", single["images"][0]["dimensions"] == (1024, 1280)
      and 1000 <= single["images"][0]["tokens"] <= 2000)
check("a1-image-no-large-or-repeat-output", not any(
    f.cls in ("large-output", "repeat-output") for f in session_findings(single)))
image_report = build_report([single], root, "fixture")
check("a1-image-report-estimate-no-data", "| image.jsonl | 1 | 1748 (estimate) | 0 |" in image_report
      and first.hex()[:32] not in image_report and "iVBORw0KGgo" not in image_report)
unknown = parse_session(write(temp / "unknown.jsonl", image_rows([b"unknown"])))
image_table = build_report([single, s, unknown], root, "fixture").split("## Images")[1].split("## Top")[0]
check("a1-image-table-only-nonzero-plus-total", [line for line in image_table.splitlines()
      if line.startswith("| ")][1:] == ["| image.jsonl | 1 | 1748 (estimate) | 0 |",
      "| unknown.jsonl | 1 | 1600 (estimate) | 1 |", "| Total | 2 | 3348 (estimate) | 1 |"])
empty_image_table = rpt.split("## Images")[1].split("## Top")[0]
check("a1-image-table-zero-total-only", [line for line in empty_image_table.splitlines()
      if line.startswith("| ")][1:] == ["| Total | 0 | 0 (estimate) | 0 |"])
repeat = parse_session(write(temp / "repeat.jsonl", image_rows([first, first, first])))
found = [f for f in session_findings(repeat) if f.cls == "image-reread"]
check("a1-image-identical-bytes-three-one-finding", len(found) == 1 and "x3" in found[0].desc
      and "TE-02" in found[0].rule and len(session_findings(repeat)) == 1)
fresh = parse_session(write(temp / "fresh.jsonl", image_rows([first, second, png(1024, 1280, 3)])))
check("a1-image-recapture-same-path-distinct-bytes", not session_findings(fresh))
mixed_rows = image_rows([first, first])
for row in mixed_rows:
    if row["type"] == "user":
        row["message"]["content"][0]["content"].append({"type": "text", "text": "text-result"})
mixed = parse_session(write(temp / "mixed-image.jsonl", mixed_rows))
check("a1-mixed-image-text-measure-unchanged", mixed["tool_result_chars"] == 22
      and len(mixed["images"]) == 2)
duplicate = parse_session(write(temp / "duplicate-result.jsonl", image_rows([first]) + image_rows([first])))
check("a1-image-tool-result-dedupe", len(duplicate["images"]) == 1)
scaled = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 3136, 1568)
check("a1-image-long-edge-downscale", image_metadata(image(scaled))["tokens"] == 1640)
jpeg = (b"\xff\xd8\xff\xe0\x00\x04xx\xff\xc2\x00\x0b\x08"
        + struct.pack(">HH", 1280, 1024) + b"\x01\x01\x11\x00\xff\xd9")
check("a1-image-jpeg-sofn-dimensions", image_metadata(image(jpeg))["dimensions"] == (1024, 1280))
check("a1-image-unknown-dimensions-flat", image_metadata(image(b"unknown"))["tokens"] == 1600)
check("a1-image-malformed-base64-flat", image_metadata({"source": {
    "type": "base64", "data": "invalid!"}})["tokens"] == 1600)
hook_rows = [assistant("r", 1, 0, 0, [tool("r", "Read", {"file_path": "/text"})]), result("r", "text")]
hook_rows.append({"type": "attachment", "attachment": {
    "type": "hook_success", "stderr": "HOOK-PRIVATE-" * 1250,
    "message": {"content": [{"type": "tool_result", "content": "HOOK-PRIVATE-" * 1250}]}}})
hook = parse_session(write(temp / "hook.jsonl", hook_rows))
check("a1-hook-attachment-never-text", hook["tool_result_chars"] == 4
      and "HOOK-PRIVATE-" not in build_report([hook], root, "fixture"))
path1, path2 = "/" + "p" * 140 + "/first.py", "/" + "p" * 140 + "/second.py"
target1 = tool_target("Read", {"file_path": path1})
target2 = tool_target("Read", {"file_path": path2})
check("a1-path-head-tail-distinct-basename", len(target1) == 100 and len(target2) == 100
      and target1 != target2 and target1.endswith("first.py") and target2.endswith("second.py"))
check("a1-command-head-truncation-unchanged", tool_target("Bash", {"command": path1}) == snippet(path1))
check("a1-single-session-agents-not-cross-session", cross_session_aggregate([s]) == ([], []))
many = parse_selected_session(session)
many["subagents"] = [dict(s["subagents"][0], agent_id="%02d" % i) for i in range(12)]
top_report = build_report([many], root, "fixture")
top_section = top_report.split("## Top 10 agents by cache read")[1].split("## Images")[0]
check("a1-top-agent-list-capped-ten", sum(line.startswith("| ") for line in top_section.splitlines()) == 11)
cap_path = write(temp / "cap/capped.jsonl", [
    assistant("main-cap", 1, 0, 0, [tool("main-cap", "Read", {"file_path": "/main-cap.txt"})]),
    result("main-cap", "M" * 100000)])
for index in range(12):
    rows = []
    for occurrence in range(2):
        tid = "cap-%d-%d" % (index, occurrence)
        rows += [assistant(tid, 1, 0, 0, [tool(tid, "Read", {"file_path": "/cap-%d.txt" % index})]),
                 result(tid, ("%02d" % index) * (15000 + index * 500))]
    write(cap_path.parent / ("capped/subagents/agent-%02d.jsonl" % index), rows)
cap_session = parse_selected_session(cap_path)
cap_report = build_report([cap_session], root, "fixture")
large_rows = [line for line in cap_report.splitlines() if line.startswith("| large-output |")]
repeat_rows = [line for line in cap_report.splitlines() if line.startswith("| repeat-output |")]
check("a1-session-large-output-cap", len(large_rows) == 10
      and cap_report.count("large-output: 15 more suppressed (session cap)") == 1)
check("a1-session-repeat-output-cap", len(repeat_rows) == 10
      and cap_report.count("repeat-output: 2 more suppressed (session cap)") == 1)
sizes = [int(re.search(r"Tool result (\d+) chars", line)[1]) for line in large_rows]
check("a1-session-cap-largest-first-provenance", sizes == [100000, 41000, 41000, 40000, 40000,
      39000, 39000, 38000, 38000, 37000]
      and large_rows[0].endswith("| capped.jsonl |")
      and all(" / agent " in line for line in large_rows[1:])
      and [int(re.search(r"~(\d+) chars each", line)[1]) for line in repeat_rows]
      == list(range(41000, 31000, -1000))
      and all(" / agent " in line for line in repeat_rows))
two_reports = build_report([cap_session, cap_session], root, "fixture")
check("a1-session-caps-reset-per-session", two_reports.count("| large-output |") == 20
      and two_reports.count("| repeat-output |") == 20)
single_flood = parse_session(write(temp / "single-flood.jsonl", [row for index in range(12)
    for row in [assistant("f%d" % index, 1, 0, 0,
                         [tool("f%d" % index, "Read", {"file_path": "/f%d" % index})]),
                result("f%d" % index, "F" * (20000 + index))]]))
check("a1-session-cap-counts-all-transcript-candidates", "large-output: 2 more suppressed (session cap)"
      in build_report([single_flood], root, "fixture"))
cap_cli = [sys.executable, str(root / "hooks/local/token-waste-audit.py"), "--last", "1",
           "--dir", str(cap_path.parent)]
run = subprocess.run(cap_cli, cwd=temp, env=env, capture_output=True, encoding="utf-8", timeout=30)
check("a1-cli-session-caps-match-report", run.returncode == 0
      and "large-output 10 | repeat-output 10" in run.stdout
      and "large-output: 15 more suppressed (session cap)" in run.stdout
      and "repeat-output: 2 more suppressed (session cap)" in run.stdout)
print("[token-waste-a1-native] %d/%d PASS" % (passed, passed + failed))
raise SystemExit(bool(failed))
