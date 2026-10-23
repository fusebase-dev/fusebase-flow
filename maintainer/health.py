"""`flow.py health --target DIR`: what install knows about a project, read-only (handoff section 13, a small 6.0 health).

The version, the manifest's drift and the Flow files an install kept (your edits, not this release's), the marked
blocks, the git hooks in the folder git runs them from (`git rev-parse --git-path hooks`, which follows core.hooksPath),
the wiring per provider (the settings parsed), the reader's schedule and state/status.line. Exit 0 healthy, 1 not, 2 no
6.0 install there. Writes nothing.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True  # read-only: no __pycache__ beside the core's reader either
import flow  # noqa: E402

sys.path.insert(0, str(flow.CORE / "hooks/local"))
import reader  # noqa: E402  (the one rule for "wired", shared with state/status.line)

HOOKS = ("pre-commit", "commit-msg", "pre-push", "pre-merge-commit")  # each one the project's hooks/git/ carries
SETTINGS = {"claude": ".claude/settings.json", "codex": ".codex/hooks.json"}


def hooks_dir(target: Path) -> Path | None:
    """The folder git runs hooks from: core.hooksPath when set (Husky writes it), else the common git dir's hooks/."""
    return flow.git_path(target, "--git-path", "hooks")


def reader_state(target: Path, record: dict) -> str:
    """What the scheduler itself says about the recorded reader, read-only (6.0.0-m6 item 7): `schtasks /Query` of the
    task's name, or the user's crontab; the install record alone said "scheduled" over a disabled task."""
    line = str(record.get("line", ""))
    tool = "crontab" if line.startswith("*/") else "schtasks"
    exe = flow.shutil.which(tool)  # TRIPWIRE: the resolved path; a bare name finds System32 first on Windows
    if not exe:
        return f"{tool} not found on PATH, so the scheduler was not asked"
    if tool == "crontab":
        argv, mine = [exe, "-l"], f"cd {flow.sh_quote(str(target))} &&"
    else:
        name = re.search(r'/TN\s+(?:"([^"]*)"|(\S+))', line)
        if not name:
            return "the install record names no task"
        argv = [exe, "/Query", "/TN", name[1] or name[2], "/FO", "LIST", "/V"]
    try:
        out = subprocess.run(argv, capture_output=True, text=True, errors="replace", timeout=120)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"{tool} could not be asked ({exc})"
    if tool == "crontab":
        found = any(mine in x and flow.READER_RUN in x for x in out.stdout.splitlines() if not x.lstrip().startswith("#"))
        return "in the crontab" if out.returncode == 0 and found else "NOT in the crontab (removed or commented out)"
    if out.returncode != 0:
        return f"schtasks has no task {name[1] or name[2]!r} (deleted)"
    fields = dict(x.split(":", 1) for x in out.stdout.splitlines() if ":" in x)
    state = (fields.get("Status", "") or fields.get("Scheduled Task State", "")).strip()
    return f"the task is {state}" if state else "schtasks answered, in a form this check does not read"


def approvals(target: Path) -> list[str]:
    """Each approval in state/approvals/ that is expired or has no readable expiry (O-31 (k)): it authorizes nothing,
    and --consume, or deleting it, clears it. Reported, never unhealthy."""
    found = []
    for f in sorted((target / "state/approvals").glob("*.json")):
        try:
            when = str(json.loads(f.read_text(encoding="utf-8")).get("expires_at", ""))
            expired = datetime.fromisoformat(when.replace("Z", "+00:00")).astimezone(timezone.utc) < datetime.now(timezone.utc)
        except (OSError, ValueError, AttributeError, TypeError):
            when, expired = "unreadable", True
        found += [f"approval: {f.name} expired ({when}); it authorizes nothing: delete it"] * expired
    return found


def runs_flows(live: Path | None, mine: Path, name: str) -> str:
    """"same" when git's hook is Flow's byte for byte, "calls" when it is a script that runs Flow's (a hook manager such
    as Husky chaining it: hooks/git/<name>, or the common git dir's hooks/<name>), else "" (m7 review B #4)."""
    if live is None or not live.is_file():
        return ""
    data = live.read_bytes()
    if data == mine.read_bytes():
        return "same"
    text = data.decode("utf-8", "replace")
    calls = re.compile(rf"(?:hooks/git/|\.git/hooks/){re.escape(name)}(?![\w.-])")
    lines = [ln.strip() for ln in text.splitlines()]  # a comment, an echo or a printf names it without running it
    return "calls" if any(calls.search(ln) and not ln.startswith(("#", "echo ", "printf ")) for ln in lines) else ""


def report(target: Path) -> tuple[int, list[str]]:
    target = target.resolve()
    try:
        manifest = json.loads((target / flow.MANIFEST).read_text(encoding="utf-8"))
        # an entry marked "project" (the project's module-size rows, policies/module-size-baseline.project.txt) is the
        # project's file: recorded for the commit that carried it there, never checked (6.0.0-m6 item 9)
        files = {e["path"]: e["sha256"] for e in manifest["files"] if not e.get("project") and not e.get("kept")}
        kept = sorted(e["path"] for e in manifest["files"] if e.get("kept"))
    except (OSError, ValueError, KeyError, TypeError):
        return 2, [f"[flow health] {target}: no readable {flow.MANIFEST}; not a Flow 6.0 install (run install)"]
    bad, out = [], [f"[flow health] {target}"]
    core = (flow.CORE / "VERSION").read_text(encoding="utf-8").strip()
    have = manifest.get("flow_version", "?")
    out.append(f"version: {have} installed{'' if have == core else f'; this core is {core} (re-run install to upgrade)'}")
    missing = sorted(p for p in files if not (target / p).is_file())
    drift = sorted(p for p, sha in files.items() if p not in missing and not flow.same_content((target / p).read_bytes(), sha))
    out.append(f"manifest: {len(files)} files, {len(files) - len(missing) - len(drift)} as installed, {len(drift)} changed, "
               f"{len(missing)} missing")
    out += [f"  changed: {p}" for p in drift] + [f"  missing: {p}" for p in missing]
    # a Flow file an install kept (your edit) is not this release's: an older one beside the new hooks (6.0.0-m7 item 4)
    out += [f"  kept, not current: {p} (your edit; install keeps it and does not upgrade it)" for p in kept]
    bad += [f"{len(missing)} Flow files missing"] * bool(missing)
    bad += [f"a hook-layer file changed: {p}" for p in drift if p.startswith("hooks/")]
    bad += [f"a hook-layer file kept from an earlier release: {p}" for p in kept if p.startswith("hooks/")]
    for name in [*flow.OVERLAY, *flow.BLOCKS] if "claude" in manifest.get("providers", []) else ["AGENTS.md", *flow.BLOCKS]:
        text = (target / name).read_bytes().decode("utf-8", "surrogateescape") if (target / name).is_file() else ""
        found = flow.block_markers(text, name) if name in flow.BLOCKS else (1, 1) if flow.FLOW_BEGIN in text else (-1, -1)
        state = found if isinstance(found, str) else "present" if found[0] >= 0 else "absent"
        out.append(f"block: {name} {state}")
        bad += [f"the Flow block in {name} is {state}"] * (state != "present")
    folder, note = hooks_dir(target), flow.hooks_path_note(target)
    if note:
        out.append(f"git hooks: {note}")
    for h in [h for h in HOOKS if (target / "hooks/git" / h).is_file()]:
        live, mine = (folder / h if folder else None), target / "hooks/git" / h
        state = runs_flows(live, mine, h)
        where = folder.as_posix() if folder else "the hooks folder"
        out.append(f"git hook: {h} " + ("installed" if state == "same" else f"installed ({live.as_posix()} calls Flow's)"
                                         if state == "calls" else f"NOT installed in {where} (or differs from "
                                                                  f"hooks/git/{h}, and does not call it)"))
        bad += [f"git hook {h} not run where git runs hooks"] * (not state)
    for name in manifest.get("providers", []):
        out.append(f"wiring: {name} {reader.wired(target, SETTINGS[name])} ({SETTINGS[name]})")
    record = manifest.get("reader")
    out.append(f"reader: registered by install; the scheduler says: {reader_state(target, record)}" if record
               else "reader: not scheduled (install --register-reader)")
    out += approvals(target)
    status = (target / "state/status.line").read_text(encoding="utf-8").strip() if (target / "state/status.line").is_file() else ""
    out.append(f"status.line: {status or 'absent (the reader has not run)'}")
    out += ["WARNING: neither `timeout` nor `gtimeout` is on PATH, so FR-27's bounded runs are skipped; on macOS: "
            "brew install coreutils"] * (not (shutil.which("timeout") or shutil.which("gtimeout")))  # T395; no verdict
    out.append("HEALTH: " + ("healthy" if not bad else "NOT healthy: " + "; ".join(bad)))
    return int(bool(bad)), out
