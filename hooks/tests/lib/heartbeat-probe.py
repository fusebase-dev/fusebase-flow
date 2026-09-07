#!/usr/bin/env python3
"""Release an AC5 fixture from observed parent-heartbeat evidence."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import time


def heartbeat_count(path: Path) -> int:
    try:
        return path.read_bytes().count(b"[bounded] still running (")
    except FileNotFoundError:
        return 0


def write_result(path: Path, values: dict[str, str | int]) -> None:
    body = "".join(f"AC5_{key.upper()}={value}\n" for key, value in values.items())
    path.write_text(body, encoding="ascii")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("tag")
    parser.add_argument("mode", choices=("live", "off", "disabled", "oneshot", "late", "contaminate"))
    parser.add_argument("--evidence-deadline", type=float, default=8.0)
    parser.add_argument("--completion-deadline", type=float, default=30.0)
    args = parser.parse_args()

    directory = args.directory
    tag = args.tag
    started = directory / f"started.{tag}"
    release = directory / f"release.{tag}"
    exited = directory / f"exited.{tag}"
    done = directory / f"done.{tag}"
    stderr = directory / f"err.{tag}"
    result = directory / f"control.{tag}"

    began = time.monotonic()
    started_at: float | None = None
    released_at: float | None = None
    release_reason = "watchdog"
    observed = 0
    pre_release = 0
    first_ms = -1
    second_ms = -1

    while time.monotonic() - began < args.completion_deadline:
        now = time.monotonic()
        if started_at is None and started.exists():
            started_at = now

        count = heartbeat_count(stderr)
        if count > observed:
            for index in range(observed + 1, count + 1):
                if started_at is not None and not release.exists() and not exited.exists():
                    pre_release += 1
                    elapsed_ms = int((now - started_at) * 1000)
                    if first_ms < 0:
                        first_ms = elapsed_ms
                    elif second_ms < 0:
                        second_ms = elapsed_ms
            observed = count

        if started_at is not None and released_at is None:
            age = now - started_at
            if args.mode in ("live", "contaminate") and pre_release >= 2:
                release_reason = "two-heartbeats"
                release.touch()
                released_at = now
            elif args.mode in ("off", "disabled") and age >= 0.25:
                release_reason = "independent"
                release.touch()
                released_at = now
            elif args.mode == "oneshot" and age >= 3.0:
                release_reason = "negative-deadline"
                release.touch()
                released_at = now
            elif args.mode == "late" and age >= 1.0:
                release_reason = "before-late-heartbeat"
                release.touch()
                released_at = now
            elif age >= args.evidence_deadline:
                release_reason = "evidence-deadline"
                release.touch()
                released_at = now

        if done.exists() and exited.exists():
            break
        time.sleep(0.025)
    else:
        release.touch(exist_ok=True)

    time.sleep(0.1)
    total = heartbeat_count(stderr)
    values: dict[str, str | int] = {
        "completed": "yes" if done.exists() and exited.exists() else "no",
        "started": "yes" if started_at is not None else "no",
        "exited": "yes" if exited.exists() else "no",
        "done": "yes" if done.exists() else "no",
        "release_reason": release_reason,
        "pre_release": pre_release,
        "total": total,
        "first_ms": first_ms,
        "second_ms": second_ms,
        "elapsed_ms": int((time.monotonic() - began) * 1000),
    }
    write_result(result, values)
    return 0 if values["completed"] == "yes" else 3


if __name__ == "__main__":
    raise SystemExit(main())
