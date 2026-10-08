from .common import (ERROR_SHAPE, LINE_TYPES, WRITE_TOOLS, LARGE_WRITE_CHARS,
                     ToolResult, canon_path, tool_target, snippet)
import hashlib
import json
from .images import result_images

def result_size_and_digest(content):
    # TRIPWIRE: never serialize image blocks into text; base64 is not model-visible text.
    parts = []
    if isinstance(content, str):
        parts.append(content)
    elif isinstance(content, list):
        for block in content:
            if isinstance(block, dict):
                if block.get("type") == "text":
                    parts.append(block.get("text") or "")
                elif block.get("type") != "image":
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
        "requests_by_id": {},
        "requests_no_id": [],
        "images": [],
        "image_only_read_seqs": set(),
        "subagents": [],
        "tool_result_chars": 0,
        "tool_results": [],           # ToolResult(chars, name, target, digest, key, seq, err)
        "read_counts": {},            # (canonical file_path, offset, limit) -> count
        "read_events": {},            # full read key -> [(seq, chars, digest, err)] in order
        "read_display": {},           # read key -> first-seen raw path (display only)
        "write_events": [],           # (seq, canonical target path) for Edit/Write/NotebookEdit
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
    cwd = ""                          # last-seen transcript cwd; roots relative tool paths
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
            if isinstance(obj.get("cwd"), str) and obj["cwd"].strip():
                cwd = obj["cwd"]
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
                    request = {"request_id": rid, "usage": usage,
                               "timestamp": obj.get("timestamp"), "model": msg.get("model")}
                    # One API request streams many assistant lines repeating the same
                    # usage object — naive summing overcounts ~2.4x; keep last per requestId.
                    if rid:
                        s["usage_by_request"][rid] = usage
                        s["requests_by_id"][rid] = request
                    else:
                        s["usage_no_request"].append(usage)
                        s["requests_no_id"].append(request)
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
                            raw_read = str(tin.get("file_path", ""))
                            key = (canon_path(raw_read, cwd), tin.get("offset"), tin.get("limit"))
                            s["read_counts"][key] = s["read_counts"].get(key, 0) + 1
                            s["read_display"].setdefault(key, raw_read)
                        if tid:
                            tool_meta[tid] = (name, tool_target(name, tin), key, seq)
                        if name in WRITE_TOOLS:
                            wpath = tin.get("file_path") or tin.get("notebook_path")
                            if wpath:
                                s["write_events"].append((seq, canon_path(wpath, cwd)))
                            bash_counts.clear()
                        if name in ("Bash", "PowerShell"):
                            norm = " ".join(str(tin.get("command", "")).split())
                            bash_counts[norm] = bash_counts.get(norm, 0) + 1
                            if bash_counts[norm] > s["bash_runs"].get(norm, 0):
                                s["bash_runs"][norm] = bash_counts[norm]
                        fp = tin.get("file_path") or tin.get("notebook_path")
                        if name == "Write" and fp:
                            content_len = len(str(tin.get("content", "")))
                            if canon_path(fp, cwd) in seen_paths and content_len >= LARGE_WRITE_CHARS:
                                s["large_writes"].append((snippet(str(fp), keep_tail=True), content_len))
                        if fp:
                            seen_paths.add(canon_path(fp, cwd))
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
                    images = result_images(block.get("content"))
                    if images and not chars and name == "Read":
                        s["image_only_read_seqs"].add(use_seq)
                    for image in images:
                        s["images"].append(dict(image, name=name, target=target, seq=use_seq))
                    s["tool_results"].append(
                        ToolResult(chars, name, target, digest, key, use_seq, err))
                    if name == "Read" and key is not None:
                        s["read_events"].setdefault(key, []).append((use_seq, chars, digest, err))
    for evs in s["read_events"].values():
        evs.sort(key=lambda e: e[0])   # event order, not transcript-result arrival order
    return s


def parse_selected_session(path, main_only=False):
    main = parse_session(path)
    main["label"] = path.name
    main["session_id"] = path.stem
    main["main_only"] = main_only
    if main_only:
        return main
    subdir = path.parent / path.stem / "subagents"
    files = sorted(subdir.glob("agent-*.jsonl"))
    files += sorted(subdir.glob("workflows/wf_*/agent-*.jsonl"))
    for agent_path in files:
        if agent_path.name == "journal.jsonl":
            continue
        agent = parse_session(agent_path)
        agent["agent_id"] = agent_path.stem.removeprefix("agent-")
        agent["workflow_id"] = agent_path.parent.name if agent_path.parent != subdir else None
        agent["session_id"] = path.stem
        agent["label"] = "%s / agent %s / workflow %s" % (
            path.name, agent["agent_id"], agent["workflow_id"] or "—")
        main["subagents"].append(agent)
    return main


def transcripts(sessions):
    return [transcript for session in sessions
            for transcript in [session, *session.get("subagents", [])]]


def usage_totals(s):
    usages = list(s["usage_by_request"].values()) + s["usage_no_request"]
    out = {"requests": len(usages), "output_tokens": 0, "cache_read": 0, "cache_creation": 0}
    for u in usages:
        out["output_tokens"] += u.get("output_tokens") or 0
        out["cache_read"] += u.get("cache_read_input_tokens") or 0
        out["cache_creation"] += u.get("cache_creation_input_tokens") or 0
    return out
