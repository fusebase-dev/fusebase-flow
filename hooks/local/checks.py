#!/usr/bin/env python3
"""Checks against overbuilding (design sections 5 and 14; handoff WP 8): `checks.py <slice>` prints the four flags and
writes them to state/flags/<slice>.tsv (id, check, task, evidence, ruling: the planner writes upheld or rejected, and a
re-run keeps it); `checks.py --precision [<slice>]` counts the rulings per check. A flag never blocks the slice.

1 scope: a path the slice changed outside its tasks' globs (outside), or a new one (new); each glob's breadth printed.
2 dependency and config: a new runtime dependency no item of the slice names (dep) or the reference project's manifest
  lacks (dep-ref), a new config key (cfg), a new environment variable read (env). Logged, not flagged: development
  dependencies, keys in a file the slice created, variables read only under test paths.
3 budget: past 2x a task's minutes before its commit, or 2x its files (test paths counted apart); a no-commit span over
  200 calls; over 135 calls before first work (state/returns/<slice>.json); one command hash 3 times in flight (logged).
4 redundancy: more than 20 lines duplicated in the project's code outside vendored_paths.
A trivial-tier slice (every commit inside the policy's trivial lists) runs no flag 1 or 4, and its brief no rubric.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import flow_docs as fd  # noqa: E402
import reader  # noqa: E402  (the heartbeat files, for the repeated command)

# Thresholds, each with its provenance (non-negotiable 2); reader.REPEATS is UNCALIBRATED and logs.
BUDGET_X = 2              # owner seed 2026-10-15: 2x the phases.md estimate in minutes or files, with no commit
NO_COMMIT_CALLS = 200     # p99 of 434 between-commit spans, release 1 (design section 14)
ORIENTATION_CALLS = 135   # p99 of 156 working agents' calls before first work, release 1 (design section 14)
DUP_LINES = 20            # owner seed 2026-10-15; the smallest real duplicate on release 1 was 27 lines
# Classification as the release 1 calibration run (--retro) used it.
CODE = (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".css", ".scss", ".py", ".sh", ".sql", ".vue", ".svelte")
SKIP_DIRS = {"node_modules", "dist", ".vite", "coverage"}
RUNTIME = ("dependencies", "peerDependencies", "optionalDependencies")
INTERNAL = ("workspace:", "file:", "link:")
ENV_BUILTINS = set("NODE_ENV MODE DEV PROD SSR BASE_URL CI".split())
ENV_RE = re.compile(r"process\.env\.([A-Z_][A-Z0-9_]*)|process\.env\[\s*[\"']([A-Z_][A-Z0-9_]*)[\"']\s*\]"
                    r"|import\.meta\.env\.([A-Z_][A-Z0-9_]*)|os\.environ(?:\.get\(|\[)\s*[\"']([A-Z_][A-Z0-9_]*)[\"']"
                    r"|os\.getenv\(\s*[\"']([A-Z_][A-Z0-9_]*)[\"']|Deno\.env\.get\(\s*[\"']([A-Z_][A-Z0-9_]*)[\"']")
JSONC = re.compile(r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/|,(?=\s*[}\]])', re.S)
RECORDS = ("docs/flow/", "state/")  # Flow's own records are never a scope or file-budget path


def load_json(text: str) -> dict | None:
    """A JSON object; tsconfig's comments and trailing commas are dropped first (strings kept). None when unreadable."""
    def strip(s: str) -> str:
        return JSONC.sub(lambda m: m[1] or "", s)
    for attempt in (text, strip(strip(text))):  # twice: a comma that stood before a comment
        try:
            obj = json.loads(attempt)
            return obj if isinstance(obj, dict) else None
        except ValueError:
            continue
    return None


def keys(obj: dict) -> set[str]:
    return set(obj) | {f"{k}.{k2}" for k, v in obj.items() if isinstance(v, dict) for k2 in v}


def added_lines(root: Path, cmd: str, *args: str) -> dict[str, list[tuple[int, str]]]:
    """{path: [(line number, text)]} of the lines `git show --format= <sha>` or `git diff <base> HEAD -- ...` adds."""
    out: dict[str, list[tuple[int, str]]] = {}
    path, line = None, 0
    for text in fd.git(root, cmd, "-U0", "--no-renames", "--no-color", *args).splitlines():
        if text.startswith("+++ "):
            path = text[6:] if text.startswith("+++ b/") else None
        elif text.startswith("@@") and path:
            line = int(re.search(r"\+(\d+)", text)[1])
        elif text.startswith("+") and path:
            out.setdefault(path, []).append((line, text[1:]))
            line += 1
    return out


def normalize(data: str) -> list[tuple[int, str]]:
    """The release 1 review's rule: whitespace collapsed; short, import, comment and brace-only lines dropped."""
    out = []
    for no, line in enumerate(data.split("\n"), 1):
        s = re.sub(r"\s+", " ", line.strip())
        if len(s) >= 4 and not s.startswith(("import ", "//", "*", "/*", "export {", "}")) and s not in ("{", "})", ");"):
            out.append((no, s))
    return out


def scope_flags(root, sl, log, at_base, head_files, match, out) -> list[tuple]:
    globs = [g for t in sl["tasks"] for g in t["globs"]]
    out += [f"  breadth: {t['id']} `{g}` matches {sum(match(p, [g]) for p in head_files)} files at HEAD"
            for t in sl["tasks"] for g in t["globs"]]
    flags = []
    for p in sorted({p for _, _, paths, _ in log for p in paths if not p.startswith(RECORDS)}):
        if not match(p, globs):
            task = next(tid for _, _, paths, tid in log if p in paths)
            flags.append((1, "new" if p not in at_base else "outside", task, f"{p} is under no task glob of the slice"))
    return flags


def dependency_flags(root, sl, log, at_base, test, match, items) -> tuple[list[tuple], list[tuple]]:
    flags, logs, base = [], [], sl["base"]
    named = " ".join(f"{i.get('criterion', '')} {i.get('test', '')} {' '.join(i.get('inputs', []))}" for i in items)
    ref = fd.reference(root)
    ref_obj = load_json(fd.read(Path(root, ref, "package.json"))) if ref != "none" else None
    ref_deps = {n for m in RUNTIME + ("devDependencies",) for n in (ref_obj or {}).get(m) or {}}
    for p in sorted({p for _, _, paths, _ in log for p in paths}):
        name, task = p.rsplit("/", 1)[-1], next(tid for _, _, paths, tid in log if p in paths)
        if name != "package.json" and name != "fusebase.json" and not fnmatch.fnmatchcase(name, "tsconfig*.json"):
            continue
        new, old = load_json(fd.git(root, "show", f"HEAD:{p}")), load_json(fd.git(root, "show", f"{base}:{p}")) or {}
        if new is None:
            continue
        sink = logs if p not in at_base else flags  # a file the slice created: its keys are logged (scaffold)
        if name == "package.json":
            had = {n for m in RUNTIME + ("devDependencies",) for n in old.get(m) or {}}
            for dep, spec in {n: s for m in RUNTIME for n, s in (new.get(m) or {}).items()}.items():
                if dep not in had and not str(spec).startswith(INTERNAL):
                    if not re.search(rf"(?<![\w@/-]){re.escape(dep)}(?![\w/-])", named):
                        flags.append((2, "dep", task, f"{p}: {dep}, named by no item of the slice"))
                    if ref_obj is not None and dep not in ref_deps:
                        flags.append((2, "dep-ref", task, f"{p}: {dep}, not in the reference {ref}"))
            logs += [(2, "dep-dev", task, f"{p}: {d}") for d in (new.get("devDependencies") or {}) if d not in had]
            top = {k for k in new if k not in RUNTIME + ("devDependencies", "scripts")}
            sink += [(2, "cfg", task, f"{p}: {k}") for k in sorted(top - set(old))]
        else:
            sink += [(2, "cfg", task, f"{p}: {k}") for k in sorted(keys(new) - keys(old))]
    readers: dict[str, set[str]] = {}
    for sha, _, _, _ in log:
        for p, lines in added_lines(root, "show", "--format=", sha).items():
            for _, text in lines if p.endswith(CODE) else ():
                for m in ENV_RE.finditer(text):
                    readers.setdefault(next(g for g in m.groups() if g), set()).add(p)
    for var, paths in sorted(readers.items()):
        if var not in ENV_BUILTINS and not fd.git(root, "grep", "-l", "-w", "-F", var, base, "--"):
            task = next((tid for _, _, ps, tid in log if paths & set(ps)), "-")
            only_tests = all(match(p, test) for p in paths)
            (logs if only_tests else flags).append((2, "env", task, f"{var}, read in {', '.join(sorted(paths))}"))
    return flags, logs


def budget_flags(root, sl, log, test, match, slice_id) -> tuple[list[tuple], list[tuple]]:
    ret, why = fd.returns(root, slice_id)
    if ret is None:
        return [], [(3, "budget", "-", f"not computed: {why}")]
    flags, logs = [], []
    started, finished = fd.stamp(ret.get("started")), fd.stamp(ret.get("finished"))
    stamps = fd.git(root, "show", "-s", "--format=%H %ct", *[c[0] for c in log]).split() if log else []
    when, first = {sha: float(ct) for sha, ct in zip(stamps[::2], stamps[1::2])}, {}
    for sha, _, _, tid in log:
        first.setdefault(tid, when.get(sha))
    prev = started
    for t in sorted(sl["tasks"], key=lambda t: first.get(t["id"]) or float("inf")):
        end = first.get(t["id"]) or finished
        if t["minutes"] and prev and end and (end - prev) / 60 > BUDGET_X * t["minutes"]:
            flags.append((3, "minutes", t["id"], f"{(end - prev) / 60:.0f} min before its first commit, over "
                                                 f"{BUDGET_X}x {t['minutes']}m"))
        prev = first.get(t["id"]) or prev
        paths = {p for _, _, ps, tid in log if tid == t["id"] for p in ps if not p.startswith(RECORDS)}
        tests = {p for p in paths if match(p, test)}
        if t["files"] is not None and len(paths - tests) > BUDGET_X * t["files"]:
            flags.append((3, "files", t["id"], f"{len(paths - tests)} files, over {BUDGET_X}x {t['files']}f "
                                               f"(test paths apart: {len(tests)})"))
    calls = ret.get("tool_calls")
    before = calls.get("before_first_work") if isinstance(calls, dict) else None
    spans = calls.get("between_commits", []) if isinstance(calls, dict) else [calls] if not log else []
    if isinstance(before, int) and before > ORIENTATION_CALLS:
        flags.append((3, "before-work-calls", "-", f"{before} calls before first work, over {ORIENTATION_CALLS}"))
    flags += [(3, "no-commit-calls", "-", f"{n} calls with no commit, over {NO_COMMIT_CALLS}")
              for n in spans if isinstance(n, int) and n > NO_COMMIT_CALLS]
    beats = [b for b in reader.heartbeats(root) if started and finished and started <= b[1] <= finished + 60]
    logs += [(3, "repeat", "-", f"command sha256 {h[:12]} {n} times in flight (UNCALIBRATED: logged)")
             for h, n in Counter(b[2] for b in beats).items() if n >= reader.REPEATS]
    return flags, logs


def duplicate_flags(root, base, log, head_files, vendored) -> list[tuple]:
    def outside(p: str) -> bool:
        parts = p.split("/")
        return p.endswith(CODE) and not SKIP_DIRS & set(parts[:-1]) and not set(vendored) & set(parts)
    window, index, lines = DUP_LINES + 1, {}, {}
    for p in filter(outside, head_files):
        try:
            lines[p] = normalize((root / p).read_text(encoding="utf-8", errors="replace"))
        except OSError:
            continue
        for i in range(len(lines[p]) - window + 1):
            index.setdefault(hash(tuple(s for _, s in lines[p][i:i + window])), []).append((p, lines[p][i][0]))
    owner = {}
    for _, _, paths, tid in log:
        for p in filter(outside, paths):
            owner.setdefault(p, tid)
    flags, added = [], added_lines(root, "diff", base, "HEAD", "--", *owner) if owner else {}
    for p, rows in sorted(added.items()):
        ln, hits, new, tid = lines.get(p, []), [], {no for no, _ in rows}, owner.get(p, "-")
        for i in range(len(ln) - window + 1):
            if any(no in new for no, _ in ln[i:i + window]) and len(index[hash(tuple(s for _, s in ln[i:i + window]))]) > 1:
                hits.append(i)
        while hits:
            run = next((k for k in range(len(hits)) if hits[k] != hits[0] + k), len(hits))
            spots = index[hash(tuple(s for _, s in ln[hits[0]:hits[0] + window]))]
            other = next(f"{q}:{n}" for q, n in spots if (q, n) != (p, ln[hits[0]][0]))
            flags.append((4, "dup", tid, f"{p}:{ln[hits[0]][0]} repeats {other}, {run + window - 1} lines"))
            hits = hits[run:]
    return flags


def write_flags(root: Path, slice_id: str, flags: list[tuple]) -> list[tuple]:
    path = root / "state/flags" / f"{slice_id}.tsv"
    try:
        kept = {r.split("\t")[0]: r.split("\t")[4] for r in path.read_text("utf-8").splitlines()[1:] if r.count("\t") >= 4}
    except OSError:
        kept = {}
    rows = []
    for check, kind, task, evidence in flags:
        clean = re.sub(r"\s+", " ", evidence)
        fid = f"{kind}-{hashlib.sha256(f'{task}|{clean}'.encode()).hexdigest()[:8]}"
        rows.append((fid, str(check), task, clean, kept.get(fid, "")))
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "".join("\t".join(r) + "\n" for r in [("id", "check", "task", "evidence", "ruling"), *rows])
    path.write_text(text, encoding="utf-8", newline="\n")
    return rows


def run(root: Path, slice_id: str) -> tuple[int, list[str]]:
    sl = fd.phases(root).get(slice_id)
    if sl is None:
        return 2, [f"checks {slice_id}: no such slice in {fd.PHASES}"]
    pol, match, log = fd.policy(root), fd.globber(), fd.slice_log(root, sl)
    test, base = fd.tier(pol, "test"), sl["base"] or ""
    at_base = set(fd.git(root, "ls-tree", "-r", "--name-only", base).splitlines()) if log else set()
    head_files = fd.git(root, "ls-tree", "-r", "--name-only", "HEAD").splitlines()
    known = fd.backlog(fd.read(root / fd.BACKLOG))[0]
    items = [known[t["item"]] for t in sl["tasks"] if t["item"] in known]
    trivial = fd.trivial(log, match, fd.tier(pol))
    out = [f"checks {slice_id}: {len(log)} commits since {base[:12] or 'no base'}; trivial tier: "
           f"{'yes (no flag 1 or 4, no rubric)' if trivial else 'no'}"]
    flags = [] if trivial else scope_flags(root, sl, log, at_base, head_files, match, out)
    dep_flags, logs = dependency_flags(root, sl, log, at_base, test, match, items) if log else ([], [])
    budget, budget_logs = budget_flags(root, sl, log, test, match, slice_id)
    flags += dep_flags + budget + ([] if trivial else duplicate_flags(root, base, log, head_files, pol.get("vendored_paths") or []))
    rows = write_flags(root, slice_id, flags)
    out += [f"  FLAG {fid} check {check} {task}: {evidence}" + (f" [{ruling}]" if ruling else "")
            for fid, check, task, evidence, ruling in rows]
    out += [f"  LOG {kind} check {check} {task}: {ev}" for check, kind, task, ev in logs + budget_logs]
    out.append(f"CHECKS: {len(rows)} flags in state/flags/{slice_id}.tsv, {len(logs + budget_logs)} logged")
    return 0, out


def precision(root: Path, slice_id: str | None) -> list[str]:
    files = [root / "state/flags" / f"{slice_id}.tsv"] if slice_id else sorted((root / "state/flags").glob("*.tsv"))
    counts: dict[str, Counter] = {}
    for f in files:
        for row in (f.read_text("utf-8").splitlines()[1:] if f.is_file() else []):
            cells = row.split("\t") + [""] * 5
            counts.setdefault(cells[1], Counter())[cells[4].strip() or "open"] += 1
    out = []
    for check, c in sorted(counts.items()):
        ruled = c["upheld"] + c["rejected"]
        share = f"{100 * c['upheld'] / ruled:.0f}%" if ruled else "n/a"
        out.append(f"check {check}: {c['upheld']} upheld, {c['rejected']} rejected, {c['open']} open, precision {share}")
    return out or ["no flags"]


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="checks.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("slice", nargs="?")
    ap.add_argument("--precision", action="store_true", help="upheld / (upheld + rejected) per check")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args(argv)
    if args.precision:
        print("\n".join(precision(args.root.resolve(), args.slice)))
        return 0
    if not args.slice:
        ap.error("a slice id, or --precision")
    rc, lines = run(args.root.resolve(), args.slice)
    print("\n".join(lines))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
