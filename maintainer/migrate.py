#!/usr/bin/env python3
"""`python maintainer/flow.py migrate --target DIR [--providers claude,codex] [--full]`.

Moves a project from its Fusebase Flow 5.x install onto the 6.0 core (handoff WP 12). A dry run by
default: it prints the lists (remove, replace, new, never touch, keep, consumer references, hidden)
and changes nothing.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

import flow

MC_MANIFEST = "audit/managed-content-manifest.json"
SKILL_MIRRORS = "audit/skill-mirror-manifest.txt"
AGENT_MIRRORS = "audit/agent-mirror-manifest.txt"
CLI_VENDOR = "audit/cli-vendor-manifest.json"
CLI_UPSTREAM = "audit/cli-upstream-manifest.json"
# Flow 5.x files no manifest records; on Onboarding each is byte-identical to Flow v5.6.
AUDIT_5X = ("audit/README.md", AGENT_MIRRORS, CLI_UPSTREAM, CLI_VENDOR,
            "audit/hook-layer-manifest.json", MC_MANIFEST, SKILL_MIRRORS)
# The four records 5.x tooling writes per project go when they parse as their writer lays them out (identical in
# v5.1 to v5.11), whatever their bytes (owner, 2026-10-17): schema_version, top-level keys, keys every asset has, more
# keys an asset may have. stamp-cli-provenance.sh writes the vendor record, refresh-cli-vendor.sh the upstream one.
JSON_RECORDS = {
    CLI_VENDOR: (2, {"schema_version", "generated_at", "source_cli_version", "reviewed_cli_policy", "description",
                     "asset_count", "assets"}, {"path", "sha256"}, {"upstream_sha256", "merge_derived", "matches_upstream"}),
    CLI_UPSTREAM: (1, {"schema_version", "generated_at", "cli_version", "description", "asset_count",
                       "superseded_custom_blocks", "assets"}, {"path", "upstream_source", "upstream_sha256",
                                                               "merge_derived"}, set()),
}
# mirror-skills.sh and mirror-agents.sh: one row per mirror, MANIFEST_ROW of 5.x hooks/local/lib/recovery-owned-write.py
MIRROR_RECORDS = {SKILL_MIRRORS: (".claude/skills/", ".agents/skills/"), AGENT_MIRRORS: (".claude/agents/", ".codex/agents/")}
MIRROR_ROW = re.compile(r"(.+?)  ([0-9a-f]{64})")
ROOT_5X = ("GEMINI.md", "install.sh")
ORPHANS = ("policies/model-routing.local.yml",)  # override of a policy the core drops
# A file deleted by its name goes only when its bytes match Flow's own: a recorded sha256 where the 5.x install has one,
# else this table of each 5.x release's bytes (maintainer/flow5_table.py writes it; maintainer data, never installed).
FLOW5_TABLE = Path(__file__).resolve().parent / "flow5-sha256.json"
REFERENCE = {"policies/model-routing.local.yml": "policies/model-routing.yml"}  # a copy of the shipped default
COMMANDS_SRC = "hooks/local/fusebase-flow-overlays/commands/"
GIT_HOOKS = ("pre-commit", "commit-msg", "pre-push")
HOOK_MARKER = b"fusebase-flow-managed-hook:"
BASELINE = flow.BASELINE
CLI_DOCS = ("docs/north-star.md", "docs/audience.md", "docs/product.md", "docs/business-logic.md")
CLI_OWNED = flow.NEVER_TOUCH + (".cursor/mcp.json",) + CLI_DOCS
CLI_DIRS = (".claude", ".codex", ".cursor", ".codex-plugin", ".agents")
CONSUMER_DIRS = ("workflows", "scripts", ".claude")
HISTORY_DIRS = ("docs/tmp",)
REWRITTEN = ("AGENTS.md", "CLAUDE.md", "VERSION", ".gitignore", flow.ATTRIBUTES)  # backed up, rewritten in place
DOCS = flow.DOCUMENTS
GROUPS = ("manifest assets", "skill mirrors", "agent mirrors", "command mirrors", "old audit records",
          "5.x root files", "orphan local overrides", "bytecode under hooks/", "old git hooks")
HEADING = re.compile(rb"^## FuseBase Flow[^\r\n]*", re.M)
H2 = re.compile(rb"^## ", re.M)
WORD = re.compile(r"[\w./-]+")
WRAP_BEGIN, WRAP_END = flow.WRAP_BEGIN.encode(), flow.WRAP_END.encode()
P_BEGIN, P_END = flow.PRESERVE_BEGIN.encode(), flow.PRESERVE_END.encode()


class Abort(Exception):
    """Stops the run before anything is written; the message names the file."""


@dataclass
class Overlay:
    name: str
    heading: str
    head: int  # byte offset of the heading in the file as committed (LF)
    start: int  # raw offsets of the replaced span: the CUSTOM:SKILL wrapper when there is one
    end: int
    wrapped: bool
    preserve: bytes  # FLOW:PRESERVE region, its BEGIN marker to its END marker, raw bytes
    crlf: bool
    size_lf: int
    start_lf: int
    end_lf: int

    def preserve_lf(self) -> int:
        return len(self.preserve) - self.preserve.count(b"\r\n")


@dataclass
class Inventory:
    target: Path
    providers: set[str]
    version: str
    remove: dict[str, list[str]] = field(default_factory=lambda: {g: [] for g in GROUPS})
    replace: list[str] = field(default_factory=list)
    identical: list[str] = field(default_factory=list)
    new: list[str] = field(default_factory=list)
    never: dict[str, list[str]] = field(default_factory=dict)
    keep: dict[str, list[str]] = field(default_factory=dict)
    changed: list[str] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)
    recorded: dict[str, str] = field(default_factory=dict)  # Flow file -> recorded sha256 ("" = none)
    consumers: dict[str, list[str]] = field(default_factory=dict)
    history: dict[str, list[str]] = field(default_factory=dict)
    hidden: list[str] = field(default_factory=list)
    overlays: dict[str, Overlay] = field(default_factory=dict)
    rows: list[str] = field(default_factory=list)
    custom_hooks: list[str] = field(default_factory=list)  # .git/hooks files without Flow's marker: the preflight stops
    edited_hooks: list[str] = field(default_factory=list)  # with the marker, bytes of no 5.x release: it stops too
    foreign: list[str] = field(default_factory=list)  # named like a 5.x file, not Flow's bytes: backed up, left in place
    own_mirrors: list[str] = field(default_factory=list)  # 5.x mirrors of the project's own skills and agents: kept
    wiring: str = ""
    vendor: tuple[int, int, int] = (0, 0, 0)
    manifest: tuple[int, int] = (0, 0)  # assets recorded in the managed-content manifest, present
    head: str = ""
    branch: str = ""
    task: str = ""
    version_is_flow: bool = True  # VERSION is Flow's (reads the manifest's flow_version) or absent

    def removals(self) -> list[str]:
        return [p for g in GROUPS for p in self.remove[g]]


def git(target: Path, *args: str, data: bytes | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=target, input=data, capture_output=True, timeout=600)


def ls_files(target: Path, *paths: str) -> list[str]:
    out = git(target, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *paths).stdout
    return sorted({p for p in out.decode("utf-8", "replace").split("\0") if p})


def load_assets(path: Path) -> dict[str, str]:
    try:
        return {a["path"]: a["sha256"] for a in json.loads(path.read_text(encoding="utf-8"))["assets"]}
    except (OSError, ValueError, KeyError, TypeError):
        return {}


def load_mirrors(path: Path) -> dict[str, str]:
    """{mirror path: recorded sha256} from the rows in the 5.x format; any other line is not a row."""
    try:
        lines = path.read_bytes().decode("utf-8", "replace").split("\n")
    except OSError:
        return {}
    rows = (MIRROR_ROW.fullmatch(line.rstrip("\r")) for line in lines)
    return {r.group(1): r.group(2) for r in rows if r}


def is_5x_record(rel: str, data: bytes) -> bool:
    """A per-project 5.x record laid out as its 5.x writer writes it (JSON_RECORDS, MIRROR_RECORDS)."""
    try:
        text = data.decode("utf-8")
        if rel in MIRROR_RECORDS:
            rows = [MIRROR_ROW.fullmatch(line.rstrip("\r")) for line in text.split("\n") if line.strip()]
            return bool(rows) and all(r and r.group(1).startswith(MIRROR_RECORDS[rel]) and mirror_source(r.group(1))
                                      for r in rows)
        version, top, need, extra = JSON_RECORDS[rel]
        doc = json.loads(text)
        assets = doc["assets"]
        return (set(doc) == top and doc["schema_version"] == version and isinstance(assets, list)
                and doc["asset_count"] == len(assets)
                and all(isinstance(a, dict) and need <= set(a) <= need | extra and isinstance(a["path"], str)
                        and all(re.fullmatch(r"[0-9a-f]{64}", str(a[k])) for k in need if k.endswith("sha256"))
                        for a in assets))
    except (ValueError, KeyError, TypeError, AttributeError):
        return False


_FLOW5: dict[str, dict[str, str]] = {}


def flow5_shas(rel: str) -> set[str]:
    """The sha256 of `rel` (or the shipped file it copies) in each Flow 5.x release."""
    if not _FLOW5:
        _FLOW5.update(json.loads(FLOW5_TABLE.read_text(encoding="utf-8"))["files"])
    return set(_FLOW5.get(REFERENCE.get(rel, rel), {}))


def self_recorded(data: bytes) -> bool:
    """A 5.x manifest whose manifest_self_sha256 verifies, computed as 5.x's managed_content_manifest.py does."""
    try:
        doc = json.loads(data.decode("utf-8"))
        payload = json.dumps({"schema_version": doc.get("schema_version"), "flow_version": doc.get("flow_version", ""),
                              "assets": doc.get("assets")}, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(payload.encode("utf-8")).hexdigest() == doc.get("manifest_self_sha256")
    except (ValueError, AttributeError):
        return False


def mirror_source(rel: str) -> str:
    """The canonical file a 5.x mirror copies (mirror-skills.sh, mirror-agents.sh), "" for any other path."""
    parts = rel.split("/")
    if len(parts) > 3 and parts[0] in (".claude", ".agents") and parts[1] == "skills":
        return "/".join(["flow-skills", *parts[2:]])
    if len(parts) == 3 and parts[0] in (".claude", ".codex") and parts[1] == "agents" and parts[2].endswith(".md"):
        return f"agents/{parts[2][:-3]}/AGENT.md"
    return ""


def walk_files(root: Path, rel: str) -> list[str]:
    base = root / rel
    found = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            found.append(Path(dirpath, name).relative_to(root).as_posix())
    return sorted(found)


def hooks_dir(target: Path) -> Path:
    if (target / ".git").is_dir():
        return target / ".git" / "hooks"
    common = git(target, "rev-parse", "--git-common-dir").stdout.decode().strip()
    return (target / common / "hooks").resolve()


def lf_offset(raw: bytes, pos: int) -> int:
    return pos - raw.count(b"\r\n", 0, pos)


def find_overlay(target: Path, name: str) -> Overlay | None:
    path = target / name
    if not path.is_file():
        return None
    raw = path.read_bytes()
    heads = list(HEADING.finditer(raw))
    if not heads and name != "AGENTS.md":
        return None  # no 5.x Flow section here: install appends the 6.0 block
    if len(heads) != 1:
        nxt = [m.start() for m in H2.finditer(raw)]
        at = nxt[-1] if nxt else max(0, len(raw) - 200)
        what = "no heading" if not heads else f"{len(heads)} headings"
        raise Abort(f"{name}: {what} beginning '## FuseBase Flow'; nothing replaced. "
                    f"The 200 bytes after byte {at:,} (the last level-2 heading): {raw[at:at + 200]!r}")
    m = heads[0]
    h = m.start()
    # The operator's FLOW:PRESERVE region belongs to the section whole, '## ' lines inside it included: the section
    # runs to the first level-2 heading after its END marker (or after the heading when there is no region).
    p = raw.find(P_BEGIN, m.end())
    q = raw.find(P_END, p) if p >= 0 else -1
    if p >= 0 and (q < 0 or raw.find(P_BEGIN, p + len(P_BEGIN)) >= 0):
        raise Abort(f"{name}: the FLOW:PRESERVE region after '## FuseBase Flow' "
                    f"{'has no END marker' if q < 0 else 'is not the only one'}; nothing replaced")
    nxt = H2.search(raw, q + len(P_END) if q >= 0 else m.end())
    end = nxt.start() if nxt else len(raw)
    start, wrapped = h, False
    b = raw.rfind(WRAP_BEGIN, 0, h)
    if b >= 0 and raw[b + len(WRAP_BEGIN):h].strip() in (b"", b"---"):
        e = raw.find(WRAP_END, h)
        inner = [x.start() for x in H2.finditer(raw, m.end(), e if e >= 0 else len(raw)) if not p <= x.start() < q]
        if e < 0 or inner or raw.find(WRAP_BEGIN, h, e) >= 0 or (p >= 0 and not h < p < q < e):
            raise Abort(f"{name}: the CUSTOM:SKILL wrapper around '## FuseBase Flow' does not close "
                        "around that section alone; nothing replaced")
        start, wrapped = b, True
        end = e + len(WRAP_END)
        end += 2 if raw[end:end + 2] == b"\r\n" else 1 if raw[end:end + 1] == b"\n" else 0
    first = raw.find(b"\n")
    return Overlay(name, m.group(0).decode("utf-8", "replace"), lf_offset(raw, h), start, end, wrapped,
                   raw[p:q] if q > p >= 0 else b"", first > 0 and raw[first - 1:first] == b"\r",
                   lf_offset(raw, len(raw)), lf_offset(raw, start), lf_offset(raw, end))


def cli_owned(rel: str, vendor: dict[str, str], cli_skills: set[str]) -> bool:
    parts = rel.split("/")
    return (flow.matches(rel, CLI_OWNED) or rel in vendor
            or (len(parts) > 2 and parts[0] in (".claude", ".agents") and parts[1] == "skills"
                and parts[2] in cli_skills))


def wiring(target: Path) -> str:
    claude = "no .claude/settings.json"
    try:
        hooks = json.loads((target / ".claude/settings.json").read_text(encoding="utf-8")).get("hooks", {})
        events = {ev: json.dumps(v) for ev, v in hooks.items()}
        flow_events = sorted(ev for ev, v in events.items() if "hooks/handlers" in v or "run-handler" in v)
        cli_events = sorted(ev for ev, v in events.items() if ".claude/hooks/" in v)
        cli = f"CLI {'/'.join(cli_events)} hooks only" if cli_events else "no CLI hooks"
        claude = f"{cli}, flow {'wired (' + '/'.join(flow_events) + ')' if flow_events else 'unenforced'}"
    except (OSError, ValueError, AttributeError):
        pass
    codex = "unenforced"
    try:
        if "hooks/handlers" in (target / ".codex/hooks.json").read_text(encoding="utf-8"):
            codex = "flow wired"
    except OSError:
        pass
    return f"claude: {claude}; codex: {codex}"


def next_task(target: Path) -> str:
    log = git(target, "log", "--format=%s").stdout.decode("utf-8", "replace")
    numbers = [int(n) for n in re.findall(r"\bT(\d+)", log)]
    return f"T{max(numbers, default=0) + 1}"


def reference_tokens(inv: Inventory) -> tuple[set[str], set[str], set[str]]:
    """(retired paths, retired skill names, word tokens: hyphenated workflow/policy stems and agent types)."""
    paths = {p for g in GROUPS[:7] for p in inv.remove[g]}
    skills = {p.split("/")[1] for p in paths if p.startswith("flow-skills/")}
    skills |= {p.split("/")[2] for p in paths if p.split("/")[1:2] == ["skills"] and len(p.split("/")) > 3}
    words = {p.split("/")[1] for p in paths if p.startswith("agents/") and p.count("/") == 2}
    words |= {Path(p).stem for p in paths if p.startswith(".claude/agents/") or p.startswith(".codex/agents/")}
    words |= {Path(p).stem for p in paths
              if p.split("/")[0] in ("workflows", "policies") and "-" in Path(p).stem and p.count("/") == 1}
    return paths, skills, words


def mentions(text: str, paths: set[str], skills: set[str], words: set[str]) -> set[str]:
    found = set()
    for word in set(WORD.findall(text)):
        parts = word.strip("./").split("/")
        for i, part in enumerate(parts):
            tail = "/".join(parts[i:])
            if tail in paths and (i == 0 or "/" in tail):  # a root file matches only as the whole word
                found.add(tail)
            if part.split(".")[0] in words:
                found.add(part.split(".")[0])
            if part in ("flow-skills", "skills") and i + 1 < len(parts) and parts[i + 1] in skills:
                found.add(f"{part}/{parts[i + 1]}")
    return found


def scan(inv: Inventory, dirs: tuple[str, ...], skip: set[str]) -> dict[str, list[str]]:
    paths, skills, words = reference_tokens(inv)
    hits: dict[str, list[str]] = {}
    for rel in ls_files(inv.target, *dirs):
        if rel in skip:
            continue
        try:
            data = (inv.target / rel).read_bytes()
        except OSError:
            continue
        if b"\0" in data[:8192]:
            continue
        found = mentions(data.decode("utf-8", "replace"), paths, skills, words)
        if found:
            hits[rel] = sorted(found)
    return hits


def inventory(target: Path, providers: set[str]) -> Inventory:
    try:
        flow_version = str(json.loads((target / MC_MANIFEST).read_text(encoding="utf-8")).get("flow_version") or "5.x")
    except (OSError, ValueError, AttributeError) as exc:
        raise Abort(f"{MC_MANIFEST} is unreadable ({exc}); nothing changed")
    inv = Inventory(target, providers, flow_version)
    version_file = target / "VERSION"
    inv.version_is_flow = not version_file.is_file() or version_file.read_text(encoding="utf-8").strip() == flow_version
    mc = load_assets(target / MC_MANIFEST)
    inv.manifest = (len(mc), sum(1 for p in mc if (target / p).is_file()))
    vendor = load_assets(target / CLI_VENDOR)
    cli_skills = flow.cli_skill_names(target)
    groups: dict[str, str] = {p: "manifest assets" for p in mc}
    inv.recorded = dict(mc)
    for group, manifest in (("skill mirrors", SKILL_MIRRORS), ("agent mirrors", AGENT_MIRRORS)):
        for p, sha in load_mirrors(target / manifest).items():
            src = mirror_source(p)  # a manifest row alone never makes a mirror Flow's: its source must be Flow's
            if src and (src in mc or flow5_shas(src)):
                groups[p], inv.recorded[p] = group, sha
            elif (target / p).is_file() and not cli_owned(p, vendor, cli_skills):
                inv.own_mirrors.append(p)
    by_name: dict[str, set[str]] = {}  # path -> the sha256 values that make it Flow's own (deleted by its name)
    for cmd in sorted((target / ".claude/commands").glob("*.md")):
        if COMMANDS_SRC + cmd.name in mc:
            rel = f".claude/commands/{cmd.name}"
            groups[rel], inv.recorded[rel] = "command mirrors", ""
            by_name[rel] = {mc[COMMANDS_SRC + cmd.name]} | flow5_shas(rel)
    for group, paths in (("old audit records", AUDIT_5X), ("5.x root files", ROOT_5X),
                         ("orphan local overrides", ORPHANS)):
        for p in paths:
            if p not in groups:  # a manifest asset keeps its recorded sha256 (audit/hook-layer-manifest.json)
                groups[p], inv.recorded[p] = group, ""
                by_name[p] = flow5_shas(p)
    plan = flow.planned_files(providers)
    plan_paths = set(plan) | {flow.MANIFEST}
    if (target / BASELINE).is_file() and BASELINE in plan:
        # install carries these rows into the core's baseline (flow.project_rows); the dry run names them
        inv.rows = flow.project_rows((target / BASELINE).read_bytes(), plan[BASELINE], set(groups) | plan_paths)
        plan[BASELINE] = flow.with_rows(plan[BASELINE], inv.rows)
    for rel in sorted(groups):
        sha = inv.recorded[rel]
        f = target / rel
        if not f.is_file():
            if sha:
                inv.missing.append(rel)
            continue
        if cli_owned(rel, vendor, cli_skills):
            inv.never.setdefault("recorded by Flow 5.x but CLI-owned (left alone)", []).append(rel)
            continue
        current = f.read_bytes()
        if sha and rel != BASELINE and not flow.same_content(current, sha):
            inv.changed.append(f"{rel} (sha256 {flow.sha256(current)[:12]}..., recorded {sha[:12]}...)")
            continue
        if rel in by_name and (rel in JSON_RECORDS or rel in MIRROR_RECORDS):
            if not is_5x_record(rel, current):  # a structure check, not a byte check (owner, 2026-10-17)
                inv.foreign.append(rel)
                continue
        elif rel in by_name and not any(flow.same_content(current, s) for s in by_name[rel]):
            if rel != MC_MANIFEST:
                inv.foreign.append(rel)  # copied to the backup folder, never deleted
                continue
            if not self_recorded(current):  # the record the whole inventory reads: an edited one stops the run
                raise Abort(f"{MC_MANIFEST} matches no Flow 5.x release and its manifest_self_sha256 does not verify, "
                            "so it cannot tell Flow's files from the project's; restore it from git "
                            f"(git checkout HEAD -- {MC_MANIFEST}) or from the 5.x release it came with; nothing changed")
        if rel in plan_paths:
            inv.replace.append(rel)
            if rel in plan and flow.same_content(current, flow.sha256(plan[rel])):
                inv.identical.append(rel)
        else:
            inv.remove[groups[rel]].append(rel)
    for rel in walk_files(target, "hooks"):
        if "/__pycache__/" in rel or rel.endswith((".pyc", ".pyo")):
            inv.remove["bytecode under hooks/"].append(rel)
    for h in GIT_HOOKS:
        f = hooks_dir(target) / h
        if f.is_file():
            data, src = f.read_bytes(), f"hooks/git/{h}"
            if HOOK_MARKER not in b"\n".join(data.splitlines()[:5]):
                inv.custom_hooks.append(h)
            elif any(flow.same_content(data, s) for s in flow5_shas(src) | ({mc[src]} if src in mc else set())):
                inv.remove["old git hooks"].append(f".git/hooks/{h}")
            else:
                inv.edited_hooks.append(h)  # install would overwrite the edit in place: the preflight stops
    for rel in sorted(plan_paths - set(inv.replace) - set(REWRITTEN)):
        f = target / rel
        why = flow.refusal(target, rel, cli_skills)
        if why:
            inv.never.setdefault("core paths the install refuses", []).append(f"{rel} ({why})")
        elif not f.exists():
            inv.new.append(rel)
        elif rel == BASELINE:  # no 5.x record: install still merges it (the core's rows plus the project's)
            if not flow.same_content(f.read_bytes(), flow.sha256(plan[rel])):
                inv.replace.append(rel)
        elif not (rel in plan and flow.same_content(f.read_bytes(), flow.sha256(plan[rel]))):
            inv.changed.append(f"{rel} (exists and is not Flow's: install would keep it, not the core's)")
    _never_and_keep(inv, vendor, set(groups) | plan_paths)
    for name in flow.OVERLAY:
        overlay = find_overlay(target, name)
        if overlay:
            inv.overlays[name] = overlay
    flow_paths = set(groups) | plan_paths
    skip = flow_paths | set(inv.removals())
    inv.consumers = scan(inv, CONSUMER_DIRS, skip)
    inv.history = scan(inv, HISTORY_DIRS, skip)
    inv.hidden = flow.ignored_paths(target, inv.new + [d for d in DOCS if not (target / d).exists()])
    inv.wiring = wiring(target)
    inv.head = git(target, "rev-parse", "HEAD").stdout.decode().strip()
    inv.branch = git(target, "rev-parse", "--abbrev-ref", "HEAD").stdout.decode().strip()
    inv.task = next_task(target)
    return inv


def _never_and_keep(inv: Inventory, vendor: dict[str, str], flow_paths: set[str]) -> None:
    target = inv.target
    candidates = [p for p in ("fusebase.json", "skills-lock.json", ".mcp.json") + CLI_DOCS if (target / p).is_file()]
    for d in CLI_DIRS:
        candidates += walk_files(target, d)
    flow_skill_dirs = {"/".join(p.split("/")[:3]) for p in flow_paths | set(inv.own_mirrors)
                       if p.split("/")[1:2] == ["skills"]}  # the project's own mirrors are listed under keep
    cli_skill_files: dict[str, int] = {}
    for rel in sorted(set(candidates)):
        parts = rel.split("/")
        if rel in flow_paths:
            continue
        if len(parts) > 3 and parts[1] == "skills" and parts[0] in (".claude", ".agents"):
            if "/".join(parts[:3]) not in flow_skill_dirs:
                cli_skill_files["/".join(parts[:3])] = cli_skill_files.get("/".join(parts[:3]), 0) + 1
        elif flow.matches(rel, CLI_OWNED) or rel in vendor:
            inv.never.setdefault("CLI-owned files", []).append(rel)
    if cli_skill_files:
        inv.never["CLI skills"] = [f"{d}/ ({n} files)" for d, n in sorted(cli_skill_files.items())]
        blocks = [d for d in cli_skill_files
                  if (target / d / "SKILL.md").is_file() and WRAP_BEGIN in (target / d / "SKILL.md").read_bytes()]
        if blocks:
            inv.keep["CUSTOM:SKILL blocks in CLI-owned skills"] = [f"{d}/SKILL.md" for d in sorted(blocks)]
    present = [p for p in vendor if (target / p).is_file()]
    same = [p for p in present if flow.same_content((target / p).read_bytes(), vendor[p])]
    inv.vendor = (len(vendor), len(present), len(same))
    state = walk_files(target, "state")
    if state:
        inv.keep["state/"] = [f"{len(state)} files"]
    docs = [p for p in walk_files(target, "docs") if p not in CLI_DOCS and not p.startswith("docs/flow/")]
    if docs:
        tops: dict[str, int] = {}
        for p in docs:
            key = "/".join(p.split("/")[:2]) + ("/" if p.count("/") > 1 else "")
            tops[key] = tops.get(key, 0) + 1
        inv.keep["project documents, those written from Flow 5.x templates included"] = [
            f"{k} {n}" for k, n in sorted(tops.items())]
    local = sorted(p.relative_to(target).as_posix() for pattern in ("policies/*.local.yml", "hooks/local/*.local.*")
                   for p in target.glob(pattern) if p.relative_to(target).as_posix() not in ORPHANS)
    if local:
        inv.keep["local overrides"] = local
    if inv.own_mirrors:
        inv.keep["the project's own skills and agents, mirrored by Flow 5.x tooling (6.0 does not mirror them)"] = sorted(
            set(inv.own_mirrors) | {s for s in map(mirror_source, inv.own_mirrors) if (target / s).is_file()})
    inv.keep["project rows in policies/module-size-baseline.txt"] = inv.rows or ["none"]


def count_by_top(paths: list[str]) -> str:
    tops: dict[str, int] = {}
    for p in paths:
        key = p.split("/")[0] + ("/" if "/" in p else "")
        tops[key] = tops.get(key, 0) + 1
    return ", ".join(f"{k} {n}" for k, n in sorted(tops.items()))


def report(inv: Inventory, full: bool) -> None:
    def say(line: str = "") -> None:
        print(f"[flow migrate] {line}".rstrip())

    def items(paths: list[str], limit: int = 0) -> None:
        for p in paths if full or not limit else paths[:limit]:
            say(f"    {p}")

    core = (flow.CORE / "VERSION").read_text(encoding="utf-8").strip()
    say(f"Fusebase Flow {inv.version} -> {core} in {inv.target} (providers: {', '.join(sorted(inv.providers))})")
    say(f"pre-migration commit: {inv.head} ({inv.branch})")
    say(f"manifest: {inv.manifest[0]} assets recorded in {MC_MANIFEST}, {inv.manifest[1]} present, "
        f"{len(inv.changed)} changed-by-both")
    removals = inv.removals()
    say(f"remove: {len(removals)} files (each copied to the backup folder first)")
    for g in GROUPS:
        paths = inv.remove[g]
        if g in ("skill mirrors", "agent mirrors"):
            provs = (".claude/skills", ".agents/skills") if g == "skill mirrors" else (".claude/agents", ".codex/agents")
            for prov in provs:
                mine = [p for p in paths if p.startswith(prov + "/")]
                names = sorted({p[len(prov) + 1:].split("/")[0] for p in mine})
                say(f"  {g} under {prov}/: {len(names)} {'skills' if g == 'skill mirrors' else 'agents'}, "
                    f"{len(mine)} files: {', '.join(names)}")
            if full:
                items(paths)
            continue
        detail = count_by_top(paths) if g in ("manifest assets", "bytecode under hooks/") else ", ".join(paths)
        say(f"  {g}: {len(paths)}" + (f" ({detail})" if paths and len(detail) < 400 else ""))
        if full and len(detail) >= 400 or full and g == "manifest assets":
            items(paths)
    if inv.foreign:
        say(f"left in place: {len(inv.foreign)} files named like Flow 5.x files that are not Flow's: no Flow release's "
            "bytes, or not laid out as the 5.x record (copied to the backup folder on --apply, never deleted)")
        items(inv.foreign)
    say(f"replace: {len(inv.replace)} files the core carries ({count_by_top(inv.replace)}); "
        f"{len(inv.identical)} already byte-identical to the core's")
    if full:
        items(inv.replace)
    say(f"new: {len(inv.new)} files the install adds ({count_by_top(inv.new)})")
    if full:
        items(inv.new)
    say(f"rewritten in place: {', '.join(inv.overlays) or 'no overlay'} (the Flow section by heading)"
        + (", VERSION (the core's)" if inv.version_is_flow else "")
        + f"; {flow.ATTRIBUTES} gets the Flow line-ending block; .gitignore is backed up and left as is")
    if not inv.version_is_flow:
        say("VERSION does not read Flow's version: it is the project's and stays as it is")
    absent = [d for d in DOCS if not (inv.target / d).exists()]
    say(f"the four documents, created when absent: {', '.join(absent) or 'all present'}")
    if inv.missing:
        say(f"recorded Flow files already absent: {len(inv.missing)}")
        items(inv.missing, 10)
    say("never touch (CLI-owned):")
    for k, v in inv.never.items():
        say(f"  {k}: {len(v)}")
        items(v, 40)
    say(f"  CLI assets {CLI_VENDOR} lists: {inv.vendor[0]}, {inv.vendor[1]} present, never touched "
        f"({inv.vendor[2]} still match their recorded sha256)")
    say("keep (project-owned):")
    for k, v in inv.keep.items():
        say(f"  {k}: {'; '.join(v) if len(v) <= 12 else str(len(v))}")
    for name, o in inv.overlays.items():
        if o.preserve:
            say(f"  {name}: the FLOW:PRESERVE region, {o.preserve_lf():,} bytes, carried verbatim")
    for name, o in inv.overlays.items():
        span = (f"inside a CUSTOM:SKILL wrapper from byte {o.start_lf:,}; {o.end_lf - o.start_lf:,} bytes replaced"
                if o.wrapped else f"no wrapper; {o.end_lf - o.start_lf:,} bytes replaced")
        say(f"overlay {name}: '{o.heading}' at byte {o.head:,} as committed, {o.size_lf - o.head:,} bytes "
            f"to the end; {span}")
    say(f"consumer references (code and config outside Flow naming a retired Flow path or agent type): {len(inv.consumers)}")
    for rel, found in inv.consumers.items():
        say(f"    {rel}: {', '.join(found)}")
    say(f"history mentions under {', '.join(d + '/' for d in HISTORY_DIRS)} (kept as written; not consumer references): "
        f"{len(inv.history)}")
    for rel, found in inv.history.items():
        say(f"    {rel}: {', '.join(found[:4])}{' ...' if len(found) > 4 else ''}")
    say(f"hidden by .gitignore (installed paths git would not add): {len(inv.hidden)}")
    for p in inv.hidden:
        say(f"    {p}")
    say(f"hook wiring, left as is: {inv.wiring}")
    say("backup folder on --apply: .flow-migrate-<UTC timestamp>/ (remove + replace + left in place + AGENTS.md, "
        "CLAUDE.md, VERSION, .gitignore and the docs/flow documents that exist)")
    say(f"commit on --apply --go-ahead: chore(flow): {inv.task} migrate Fusebase Flow {inv.version} to {core}")


def run(target: Path, providers: set[str], full: bool, apply: bool = False, go_ahead: bool = False,
        task: str | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # headings carry an em dash
    if apply and not go_ahead:
        print("[flow migrate] REFUSED: --apply needs --go-ahead, passed only after the operator's go-ahead in chat; "
              "nothing written")
        return 2
    target = target.resolve()
    if flow.git_toplevel(target) != target:
        print(f"[flow migrate] REFUSED: {target} is not the top level of a git work tree")
        return 2
    if not (target / MC_MANIFEST).is_file():
        if git(target, "cat-file", "-e", f"HEAD:{MC_MANIFEST}").returncode == 0:
            import migrate_apply  # an apply that did not end in its commit: finish it or roll it back
            return migrate_apply.resume(target)
        if (target / flow.MANIFEST).is_file():
            print(f"[flow migrate] nothing to migrate: {target} carries Fusebase Flow "
                  f"{json.loads((target / flow.MANIFEST).read_text(encoding='utf-8')).get('flow_version')} "
                  f"({flow.MANIFEST}); re-run install to upgrade within 6.0")
            return 0
        print(f"[flow migrate] REFUSED: no Flow 5.x install in {target} ({MC_MANIFEST} is absent)")
        return 2
    try:
        inv = inventory(target, providers)
    except Abort as exc:
        print(f"[flow migrate] ABORT: {exc}")
        return 3
    if inv.changed:
        print("[flow migrate] ABORT: changed-by-both: a project edit inside a Flow-owned file; nothing changed, nothing replaced")
        for line in inv.changed:
            print(f"[flow migrate]   {line}")
        return 3
    inv.task = task or inv.task
    import migrate_preflight
    print("[flow migrate] dry run: nothing changed" if not apply
          else "[flow migrate] apply: the operator's go-ahead was given in chat (--go-ahead)")
    report(inv, full)
    sys.stdout.flush()
    stops = migrate_preflight.run(inv, apply)
    if stops:
        wrote = [p for c in stops for p in c.wrote]
        print(f"[flow migrate] {'STOPPED before any change' if apply else '--apply would stop before any change'}: "
              f"{len(stops)} preflight check(s) failed ({', '.join(c.name for c in stops)}); "
              + (f"the migration wrote nothing, but the project's command changed {len(wrote)} path(s), named above"
                 if wrote else "nothing written"))
        return 2
    if not apply:
        return 0
    import migrate_apply
    return migrate_apply.apply(inv)
