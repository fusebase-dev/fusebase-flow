#!/usr/bin/env python3
"""The 6.0 commit-msg rules (handoff WP 10; decision 10(c)): `commit_msg.py <message file>`, run by hooks/git/commit-msg
from the top of the work tree; exit 0 accept, 1 reject with the reason on stderr.

- A merge (MERGE_HEAD present) passes; `Revert "<s>"` is judged as <s>.
- A subject matching an `exempt_subjects` form of policies/evidence-classes.yml at HEAD passes whatever it stages: the
  FuseBase CLI's two update checkpoints.
- `plan:` and `ship:` pass only when every staged path is one the plan or ship skill's commit stages; `flow:` (Flow's
  own install, migration and upgrade) only when every staged path is Flow's own or one of the four documents
  (flow_owned.py).
- Any other subject carries exactly one T<n>. When docs/flow/phases.md at HEAD has tasks, T<n> must be one of them; a
  commit of the four documents alone, or a trivial-tier commit, needs nothing more; any other needs the task's item
  in backlog.md at HEAD.
- Trivial tier: every staged path matches the `trivial` lists of policies/evidence-classes.yml at HEAD (no local twin,
  never the staged copy), a code extension only through `test`, a deleted test or an added skip never; or every staged
  change is formatting (whitespace and blank lines).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

BLOCK = "[fusebase-flow:commit-msg] BLOCK — "
try:
    import yaml
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import flow_docs as fd
    import flow_owned
except ImportError as exc:  # one Flow line, never a traceback (O-19)
    FIX = (f'"{sys.executable}" -m pip install -r hooks/requirements.txt' if exc.name == "yaml" else
           "re-run the Flow install, which restores hooks/local/lib/")
    sys.exit(f"{BLOCK}{exc.name or exc} cannot be imported, so the subject cannot be checked. Fix: {FIX}; "
             "NEVER use --no-verify.")

FOUR = re.compile(r"docs/flow/(backlog|phases|evidence|ledger)\.md|docs/flow/evidence/[^/]+\.md")
PLAN = re.compile(r"state/flags/[^/]+\.tsv|state/gate/[^/]+\.txt")  # flow-skills/plan/SKILL.md, "Commit"
SHIP = re.compile(r"state/flags/[^/]+\.tsv|state/gate/[^/]+\.txt|state/done/[^/]+\.json|state/deploys/[^/]+\.jsonl")
VAGUE = re.compile(r"^(?:T\d+|plan|ship)\b[:\s]*(update|fix|changes|misc|stuff|wip)\.?$", re.I)
SKIP = re.compile(r"^\+(?!\+\+).*\b(skip|todo)\b", re.I | re.M)


def subject_of(text: str) -> str:
    lines = [ln for ln in text.splitlines() if ln.strip() and not ln.startswith("#")]
    subject = lines[0].strip() if lines else ""
    while m := re.fullmatch(r'Revert "(.*)"', subject):  # decision 10(c) condition 2
        subject = m[1].strip()
    return subject


def exempt(root: Path, subject: str) -> bool:
    """The subject matches a form the committed policy names (O-20), whole; never a local twin or the working tree."""
    try:
        doc = yaml.safe_load(fd.git(root, "show", "HEAD:policies/evidence-classes.yml")) or {}
        return any(re.fullmatch(str(form), subject) for form in doc.get("exempt_subjects") or [])
    except (yaml.YAMLError, AttributeError, TypeError, re.error):
        return False


def code_extensions(root: Path) -> set[str]:
    try:
        globs = (yaml.safe_load(fd.git(root, "show", "HEAD:policies/module-size.yml")) or {}).get("source_globs") or []
    except (yaml.YAMLError, AttributeError):
        globs = []
    return {m[1] for g in globs if (m := re.search(r"\*(\.\w+)$", str(g)))}


def trivial(root: Path, staged: list[str], deleted: set[str]) -> bool:
    try:
        lists = (yaml.safe_load(fd.git(root, "show", "HEAD:policies/evidence-classes.yml")) or {}).get("trivial") or {}
    except (yaml.YAMLError, AttributeError):
        return False
    match, code = fd.globber(), code_extensions(root)
    tests, prose = list(lists.get("test") or []), [*(lists.get("docs_only") or []), *(lists.get("copy") or [])]
    for p in staged:
        if match(p, tests):
            if p in deleted or SKIP.search(fd.git(root, "diff", "--cached", "--", p)):
                return False
        elif Path(p).suffix in code or not match(p, prose):
            return False
    return bool(staged)


def formatting_only(root: Path, pairs: list[tuple[str, str]]) -> bool:
    """Every staged path is modified, and only in whitespace or blank lines (git then prints no hunk at all)."""
    lines = fd.git(root, "diff", "--cached", "--no-renames", "-w", "--ignore-blank-lines", "-U0", "--no-color",
                   "--no-ext-diff").splitlines()
    heads = ("old mode", "new mode", "Binary files")
    return bool(pairs) and all(s == "M" for s, _ in pairs) and not any(
        ln.startswith(heads) or (ln.startswith(("+", "-")) and not ln.startswith(("+++", "---"))) for ln in lines)


def merging(root: Path) -> bool:
    """A merge is told by git's state, never by its subject (decision 10(c) condition 1)."""
    rel = fd.git(root, "rev-parse", "--git-path", "MERGE_HEAD").strip()
    return bool(rel) and (Path(rel) if Path(rel).is_absolute() else root / rel).is_file()


def check(root: Path, text: str) -> str | None:
    """None when the message passes, else the reason."""
    if merging(root):
        return None
    subject = subject_of(text)
    if not subject:
        return "empty commit message."
    if exempt(root, subject):
        return None
    if VAGUE.match(subject):
        return f"vague subject: '{subject}'. Say what the commit does, such as 'T17: reject magic links older than 15 minutes'."
    names = fd.git(root, "diff", "--cached", "--name-status", "--no-renames", "-z", "--ignore-submodules=none").split("\0")
    pairs = [(names[i], names[i + 1]) for i in range(0, len(names) - 1, 2)]
    staged, deleted = [p for _, p in pairs], {p for s, p in pairs if s.startswith("D")}
    if subject.startswith("flow:"):  # O-21
        other = flow_owned.foreign(root, [(s, p) for s, p in pairs if not FOUR.fullmatch(p)])
        return (f"a `flow:` commit stages Flow's own files (as audit/flow-install.json records them), the four "
                f"documents and Flow's marked blocks only; this one also stages {', '.join(other[:5])}. Unstage those "
                "and commit them under a task's T<n>.") if other else None
    if m := re.match(r"(plan|ship):\s", subject):
        allowed = PLAN if m[1] == "plan" else SHIP
        other = [p for p in staged if not (FOUR.fullmatch(p) or allowed.fullmatch(p))]
        return (f"a `{m[1]}:` commit stages the four documents and the state files its skill names only; this one also "
                f"stages {', '.join(other[:5])}. Commit those under a task's T<n>.") if other else None
    ids = sorted(set(fd.TASK.findall(subject)))
    if len(ids) != 1:
        return ("implementation commits must cite a T-number (FR-03): exactly one T<n> in the subject, `plan:` or "
                "`ship:` on a commit of the four documents, or `flow:` on Flow's own files. "
                f"Subject: {subject}" if not ids else
                f"exactly one T<n> per commit (FR-03); the subject names {', '.join(ids)}. Split the commit.")
    tasks = {t["id"]: t for s in fd.phases(root, fd.uncomment(fd.git(root, "show", f"HEAD:{fd.PHASES}"))).values()
             for t in s["tasks"]}
    if not tasks:
        return None  # no plan at HEAD yet (a fresh install, a migration): the id cannot be resolved
    if ids[0] not in tasks:
        return f"{ids[0]} is not a task in {fd.PHASES} at HEAD; plan it first (a `plan:` commit), or use its own id."
    if all(FOUR.fullmatch(p) for p in staged) or trivial(root, staged, deleted) or formatting_only(root, pairs):
        return None
    item = tasks[ids[0]]["item"]
    if not re.fullmatch(r"B\d+", item) or item not in fd.backlog(fd.uncomment(fd.git(root, "show", f"HEAD:{fd.BACKLOG}")))[0]:
        return (f"{ids[0]}'s task names no backlog item at HEAD (`{item or '-'}`), and this commit stages a path outside the "
                "trivial-tier lists of policies/evidence-classes.yml; rule 1 needs the item first.")
    return None


def main(argv: list[str]) -> int:
    root = Path(fd.git(Path.cwd(), "rev-parse", "--show-toplevel").strip() or Path.cwd())
    why = check(root, Path(argv[0]).read_text(encoding="utf-8", errors="replace"))
    if why:
        print(BLOCK + why, file=sys.stderr)
        print("Examples: 'T17: reject magic links older than 15 minutes', 'plan: phase 2 slices', 'ship: P1 to dev'.",
              file=sys.stderr)
    return 1 if why else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
