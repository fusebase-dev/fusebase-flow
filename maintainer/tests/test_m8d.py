#!/usr/bin/env python3
"""The 6.0.0-m8 fix pass, round 2 (re-check B held the tag again: T371 refused every Bash line with common non-ASCII on
Windows, nested substitutions grew the parser's work exponentially, and forms just past T373 to T376 still passed).
`python maintainer/tests/test_m8d.py`; test_migrate.py's load_tests runs it too, so core-verify carries it."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import unittest

import test_m7
import test_m8
import test_m8c

BS = chr(92)  # a backslash, so no escape in this file is read twice
NL = chr(10)


class RawUtf8Stdin(test_m7.Installed):
    """Re-check B HOLD a (introduced by T371): Claude Code (Node's JSON.stringify) and Codex send non-ASCII unescaped,
    as raw UTF-8. The handlers read stdin in Windows' code page (cp1252, surrogateescape), cmd_sha256 then raised on a
    byte cp1252 leaves undefined, and T371's fail-closed turned that crash into a deny: `git commit -m "T1: исправление
    ссылки"`, a closing smart quote and `echo "❌ failed"` were refused. The handlers read stdin as UTF-8 bytes, and a
    lone surrogate becomes U+FFFD, so no hash or audit line raises on any text."""

    ENV = {k: v for k, v in os.environ.items() if k not in ("PYTHONUTF8", "PYTHONIOENCODING")}
    ENV["PYTHONIOENCODING"] = "cp1252:surrogateescape"  # Windows' default for a piped stdin, on every platform

    def hook(self, handler: str, data: bytes) -> tuple[int, dict]:
        """The handler as Claude Code runs it: through run-handler.sh, the call's JSON bytes on stdin."""
        script = f"{self.repo.as_posix()}/hooks/handlers/{handler}.py"
        out = subprocess.run([test_m8.BASH, "hooks/local/run-handler.sh", script], cwd=self.repo, input=data,
                             capture_output=True, timeout=300, env={**self.ENV, "CLAUDE_PROJECT_DIR": str(self.repo)})
        try:
            return out.returncode, json.loads(out.stdout.decode("utf-8", "replace") or "{}")
        except ValueError:
            return out.returncode, {"stdout": out.stdout[-300:], "stderr": out.stderr[-300:]}

    def event(self, command: str, hook: str = "PreToolUse") -> bytes:
        payload = {"session_id": "m8d", "cwd": str(self.repo), "hook_event_name": hook, "tool_name": "Bash",
                   "tool_input": {"command": command}}
        return json.dumps(payload, ensure_ascii=False).encode("utf-8")

    def assert_decides(self, data: bytes, want: tuple) -> None:
        rc, out = self.hook("pre_tool_use", data)
        self.assertEqual((rc, out.get("flow_decision"), out.get("rule_id")), want, out.get("reason", out))

    def test_raw_utf8_commit_messages_and_echo_text_are_allowed_and_a_delete_is_denied(self) -> None:
        for command in ('git commit -m "T1: исправление ссылки"', 'git commit -m "T1: правка"',
                        'git commit -m "T1: fix the “quoted” word"', 'echo "❌ failed"', 'echo "⚠️ check the build"',
                        'git commit -m "T1: café"'):
            with self.subTest(command=command):
                self.assert_decides(self.event(command), (0, "allow", None))
        self.assert_decides(self.event("rm -rf ./сборка"), (2, "deny", "FR-06"))

    def test_bytes_utf8_never_holds_and_a_lone_surrogate_escape_decide_as_well(self) -> None:
        cesu = bytes([0xED, 0xA0, 0x80, 0x20, 0xFF])  # a surrogate's bytes, then a byte no UTF-8 holds
        escape = (BS + "ud800").encode("ascii")  # JSON's own escape of a lone surrogate
        for odd in (cesu, escape):
            with self.subTest(odd=odd):
                self.assert_decides(self.event('echo "X"').replace(b"X", odd), (0, "allow", None))
                self.assert_decides(self.event("rm -rf ./X").replace(b"X", odd), (2, "deny", "FR-06"))

    def test_post_tool_use_logs_the_hash_of_a_raw_utf8_command(self) -> None:
        command = 'git commit -m "T1: исправление “ссылки” ❌"'
        rc, out = self.hook("post_tool_use", self.event(command, "PostToolUse"))
        self.assertEqual((rc, out.get("flow_decision")), (0, "allow"), out)
        lines = (self.repo / "state/audit.log.jsonl").read_text(encoding="utf-8").splitlines()
        want = hashlib.sha256(" ".join(command.split()).encode("utf-8")).hexdigest()
        self.assertIn(want, [json.loads(ln).get("cmd_sha256") for ln in lines], "the twin hashes differ")


class AllowlistDefinition(test_m8c.Gate):
    """Reviewer B's re-check of the cut: the allowlist (T384) matched its reference, not its definition. A runner
    spelled by path, with .exe, quoted or with the heredoc attached was not a runner, so its heredoc body or the echo
    piped into it was blanked; `<<WORD` inside quotes, a comment or a here-string hid the lines after it; and a 40 KB
    line ran past the hook's timeout. A heredoc in `$(...)` inside double quotes is still a heredoc (O2c)."""

    def test_a_runner_in_any_spelling_runs_its_heredoc_and_its_pipe(self) -> None:
        body = NL + "rm -rf /tmp/x" + NL + "EOF"
        self.assert_denied("/bin/bash <<'EOF'" + body, "bash<<'EOF'" + body,
                           "sh<<EOF" + NL + "fusebase deploy" + NL + "EOF",
                           "bash.exe <<'EOF'" + body, '"C:/Program Files/Git/bin/bash.exe" <<' + "'EOF'" + body,
                           '"bash" <<' + "'EOF'" + body,
                           "/usr/bin/ssh host <<'EOF'" + NL + "rm -rf /srv/x" + NL + "EOF",
                           "echo 'rm -rf /tmp/x' | /bin/sh", "echo 'fusebase deploy' | bash.exe",
                           "/bin/echo 'rm -rf /tmp/x' | sh", "echo 'rm -rf /tmp/x' | \"sh\"")

    def test_a_heredoc_marker_in_quotes_a_comment_or_a_here_string_hides_nothing(self) -> None:
        self.assert_denied('git commit -m "doc: explain <<EOF usage"' + NL + "rm -rf /tmp/x",
                           "cat <<< EOF" + NL + "rm -rf /tmp/x", "# see cat <<EOF in the docs" + NL + "fusebase deploy",
                           "grep -n '<<EOF' docs/*.md" + NL + "git push --force origin main")

    def test_a_heredoc_inside_a_quoted_substitution_stays_data_and_a_pipe_ends_at_a_separator(self) -> None:
        self.assert_allowed('git commit -m "$(cat <<' + "'EOF'" + NL + "T1: fusebase deploy needs approval"
                            + NL + "EOF" + NL + ')"',
                            'gh pr create --title x --body "$(cat <<' + "'EOF'" + NL + "- rm -rf guard" + NL + "EOF"
                            + NL + ')"', "echo 'note: rm -rf is denied' | tee notes.md; ssh host ls")

    def test_a_long_line_decides_in_seconds(self) -> None:
        start = time.process_time()
        self.assert_denied("echo 'x' | cat; " * 2500 + "fusebase deploy")
        self.assertLess(time.process_time() - start, 4.9, "6.0.0-m7 decided this 40 KB line in 4.9 s")


class ScanColor(test_m8.Repo):
    """T393 (audit #3): the commit, merge and push secret scans keep the `+` lines of `git diff --cached -U0` and
    `git log -p`. A user's color.ui=always or color.diff=always starts every line with an escape code, and diff.external
    prints its tool's own output, so the scans saw nothing. Each scan, the repository's own copy run as its hook runs
    it, must find a key staged, merged in or pushed under each setting."""

    KEY = "AKIA" + "IOSFODNN7EXAMPLE"  # assembled at run time, so no scanner sees the literal in this file

    def setUp(self) -> None:
        super().setUp()
        for rel in ("hooks", "policies"):
            shutil.copytree(test_m8.CORE / rel, self.repo / rel, ignore=shutil.ignore_patterns("__pycache__"))
        test_m8.git(self.repo, "add", "-A")
        test_m8.git(self.repo, "commit", "-q", "--no-verify", "-m", "flow: the hooks")  # carries pre-merge-commit
        test_m8.write(self.repo, ".git/flow/range-base", test_m8.git(self.repo, "rev-parse", "HEAD").stdout)
        test_m8.git(self.repo, "checkout", "-q", "-b", "side")
        test_m8.write(self.repo, "config/settings.txt", f"aws_access_key_id = {self.KEY}\n")
        test_m8.git(self.repo, "add", "--", "config/settings.txt")
        test_m8.git(self.repo, "commit", "-q", "--no-verify", "-m", "T1: settings")
        self.side = test_m8.git(self.repo, "rev-parse", "HEAD").stdout.strip()
        test_m8.git(self.repo, "checkout", "-q", "main")
        test_m8.write(self.repo, "updates.txt", f"refs/heads/side {self.side} refs/heads/side {'0' * 40}\n")

    def py(self, *argv: str) -> subprocess.CompletedProcess:
        env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
        return subprocess.run([sys.executable, "-S", *argv], cwd=self.repo, env=env, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=600)

    def found(self) -> list[str]:
        """The scans that found the key: the pre-commit's, the pre-merge-commit's and the pre-push's."""
        hits = []
        test_m8.git(self.repo, "checkout", "-q", "side", "--", "config/settings.txt")
        staged = self.py("-c", "import sys; sys.path.insert(0, 'hooks'); from shared.staged_secret_scan import "
                               "_restore_site_packages, staged_added_text; from pathlib import Path; "
                               "_restore_site_packages(); print(staged_added_text(Path('.')))")
        hits += ["pre-commit"] if self.KEY in staged.stdout else []
        test_m8.git(self.repo, "rm", "-q", "-f", "--cached", "--", "config/settings.txt")
        (self.repo / "config/settings.txt").unlink()
        test_m8.git(self.repo, "merge", "--no-ff", "--no-commit", "side")
        hits += ["merge"] if "secret pattern" in self.py("hooks/local/lib/range_check.py", "--merge").stderr else []
        test_m8.git(self.repo, "merge", "--abort")
        pushed = self.py("hooks/local/lib/range_check.py", "--push", "updates.txt", "--remote", "origin")
        return hits + (["push"] if "secret pattern" in pushed.stderr else [])

    def test_each_scan_finds_the_key_whatever_the_users_diff_colour_or_external_diff(self) -> None:
        seen = {}
        for key, value in ((None, None), ("color.ui", "always"), ("color.diff", "always"), ("diff.external", "true")):
            if key:
                test_m8.git(self.repo, "config", key, value)
            seen[f"{key}={value}"] = self.found()
            if key:
                test_m8.git(self.repo, "config", "--unset", key)
        self.assertEqual(seen, {k: ["pre-commit", "merge", "push"] for k in seen})


class SkipMarkers(unittest.TestCase):
    """T394 (audit #4): evidence_rows.ADDED_SKIP and its twin commit_msg.SKIP matched `skip` or `todo` anywhere on an
    added line, so a `// TODO` comment or a test about todos failed a passing test row. Only a test runner's skip or
    todo marker counts."""

    NOT = ("// TODO: tidy", 'it("creates a todo", () => {});', "const todo = makeTodo();",
           "# TODO: cover the 404 path", 'it("can skip onboarding", () => {});')
    REAL = ("test.skip('x', () => {});", "it.skip('x', () => {});", "describe.skip('x', () => {});", "test.todo('x');",
            "it.todo('x');", "test('x', { skip: true }, () => {});", "test('x', { todo: 'later' }, () => {});",
            "t.pass('works # SKIP no db')", "echo 'not ok 2 - x # TODO later'", "ok 3 - x # SKIP",
            "@unittest.skip('slow')", "@pytest.mark.skip(reason='slow')", "        self.skipTest('no db')")

    def test_only_a_test_runners_skip_or_todo_marker_counts(self) -> None:
        import commit_msg
        import evidence_rows
        for name, pattern in (("evidence_rows.ADDED_SKIP", evidence_rows.ADDED_SKIP), ("commit_msg.SKIP", commit_msg.SKIP)):
            self.assertEqual([ln for ln in self.NOT if pattern.search("+" + ln)], [], f"{name}: not skips")
            self.assertEqual([ln for ln in self.REAL if not pattern.search("+" + ln)], [], f"{name}: skips")


if __name__ == "__main__":
    unittest.main(verbosity=2)
