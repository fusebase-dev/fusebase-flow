"""Fusebase Flow — shell_parse: a bash command line's syntax, for the command gate (6.0.0-m8 item 7.10; shell_view.py
says what it runs).

Reads lists (`;`, `&&`, `||`, `&`, newlines), pipelines, `( )` subshells, words with their quotes ('...', "...",
$'...' ANSI-C, backslash escapes, line continuation), `$VAR`, `${VAR...}`, `$(...)`, backticks, `<(...)`, `$((...))`,
redirections, heredocs (body by the delimiter's quoting) and here-strings, comments, `[[ ... ]]`, `for` headers and
function definitions. Anything else (`case`, `coproc`, `select`, an unbalanced quote or parenthesis) raises ParseError,
and the gate judges that command's raw text, as before.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=")


class ParseError(ValueError):
    """The text is not a command line this module reads; the gate judges its raw text."""


# ---------------------------------------------------------------------------- lexing
@dataclass
class Word:
    parts: list  # ("lit", text, quoted) | ("var", name, op, arg_word, quoted) | ("sub", node, quoted) | ("unk", text, quoted)
    raw: str = ""


@dataclass
class Redir:
    op: str
    target: Word | None = None
    body: str | None = None  # a heredoc's or here-string's text
    body_quoted: bool = True  # a quoted delimiter: no expansion in the body


@dataclass
class Simple:
    words: list[Word] = field(default_factory=list)
    redirs: list[Redir] = field(default_factory=list)
    header: bool = False  # a for/select header: its words are data


@dataclass
class Group:
    body: list  # a list (pipelines)


class Lexer:
    def __init__(self, text: str):
        self.s, self.i, self.heredocs = text, 0, []

    def peek(self, n: int = 0) -> str:
        return self.s[self.i + n] if self.i + n < len(self.s) else ""

    def skip_blank(self) -> None:
        while True:
            c = self.peek()
            if c and c in " \t":
                self.i += 1
            elif c == "\\" and self.peek(1) == "\n":
                self.i += 2
            elif c == "#":
                while self.peek() not in ("", "\n"):
                    self.i += 1
            else:
                return

    def newline(self) -> None:
        """At a newline: the heredoc bodies queued on this line follow it."""
        self.i += 1
        for r, strip, quoted in self.heredocs:
            lines, delim = [], r.target_text
            while self.i <= len(self.s):
                end = self.s.find("\n", self.i)
                line = self.s[self.i:] if end < 0 else self.s[self.i:end]
                self.i = len(self.s) + 1 if end < 0 else end + 1
                if (line.lstrip("\t") if strip else line) == delim:
                    break
                lines.append(line.lstrip("\t") if strip else line)
            r.body, r.body_quoted = "\n".join(lines) + ("\n" if lines else ""), quoted
        self.i = min(self.i, len(self.s))
        self.heredocs = []


def parse(text: str) -> list:
    lx = Lexer(text)
    out = parse_list(lx, "")
    if lx.i < len(lx.s):
        raise ParseError(f"unexpected {lx.s[lx.i]!r} at {lx.i}")
    if lx.heredocs:  # a heredoc whose body never started: bash reads to the end, so do we
        lx.s += "\n"
        lx.newline()
    return out


def parse_list(lx: Lexer, close: str) -> list:
    """Pipelines up to `close` (")" or "" for the end); each pipeline is a list of commands."""
    items = []
    while True:
        lx.skip_blank()
        c = lx.peek()
        if c == "":
            if close:
                raise ParseError(f"missing {close!r}")
            return items
        if close and c == close:
            lx.i += 1
            return items
        if c == "\n":
            lx.newline()
            continue
        if c in ";&|" or c == ")":
            if lx.s.startswith(";;", lx.i):
                raise ParseError("case clause")
            if c == ")" and not close:
                raise ParseError("unbalanced )")
            lx.i += 2 if lx.s[lx.i:lx.i + 2] in ("&&", "||") else 1
            continue
        items.append(parse_pipeline(lx, close))


def parse_pipeline(lx: Lexer, close: str) -> list:
    cmds = [parse_command(lx, close)]
    while True:
        lx.skip_blank()
        if lx.peek() == "|" and lx.peek(1) != "|":
            lx.i += 2 if lx.peek(1) == "&" else 1
            lx.skip_blank()
            while lx.peek() == "\n":
                lx.newline()
                lx.skip_blank()
            cmds.append(parse_command(lx, close))
        else:
            return cmds


def parse_command(lx: Lexer, close: str):
    lx.skip_blank()
    if lx.s.startswith("((", lx.i):  # an arithmetic command: no command runs
        depth, lx.i = 0, lx.i
        while lx.i < len(lx.s):
            depth += {"(": 1, ")": -1}.get(lx.s[lx.i], 0)
            lx.i += 1
            if depth == 0:
                return Simple(header=True)
        raise ParseError("unbalanced ((")
    if lx.peek() == "(":
        lx.i += 1
        return Group(parse_list(lx, ")"))
    cmd = Simple()
    while True:
        lx.skip_blank()
        c = lx.peek()
        if c == "" or c == "\n" or c in ";&|" and not lx.s.startswith("&>", lx.i) or c == ")":
            return cmd
        if c == "(":
            if len(cmd.words) == 1 and re.match(r"\(\s*\)", lx.s[lx.i:]):  # name() { ...; }: a function definition
                lx.i += re.match(r"\(\s*\)", lx.s[lx.i:]).end()
                cmd.words, cmd.header = [], True
                return cmd
            raise ParseError("( inside a command")
        redir = read_redir(lx)
        if redir:
            cmd.redirs.append(redir)
            continue
        word = read_word(lx)
        if not cmd.words and word.raw in ("case", "coproc", "select", "function") and not cmd.redirs:
            if word.raw == "function":
                read_word_after_blank(lx)
                cmd.header = True
                continue
            raise ParseError(f"`{word.raw}`")
        if not cmd.words and word.raw in ("for",):
            cmd.header = True
        cmd.words.append(word)
        if word.raw == "[[" and len(cmd.words) == 1:
            read_double_bracket(lx, cmd)
            return cmd


def read_word_after_blank(lx: Lexer) -> Word:
    lx.skip_blank()
    return read_word(lx)


def read_double_bracket(lx: Lexer, cmd: Simple) -> None:
    """`[[ ... ]]`: its operands are data, and `&&`, `<` inside it are no operators."""
    end = lx.s.find("]]", lx.i)
    if end < 0:
        raise ParseError("unclosed [[")
    inner = lx.s[lx.i:end]
    if re.search(r"\$\(|`", inner):
        raise ParseError("command substitution inside [[")
    cmd.words.append(Word([("lit", inner, True)], inner))
    lx.i = end + 2


REDIR = re.compile(r"(\d*)(<<<|<<-|<<|&>>|&>|>>|>\||>&|<&|<>|>|<)")


def read_redir(lx: Lexer) -> Redir | None:
    m = REDIR.match(lx.s, lx.i)
    if not m:
        return None
    if m[1] and lx.i > 0 and lx.s[lx.i - 1] not in " \t\n;&|(":
        return None
    op = m[2]
    if op in ("<", ">") and lx.s[m.end():m.end() + 1] == "(":  # <(...) is a word: process substitution
        return None
    lx.i = m.end()
    if op in (">&", "<&") and re.match(r"\d+|-", lx.s[lx.i:]):
        lx.i += re.match(r"\d+|-", lx.s[lx.i:]).end()
        return Redir(op)
    lx.skip_blank()
    target = read_word(lx)
    r = Redir(">" if op in ("&>", ">|", ">&") else ">>" if op == "&>>" else op, target)
    if op in ("<<", "<<-"):
        quoted = any(p[0] == "lit" and p[2] for p in target.parts) or "\\" in target.raw
        r.target_text = "".join(p[1] for p in target.parts if p[0] == "lit")
        lx.heredocs.append((r, op == "<<-", quoted))
    elif op == "<<<":
        r.body, r.body_quoted = None, False
    return r


def read_word(lx: Lexer) -> Word:
    parts, start = [], lx.i
    s = lx.s
    buf = []

    def flush(quoted: bool = False) -> None:
        if buf:
            parts.append(("lit", "".join(buf), quoted))
            buf.clear()
    while lx.i < len(s):
        c = s[lx.i]
        if c in " \t\n;&|()<>" and not (c in "<>" and s[lx.i + 1:lx.i + 2] == "(" and not buf and not parts):
            break
        if c == "\\":
            if s[lx.i + 1:lx.i + 2] == "\n":
                lx.i += 2
                continue
            flush()
            parts.append(("lit", s[lx.i + 1:lx.i + 2], True))
            lx.i += 2
            continue
        if c == "'":
            flush()
            end = s.find("'", lx.i + 1)
            if end < 0:
                raise ParseError("unclosed '")
            parts.append(("lit", s[lx.i + 1:end], True))
            lx.i = end + 1
            continue
        if c == '"':
            flush()
            lx.i += 1
            parts += read_double(lx)
            continue
        if c == "`":
            flush()
            parts.append(("sub", read_backtick(lx), False))
            continue
        if c == "$":
            flush()
            parts.append(read_dollar(lx, False))
            continue
        if c in "<>" and s[lx.i + 1:lx.i + 2] == "(":  # process substitution
            lx.i += 2
            parts.append(("sub", parse_list(lx, ")"), False))
            continue
        buf.append(c)
        lx.i += 1
    flush()
    if not parts:
        raise ParseError(f"empty word at {start}")
    return Word(parts, s[start:lx.i])


def read_double(lx: Lexer) -> list:
    s, parts, buf = lx.s, [], []
    while True:
        if lx.i >= len(s):
            raise ParseError('unclosed "')
        c = s[lx.i]
        if c == '"':
            lx.i += 1
            break
        if c == "\\" and s[lx.i + 1:lx.i + 2] in ('"', "\\", "$", "`", "\n"):
            if s[lx.i + 1] != "\n":
                buf.append(s[lx.i + 1])
            lx.i += 2
            continue
        if c in "$`":
            if buf:
                parts.append(("lit", "".join(buf), True))
                buf = []
            parts.append(read_dollar(lx, True) if c == "$" else ("sub", read_backtick(lx), True))
            continue
        buf.append(c)
        lx.i += 1
    parts.append(("lit", "".join(buf), True))
    return parts


def read_backtick(lx: Lexer) -> list:
    s, j, inner = lx.s, lx.i + 1, []
    while j < len(s) and s[j] != "`":
        if s[j] == "\\" and j + 1 < len(s) and s[j + 1] in "`\\$":
            inner.append(s[j + 1])
            j += 2
            continue
        inner.append(s[j])
        j += 1
    if j >= len(s):
        raise ParseError("unclosed `")
    lx.i = j + 1
    return parse("".join(inner))


ANSI = {"a": "\a", "b": "\b", "e": "\x1b", "E": "\x1b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v",
        "\\": "\\", "'": "'", '"': '"', "?": "?"}


def ansi_c(body: str) -> str:
    """The value of $'...' (bash's ANSI-C quoting)."""
    out, i = [], 0
    while i < len(body):
        if body[i] != "\\" or i + 1 >= len(body):
            out.append(body[i])
            i += 1
            continue
        c = body[i + 1]
        if c in ANSI:
            out.append(ANSI[c])
            i += 2
        elif m := re.match(r"x([0-9A-Fa-f]{1,2})|u([0-9A-Fa-f]{1,4})|U([0-9A-Fa-f]{1,8})|([0-7]{1,3})", body[i + 1:]):
            out.append(chr(int(next(g for g in m.groups() if g), 8 if m[4] else 16)))
            i += 1 + m.end()
        elif c == "c" and i + 2 < len(body):
            out.append(chr(ord(body[i + 2]) & 31))
            i += 3
        else:
            out.append("\\" + c)
            i += 2
    return "".join(out)


def read_dollar(lx: Lexer, quoted: bool):
    s, i = lx.s, lx.i
    nxt = s[i + 1:i + 2]
    if nxt == "'" and not quoted:
        end, j = None, i + 2
        while j < len(s):
            if s[j] == "\\":
                j += 2
                continue
            if s[j] == "'":
                end = j
                break
            j += 1
        if end is None:
            raise ParseError("unclosed $'")
        lx.i = end + 1
        return ("lit", ansi_c(s[i + 2:end]), True)
    if nxt == '"' and not quoted:
        lx.i = i + 2
        parts = read_double(lx)
        return ("var", "", "parts", parts, True)
    if s.startswith("$((", i):
        depth, j = 0, i + 1
        while j < len(s):
            depth += {"(": 1, ")": -1}.get(s[j], 0)
            j += 1
            if depth == 0:
                break
        else:
            raise ParseError("unbalanced $((")
        lx.i = j
        return ("unk", s[i:j], quoted)
    if nxt == "(":
        lx.i = i + 2
        return ("sub", parse_list(lx, ")"), quoted)
    if nxt == "{":
        depth, j = 0, i + 1
        while j < len(s):
            if s[j] == "\\":
                j += 2
                continue
            depth += {"{": 1, "}": -1}.get(s[j], 0)
            j += 1
            if depth == 0:
                break
        else:
            raise ParseError("unclosed ${")
        lx.i = j
        inner = s[i + 2:j - 1]
        m = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*#?$!-])(:?[-=+?])?(.*)", inner, re.S)
        if not m:
            return ("unk", s[i:j], quoted)
        arg = parse_word_text(m[3]) if m[2] else None
        return ("var", m[1], m[2] or "", arg, quoted)
    m = NAME.match(s, i + 1) or re.compile(r"[0-9@*#?$!-]").match(s, i + 1)
    if m:
        lx.i = m.end()
        return ("var", m[0], "", None, quoted)
    lx.i = i + 1
    return ("lit", "$", quoted)


def parse_word_text(text: str) -> Word | None:
    """A ${x:-word} default, read as a word (its quotes removed when expanded)."""
    if not text:
        return Word([("lit", "", True)], "")
    lx = Lexer(text)
    parts = []
    while lx.i < len(text):
        if text[lx.i] in " \t":
            parts.append(("lit", text[lx.i], False))
            lx.i += 1
            continue
        parts += read_word(lx).parts
    return Word(parts, text)


__all__ = ["ASSIGN", "Group", "Lexer", "ParseError", "Redir", "Simple", "Word", "ansi_c", "parse", "parse_list"]
