"""checks-retro fixtures for hooks/local/lib/checks.py --retro.

Usage: python hooks/tests/fixtures/checks_retro.py <worktree-root> <tmpdir>. Prints PASS/FAIL per case and exits
with the failure count. Every repository is built by ONE `git fast-import`; no per-commit process.
"""
import contextlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import types

root, temp = map(Path, sys.argv[1:3])
sys.path.insert(0, str(root / "hooks/local/lib"))
import checks  # noqa: E402
import checks_git  # noqa: E402

TOOL = root / "hooks/local/lib/checks.py"
T0 = time.monotonic()
temp.mkdir(parents=True, exist_ok=True)
WORK = Path(tempfile.mkdtemp(prefix="checks-retro-", dir=temp))
REPO = WORK / "repo"
passed = failed = 0


def case(name, fn):
    global passed, failed
    try:
        errs = fn()
    except Exception as e:  # noqa: BLE001 - a crashing case is a FAIL row, never an abort
        errs = [f"exception {type(e).__name__}: {e}"]
    if errs:
        failed += 1
        print(f"FAIL: checks-retro {name}: {'; '.join(errs)}")
    else:
        passed += 1
        print(f"PASS: checks-retro {name}")


def expect(errs, cond, label):
    if not cond:
        errs.append(label)


# --- fast-import builder ---------------------------------------------------------------------------------------

def _quote(path):
    return b'"' + path.encode("utf-8").replace(b"\\", b"\\\\").replace(b'"', b'\\"') + b'"'


def _data(body):
    return b"data %d\n" % len(body) + body + b"\n"


class Stream:
    def __init__(self):
        self.parts, self.mark, self.heads, self.clock = [], 0, {}, 1700000000

    def commit(self, branch, msg, files=None, deletes=(), merge=None, start=None):
        self.mark += 1
        self.clock += 1
        parent = start if start is not None else self.heads.get(branch)
        out = [f"commit refs/heads/{branch}\nmark :{self.mark}\n".encode(),
               f"committer Fixture <fixture@example.com> {self.clock} +0000\n".encode(), _data(msg.encode())]
        if parent:
            out.append(f"from :{parent}\n".encode())
        if merge:
            out.append(f"merge :{merge}\n".encode())
        out += [b"D " + _quote(p) + b"\n" for p in deletes]
        out += [b"M 100644 inline " + _quote(p) + b"\n" + _data(body) for p, body in (files or {}).items()]
        self.parts += out
        self.heads[branch] = self.mark
        return self.mark

    def build(self, repo):
        subprocess.run(["git", "init", "-q", "--initial-branch=main", str(repo)], check=True)
        subprocess.run(["git", "-C", str(repo), "fast-import", "--quiet"], input=b"".join(self.parts), check=True)


def block(tag, n):
    return [f"const {tag}_{i} = compute('{tag}', {i});" for i in range(n)]


def text(lines):
    return ("\n".join(lines) + "\n").encode("utf-8")


def js(obj):
    return (json.dumps(obj, indent=2) + "\n").encode("utf-8")


# --- tool runner -----------------------------------------------------------------------------------------------

RUNS = [0]


class Result:
    def __init__(self, rc, out, stdout, stderr):
        self.rc, self.out, self.stdout, self.stderr = rc, out, stdout, stderr
        self.raw = out.read_bytes() if out.exists() else None
        self.head, self.rows, self.bad_rows = {}, [], 0
        if self.raw is not None:
            cols = None
            for line in self.raw.decode("utf-8").split("\n")[:-1]:
                if line.startswith("#"):
                    k, _, v = line[1:].partition("\t")
                    self.head.setdefault(k, []).append(v)
                elif cols is None:
                    cols = line.split("\t")
                else:
                    fields = line.split("\t")
                    self.bad_rows += len(fields) != len(cols)
                    self.rows.append(dict(zip(cols, fields)))

    def task(self, task, check=None):
        return [r for r in self.rows if r["task"] == task and (check is None or r["check"] == str(check))]


def tool(rng, *extra, repo=None):
    RUNS[0] += 1
    out = WORK / f"run{RUNS[0]}" / "out.tsv"
    argv = ["--retro", rng, "--repo", str(repo or REPO), "--out", str(out), *extra]
    so, se = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(so), contextlib.redirect_stderr(se):
        rc = checks.main(argv)
    return Result(rc, out, so.getvalue(), se.getvalue())


def sole_dup(errs, res, task, path, name, lines, line=1):
    rows = res.task(task, 4)
    expect(errs, len(rows) == 1, f"{task}: {len(rows)} dup rows, want 1")
    if rows:
        r = rows[0]
        got = (r["kind"], r["level"], r["path"], r["name"], r["lines"], r["note"], r["named"], r["ruling"])
        want = ("dup", "flag", path, name, str(lines), f"line={line}", "n/a", "")
        expect(errs, got == want, f"{task}: row {got} != {want}")
        expect(errs, re.fullmatch(r"F4-[0-9a-f]{7}-1", r["id"]) and r["commit"].startswith(r["id"][3:10]),
               f"{task}: id {r['id']} does not match commit")


# --- scenarios ---------------------------------------------------------------------------------------------------

S = Stream()
# R2: B's 25 normalized lines equal A's; a different raw layout gives a different blob.
S.commit("r2", "T21 add a", {"src/a.ts": text(["// header", "import x from 'y';", ""] + block("r2", 25) + ["}"])})
S.commit("r2", "T22 add b", {"src/b.ts": text(block("r2", 25)[:10] + [""] + block("r2", 25)[10:])})
# R3: a 20-line copy (r3a) and a 21-line copy (r3b), each framed by unrelated lines.
for br, n in (("r3a", 20), ("r3b", 21)):
    S.commit(br, "T31 base", {"src/base.ts": text(block(br + "pre", 3) + block(br + "blk", n) + block(br + "post", 3))})
    S.commit(br, "T32 copy", {"src/copy.ts": text(block(br + "cpre", 2) + block(br + "blk", n) + block(br + "cpost", 2))})
# R4: move, then delete-and-add rename, then a control copy.
mv = block("mv", 30)
S.commit("r4", "T41 base", {"src/a.ts": text(block("a4pre", 5) + mv + block("a4post", 5))})
S.commit("r4", "T42 move", {"src/a.ts": text(block("a4pre", 5) + block("a4post", 5)), "src/b.ts": text(mv)})
S.commit("r4", "T43 rename", {"src/c.ts": text(mv)}, deletes=["src/b.ts"])
S.commit("r4", "T44 control copy", {"src/d.ts": text(block("d4", 2) + mv)})
# R5: vendored copies on both sides: a copy INTO the vendored path, and a copy whose only twin is vendored.
S.commit("r5", "T51 lib", {"packages/x/src/a.ts": text(block("v5", 25))})
S.commit("r5", "T52 sync", {"apps/x/src/_web/a.ts": text(["// generated"] + block("v5", 25))})
S.commit("r5", "T53 sync", {"apps/x/src/_web/b.ts": text(["// generated"] + block("w5", 25))})
S.commit("r5", "T54 lib", {"packages/x/src/b.ts": text(block("w5", 25))})
# R6: two identical new files in one commit.
S.commit("r6", "T61 twins", {"src/x.ts": text(block("r6", 25)), "src/y.ts": text(block("r6", 25))})
# R7: a duplicated 40-line block, then a 2-line edit inside the copy.
r7 = block("r7", 40)
S.commit("r7", "T71 base", {"src/a.ts": text(r7)})
S.commit("r7", "T72 copy", {"src/b.ts": text(r7)})
S.commit("r7", "T73 edit", {"src/b.ts": text(r7[:10] + ["const edited_1 = 1;", "const edited_2 = 2;"] + r7[12:])})
# R8: dependency diff.
pa = {"name": "a", "dependencies": {"react": "^18.0.0"}}
pb = {"name": "b", "dependencies": {"react": "^18.0.0"}}
S.commit("r8", "T81 scaffold", {"apps/a/package.json": js(pa),
                                "packages/lib/package.json": js({"name": "@x/lib", "version": "1.0.0"})})
pa["dependencies"]["zod"] = "^3.0.0"
S.commit("r8", "T82 zod", {"apps/a/package.json": js(pa)})
S.commit("r8", "T83 app b", {"apps/b/package.json": js(pb)})
pa["devDependencies"] = {"vitest": "^1.0.0"}
S.commit("r8", "T84 vitest", {"apps/a/package.json": js(pa)})
pb["dependencies"]["@x/lib"] = "workspace:*"
S.commit("r8", "T85 workspace", {"apps/b/package.json": js(pb)})
pb["dependencies"]["@x/util"] = "^1.0.0"
S.commit("r8", "T86 internal by name", {"apps/b/package.json": js(pb),
                                        "packages/util/package.json": js({"name": "@x/util"})})
pa["dependencies"]["react"] = "^18.3.0"
S.commit("r8", "T87 bump", {"apps/a/package.json": js(pa)})
# R10: env names; the secret value, subject marker and added-line marker must never be written. The "++ b/..."
# line becomes a "+++ b/..." hunk-body line, and the spaced non-ASCII path gets git's trailing-tab header form.
S.commit("r10", "T101 config", {"src/config.ts": text(["export const existing = process.env.EXISTING_NAME;"])})
S.commit("r10", "T102 SUBJECT-MARKER-q7", {"src/my äpp.ts": text([
    "++ b/src/decoy.ts", "const fixtureAddedLineMarker = 1;", 'process.env.API_TOKEN = "s3cr3t-fixture-value";',
    "const e = process.env.EXISTING_NAME;", "if (process.env.NODE_ENV) { run(); }"])})
# R11: config keys, reordering, invalid JSON; plus a root tsconfig at depth 2.
S.commit("r11", "T111 cfg", {"fusebase.json": b'{"a": 1, "b": {"c": 2}}\n'})
S.commit("r11", "T112 new key", {"fusebase.json": b'{"a": 1, "b": {"c": 2}, "e": 4}\n'})
S.commit("r11", "T113 reorder", {"fusebase.json": b'{"e": 4, "b": {"c": 2}, "a": 1}\n'})
S.commit("r11", "T114 invalid", {"apps/x/tsconfig.json": b'{"compilerOptions": {"strict": true,,}}\n'})
S.commit("r11", "T115 tsconfig", {"tsconfig.json": b'{"compilerOptions": {"strict": true}}\n'})
S.commit("r11", "T116 depth two", {"tsconfig.json": b'{"compilerOptions": {"strict": true, "noEmit": true}}\n'})
# R12: a merge whose resolution blob exists in neither parent; a later copy must see it.
c1 = S.commit("r12", "T121 base", {"src/a.ts": text(block("v1", 5))})
side = S.commit("r12side", "T122 side", {"src/a.ts": text(block("v2", 5))}, start=c1)
S.commit("r12", "T123 main", {"src/a.ts": text(block("v3", 5))})
S.commit("r12", "T124 merge", {"src/a.ts": text(block("v4pre", 2) + block("res", 25))}, merge=side)
S.commit("r12", "T125 copy", {"src/b.ts": text(block("res", 25))})
# R18: an edit whose added-line ranges differ between diff algorithms (myers: longest added run 11, histogram: 22).
r18_old = ["if (ok) return;", "const o10_1 = 1;", "return value;", "return null;", "const x = 1;", "const o10_5 = 5;"]
r18_copy = (["if (ok) return;", "const c10_1 = 1;", "const c10_2 = 2;", "return value;", "return null;",
             "const c10_5 = 5;", "const c10_6 = 6;", "return value;", "if (ok) return;", "const c10_9 = 9;",
             "if (ok) return;", "return value;"] + [f"const c10_{i} = {i};" for i in range(12, 16)]
            + ["const x = 1;"] + [f"const c10_{i} = {i};" for i in range(17, 22)])
S.commit("r18", "T181 base", {"src/a.ts": text(r18_copy), "src/b.ts": text(r18_old)})
S.commit("r18", "T182 edit", {"src/b.ts": text(r18_old[:1] + r18_copy + ["const o10_1 = 1;", "return value;",
                                                                        "return null;", "const edit10 = 9;",
                                                                        "const o10_5 = 5;"])})
# R20: a blob over --max-blob-bytes 3000 is skipped; small blobs around it still flag.
S.commit("r20", "T201 big", {"src/big.ts": text(block("big", 25) + block("pad", 150)), "src/a.ts": text(block("x20", 25))})
S.commit("r20", "T202 copies", {"src/b.ts": text(block("x20", 25)), "src/c.ts": text(block("big", 25))})
# R21: tsconfig JSONC (comments, trailing commas, comment-like text inside strings); fusebase.json stays strict.
TSC = ('{\n  // compiler options\n  "compilerOptions": {\n    /* strict mode */ "strict": true,\n'
       '    "x//y": "keep // this, }",\n    "p/*q*/r": "a/*b*/c",\n    "empty": "",\n    "trail": ["a", "b",],%s\n'
       '  },\n}\n')
S.commit("r21", "T211 jsonc", {"apps/web/tsconfig.json": (TSC % "").encode()})
S.commit("r21", "T212 new key", {"apps/web/tsconfig.json": (TSC % '\n    "noEmit": true,').encode()})
S.commit("r21", "T213 strict", {"fusebase.json": b'{\n  // not accepted here\n  "a": 1\n}\n'})


def r13_history():
    """200 commits on main: every 50th plants a duplicate (the first seed is in the root), every 100th a dep."""
    pkg, logs = {"name": "big", "version": "1.0.0", "dependencies": {}}, {}
    for k in range(1, 201):
        files = {}
        logs.setdefault(k % 7, []).append(f"export const step_{k} = {k};")
        files[f"src/log_{k % 7}.ts"] = text(logs[k % 7])
        if k == 1:
            files["package.json"] = js(pkg)
        for j in range(1, 5):
            seed = block(f"seed{j}", 25)
            if k == (1 if j == 1 else 50 * j - 25):
                files[f"src/seed_{j}.ts"] = text(seed)
            if k == 50 * j:
                files[f"src/copy_{j}.ts"] = text(seed if j % 2 == 0 else ["// copy"] + seed + [f"export const tail_{j} = 1;"])
        if k % 100 == 0:
            pkg["dependencies"][f"dep-{k // 100}"] = "^1.0.0"
            files["package.json"] = js(pkg)
        S.commit("main", f"T{1000 + k} step", files)


r13_history()


# --- cases -------------------------------------------------------------------------------------------------------

def norm_lines(p):
    out = []
    for l in open(p, encoding="utf-8", errors="replace"):
        s = re.sub(r"\s+", " ", l.strip())
        if len(s) < 4 or s.startswith(("import ", "//", "*", "/*", "export {", "}")) or s in ("{", "})", ");", "),"):
            continue
        out.append(s)
    return out


NORM_TABLE = ["", "abc", "  abcd  ", "import x from 'y';", "// comment line", " * doc line", "/* block */",
              "export { a, b };", "}", "})", ");", "),", "{", "  const   a  =  1;  ", "\tfoo\t\tbar baz",
              "export const x = 1;", "} else {", "**bold text", "a  b　c", "if (a) { return b; }"]
# Expected values generated from hooks/shared/path_policy.py:_matches_any on 2026-10-16 (lowercase, "/" only, so
# fnmatch's Windows case folding cannot change them).
GLOB_TABLE = [
    ("apps/x/src/_web/a.ts", "apps/*/src/_web/**", True), ("apps/x/backend/src/_core/b.ts", "apps/*/backend/src/_core/**", True),
    ("apps/x/src/web/a.ts", "apps/*/src/_web/**", False), ("packages/p/a.ts", "apps/**", False),
    ("apps/a.ts", "apps/**", True), ("appsx/a.ts", "apps/**", True), ("src/deep/x.test.ts", "**/*.test.ts", True),
    ("x.test.ts", "**/*.test.ts", False), ("a/b/c.md", "a/*", True), ("docs/sub/x.md", "docs/*.md", True),
    ("a/b", "a/b", True), ("a/bc", "a/b?", True), ("a/b/c", "a/[bc]/c", True), ("lib/x.ts", "**/lib/**", False),
    ("src/lib/x.ts", "**/lib/**", True), ("src/x.ts", "src/**/x.ts", True),
    ("tsconfig.json", "**/tsconfig*.json", False), ("apps/a/tsconfig.app.json", "**/tsconfig*.json", True)]


def r1():
    errs = []
    data = ("\n".join(NORM_TABLE) + "\n").encode("utf-8")
    ref_file = WORK / "norm.txt"
    ref_file.write_bytes(data)
    got = checks.normalize(data)
    expect(errs, len(NORM_TABLE) == 20, "table is not 20 lines")
    expect(errs, [s for _, s in got] == norm_lines(ref_file), f"normalize {[s for _, s in got]} != reference")
    expect(errs, all(checks.WS_RE.sub(" ", NORM_TABLE[n - 1].strip()) == s for n, s in got), "raw line numbers")
    bad = [(p, g) for p, g, want in GLOB_TABLE if checks.glob_match(p, [g]) != want]
    expect(errs, not bad, f"glob parity {bad}")
    return errs


def r2():
    errs = []
    res = tool("r2")
    expect(errs, res.rc == 0 and len(res.rows) == 1 and not res.bad_rows, f"rc {res.rc} rows {len(res.rows)}")
    sole_dup(errs, res, "T22", "src/b.ts", "src/a.ts:4", 25)
    return errs


def r3():
    errs = []
    a, b, a10 = tool("r3a"), tool("r3b"), tool("r3a", "--dup-over", "10")
    expect(errs, a.rc == 0 and not a.rows, f"20 lines: rc {a.rc} rows {len(a.rows)}")
    expect(errs, len(b.rows) == 1, f"21 lines: {len(b.rows)} rows")
    sole_dup(errs, b, "T32", "src/copy.ts", "src/base.ts:4", 21, line=3)
    expect(errs, len(a10.rows) == 1, f"--dup-over 10: {len(a10.rows)} rows")
    sole_dup(errs, a10, "T32", "src/copy.ts", "src/base.ts:4", 20, line=3)
    expect(errs, a10.head.get("const", [""])[0].startswith("DUP_OVER_LINES\t10\t"), "header does not record 10")
    return errs


def r4():
    errs = []
    res = tool("r4")
    for t in ("T41", "T42", "T43"):
        expect(errs, not res.task(t), f"{t}: {len(res.task(t))} rows")
    sole_dup(errs, res, "T44", "src/d.ts", "src/c.ts:1", 30, line=3)
    return errs


def r5():
    errs = []
    vend, plain = tool("r5", "--vendored", "apps/*/src/_web/**"), tool("r5")
    expect(errs, vend.rc == 0 and not vend.rows, f"vendored: {len(vend.rows)} rows")
    expect(errs, vend.head.get("vendored") == ["apps/*/src/_web/**"], "header #vendored")
    expect(errs, len(plain.rows) == 2, f"plain: {len(plain.rows)} rows")
    sole_dup(errs, plain, "T52", "apps/x/src/_web/a.ts", "packages/x/src/a.ts:1", 25, line=2)
    sole_dup(errs, plain, "T54", "packages/x/src/b.ts", "apps/x/src/_web/b.ts:2", 25)
    inc = tool("r5", "--include", "packages/**")
    expect(errs, len(inc.rows) == 1 and inc.head.get("include") == ["packages/**"], f"--include: {len(inc.rows)} rows")
    sole_dup(errs, inc, "T54", "packages/x/src/b.ts", "apps/x/src/_web/b.ts:2", 25)
    return errs


def r6():
    errs = []
    res = tool("r6")
    expect(errs, len(res.rows) == 1, f"{len(res.rows)} rows")
    sole_dup(errs, res, "T61", "src/x.ts", "src/y.ts:1", 25)
    return errs


def r7():
    errs = []
    res = tool("r7")
    expect(errs, len(res.rows) == 1 and not res.task("T73"), f"rows {[(r['task'], r['lines']) for r in res.rows]}")
    sole_dup(errs, res, "T72", "src/b.ts", "src/a.ts:1", 40)
    return errs


def r8():
    errs = []
    res = tool("r8")
    deps = {t: [(r["kind"], r["name"], r["level"], r["path"]) for r in res.task(t, 2) if r["kind"].startswith("dep")]
            for t in ("T82", "T83", "T84", "T85", "T86", "T87")}
    want = {"T82": [("dep", "zod", "flag", "apps/a/package.json")], "T83": [],
            "T84": [("dep-dev", "vitest", "log", "apps/a/package.json")], "T85": [], "T86": [], "T87": []}
    expect(errs, deps == want, f"dep rows {deps}")
    expect(errs, res.head.get("reference") == ["none"], "header #reference")
    expect(errs, "dep-ref: not run (no reference manifest)" in res.stdout, "summary dep-ref line")
    expect(errs, not any(r["kind"] == "dep-ref" for r in res.rows), "dep-ref row written")
    return errs


def r10():
    errs = []
    res = tool("r10")
    rows = [(r["kind"], r["name"], r["level"], r["path"]) for r in res.task("T102")]
    expect(errs, rows == [("env", "API_TOKEN", "flag", "src/my äpp.ts")], f"T102 rows {rows}")
    blob = (res.raw or b"").decode("utf-8") + res.stdout + res.stderr
    for marker in ("s3cr3t-fixture-value", "SUBJECT-MARKER-q7", "fixtureAddedLineMarker"):
        expect(errs, marker not in blob, f"{marker} leaked")
    return errs


def r11():
    errs = []
    res = tool("r11")
    got = {t: [(r["kind"], r["path"], r["name"]) for r in res.task(t)] for t in ("T112", "T113", "T114", "T116")}
    want = {"T112": [("cfg", "fusebase.json", "e")], "T113": [], "T114": [],
            "T116": [("cfg", "tsconfig.json", "compilerOptions.noEmit")]}
    expect(errs, got == want, f"cfg rows {got}")
    expect(errs, res.head.get("unparsed_manifests") == ["1"], f"#unparsed_manifests {res.head.get('unparsed_manifests')}")
    return errs


def r12():
    errs = []
    res = tool("r12")
    h = {k: res.head.get(k) for k in ("commits", "merges_skipped", "scanned")}
    expect(errs, h == {"commits": ["5"], "merges_skipped": ["1"], "scanned": ["4"]}, f"header {h}")
    expect(errs, not res.task("T124"), "merge carries rows")
    expect(errs, len(res.rows) == 1, f"{len(res.rows)} rows")
    sole_dup(errs, res, "T125", "src/b.ts", "src/a.ts:3", 25)
    return errs


def r13():
    errs, outs = [], []
    for seed in ("1", "2"):
        out = WORK / f"r13-{seed}" / "out.tsv"
        start = time.monotonic()
        p = subprocess.run([sys.executable, str(TOOL), "--retro", "main", "--repo", str(REPO), "--out", str(out)],
                           capture_output=True, timeout=600, env={**os.environ, "PYTHONHASHSEED": seed})
        print(f"INFO: checks-retro R13 run hashseed={seed} rc={p.returncode} elapsed_s {time.monotonic() - start:.1f}")
        expect(errs, p.returncode == 0, f"seed {seed}: rc {p.returncode}")
        expect(errs, sorted(x.name for x in out.parent.iterdir()) == ["out.tsv"], f"seed {seed}: stray files")
        outs.append(Result(p.returncode, out, "", ""))
    a, b = outs
    kinds = [r["kind"] for r in a.rows]
    expect(errs, a.head.get("commits") == ["200"], f"#commits {a.head.get('commits')}")
    expect(errs, (kinds.count("dup"), kinds.count("dep"), len(kinds)) == (4, 2, 8), f"rows {kinds}")
    expect(errs, len({r["id"] for r in a.rows}) == len(a.rows) and not a.bad_rows, "ids not unique or bad rows")
    expect(errs, a.raw is not None and a.raw == b.raw, "rerun under another hash seed is not byte-identical")
    # A..B shape (spec 2.8): commit 50 copies seed_1, which only the boundary commit 49's ls-tree carries.
    part = tool("main~151..main")
    kinds = [r["kind"] for r in part.rows]
    expect(errs, part.head.get("commits") == ["151"], f"A..B #commits {part.head.get('commits')}")
    expect(errs, (kinds.count("dup"), kinds.count("dep"), len(kinds)) == (4, 2, 6), f"A..B rows {kinds}")
    return errs


class DesyncCatFile(checks.CatFile):
    def get(self, sha, limit):
        self.proc.stdin.write(b"HEAD\n")
        return super().get(sha, limit)


def r14():
    errs = []
    empty = tool("HEAD..HEAD")
    expect(errs, empty.rc == 3 and "0 commits" in empty.stderr and empty.raw is None, f"HEAD..HEAD rc {empty.rc}")
    unresolved = tool("no-such-ref")
    expect(errs, unresolved.rc == 3 and "does not resolve" in unresolved.stderr, f"no-such-ref rc {unresolved.rc}")
    p = subprocess.run([sys.executable, str(TOOL), "--retro", "-x", "--repo", str(REPO), "--out", str(WORK / "x.tsv")],
                       capture_output=True, timeout=600)
    expect(errs, p.returncode == 2, f"--retro -x rc {p.returncode}")
    se = io.StringIO()
    with contextlib.redirect_stderr(se):
        dash = checks.main(["--retro=-x", "--repo", str(REPO), "--out", str(WORK / "x.tsv")])
        no_out = checks.main(["--retro", "main", "--repo", str(REPO)])
    expect(errs, dash == 2 and "must not start with '-'" in se.getvalue(), f"--retro=-x rc {dash}")
    expect(errs, no_out == 2 and not (WORK / "x.tsv").exists(), f"missing --out rc {no_out}")
    norepo = WORK / "norepo"
    norepo.mkdir()
    saved = os.environ.get("GIT_CEILING_DIRECTORIES")
    os.environ["GIT_CEILING_DIRECTORIES"] = str(WORK)
    try:
        nr = tool("main", repo=norepo)
    finally:
        if saved is None:
            del os.environ["GIT_CEILING_DIRECTORIES"]
        else:
            os.environ["GIT_CEILING_DIRECTORIES"] = saved
    expect(errs, nr.rc == 3 and "not a git repository" in nr.stderr, f"non-repo rc {nr.rc}")
    real = checks.CatFile
    checks.CatFile = DesyncCatFile
    try:
        ds = tool("r2")
    finally:
        checks.CatFile = real
    expect(errs, ds.rc == 4 and "cat-file desync" in ds.stderr, f"desync rc {ds.rc}")
    expect(errs, ds.raw is None and not list(ds.out.parent.iterdir()), "desync left a TSV or temp file")
    return errs


def r17():
    """Argument errors exit 2 with a fixed label and never echo the supplied value."""
    errs = []
    base = ["--retro", "main", "--repo", str(REPO), "--out", str(WORK / "r17" / "out.tsv")]
    for i, extra in enumerate((["--bogus=MARK-unknown-k3"], ["MARK-positional-k4"], ["--dup-over", "MARK-int-k5"],
                               ["--max-blob-bytes=MARK-int-k6"])):
        so, se = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(so), contextlib.redirect_stderr(se):
            rc = checks.main(base + extra)
        said = so.getvalue() + se.getvalue()
        expect(errs, rc == 2 and "MARK-" not in said and "bad, missing or unknown argument" in said,
               f"in-process case {i}: rc {rc}, marker echoed {'MARK-' in said}")
    p = subprocess.run([sys.executable, str(TOOL), *base, "--dup-over", "MARK-proc-k7"], capture_output=True, timeout=600)
    expect(errs, p.returncode == 2 and b"MARK-" not in p.stdout + p.stderr, f"process: rc {p.returncode}")
    expect(errs, not (WORK / "r17").exists(), "an argument error created the output directory")
    return errs


HOSTILE = (b"[diff]\n\tnoprefix = true\n\talgorithm = histogram\n\tindentHeuristic = false\n[color]\n\tui = always\n"
           b"[core]\n\tquotepath = true\n[log]\n\tshowSignature = true\n\tshowRoot = false\n")


def r18():
    """A hostile user config (diff algorithm, prefixes, colour, quoting, root diff) leaves every TSV byte-identical."""
    errs = []
    branches = ("r18", "r10", "main")
    clean = {br: tool(br) for br in branches}
    cfg = REPO / ".git" / "config"
    saved = cfg.read_bytes()
    try:
        cfg.write_bytes(saved + HOSTILE)
        hostile = {br: tool(br) for br in branches}
        patch = [subprocess.run(["git", "-C", str(REPO), *pins, "log", "-p", "-U0", "--format=", "-1", "r18"],
                                capture_output=True, timeout=600).stdout for pins in ((), ("-c", "diff.algorithm=myers"))]
    finally:
        cfg.write_bytes(saved)
    for br in branches:
        expect(errs, clean[br].rc == 0 and clean[br].raw == hostile[br].raw, f"{br}: TSV differs under hostile config")
    expect(errs, b"\x1b[" in patch[0] and patch[0] != patch[1], "hostile config inactive or r18 not algorithm-sensitive")
    expect(errs, not clean["r18"].task("T182"), f"T182 rows {clean['r18'].task('T182')}")
    return errs


# Stage -> (replaced git subcommand, stand-in code run as `python -c CODE <repo> <answered-file>`).
# cat-file-shutdown proxies every request to a real cat-file, records how many it answered, then stalls at stdin EOF.
SHUTDOWN = WORK / "cat-file-shutdown-answered"
STUBS = {"rev-list": ("rev-list", "import time; time.sleep(120)"),
         "log": ("log", "import sys, time; sys.stdout.buffer.write(b'\\x1eC ' + b'a' * 40 + b' \\x1f\\x1f\\n'); "
                        "sys.stdout.flush(); time.sleep(120)"),
         "cat-file": ("cat-file", "import time; time.sleep(120)"),
         "cat-file-shutdown": ("cat-file", "\n".join((
             "import subprocess, sys, time",
             "real = subprocess.Popen(['git', '-C', sys.argv[1], 'cat-file', '--batch'], stdin=subprocess.PIPE,"
             " stdout=subprocess.PIPE)",
             "n = 0",
             "for line in sys.stdin.buffer:",
             "    real.stdin.write(line)",
             "    real.stdin.flush()",
             "    head = real.stdout.readline()",
             "    f = head.split()",
             "    sys.stdout.buffer.write(head + (real.stdout.read(int(f[2]) + 1) if len(f) == 3 else b''))",
             "    sys.stdout.buffer.flush()",
             "    n += 1",
             "real.stdin.close()",
             "real.wait()",
             "open(sys.argv[2], 'w').write(str(n))",
             "time.sleep(120)")))}


class StallGit(checks_git.Git):
    stage, stubs = None, []

    def argv(self, *args):
        cmd, code = STUBS[StallGit.stage]
        return [sys.executable, "-c", code, self.repo, str(SHUTDOWN)] if args[0] == cmd else super().argv(*args)

    def spawn(self, args, stdin=subprocess.DEVNULL):
        p = super().spawn(args, stdin)
        if args[0] == STUBS[StallGit.stage][0]:
            StallGit.stubs.append(p)
        return p


def r19():
    """A stalled git child (finite command, log stream, cat-file batch, cat-file shutdown after every answer) ends in
    a bounded exit 4 with the fixed message, and no TSV or temp file."""
    errs = []
    real_git, real_stall = checks.Git, checks_git.STALL_SECONDS
    checks.Git, checks_git.STALL_SECONDS = StallGit, 5
    try:
        for stage in STUBS:
            StallGit.stage, StallGit.stubs = stage, []
            start = time.monotonic()
            res = tool("r2")
            print(f"INFO: checks-retro R19 {stage} stall rc={res.rc} elapsed_s {time.monotonic() - start:.1f}")
            expect(errs, res.rc == 4 and "no progress for 5 s" in res.stderr, f"{stage}: rc {res.rc}")
            expect(errs, len(StallGit.stubs) == 1 and StallGit.stubs[0].poll() is not None,
                   f"{stage}: stub not spawned once, or still running")
            expect(errs, res.raw is None and not list(res.out.parent.iterdir()), f"{stage}: TSV or temp file left")
        answered = SHUTDOWN.read_text() if SHUTDOWN.exists() else "0"
        expect(errs, answered.isdigit() and int(answered) > 0,
               f"cat-file-shutdown: stand-in answered {answered} requests before its shutdown stall, want > 0")
    finally:
        checks.Git, checks_git.STALL_SECONDS = real_git, real_stall
        for p in StallGit.stubs:
            if p.poll() is None:
                p.kill()
    return errs


class CountingPipe(io.BytesIO):
    largest = 0

    def read(self, n=-1):
        CountingPipe.largest = max(CountingPipe.largest, n)
        return super().read(n)


def r20():
    """An oversized blob is drained in bounded chunks, counted as skipped, and the batch protocol stays in sync."""
    errs = []
    s1, s2, big = b"1" * 40, b"2" * 40, b"x" * (2 << 20)
    cat = checks_git.CatFile.__new__(checks_git.CatFile)
    cat.proc = types.SimpleNamespace(stdin=io.BytesIO(),
                                     stdout=CountingPipe(b"%s blob %d\n%s\n%s blob 3\nabc\n" % (s1, len(big), big, s2)))
    cat.tick = lambda: None
    first, second = cat.get(s1.decode(), 1024), cat.get(s2.decode(), 1024)
    expect(errs, first is None and second == b"abc", "oversized blob not skipped, or protocol out of sync")
    expect(errs, CountingPipe.largest <= checks_git.DRAIN_CHUNK, f"largest single read {CountingPipe.largest} bytes")
    res = tool("r20", "--max-blob-bytes", "3000")
    skipped = res.head.get("skipped_blobs")
    expect(errs, res.rc == 0 and skipped == ["1"] and len(res.rows) == 1, f"rc {res.rc} skipped {skipped} rows {len(res.rows)}")
    sole_dup(errs, res, "T202", "src/b.ts", "src/a.ts:1", 25)
    return errs


def r21():
    """tsconfig*.json accepts comments and trailing commas outside strings; other manifests stay strict JSON."""
    errs = []
    unit = checks.parse_json(b'{"a": "", "b": "//", /* c */ "c": [1,],}', True)
    expect(errs, unit == {"a": "", "b": "//", "c": [1]}, f"JSONC unit {unit}")
    expect(errs, checks.parse_json(b'{"a": 1, // c\n}') is None, "JSONC accepted without the tsconfig flag")
    res = tool("r21")
    names = sorted(r["name"] for r in res.task("T211"))
    want = sorted(["compilerOptions", "compilerOptions.strict", "compilerOptions.x//y", "compilerOptions.p/*q*/r",
                   "compilerOptions.empty", "compilerOptions.trail"])
    expect(errs, names == want, f"T211 names {names}")
    got = [(r["kind"], r["path"], r["name"]) for r in res.task("T212")]
    expect(errs, got == [("cfg", "apps/web/tsconfig.json", "compilerOptions.noEmit")], f"T212 rows {got}")
    expect(errs, not res.task("T213") and res.head.get("unparsed_manifests") == ["1"], "fusebase.json must stay strict")
    return errs


S.build(REPO)
for name, fn in (("R1", r1), ("R2", r2), ("R3", r3), ("R4", r4), ("R5", r5), ("R6", r6), ("R7", r7), ("R8", r8),
                 ("R10", r10), ("R11", r11), ("R12", r12), ("R13", r13), ("R14", r14), ("R17", r17), ("R18", r18),
                 ("R19", r19), ("R20", r20), ("R21", r21)):
    case(name, fn)
print(f"INFO: checks-retro passed={passed} failed={failed} elapsed_s {time.monotonic() - T0:.1f}")
sys.exit(failed)
