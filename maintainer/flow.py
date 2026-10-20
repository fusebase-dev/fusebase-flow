#!/usr/bin/env python3
"""Fusebase Flow 6.0 installer: `python maintainer/flow.py install --target DIR [--providers claude,codex]`; also
`flow.py health --target DIR` (read-only) and `flow.py migrate` (a 5.x project).

Copies the core into a project, generates provider mirrors, merges the overlay block into
AGENTS.md / CLAUDE.md, writes audit/flow-install.json and installs the three git hooks.
Re-running it is the upgrade within 6.0.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

CORE = Path(__file__).resolve().parent.parent
MANIFEST = "audit/flow-install.json"
PRIOR_5X = ("audit/managed-content-manifest.json", "audit/hook-layer-manifest.json")
CORE_PATTERNS = (
    "FLOW_RULES.md", "VERSION", "hooks/requirements.txt", "hooks/git/*", "hooks/shared/*.py",
    "hooks/handlers/*.py", "hooks/local/*.sh", "hooks/local/*.py", "hooks/local/lib/*.sh", "hooks/local/lib/*.py",
    "policies/*.yml", "policies/module-size-baseline.txt",
    "agents/*/AGENT.md", "flow-skills/*/SKILL.md", "templates/*.md", "workflows/*.md",
)
EXECUTABLE = ("hooks/git/*", "*.sh")
CODEX_AGENTS = ("planner", "builder")
# CLI-owned (handoff WP 12): the installer never writes these, whatever its own list says.
NEVER_TOUCH = (
    "fusebase.json", "skills-lock.json", ".mcp.json", ".claude/settings.json",
    ".claude/settings.local.json", ".claude/hooks/*", ".claude/agents/app-*",
    ".codex/agents/app-*", ".codex/config.toml", ".codex/hooks.json", ".codex-plugin/*",
)
BASELINE = "policies/module-size-baseline.txt"  # Flow's: the core's rows only
# The project's rows (6.0.0-m6 item 9, M6-15), the committed sibling hooks/shared/module_size.py also reads: install moves
# them there out of a baseline that held both, and never rewrites the file after.
PROJECT_BASELINE = "policies/module-size-baseline.project.txt"
PROJECT_HEADER = ("# FR-25 module-size baseline — the project's over-ceiling files frozen at current size (Flow's own "
                  f"rows: {BASELINE}).\n# Regenerate (agent runs on the operator's go-ahead): bash "
                  "hooks/local/check-module-size.sh --write-baseline\n# Re-key ONE file (no global amnesty): ... "
                  "--write-baseline <path>\n").encode("utf-8")  # module_size.py's --write-baseline header, byte for byte
FLOW5_ROWS = ("hooks/local/upgrade.sh",)  # the 5.x core's own row: Flow's, never carried as the project's
OVERLAY = {"AGENTS.md": "maintainer/overlay/AGENTS.block.md", "CLAUDE.md": "maintainer/overlay/CLAUDE.block.md"}
FLOW_BEGIN, FLOW_END = "<!-- FLOW:BEGIN", "<!-- FLOW:END -->"
PRESERVE_BEGIN, PRESERVE_END = "<!-- FLOW:PRESERVE:BEGIN", "<!-- FLOW:PRESERVE:END -->"
WRAP_BEGIN, WRAP_END = "<!-- CUSTOM:SKILL:BEGIN -->", "<!-- CUSTOM:SKILL:END -->"
# The project's .gitattributes gets one Flow block pinning what Flow writes to LF; re-install replaces the block.
ATTRIBUTES = ".gitattributes"
ATTR_BEGIN, ATTR_END = "# FLOW:BEGIN line endings (flow.py install writes this block; re-install replaces it)", \
    "# FLOW:END line endings"
ATTR_FIX = ("restore the missing marker line, or delete the block's lines by hand, then re-run "
            "(Flow replaces only a whole marked block and never deletes the project's lines)")
# The project's .gitignore gets one Flow block too (O-4): runtime state and bytecode the hooks write.
IGNORE = ".gitignore"
IGNORE_LINES = ("state/approvals/*", "!state/approvals/.gitkeep", "state/audit/*", "state/audit.log.jsonl",
                "hooks/**/__pycache__/", "state/reader/", "state/status.line", "state/returns/")
# {file: (BEGIN line, END line, what the block is)}; a BEGIN marker line starts with the part before " (".
BLOCKS = {ATTRIBUTES: (ATTR_BEGIN, ATTR_END, "line-ending"),
          IGNORE: ("# FLOW:BEGIN ignore (flow.py install writes this block; re-install replaces it)",
                   "# FLOW:END ignore", "ignore")}
DOCS_DIR = "docs/flow"
DOCUMENTS = tuple(f"{DOCS_DIR}/{name}.md" for name in ("backlog", "phases", "evidence", "ledger"))
COMMIT_MSG_PY = "hooks/local/lib/commit_msg.py"  # 6.0's commit-msg needs it in the work tree


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def same_content(current: bytes, recorded_sha: str) -> bool:
    # TRIPWIRE: an autocrlf checkout turns an unedited LF file into CRLF; both forms count as unedited.
    return recorded_sha in (sha256(current), sha256(current.replace(b"\r\n", b"\n")))


def matches(path: str, patterns: tuple[str, ...]) -> bool:
    return any(fnmatch.fnmatchcase(path, p) for p in patterns)


def core_files() -> list[str]:
    found: set[str] = set()
    for pattern in CORE_PATTERNS:
        for p in CORE.glob(pattern):
            rel = p.relative_to(CORE).as_posix()
            if p.is_file() and "__pycache__" not in rel and fnmatch.fnmatchcase(rel, pattern):
                found.add(rel)
    return sorted(found)


def split_frontmatter(text: str) -> tuple[dict[str, str], str]:
    if not text.startswith("---\n"):
        return {}, text
    head, _, body = text[4:].partition("\n---\n")
    meta = {}
    for line in head.splitlines():
        key, sep, value = line.partition(":")
        if sep:
            meta[key.strip()] = value.strip()
    return meta, body.lstrip("\n")


def toml_str(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def codex_agent_toml(agent_md: str) -> str:
    meta, body = split_frontmatter(agent_md)
    body = body.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    return (
        f"# Generated by maintainer/flow.py from agents/{meta['name']}/AGENT.md; re-install regenerates it.\n"
        f"name = {toml_str(meta['name'])}\n"
        f"description = {toml_str(meta.get('description', ''))}\n"
        f'sandbox_mode = "workspace-write"\n'
        f'developer_instructions = """\n{body}"""\n'
    )


def planned_files(providers: set[str]) -> dict[str, bytes]:
    plan: dict[str, bytes] = {}
    for rel in core_files():
        plan[rel] = (CORE / rel).read_bytes()
    skills = sorted(p.parent.name for p in CORE.glob("flow-skills/*/SKILL.md"))
    agents = sorted(p.parent.name for p in CORE.glob("agents/*/AGENT.md"))
    for s in skills:
        data = (CORE / f"flow-skills/{s}/SKILL.md").read_bytes()
        if "claude" in providers:
            plan[f".claude/skills/{s}/SKILL.md"] = data
        if "codex" in providers:
            plan[f".agents/skills/{s}/SKILL.md"] = data
    for a in agents:
        data = (CORE / f"agents/{a}/AGENT.md").read_bytes()
        if "claude" in providers:
            plan[f".claude/agents/{a}.md"] = data
        if "codex" in providers and a in CODEX_AGENTS:
            plan[f".codex/agents/{a}.toml"] = codex_agent_toml(data.decode("utf-8")).encode("utf-8")
    return plan


def baseline_rows(data: bytes) -> dict[str, str]:
    """{path: row} for each `N path` row, parsed as hooks/shared/module_size.py reads them (a later row wins)."""
    rows: dict[str, str] = {}
    for line in data.decode("utf-8", "replace").splitlines():
        line = line.strip()
        parts = line.split(" ", 1)
        if line and not line.startswith("#") and len(parts) == 2 and parts[0].isdigit():
            rows[parts[1]] = line
    return rows


def project_rows(current: bytes, core: bytes, flow_paths: set[str]) -> list[str]:
    """The project's rows of a module-size baseline: rows naming a path neither Flow nor the core's rows own."""
    core_paths = set(baseline_rows(core))
    return [row for path, row in baseline_rows(current).items() if path not in flow_paths and path not in core_paths]


def with_rows(core: bytes, rows: list[str]) -> bytes:
    """The core's baseline with the project's rows appended, LF."""
    if not rows:
        return core
    return core + (b"" if core.endswith(b"\n") else b"\n") + "".join(f"{r}\n" for r in rows).encode("utf-8")


def old_files(target: Path) -> list[dict]:
    """The `files` entries of the install manifest already in the target, [] when there is none."""
    try:
        files = json.loads((target / MANIFEST).read_text(encoding="utf-8")).get("files")
    except (OSError, ValueError, AttributeError):
        return []
    return [e for e in files if isinstance(e, dict)] if isinstance(files, list) else []


def project_baseline(target: Path, rows: list[str]) -> bytes | None:
    """The project's baseline file with `rows` added to the rows it has (its own row for a path stays), or None when it
    already holds them all."""
    path = target / PROJECT_BASELINE
    current = path.read_bytes() if path.is_file() and not path.is_symlink() else b""
    have = baseline_rows(current)
    new = [r for r in rows if r.split(" ", 1)[1] not in have]
    return with_rows(current or PROJECT_HEADER, new) if new else None


def load_prior(target: Path) -> dict[str, set[str]]:
    """{path: recorded sha256s} from the 6.0 install manifest and the 5.x Flow manifests."""
    prior: dict[str, set[str]] = {}
    for rel, key in ((MANIFEST, "files"),) + tuple((m, "assets") for m in PRIOR_5X):
        try:
            doc = json.loads((target / rel).read_text(encoding="utf-8"))
            for entry in doc.get(key, []):
                prior.setdefault(entry["path"], set()).add(entry["sha256"])
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            continue
    return prior


def cli_skill_names(target: Path) -> set[str]:
    names: set[str] = set()

    def walk(node: object) -> None:
        if isinstance(node, dict):
            for k, v in node.items():
                names.add(str(k))
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
        elif isinstance(node, str):
            names.add(node)

    try:
        walk(json.loads((target / "skills-lock.json").read_text(encoding="utf-8")))
    except (OSError, ValueError):
        pass
    return names


def refusal(target: Path, rel: str, cli_skills: set[str]) -> str | None:
    if matches(rel, NEVER_TOUCH):
        return "CLI-owned path"
    parts = rel.split("/")
    if parts[0] in (".claude", ".agents") and len(parts) > 2 and parts[1] == "skills" and parts[2] in cli_skills:
        return "skill name listed in skills-lock.json (CLI-owned)"
    dest = target / rel
    for parent in [dest, *dest.parents]:
        if parent == target:
            break
        if parent.is_symlink():
            return "symlink on the path"
    if dest.exists() and not dest.is_file():
        return "exists and is not a regular file"
    return None


def write_bytes(dest: Path, data: bytes, executable: bool) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".flow-tmp")
    tmp.write_bytes(data)
    os.replace(tmp, dest)
    if executable and os.name != "nt":
        dest.chmod(0o755)


def merge_block(existing: str | None, block: str) -> str:
    nl = "\n"
    if existing is not None and existing[:existing.find("\n") + 1].endswith("\r\n"):
        # TRIPWIRE: an autocrlf checkout; an LF block inside a CRLF file would mix line endings.
        nl, block = "\r\n", block.replace("\r\n", "\n").replace("\n", "\r\n")
    inner_start = block.index(FLOW_BEGIN)
    inner = block[inner_start: block.index(FLOW_END) + len(FLOW_END)]
    if existing is None:
        return block
    if FLOW_BEGIN not in existing:
        sep = "" if existing.endswith("\n") else nl
        return existing + sep + nl + block
    start = existing.index(FLOW_BEGIN)
    end = existing.index(FLOW_END, start) + len(FLOW_END)
    old = existing[start:end]
    if PRESERVE_BEGIN in old and PRESERVE_END in old:
        # The operator's region, its BEGIN marker line included, stays byte for byte.
        kept = old[old.index(PRESERVE_BEGIN): old.index(PRESERVE_END)]
        inner = inner[:inner.index(PRESERVE_BEGIN)] + kept + inner[inner.index(PRESERVE_END):]
    merged = existing[:start] + inner + existing[end:]
    assert merged.startswith(existing[:start]) and merged.endswith(existing[end:])
    return merged


def attributes_block(paths: list[str]) -> str:
    """`text eol=lf` for each file Flow writes, by its exact path, and for the Markdown documents in docs/flow/ (the
    lifecycle writes docs/flow/evidence/P<n>.md too); each line anchored with a leading slash."""
    # TRIPWIRE: never a folder, text=auto or a type outside docs/flow/: the block comes last, so any of those overrides
    # the project's own `*.png binary` lines and rewrites the CRLF bytes inside its binaries (fix-pass review R1).
    pins = sorted({*paths, MANIFEST, f"{DOCS_DIR}/**/*.md"})
    return "\n".join([ATTR_BEGIN, "# core.autocrlf=true would otherwise check these out as CRLF: the hooks break and "
                      "the sha256 records stop matching.", *(f"/{p} text eol=lf" for p in pins), ATTR_END]) + "\n"


def ignore_block() -> str:
    return "\n".join([BLOCKS[IGNORE][0], "# Runtime state and bytecode the Flow hooks write: never committed.",
                      "# Committed records, so not here: state/flags/ state/gate/ state/done/ state/deploys/ state/runs/",
                      *IGNORE_LINES, BLOCKS[IGNORE][1]]) + "\n"


def block_markers(text: str, name: str = ATTRIBUTES) -> tuple[int, int] | str:
    """The Flow block's BEGIN and END line indexes in file `name` ((-1, -1) when it has none), or what is wrong with
    its markers."""
    begin, end = BLOCKS[name][0].split(" (")[0], BLOCKS[name][1]
    lines = text.split("\n")
    begins = [i for i, line in enumerate(lines) if line.startswith(begin)]
    ends = [i for i, line in enumerate(lines) if line.startswith(end)]
    if not begins and not ends:
        return -1, -1
    if len(begins) == 1 and len(ends) == 1 and begins[0] < ends[0]:
        return begins[0], ends[0]
    where = "; ".join(f"line {i + 1}: '{begin if i in begins else end}'" for i in sorted(begins + ends))
    return f"{name} {where}: the Flow block needs one '{begin}' line, then one '{end}' line"


def merge_marked(existing: str | None, block: str, name: str = ATTRIBUTES) -> str:
    """The block replaces its earlier copy, or is appended; the file keeps its own line endings (merged, as AGENTS.md).
    The caller has checked the markers (block_markers)."""
    if existing is None:
        return block
    nl = "\r\n" if existing[:existing.find("\n") + 1].endswith("\r\n") else "\n"
    block = block.replace("\n", nl)
    found = block_markers(existing, name)
    if isinstance(found, str):
        raise ValueError(found)
    start, stop = found
    if start >= 0:
        lines = existing.split("\n")  # a CRLF line keeps its \r
        return "".join(f"{line}\n" for line in lines[:start]) + block + "\n".join(lines[stop + 1:])
    sep = "" if not existing or existing.endswith("\n") else nl
    return existing + sep + (nl if existing else "") + block


def install_hooks(target: Path) -> tuple[int, str]:
    bash = shutil.which("bash")
    if not bash:
        return 1, "bash not found: the three git hooks were not installed"
    try:
        proc = subprocess.run([bash, "hooks/local/install-git-hooks.sh"], cwd=target,
                              capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return 124, "install-git-hooks.sh did not finish within 600 s"
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def ignored_paths(target: Path, paths: list[str]) -> list[str]:
    try:
        # TRIPWIRE: bytes, not text=True: Windows text mode writes CRLF and git reads "path\r".
        proc = subprocess.run(["git", "check-ignore", "--stdin"], cwd=target,
                              input=("\n".join(paths) + "\n").encode("utf-8"), capture_output=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return ["(git check-ignore did not run)"]
    return [line.strip() for line in proc.stdout.decode("utf-8", "replace").splitlines() if line.strip()]


CONSOLE = ("no pythonw.exe was found beside this Python, through the py launcher or on PATH, so the task runs python.exe "
           "and a console window opens every 5 minutes. To avoid it, install Python from python.org (it ships "
           "pythonw.exe) or put pythonw.exe on PATH, then re-run install with --register-reader")


def quiet_python(executable: str = "") -> tuple[str, str]:
    """The interpreter the Windows reader task runs, and a warning when it opens a console (brief m5 item 7): pythonw.exe
    beside this Python, else beside the py launcher's Python 3, else pythonw on PATH, else python.exe."""
    executable = executable or sys.executable
    if (beside := Path(executable).with_name("pythonw.exe")).is_file():
        return str(beside), ""
    if launcher := shutil.which("py"):  # TRIPWIRE: the resolved path; a bare name finds System32 first on Windows
        try:
            out = subprocess.run([launcher, "-3", "-c", "import sys; print(sys.executable)"], capture_output=True,
                                 text=True, timeout=120).stdout.strip().splitlines()
        except (OSError, subprocess.TimeoutExpired):
            out = []
        if out and (found := Path(out[-1].strip()).with_name("pythonw.exe")).is_file():
            return str(found), ""
    return (on_path, "") if (on_path := shutil.which("pythonw")) else (executable, CONSOLE)


def reader_line(target: Path, python: str = "") -> tuple[str, list[str]]:
    """The scheduler line that runs the heartbeat reader every 5 minutes (design section 6), printed and as argv; on
    Windows with `python` (quiet_python() when not given)."""
    script = target / "hooks/local/reader.py"
    if os.name == "nt":
        name = f"FuseBase Flow reader {target.name}-{sha256(str(target).encode('utf-8'))[:8]}"
        run = f'"{python or quiet_python()[0]}" "{script}" --once'  # no console window every 5 minutes
        argv = ["schtasks", "/Create", "/F", "/SC", "MINUTE", "/MO", "5", "/TN", name, "/TR", run]
        return subprocess.list2cmdline(argv), argv
    line = f"*/5 * * * * cd {sh_quote(str(target))} && {sh_quote(sys.executable)} {READER_RUN} >/dev/null 2>&1"
    return line, ["crontab", line]


def sh_quote(text: str) -> str:
    return "'" + text.replace("'", "'\\''") + "'"


READER_RUN = "hooks/local/reader.py --once"
TR_MAX = 261  # schtasks /Create refuses a longer /TR value


def by_hand(argv: list[str]) -> tuple[str, str]:
    """Where and what the user adds by hand when the registration is refused or fails."""
    if argv[0] == "crontab":
        return "crontab -e", argv[1]
    if len(argv[-1]) <= TR_MAX:
        return "a terminal", subprocess.list2cmdline(argv)
    exe, _, rest = argv[-1][1:].partition('" ')
    name, exe, rest = (x.replace("'", "''") for x in (argv[argv.index("/TN") + 1], exe, rest))
    return "PowerShell", (f"Register-ScheduledTask -TaskName '{name}' -Action (New-ScheduledTaskAction -Execute '{exe}' "
                          f"-Argument '{rest}') -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date) "
                          "-RepetitionInterval (New-TimeSpan -Minutes 5)) -Force")


def register_reader(argv: list[str], target: Path) -> tuple[int, str]:
    """Registers the line with schtasks, or adds it to the user's crontab once. Whenever it cannot be sure, it writes
    nothing and returns non-zero; the caller prints by_hand(argv)."""
    exe = shutil.which(argv[0])  # TRIPWIRE: a bare name skips PATH on Windows (System32 is searched first)
    if not exe:
        return 1, f"{argv[0]} not found on PATH"
    try:
        if argv[0] != "crontab":
            if len(argv[-1]) > TR_MAX:
                return 1, f"the /TR value is {len(argv[-1])} characters; schtasks refuses more than {TR_MAX}"
            proc = subprocess.run([exe, *argv[1:]], capture_output=True, text=True, timeout=120)
            return proc.returncode, (proc.stdout + proc.stderr).strip()
        read = subprocess.run([exe, "-l"], capture_output=True, timeout=60)
        err = read.stderr.decode("utf-8", "replace").strip()
        if read.returncode != 0 and "no crontab" not in err.lower():
            return 1, f"crontab -l exited {read.returncode} ({err or 'no message'}): the crontab is left untouched"
        # TRIPWIRE: bytes with surrogateescape, so a crontab that is not UTF-8 goes back byte for byte.
        have = read.stdout.decode("utf-8", "surrogateescape") if read.returncode == 0 else ""
        mine = f"cd {sh_quote(str(target))} &&"
        if any(mine in x and READER_RUN in x for x in have.splitlines() if not x.lstrip().startswith("#")):
            return 0, "already in the crontab for this project"
        text = have + ("" if not have or have.endswith("\n") else "\n") + argv[1] + "\n"
        proc = subprocess.run([exe, "-"], input=text.encode("utf-8", "surrogateescape"), capture_output=True,
                              timeout=60)
        return proc.returncode, (proc.stdout + proc.stderr).decode("utf-8", "replace").strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 1, str(exc)


def git_toplevel(target: Path) -> Path | None:
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=target,
                             capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return Path(out.stdout.strip()).resolve() if out.returncode == 0 and out.stdout.strip() else None


def git_text(target: Path, *args: str, data: str = "") -> str:
    """git's stdout, "" when it fails."""
    try:
        out = subprocess.run(["git", *args], cwd=target, input=data.encode("utf-8"), capture_output=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return out.stdout.decode("utf-8", "replace") if out.returncode == 0 else ""


def main_worktree(target: Path) -> str:
    """The main worktree's path when `target` is a linked worktree (`git worktree add`), else "". git keeps one hooks
    folder for all of a repository's worktrees, so install and migrate run in the main one only (r3-09)."""
    dirs = git_text(target, "rev-parse", "--git-dir", "--git-common-dir").splitlines()
    if len(dirs) != 2 or (target / dirs[0]).resolve() == (target / dirs[1]).resolve():
        return ""
    first = git_text(target, "worktree", "list", "--porcelain").split("\n", 1)[0]
    return first[len("worktree "):] if first.startswith("worktree ") else str((target / dirs[1]).resolve().parent)


def open_checkouts(target: Path) -> list[str]:
    """The other local branches and linked worktrees whose tip has no Flow 6.0 commit-msg helper, one line each: the
    6.0 git hooks, which they share, refuse their commits until they merge the branch installed here (r1-09)."""
    here = git_text(target, "rev-parse", "--abbrev-ref", "HEAD").strip()
    heads = git_text(target, "for-each-ref", "--format=%(refname:short)", "refs/heads").splitlines()
    lines, revs = [f"branch {b}" for b in heads if b and b != here], [b for b in heads if b and b != here]
    for block in git_text(target, "worktree", "list", "--porcelain").split("\n\n")[1:]:  # the first is the main one
        tree = dict(line.partition(" ")[::2] for line in block.splitlines())
        if tree.get("HEAD") and Path(tree.get("worktree", "")).resolve() != target:
            lines.append(f"worktree {tree['worktree']} ({tree.get('branch', 'detached').removeprefix('refs/heads/')})")
            revs.append(tree["HEAD"])
    found = git_text(target, "cat-file", "--batch-check", data="".join(f"{r}:{COMMIT_MSG_PY}\n" for r in revs))
    found_lines = found.splitlines()
    if len(found_lines) != len(lines):
        return lines
    return [line for line, out in zip(lines, found_lines) if out.endswith(" missing")]


def open_warning(lines: list[str], branch: str, commit: str) -> list[str]:
    """The warning install and migrate print for open_checkouts(), at most 20 of them named."""
    named = lines[:20] + ([f"and {len(lines) - 20} more"] if len(lines) > 20 else [])
    return [f"WARNING: {len(lines)} other branches and worktrees have no Flow 6.0 files at their tip ({COMMIT_MSG_PY}); "
            f"the git hooks are one set for the whole repository, so their commits are refused: each must merge "
            f"{branch} once {commit} lands, before its next commit:", *(f"  {line}" for line in named)] if lines else []


def install(target: Path, providers: set[str], prior_5x: dict[str, set[str]] | None = None,
            register: bool = False, wire_hooks: bool = False) -> int:
    """prior_5x: Flow records read before a migration removed the 5.x manifests (migrate.py). register: schedule the
    heartbeat reader (--register-reader); a plain install registers nothing and keeps an earlier record. wire_hooks:
    merge the two tool handlers into each provider's hook settings (--wire-hooks); a plain install writes neither."""
    target = target.resolve()
    if git_toplevel(target) != target:
        print(f"[flow] REFUSED: {target} is not the top level of a git work tree (git init it first)")
        return 2
    main = main_worktree(target)
    if main:
        print(f"[flow] REFUSED: {target} is a linked worktree. The git hooks are one set for all the repository's "
              f"worktrees, so install runs in the main worktree: {main}; nothing written")
        return 2
    for name in BLOCKS:
        path = target / name
        damaged = block_markers(path.read_bytes().decode("utf-8", "surrogateescape"), name) if path.is_file() else ""
        if isinstance(damaged, str) and damaged:
            print(f"[flow] REFUSED: {damaged}; {ATTR_FIX}; nothing written")
            return 2
    version = (CORE / "VERSION").read_text(encoding="utf-8").strip()
    prior = load_prior(target)
    for rel, shas in (prior_5x or {}).items():
        prior.setdefault(rel, set()).update(shas)
    cli_skills = cli_skill_names(target)
    report: dict[str, list[str]] = {k: [] for k in ("added", "replaced", "unchanged", "kept", "refused", "merged")}
    recorded: list[dict[str, str]] = []
    plan = planned_files(providers)
    rows: list[str] = []
    if BASELINE in plan and (target / BASELINE).is_file() and not (target / BASELINE).is_symlink():
        # The rows naming Flow paths are Flow's and come from the core; the project's rows move to its own file.
        rows = project_rows((target / BASELINE).read_bytes(), plan[BASELINE], set(plan) | set(prior) | set(FLOW5_ROWS))
    for rel, data in plan.items():
        why = refusal(target, rel, cli_skills)
        if why:
            report["refused"].append(f"{rel} ({why})")
            continue
        dest = target / rel
        if dest.exists():
            current = dest.read_bytes()
            if same_content(current, sha256(data)):
                report["unchanged"].append(rel)
                recorded.append({"path": rel, "sha256": sha256(data)})
                continue
            if rel != BASELINE and not any(same_content(current, s) for s in prior.get(rel, ())):
                report["kept"].append(f"{rel} (differs; not a Flow-owned unedited file)")
                continue
            report["replaced"].append(f"{rel} (the core's rows; {len(rows)} project rows moved to {PROJECT_BASELINE})"
                                      if rel == BASELINE else rel)
        else:
            report["added"].append(rel)
        write_bytes(dest, data, matches(rel, EXECUTABLE))
        recorded.append({"path": rel, "sha256": sha256(data)})
    if rows and (data := project_baseline(target, rows)) is not None and not refusal(target, PROJECT_BASELINE, cli_skills):
        report["added" if not (target / PROJECT_BASELINE).exists() else "replaced"].append(
            f"{PROJECT_BASELINE} (the project's own: {len(rows)} rows from {BASELINE})")
        write_bytes(target / PROJECT_BASELINE, data, False)
        # recorded for the flow: commit that carries it (flow_owned.py); marked the project's, so health never checks it
        recorded.append({"path": PROJECT_BASELINE, "sha256": sha256(data), "project": True})
    else:  # the project's file, as an earlier install recorded it: a re-run leaves the entry, and the file, as they are
        recorded += [e for e in old_files(target) if e.get("path") == PROJECT_BASELINE and e.get("project")][:1]
    for name, block_rel in OVERLAY.items():
        if ("claude" not in providers) and name == "CLAUDE.md":
            continue
        dest = target / name
        block = (CORE / block_rel).read_bytes().decode("utf-8")
        before = dest.read_bytes().decode("utf-8") if dest.is_file() else None
        after = merge_block(before, block)
        if after != before:
            write_bytes(dest, after.encode("utf-8"), False)
        report["merged"].append(f"{name} ({'created' if before is None else 'block updated' if after != before else 'block current'})")
    for name, block in ((ATTRIBUTES, attributes_block([e["path"] for e in recorded])), (IGNORE, ignore_block())):
        path = target / name
        if path.is_symlink() or (path.exists() and not path.is_file()):
            report["refused"].append(f"{name} (a symlink or not a regular file: the {BLOCKS[name][2]} block is not written)")
            continue
        before = path.read_bytes().decode("utf-8", "surrogateescape") if path.is_file() else None
        after = merge_marked(before, block, name)
        if after != before:
            write_bytes(path, after.encode("utf-8", "surrogateescape"), False)
        report["merged"].append(f"{name} ({'created' if before is None else 'block updated' if after != before else 'block current'})")
    try:
        reader = json.loads((target / MANIFEST).read_text(encoding="utf-8")).get("reader")
    except (OSError, ValueError, AttributeError):
        reader = None
    python, console = quiet_python() if register and os.name == "nt" else (sys.executable, "")
    reader_cmd, argv = reader_line(target, python)
    reader_rc, reader_out = register_reader(argv, target) if register else (0, "")
    if register and reader_rc == 0:
        reader = {"line": reader_cmd, "registered": True}
    manifest = {
        "schema_version": 1, "flow_version": version, "providers": sorted(providers),
        "files": sorted(recorded, key=lambda e: e["path"]),
        "merged": sorted(OVERLAY if "claude" in providers else ["AGENTS.md"]) + list(BLOCKS),
    }
    write_bytes(target / MANIFEST, (json.dumps({**manifest, **({"reader": reader} if reader else {})}, indent=2)
                                    + "\n").encode("utf-8"), False)
    report["ignored"] = ignored_paths(target, [e["path"] for e in recorded])
    rc, hooks_out = install_hooks(target)
    print(f"[flow] Fusebase Flow {version} -> {target} (providers: {', '.join(sorted(providers)) or 'none'})")
    for key in ("added", "replaced", "unchanged", "kept", "refused", "merged", "ignored"):
        note = " (hidden by the project's .gitignore: commit them with a !negation line)" if key == "ignored" and report[key] else ""
        print(f"[flow] {key}: {len(report[key])}{note}")
        for item in report[key]:
            print(f"[flow]   {item}")
    print(f"[flow] manifest: {MANIFEST} ({len(recorded)} files)")
    print("[flow] git hooks:")
    for line in hooks_out.splitlines():
        print(f"[flow]   {line}")
    if prior_5x is None:  # migrate prints its own
        here = git_text(target, "rev-parse", "--abbrev-ref", "HEAD").strip()
        for line in open_warning(open_checkouts(target), here, "the commit of this install"):
            print(f"[flow] {line}")
    if not wire_hooks:
        print("[flow] provider hook wiring: not written (opt-in: re-run install with --wire-hooks)")
    else:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import wire
    for name in sorted(providers) if wire_hooks else ():
        wired_rc, wired_out = wire.wire(target, name)
        # Its own status, as the reader registration's: a refused merge leaves the install's exit code alone.
        print(f"[flow] provider hook wiring: {'' if wired_rc == 0 else 'NOT wired: '}{wired_out[0]}")
        for line in "\n".join(wired_out[1:]).splitlines():
            print(f"[flow]   {line}")
    if not register:
        print("[flow] heartbeat reader: " + ("registered earlier: " + reader["line"] if reader else
                                             "not scheduled (re-run install with --register-reader to schedule it)"))
    elif reader_rc == 0:
        print(f"[flow] heartbeat reader: registered: {reader_cmd}")
    else:
        # Its own status: a refused or failed registration leaves the install's exit code alone (O-16).
        print(f"[flow] heartbeat reader: NOT registered (status {reader_rc}); the install above is complete")
    for out_line in reader_out.splitlines():
        print(f"[flow]   {out_line}")
    if console:
        print(f"[flow]   WARNING: {console}.")
    if register and reader_rc != 0:
        where, line = by_hand(argv)
        print(f"[flow]   add this line by hand ({where}): {line}")
    return 0 if rc == 0 else 1


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="flow.py")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("install", help="install or upgrade the core in a project")
    p.add_argument("--target", required=True, type=Path)
    p.add_argument("--providers", default="claude,codex")
    p.add_argument("--wire-hooks", action="store_true",
                   help="merge the two tool handlers into .claude/settings.json and/or .codex/hooks.json")
    p.add_argument("--register-reader", action="store_true",
                   help="schedule hooks/local/reader.py --once every 5 minutes (schtasks or crontab)")
    h = sub.add_parser("health", help="what install knows about a project, read-only; exit 0 healthy, 1 not")
    h.add_argument("--target", required=True, type=Path)
    m = sub.add_parser("migrate", help="move a project from its Flow 5.x install onto this core (a dry run by default)")
    m.add_argument("--target", required=True, type=Path)
    m.add_argument("--providers", default="claude,codex")
    m.add_argument("--full", action="store_true", help="list every path, not only the groups")
    m.add_argument("--apply", action="store_true", help="perform the migration (needs --go-ahead)")
    m.add_argument("--go-ahead", action="store_true", help="the operator gave the go-ahead in chat")
    args = parser.parse_args(argv)
    if args.cmd == "health":
        sys.modules.setdefault("flow", sys.modules[__name__])  # health.py imports this module, not a second copy
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import health
        rc, lines = health.report(args.target)
        print("\n".join(lines))
        return rc
    providers = {x.strip() for x in args.providers.split(",") if x.strip()}
    unknown = providers - {"claude", "codex"}
    if unknown:
        parser.error(f"unknown provider(s): {', '.join(sorted(unknown))} (supported: claude, codex)")
    if args.cmd == "migrate":
        sys.modules.setdefault("flow", sys.modules[__name__])  # migrate.py imports this module, not a second copy
        sys.path.insert(0, str(Path(__file__).resolve().parent))  # PYTHONSAFEPATH=1 leaves the script's folder off
        import migrate
        return migrate.run(args.target, providers, args.full, args.apply, args.go_ahead)
    return install(args.target, providers, register=args.register_reader, wire_hooks=args.wire_hooks)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
