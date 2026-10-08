import posixpath
import re
import subprocess
from collections import namedtuple
from pathlib import Path

DEFAULT_LAST = 10
READ_REPEAT_MIN = 3
BASH_REPEAT_MIN = 3
FR10_TRIPLE = 3                # exactly-3 runs: labeled, dismissed only when probe-shaped
LARGE_WRITE_CHARS = 10_000
SNIPPET_MAX = 100
TOP_SINKS = 10
LARGE_TOOL_RESULT_CHARS = 20_000
REPEAT_OUTPUT_MIN = 2          # an identical large body seen >= this many times = candidate
LINE_TYPES = {"assistant", "user"}
WRITE_TOOLS = {"Edit", "Write", "NotebookEdit"}

# TRIPWIRE: `key` is the FULL read key (path, offset, limit) and `seq` the event index.
# Both are the association A8/AC15 requires — `target` is a <=100-char display snippet
# and must never be used as a classification key.
ToolResult = namedtuple("ToolResult", "chars name target digest key seq err")
Finding = namedtuple("Finding", "cls desc rule status label evidence rank", defaults=[()])

LIVE = "live"
CLASSIFIED = "auto-classified"

TERMINAL_FOUND = "TERMINAL STATE: candidates found (live candidates need adjudication)"
TERMINAL_ALL_CLASSIFIED = (
    "TERMINAL STATE: candidates found but all auto-classified (0 live; see the "
    "auto-classified section for the rule and evidence behind each dismissal)")
TERMINAL_CLEAN = "TERMINAL STATE: no candidates above thresholds (transcripts parsed successfully)"
TERMINAL_NO_DATA = (
    "TERMINAL STATE: no transcripts / parse failure (nothing was parsed — this is NOT "
    "evidence of cleanliness)")

# A8 probe-shaped predicate, matched on the parsed command VERB or a known exact form.
# TRIPWIRE: never widen any of these to an anywhere-in-the-string regex. `\bstatus\b`
# anywhere dismissed `echo status` x3 and `deploy --message status` x3 (A8 amendment,
# BLOCKER 5) — a probe token in argument position is not a probe.
PROBE_VERBS = {
    "pytest": "test runner (pytest)",
    "py.test": "test runner (pytest)",
    "run-tests": "test runner (run-tests)",
    "health-check": "health verb (health-check)",
    "preflight": "health verb (preflight)",
    "status": "status verb (status)",
}
PROBE_VERB_PAIRS = {
    ("npm", "test"): "test runner (npm test)",
    ("git", "status"): "status verb (git status)",
}
PROBE_FLAGS = {"--dry-run": "explicit --dry-run", "--version": "version verb (--version)"}
TEST_DIR_PREFIX = "hooks/tests/"
INTERPRETERS = {"bash", "sh", "zsh", "dash", "python", "python3", "py", "env", "time",
                "command", "nice", "stdbuf"}
VERB_SUFFIXES = (".sh", ".py", ".exe", ".bash", ".ps1")
SEGMENT_SPLIT = re.compile(r"\|\||&&|;|\||\n")
ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
DRIVE_RE = re.compile(r"^[A-Za-z]:(?:/|$)")

# TRIPWIRE: matched against the whitespace-normalized result HEAD only, and only ever
# as a boolean — the head itself never leaves result_size_and_digest (no-content-emitted).
ERROR_SHAPE = re.compile(r"(?i)^\s*(error\b|<tool_use_error>|exception\b|traceback\b)")

FALSE_POSITIVE_HEADER = (
    "Findings below are CANDIDATES that MAY indicate an FR-26 rule violation — "
    "not verdicts. Known false-positive classes: a WARRANTED FR-18 full-Write "
    "supersede (structure/mode/ticket change, or most sections changed — FR-18 "
    "mandates the replaced semantics, not the rewrite tool; a targeted Edit is "
    "the default primitive), mirror/overlay regeneration (generated "
    "copies), deliberate FR-10 3/3 reproduction runs, test reruns after a real "
    "change, bounded labeled flaky-external retries. For large-output: an "
    "intentional first read of a large file needed to hold its invariants, a "
    "warranted FR-18 full-Write supersede or mirror regeneration, generated output "
    "that is itself the subject of the task, deliberate FR-10 reproduction "
    "evidence, and a one-time large diagnostic report written to disk then read once. "
    "For repeat-output: a deliberately re-run command's fresh (different) output and "
    "FR-10 reproduction reruns are not re-sends of the same body."
)


def snippet(text, keep_tail=False):
    if not isinstance(text, str):
        text = str(text)
    one_line = " ".join(text.split())
    if keep_tail and len(one_line) > SNIPPET_MAX:
        head = (SNIPPET_MAX - 1) // 2
        return one_line[:head] + "…" + one_line[-(SNIPPET_MAX - 1 - head):]
    return one_line[:SNIPPET_MAX]


def git_root():
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=10,
        )
        if out.returncode == 0 and out.stdout.strip():
            return Path(out.stdout.strip())
    except Exception:
        pass
    return Path.cwd()


def munge(path_str):
    return re.sub(r"[^A-Za-z0-9]", "-", path_str)


def canon_path(raw, cwd=""):
    """Canonical path form for read keying and A8 contradiction checks.

    TRIPWIRE: pure string work, never a filesystem call — transcripts are parsed on a
    different host/cwd than the one that produced them, so `Path.resolve()` would silently
    re-root them. Separator-normalized, `.`/`..` collapsed, relative paths resolved against
    the transcript's own cwd, drive-letter paths case-folded (Windows semantics). Raw
    string equality made `C:/Repo/a.txt` and `c:\\repo\\a.txt` look like unrelated paths
    (A8 amendment, BLOCKER 6)."""
    t = str(raw or "").strip().strip('"').strip("'").replace("\\", "/")
    if not t:
        return ""
    if not (DRIVE_RE.match(t) or t.startswith("/")):
        base = str(cwd or "").strip().strip('"').strip("'").replace("\\", "/").rstrip("/")
        if base:
            t = base + "/" + t
    t = posixpath.normpath(t)
    return t.lower() if DRIVE_RE.match(t) else t


def locate_transcript_dir(root):
    projects = Path.home() / ".claude" / "projects"
    munged = munge(str(root.resolve()))
    exact = projects / munged
    if exact.is_dir():
        return exact
    # Windows drive-letter munge edge: on-disk dir name may differ only by case.
    if projects.is_dir():
        for child in projects.iterdir():
            if child.is_dir() and child.name.lower() == munged.lower():
                return child
    return None


def tool_target(name, tool_input):
    if not isinstance(tool_input, dict):
        return snippet(name)
    if name == "Read":
        t = str(tool_input.get("file_path", ""))
        off, lim = tool_input.get("offset"), tool_input.get("limit")
        if off is not None or lim is not None:
            t += " [offset=%s limit=%s]" % (off, lim)
        return snippet(t, keep_tail=True)
    if name in ("Bash", "PowerShell"):
        return snippet(tool_input.get("command", ""))
    for key in ("file_path", "notebook_path", "pattern", "url", "query", "path", "skill"):
        if tool_input.get(key):
            return snippet(str(tool_input[key]), keep_tail=True)
    return snippet(name)

def is_output_heavy(name):
    """A large result is a context-compression candidate when it came from an
    OUTPUT-producing tool — any built-in OR MCP (`mcp__*`) tool. Detected GENERICALLY by
    excluding write tools (their result is an edit confirmation; the bulk content is the
    edit itself, covered by the rewrite class) and the unmapped "?" sentinel (unknown
    provenance). An exclusion test, not an allowlist, so new built-ins and MCP servers
    are covered automatically instead of silently missed."""
    return name not in WRITE_TOOLS and name != "?"
