#!/usr/bin/env python3
"""The 6.0.0-m8 fix pass, round 2 (re-check B held the tag again: T371 refused every Bash line with common non-ASCII on
Windows, nested substitutions grew the parser's work exponentially, and forms just past T373 to T376 still passed).
`python maintainer/tests/test_m8d.py`; test_migrate.py's load_tests runs it too, so core-verify carries it."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
