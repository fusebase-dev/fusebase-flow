#!/usr/bin/env bash
# Fusebase Flow - CLI/Flow conflict reporter (read-only).
#
# Reports ownership and drift for agent-facing surfaces shared by FuseBase CLI
# and Fusebase Flow. This script never writes to the target repository.

set -uo pipefail

FORMAT="text"
TARGET=""

usage() {
  cat <<'USAGE'
Usage: bash hooks/local/check-cli-flow-conflicts.sh [--json] [target-root]

Reads hooks/local/fusebase-flow-overlays/agent-surface-ownership.json and
reports CLI-owned, Flow-owned, and shared-merge surface status. No writes.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json|--machine)
      FORMAT="json"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -n "$TARGET" ]; then
        echo "[check-cli-flow-conflicts] unexpected extra argument: $1" >&2
        usage >&2
        exit 2
      fi
      TARGET="$1"
      shift
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

ROOT="$(cd "$TARGET" 2>/dev/null && pwd)"
if [ -z "$ROOT" ]; then
  echo "[check-cli-flow-conflicts] target root not found: $TARGET" >&2
  exit 2
fi

MANIFEST="$ROOT/hooks/local/fusebase-flow-overlays/agent-surface-ownership.json"
if [ ! -f "$MANIFEST" ]; then
  echo "[check-cli-flow-conflicts] manifest not found: $MANIFEST" >&2
  exit 2
fi

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  echo "[check-cli-flow-conflicts] $python_bin not found; install Python 3.10+." >&2
  exit 2
fi

"$python_bin" - "$ROOT" "$MANIFEST" "$FORMAT" <<'PY'
from __future__ import annotations

import hashlib
import json
import sys
from fnmatch import fnmatch
from pathlib import Path
from typing import Any

root = Path(sys.argv[1]).resolve()
manifest_path = Path(sys.argv[2]).resolve()
fmt = sys.argv[3]

# --- CLI vendor provenance (B2/B3) -----------------------------------------
# audit/cli-vendor-manifest.json maps each vendored CLI-owned asset to its
# bundled sha256. We hash present assets against it to emit the advisory
# CLI_SNAPSHOT_STALE finding (info, NON-FAILING). Absent/invalid manifest ->
# provenance simply unavailable; we never fail on it.
PROVENANCE: dict[str, str] = {}
PROVENANCE_AVAILABLE = False
_prov_path = root / "audit" / "cli-vendor-manifest.json"
if _prov_path.is_file():
    try:
        _prov = json.loads(_prov_path.read_text(encoding="utf-8"))
        for _a in _prov.get("assets", []) or []:
            p = _a.get("path")
            s = _a.get("sha256")
            if isinstance(p, str) and isinstance(s, str):
                PROVENANCE[p] = s
        PROVENANCE_AVAILABLE = bool(PROVENANCE)
    except Exception:
        PROVENANCE_AVAILABLE = False


def sha256_of(path: Path) -> str | None:
    try:
        h = hashlib.sha256()
        with path.open("rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None


def has_custom_skill_block(path: Path) -> bool:
    """True if the file contains a CUSTOM:SKILL:BEGIN marker (a user edit that a
    fusebase update / CLI refresh would clobber)."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return "CUSTOM:SKILL:BEGIN" in text


def check_provenance(rel_path: str) -> None:
    """Emit an advisory CLI_SNAPSHOT_STALE finding if a present CLI asset's
    sha256 differs from the bundled provenance. Advisory only — never changes
    the verdict/exit code (these are filtered out of cli_drift below)."""
    if not PROVENANCE_AVAILABLE:
        return
    expected = PROVENANCE.get(rel_path)
    if not expected:
        return
    actual = sha256_of(root / rel_path)
    if actual is None:
        return
    if actual != expected:
        add(
            "CLI_SNAPSHOT_STALE", "cli", "cli-owned", rel_path,
            "advisory only; if intentional run bash hooks/local/stamp-cli-provenance.sh to re-stamp, "
            "or run the current FuseBase CLI refresh to align",
            "present asset differs from bundled provenance sha256 (newer or locally-modified copy)",
        )


def scan_custom_skill_block(rel_path: str) -> None:
    """Emit an advisory CLI_CUSTOM_AT_RISK finding when a CLI-owned skill file
    carries a CUSTOM:SKILL block — those edits are at risk on the next CLI
    refresh. Advisory only — never changes the verdict/exit code."""
    if has_custom_skill_block(root / rel_path):
        add(
            "CLI_CUSTOM_AT_RISK", "cli", "cli-owned", rel_path,
            "back up the CUSTOM:SKILL block; the next FuseBase CLI refresh may overwrite it",
            "CUSTOM:SKILL block found in a CLI-owned skill (at-risk on next refresh)",
        )


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return ""


def rel_exists(rel: str) -> bool:
    return (root / rel).exists()


def commands_in_settings(path: Path) -> list[str]:
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []
    commands: list[str] = []
    hooks = data.get("hooks") if isinstance(data, dict) else None
    if not isinstance(hooks, dict):
        return []
    for blocks in hooks.values():
        if not isinstance(blocks, list):
            continue
        for block in blocks:
            if not isinstance(block, dict):
                continue
            for hook in block.get("hooks") or []:
                if isinstance(hook, dict) and isinstance(hook.get("command"), str):
                    commands.append(hook["command"])
    return commands


def flow_skill_names() -> list[str]:
    skills_dir = root / "skills"
    if not skills_dir.is_dir():
        return []
    return sorted(
        p.name
        for p in skills_dir.iterdir()
        if p.is_dir() and (p / "SKILL.md").is_file()
    )


def flow_agent_names() -> list[str]:
    agents_dir = root / "agents"
    if not agents_dir.is_dir():
        return []
    return sorted(
        p.name
        for p in agents_dir.iterdir()
        if p.is_dir() and (p / "AGENT.md").is_file()
    )


def add(status: str, layer: str, owner: str, path: str, action: str, detail: str = "") -> None:
    findings.append({
        "status": status,
        "layer": layer,
        "owner": owner,
        "path": path,
        "action": action,
        "detail": detail,
    })


try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"[check-cli-flow-conflicts] invalid manifest JSON: {exc}", file=sys.stderr)
    sys.exit(2)

if manifest.get("schema_version") != 1:
    print("[check-cli-flow-conflicts] unsupported manifest schema_version", file=sys.stderr)
    sys.exit(2)

findings: list[dict[str, str]] = []
paths: list[dict[str, Any]] = manifest.get("paths") or []
flow_skills = flow_skill_names()
flow_agents = flow_agent_names()

for entry in paths:
    owner = entry.get("owner", "")
    rel = entry.get("path", "")
    required = bool(entry.get("required"))
    action = entry.get("flow_action") or entry.get("cli_action") or ""
    layer = {
        "cli-owned": "cli",
        "flow-owned": "flow",
        "shared-merge": "shared",
    }.get(owner, "unknown")

    if rel in {"AGENTS.md", "CLAUDE.md"}:
        path = root / rel
        if not path.exists():
            if required:
                add("MISSING", layer, owner, rel, action, "required file missing")
            else:
                add("INFO", layer, owner, rel, "optional file absent")
            continue
        text = read_text(path)
        if "Fusebase Flow" in text:
            add("OK", layer, owner, rel, action, "Flow marker present")
        else:
            add("DRIFT", layer, owner, rel, action, "Flow overlay marker missing")
        continue

    if rel == ".claude/settings.json":
        path = root / rel
        if not path.exists():
            add("INFO", layer, owner, rel, "Claude settings absent")
            continue
        commands = commands_in_settings(path)
        if not commands:
            add("DRIFT", layer, owner, rel, action, "settings is missing hook commands or is invalid JSON")
            continue
        has_flow_stop = any("hooks/handlers/stop.py" in c for c in commands)
        cli_hook_dir = root / ".claude" / "hooks"
        # Cross-platform node Stop hooks are the canonical wired set (B5 / v3.2.0).
        # run-typecheck-apps.js carries the CVE-2024-27980 shell:win32 patch;
        # quality-check-apps.js runs the app-quality checks. The jq/bash
        # duplicates (run-lint-on-stop.sh, run-typecheck-on-stop.sh) are
        # deprecated and intentionally not part of the expected wired set.
        expected_cli_markers = [
            "run-typecheck-apps.js",
            "quality-check-apps.js",
        ]
        missing_cli_hooks = [
            marker
            for marker in expected_cli_markers
            if (cli_hook_dir / marker).is_file()
            and not any(marker in c for c in commands)
        ]
        if has_flow_stop and not missing_cli_hooks:
            add("OK", layer, owner, rel, action, "Flow stop hook and existing CLI hooks preserved")
        elif not has_flow_stop:
            add("DRIFT", layer, owner, rel, action, "Flow stop hook missing")
        else:
            add("DRIFT", layer, owner, rel, action, "CLI Stop hooks not preserved: " + ", ".join(missing_cli_hooks))
        continue

    if rel == ".codex/config.toml":
        path = root / rel
        if not path.exists():
            add("INFO", layer, owner, rel, "Codex config absent")
            continue
        text = read_text(path)
        preserved_keys = [key for key in ("codex_hooks", "hooks_file", "skills_dir") if key in text]
        if preserved_keys:
            add("OK", layer, owner, rel, action, "non-MCP settings present: " + ", ".join(preserved_keys))
        else:
            add("INFO", layer, owner, rel, action, "no Flow non-MCP settings detected; do not overwrite if present")
        continue

    if "<cli-provider-skill>" in rel:
        known = entry.get("known_names") or []
        mirror_root = ".claude/skills" if rel.startswith(".claude/") else ".agents/skills"
        if not (root / mirror_root).is_dir():
            add("INFO", layer, owner, mirror_root, "provider skill mirror absent")
            continue
        for name in known:
            skill_path = f"{mirror_root}/{name}/SKILL.md"
            if rel_exists(skill_path):
                add("OK", layer, owner, skill_path, "current CLI owns provider skill text")
                # B3: advisory drift + CUSTOM-block scan for the present asset.
                check_provenance(skill_path)
                scan_custom_skill_block(skill_path)
                # Also advise on drift for any vendored references/ files.
                skill_dir = root / mirror_root / name
                for fp in sorted(skill_dir.rglob("*")):
                    if fp.is_file() and fp.name != "SKILL.md":
                        rp = str(fp.relative_to(root)).replace("\\", "/")
                        check_provenance(rp)
            else:
                add("MISSING", layer, owner, skill_path, "run current FuseBase CLI refresh/update first", "provider skill missing")
        continue

    if "<flow-skill>" in rel:
        mirror_root = ".claude/skills" if rel.startswith(".claude/") else ".agents/skills"
        if not flow_skills:
            add("INFO", layer, owner, mirror_root, "canonical Flow skills absent")
            continue
        for name in flow_skills:
            skill_path = f"{mirror_root}/{name}/SKILL.md"
            if rel_exists(skill_path):
                add("OK", layer, owner, skill_path, "Flow skill mirror present")
            else:
                add("MISSING", layer, owner, skill_path, "run bash hooks/local/post-fusebase-update.sh", "Flow skill mirror missing")
        continue

    if "<cli-provider-agent>" in rel:
        known = entry.get("known_names") or []
        mirror_root = ".claude/agents" if rel.startswith(".claude/") else ".codex/agents"
        if not (root / mirror_root).is_dir():
            add("INFO", layer, owner, mirror_root, "provider agent mirror absent")
            continue
        for name in known:
            agent_path = f"{mirror_root}/{name}.md"
            if rel_exists(agent_path):
                add("OK", layer, owner, agent_path, "current CLI owns provider agent")
                check_provenance(agent_path)
            else:
                add("MISSING", layer, owner, agent_path, "run current FuseBase CLI refresh/update first", "provider agent missing")
        continue

    if "<flow-agent>" in rel:
        mirror_root = ".claude/agents" if rel.startswith(".claude/") else ".codex/agents"
        if not flow_agents:
            add("INFO", layer, owner, mirror_root, "canonical Flow agents absent")
            continue
        for name in flow_agents:
            agent_path = f"{mirror_root}/{name}.md"
            if rel_exists(agent_path):
                add("OK", layer, owner, agent_path, "Flow agent mirror present")
            else:
                add("MISSING", layer, owner, agent_path, "run bash hooks/local/post-fusebase-update.sh", "Flow agent mirror missing")
        continue

    if "*" in rel:
        matches = [
            str(p.relative_to(root)).replace("\\", "/")
            for p in root.rglob("*")
            if fnmatch(str(p.relative_to(root)).replace("\\", "/"), rel)
        ]
        if matches:
            add("OK", layer, owner, rel, action, f"{len(matches)} path(s) present")
            # B3: advisory drift for vendored CLI-owned files matched by a glob
            # (e.g. .claude/hooks/**) that have a provenance entry.
            if layer == "cli":
                for m in matches:
                    if (root / m).is_file():
                        check_provenance(m)
        elif required:
            add("MISSING", layer, owner, rel, action, "required glob has no matches")
        else:
            add("INFO", layer, owner, rel, action, "optional glob has no matches")
        continue

    exists = rel_exists(rel)
    if exists:
        add("OK", layer, owner, rel, action)
    elif required:
        add("MISSING", layer, owner, rel, action, "required path missing")
    else:
        add("INFO", layer, owner, rel, action, "optional path absent")

broken = [f for f in findings if f["layer"] == "unknown" or f["status"] == "BROKEN"]
cli_drift = [f for f in findings if f["layer"] == "cli" and f["status"] in {"MISSING", "DRIFT"}]
shared_drift = [f for f in findings if f["layer"] == "shared" and f["status"] in {"MISSING", "DRIFT"}]
flow_drift = [f for f in findings if f["layer"] == "flow" and f["status"] in {"MISSING", "DRIFT"}]
# Advisory (B3): present-but-changed snapshots and at-risk CUSTOM blocks.
# These are INFORMATIONAL ONLY and deliberately excluded from cli_drift above,
# so they never change the verdict or exit code.
cli_stale = [f for f in findings if f["status"] == "CLI_SNAPSHOT_STALE"]
cli_custom_at_risk = [f for f in findings if f["status"] == "CLI_CUSTOM_AT_RISK"]

if broken:
    verdict = "BROKEN"
    exit_code = 2
elif cli_drift:
    verdict = "CLI_LAYER_DRIFT"
    exit_code = 1
elif shared_drift:
    verdict = "SHARED_MERGE_DRIFT"
    exit_code = 1
elif flow_drift:
    verdict = "FLOW_LAYER_DRIFT"
    exit_code = 1
else:
    verdict = "HEALTHY"
    exit_code = 0

if fmt == "json":
    print(json.dumps({
        "schema_version": manifest["schema_version"],
        "project_root": str(root),
        "manifest": str(manifest_path),
        "verdict": verdict,
        "summary": {
            "cli_drift": len(cli_drift),
            "shared_merge_drift": len(shared_drift),
            "flow_drift": len(flow_drift),
            "broken": len(broken),
            "cli_snapshot_stale": len(cli_stale),
            "cli_custom_at_risk": len(cli_custom_at_risk),
            "findings": len(findings),
        },
        "provenance_available": PROVENANCE_AVAILABLE,
        "findings": findings,
    }, indent=2))
else:
    print("")
    print("============================================================")
    print("Fusebase Flow - CLI/Flow Conflict Report")
    print("============================================================")
    print(f"Project root: {root}")
    print(f"Manifest: {manifest_path}")
    print(f"Manifest schema: {manifest['schema_version']}")
    print(f"Verdict: {verdict}")
    print("")
    print("Summary:")
    print(f"  CLI drift: {len(cli_drift)}")
    print(f"  Shared merge drift: {len(shared_drift)}")
    print(f"  Flow drift: {len(flow_drift)}")
    print(f"  Broken: {len(broken)}")
    print(f"  CLI snapshot stale (advisory): {len(cli_stale)}")
    print(f"  CLI CUSTOM at-risk (advisory): {len(cli_custom_at_risk)}")
    if not PROVENANCE_AVAILABLE:
        print("  (provenance manifest unavailable — drift advisory skipped; "
              "run bash hooks/local/stamp-cli-provenance.sh)")
    print("")
    print("Findings:")
    for f in findings:
        if f["status"] == "OK":
            continue
        detail = f" - {f['detail']}" if f.get("detail") else ""
        print(f"  [{f['status']}] {f['layer']} {f['path']}{detail}")
        if f.get("action"):
            print(f"      action: {f['action']}")
    if verdict == "HEALTHY" and not cli_stale and not cli_custom_at_risk:
        print("  No write conflict detected.")
    print("")
    print("Next action:")
    if verdict == "CLI_LAYER_DRIFT":
        print("  Run the current FuseBase CLI refresh/update for this project first, then rerun this report and Flow recovery.")
    elif verdict == "SHARED_MERGE_DRIFT":
        print("  Review shared files and run Flow recovery only for Flow overlay/merge additions.")
    elif verdict == "FLOW_LAYER_DRIFT":
        print("  Run: bash hooks/local/post-fusebase-update.sh")
    elif verdict == "BROKEN":
        print("  Inspect broken findings before running recovery.")
    else:
        print("  No action required.")
    print("============================================================")

sys.exit(exit_code)
PY
