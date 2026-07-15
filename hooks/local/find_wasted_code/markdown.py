"""Deterministic Markdown helpers: fence tracking, GitHub heading slugs, links.

Conservative by design. Where GitHub's slug algorithm is ambiguous for a given
heading (code spans, HTML entities, emphasis, non-ASCII, raw HTML), the file is
marked NOT slug-confident, and a non-matching anchor is reported `inconclusive`
rather than `broken` — we never claim a broken anchor we cannot prove.
"""
from __future__ import annotations

import re

_FENCE_RE = re.compile(r"^(\s*)(`{3,}|~{3,})(.*)$")
_ATX_RE = re.compile(r"^(\s{0,3})(#{1,6})(\s+.*?|)\s*$")
_SETEXT_RE = re.compile(r"^(\s{0,3})(=+|-+)\s*$")
_ATX_CLOSE_RE = re.compile(r"\s+#+\s*$")
_HTML_ID_RE = re.compile(r"""(?:id|name)\s*=\s*["']([^"']+)["']""")


def iter_lines(text):
    """Yield (lineno, line, in_fence, info) — fenced code blocks flagged.

    Fence matching honours the CommonMark rule that a closing fence must use the
    same marker char and be at least as long as the opener.
    """
    in_fence = False
    fence_char = ""
    fence_len = 0
    info = ""
    for i, line in enumerate(text.split("\n"), 1):
        m = _FENCE_RE.match(line)
        if m:
            marker = m.group(2)
            if not in_fence:
                in_fence, fence_char, fence_len, info = True, marker[0], len(marker), m.group(3).strip()
                yield i, line, True, info
                continue
            elif marker[0] == fence_char and len(marker) >= fence_len:
                yield i, line, True, info
                in_fence, fence_char, fence_len, info = False, "", 0, ""
                continue
        yield i, line, in_fence, (info if in_fence else "")


def _render_heading(raw):
    s = _ATX_CLOSE_RE.sub("", raw)
    s = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", s)          # images -> nothing
    s = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", s)      # [t](u) -> t
    s = re.sub(r"\[([^\]]*)\]\[[^\]]*\]", r"\1", s)     # [t][r] -> t
    s = re.sub(r"`+([^`]*)`+", r"\1", s)                # `code` -> code
    s = re.sub(r"(\*\*|\*|__|~~)", "", s)               # emphasis markers
    s = re.sub(r"<[^>]+>", "", s)                       # html tags
    for ent, ch in (("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                    ("&quot;", '"'), ("&#39;", "'"), ("&nbsp;", " ")):
        s = s.replace(ent, ch)
    return s


def github_slug(rendered):
    s = rendered.strip().lower()
    s = re.sub(r"[^\w\s-]", "", s, flags=re.UNICODE)
    s = re.sub(r"\s", "-", s)
    return s


_RISKY_RE = re.compile(r"[<>&*_`]|[^\x00-\x7f]")


class Headings:
    """All anchors a Markdown document offers, plus a slug-confidence flag."""

    def __init__(self, text):
        self.slugs = set()      # deduped github slugs (lowercased)
        self.html_ids = set()   # explicit id=/name= anchors (case-sensitive)
        self.confident = True   # False if any heading is slug-ambiguous
        self._build(text)

    def _add_slug(self, base):
        slug = base
        n = 0
        while slug in self.slugs:
            n += 1
            slug = "%s-%d" % (base, n)
        self.slugs.add(slug)

    def _build(self, text):
        lines = list(iter_lines(text))
        for idx, (lineno, line, in_fence, _info) in enumerate(lines):
            for hid in _HTML_ID_RE.findall(line):
                self.html_ids.add(hid)
            if in_fence:
                continue
            raw = None
            m = _ATX_RE.match(line)
            if m:
                raw = m.group(3).strip()
            else:
                sm = _SETEXT_RE.match(line)
                if sm and idx > 0:
                    prev = lines[idx - 1]
                    if not prev[2] and prev[1].strip() and not _ATX_RE.match(prev[1]) \
                            and not _FENCE_RE.match(prev[1]):
                        raw = prev[1].strip()
            if raw is None:
                continue
            if _RISKY_RE.search(raw):
                self.confident = False
            self._add_slug(github_slug(_render_heading(raw)))

    def has_anchor(self, anchor):
        if anchor in self.html_ids:          # explicit id, case-sensitive
            return True
        return anchor.lower() in self.slugs   # slug, case-insensitive


# --- link extraction --------------------------------------------------------
_LINK_OPEN_RE = re.compile(r"(?<![\\!])\[[^\]]*\]\(")
_REF_USE_RE = re.compile(r"(?<![\\!])\[[^\]]*\]\[([^\]]*)\]")
_REF_DEF_RE = re.compile(r"^\s{0,3}\[([^\]]+)\]:\s*(<[^>]*>|\S+)")
_HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)


def _clean_dest(dest):
    dest = dest.strip()
    if dest.startswith("<") and dest.endswith(">"):
        dest = dest[1:-1]
    return dest


def _blank(match):
    return "".join("\n" if c == "\n" else " " for c in match.group(0))


def _mask_code_spans(line):
    """Blank inline code spans, honouring CommonMark's rule that a run of N
    backticks closes only on a run of exactly N — so `` `x` `` inside `` ``…`` `` is
    not mistaken for a boundary and link-shaped text inside a code span is masked."""
    out = list(line)
    n = len(line)
    i = 0
    while i < n:
        if line[i] != "`":
            i += 1
            continue
        j = i
        while j < n and line[j] == "`":
            j += 1
        run = j - i
        k = j
        found = False
        while k < n:
            if line[k] == "`":
                mm = k
                while mm < n and line[mm] == "`":
                    mm += 1
                if mm - k == run:
                    for p in range(i, mm):
                        out[p] = " "
                    i = mm
                    found = True
                    break
                k = mm
            else:
                k += 1
        if not found:
            i = j
    return "".join(out)


def _valid_title(t):
    """A CommonMark link title is empty, or quoted (\"…\"/'…'), or parenthesised.
    Anything else after the dest means the whole `[x](…)` is not a real link."""
    t = t.strip()
    if not t:
        return True
    if t[0] in "\"'":
        return len(t) >= 2 and t[-1] == t[0]
    if t[0] == "(":
        return t[-1] == ")"
    return False


def _inline_dests(line):
    """Parse inline-link destinations with balanced parentheses.

    `[x](foo(bar).md)` yields `foo(bar).md`, not the truncated `foo(bar`. A link
    whose dest never closes its `(`, or whose title is malformed, is skipped
    (never a false broken)."""
    dests, spans = [], []
    consumed_until = 0   # end of the last real link, so `[y](…)` inside a title is skipped
    for m in _LINK_OPEN_RE.finditer(line):
        if m.start() < consumed_until:
            continue
        k = m.end()
        if k < len(line) and line[k] == "<":
            end = line.find(">", k)
            close = line.find(")", end) if end != -1 else -1
            # require a real closing `)` AND a valid (or empty) title after the dest.
            if end != -1 and close != -1 and _valid_title(line[end + 1:close]):
                dests.append(line[k + 1:end])
                consumed_until = close + 1
                spans.append((m.start(), consumed_until))
            continue
        depth, buf, title, closed, in_title, esc = 1, [], [], False, False, False
        while k < len(line):
            c = line[k]
            if esc:                       # backslash-escaped char is literal (e.g. \) in a dest)
                (title if in_title else buf).append(c)
                esc = False
            elif c == "\\":
                esc = True
            elif c == "(":
                depth += 1
                (title if in_title else buf).append(c)
            elif c == ")":
                depth -= 1
                if depth == 0:
                    closed = True
                    break
                (title if in_title else buf).append(c)
            elif c.isspace():
                in_title = True   # dest ended; a title may follow — keep scanning for `)`
            elif in_title:
                title.append(c)
            else:
                buf.append(c)
            k += 1
        if not closed:
            continue            # unterminated `[x](foo` — malformed text, not a link.
        if not _valid_title("".join(title)):
            continue            # malformed/unterminated title — not a real link.
        dests.append("".join(buf))
        consumed_until = k + 1  # k is at the closing ')'
        spans.append((m.start(), consumed_until))
    return dests, spans


def extract_links(text):
    """Return (links, ref_defs). links = [(lineno, dest, in_fence)]. Fenced code,
    inline-code spans, and HTML comments are masked so link-shaped text inside
    them is never treated as a real link. Only inline `[t](dest)` and reference
    `[t][r]` forms are extracted — shortcut `[t]` is deliberately not matched
    (documented false-negative, never a false positive)."""
    text = _HTML_COMMENT_RE.sub(_blank, text)
    lines = list(iter_lines(text))
    ref_defs = {}
    for _lineno, line, in_fence, _info in lines:
        if in_fence:
            continue
        m = _REF_DEF_RE.match(line)
        if m:
            ref_defs[m.group(1).lower()] = _clean_dest(m.group(2))
    links = []
    for lineno, line, in_fence, _info in lines:
        if in_fence:
            continue
        masked = _mask_code_spans(line)
        dests, spans = _inline_dests(masked)
        for dest in dests:
            links.append((lineno, _clean_dest(dest), False))
        # blank consumed inline-link ranges so a `[y][ref]` inside a link title is
        # not re-matched by the reference-link pass.
        ref_chars = list(masked)
        for s, e in spans:
            for p in range(s, min(e, len(ref_chars))):
                ref_chars[p] = " "
        for m in _REF_USE_RE.finditer("".join(ref_chars)):
            label = m.group(1).strip().lower()
            if label and label in ref_defs:
                links.append((lineno, ref_defs[label], False))
    return links, ref_defs
