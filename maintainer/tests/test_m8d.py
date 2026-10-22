#!/usr/bin/env python3
"""The 6.0.0-m8 fix pass, round 2 (re-check B held the tag again: T371 refused every Bash line with common non-ASCII on
Windows, nested substitutions grew the parser's work exponentially, and forms just past T373 to T376 still passed).
`python maintainer/tests/test_m8d.py`; test_migrate.py's load_tests runs it too, so core-verify carries it."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import unittest

import test_m7
import test_m8

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
