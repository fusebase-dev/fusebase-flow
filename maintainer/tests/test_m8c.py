#!/usr/bin/env python3
"""The 6.0.0-m8 fix pass (review B held the tag: the command gate let through commands 6.0.0-m7 denied).
`python maintainer/tests/test_m8c.py`; test_migrate.py's load_tests runs it too, so core-verify carries it."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

CORE = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(CORE / "hooks")]
from shared import shell_view  # noqa: E402
from shared.command_policy import evaluate  # noqa: E402
from shared.policy_loader import reset_cache  # noqa: E402

BS = chr(92)  # a backslash, so no escape in this file is read twice


def decision(command: str) -> str:
    reset_cache()
    return evaluate(command, root=CORE).decision


class Gate(unittest.TestCase):
    def assert_denied(self, *commands: str) -> None:
        self.assertEqual([c for c in commands if decision(c) != "deny"], [], "allowed, though the line runs it")

    def assert_allowed(self, *commands: str) -> None:
        self.assertEqual([c for c in commands if decision(c) != "allow"], [], "denied, though the words are data")


class FailsClosed(Gate):
    """Review B H1: an error in the parser let the command run. view() caught three exception types, chr() raised on
    `$'\\U00110000'`, and the hook's exit 1 is non-blocking (run-handler.sh). Any error now means the raw text is
    judged, and the hook prints a decision on every path."""

    def test_any_parser_error_judges_the_raw_text(self) -> None:
        with mock.patch.object(shell_view, "parse", side_effect=KeyError("an error the parser never planned for")):
            self.assert_denied("rm -rf /tmp/h1-monkeypatched")
            self.assert_allowed("ls /tmp/h1-monkeypatched")

    def test_a_code_point_past_unicode_judges_the_line(self) -> None:
        self.assert_denied(f"echo $'{BS}U00110000'; rm -rf /tmp/x", f"X=$'{BS}UFFFFFFFF' fusebase deploy",
                           f"echo $'{BS}U7FFFFFFF' && git commit --no-verify -m x")
        self.assert_allowed(f"echo $'{BS}U00110000'")

    def test_the_hook_prints_a_deny_when_it_fails(self) -> None:
        spec = importlib.util.spec_from_file_location("pre_tool_use_h1", CORE / "hooks/handlers/pre_tool_use.py")
        handler = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(handler)
        with tempfile.TemporaryDirectory() as folder:  # no git root: nothing is written
            event = json.dumps({"tool_name": "Bash", "cwd": folder, "tool_input": {"command": "ls"}})
            out = io.StringIO()
            with mock.patch.object(handler, "evaluate_command", side_effect=RuntimeError("an error on the way")), \
                    mock.patch("sys.stdin", io.StringIO(event)), contextlib.redirect_stdout(out), \
                    contextlib.redirect_stderr(io.StringIO()):
                rc = handler.main()
        self.assertEqual(rc, 2)
        self.assertEqual(json.loads(out.getvalue())["flow_decision"], "deny")


class CodeTheParserReads(Gate):
    """Review B H2: code bash runs that the parser read but never checked: the body after `function NAME`, a command
    substitution inside $(( )), (( )) or a ${x/a/b} argument, backticks in an unquoted heredoc, `cat - <<EOF | sh`,
    `bash /dev/stdin`, a variable `read` fills from a here-string, and an exec call's string that does not parse."""

    def test_the_body_after_function_name_is_a_command(self) -> None:
        self.assert_denied("function f { rm -rf /tmp/x; }; f", "function ship { fusebase deploy; }; ship")
        self.assert_allowed("function check { grep -n 'rm -rf' README.md; }; check")

    def test_a_substitution_inside_arithmetic_or_a_parameter_argument_runs(self) -> None:
        self.assert_denied("echo $(( $(rm -rf /tmp/x) + 1 ))", "(( $(rm -rf /tmp/x) ))",
                           "x=abc; echo ${x/a/$(rm -rf /tmp/x)}", "echo ${x#$(rm -rf /tmp/x)}")
        self.assert_allowed("echo $(( 1 + 2 ))", "x=abc; echo ${x/a/b}")

    def test_backticks_in_an_unquoted_heredoc_and_stdin_shells_run(self) -> None:
        nl = chr(10)
        self.assert_denied(f"cat <<EOF{nl}`rm -rf /tmp/x`{nl}EOF", f"git commit -F - <<EOF{nl}T1: `fusebase deploy`{nl}EOF",
                           f"cat - <<EOF | sh{nl}rm -rf /tmp/x{nl}EOF", f"bash /dev/stdin <<EOF{nl}rm -rf /tmp/x{nl}EOF",
                           "read X <<< 'rm -rf /tmp/x'; $X")
        self.assert_allowed(f"cat > notes.md <<'EOF'{nl}Run `rm -rf build` by hand.{nl}EOF",
                            "git commit -m 'T1: `fusebase deploy` is gated'")

    def test_an_exec_call_string_that_does_not_parse_is_judged_raw(self) -> None:
        self.assert_denied("python3 -c \"import os; os.system('rm -rf /tmp/x \\\"')\"")


class ArgumentsThatRun(Gate):
    """Review B H3, the programs whose argument is a shell command: trap's, git's `submodule foreach`, `rebase -x`, a
    `!` alias, core.pager and core.sshCommand, and GIT_SSH_COMMAND (CODE_ARGS beside WRAPPERS)."""

    def test_trap_and_git_run_their_argument(self) -> None:
        self.assert_denied("trap 'rm -rf \"$tmp\"' EXIT", "trap \"rm -rf /tmp/x\" EXIT INT",
                           "git submodule foreach 'git reset --hard'", "git submodule foreach --recursive 'git clean -fdx'",
                           "git rebase --exec 'rm -rf /tmp/x' HEAD~1", "git rebase -x 'fusebase deploy' HEAD~1",
                           "git -c alias.x='!rm -rf /tmp/x' x", "git config alias.x '!fusebase deploy' && git x",
                           "git -c core.pager='rm -rf /tmp/x' log", "git -c core.sshCommand='fusebase deploy' fetch",
                           "GIT_SSH_COMMAND='rm -rf /tmp/x' git fetch")
        self.assert_allowed("trap 'echo done' EXIT", "git submodule foreach 'git status'",
                            "git rebase -x 'npm test' HEAD~3", "git -c core.pager=less log",
                            "GIT_SSH_COMMAND='ssh -i ~/.ssh/deploy_key' git fetch", "git config alias.st status")


class StdinThatRuns(Gate):
    """Review B H3, the readers of stdin: a remote or container shell behind ssh, docker exec, kubectl exec or docker
    compose exec; psql, whose input is judged where a rule names psql; and `xargs ... sh -c`, whose input is the
    command string."""

    def test_a_remote_or_container_shell_and_psql_run_what_they_read(self) -> None:
        nl = chr(10)
        self.assert_denied(f"ssh deploy@host <<'EOF'{nl}rm -rf /srv/app/releases{nl}EOF",
                           f"ssh deploy@host bash -s <<'EOF'{nl}rm -rf /srv/app/releases{nl}EOF",
                           f"docker exec -i app sh <<'EOF'{nl}rm -rf /data/uploads{nl}EOF",
                           f"kubectl exec -i pod -- sh <<'EOF'{nl}rm -rf /data{nl}EOF",
                           "echo 'rm -rf /srv/app' | ssh host", "echo 'rm -rf /data' | docker exec -i app sh",
                           "docker compose exec -T db psql -U app <<< 'DROP TABLE users;'", "psql <<< 'TRUNCATE users'",
                           f"psql \"$DB\" <<'SQL'{nl}DROP TABLE users;{nl}SQL", "echo 'rm -rf /tmp/x' | xargs -0 sh -c")
        self.assert_allowed("ssh host 'ls -la /srv/app'", "cat notes.md | ssh host 'cat > notes.md'",
                            "docker exec app ls /data", f"psql \"$DB\" <<'SQL'{nl}SELECT count(*) FROM users;{nl}SQL",
                            "echo 'a b' | xargs -n1 echo")


class UnknownRunners(Gate):
    """Review B H3, the subcommand slot: the word after any program was taken for its subcommand, so `fakeroot rm -rf`
    and `proxychains4 fusebase deploy` passed, and so did `npm exec -- fusebase deploy`. It now holds for known CLIs."""

    def test_an_unknown_programs_first_argument_may_be_a_command(self) -> None:
        self.assert_denied("fakeroot rm -rf /tmp/x", "proxychains4 fusebase deploy", "npm exec -- fusebase deploy",
                           "npm exec --yes fusebase deploy", "npm x --yes fusebase deploy",
                           "npm exec -- prisma migrate deploy")
        self.assert_allowed("npm rm lodash", "git rm old.txt", "docker rm my-container", "helm rm my-release",
                            "cargo rm serde", "pnpm remove lodash", "make clean")


class OptionForms(Gate):
    """Review B H4, option parsing: `npx -c` and `npm exec -c` run a command line; an interpreter's code option may be
    combined (`-Sc`, perl's `-ne`) or carry its code attached (`-c"..."`, `-e'...'`, `--eval=...`)."""

    def test_exec_c_and_attached_or_combined_code_options_are_code(self) -> None:
        self.assert_denied("npx -c 'fusebase deploy'", "npm exec -c 'fusebase deploy'",
                           "python3 -c\"import os; os.system('rm -rf /tmp/x')\"",
                           "python3 -Sc \"import os; os.system('rm -rf /tmp/x')\"",
                           "perl -ne 'system(\"rm -rf /tmp/x\")' file", "perl -e'system(\"rm -rf /tmp/x\")'",
                           "node --eval=\"require('child_process').execSync('rm -rf /tmp/x')\"")
        self.assert_allowed("npm exec -- eslint .", "npx -y prettier --check .",
                            "python3 -c \"print('the rm -rf guard')\"",
                            "node --eval=\"console.log('fusebase deploy notes')\"")


if __name__ == "__main__":
    unittest.main(verbosity=2)
