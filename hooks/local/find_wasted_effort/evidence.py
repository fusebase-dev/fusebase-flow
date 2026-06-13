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
    {file, kind} dicts; [] when none on disk. CONSUMED by rule 1 as contrary
    evidence: a deviation-gating approval (see DEVIATION_GATING_APPROVALS) is a
    recorded operator decision that authorized a real deviation — a gate that
    bought an outcome, which dismisses rule 1's "every deviation rubber-stamped"
    signal. The artifact name encodes the kind: <operation>-<slug>-<date>.json,
    so the kind is the leading token before the slug."""
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


def deviation_gating_approvals(approvals):
    """Subset of collected approvals whose KIND gates a real deviation from a
    default (rule-1 contrary evidence). Routine-deploy kinds are excluded — they
    are the happy path, not a deviation a gate had to stop and authorize."""
    from .constants import DEVIATION_GATING_APPROVALS
    return [a for a in approvals if a["kind"] in DEVIATION_GATING_APPROVALS]


# --------------------------------------------------------------------------
# round artifacts (handoffs, gate/deploy reports, change-notes)
# --------------------------------------------------------------------------

def collect_artifacts(root):
    """Round artifacts to scan: handoffs (tmp + durable), gate reports, deploy
    reports (incl. dated filename variants + reports saved under state/), change-
    notes, verification gates. Returns [(relpath, text)].

    The dated/variant report globs (deploy-report-<date>.md, gate-report-<date>.md,
    and gate/deploy reports persisted under state/) exist so artifact_kind() can
    classify a REAL recorded outcome saved under a real-world filename — not only
    the exact docs/specs/<slug>/gate-report.md basename (MED fix: false negatives
    when a genuine outcome lives at a dated path)."""
    out = []
    globs = [
        "docs/tmp/handoff/*.md",
        "docs/handoff/*.md",
        "docs/changes/*.md",
        "docs/specs/*/verification-gate.md",
        "docs/specs/*/gate-report.md",
        "docs/specs/*/gate-report-*.md",
        "docs/specs/*/deploy-report.md",
        "docs/specs/*/deploy-report-*.md",
        "docs/tmp/handoff/*-smoke/*.md",
        "state/gate-report*.md",
        "state/deploy-report*.md",
        "state/reports/*.md",
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
# artifact kind + recorded-outcome extraction (HIGH integrity fix)
#
# Outcome / firing / block evidence must come ONLY from ACTUAL RECORDED OUTCOMES
# — a gate-report or deploy-report's outcome/result sections — NEVER from a spec,
# a verification-gate (which is INSTRUCTIONAL: "If ANY item fails, redirect AI
# Developer. Do NOT bypass."), a handoff, a change-note, or a template/example/
# rollback section. And matching is PER-ARTIFACT: a token in one file plus a token
# in another file must NOT combine into one fabricated event (no concatenation).
# --------------------------------------------------------------------------

# A recorded-report basename: the exact report names AND their dated variants
# (deploy-report-2026-06-13.md, gate-report-<date>.md). Matched as report-name +
# optional `-<anything>` suffix + `.md`, so a dated filename a real deploy saved
# is recognized as an outcome source (MED fix), while spec.md / verification-gate.md
# / decisions.md remain instructional.
_GATE_REPORT_BASE_RE = re.compile(r"^gate-report(?:-[a-z0-9._-]+)?\.md$", re.IGNORECASE)
_DEPLOY_REPORT_BASE_RE = re.compile(r"^deploy-report(?:-[a-z0-9._-]+)?\.md$", re.IGNORECASE)
# A recorded-report HEADER (markdown H1) — the title a filled gate/deploy REPORT
# carries ("# Gate report — <slug>", "# Deploy report — <slug>"). A deploy
# *handoff* (instructional) titles itself "# Deploy handoff" / "Role bootstrap",
# so the header discriminates a real outcome saved at a handoff-style path
# (docs/tmp/handoff/<date>-<slug>-deploy.md) from the instructional handoff.
_GATE_REPORT_HEADER_RE = re.compile(r"^\s{0,3}#{1,3}\s+gate report\b", re.IGNORECASE | re.MULTILINE)
_DEPLOY_REPORT_HEADER_RE = re.compile(r"^\s{0,3}#{1,3}\s+deploy report\b", re.IGNORECASE | re.MULTILINE)
# A handoff-style path where a recorded report may be saved under a -deploy/-smoke
# filename (and therefore needs the header sniff to tell report from handoff).
_HANDOFF_REPORT_PATH_RE = re.compile(r"^(?:docs/tmp/handoff|docs/handoff|state)/", re.IGNORECASE)


def artifact_kind(rel, text=None):
    """Classify an artifact so the outcome collectors scan ONLY recorded-report
    kinds. Classification is by report-basename (incl. dated variants) AND, for a
    handoff-style path that may hold either an instructional handoff or a recorded
    report under a -deploy/-smoke filename, by the report HEADER in `text` (MED
    fix). Returns one of:
      'gate-report' | 'deploy-report'  -> recorded OUTCOMES (scan outcome sections)
      'verification-gate' | 'spec' | 'decisions' | 'handoff' | 'change-note' |
      'other'                          -> INSTRUCTIONAL/spec/contract text (never an
                                          outcome source for blocks/firings)

    A spec.md / verification-gate.md / decisions.md / *-implement.md handoff is
    NEVER reclassified as a recorded report — re-admitting that instruction text
    was the HIGH finding and stays excluded.
    """
    relp = rel.replace("\\", "/")
    base = relp.rsplit("/", 1)[-1].lower()
    # Exact instruction surfaces — never an outcome source, regardless of header.
    if base == "verification-gate.md":
        return "verification-gate"
    if base == "spec.md":
        return "spec"
    if base == "decisions.md":
        return "decisions"
    if base.endswith("-implement.md"):
        return "handoff"
    # Recorded-report basenames (exact + dated variants).
    if _GATE_REPORT_BASE_RE.match(base):
        return "gate-report"
    if _DEPLOY_REPORT_BASE_RE.match(base):
        return "deploy-report"
    # A -deploy/-smoke file on a handoff-style path: report iff its HEADER says so;
    # otherwise it's the instructional handoff. The header check requires `text`.
    if (base.endswith("-deploy.md") or base.endswith("-smoke.md")) and \
            _HANDOFF_REPORT_PATH_RE.match(relp):
        if text:
            if _DEPLOY_REPORT_HEADER_RE.search(text):
                return "deploy-report"
            if _GATE_REPORT_HEADER_RE.search(text):
                return "gate-report"
        return "handoff"
    if base.endswith("-deploy.md") or base.endswith("-smoke.md"):
        return "handoff"
    if "/docs/changes/" in ("/" + relp):
        return "change-note"
    return "other"


# Recorded-report kinds whose OUTCOME sections may source a real gate-block or a
# real control firing. Everything else is instructional/spec/contract text.
RECORDED_REPORT_KINDS = frozenset({"gate-report", "deploy-report"})

# A heading that names a genuine RECORDED OUTCOME — including a rollback/recovery
# RESULT (as opposed to the rollback PROCEDURE). Checked BEFORE the non-outcome
# regex so "## Rollback result" / "## Rollback outcome" reopens an outcome section
# even though it contains the word "rollback" (MED fix: a genuine recorded rollback
# result was being stripped along with the procedure). "rolled back" / "probe
# failed" / "gate blocked" / "redeploy" in a heading are recorded-outcome signals.
_OUTCOME_HEADING_RE = re.compile(
    r"^\s{0,3}#{1,6}\s+.*\b("
    r"rollback result|rollback outcome|rollback executed|rolled back|"
    r"recovery (?:result|outcome|taken|executed)|"
    r"probe result|probe failed|gate blocked|redeploy(?:ed)?|"
    r"smoke|deploy command|gate satisfaction|pre-deploy|"
    r"deviation|test count|worker-undisturbed|status|result|outcome)\b",
    re.IGNORECASE)
# Section headings (markdown ##/###) whose BODY is instructional / example /
# template / rollback PROCEDURE text — excluded even inside a recorded report so a
# rollback EXAMPLE ("git revert <hash>") or a "use this template when" block is
# never mistaken for a recorded firing/block. `rollback` / `recovery` trip this
# ONLY when paired with procedure/example/steps/how-to words — a bare "## Rollback
# result" is an OUTCOME (handled above), not stripped (MED fix).
_NON_OUTCOME_HEADING_RE = re.compile(
    r"^\s{0,3}#{1,6}\s+.*\b("
    r"(?:rollback|recovery)\s+(?:procedure|example|steps?|playbook|template|guide)|"
    r"(?:procedure|example|steps?|playbook|guide)\s+(?:for\s+)?(?:rollback|recovery)|"
    r"use this template|fill-in|why .* matters|example|template body|"
    r"if a probe failed|appendix|how to|procedure)\b",
    re.IGNORECASE)
# Template/example placeholder lines (angle-bracket fills, code-fence template
# bodies) carry instruction grammar, not a recorded outcome.
_TEMPLATE_PLACEHOLDER_RE = re.compile(r"<[a-z][a-z0-9 _/+-]*>", re.IGNORECASE)
# A literal instruction line that ships in the verification-gate/gate-report
# TEMPLATE body ("If ANY item fails, redirect AI Developer. Do NOT bypass.").
_INSTRUCTION_LINE_RE = re.compile(
    r"\b(if any .*fails?|do not bypass|redirect(?:ed)? .* developer|"
    r"replace this section|must show|paste (?:the|this|actual)|"
    r"use this section instead)\b", re.IGNORECASE)


def recorded_outcome_text(text):
    """Return ONLY the recorded-outcome lines of a report — the lines that state
    what ACTUALLY happened — with instructional / example / rollback / template
    boilerplate stripped. Lines inside a non-outcome section heading are dropped;
    template-placeholder lines (`<...>`) and literal instruction lines are dropped.
    The result is what the outcome collectors regex-match (per-artifact)."""
    kept = []
    in_non_outcome = False
    for line in text.splitlines():
        # OUTCOME headings are tested FIRST so a heading naming a result/outcome
        # (e.g. "## Rollback result", "## Recovery outcome") reopens an outcome
        # section even though it shares a word with the non-outcome pattern (MED fix).
        if _OUTCOME_HEADING_RE.match(line):
            in_non_outcome = False
            # keep the outcome heading itself out of the matched body
            continue
        if _NON_OUTCOME_HEADING_RE.match(line):
            in_non_outcome = True
            continue
        if in_non_outcome:
            continue
        if _TEMPLATE_PLACEHOLDER_RE.search(line):
            continue
        if _INSTRUCTION_LINE_RE.search(line):
            continue
        kept.append(line)
    return "\n".join(kept)


# --------------------------------------------------------------------------
# rule-2 input: full-suite run traces per round (BLOCKER 1)
# --------------------------------------------------------------------------

def collect_suite_runs(artifacts, rounds):
    """Derive per-round full-suite run counts + whether fail-sets were identical,
    from suite-run + fail-set traces in gate/deploy reports and handoffs.

    Returns ({round_id: (run_count, identical_failsets, failset_complete)}, reason).
    `failset_complete` is True ONLY when a fail-set was recorded for EVERY counted
    run (>=1 fail-set and one per run); when fail-sets are missing or fewer than the
    run count, it is False so rule 2 returns inconclusive instead of a false confirm
    (HIGH finding — a confirm requires real evidence that the repeated runs had
    IDENTICAL recorded fail-sets, per rule-signatures.md:20-25). When NO artifact
    records a machine-readable suite-run trace, returns ({}, reason) so rule 2 emits
    an honest inconclusive naming the missing input."""
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
        # complete = a fail-set recorded for every counted run (>=1, one per run).
        # Without this, runs with NO recorded fail-set would default to "identical"
        # and falsely confirm. Fewer fail-sets than runs is incomplete evidence too.
        failset_complete = bool(fs) and len(fs) >= acc["runs"]
        identical = (len(set(fs)) <= 1) if fs else False
        result[rid] = (acc["runs"], identical, failset_complete)
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

# A RECORDED gate block — a real outcome ("the gate blocked X", "deviation
# rejected", a recorded probe/deploy FAILURE). The old set included INSTRUCTIONAL
# phrases ("redirect AI Developer", "do not bypass") that ship in the verification-
# gate TEMPLATE — those are now excluded (they describe what SHOULD happen, not what
# DID). They are additionally stripped by recorded_outcome_text() as defense in depth.
GATE_BLOCK_RE = re.compile(
    r"\b(gate blocked|deviation rejected|blocked the deploy|blocked deploy|"
    r"deploy failed|probe failed|smoke failed|stopped (?:the )?deploy|"
    r"halted at the gate)\b",
    re.IGNORECASE)
GATE_APPROVE_RE = re.compile(
    r"\b(approved per operator|operator approved|deviation approved|"
    r"self-approved per fr-03|approved every deviation)\b", re.IGNORECASE)


def collect_gate_outcomes(artifacts):
    """Count recorded gate deviation outcomes: approvals vs blocks.

    INTEGRITY (HIGH fix): blocks/approvals are counted ONLY from ACTUAL RECORDED
    OUTCOMES — gate-report / deploy-report OUTCOME sections — NEVER from a
    verification-gate template, a spec, a handoff, or a change-note (all
    INSTRUCTIONAL). Matching is PER-ARTIFACT (no concatenation), so a token in one
    file cannot combine with a token in another to fabricate one event. Returns
    (approvals, blocks)."""
    approvals = blocks = 0
    for rel, text in artifacts:
        if artifact_kind(rel, text) not in RECORDED_REPORT_KINDS:
            continue                       # instructional/spec/contract text — never an outcome
        body = recorded_outcome_text(text)  # strip rollback/example/template/instruction
        approvals += len(GATE_APPROVE_RE.findall(body))
        blocks += len(GATE_BLOCK_RE.findall(body))
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
    """Map incident-class -> True when a RECORDED REPORT shows that class's control
    actually FIRED in the window (a real gate stop, a rollback that was USED, a
    worker-undisturbed catch that recorded a real drift). A fired control is NOT a
    waste candidate (rule 6 contrary evidence). Returns the set of incident-classes
    with firing evidence.

    INTEGRITY (HIGH fix), three rails:
      1. ONLY recorded-report kinds (gate-report / deploy-report) source a firing —
         a spec's rollback EXAMPLE ("git revert <hash>") or a verification-gate
         instruction is never a firing.
      2. ONLY each report's recorded-OUTCOME section is scanned — rollback
         PROCEDURE / example / template sections are stripped first.
      3. Matching is PER-ARTIFACT — tokens are required to co-occur WITHIN ONE
         report's outcome text, so `abort` in one file + `APPROVE-DEPLOY-NOW` in an
         unrelated file can NOT combine into one fabricated unattended-cutover event.
    """
    fired = set()
    for rel, text in artifacts:
        if artifact_kind(rel, text) not in RECORDED_REPORT_KINDS:
            continue
        body = recorded_outcome_text(text)
        low = body.lower()
        # narrow, high-precision firing signals per class — evaluated PER-ARTIFACT
        if GATE_BLOCK_RE.search(body):
            fired |= {"false-green-deploy", "unauthorized-deploy"}
        # a rollback that was actually USED (past-tense outcome), not the procedure.
        # The rollback PROCEDURE / `git revert <hash>` EXAMPLE is already stripped by
        # recorded_outcome_text(), so a past-tense "rolled back" in a result/status
        # section is a genuine firing, not template boilerplate.
        if ("rolled back the deploy" in low or "rollback executed" in low or
                "reverted the deploy" in low or "deploy was rolled back" in low):
            fired.add("irreversible-loss")
        # a worker-undisturbed catch that recorded a REAL drift in this report
        if ("worker-undisturbed" in low or "protected path" in low) and \
                ("non-empty diff" in low or "changed since gate" in low or
                 ("drift" in low and "detected" in low)):
            fired.add("silent-protected-path-drift")
        # an unattended-cutover catch: BOTH tokens must appear in THIS report's
        # outcome text (per-artifact), describing a real aborted cutover.
        if "abort" in low and "approve-deploy-now" in low:
            fired.add("unattended-prod-cutover")
    return fired
