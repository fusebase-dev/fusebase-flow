#!/usr/bin/env python3
"""Project agent variants from policies/agent-tools.yml (task-delegation § Agent tool reach).

TRIPWIRE: never read the profile through policy_loader (it merges the gitignored .local twin);
never touch base mirrors or the agent-mirror manifest.
"""
from __future__ import annotations

import argparse
import functools
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

PROFILE_REL = "policies/agent-tools.yml"
LOCAL_TWIN_REL = "policies/agent-tools.local.yml"
OWNERSHIP_REL = "hooks/local/fusebase-flow-overlays/agent-surface-ownership.json"
VARIANT_DIR = ".claude/agents"
SUFFIX = "-project"
MAX_PROFILE_BYTES = 65536
MAX_TOOLS = 32
AGENT_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")
# TRIPWIRE: fullmatch only. match() with `$` accepts a trailing newline, which injects frontmatter.
TOOL_RE = re.compile(r"[A-Z][A-Za-z0-9]{0,63}|mcp__[A-Za-z0-9][A-Za-z0-9_-]{0,127}__[A-Za-z0-9][A-Za-z0-9_.-]{0,127}")
DENY_CASEFOLD = {"askuserquestion", "agent", "task"}
MARKER_RE = re.compile(
    r"<!-- FUSEBASE-FLOW-GENERATED: agent variant; source agents/(?P<a>[a-z0-9][a-z0-9-]*)/AGENT\.md \+ policies/"
    r"agent-tools\.yml; sha256=(?P<h>[0-9a-f]{64}); regenerate via bash hooks/local/mirror-agents\.sh; do not hand-edit -->")
GIT_TIMEOUT = 15
TAG = "[mirror-agents]"
CHECK_ROWS = {
    "generated": "agent variant missing: {rel} (run mirror-agents.sh)",
    "regenerated": f"agent variant drift: {{rel}} != agents/{{agent}}/AGENT.md + {PROFILE_REL} (run mirror-agents.sh)",
    "preserved": f"agent variant edited by hand: {{rel}} (move the change into {PROFILE_REL}, delete it, run mirror-agents.sh)",
    "removed": "agent variant orphan: {rel} (run mirror-agents.sh to remove it)",
    "reserved": f"reserved agent name: {{rel}} (Flow generates this name from {PROFILE_REL})",
    "unsafe": "unsafe variant path: {rel}",
}


class ProfileError(Exception):
    pass


@functools.lru_cache(maxsize=None)
def _helper():
    path = Path(__file__).with_name("recovery-owned-write.py")
    spec = importlib.util.spec_from_file_location("flow_agent_profile_owned_write", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _one_line(value) -> str:
    return " ".join(str(value).split()).encode("ascii", "backslashreplace").decode("ascii")


def _show(value) -> str:
    text = ascii(value)
    return text if len(text) <= 80 else text[:77] + "..."


def _yaml():
    try:
        import yaml
    except ImportError as exc:
        raise ProfileError(f"PyYAML is required to read {PROFILE_REL}") from exc
    return yaml


def canonical_agents(root: Path) -> list[str]:
    base = root / "agents"
    return sorted(d.name for d in base.iterdir()
                  if d.is_dir() and not d.is_symlink()
                  and (d / "AGENT.md").is_file() and not (d / "AGENT.md").is_symlink()) if base.is_dir() else []


def cli_reserved(root: Path) -> set[str]:
    try:
        doc = json.loads((root / OWNERSHIP_REL).read_text(encoding="utf-8"))
        return {name for entry in doc["paths"] if "<cli-provider-agent>" in entry.get("path", "")
                for name in entry.get("known_names") or []}
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
        raise ProfileError(f"cannot read CLI agent names from {OWNERSHIP_REL}: {_one_line(exc)}") from exc


def _tools(agent: str, tools) -> list[str]:
    if not isinstance(tools, list) or not tools:
        raise ProfileError(f"agent '{agent}': add_tools must be a non-empty list")
    if len(tools) > MAX_TOOLS:
        raise ProfileError(f"agent '{agent}': add_tools has {len(tools)} entries; at most {MAX_TOOLS}")
    seen: list[str] = []
    for index, tool in enumerate(tools):
        where = f"agent '{agent}' add_tools[{index}] = {_show(tool)}"
        if not isinstance(tool, str):
            raise ProfileError(f"{where}: not a string")
        folded = tool.casefold()
        if folded == "askuserquestion":
            raise ProfileError(f"{where}: FR-19, popup question tools are never granted")
        if folded in DENY_CASEFOLD:
            raise ProfileError(f"{where}: delegation tools are not input reach")
        if not TOOL_RE.fullmatch(tool):
            raise ProfileError(f"{where}: not a tool name (built-in PascalCase or mcp__<server>__<tool>)")
        if tool in seen:
            raise ProfileError(f"{where}: duplicate")
        seen.append(tool)
    return seen


def load_profile(root: Path) -> dict[str, list[str]] | None:
    path = root / PROFILE_REL
    if not (path.exists() or path.is_symlink()):
        return None
    try:
        _helper().reject_symlinks(root, path, "profile")
    except RuntimeError as exc:
        raise ProfileError(_one_line(exc)) from exc
    if not path.is_file():
        raise ProfileError(f"{PROFILE_REL} is not a regular file")
    if path.stat().st_size > MAX_PROFILE_BYTES:
        raise ProfileError(f"{PROFILE_REL} is larger than {MAX_PROFILE_BYTES} bytes")
    yaml = _yaml()
    try:
        doc = yaml.safe_load(path.read_bytes().decode("utf-8-sig"))
    except (UnicodeDecodeError, yaml.YAMLError) as exc:
        raise ProfileError(f"{PROFILE_REL} is not valid UTF-8 YAML: {_one_line(exc)}") from exc
    if not isinstance(doc, dict):
        raise ProfileError(f"{PROFILE_REL} must be a mapping with schema_version and agents")
    for key in doc:
        if key not in ("schema_version", "agents"):
            raise ProfileError(f"unsupported key {_show(key)}; the profile has schema_version and agents only")
    version = doc.get("schema_version")
    if type(version) is not int or version != 1:
        raise ProfileError(f"schema_version must be 1, got {_show(version)}")
    agents = doc.get("agents")
    if not isinstance(agents, dict):
        raise ProfileError("agents must be a mapping (write 'agents: {}' for none)")
    canonical = canonical_agents(root)
    reserved = cli_reserved(root)
    valid = ", ".join(canonical)
    out: dict[str, list[str]] = {}
    for name, entry in agents.items():
        if not isinstance(name, str) or not AGENT_RE.fullmatch(name):
            raise ProfileError(f"unknown agent {_show(name)}; valid: {valid}")
        if name.endswith(SUFFIX):
            raise ProfileError(f"agent '{name}': reserved suffix '{SUFFIX}'; list the Flow agent, Flow generates the variant")
        if name in reserved:
            raise ProfileError(f"agent '{name}' is a CLI-owned agent; the profile covers Flow agents only")
        if name not in canonical:
            raise ProfileError(f"unknown agent '{name}'; valid: {valid}")
        if not isinstance(entry, dict):
            raise ProfileError(f"agent '{name}' must map to {{add_tools: [...]}}")
        for key in entry:
            if key != "add_tools":
                raise ProfileError(f"profiles only add tools; {_show(key)} is not supported (agent '{name}')")
        out[name] = _tools(name, entry.get("add_tools"))
    return out


def _parse_canonical(agent: str, raw: bytes):
    yaml = _yaml()
    source = f"agents/{agent}/AGENT.md"
    lf = _helper().lf_form(raw)
    try:
        lines = lf.decode("utf-8").split("\n")
        if lines[0] != "---":
            raise ValueError
        k = lines.index("---", 1)
    except (UnicodeDecodeError, ValueError) as exc:
        raise ProfileError(f"{source}: no UTF-8 '---' fenced frontmatter") from exc
    front = lines[1:k]
    try:
        meta = yaml.safe_load("\n".join(front))
        for key in ("name", "description", "tools"):
            rows = [line for line in front if line.startswith(f"{key}:")]
            single = yaml.safe_load(rows[0]) if len(rows) == 1 else None
            if not isinstance(meta, dict) or not isinstance(meta.get(key), str) \
                    or not isinstance(single, dict) or single.get(key) != meta[key]:
                raise ProfileError(f"{source}: '{key}:' must be exactly one single-line string")
    except yaml.YAMLError as exc:
        raise ProfileError(f"{source}: frontmatter is not YAML: {_one_line(exc)}") from exc
    if meta["name"] != agent:
        raise ProfileError(f"{source}: name is {_show(meta['name'])}, expected '{agent}'")
    base = [tool.strip() for tool in meta["tools"].split(",")]
    if not all(base):
        raise ProfileError(f"{source}: 'tools:' must be a non-empty comma list")
    return lines, k, meta, base, lf != raw


def compose(agent: str, canon_bytes: bytes, added: list[str]) -> bytes:
    lines, k, meta, base, crlf = _parse_canonical(agent, canon_bytes)
    added = [tool for tool in added if tool not in base]
    if not added:
        raise ProfileError(f"agent '{agent}': no tool to add")
    suffix = (f"Project variant with added tools {', '.join(added)} from {PROFILE_REL}; "
              "dispatch it only for tasks whose Inputs need them.")
    name, description, tools = f"{agent}{SUFFIX}", f"{meta['description']} {suffix}", ", ".join(base + added)
    front = []
    for line in lines[1:k]:
        if line.startswith("name:"):
            line = f"name: {name}"
        elif line.startswith("description:"):
            line = "description: " + json.dumps(description, ensure_ascii=False)
        elif line.startswith("tools:"):
            line = f"tools: {tools}"
        front.append(line)
    yaml = _yaml()
    try:
        echo = yaml.safe_load("\n".join(front))
    except yaml.YAMLError:
        echo = None
    if not isinstance(echo, dict) or (echo.get("name"), echo.get("description"), echo.get("tools")) \
            != (name, description, tools):
        raise ProfileError(f"agent '{agent}': composed frontmatter does not round-trip; nothing written")
    head = "---\n" + "\n".join(front) + "\n---\n"
    body = "\n".join(lines[k + 1:])
    digest = hashlib.sha256((head + body).encode("utf-8")).hexdigest()
    marker = (f"<!-- FUSEBASE-FLOW-GENERATED: agent variant; source agents/{agent}/AGENT.md + {PROFILE_REL}; "
              f"sha256={digest}; regenerate via bash hooks/local/mirror-agents.sh; do not hand-edit -->")
    text = head + "\n" + marker + "\n" + body
    return (text.replace("\n", "\r\n") if crlf else text).encode("utf-8")


def owned(raw: bytes, agent: str) -> bool:
    try:
        lines = _helper().lf_form(raw).decode("utf-8").split("\n")
        if lines[0] != "---":
            return False
        k = lines.index("---", 1)
        match = MARKER_RE.fullmatch(lines[k + 2])
    except (UnicodeDecodeError, ValueError, IndexError):
        return False
    if lines[k + 1] != "" or not match or match["a"] != agent:
        return False
    head = "\n".join(lines[:k + 1]) + "\n"
    body = "\n".join(lines[k + 3:])
    return hashlib.sha256((head + body).encode("utf-8")).hexdigest() == match["h"]


def plan(root: Path) -> tuple[bool, dict[str, tuple[str, bytes]], list[str]]:
    profile = load_profile(root)
    desired: dict[str, tuple[str, bytes]] = {}
    notes: list[str] = []
    for agent, tools in (profile or {}).items():
        raw = (root / "agents" / agent / "AGENT.md").read_bytes()
        base = _parse_canonical(agent, raw)[3]
        notes += [f"{agent}: {tool} is already in agents/{agent}/AGENT.md; skipped" for tool in tools if tool in base]
        added = [tool for tool in tools if tool not in base]
        if not added:
            notes.append(f"{agent}: no added tools, so no variant")
            continue
        desired[f"{VARIANT_DIR}/{agent}{SUFFIX}.md"] = (agent, compose(agent, raw, added))
    return profile is not None, desired, notes


def _scan(root: Path, desired: dict[str, tuple[str, bytes]]) -> list[tuple[str, str, str, bytes | None]]:
    canonical = set(canonical_agents(root))
    rels = set(desired)
    variant_dir = root / VARIANT_DIR
    if variant_dir.is_dir():
        rels.update(f"{VARIANT_DIR}/{path.name}" for path in variant_dir.glob(f"*{SUFFIX}.md"))
    lf_form = _helper().lf_form
    rows = []
    for rel in sorted(rels):
        agent = rel.rsplit("/", 1)[1][:-len(f"{SUFFIX}.md")]
        if rel not in desired and agent not in canonical:
            orphan = None
            try:
                _helper().reject_symlinks(root, root / rel, "variant")
                if (root / rel).is_file():
                    orphan = (root / rel).read_bytes()
            except RuntimeError:
                orphan = None
            # TRIPWIRE: only a marker-verified Flow variant is removed; any other *-project file is the project's.
            rows.append(("removed", rel, agent, orphan) if orphan is not None and owned(orphan, agent)
                        else ("ignored", rel, agent, None))
            continue
        target = root / rel
        try:
            _helper().reject_symlinks(root, target, "variant")
            if target.exists() and not target.is_file():
                raise RuntimeError("not a regular file")
        except RuntimeError:
            rows.append(("unsafe", rel, agent, None))
            continue
        raw = target.read_bytes() if target.exists() else None
        if rel not in desired:
            state = "removed" if raw is not None and owned(raw, agent) else "reserved"
        elif raw is None:
            state = "generated"
        elif lf_form(raw) == lf_form(desired[rel][1]):
            state = "current"
        else:
            state = "regenerated" if owned(raw, agent) else "preserved"
        rows.append((state, rel, agent, raw))
    return rows


def _unchanged(target: Path, raw: bytes | None) -> bool:
    if raw is None:
        return not target.exists() and not target.is_symlink()
    return target.is_file() and not target.is_symlink() and target.read_bytes() == raw


def apply(root: Path) -> int:
    with _helper().recovery_lock(root):
        if (root / LOCAL_TWIN_REL).exists():
            print(f"{TAG} ignored {LOCAL_TWIN_REL}: only the committed {PROFILE_REL} is read", file=sys.stderr)
        try:
            present, desired, notes = plan(root)
        except ProfileError as exc:
            print(f"{TAG} agent tool profile invalid: {_one_line(exc)}", file=sys.stderr)
            return 2
        for note in notes:
            print(f"{TAG} {note}", file=sys.stderr)
        counts = dict.fromkeys(("generated", "current", "removed", "preserved"), 0)
        rc, shown = 0, present
        for state, rel, _agent, raw in _scan(root, desired):
            if state == "ignored":
                continue
            shown = True
            target = root / rel
            if state == "current":
                counts["current"] += 1
            elif state == "unsafe":
                print(f"{TAG} unsafe variant path: {rel} (symlink or not a regular file; left alone)", file=sys.stderr)
                rc = max(rc, 1 if rel in desired else 0)
            elif state == "reserved":
                print(f"{TAG} reserved agent name: {rel} (generated from {PROFILE_REL}; left alone)", file=sys.stderr)
            elif state == "preserved" or not _unchanged(target, raw):
                print(f"{TAG} preserved {rel} (hand-edited or not Flow-generated; move the change into "
                      f"{PROFILE_REL}, delete the file, re-run)", file=sys.stderr)
                counts["preserved"] += 1
                rc = 1
            elif state == "removed":
                target.unlink()
                counts["removed"] += 1
            else:
                _helper().atomic_bytes(target, desired[rel][1])
                counts["generated"] += 1
        if shown:
            print(f"{TAG} project variants: {'; '.join(f'{key} {value}' for key, value in counts.items())} ({PROFILE_REL})")
        return rc


def _uncommitted(root: Path) -> bool:
    def git(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", *args], cwd=root, capture_output=True, timeout=GIT_TIMEOUT)
    try:
        inside = git("rev-parse", "--is-inside-work-tree")
        if inside.returncode != 0 or inside.stdout.strip() != b"true":
            return False
        if git("ls-files", "--error-unmatch", "--", PROFILE_REL).returncode != 0:
            return True
        if git("rev-parse", "--verify", "-q", "HEAD^{commit}").returncode != 0:
            return True
        return git("diff", "--quiet", "HEAD", "--", PROFILE_REL).returncode == 1
    except (OSError, subprocess.SubprocessError):
        return False


def check(root: Path) -> int:
    if (root / LOCAL_TWIN_REL).exists():
        print(f"WARN ignored {LOCAL_TWIN_REL}: only the committed {PROFILE_REL} is read")
    try:
        present, desired, notes = plan(root)
    except ProfileError as exc:
        print(f"ERROR {_one_line(exc)}")
        return 0
    if present and _uncommitted(root):
        print(f"WARN {PROFILE_REL} is not committed; variants reflect an uncommitted profile")
    for note in notes:
        print(f"NOTE {note}")
    current = 0
    for state, rel, agent, _raw in _scan(root, desired):
        if state == "current":
            current += 1
        elif state in CHECK_ROWS:
            print("WARN " + _one_line(CHECK_ROWS[state].format(rel=rel, agent=agent)))
    if current:
        print(f"NOTE agent variants current: {current}")
    return 0


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        getattr(stream, "reconfigure", lambda **_: None)(errors="backslashreplace")
    parser = argparse.ArgumentParser(description=f"Generate or check {VARIANT_DIR}/<agent>{SUFFIX}.md from {PROFILE_REL}.")
    parser.add_argument("command", choices=("apply", "check"))
    parser.add_argument("--root", required=True)
    args = parser.parse_args(argv)
    try:
        root = _helper().native_path(args.root).resolve()
        return apply(root) if args.command == "apply" else check(root)
    except Exception as exc:
        if args.command == "check":
            print(f"ERROR crash: {_one_line(exc)}")
        else:
            print(f"{TAG} agent tool profile step crashed: {_one_line(exc)}", file=sys.stderr)
        return 99


if __name__ == "__main__":
    raise SystemExit(main())
