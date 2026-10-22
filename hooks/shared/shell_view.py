"""Fusebase Flow — shell_view: what a shell command actually runs, for the command gate (6.0.0-m8 item 7.10).

The owner's lock of 2026-10-21 (docs/backlog/command-gate-shell-evasion/, D1 = D1a, D2 = D2-no): "match parsed command
tokens, never words inside quoted strings, heredocs or search patterns; and never suggest minting an approval for an
action the command does not take."

`view(command)` parses a POSIX/bash command line (quote removal, escapes, ANSI-C quoting, line continuation, comments,
lists, pipelines, subshells, groups, command and process substitution, heredocs and here-strings, known variables) and
returns the texts a rule may match: one per simple command that runs, its words joined by single spaces, with the word
offsets where a match may START (a command word, its options and operands; never a data word, never inside a word, never
the subcommand slot of a CLI: `npm rm`, `git rm`); one per redirection (`> target`); and interpreter code (python -c, a
python heredoc) with its multi-word string literals blanked, matched anywhere. Text the shell does not run as a command
is not judged: a quoted message (`git commit -m`), a search pattern (grep, rg, sed's script, `git log --grep`), echo and
printf arguments, a heredoc a non-shell reads, a comment. Text it does run is: `$(...)` anywhere, `sh -c`, `eval`, an
alias's value, `find -exec`, `ssh host cmd`, a heredoc or a pipe into a shell (echo and printf output simulated), the
`--command` of approve-local.sh. A command the parser cannot read (a syntax error, `case`, PowerShell) is judged on its
raw text, as before (`parsed` False), and the gate then names no approval to mint.

TRIPWIRE (N1..N6 of the ticket): never blank heredocs or `-m` payloads wholesale, never split argv naively, never
anchor a rule to the start of the whole string; a construct this module does not understand must raise ParseError (raw
matching), never be skipped.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from .shell_parse import ASSIGN, Group, ParseError, Simple, Word, ansi_c, parse, subs_in

DATA = "\x00"  # a data word's rendering: no rule matches it, and \b still sees a boundary around it
IFS = " \t\n"
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "ash", "mksh", "yash"}
INTERPRETERS = {"python", "python3", "python2", "py", "pypy", "pypy3", "node", "nodejs", "deno", "bun", "perl", "ruby",
                "php"}
SEARCH = {"grep", "egrep", "fgrep", "zgrep", "rg", "ag", "ack", "ugrep", "findstr", "select-string"}
DATA_ARGS = {"echo", "printf", ":", "true", "false", "[", "test", "[[", "printenv", "type", "which", "whereis"}
ASSIGNERS = {"export", "declare", "typeset", "local", "readonly"}
# A wrapper runs the command that follows its own options (option words taking a value listed).
WRAPPERS = {"env": "uSCP", "sudo": "ugpChDrtU", "doas": "uC", "nohup": "", "time": "of", "exec": "a", "command": "",
            "builtin": "", "nice": "n", "ionice": "cnp", "timeout": "sk", "stdbuf": "ioe", "setsid": "", "chronic": "",
            "unbuffer": "", "xargs": "IinPLsdEa", "watch": "nd", "busybox": "", "taskset": "", "strace": "oesp",
            "ltrace": "oesp", "caffeinate": "tw", "npx": "pc", "bunx": "p", "pnpx": "p", "flock": "wE", "nsenter": "t"}
RUNNERS = {"pnpm", "yarn", "bun"}  # run their own subcommand, or else the project's binary of that name
# The CLIs whose next word is their own subcommand (npm rm, git rm, docker rm, helm rm): no rule starts there. Any other
# program's first argument may be a command it runs (fakeroot rm -rf, proxychains4 fusebase deploy; review B H3).
CLIS = set("npm pnpm yarn bun npx git docker docker-compose podman kubectl helm gh cargo go pip pip3 pipx uv poetry conda "
           "brew apt apt-get dnf yum apk snap systemctl service fusebase terraform aws az gcloud firebase vercel netlify "
           "heroku fly flyctl supabase prisma dotnet composer gem bundle rake rails jj hg svn rustup deno nx turbo "
           "lerna mix kind minikube skaffold".split())
RUNNER_OWN = set("add remove rm uninstall install i update up upgrade run test init create publish link unlink why "
                 "outdated audit list ls info config store cache prune dedupe import version pack login logout whoami "
                 "global bin workspace workspaces patch rebuild env setup licenses root".split())
GIT_GLOBAL_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--exec-path",
                    "--super-prefix", "--attr-source"}
# Programs whose argument, or an option's value, is a shell command they run (6.0.0-m8 fix, review B H3): trap's first
# argument; git's `submodule foreach` command, `rebase -x/--exec`, a `!` alias and the settings and variables below.
CODE_ARGS = {"trap": "first", "git": "submodule foreach, rebase -x/--exec, -c or config: alias.*=!..., GIT_CODE_KEYS"}
GIT_CODE_KEYS = {"core.sshcommand", "core.pager", "core.editor", "sequence.editor"}
GIT_CODE_VARS = {"GIT_SSH_COMMAND", "GIT_PAGER", "GIT_EDITOR", "GIT_SEQUENCE_EDITOR"}
EXEC_VALUE = {"-e", "--env", "-u", "--user", "-w", "--workdir", "--env-file", "--detach-keys", "--index", "-c",
              "--container", "-n", "--namespace", "-f", "--filename"}  # docker/kubectl exec options with a value
RESERVED = {"!", "{", "}", "if", "then", "elif", "else", "fi", "do", "done", "while", "until"}
STDIN = {"-", "/dev/stdin", "/dev/fd/0", "/proc/self/fd/0"}  # a script path that is the shell's own stdin
BARE = re.compile(r"[A-Za-z][\w.:-]*")
NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
EXEC_CALL = re.compile(r"(?:\bos\.(?:system|popen|exec\w*|spawn\w*)|\bsubprocess\.\w+|\bcommands\.getoutput|"
                       r"\bpty\.spawn|\bchild_process\.\w+|\bexecSync|\bexecFileSync|\bspawnSync|\bexecFile|\bspawn|"
                       r"\bexec|\bsystem|\bpopen|\bshell_exec|\bpassthru|\bproc_open)\s*\(\s*\[?")


@dataclass
class View:
    raw: str
    parsed: bool
    texts: list[tuple[str, tuple[int, ...] | None]] = field(default_factory=list)  # None: match anywhere (code)
    why: str = ""

    def matches(self, regex: re.Pattern) -> bool:
        if not self.parsed:
            return bool(regex.search(self.raw))
        for text, starts in self.texts:
            if starts is None:
                if regex.search(text):
                    return True
            elif any(regex.match(text, at) for at in starts):
                return True
        return False


# ---------------------------------------------------------------------------- expansion
class Analysis:
    def __init__(self) -> None:
        self.env: dict[str, str] = {"IFS": IFS}
        self.texts: list[tuple[str, tuple[int, ...] | None]] = []

    # A field is (text, has_quoted_whitespace); unresolved parts keep their source text.
    def expand(self, word: Word) -> list[str]:
        segs: list[tuple[str, bool]] = []  # (text, splittable)
        self._parts(word.parts, segs)
        fields, cur, started = [], [], False
        for text, split in segs:
            if not split:
                cur.append(text)
                started = True
                continue
            for k, piece in enumerate(re.split(r"[ \t\n]+", text)):
                if k:
                    if started or cur:
                        fields.append("".join(cur))
                    cur, started = [], False
                if piece:
                    cur.append(piece)
                    started = True
        if started or cur:
            fields.append("".join(cur))
        return fields

    def _parts(self, parts: list, segs: list) -> None:
        for p in parts:
            kind = p[0]
            if kind == "lit":
                segs.append((p[1], False))
            elif kind == "unk":
                segs.append((p[1], False))
            elif kind == "run":  # substitutions inside a text no word holds ($((...)), ${x/a/b}): they run
                for node in p[1]:
                    self.walk(node)
            elif kind == "sub":
                out = self.sub_output(p[1])
                segs.append((out if out is not None else "$(...)", not p[2] and out is not None))
            elif kind == "var":
                name, op, arg, quoted = p[1], p[2], p[3], p[4]
                if op == "parts":
                    self._parts(arg, segs)
                    continue
                value = self.env.get(name)
                if value is None and op in ("-", ":-", "=", ":=") and arg is not None:
                    inner: list = []
                    self._parts(arg.parts, inner)
                    value = "".join(t for t, _ in inner)
                    if op in ("=", ":="):
                        self.env[name] = value
                if value is None:
                    segs.append((f"${name}", False))
                else:
                    segs.append((value, not quoted))

    def sub_output(self, node: list) -> str | None:
        """$(...)'s output when it is one echo or printf of resolved words, else None; its commands are judged."""
        self.walk(node)
        if len(node) == 1 and len(node[0]) == 1 and isinstance(node[0][0], Simple):
            words = [w for wd in node[0][0].words for w in self.expand(wd)]
            out = simulate(words)
            return out.rstrip("\n") if out is not None else None
        return None

    # ------------------------------------------------------------------------ walking
    def walk(self, items: list) -> None:
        for pipeline in items:
            for k, cmd in enumerate(pipeline):
                reader = stdin_reader(pipeline[k + 1]) if k + 1 < len(pipeline) else ""
                if isinstance(cmd, Group):
                    self.walk(cmd.body)
                else:
                    self.simple(cmd, reader)

    def simple(self, cmd: Simple, out_to: str) -> None:
        for r in cmd.redirs:
            if r.target is not None and r.op not in ("<<", "<<-"):
                target = " ".join(self.expand(r.target))
                self.texts.append((f"{r.op} {target}", (0,)))
        if cmd.header:
            for w in cmd.words:
                self.expand(w)  # its substitutions still run
            return
        fields: list[str] = []
        for w in cmd.words:
            fields += self.expand(w)
        while fields and fields[0] in RESERVED:
            fields.pop(0)
        if not fields:
            self.heredocs(cmd, "", [])
            return
        self.judge(fields, cmd, out_to)

    def heredocs(self, cmd: Simple, consumer: str, fields: list[str], out_to: str = "") -> None:
        """Each heredoc's and here-string's text goes to `consumer`; to `out_to` when the consumer is cat in a pipe into
        a shell (`cat <<EOF | sh`)."""
        if not consumer and out_to and fields and basename(fields[0]) == "cat" and set(fields[1:]) <= {"-"}:
            consumer = out_to
        for r in cmd.redirs:
            body = r.body
            if r.op == "<<<" and r.target is not None:
                body = " ".join(self.expand(r.target)) + "\n"
            if body is None:
                continue
            if r.op in ("<<", "<<-") and not r.body_quoted:  # $(...) and backticks in an unquoted heredoc run
                for node in subs_in(body):  # (a substitution that does not parse: the line is judged raw)
                    self.walk(node)
            self.feed(consumer, fields, body)

    def feed(self, consumer: str, fields: list[str], text: str) -> None:
        """`text` reaches `consumer`'s stdin: a shell runs it, an interpreter runs it as its code, anything else reads
        it as data."""
        if consumer == "shell":
            self.code(text)
        elif consumer == "script":
            self.script(text, fields[0] if fields else "")
        elif consumer == "sql":  # psql reads it: judged where a rule names psql (review B H3)
            self.texts.append(("psql " + " ".join(text.split()), (0,)))

    def code(self, text: str) -> None:
        self.walk(parse(text))

    def script(self, code: str, interpreter: str) -> None:
        base = interpreter.rsplit("/", 1)[-1].lower()
        self.texts.append((blank_literals(code, base, self), None))

    def judge(self, fields: list[str], cmd: Simple, out_to: str) -> None:
        roles = classify(fields)
        c = next((k for k, r in enumerate(roles) if r == "cmd"), len(fields))
        last = max((k for k, r in enumerate(roles) if r == "cmd"), default=c)
        base = basename(fields[last]) if last < len(fields) else ""
        if all(r == "assign" for r in roles):  # NAME=value: known from here on
            for f in fields:
                name, _, value = f.partition("=")
                self.env[name.rstrip("+")] = value
        if base in ASSIGNERS:
            for f in fields[last + 1:]:
                if ASSIGN.match(f):
                    name, _, value = f.partition("=")
                    self.env[name] = value
        if base == "read":
            self.read_into(fields[last + 1:], cmd)
        for f in fields:  # GIT_SSH_COMMAND='...' git fetch: git runs the value (review B H3)
            if ASSIGN.match(f) and f.partition("=")[0].rstrip("+") in GIT_CODE_VARS:
                self.code(f.partition("=")[2])
        self.args(fields, roles, last, base)
        consumer, reader = consumer_of(fields, last)
        self.heredocs(cmd, consumer, reader, out_to)
        if out_to and base in ("echo", "printf"):
            out = simulate(fields[last:])
            if out is not None:
                self.feed(out_to, [], out)
        self.render(fields, roles, last)
        if base == "git":
            keep = git_without_globals(fields, last)
            if len(keep) < len(fields):
                self.render([fields[k] for k in keep], [roles[k] for k in keep], last)

    def read_into(self, args: list[str], cmd: Simple) -> None:
        """`read X <<< 'text'` (or a heredoc): X is known from here on, as an assignment would make it."""
        names, k = [], 0
        while k < len(args):
            if args[k] in ("-p", "-d", "-n", "-N", "-t", "-u", "-a"):  # an option and its value
                k += 2
                continue
            if NAME_RE.fullmatch(args[k]):
                names.append(args[k])
            k += 1
        text = next((" ".join(self.expand(r.target)) if r.op == "<<<" and r.target is not None else
                     (r.body or "").split("\n", 1)[0] for r in cmd.redirs if r.op in ("<<<", "<<", "<<-")), None)
        if names and text is not None:
            words = text.split(None, len(names) - 1)
            for name, value in zip(names, words + [""] * len(names)):
                self.env[name] = value

    def args(self, fields: list[str], roles: list[str], c: int, base: str) -> None:
        """Marks data words and runs the code an argument carries (roles is edited in place)."""
        rest = range(c + 1, len(fields))
        if base in DATA_ARGS or base in SEARCH:
            for k in rest:
                roles[k] = "data"
        elif base == "sed":
            scripts = [k + 1 for k in rest if fields[k] in ("-e", "--expression") and k + 1 < len(fields)]
            scripts += [k for k in rest if fields[k].startswith(("--expression=", "-e")) and len(fields[k]) > 2
                        and fields[k] not in ("-e", "--expression")]
            if not scripts:
                scripts = [next((k for k in rest if not fields[k].startswith("-")), None)]
            for k in scripts:
                if k is not None:
                    roles[k] = "data"
        elif base == "git":
            git_data(fields, roles, c)
            self.git_code(fields, roles, c)
        elif base in CODE_ARGS:  # trap '<command>' <signals>
            k = c + 1
            while k < len(fields) and fields[k] in ("-p", "-l", "--"):
                k += 1
            if k < len(fields):
                roles[k] = "data"
                self.code(fields[k])
        elif base == "gh":
            for k in rest:
                if fields[k - 1] in ("--body", "-b", "--title", "-t", "--notes", "-n", "--message", "-m"):
                    roles[k] = "data"
                elif fields[k].startswith(("--body=", "--title=", "--notes=", "--message=")):
                    roles[k] = "data"
        elif base == "eval":
            for k in rest:
                roles[k] = "data"
            self.code(" ".join(fields[c + 1:]))
        elif base == "alias":
            for k in rest:
                roles[k] = "data"
                if "=" in fields[k]:
                    self.code(fields[k].partition("=")[2])
        elif base in INTERPRETERS:
            for k in rest:
                if fields[k - 1] in ("-c", "-e", "-E", "--eval", "-p", "--print", "-r") and roles[k - 1] != "data":
                    roles[k] = "data"
                    self.script(fields[k], base)
        elif base == "find":
            k = c + 1
            while k < len(fields):
                if fields[k] in ("-exec", "-execdir", "-ok", "-okdir"):
                    end = next((j for j in range(k + 1, len(fields)) if fields[j] in (";", "+")), len(fields))
                    inner = fields[k + 1:end]
                    if inner:
                        self.judge_words(inner)
                    k = end
                k += 1
        elif base == "ssh":
            k = c + 1
            while k < len(fields) and fields[k].startswith("-"):
                k += 2 if fields[k][-1:] in "bcDEeFIiJLlmOopQRSWw" and len(fields[k]) == 2 else 1
            if k + 1 < len(fields):
                for j in range(k + 1, len(fields)):
                    roles[j] = "data"
                self.code(" ".join(fields[k + 1:]))
        self.shell_c(fields, roles, c)
        self.approve_local(fields, roles, c)

    def git_code(self, fields: list[str], roles: list[str], c: int) -> None:
        """The shell commands a git line hands to a shell (CODE_ARGS)."""
        k = c + 1
        while k < len(fields) and fields[k].startswith("-") and fields[k] != "--":
            if fields[k] == "-c" and k + 1 < len(fields):
                self.git_setting(fields[k + 1])
            k += 2 if fields[k] in GIT_GLOBAL_VALUE else 1
        sub, rest = (fields[k] if k < len(fields) else ""), range(k + 1, len(fields))
        if sub == "submodule" and fields[k + 1:k + 2] == ["foreach"]:
            j = k + 2
            while j < len(fields) and fields[j].startswith("-"):
                j += 1
            if j < len(fields):
                for t in range(j, len(fields)):
                    roles[t] = "data"
                self.code(" ".join(fields[j:]))
        elif sub == "rebase":
            for j in rest:
                if fields[j] in ("-x", "--exec") and j + 1 < len(fields):
                    roles[j + 1] = "data"
                    self.code(fields[j + 1])
                elif fields[j].startswith("--exec="):
                    roles[j] = "data"
                    self.code(fields[j].partition("=")[2])
        elif sub == "config":
            pos = [j for j in rest if not fields[j].startswith("-") and fields[j - 1] not in ("-f", "--file", "--blob")]
            pos = pos[1:] if pos and fields[pos[0]] == "set" else pos
            if len(pos) >= 2:
                self.git_setting(f"{fields[pos[0]]}={fields[pos[1]]}")

    def git_setting(self, setting: str) -> None:
        key, _, value = setting.partition("=")
        if key.lower().startswith("alias.") and value.startswith("!"):
            self.code(value[1:])
        elif key.lower() in GIT_CODE_KEYS:
            self.code(value)

    def shell_c(self, fields: list[str], roles: list[str], c: int) -> None:
        """`sh -c X` (and `bash -lc X` ...), as the command or anywhere among its arguments: X is shell code; the words
        after it are its $0, $1 ..."""
        k = c
        while k < len(fields):
            if basename(fields[k]) in SHELLS and roles[k] != "data":
                j = k + 1
                while j < len(fields) and fields[j].startswith("-") and fields[j] != "--":
                    if re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", fields[j]) and j + 1 < len(fields):
                        roles[j + 1] = "data"
                        for t in range(j + 2, len(fields)):
                            roles[t] = "data"
                        self.code(fields[j + 1])
                        return
                    j += 2 if fields[j] in ("-o", "+o", "-O", "+O") else 1
            k += 1

    def approve_local(self, fields: list[str], roles: list[str], c: int) -> None:
        """approve-local.sh's --command is the command the approval binds: judged as if it ran (T284: only a
        destructive_file_delete mint has it blanked first, by command_rules.mint_subject); its reason is data."""
        at = next((k for k in range(c, min(c + 2, len(fields))) if basename(fields[k]) == "approve-local.sh"), None)
        if at is None:
            return
        k = at + 1
        while k < len(fields):
            if fields[k] == "--command" and k + 1 < len(fields):
                roles[k + 1] = "data"
                self.code(fields[k + 1])
                k += 2
                continue
            if not fields[k].startswith("-") and k >= at + 3:
                roles[k] = "data"
            k += 1

    def judge_words(self, fields: list[str]) -> None:
        roles = classify(fields)
        c = next((k for k, r in enumerate(roles) if r == "cmd"), len(fields))
        last = max((k for k, r in enumerate(roles) if r == "cmd"), default=c)
        self.args(fields, roles, last, basename(fields[last]) if last < len(fields) else "")
        self.render(fields, roles, last)

    def render(self, fields: list[str], roles: list[str], last: int) -> None:
        out, starts, at = [], [], 0
        for k, (f, role) in enumerate(zip(fields, roles)):
            text = DATA if role == "data" else basename(f) if role == "cmd" else f
            text = "".join(DATA if ch.isspace() and ch not in IFS else ch for ch in text)
            eligible = role != "data" and not any(ch in IFS for ch in text) and text != DATA and not (
                k == last + 1 and subcommand_slot(fields, last))
            if eligible:
                starts.append(at)
            out.append(text)
            at += len(text) + 1
        self.texts.append((" ".join(out), tuple(starts)))


# ---------------------------------------------------------------------------- roles
def basename(word: str) -> str:
    return re.split(r"[/\\]", word)[-1] if word else word


def classify(fields: list[str]) -> list[str]:
    """Each field's role: assign (a prefix NAME=value), cmd (a command word: the first, and each one a wrapper runs),
    or arg."""
    roles, k = ["arg"] * len(fields), 0
    while k < len(fields) and ASSIGN.match(fields[k]):
        roles[k] = "assign"
        k += 1
    while k < len(fields):
        roles[k] = "cmd"
        base = basename(fields[k])
        if base in RUNNERS and k + 1 < len(fields):
            nxt = fields[k + 1]
            if nxt in ("exec", "dlx", "x"):
                k += 2
                continue
            if nxt in RUNNER_OWN or nxt.startswith("-"):
                break
            k += 1
            continue
        if base == "npm" and k + 1 < len(fields) and fields[k + 1] in ("exec", "x"):
            k += 2
            continue
        if base not in WRAPPERS:
            break
        values, k = WRAPPERS[base], k + 1
        while k < len(fields) and (fields[k].startswith("-") or (base == "env" and ASSIGN.match(fields[k]))):
            opt = fields[k]
            k += 1
            if opt == "--":
                break
            if len(opt) == 2 and opt[1] in values and k < len(fields):
                k += 1
        if base in ("timeout", "taskset") and k < len(fields):
            k += 1
        if base == "nice" and k < len(fields) and re.fullmatch(r"-?\d+", fields[k]):
            k += 1
    return roles


def subcommand_slot(fields: list[str], last: int) -> bool:
    """The word right after a CLI is its subcommand (npm rm, git rm, docker rm): no rule starts there. A wrapper's next
    word is a command instead (classify marks it)."""
    return last + 1 < len(fields) and basename(fields[last]) in CLIS and bool(BARE.fullmatch(fields[last + 1]))


def git_data(fields: list[str], roles: list[str], c: int) -> None:
    k = c + 1
    while k < len(fields) and fields[k].startswith("-"):
        k += 2 if fields[k] in GIT_GLOBAL_VALUE else 1
    sub = fields[k] if k < len(fields) else ""
    rest = range(k + 1, len(fields))
    if sub == "grep":
        for j in rest:
            roles[j] = "data"
        return
    message = sub in ("commit", "merge", "tag", "stash", "notes", "commit-tree", "am", "push")
    search = sub in ("log", "shortlog", "rev-list", "reflog", "whatchanged", "show", "blame")
    for j in rest:
        prev, word = fields[j - 1], fields[j]
        if message and (prev in ("-m", "--message", "-F", "--file") and prev != "-F" and prev != "--file"
                        or re.fullmatch(r"-[a-zA-Z]*m", prev)):
            roles[j] = "data"
        elif message and word.startswith(("--message=", "-m")) and len(word) > 2 and word != "-m":
            roles[j] = "data"
        elif search and (prev in ("--grep", "-S", "-G", "--author", "--committer", "--format", "--pretty")
                         or word.startswith(("--grep=", "--author=", "--committer=", "--format=", "--pretty=", "-S",
                                             "-G")) and len(word) > 2):
            roles[j] = "data"
        elif sub == "stash" and fields[k + 1:k + 2] == ["save"] and j > k + 1:
            roles[j] = "data"


def git_without_globals(fields: list[str], c: int) -> list[int]:
    """The indices of git's words without its global options (-C dir, -c k=v, --git-dir=...), so `git -C x push --force`
    reads as `git push --force` (corpus PF-09); the form with them is judged too (core.hooksPath rules read -c)."""
    k = c + 1
    while k < len(fields) and fields[k].startswith("-") and fields[k] != "--":
        k += 2 if fields[k] in GIT_GLOBAL_VALUE else 1
    return list(range(c + 1)) + list(range(k, len(fields)))


def is_shell_reader(fields: list[str], c: int) -> bool:
    """A shell that reads its commands from stdin: no -c, and no script file (or -s)."""
    if c >= len(fields) or basename(fields[c]) not in SHELLS:
        return False
    args = fields[c + 1:]
    if "-s" in args:
        return True
    opts = [a for a in args if a.startswith("-") and a != "-"]
    positional = [a for a in args if a not in opts]
    return not any(re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", o) for o in opts) and (not positional or positional[0] in STDIN)


def is_script_reader(fields: list[str], c: int) -> bool:
    """An interpreter that reads its program from stdin (`python3 -`, `node`)."""
    if c >= len(fields) or basename(fields[c]).lower() not in INTERPRETERS:
        return False
    args = fields[c + 1:]
    if any(a in ("-c", "-e", "-E", "--eval", "-p", "-r") for a in args):
        return False
    positional = [a for a in args if a == "-" or not a.startswith("-")]
    return not positional or positional[0] in STDIN


def stdin_reader(cmd) -> str:
    """"shell" or "script" when the next stage of a pipeline runs what it reads, else ""."""
    if not isinstance(cmd, Simple) or not cmd.words:
        return ""
    try:
        fields = [f for w in cmd.words for f in Analysis().expand(w)]
    except ParseError:
        return ""
    roles = classify(fields)
    last = max((k for k, r in enumerate(roles) if r == "cmd"), default=0)
    return consumer_of(fields, last)[0]


def remote_command(fields: list[str], c: int) -> list[str] | None:
    """The command a remote or container shell runs (review B H3): `ssh [opts] HOST [CMD...]` ([] when ssh names none:
    the login shell then reads stdin), `docker|podman [compose] exec [opts] NAME CMD...`, `docker-compose exec ...`,
    `kubectl exec [opts] POD [--] CMD...`; None for any other program."""
    base, rest = basename(fields[c]), fields[c + 1:]
    if base == "ssh":
        k = 0
        while k < len(rest) and rest[k].startswith("-"):
            k += 2 if len(rest[k]) == 2 and rest[k][1] in "bcDEeFIiJLlmOopQRSWw" else 1
        return rest[k + 1:]
    head = rest[:2] if base in ("docker", "podman") and rest[:1] == ["compose"] else rest[:1]
    if base not in ("docker", "podman", "docker-compose", "kubectl") or head[-1:] != ["exec"]:
        return None
    if base == "kubectl" and "--" in rest:
        return rest[rest.index("--") + 1:]
    k = len(head)
    while k < len(rest) and rest[k].startswith("-"):
        k += 2 if rest[k] in EXEC_VALUE else 1
    return rest[k + 1:]


def consumer_of(fields: list[str], c: int) -> tuple[str, list[str]]:
    """Who reads this command's stdin as code, and the words of that reader: "shell", "script" (an interpreter), "sql"
    (psql), or "" (data). A remote or container shell is looked through; `xargs ... sh -c` takes its input as the command
    string."""
    if c >= len(fields):
        return "", []
    inner = remote_command(fields, c)
    if inner is not None:
        if not inner:
            return ("shell" if basename(fields[c]) == "ssh" else ""), fields[c:]
        roles = classify(inner)
        return consumer_of(inner, max((k for k, r in enumerate(roles) if r == "cmd"), default=0))
    base = basename(fields[c])
    if is_shell_reader(fields, c) or base in SHELLS and any(basename(f) == "xargs" for f in fields[:c]) and re.fullmatch(
            r"-[a-zA-Z]*c[a-zA-Z]*", fields[-1]):
        return "shell", fields[c:]
    if is_script_reader(fields, c):
        return "script", fields[c:]
    if base == "psql" and not any(a in ("-c", "--command", "-f", "--file") or a.startswith(("--command=", "--file="))
                                  for a in fields[c + 1:]):
        return "sql", fields[c:]
    return "", fields[c:]


def simulate(words: list[str]) -> str | None:
    """What `echo ...` or `printf ...` writes, when its words are known; None otherwise."""
    if not words or basename(words[0]) not in ("echo", "printf") or any("$" in w for w in words[1:]):
        return None
    if basename(words[0]) == "echo":
        args, nl, esc = words[1:], "\n", False
        while args and re.fullmatch(r"-[neE]+", args[0]):
            nl = "" if "n" in args[0] else nl
            esc = "e" in args[0] or (esc and "E" not in args[0])
            args = args[1:]
        text = " ".join(args)
        return (ansi_c(text) if esc else text) + nl
    if len(words) < 2 or re.search(r"%(?![%sbdi])", words[1].replace("%%", "")):
        return None
    fmt, args, out = ansi_c(words[1]), list(words[2:]), []

    def sub(m: re.Match) -> str:
        if m[0] == "%%":
            return "%"
        value = args.pop(0) if args else ""
        return ansi_c(value) if m[0] == "%b" else value
    while True:
        before = len(args)
        out.append(re.sub(r"%%|%[sbdi]", sub, fmt))
        if not args or len(args) == before:  # bash reuses the format while arguments remain
            return "".join(out)


STRING = re.compile(r'"""(?:\\.|[^\\])*?"""|\'\'\'(?:\\.|[^\\])*?\'\'\'|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|'
                    r'`(?:\\.|[^`\\])*`', re.S)


QUOTE_OP = re.compile(r"(\bq[qw]?|%[qQwW])(?:\((?:[^()\\]|\\.)*\)|\{(?:[^{}\\]|\\.)*\}|\[(?:[^\[\]\\]|\\.)*\]|/(?:[^/\\]|\\.)*/)",
                      re.S)


def literal_body(lit: str) -> str:
    body = lit[3:-3] if lit[:3] in ('"""', "'''") else lit[1:-1]
    return body.replace("\\'", "'").replace('\\"', '"')


def blank_literals(code: str, base: str, an: Analysis) -> str:
    """Interpreter code as the gate reads it: comments dropped; a string literal holding whitespace blanked (it is
    data: `write('the rm -rf guard')`). The command an exec call runs (`os.system('...')`, `subprocess.run([...])`,
    perl's and ruby's backticks) is judged as shell code first."""
    for m in EXEC_CALL.finditer(code):
        rest = code[m.end():]
        if code[m.end() - 1] == "[" or re.match(r"\s*\[", rest):  # a list: its literals are the argv
            end = rest.find("]")
            text = " ".join(literal_body(x[0]) for x in STRING.finditer(rest[:end if end >= 0 else len(rest)]))
        else:
            first = STRING.match(rest.lstrip())
            text = literal_body(first[0]) if first else ""
        if text:
            an.code(text)  # unparseable: the line is judged raw (6.0.0-m8 fix, H2)
    if base in ("perl", "ruby", "php"):
        for m in re.finditer(r"`([^`]*)`|(?:\bqx|%x)\((.*?)\)", code, re.S):
            an.code(m[1] if m[1] is not None else m[2])  # unparseable: the line is judged raw (6.0.0-m8 fix, H2)
        # perl's q() qq() qw() and ruby's %q() %Q() %w(): strings; blanked when they hold whitespace
        code = QUOTE_OP.sub(lambda m: m[0] if not any(ch.isspace() for ch in m[0]) else m[1] + "()", code)
    out, at = [], 0
    hashes = base not in ("node", "nodejs", "deno", "bun")
    for m in STRING.finditer(code):
        head = code[at:m.start()]
        head = re.sub(r"#[^\n]*" if hashes else r"//[^\n]*|/\*.*?\*/", "", head, flags=re.S)
        out.append(head)
        lit = m[0]
        body = lit[3:-3] if lit[:3] in ('"""', "'''") else lit[1:-1]
        if any(ch.isspace() for ch in body):
            out.append(lit[0] + lit[-1] if lit[:3] not in ('"""', "'''") else lit[:3] + lit[-3:])
        else:
            out.append(lit)
        at = m.end()
    out.append(re.sub(r"#[^\n]*" if hashes else r"//[^\n]*|/\*.*?\*/", "", code[at:], flags=re.S))
    return "".join(out)


def view(command: str, shell: str = "bash") -> View:
    """The texts the rules judge for `command` (see the module docstring)."""
    if shell.lower() not in ("bash", "sh", ""):
        return View(command, False, why=f"{shell} commands are judged on their raw text")
    try:
        an = Analysis()
        an.walk(parse(command))
        return View(command, True, an.texts)
    except Exception as exc:  # noqa: BLE001 — TRIPWIRE (6.0.0-m8 fix, review B H1): ANY error here means the raw text
        # is judged; a ValueError from chr() once escaped this function, and the hook's exit 1 let the command run
        return View(command, False, why=str(exc) or type(exc).__name__)


__all__ = ["View", "view"]
