"""`flow.py health --target DIR`: what install knows about a project, read-only (handoff section 13, a small 6.0 health).

The version, the manifest's drift, the marked blocks, the git hooks, the wiring per provider, the reader's schedule and
state/status.line. Exit 0 healthy, 1 not, 2 no 6.0 install there. Writes nothing.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # read-only: no __pycache__ beside the core's reader either
import flow  # noqa: E402

sys.path.insert(0, str(flow.CORE / "hooks/local"))
import reader  # noqa: E402  (the one rule for "wired", shared with state/status.line)

HOOKS = ("pre-commit", "commit-msg", "pre-push")
SETTINGS = {"claude": ".claude/settings.json", "codex": ".codex/hooks.json"}


def hooks_dir(target: Path) -> Path | None:
    try:
        out = subprocess.run(["git", "--no-optional-locks", "rev-parse", "--git-common-dir"], cwd=target,
                             capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return None
    common = Path(out.stdout.strip())
    return (common if common.is_absolute() else target / common) / "hooks" if out.returncode == 0 else None


def report(target: Path) -> tuple[int, list[str]]:
    target = target.resolve()
    try:
        manifest = json.loads((target / flow.MANIFEST).read_text(encoding="utf-8"))
        files = {e["path"]: e["sha256"] for e in manifest["files"]}
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
    bad += [f"{len(missing)} Flow files missing"] * bool(missing)
    bad += [f"a hook-layer file changed: {p}" for p in drift if p.startswith("hooks/")]
    for name in [*flow.OVERLAY, *flow.BLOCKS] if "claude" in manifest.get("providers", []) else ["AGENTS.md", *flow.BLOCKS]:
        text = (target / name).read_bytes().decode("utf-8", "surrogateescape") if (target / name).is_file() else ""
        found = flow.block_markers(text, name) if name in flow.BLOCKS else (1, 1) if flow.FLOW_BEGIN in text else (-1, -1)
        state = found if isinstance(found, str) else "present" if found[0] >= 0 else "absent"
        out.append(f"block: {name} {state}")
        bad += [f"the Flow block in {name} is {state}"] * (state != "present")
    folder = hooks_dir(target)
    for h in HOOKS:
        live, mine = (folder / h if folder else None), target / "hooks/git" / h
        same = live is not None and live.is_file() and mine.is_file() and live.read_bytes() == mine.read_bytes()
        out.append(f"git hook: {h} {'installed' if same else 'NOT installed (or differs from hooks/git/' + h + ')'}")
        bad += [f"git hook {h} not installed"] * (not same)
    for name in manifest.get("providers", []):
        out.append(f"wiring: {name} {reader.wired(target, SETTINGS[name])} ({SETTINGS[name]})")
    record = manifest.get("reader")
    out.append(f"reader: {'scheduled: ' + record['line'] if record else 'not scheduled (install --register-reader)'}")
    status = (target / "state/status.line").read_text(encoding="utf-8").strip() if (target / "state/status.line").is_file() else ""
    out.append(f"status.line: {status or 'absent (the reader has not run)'}")
    out.append("HEALTH: " + ("healthy" if not bad else "NOT healthy: " + "; ".join(bad)))
    return int(bool(bad)), out
