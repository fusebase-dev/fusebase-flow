#!/usr/bin/env python3
"""The suite in parallel: `python maintainer/tests/test_migrate.py` runs it through here (6.0.0-m8 item 10: the
Windows leg ran over 30 minutes, one test at a time). The parent lists the suite's test classes (test_migrate's
load_tests), starts FLOW_TEST_WORKERS worker processes (default: the CPU count, at most 4; 1 runs the old single
process) and hands each worker the next class whenever it finishes one, the heaviest first. A worker runs its classes
one at a time in one process, so a fixture built once per process (test_m6.Project's) serves every class it runs. The
parent prints each class's unittest output whole as it finishes, then the totals and the ten slowest classes, and fails
when a class failed or errored, or a worker died."""
from __future__ import annotations

import importlib
import io
import json
import os
import subprocess
import sys
import threading
import time
import traceback
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
MARK = "[suite-worker] "  # a line of its own after each class's output: the class's counts as JSON
HEAVY = {"test_migrate": 6, "test_migrate_recovery": 6, "test_m6": 4, "test_m6_fix": 4, "test_m7": 4, "test_m8": 3,
         "test_m8b": 4}  # a class's weight per test: these build projects, install and commit through the hooks


def classes(suite: unittest.TestSuite) -> list[tuple[str, int]]:
    """(module.Class, its test count) for each class the suite holds, in suite order."""
    counts: dict[str, int] = {}

    def walk(s: unittest.TestSuite) -> None:
        for t in s:
            if isinstance(t, unittest.TestSuite):
                walk(t)
            else:
                name = f"{type(t).__module__}.{type(t).__qualname__}"
                counts[name] = counts.get(name, 0) + 1
    walk(suite)
    return list(counts.items())


def worker() -> int:
    """Read one class name per line from stdin, run it, print its output and a MARK line with its counts."""
    sys.path.insert(0, str(HERE))
    for line in sys.stdin:
        name, started, out = line.strip(), time.monotonic(), io.StringIO()
        if not name:
            break
        try:
            module, cls = name.rsplit(".", 1)
            suite = unittest.defaultTestLoader.loadTestsFromTestCase(getattr(importlib.import_module(module), cls))
            result = unittest.TextTestRunner(stream=out, verbosity=2).run(suite)
            counts = {"run": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
                      "skipped": len(result.skipped)}
        except BaseException:  # noqa: BLE001 — reported as the class's error, the next class still runs
            out.write(traceback.format_exc())
            counts = {"run": 0, "failures": 0, "errors": 1, "skipped": 0}
        sys.stdout.write(out.getvalue())
        sys.stdout.write("\n" + MARK + json.dumps({"name": name, "seconds": round(time.monotonic() - started, 1), **counts})
                         + "\n")
        sys.stdout.flush()
    return 0


def main() -> int:
    sys.path.insert(0, str(HERE))
    import test_migrate
    found = classes(unittest.defaultTestLoader.loadTestsFromModule(test_migrate))
    queue = [n for n, _ in sorted(found, key=lambda c: -c[1] * HEAVY.get(c[0].split(".")[0], 1))]
    workers = min(int(os.environ.get("FLOW_TEST_WORKERS") or min(4, os.cpu_count() or 1)), len(queue))
    print(f"[suite] {sum(c for _, c in found)} tests in {len(queue)} classes, {workers} worker processes", flush=True)
    lock, results, started = threading.Lock(), [], time.monotonic()
    env = {**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONUNBUFFERED": "1"}

    def start() -> subprocess.Popen:
        return subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--worker"], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                                errors="replace", env=env)

    def drive() -> None:
        proc = start()
        while True:
            with lock:
                if not queue:
                    break
                name = queue.pop(0)
            proc.stdin.write(name + "\n")
            proc.stdin.flush()
            chunk, record = [], None
            for line in proc.stdout:
                if line.startswith(MARK):
                    record = json.loads(line[len(MARK):])
                    break
                chunk.append(line)
            if record is None:  # the worker died inside this class: report it, carry on in a new worker
                record = {"name": name, "seconds": 0.0, "run": 0, "failures": 0, "errors": 1, "skipped": 0}
                chunk.append(f"[suite] the worker running {name} exited (code {proc.wait()})\n")
                proc = start()
            with lock:
                results.append(record)
                print("".join(chunk) + f"[suite] {name}: {record['run']} tests in {record['seconds']} s", flush=True)
        proc.stdin.close()
        proc.wait()

    threads = [threading.Thread(target=drive) for _ in range(workers)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    total = {k: sum(r[k] for r in results) for k in ("run", "failures", "errors", "skipped")}
    print(f"\n[suite] slowest classes: " + ", ".join(f"{r['name']} {r['seconds']} s" for r in
                                                      sorted(results, key=lambda r: -r["seconds"])[:10]))
    print(f"[suite] Ran {total['run']} tests in {time.monotonic() - started:.1f} s ({workers} workers)")
    bad = total["failures"] or total["errors"] or len(results) < len(found)
    print(f"[suite] {'FAILED' if bad else 'OK'} (failures={total['failures']}, errors={total['errors']}, "
          f"skipped={total['skipped']})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(worker() if sys.argv[1:] == ["--worker"] else main())
