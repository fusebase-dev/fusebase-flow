#!/usr/bin/env python3
"""FR-13 validator-free tier (workflows/git-discipline.md § Validator-free paths).

Exit: 10 = skip lint/typecheck; 0 = run them (reason printed); any other rc = the caller runs them.
TRIPWIRE: 10 is the ONLY skip signal. Never map 0, 1, an exception or a SystemExit to a skip.
"""
from __future__ import annotations

import importlib.util
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

DECLARATION = "policies/validator-free-paths.yml"
SKIP_RC = 10
MAX_BLOB = 64 * 1024
MAX_PATTERNS = 500
MAX_PATTERN_LEN = 300
TAG = "[fusebase-flow:pre-commit]"

TIER_INPUTS = frozenset({
    DECLARATION,
    "hooks/git/pre-commit",
    "hooks/local/lib/precommit-validator-reuse.sh",
    "hooks/local/lib/validator_tier.py",
    "hooks/shared/module_size.py",
})
# TRIPWIRE: not exhaustive (lint commands are opaque); projects must not declare what their validators read.
VALIDATOR_CONFIG_GLOBS = (
    "**/package.json", "**/package-lock.json", "**/npm-shrinkwrap.json", "**/pnpm-lock.yaml",
    "**/pnpm-workspace.yaml", "**/yarn.lock", "**/bun.lock", "**/bun.lockb",
    "**/tsconfig.json", "**/tsconfig.*.json", "**/jsconfig.json", "**/jsconfig.*.json",
    "**/eslint.config.*", "**/.eslintrc", "**/.eslintrc.*", "**/.eslintignore",
    "**/.prettierrc", "**/.prettierrc.*", "**/prettier.config.*", "**/.prettierignore",
    "**/.markdownlint*", "**/cspell.json", "**/.cspell.json", "**/cspell.config.*",
    "**/cspell.yaml", "**/cspell.yml", "**/.stylelintrc", "**/.stylelintrc.*",
    "**/stylelint.config.*", "**/biome.json", "**/biome.jsonc", "**/deno.json", "**/deno.jsonc",
    "**/.editorconfig", "**/.gitignore", "**/pyproject.toml", "**/setup.cfg", "**/tox.ini",
    "**/.flake8", "**/mypy.ini", "**/.mypy.ini", "**/ruff.toml", "**/.ruff.toml",
    "**/.pylintrc", "**/pylintrc",
)
BREADTH_PROBES = (
    "package.json", "apps/web/package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock",
    "tsconfig.json", "apps/web/tsconfig.app.json", "jsconfig.json", "eslint.config.js",
    "eslint.config.mjs", ".eslintrc.json", ".eslintrc.cjs", ".prettierrc", "prettier.config.js",
    ".prettierignore", ".markdownlint.json", "cspell.json", ".stylelintrc.json", "biome.json",
    "deno.json", ".editorconfig", ".gitignore", "pyproject.toml", "setup.cfg", "ruff.toml",
    "mypy.ini",
)
_BAD_CHARS = frozenset("\\[]{}")
_CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")


class Verdict(NamedTuple):
    skip: bool
    reason: str


def load_glob(root: Path):
    # TRIPWIRE: NOT path_policy's matcher - fnmatch over-matches, which is fail-OPEN for a skip list.
    # TRIPWIRE: callers use .fullmatch() only; the regex ends in "$", which .match() accepts before a trailing "\n".
    spec = importlib.util.spec_from_file_location("_ff_tier_module_size",
                                                  Path(root) / "hooks/shared/module_size.py")
    if spec is None or spec.loader is None:
        raise ImportError("hooks/shared/module_size.py not loadable")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod._glob_to_regex


def pattern_problem(p) -> str:
    if not isinstance(p, str):
        return "not a string"
    if not p or p != p.strip():
        return "empty or padded with whitespace"
    if len(p) > MAX_PATTERN_LEN:
        return "longer than %d characters" % MAX_PATTERN_LEN
    if _CONTROL.search(p):
        return "control character"
    if p[0] in "/!":
        return "must be repo-relative (no leading / or !)"
    if any(c in _BAD_CHARS for c in p):
        return "\\ [ ] { } are not supported"
    if p.endswith("/"):
        return "write a directory as dir/**"
    for seg in p.split("/"):
        if seg in ("", ".", ".."):
            return "empty, . or .. path segment"
        if "**" in seg and seg != "**":
            return "** must be a whole path segment"
    return ""


def _restore_site_packages() -> None:
    # TRIPWIRE: the hook runs python3 -S with PYTHONNOUSERSITE=1; a user-site PyYAML is reachable only via this.
    import site
    for get in (getattr(site, "getsitepackages", None), getattr(site, "getusersitepackages", None)):
        try:
            got = get() if get else []
        except Exception:
            continue
        for p in ([got] if isinstance(got, str) else got):
            if p and p not in sys.path:
                sys.path.append(p)


def parse_declaration(blob: bytes, compile_glob):
    if len(blob) > MAX_BLOB:
        return None, "larger than %d bytes" % MAX_BLOB
    try:
        text = blob.decode("utf-8-sig")
    except UnicodeDecodeError:
        return None, "not UTF-8"
    try:
        _restore_site_packages()
        import yaml
    except Exception as e:
        return None, "PyYAML unavailable (%s)" % e.__class__.__name__
    try:
        doc = yaml.safe_load(text)
    except Exception:
        return None, "not valid YAML"
    if not isinstance(doc, dict) or set(doc) != {"schema_version", "validator_free_paths"}:
        return None, "needs exactly the keys schema_version and validator_free_paths"
    if type(doc["schema_version"]) is not int or doc["schema_version"] != 1:
        return None, "schema_version must be 1"
    items = doc["validator_free_paths"]
    if items is None:
        items = []
    if not isinstance(items, list):
        return None, "validator_free_paths must be a list"
    if not items:
        return [], "declares no paths"
    if len(items) > MAX_PATTERNS:
        return None, "more than %d patterns" % MAX_PATTERNS
    out = []
    for raw in items:
        why = pattern_problem(raw)
        if why:
            return None, "pattern %r rejected: %s" % (raw, why)
        rx = compile_glob(raw)
        hit = next((probe for probe in BREADTH_PROBES if rx.fullmatch(probe)), None)
        if hit:
            return None, "pattern %r covers validator config %r" % (raw, hit)
        out.append((raw, rx))
    return out, ""


def decide(staged, patterns, compile_glob) -> Verdict:
    if not staged:
        return Verdict(False, "nothing staged")
    for path in staged:
        if _CONTROL.search(path):
            return Verdict(False, "staged path %r contains a control character" % path)
    config = [compile_glob(g) for g in VALIDATOR_CONFIG_GLOBS]
    for path in staged:
        if path in TIER_INPUTS or any(r.fullmatch(path) for r in config):
            return Verdict(False, "%s is a validator config or tier input" % path)
    undeclared = [p for p in staged if not any(rx.fullmatch(p) for _, rx in patterns)]
    if undeclared:
        more = " (+%d more)" % (len(undeclared) - 1) if len(undeclared) > 1 else ""
        return Verdict(False, "%s is not declared validator-free%s" % (undeclared[0], more))
    return Verdict(True, "all %d staged path(s) are declared validator-free" % len(staged))


def _git(root: Path, *args: str):
    # TRIPWIRE: inherit the hook env - GIT_INDEX_FILE is the index that `commit -a` / `commit <paths>` will commit.
    proc = subprocess.run(["git", *args], cwd=str(root), capture_output=True)
    return proc.returncode, proc.stdout


def read_declaration(root: Path):
    # TRIPWIRE: HEAD only - reading the index or working tree would let a staged edit self-qualify.
    rc, out = _git(root, "ls-tree", "-z", "HEAD", "--", DECLARATION)
    if rc != 0:
        rc2, _ = _git(root, "rev-parse", "--verify", "--quiet", "HEAD^{commit}")
        return None, ("no commit yet (unborn HEAD)" if rc2 == 1
                      else "could not read HEAD (git rc=%d)" % rc)
    if not out:
        return None, "no declaration (%s absent at HEAD)" % DECLARATION
    meta, _, _ = out.split(b"\0", 1)[0].partition(b"\t")
    parts = meta.split(b" ")
    if len(parts) != 3 or parts[1] != b"blob" or parts[0] not in (b"100644", b"100755"):
        return None, "%s at HEAD is not a regular file" % DECLARATION
    oid = parts[2].decode("ascii", "replace")
    rc, blob = _git(root, "cat-file", "blob", oid)
    if rc != 0:
        return None, "could not read %s at HEAD (git rc=%d)" % (DECLARATION, rc)
    return blob, oid[:7]


def staged_paths(root: Path):
    # TRIPWIRE: no --diff-filter, keep --no-renames and --ignore-submodules=none: deletions, both rename sides and gitlink bumps count.
    rc, out = _git(root, "diff", "--cached", "--name-only", "--no-renames", "-z",
                   "--ignore-submodules=none", "--no-ext-diff", "--no-textconv")
    if rc != 0:
        return None, "could not list staged paths (git rc=%d)" % rc
    try:
        return [n.decode("utf-8") for n in out.split(b"\0") if n], ""
    except UnicodeDecodeError:
        return None, "a staged path is not UTF-8"


def evaluate(root: Path) -> Verdict:
    blob, info = read_declaration(root)
    if blob is None:
        return Verdict(False, info)
    compile_glob = load_glob(root)
    patterns, why = parse_declaration(blob, compile_glob)
    if patterns is None:
        return Verdict(False, "%s@%s is invalid: %s" % (DECLARATION, info, why))
    if not patterns:
        return Verdict(False, "%s@%s %s" % (DECLARATION, info, why))
    staged, why = staged_paths(root)
    if staged is None:
        return Verdict(False, why)
    v = decide(staged, patterns, compile_glob)
    return Verdict(v.skip, "%s (%s@%s)" % (v.reason, DECLARATION, info) if v.skip else v.reason)


def main(argv) -> int:
    try:
        sys.stderr.reconfigure(errors="backslashreplace")
    except Exception:
        pass
    root = Path(argv[argv.index("--root") + 1]) if "--root" in argv[:-1] else Path.cwd()
    try:
        v = evaluate(root)
    except BaseException as e:  # TRIPWIRE: a SystemExit raised by loaded code must become the full tier
        if isinstance(e, KeyboardInterrupt):
            raise
        v = Verdict(False, "tier check error (%s)" % e.__class__.__name__)
    if v.skip:
        print("%s tier=validator-free: lint/typecheck skipped - %s" % (TAG, v.reason), file=sys.stderr)
        return SKIP_RC
    print("%s tier=full: lint/typecheck run - %s" % (TAG, v.reason), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
