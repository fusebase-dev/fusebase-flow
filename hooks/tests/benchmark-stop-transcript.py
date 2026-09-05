#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import statistics
import sys
import tempfile
import time
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
HANDLER = ROOT / "hooks/handlers/stop.py"
OUT = ROOT / "state/audit/flow-performance-and-recovery-hardening/stop-benchmark.json"


def load_handler():
    spec = importlib.util.spec_from_file_location("flow_stop_benchmark", HANDLER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.emit = lambda *args, **kwargs: None
    return module


def transcript_bytes(size: int) -> bytes:
    signals = "git diff --stat lint clean typecheck clean gate report comment-policy review: applied (FR-22) "
    final = json.dumps({"role": "assistant", "content": "Implementation complete"})
    prefix = json.dumps({"role": "user", "content": signals})[:-2]
    base = (prefix + '"}\n' + final + "\n").encode()
    if len(base) > size:
        raise ValueError(size)
    return (prefix + ("x" * (size - len(base))) + '"}\n' + final + "\n").encode()


def run_once(module, transcript: Path) -> tuple[float, int, int]:
    original = Path.read_text
    reads = 0
    bytes_read = 0
    target = transcript.resolve()

    def tracked(path: Path, *args, **kwargs):
        nonlocal reads, bytes_read
        text = original(path, *args, **kwargs)
        if path.resolve() == target:
            reads += 1
            bytes_read += transcript.stat().st_size
        return text

    event = json.dumps({"cwd": str(ROOT), "transcript_path": str(transcript)})
    old_stdin = sys.stdin
    stdout = io.StringIO()
    started = time.perf_counter()
    try:
        sys.stdin = io.StringIO(event)
        with mock.patch.object(Path, "read_text", tracked), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(io.StringIO()):
            rc = module.main()
    finally:
        sys.stdin = old_stdin
    elapsed = time.perf_counter() - started
    result = json.loads(stdout.getvalue())
    if rc != 0 or result.get("decision") != "allow" or reads != 1:
        raise AssertionError((rc, result, reads, bytes_read))
    return elapsed, reads, bytes_read


def main() -> int:
    module = load_handler()
    rows = []
    with tempfile.TemporaryDirectory(prefix="flow-stop-benchmark-") as raw:
        work = Path(raw)
        for mib in (1, 10, 30):
            path = work / f"{mib}mib.jsonl"
            path.write_bytes(transcript_bytes(mib * 1024 * 1024))
            samples = [run_once(module, path) for _ in range(3)]
            rows.append({
                "mib": mib,
                "bytes": path.stat().st_size,
                "wall_seconds_median": statistics.median(sample[0] for sample in samples),
                "wall_seconds_samples": [sample[0] for sample in samples],
                "transcript_reads_per_run": [sample[1] for sample in samples],
                "transcript_bytes_per_run": [sample[2] for sample in samples],
            })
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"schema_version": 1, "results": rows}, indent=2) + "\n", encoding="utf-8")
    print("PASS: stop-transcript one read per 1/10/30 MiB run; benchmark recorded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
