#!/usr/bin/env python3
"""Heartbeat reader (design section 6; handoff WP 7a): `reader.py --once` reads, writes and exits; `--watch [SECS]`
runs `--once` every SECS (default 60) in a terminal.

Signals, from files and git only: the bounded-run heartbeat files state/audit/liveness/<label>-<pid>-<n>.hb, the mtime
of the git index, the last commit time, mtimes under state/, and the audit line state/audit.log.jsonl when a provider's
hooks write one. Writes state/reader/last.json and state/status.line, never the ledger. It prints timestamps, pids and
sha256 prefixes, never a command or a heartbeat label (non-negotiable 9).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from flow_docs import git  # noqa: E402  (UTF-8, whatever the locale's code page)
from wiring import wired  # noqa: E402  (the provider's settings parsed; health reads it through this module)

# A threshold without provenance is UNCALIBRATED and logs instead of alerting (non-negotiable 2).
SILENCE_S = 30 * 60  # consumer watchdog 2026-10-14; the transcript floor is 15 min (design section 14)
REPEATS = 3          # UNCALIBRATED: owner seed 2026-10-15; logged, not an alert, until measured
CMD = re.compile(r"cmd sha256=([0-9a-f]{64})$")  # bounded-run's line 2 (5.x 834901cd)
TERMINAL = ("done", "TIMEOUT", "SKIPPED")  # bounded-run's last record; a heartbeat file without one is in flight
OWN = ("state/reader/", "state/status.line")  # the reader's own writes are not activity


def utc(t: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def heartbeats(root: Path) -> list[tuple[str, float, str, bool]]:
    """(pid, mtime, command sha256, in flight) per heartbeat file: bounded-run's `cmd sha256=` line, or for a
    heartbeat that predates it the sha256 of its label line `bounded-run <label>`."""
    found = []
    for p in sorted((root / "state/audit/liveness").glob("*.hb")):
        try:
            lines, mtime = p.read_text(encoding="utf-8", errors="replace").splitlines(), p.stat().st_mtime
        except OSError:
            continue
        label = lines[0].rsplit(" deadline=", 1)[0] if lines else p.stem
        pid = p.stem.rsplit("-", 2)[-2] if p.stem.count("-") >= 2 else "?"
        cmd = next((m[1] for line in lines[1:3] if (m := CMD.match(line))), None)
        found.append((pid, mtime, cmd or hashlib.sha256(label.encode("utf-8")).hexdigest(),
                      not (lines and lines[-1].startswith(TERMINAL))))
    return found


def audit(root: Path) -> tuple[float, list[str]]:
    """The audit line's mtime and its last command hashes, when a provider's hooks write it (a fourth signal)."""
    p = root / "state/audit.log.jsonl"
    try:
        with p.open("rb") as fh:
            fh.seek(max(0, p.stat().st_size - 65536))
            tail, mtime = fh.read().decode("utf-8", "replace").splitlines()[-50:], p.stat().st_mtime
    except OSError:
        return 0.0, []
    hashes = []
    for line in tail:
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        # A completed call only: pre_tool_use writes the same hash before the call runs (O-22).
        if (isinstance(rec, dict) and str(rec.get("event")).startswith("post_tool_use")
                and isinstance(rec.get("cmd_sha256"), str)):
            hashes.append(rec["cmd_sha256"])
    return mtime, hashes


def state_mtimes(root: Path) -> list[float]:
    times = []
    for dirpath, _, names in os.walk(root / "state"):
        for name in names:
            p = Path(dirpath, name)
            if not p.relative_to(root).as_posix().startswith(OWN):
                try:
                    times.append(p.stat().st_mtime)
                except OSError:
                    pass
    return times


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    os.replace(tmp, path)


def once(root: Path, now: float | None = None) -> dict:
    now = time.time() if now is None else now
    try:
        prev = json.loads((root / "state/reader/last.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        prev = {}
    beats, (audit_t, audit_hashes) = heartbeats(root), audit(root)
    flight = [b for b in beats if b[3]]
    index = Path(root, git(root, "rev-parse", "--git-path", "index").strip() or ".git/index")
    signals = [b[1] for b in beats] + state_mtimes(root) + [audit_t, float(git(root, "log", "-1", "--format=%ct").strip() or 0)]
    signals += [index.stat().st_mtime] if index.is_file() else []
    last = max(signals + [0.0])
    open_ids = {a.get("id") for a in prev.get("alerts", [])}
    alerts, logged = [], []
    silence_id = f"silence-{int(last)}"
    # Silence alerts while a command is in flight, or once activity stops after a running reading; it stays open
    # until activity resumes. A run nothing launched under bounded_run and nobody saw running reads as idle.
    if now - last > SILENCE_S and (flight or prev.get("status") == "running" or silence_id in open_ids):
        alerts.append({"id": silence_id, "kind": "silence", "last": utc(last), "minutes": int((now - last) // 60)})
    repeated = [h for h, n in Counter(b[2] for b in flight).items() if n >= REPEATS]
    if len(audit_hashes) >= REPEATS and len(set(audit_hashes[-REPEATS:])) == 1:
        repeated.append(audit_hashes[-1])
    for h in sorted(set(repeated)):
        logged.append({"id": f"repeat-{h[:12]}", "kind": "repeat", "cmd_sha256": h, "note": "UNCALIBRATED: logged"})
    status = "running" if flight or now - last <= SILENCE_S else "idle"
    raised = prev.get("counters", {}).get("alerts_raised", 0) + sum(a["id"] not in open_ids for a in alerts)
    record = {"reader": utc(now), "status": status, "last": utc(last), "alerts": alerts, "logged": logged,
              "in_flight": [{"pid": b[0], "cmd_sha256": b[2], "seen": utc(b[1])} for b in flight],
              "counters": {"heartbeats": len(beats), "in_flight": len(flight), "alerts": len(alerts),
                           "logged": len(logged), "alerts_raised": raised}}
    line = (f"flow: {status} last={utc(last)} hooks: claude {wired(root, '.claude/settings.json')}, "
            f"codex {wired(root, '.codex/hooks.json')} alerts={len(alerts)} reader={utc(now)}")
    write(root / "state/reader/last.json", json.dumps(record, indent=2) + "\n")
    write(root / "state/status.line", line + "\n")
    print(line)
    for a in alerts:
        print(f"ALERT {a['id']}: no activity since {a['last']} ({a['minutes']} min, threshold {SILENCE_S // 60} min)")
    for g in logged:
        print(f"LOG {g['id']}: the same command hash {REPEATS} times in flight or in a row ({g['note']})")
    return record


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="reader.py", description=__doc__.split("\n\n")[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--once", action="store_true")
    mode.add_argument("--watch", nargs="?", type=int, const=60, metavar="SECS")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args(argv)
    if args.once:
        once(args.root.resolve())
        return 0
    try:
        while True:
            once(args.root.resolve())
            time.sleep(max(5, args.watch))
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
