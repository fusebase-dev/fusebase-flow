"""Fusebase Flow — shell_runners: the programs that run code and how a command's words are laid out, for shell_view
(the command gate, 6.0.0-m8 item 7.10).

Moved out of shell_view.py unchanged (6.0.0-m8 fix pass, round 2), so that module stays under its size ceiling: the
shells, interpreters, wrappers, runners and CLIs; the options that take a value; the interpreters' code options; git's
settings and variables that run a command; each word's role (classify); and what echo or printf writes (simulate).
"""
from __future__ import annotations

import re

from .shell_parse import ASSIGN, ansi_c

SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "ash", "mksh", "yash"}
INTERPRETERS = {"python", "python3", "python2", "py", "pypy", "pypy3", "node", "nodejs", "deno", "bun", "perl", "ruby",
                "php"}
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
EXEC_OPTION_VALUE = {"-p", "--package", "-c", "--call", "-w", "--workspace", "--prefix", "--filter"}  # npm exec / npx
# The letters that name an interpreter's code option (-c, perl -e, node -e/-p); any other interpreter: c, e, E, p, r.
CODE_FLAGS = {"python": "c", "python3": "c", "python2": "c", "py": "c", "pypy": "c", "pypy3": "c", "node": "ep",
              "nodejs": "ep", "bun": "e", "perl": "eE", "ruby": "e", "php": "r"}
EXEC_VALUE = {"-e", "--env", "-u", "--user", "-w", "--workdir", "--env-file", "--detach-keys", "--index", "-c",
              "--container", "-n", "--namespace", "-f", "--filename"}  # docker/kubectl exec options with a value
STDIN = {"-", "/dev/stdin", "/dev/fd/0", "/proc/self/fd/0"}  # a script path that is the shell's own stdin
BARE = re.compile(r"[A-Za-z][\w.:-]*")


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
                k = exec_options(fields, k + 2)
                continue
            if nxt in RUNNER_OWN or nxt.startswith("-"):
                break
            k += 1
            continue
        if base == "npm" and k + 1 < len(fields) and fields[k + 1] in ("exec", "x") or base == "npx":
            k = exec_options(fields, k + (1 if base == "npx" else 2))
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


def exec_options(fields: list[str], k: int) -> int:
    """The index of the command after npm exec's, npx's or pnpm dlx's own options (`--`, --yes, --package=x, -p x)."""
    while k < len(fields) and fields[k].startswith("-"):
        k += 1
        if fields[k - 1] == "--":
            break
        if fields[k - 1] in EXEC_OPTION_VALUE and k < len(fields):
            k += 1
    return k


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
    if any(code_flag(a, basename(fields[c]).lower()) is not None for a in args):
        return False
    positional = [a for a in args if a == "-" or not a.startswith("-")]
    return not positional or positional[0] in STDIN


def code_flag(word: str, base: str) -> str | None:
    """An interpreter's code option: "" when the code is the next word (-c, -Sc, perl -ne, --eval), the code itself when
    attached (-cCODE, perl -eCODE, --eval=CODE), None for any other word (review B H4)."""
    if word in ("--eval", "--print"):
        return ""
    if word.startswith(("--eval=", "--print=")):
        return word.partition("=")[2] or None
    if not word.startswith("-") or word.startswith("--"):
        return None
    letters = CODE_FLAGS.get(base.lower(), "ceEpr")
    for i, ch in enumerate(word[1:], 1):
        if ch in letters:
            return word[i + 1:]
        if not ch.isalpha():
            return None
    return None


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
