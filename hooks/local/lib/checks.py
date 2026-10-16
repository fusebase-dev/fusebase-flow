#!/usr/bin/env python3
"""Flow checks --retro: flag 2 (dependency, config, env) and flag 4 (duplicate blocks) per commit, written as one TSV.

Stdlib Python 3.10+ and the git binary. Exit 0 wrote the TSV; 2 usage; 3 no data or environment; 4 internal (no TSV).
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
import tempfile
import time
import traceback
from array import array

from checks_git import Commit, CatFile, Fail, Git, ls_tree, read_log  # sibling module in hooks/local/lib

DUP_OVER_LINES = 20
DUP_OVER_PROVENANCE = "owner seed 2026-10-15"
MAX_BLOB_BYTES = 1048576
MAX_BLOB_PROVENANCE = "definition 2026-10-15"
SKIP_DIRS = frozenset(("node_modules", "dist", ".vite", "coverage"))
CODE_EXTS = (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".css", ".scss", ".py", ".sh", ".sql", ".vue", ".svelte")
RUNTIME_MAPS = ("dependencies", "peerDependencies", "optionalDependencies")
DEP_MAPS = RUNTIME_MAPS + ("devDependencies",)
INTERNAL_SPECS = ("workspace:", "file:", "link:")
ENV_BUILTINS = frozenset("NODE_ENV MODE DEV PROD SSR BASE_URL CI".split())
COLUMNS = ("id", "check", "kind", "level", "commit", "task", "path", "name", "lines", "named", "ruling", "note")
KIND_ORDER = {"dep": 0, "dep-dev": 1, "cfg": 2, "env": 3, "dup": 4}
EXIT_LABEL = {2: "usage", 3: "no-data", 4: "internal"}

WS_RE = re.compile(r"\s+")
ENV_RE = re.compile(rb"process\.env\.([A-Z_][A-Z0-9_]*)\b"
                    rb"|process\.env\[\s*[\"']([A-Z_][A-Z0-9_]*)[\"']\s*\]"
                    rb"|import\.meta\.env\.([A-Z_][A-Z0-9_]*)\b"
                    rb"|Deno\.env\.get\(\s*[\"']([A-Z_][A-Z0-9_]*)[\"']\s*\)"
                    rb"|os\.environ\[\s*[\"']([A-Z_][A-Z0-9_]*)[\"']\s*\]"
                    rb"|os\.environ\.get\(\s*[\"']([A-Z_][A-Z0-9_]*)[\"']"
                    rb"|os\.getenv\(\s*[\"']([A-Z_][A-Z0-9_]*)[\"']")
ENVX_RE = re.compile(rb"^[ \t]*(?:export[ \t]+)?([A-Z_][A-Z0-9_]*)[ \t]*=", re.M)
# Group 1 is a whole JSON string, so comment-like text and commas inside strings are kept as they are.
JSONC_COMMENT_RE = re.compile(r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/', re.S)
JSONC_COMMA_RE = re.compile(r'("(?:\\.|[^"\\])*")|,(?=\s*[}\]])')

V, SK, CODE, INC, PKG, CFG, ENVX, JSONC = 1, 2, 4, 8, 16, 32, 64, 128
OUT = V | SK


def glob_match(path: str, patterns) -> bool:
    return any(fnmatch.fnmatch(path, pat) or _glob_starstar(path, pat) for pat in patterns)


# TRIPWIRE: copied from hooks/shared/path_policy.py:56,67-72 (never imported: PyYAML); keep in parity, fixture R1.
def _glob_starstar(path: str, pattern: str) -> bool:
    if "**" not in pattern:
        return False
    parts = pattern.split("**")
    if len(parts) != 2:
        return False
    head, tail = parts
    if head and not path.startswith(head.rstrip("/")):
        return False
    if tail and not path.endswith(tail.lstrip("/")):
        return False
    return True


# TRIPWIRE: verbatim rule of the release 1 review script's norm_lines (code_redundancy.py), so counts stay
# comparable; lines split on "\n" only, as git numbers them. Fixture R1 holds the parity.
def normalize(data: bytes) -> list:
    out = []
    for no, line in enumerate(data.decode("utf-8", "replace").split("\n"), 1):
        s = WS_RE.sub(" ", line.strip())
        if len(s) < 4 or s.startswith(("import ", "//", "*", "/*", "export {", "}")) or s in ("{", "})", ");", "),"):
            continue
        out.append((no, s))
    return out


class Scope:
    """Path classification bits, memoized: the same paths recur in every derived tree."""

    def __init__(self, vendored, include):
        self.vendored, self.include, self.memo = list(vendored), list(include), {}

    def __call__(self, path: str) -> int:
        k = self.memo.get(path)
        if k is None:
            base = path.rsplit("/", 1)[-1]
            k = ((V if glob_match(path, self.vendored) else 0)
                 | (SK if SKIP_DIRS.intersection(path.split("/")[:-1]) else 0)
                 | (CODE if path.endswith(CODE_EXTS) else 0)
                 | (INC if not self.include or glob_match(path, self.include) else 0)
                 | (PKG if base == "package.json" else 0)
                 | (CFG if base == "fusebase.json" else 0)
                 | (CFG | JSONC if fnmatch.fnmatchcase(base, "tsconfig*.json") else 0)
                 | (ENVX if fnmatch.fnmatchcase(base, ".env*.example") else 0))
            self.memo[path] = k
        return k


def env_matches(data: bytes, envx: bool) -> list:
    out = []
    for rx in (ENV_RE, ENVX_RE) if envx else (ENV_RE,):
        if rx is ENV_RE and b"env" not in data:
            continue
        line, pos = 1, 0
        for m in rx.finditer(data):
            line += data.count(b"\n", pos, m.start())
            pos = m.start()
            out.append((line, m.group(m.lastindex).decode("ascii")))
    return out


def _strings_only(m) -> str:
    return m.group(1) if m.group(1) is not None else ""


def parse_json(data: bytes, jsonc: bool = False):
    """A JSON object, or None. jsonc (tsconfig only) also accepts // and /* */ comments and trailing commas."""
    try:
        obj = json.loads(data)
    except (ValueError, RecursionError):
        if not jsonc:
            return None
        try:
            text = JSONC_COMMENT_RE.sub(_strings_only, data.decode("utf-8-sig"))
            obj = json.loads(JSONC_COMMA_RE.sub(_strings_only, text))
        except (ValueError, RecursionError):
            return None
    return obj if isinstance(obj, dict) else None


def pkg_summary(obj: dict):
    maps = {m: obj[m] for m in DEP_MAPS if isinstance(obj.get(m), dict)}
    name = obj.get("name") if isinstance(obj.get("name"), str) else None
    return maps, name, frozenset(k for k in obj if k not in DEP_MAPS and k != "scripts")


def key_paths(obj: dict) -> frozenset:
    keys = set()
    for k, v in obj.items():
        keys.add(k)
        if isinstance(v, dict):
            keys.update(k + "." + k2 for k2 in v)
    return frozenset(keys)


class Blobs:
    def __init__(self):
        self.lines, self.env, self.pkg, self.cfg, self.bad, self.skipped = {}, {}, {}, {}, set(), 0


def wanted_blobs(commits: list, base_trees: dict, scope: Scope):
    """Every blob of a non-vendored path, with the OR of its path bits; skip-directory-only blobs are counted."""
    want, skipdir = {}, set()

    def note(p, sha):
        k = scope(p)
        if k & V:
            return
        if k & SK:
            skipdir.add(sha)
        else:
            want[sha] = want.get(sha, 0) | k

    for tree in base_trees.values():
        for p, sha in tree.items():
            note(p, sha)
    for c in commits:
        if len(c.parents) <= 1:
            for mode, sha, st, p in c.entries:
                if st != "D" and mode.startswith("100"):
                    note(p, sha)
    return want, len(skipdir.difference(want))


def read_blobs(git: Git, want: dict, max_bytes: int, window: int) -> Blobs:
    """Pass B: each distinct blob read once; per-line hashes, env names and manifest summaries cached by sha."""
    b = Blobs()
    cat = CatFile(git)
    try:
        for sha in sorted(want):
            k = want[sha]
            data = cat.get(sha, max_bytes)
            if data is None or b"\0" in data[:8000]:
                b.skipped += 1
                continue
            matches = env_matches(data, bool(k & ENVX))
            if matches:
                b.env[sha] = matches
            if k & CODE:
                norm = normalize(data)
                if len(norm) >= window:
                    b.lines[sha] = (array("q", [hash(s) for _, s in norm]), array("i", [n for n, _ in norm]))
            if k & (PKG | CFG):
                obj = parse_json(data, bool(k & JSONC))
                if obj is None:
                    b.bad.add(sha)
                    continue
                if k & PKG:
                    b.pkg[sha] = pkg_summary(obj)
                if k & CFG:
                    b.cfg[sha] = key_paths(obj)
    finally:
        cat.close()
    return b


def added_windows(ln, ranges: list, window: int) -> list:
    starts, run, j = [], 0, 0
    for i, n in enumerate(ln):
        while j < len(ranges) and ranges[j][1] < n:
            j += 1
        run = run + 1 if j < len(ranges) and ranges[j][0] <= n else 0
        if run >= window:
            starts.append(i - window + 1)
    return starts


# TRIPWIRE: hash() is randomized per process. Window hashes stay in memory and never order output; R13 reruns
# under two hash seeds and compares bytes.
def build_index(commits: list, b: Blobs, scope: Scope, window: int) -> dict:
    """Pass B2: wanted windows (all lines added) first, then one sweep of every indexed blob for those windows."""
    wanted, width = set(), 8 * window
    for c in commits:
        if len(c.parents) > 1:
            continue
        for mode, sha, st, p in c.entries:
            ranges = c.added.get(p)
            if not ranges or st == "D" or sha not in b.lines or not scope(p) & CODE:
                continue
            hs, ln = b.lines[sha]
            starts = added_windows(ln, ranges, window)
            if starts:
                buf = hs.tobytes()
                c.wanted[p] = [(i, hash(buf[8 * i:8 * i + width])) for i in starts]
                wanted.update(h for _, h in c.wanted[p])
    index = {}
    if wanted:
        for sha, (hs, _) in b.lines.items():
            buf = hs.tobytes()
            for i in range(len(hs) - window + 1):
                h = hash(buf[8 * i:8 * i + width])
                if h in wanted:
                    index.setdefault(h, {}).setdefault(sha, []).append(i)
    return index


def dep_names(tree: dict, b: Blobs, scope: Scope) -> set:
    names = set()
    for p, sha in tree.items():
        if sha in b.pkg and scope(p) & (PKG | OUT) == PKG:
            for m in b.pkg[sha][0].values():
                names.update(m)
    return names


def env_names(tree: dict, b: Blobs, scope: Scope) -> set:
    names = set()
    for p, sha in tree.items():
        if sha in b.env and not scope(p) & OUT:
            names.update(n for _, n in b.env[sha])
    return names


def manifest_diff(c: Commit, ptree: dict, b: Blobs, scope: Scope):
    """Flag 2 parent side: dependency candidates and new config key paths. Unparsed manifests invent nothing."""
    deps, cfg, union = [], [], None
    for mode, sha, st, p in c.entries:
        k = scope(p)
        if k & OUT or st == "D" or not mode.startswith("100") or not k & (PKG | CFG):
            continue
        old = ptree.get(p)
        if k & PKG and sha in b.pkg and (old is None or old in b.pkg):
            maps, _, top = b.pkg[sha]
            cfg += [(p, key) for key in top - (b.pkg[old][2] if old else frozenset())]
            if union is None:
                union = dep_names(ptree, b, scope)
            runtime = {n: v for m in RUNTIME_MAPS for n, v in maps.get(m, {}).items()}
            dev = {n: v for n, v in maps.get("devDependencies", {}).items() if n not in runtime}
            for kind, names in (("dep", runtime), ("dep-dev", dev)):
                deps += [(p, kind, n) for n, spec in names.items() if n not in union
                         and not (isinstance(spec, str) and spec.startswith(INTERNAL_SPECS))]
        if k & CFG and sha in b.cfg and (old is None or old in b.cfg):
            cfg += [(p, key) for key in b.cfg[sha] - (b.cfg[old] if old else frozenset())]
    return deps, cfg


def env_candidates(c: Commit, b: Blobs, scope: Scope) -> dict:
    found = {}
    for mode, sha, st, p in c.entries:
        ranges, matches = c.added.get(p), b.env.get(sha)
        if not ranges or not matches or st == "D":
            continue
        for line, name in matches:
            if name not in ENV_BUILTINS and any(lo <= line <= hi for lo, hi in ranges):
                if name not in found or p < found[name]:
                    found[name] = p
    return found


def dup_blocks(c: Commit, tree: dict, b: Blobs, index: dict, scope: Scope, window: int) -> list:
    """Flag 4 against tree(C): a wanted window is duplicated when its occurrences over code paths sum to 2+."""
    rel = set()
    for w in c.wanted.values():
        for _, h in w:
            rel.update(index[h])
    occ = {}
    for p, sha in tree.items():
        if sha in rel and scope(p) & (CODE | OUT) == CODE:
            occ.setdefault(sha, []).append(p)
    out, seen = [], set()
    for p in sorted(c.wanted):
        ln, first = b.lines[tree[p]][1], dict(c.wanted[p])
        dup = [i for i, h in c.wanted[p] if sum(len(occ.get(s, ())) * len(js) for s, js in index[h].items()) >= 2]
        for start, run in _runs(dup):
            h0, length = first[start], run + window - 1
            if (h0, length) in seen:
                continue
            seen.add((h0, length))
            here = ln[start]
            spots = sorted((q, b.lines[s][1][j]) for s, js in index[h0].items() for q in occ.get(s, ()) for j in js)
            spots = [x for x in spots if x != (p, here)]
            other = next((x for x in spots if x[0] != p), spots[0] if spots else None)
            out.append((p, here, f"{other[0]}:{other[1]}" if other else "", length))
    return out


def _runs(idx: list):
    runs = []
    for i in idx:
        if runs and runs[-1][0] + runs[-1][1] == i:
            runs[-1][1] += 1
        else:
            runs.append([i, 1])
    return runs


def walk(commits: list, base_trees: dict, b: Blobs, index: dict, scope: Scope, window: int) -> tuple:
    """Pass C: derive tree(C) per commit (parents first) and evaluate flags 2 and 4."""
    rows, merges, kids, trees = [], 0, {}, {}
    for c in commits:
        if len(c.parents) == 1:
            kids[c.parents[0]] = kids.get(c.parents[0], 0) + 1
    for idx, c in enumerate(commits):
        if len(c.parents) > 1:
            merges += 1
            tree = base_trees.pop(c.sha)
            if kids.get(c.sha):
                trees[c.sha] = tree
            continue
        par = c.parents[0] if c.parents else None
        if par is None:
            ptree, take = {}, True
        else:
            src = trees if par in trees else base_trees
            ptree = src[par]
            kids[par] -= 1
            take = kids[par] == 0
            if take:
                del src[par]
        # TRIPWIRE: when this is the parent's last child its tree is mutated in place; read parent-side facts first.
        deps, cfg = manifest_diff(c, ptree, b, scope)
        env = env_candidates(c, b, scope)
        if env:
            known = env_names(ptree, b, scope)
            env = {n: p for n, p in env.items() if n not in known}
        tree = ptree if take else dict(ptree)
        for mode, sha, st, p in c.entries:
            if st == "D" or not mode.startswith("100"):
                tree.pop(p, None)
            else:
                tree[p] = sha
        if kids.get(c.sha):
            trees[c.sha] = tree
        if deps:
            internal = {b.pkg[s][1] for p, s in tree.items() if s in b.pkg and scope(p) & (PKG | OUT) == PKG}
            rows += [(idx, 2, p, KIND_ORDER[kind], 0, n, kind, "flag" if kind == "dep" else "log", "")
                     for p, kind, n in deps if n not in internal]
        rows += [(idx, 2, p, KIND_ORDER["cfg"], 0, key, "cfg", "flag", "") for p, key in cfg]
        rows += [(idx, 2, p, KIND_ORDER["env"], 0, n, "env", "flag", "") for n, p in env.items()]
        if c.wanted:
            rows += [(idx, 4, p, KIND_ORDER["dup"], here, name, "dup", "flag", length)
                     for p, here, name, length in dup_blocks(c, tree, b, index, scope, window)]
    return rows, merges


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")


def check_args(a) -> str:
    if not a.retro or a.retro.startswith("-"):
        raise Fail(2, "RANGE must be given and must not start with '-'")
    if a.dup_over < 1 or a.max_blob_bytes < 0:
        raise Fail(2, "--dup-over must be >= 1 and --max-blob-bytes >= 0")
    out = os.path.abspath(a.out)
    if os.path.isdir(out):
        raise Fail(2, "--out is a directory")
    try:
        os.makedirs(os.path.dirname(out), exist_ok=True)
    except OSError:
        raise Fail(2, "--out directory cannot be created") from None
    return out


def resolve(a, git: Git) -> int:
    if a.repo is None:
        rc, top = git.run("rev-parse", "--show-toplevel")
        if rc != 0:
            raise Fail(3, "the cwd is not inside a git work tree")
        git.repo = top.decode("utf-8", "surrogateescape").strip()
    if git.run("rev-parse", "--git-dir")[0] != 0:
        raise Fail(3, "--repo is not a git repository")
    rc, count = git.run("rev-list", "--count", a.retro, "--")
    if rc != 0:
        raise Fail(3, "RANGE does not resolve")
    if not count.strip().isdigit():
        raise Fail(4, "rev-list count parse")
    if int(count) == 0:
        raise Fail(3, "RANGE resolves to 0 commits")
    return int(count)


def render(a, commits: list, count: int, merges: int, rows: list, skipped: int, unparsed: int) -> bytes:
    dup_prov = DUP_OVER_PROVENANCE if a.dup_over == DUP_OVER_LINES else "override --dup-over"
    blob_prov = MAX_BLOB_PROVENANCE if a.max_blob_bytes == MAX_BLOB_BYTES else "override --max-blob-bytes"
    head = [("flow-flags", "v1"), ("mode", "retro"), ("range", esc(a.retro)), ("tip", commits[-1].sha),
            ("commits", count), ("merges_skipped", merges), ("scanned", count - merges),
            ("vendored", esc(";".join(a.vendored)) or "none"), ("include", esc(";".join(a.include)) or "*"),
            ("reference", "none"), ("const", f"DUP_OVER_LINES\t{a.dup_over}\t{dup_prov}"),
            ("const", f"MAX_BLOB_BYTES\t{a.max_blob_bytes}\t{blob_prov}"),
            ("skipped_blobs", skipped), ("unparsed_manifests", unparsed)]
    lines = [f"#{k}\t{v}" for k, v in head] + ["\t".join(COLUMNS)]
    counters = {}
    for idx, check, path, _, line, name, kind, level, length in sorted(rows, key=lambda r: r[:6]):
        sha = commits[idx].sha
        k = counters[(idx, check)] = counters.get((idx, check), 0) + 1
        lines.append("\t".join((f"F{check}-{sha[:7]}-{k}", str(check), kind, level, sha, commits[idx].task,
                                esc(path), esc(name), str(length), "n/a", "", f"line={line}" if check == 4 else "")))
    return ("\n".join(lines) + "\n").encode("utf-8", "surrogateescape")


# TRIPWIRE: stdout carries numbers and fixed labels only (kinds and levels are constants); never paths or names.
def summary(out: str, count: int, merges: int, rows: list, skipped: int, unparsed: int, elapsed: float) -> None:
    by_kind = {}
    for r in rows:
        by_kind[(r[6], r[7])] = by_kind.get((r[6], r[7]), 0) + 1
    print("checks --retro")
    print(f"commits {count}")
    print(f"merges_skipped {merges}")
    print(f"scanned {count - merges}")
    print(f"rows {len(rows)}")
    for kind, level in sorted(by_kind, key=lambda x: (KIND_ORDER[x[0]], x[1])):
        print(f"rows {kind} {level} {by_kind[(kind, level)]}")
    print(f"skipped_blobs {skipped}")
    print(f"unparsed_manifests {unparsed}")
    print("dep-ref: not run (no reference manifest)")
    print(f"elapsed_s {elapsed:.1f}")
    print(f"out {out}")


def run(a, t0: float) -> int:
    out = check_args(a)
    scope, window = Scope(a.vendored, a.include), a.dup_over + 1
    git = Git(a.repo or ".")
    try:
        count = resolve(a, git)
        commits = read_log(git, a.retro, lambda p: scope(p) & (OUT | INC) == INC and bool(scope(p) & (CODE | ENVX)))
        if len(commits) != count:
            raise Fail(4, "log stream commit count differs from rev-list --count")
        in_range, base_trees = {c.sha for c in commits}, {}
        for c in commits:
            need = c.sha if len(c.parents) > 1 else (c.parents[0] if c.parents and c.parents[0] not in in_range else None)
            if need and need not in base_trees:
                base_trees[need] = ls_tree(git, need)
        want, skipdir = wanted_blobs(commits, base_trees, scope)
        b = read_blobs(git, want, a.max_blob_bytes, window)
        # TRIPWIRE: the watchdog can fire during a child's shutdown without raising anything; check before leaving
        # the git phase so a stall never publishes a TSV (R19 cat-file-shutdown).
        git.check()
    except Exception:
        git.check()  # a child killed by the watchdog surfaces as a parse error; report the stall instead
        raise
    finally:
        git.close()
    skipped, unparsed = b.skipped + skipdir, len(b.bad)
    index = build_index(commits, b, scope, window)
    rows, merges = walk(commits, base_trees, b, index, scope, window)
    payload = render(a, commits, count, merges, rows, skipped, unparsed)
    fd, tmp = tempfile.mkstemp(prefix=".checks-retro-", suffix=".tmp", dir=os.path.dirname(out))
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(payload)
        os.replace(tmp, out)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    summary(out, count, merges, rows, skipped, unparsed, time.monotonic() - t0)
    return 0


class Parser(argparse.ArgumentParser):
    # TRIPWIRE: argparse's own messages echo the supplied values, secrets included; print a fixed label only (R17).
    def error(self, message):
        self.exit(2, "checks: usage: bad, missing or unknown argument (see --help)\n")


def main(argv=None) -> int:
    t0 = time.monotonic()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    ap = Parser(prog="checks.py", description=__doc__.strip().split("\n")[0])
    ap.add_argument("--retro", required=True, metavar="RANGE", help="one git rev-list range: A..B, or B for all ancestors")
    ap.add_argument("--out", required=True, metavar="FILE", help="TSV path, written atomically (required)")
    ap.add_argument("--repo", metavar="PATH", help="target repository (default: git toplevel of the cwd)")
    ap.add_argument("--vendored", action="append", default=[], metavar="GLOB",
                    help="excluded from both sides of flags 2 and 4 (repeatable)")
    ap.add_argument("--include", action="append", default=[], metavar="GLOB",
                    help="flag 4 and env scan new code only under these globs (repeatable; default every path)")
    ap.add_argument("--dup-over", type=int, default=DUP_OVER_LINES, metavar="N",
                    help=f"flag blocks over N normalized lines (default {DUP_OVER_LINES}; calibration reruns only)")
    ap.add_argument("--max-blob-bytes", type=int, default=MAX_BLOB_BYTES, metavar="N",
                    help=f"skip and count larger blobs (default {MAX_BLOB_BYTES})")
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return e.code if isinstance(e.code, int) else 2
    try:
        return run(a, t0)
    except Fail as e:
        print(f"checks: {EXIT_LABEL[e.code]}: {e.label}", file=sys.stderr)
        return e.code
    # TRIPWIRE: never print str(e); decode and JSON errors can carry blob bytes. Type and line number only.
    except Exception as e:  # noqa: BLE001 - exit 4 contract
        frame = traceback.extract_tb(e.__traceback__)[-1]
        print(f"checks: internal: {type(e).__name__} at {os.path.basename(frame.filename)}:{frame.lineno}",
              file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main())
