"""W5 — silent push-through, reported as a COVERAGE BASELINE, never as findings.

Codex review established that generic swallowed-error detection cannot be made
low-false-positive: this repo intentionally fails open/closed in many places
(best-effort cleanup, guarded probes, fallbacks). So W5 emits NO confirmed
findings in v1. Instead it produces a measured, labelled baseline (count + a
capped sample) the operator reviews — surfacing the north-star signal
("silently push through without telling anyone") without crying wolf. Precise
fail-open-on-a-trust-path detection is noted as future work in the rule catalog.

Suppress a known-intentional swallow from the baseline with an inline
`find-wasted-code: ignore W5 — <reason>` comment.
"""
from __future__ import annotations

import ast
import re

from .constants import W5, strip_heredocs

_IGNORE_RE = re.compile(r"find-wasted-code:\s*ignore\s+W5")
_SH_SWALLOW_RE = re.compile(r"2>\s*/dev/null|\|\|\s*true\b|\|\|\s*return\s+0\b|\|\|\s*:")
_BENIGN_CONST = (ast.Constant,)


def _has_diagnostic(node):
    """True if the handler body raises or emits any diagnostic (log/print/warn)."""
    for n in ast.walk(node):
        if isinstance(n, ast.Raise):
            return True
        if isinstance(n, ast.Call):
            f = n.func
            name = ""
            if isinstance(f, ast.Attribute):
                name = f.attr
            elif isinstance(f, ast.Name):
                name = f.id
            if name and re.search(r"log|warn|error|print|critical|exception|stderr|write", name, re.I):
                return True
    return False


def _trivial_body(handler):
    for stmt in handler.body:
        if isinstance(stmt, ast.Pass):
            continue
        if isinstance(stmt, ast.Continue):
            continue
        if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant):
            continue  # bare literal / Ellipsis / docstring
        if isinstance(stmt, ast.Return) and (stmt.value is None
                                             or isinstance(stmt.value, _BENIGN_CONST)):
            continue
        return False
    return True


def _is_broad(handler):
    t = handler.type
    if t is None:
        return True                       # bare except:
    names = []
    if isinstance(t, ast.Name):
        names = [t.id]
    elif isinstance(t, ast.Tuple):
        names = [e.id for e in t.elts if isinstance(e, ast.Name)]
    return any(n in ("Exception", "BaseException") for n in names)


def baseline_py(cov, path, text):
    cov.rules_run.add(W5)
    lines = text.split("\n")
    try:
        tree = ast.parse(text)
    except SyntaxError:
        cov.unresolve(W5, path, 1, "python did not parse (W5 baseline skipped)")
        return
    for node in ast.walk(tree):
        if not isinstance(node, ast.ExceptHandler):
            continue
        if not _is_broad(node) or not _trivial_body(node):
            continue
        # ignore-directive on the handler's line range?
        end = getattr(node, "end_lineno", node.lineno) or node.lineno
        span = "\n".join(lines[node.lineno - 1:end])
        if _IGNORE_RE.search(span):
            cov.dismiss(W5, path, node.lineno)
            continue
        if _has_diagnostic(node):
            continue
        cov.w5_py.append((path, node.lineno))


def baseline_sh(cov, path, text):
    cov.rules_run.add(W5)
    lines = strip_heredocs(text.split("\n"))
    for i, line in enumerate(lines, 1):
        code = line.split("#", 1)[0]      # drop trailing comment (approx; good enough for a baseline)
        if line.lstrip().startswith("#"):
            continue
        if _IGNORE_RE.search(line):
            cov.dismiss(W5, path, i)
            continue
        if _SH_SWALLOW_RE.search(code):
            cov.w5_sh.append((path, i))
