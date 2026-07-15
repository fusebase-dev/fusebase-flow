"""W2 — broken internal Markdown links (path + anchor).

Contract (locked against Codex review):
- Relative dest resolves against the SOURCE document's directory; `/x` from repo
  root; `#x` against the current document.
- Raw dest is split on the first literal `#` BEFORE percent-decoding.
- External schemes (http(s)/mailto/tel///) and placeholder dests are skipped.
- A missing PATH is `broken` (deterministic; directories count as existing).
- Anchor validation runs ONLY for Markdown targets (`code.py#L20` is a line ref,
  not a heading). A missing anchor is `broken` only when the target file is
  slug-confident; otherwise `inconclusive` — never a false broken-anchor claim.
"""
from __future__ import annotations

import posixpath
import re
import urllib.parse

from .constants import (
    W2, TIER_BROKEN, TIER_CANDIDATE, CONFIRMED, INCONCLUSIVE, SEV_MAJOR, SEV_MINOR,
    has_placeholder,
)
from .markdown import extract_links, Headings
from .model import Finding

_EXTERNAL_RE = re.compile(r"^(?:[a-z][a-z0-9+.\-]*:|//|#!|data:)", re.IGNORECASE)
_MD_EXT = (".md", ".markdown")
_LINE_ANCHOR_RE = re.compile(r"^L\d+(?:-L?\d+)?$")
_MAJOR_SURFACES = ("README.md", "AGENTS.md", "CLAUDE.md", "project-onboarding",
                   "docs/north-star", "onboard")


def _severity(path):
    return SEV_MAJOR if any(s in path for s in _MAJOR_SURFACES) else SEV_MINOR


def _resolve(src_path, raw_dest):
    """Return (target_or_None, fragment_or_None, kind) — kind in {self, file, skip}."""
    if raw_dest.startswith("#"):
        return None, urllib.parse.unquote(raw_dest[1:]), "self"
    if "#" in raw_dest:
        pathpart, frag = raw_dest.split("#", 1)
        frag = urllib.parse.unquote(frag)
    else:
        pathpart, frag = raw_dest, None
    pathpart = urllib.parse.unquote(pathpart)
    if pathpart == "":
        return None, frag, "self"
    if pathpart.startswith("/"):
        target = pathpart.lstrip("/")
    else:
        base = posixpath.dirname(src_path)
        target = posixpath.normpath(posixpath.join(base, pathpart))
    if target.startswith("..") or target == "." or target == "":
        return None, frag, "skip"        # escapes repo root — cannot resolve
    return target, frag, "file"


class _HeadingCache:
    def __init__(self, inv):
        self.inv = inv
        self._c = {}

    def get(self, rel, text=None):
        if rel in self._c:
            return self._c[rel]
        if text is None:
            text, note = self.inv.read_text(rel)
            if text is None:
                self._c[rel] = None
                return None
        h = Headings(text)
        self._c[rel] = h
        return h


def scan_w2(inv, cov, path, text, hcache):
    cov.rules_run.add(W2)
    links, _defs = extract_links(text)
    self_headings = None
    for lineno, dest, in_fence in links:
        if in_fence or not dest:
            continue
        if _EXTERNAL_RE.match(dest) or has_placeholder(dest):
            continue
        target, frag, kind = _resolve(path, dest)
        if kind == "skip":
            cov.unresolve(W2, path, lineno, "unresolvable dest: %s" % dest)
            continue
        if kind == "self":
            target = path
        else:
            # PATH existence.
            if not inv.exists(target):
                real = inv.case_mismatch(target)
                note = ("case-mismatch: tracked as %s" % real) if real else \
                    "link target does not exist"
                yield Finding(W2, TIER_BROKEN, CONFIRMED, _severity(path), path, lineno,
                              dest, "Fix the link path or restore the target.", note)
                continue
            if target in inv.dirs and target not in inv.files:
                # directory target — valid; anchors N/A.
                continue
        if not frag:
            continue
        # ANCHOR validation — Markdown targets only.
        if not target.lower().endswith(_MD_EXT):
            if _LINE_ANCHOR_RE.match(frag):
                continue                      # code.py#L20 line ref — valid
            cov.unresolve(W2, path, lineno, "non-markdown anchor not validated: %s" % dest)
            continue
        if kind == "self":
            if self_headings is None:
                self_headings = Headings(text)
            headings = self_headings
        else:
            headings = hcache.get(target)
        if headings is None:
            cov.unresolve(W2, path, lineno, "anchor target unreadable: %s" % dest)
            continue
        if headings.has_anchor(frag):
            continue
        if headings.confident:
            yield Finding(W2, TIER_BROKEN, CONFIRMED, _severity(path), path, lineno,
                          dest, "Fix the anchor to match an existing heading.",
                          "no heading in the target yields this anchor slug")
        else:
            yield Finding(W2, TIER_CANDIDATE, INCONCLUSIVE, SEV_MINOR, path, lineno,
                          dest, "Verify the anchor against the target's headings.",
                          "target has slug-ambiguous headings — verify manually")
