"""Evidence collection (read-only) for the find-wasted-effort analyzer.

Every collector reads real on-disk Flow artifacts (git log + diffstat, approval
artifacts, gate/deploy reports, handoffs, change-notes, round structure, the
ratchet-governance coverage map + on-disk prevents: markers) and shapes them
into the evidence dict the rule evaluators consume.

HONESTY CONTRACT (BLOCKER 1): when a rule's input is genuinely unavailable in
this repo, the collector returns a structured value carrying a `reason` string
so the rule emits an HONEST `inconclusive` with that reason — never a hard-coded
empty that masquerades as a real verdict. The reason names what was missing.

stdlib-only. No writes.
"""

import re
import subprocess
from pathlib import Path

from .constants import parse_prevents_classes

# A "round" = the commit cluster for one ticket slug (a deploy unit). We derive
# slugs from the docs trail (handoffs/change-notes/specs) and from commit subjects.
SLUG_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}-(.+?)-(?:implement|deploy|smoke)\.md$")
TNUM_RE = re.compile(r"\bT(\d+)\b")
# Suite-run trace lines a report records when it runs the full test suite.
SUITE_RUN_RE = re.compile(
    r"\b(run-tests|full suite|full-suite|test suite|npm (?:run )?test|pytest|"
    r"go test|cargo test)\b", re.IGNORECASE)
# A recorded fail-set (e.g. "0 failures", "3 failing", "all PASS", "FAIL: x").
FAILSET_RE = re.compile(
    r"\b(\d+)\s+fail(?:ing|ures?)?\b|\ball (?:pass|green)\b|\b0/\d+\b", re.IGNORECASE)
# A durable deploy-hash record (rule 7 cross-session re-derivation target).
DEPLOY_HASH_RE = re.compile(r"deploy(?:ed)?(?:\s+hash)?[:\s`]+([0-9a-f]{7,40})\b", re.IGNORECASE)


def read_text(path):
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def relpath(path, root):
    """POSIX-normalized path relative to root. Forward slashes ALWAYS so rule 6's
    per-element matching against ratchet-governance.yml (which uses forward slashes)
    is correct on Windows too — Path.relative_to() yields OS-native separators."""
    return str(path.relative_to(root)).replace("\\", "/")


# --------------------------------------------------------------------------
# git
# --------------------------------------------------------------------------

def git_log(root, n):
    """Return [(sha, subject)] for the last n commits; [] if git unavailable."""
    try:
        out = subprocess.run(
            ["git", "log", "-n", str(n), "--pretty=%H%x00%s"],
            capture_output=True, text=True, cwd=str(root), timeout=30,
        )
        if out.returncode != 0:
            return []
        rows = []
        for line in out.stdout.splitlines():
            if "\x00" in line:
                sha, subj = line.split("\x00", 1)
                rows.append((sha.strip(), subj.strip()))
        return rows
    except Exception:
        return []


def git_numstat(root, n):
    """Return {sha: (files_changed, insertions, deletions)} for the last n commits
    via `git log --numstat`. {} if git unavailable. Used by rule 5 (diff size)."""
    try:
        out = subprocess.run(
            ["git", "log", "-n", str(n), "--numstat", "--pretty=format:%x01%H"],
            capture_output=True, text=True, cwd=str(root), timeout=30,
        )
        if out.returncode != 0:
            return {}
        stats = {}
        cur = None
        for line in out.stdout.splitlines():
            if line.startswith("\x01"):
                cur = line[1:].strip()
                stats[cur] = [0, 0, 0]
                continue
            if cur is None or not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) >= 3:
                add, dele = parts[0], parts[1]
                stats[cur][0] += 1
                stats[cur][1] += int(add) if add.isdigit() else 0
                stats[cur][2] += int(dele) if dele.isdigit() else 0
        return {k: tuple(v) for k, v in stats.items()}
    except Exception:
        return {}


# --------------------------------------------------------------------------
# round structure (commit clusters keyed by ticket slug)
# --------------------------------------------------------------------------

def slug_from_subject(subject):
    """Heuristic slug from a commit subject: 'T18: ... (D5)' style or the
    spec/handoff slug if named. Returns None when no slug signal is present."""
    m = re.search(r"\b([a-z0-9]+(?:-[a-z0-9]+){2,})\b", subject)
    return m.group(1) if m else None


def build_rounds(commits, numstat):
    """Group commits into rounds. A round id is a ticket slug when derivable,
    else the lead commit sha. Returns {round_id: {commits, tnums, files, ins, del}}."""
    rounds = {}
    for sha, subj in commits:
        rid = slug_from_subject(subj) or sha[:7]
        r = rounds.setdefault(rid, {"commits": [], "tnums": set(), "files": 0,
                                    "ins": 0, "dele": 0, "subjects": []})
        r["commits"].append(sha)
        r["subjects"].append(subj)
        for m in TNUM_RE.finditer(subj):
            r["tnums"].add(int(m.group(1)))
        f, i, d = numstat.get(sha, (0, 0, 0))
        r["files"] += f
        r["ins"] += i
        r["dele"] += d
    return rounds


# --------------------------------------------------------------------------
# approval artifacts (promised input — MED finding)
# --------------------------------------------------------------------------

def collect_approvals(root):
    """Read state/approvals/*.json (the deploy-authority trail). Returns a list of
    {file, kind} dicts; [] when none on disk. Feeds rule-1 contrary evidence (an
    approval artifact is a recorded operator decision, not a silent gate skip)."""
    base = root / "state" / "approvals"
    out = []
    if not base.is_dir():
        return out
    for f in sorted(base.glob("*.json")):
        if f.name == ".gitkeep":
            continue
        name = f.name
        kind = name.split("-", 1)[0] if "-" in name else name.replace(".json", "")
        out.append({"file": relpath(f, root), "kind": kind})
    return out


# --------------------------------------------------------------------------
# round artifacts (handoffs, gate/deploy reports, change-notes)
# --------------------------------------------------------------------------

def collect_artifacts(root):
    """Round artifacts to scan: handoffs (tmp + durable), gate reports, deploy
    reports, change-notes, verification gates. Returns [(relpath, text)]."""
    out = []
    globs = [
        "docs/tmp/handoff/*.md",
        "docs/handoff/*.md",
        "docs/changes/*.md",
        "docs/specs/*/verification-gate.md",
        "docs/specs/*/gate-report.md",
        "docs/specs/*/deploy-report.md",
    ]
    seen = set()
    for g in globs:
        for f in sorted(root.glob(g)):
            try:
                rel = relpath(f, root)
            except ValueError:
                continue
            if f.is_file() and rel not in seen:
                seen.add(rel)
                out.append((rel, read_text(f)))
    return out


def artifact_slug(rel):
    rel = rel.replace("\\", "/")
    m = SLUG_RE.search(rel)
    if m:
        return m.group(1)
    # spec-dir artifacts: docs/specs/<slug>/...
    parts = rel.split("/")
    if len(parts) >= 3 and parts[0] == "docs" and parts[1] == "specs":
        return parts[2]
    return None


# --------------------------------------------------------------------------
# rule-2 input: full-suite run traces per round (BLOCKER 1)
# --------------------------------------------------------------------------

def collect_suite_runs(artifacts, rounds):
    """Derive per-round full-suite run counts + whether fail-sets were identical,
    from suite-run + fail-set traces in gate/deploy reports and handoffs.

    Returns ({round_id: (run_count, identical_failsets)}, reason). When NO artifact
    records a machine-readable suite-run trace, returns ({}, reason) so rule 2
    emits an honest inconclusive naming the missing input."""
    per_round = {}            # round_id -> {"runs": int, "failsets": [str,...]}
    for rel, text in artifacts:
        slug = artifact_slug(rel)
        if not slug:
            continue
        # only attribute traces to a round we actually grouped from git
        rid = slug if slug in rounds else None
        if rid is None:
            # still record under the slug so cross-report rounds aggregate
            rid = slug
        runs = 0
        failsets = []
        for line in text.splitlines():
            if SUITE_RUN_RE.search(line):
                runs += 1
                fm = FAILSET_RE.search(line)
                if fm:
                    failsets.append(fm.group(0).lower().strip())
        if runs:
            acc = per_round.setdefault(rid, {"runs": 0, "failsets": []})
            acc["runs"] += runs
            acc["failsets"].extend(failsets)
    if not per_round:
        return {}, ("no artifact records a machine-readable full-suite run trace "
                    "(reports do not log per-round suite-run counts/fail-sets)")
    result = {}
    for rid, acc in per_round.items():
        fs = [f for f in acc["failsets"] if f]
        identical = (len(set(fs)) <= 1) if fs else True
        result[rid] = (acc["runs"], identical)
    return result, None


# --------------------------------------------------------------------------
# rule-5 input: lane candidates (small diff + zero decisions + Full ceremony)
# --------------------------------------------------------------------------

SMALL_DIFF_FILES = 3         # <= this many files changed = "small"
SMALL_DIFF_LINES = 60        # <= this many net lines = "small"
DECISION_RE = re.compile(r"\b(decision|decisions\.md|locked decision|D\d\b|trade-?off|"
                         r"adversarial review|design (?:risk|option))\b", re.IGNORECASE)
FULL_LANE_RE = re.compile(r"\b(full lane|eight-phase|verification gate|deploy handoff|"
                          r"production_deploy)\b", re.IGNORECASE)
LIGHTWEIGHT_RE = re.compile(r"\b(lightweight|change-note|change_tier)\b", re.IGNORECASE)


def collect_lane_candidates(rounds, artifacts):
    """Pair per-round diff size (git) with decision presence + lane signal (docs).

    Returns (candidate_or_None, reason). A candidate = a clearly-small,
    zero-decision round that nonetheless ran Full ceremony. When diff size OR the
    decision/lane signal cannot be paired for ANY round, returns (None, reason)
    so rule 5 emits an honest inconclusive."""
    if not rounds:
        return None, "no git-derived rounds (git unavailable or empty history)"
    # index artifact text by slug for decision/lane signals
    by_slug = {}
    for rel, text in artifacts:
        slug = artifact_slug(rel)
        if slug:
            by_slug.setdefault(slug, []).append(text)

    best = None
    paired_any = False
    for rid, r in rounds.items():
        docs = by_slug.get(rid)
        if docs is None:
            # no doc trail for this round -> cannot judge decision/lane presence
            continue
        paired_any = True
        net_lines = r["ins"] + r["dele"]
        small = r["files"] and r["files"] <= SMALL_DIFF_FILES and net_lines <= SMALL_DIFF_LINES
        blob = "\n".join(docs)
        has_decision = bool(DECISION_RE.search(blob))
        ran_full = bool(FULL_LANE_RE.search(blob)) and not LIGHTWEIGHT_RE.search(blob)
        if small and not has_decision and ran_full:
            cand = {"round": rid, "clear": True,
                    "files": r["files"], "lines": net_lines}
            best = best or cand
        elif small and ran_full:
            # ambiguous: small + Full but a decision/risk was surfaced -> inconclusive
            best = best or {"round": rid, "clear": False,
                            "files": r["files"], "lines": net_lines}
    if not paired_any:
        return None, ("no round could pair git diff size with a decision/lane doc "
                      "trail (handoffs/specs absent for the windowed rounds)")
    return best, (None if best else
                  "no small-diff + zero-decision + Full-ceremony round in the window")


# --------------------------------------------------------------------------
# rule-7 input: cross-session re-derivation of a durable record (BLOCKER 1)
# --------------------------------------------------------------------------

def collect_cross_session_rederivation(artifacts):
    """Cross-session ceremony layer ONLY. Detect a later session re-deriving a
    deploy-hash that an earlier durable artifact already recorded.

    Returns (signal_or_None, reason). signal = {record, record_present, sessions}.
    When no cross-session deploy-hash signal exists, returns (None, reason) so
    rule 7 emits an honest inconclusive. Execution-layer polling is FR-26's axis
    and is NOT collected here."""
    # map deploy-hash -> set of artifact slugs that mention it (a "session" proxy:
    # distinct dated handoffs/reports are distinct cross-session records)
    hash_sources = {}
    for rel, text in artifacts:
        slug = artifact_slug(rel) or rel
        for m in DEPLOY_HASH_RE.finditer(text):
            h = m.group(1)
            hash_sources.setdefault(h, set()).add((slug, rel))
    if not hash_sources:
        return None, ("no durable deploy-hash record appears in the artifact window "
                      "(nothing for a later session to re-derive)")
    # a re-derivation candidate: the same hash recorded across >= 2 distinct
    # dated artifacts (the record existed AND a later artifact restated it).
    for h, sources in sorted(hash_sources.items()):
        rels = sorted({rel for _, rel in sources})
        if len(rels) >= 2:
            return ({"record": "deploy-hash %s" % h, "record_present": True,
                     "sessions": rels[:4]}, None)
    return None, ("each durable deploy-hash is recorded once — no cross-session "
                  "re-derivation of an already-durable record")


# --------------------------------------------------------------------------
# rule-1 input: gate deviation outcomes (approved vs blocked)
# --------------------------------------------------------------------------

GATE_BLOCK_RE = re.compile(
    r"\b(gate blocked|deviation rejected|redirect(?:ed)? (?:the )?ai developer|"
    r"do not bypass|gate fail(?:ed)?|blocked deploy|STOP→Full|stop to full)\b",
    re.IGNORECASE)
GATE_APPROVE_RE = re.compile(
    r"\b(approved per operator|operator approved|deviation approved|"
    r"self-approved per fr-03|approved every deviation)\b", re.IGNORECASE)


def collect_gate_outcomes(artifacts):
    """Count recorded gate deviation outcomes: approvals vs blocks. Conservative
    (only unambiguous phrases) so the rule degrades to inconclusive, never to a
    false confirmed. Returns (approvals, blocks)."""
    approvals = blocks = 0
    for _, text in artifacts:
        approvals += len(GATE_APPROVE_RE.findall(text))
        blocks += len(GATE_BLOCK_RE.findall(text))
    return approvals, blocks


# --------------------------------------------------------------------------
# rule-3 input: verbatim duplicate blocks across artifacts
# --------------------------------------------------------------------------

def detect_duplicate_blocks(artifacts, fp_header):
    """Verbatim multi-line blocks appearing in >= DUP_BLOCK_MIN artifacts.
    Block = a paragraph (>=120 chars) separated by blank lines. Self-bootstrapping
    markers downgrade a block to dismissed."""
    from .constants import DUP_BLOCK_MIN
    boot_markers = ("Role bootstrap", "Self-attest", fp_header[:40],
                    "Operating as", "Mode B (full)")
    para_files = {}
    for rel, text in artifacts:
        for para in re.split(r"\n\s*\n", text):
            p = para.strip()
            if len(p) >= 120:
                para_files.setdefault(p, set()).add(rel)
    dups = []
    for para, files in para_files.items():
        if len(files) >= DUP_BLOCK_MIN:
            bootstrapping = any(m in para for m in boot_markers)
            dups.append({"count": len(files), "files": sorted(files)[:5],
                         "bootstrapping": bootstrapping})
    dups.sort(key=lambda d: -d["count"])
    return dups


# --------------------------------------------------------------------------
# rule-6 input: ratchet governance coverage map + on-disk prevents: markers
# --------------------------------------------------------------------------

def collect_prevents_annotations(root):
    """Map relative file -> {element_line: set(classes)} for every prevents: marker
    on disk, AND file -> set(all classes). Returns (per_file_classes, per_line).
    per_line lets rule 6 do PER-ELEMENT verdicts, not a whole-file roll-up."""
    per_file = {}
    per_line = {}             # relpath -> [ (lineno, text, set(classes)) ]
    for d in ("templates", "workflows"):
        base = root / d
        if not base.is_dir():
            continue
        for f in sorted(base.rglob("*.md")):
            rel = relpath(f, root)
            classes_all = set()
            lines = []
            for i, line in enumerate(read_text(f).splitlines(), start=1):
                cs = parse_prevents_classes(line)
                if cs:
                    classes_all |= cs
                    lines.append((i, line.strip(), cs))
            if classes_all:
                per_file[rel] = classes_all
                per_line[rel] = lines
    return per_file, per_line


def load_ratchet_governance(root):
    """Tolerant stdlib parse of the coverage map (no yaml dependency). Returns
    (elements, parsed_ok, severity_tag). Each element: {file, element, prevents
    (list), severity}. We need per-element file/element/prevents/severity to drive
    rule 6's PER-ELEMENT contract."""
    path = root / "policies" / "ratchet-governance.yml"
    text = read_text(path)
    if not text:
        return [], False, "catastrophic-low-frequency"
    elements = []
    cur = {}
    in_annotated = False
    severity_tag = "catastrophic-low-frequency"
    for raw in text.splitlines():
        stripped = raw.strip()
        if stripped.startswith("severity_tag:"):
            val = stripped.split("severity_tag:", 1)[1].strip().strip('"').strip("'")
            # strip trailing inline comment
            val = val.split("#", 1)[0].strip().strip('"').strip("'")
            if val:
                severity_tag = val
        if stripped.startswith("annotated_elements:"):
            in_annotated = True
            continue
        if in_annotated and stripped.startswith("not_in_scope_phase1:"):
            break
        if not in_annotated:
            continue
        if stripped.startswith("- file:"):
            if cur:
                elements.append(cur)
            cur = {"file": stripped.split("file:", 1)[1].strip(), "prevents": [],
                   "severity": None}
        elif stripped.startswith("element:"):
            cur["element"] = stripped.split("element:", 1)[1].strip().strip('"')
        elif stripped.startswith("prevents:"):
            raw_p = stripped.split("prevents:", 1)[1].strip()
            cur["prevents"] = _parse_yaml_list(raw_p)
        elif stripped.startswith("severity:"):
            cur["severity"] = stripped.split("severity:", 1)[1].strip()
    if cur:
        elements.append(cur)
    return elements, True, severity_tag


def _parse_yaml_list(raw):
    """Parse `[a, b]` inline list or a bare scalar into a list of strings."""
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        inner = raw[1:-1]
        return [x.strip() for x in inner.split(",") if x.strip()]
    return [raw] if raw else []


def collect_firing_evidence(artifacts):
    """Map incident-class -> True when an artifact shows that class's control
    FIRED in the window (a gate stop, a rollback used, a worker-undisturbed catch).
    A fired control is NOT a waste candidate (rule 6 contrary evidence). Returns
    a set of incident-classes with firing evidence."""
    fired = set()
    text_all = "\n".join(t for _, t in artifacts)
    low = text_all.lower()
    # narrow, high-precision firing signals per class
    if GATE_BLOCK_RE.search(text_all):
        fired |= {"false-green-deploy", "unauthorized-deploy"}
    if "git revert" in low and ("rollback" in low or "reverted" in low):
        fired.add("irreversible-loss")
    if ("worker-undisturbed" in low or "protected path" in low) and \
            ("non-empty diff" in low or "changed since gate" in low or "stop" in low and "drift" in low):
        fired.add("silent-protected-path-drift")
    if "abort" in low and "approve-deploy-now" in low:
        fired.add("unattended-prod-cutover")
    return fired
