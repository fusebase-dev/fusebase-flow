from __future__ import annotations

import hashlib
import importlib.util
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check(source: Path) -> tuple[str, str]:
    preflight = load(source / "hooks/local/lib/recovery-preflight.py", "noop_preflight")
    verifier = load(source / "hooks/local/lib/recovery-verify.py", "noop_verifier")
    helper = source / "hooks/local/fusebase-flow-overlays/overlay-block-replace.py"
    overlay = load(helper, "noop_overlay")
    passed = []

    def record(name: str, good: bool) -> None:
        assert good, name
        passed.append(f"PASS: T131 {name}")

    with tempfile.TemporaryDirectory(prefix="flow-overlay-noop-") as raw:
        root = Path(raw)
        directory = root / "hooks/local/fusebase-flow-overlays"
        directory.mkdir(parents=True)
        templates = {}
        for name, template in (("AGENTS.md", "agents-md-overlay.md"),
                               ("CLAUDE.md", "claude-md-overlay.md")):
            shutil.copyfile(source / "hooks/local/fusebase-flow-overlays" / template,
                            directory / template)
            templates[name] = (directory / template).read_bytes().replace(b"\r\n", b"\n")
        shutil.copyfile(helper, directory / helper.name)
        prefix = b"provider line\n" * 200

        def reset() -> None:
            for name, content in templates.items():
                (root / name).write_bytes(prefix + content)

        def plan(refresh: bool = False) -> dict:
            return {"surfaces": verifier.SURFACES, "plan_id": "overlay-noop",
                    "options": {"wire_hooks": False, "restore_git_hooks": False,
                                "refresh_overlays": refresh},
                    "targets": [], "overlays": preflight.validate_overlays(root, refresh)}

        def row(value: dict, name: str) -> dict:
            return next(item for item in value["overlays"] if item["surface"] == name)

        for name, content in templates.items():
            reset()
            lines = content.split(b"\n")
            begin = lines.index(overlay.BEGIN)
            end = lines.index(overlay.END)
            changed = [index for index in range(begin + 1, end)]
            preserve = [i for i, line in enumerate(lines) if line.startswith(overlay.PRESERVE_BEGIN)]
            if preserve:
                preserve_end = lines.index(overlay.PRESERVE_END)
                changed = [i for i in changed if not preserve[0] <= i <= preserve_end]
            for index in changed:
                lines[index] += b"\r"
            mixed = prefix + b"\n".join(lines)
            target = root / name
            target.write_bytes(mixed)
            value = plan()
            expected_drift = (f"eol-only:{len(changed)}:"
                              f"{201 + changed[0]}-{201 + changed[-1]}")
            record(f"{name}-eol-drift-exact-count-and-lines",
                   row(value, name)["drift"] == expected_drift)
            record(f"{name}-noop-pin-and-read-only",
                   row(value, name)["expected_sha256"] == hashlib.sha256(mixed).hexdigest()
                   and target.read_bytes() == mixed and not verifier.verify(root, value)["failures"])
            refreshed, _ = preflight.expected_overlay_bytes(
                mixed, (directory / ("agents-md-overlay.md" if name == "AGENTS.md"
                                     else "claude-md-overlay.md")).read_bytes(), overlay,
                (next(line for line in content.split(b"\n") if line.startswith(b"## ")),),
                next(line for line in content.split(b"\n") if line.startswith(b"## ")))
            refresh_plan = plan(True)
            record(f"{name}-refresh-pin-unchanged",
                   row(refresh_plan, name)["expected_sha256"] == hashlib.sha256(refreshed).hexdigest()
                   and row(refresh_plan, name)["drift"] == "")
            target.write_bytes(refreshed)
            record(f"{name}-refresh-verifies", not verifier.verify(root, refresh_plan)["failures"])

        reset()
        target = root / "AGENTS.md"
        lines = templates["AGENTS.md"].split(b"\n")
        index = next(i for i, line in enumerate(lines) if line.startswith(b"### Session"))
        lines[index] += b" drift"
        drifted = prefix + b"\n".join(lines)
        target.write_bytes(drifted)
        value = plan()
        record("content-drift-first-normalized-line", row(value, "AGENTS.md")["drift"] == f"content:{201 + index}")
        record("content-noop-verifies", not verifier.verify(root, value)["failures"])
        target.write_bytes(drifted.replace(b"provider line", b"external mutation", 1))
        record("post-plan-mutation-still-uncertain",
               verifier.verify(root, value)["uncertain_surfaces"] == ["agents_overlay"])

        for name, aliases in (
            ("AGENTS.md", ("## Fusebase Flow — workflow lifecycle overlay",)),
            ("CLAUDE.md", ("## FuseBase Flow — additional rules (overlay)",
                           "## Fusebase Flow — additional rules (overlay)")),
        ):
            canonical = next(line for line in templates[name].split(b"\n") if line.startswith(b"## "))
            for alias in aliases:
                reset()
                old = alias.encode()
                original = (prefix + templates[name]).replace(canonical, old).replace(b"\n", b"\r\n")
                target = root / name
                target.write_bytes(original)
                value = plan()
                expected = original.replace(old + b"\r\n", canonical + b"\r\n")
                result = subprocess.run([sys.executable, "-B", str(helper), "--migrate-heading",
                                         str(target), alias, canonical.decode()],
                                        capture_output=True, timeout=20)
                record(f"{name}-{alias}-heading-only-crlf",
                       result.returncode == 0 and target.read_bytes() == expected
                       and expected.count(b"\r") == original.count(b"\r"))
                record(f"{name}-{alias}-migration-pin-verifies",
                       row(value, name)["expected_sha256"] == hashlib.sha256(expected).hexdigest()
                       and not verifier.verify(root, value)["failures"])

            reset()
            original = b"prose " + canonical + b" suffix\n" + templates[name].replace(canonical, aliases[-1].encode())
            (root / name).write_bytes(original)
            value = plan()
            record(f"{name}-canonical-substring-suppresses-migration",
                   row(value, name)["expected_sha256"] == hashlib.sha256(original).hexdigest()
                   and not verifier.verify(root, value)["failures"])
            if len(aliases) == 2:
                original = b"prose " + aliases[0].encode() + b" suffix\n" + templates[name].replace(canonical, aliases[1].encode())
                (root / name).write_bytes(original)
                value = plan()
                record("CLAUDE-first-alias-substring-precedence",
                       row(value, name)["expected_sha256"] == hashlib.sha256(original).hexdigest()
                       and not verifier.verify(root, value)["failures"])

        old, new = b"old heading", b"new heading"
        for data in (old, old + b"\n", old + b"\r\n", b"prefix\n" + old + b"\r\nsuffix",
                     old + b"\n" + old + b"\r\n"):
            migrated, count = overlay.migrate_heading_lines(data, old, new)
            record(f"heading-preserves-all-other-bytes-{len(passed)}",
                   migrated == data.replace(old, new) and count == data.count(old))
        unchanged = b"prefix old heading\nold heading suffix\nold heading\r\r\n"
        record("heading-matches-only-exact-lf-or-crlf-lines",
               overlay.migrate_heading_lines(unchanged, old, new) == (unchanged, 0))
        target.write_bytes(unchanged)
        timestamp = target.stat().st_mtime_ns
        result = subprocess.run([sys.executable, "-B", str(helper), "--migrate-heading",
                                 str(target), old.decode(), new.decode()], capture_output=True, timeout=20)
        record("migration-cli-no-match-rc1-no-write",
               result.returncode == 1 and target.read_bytes() == unchanged
               and target.stat().st_mtime_ns == timestamp)
        result = subprocess.run([sys.executable, "-B", str(helper), "--migrate-heading",
                                 str(root / "missing"), old.decode(), new.decode()],
                                capture_output=True, timeout=20)
        record("migration-cli-error-rc2", result.returncode == 2)
        target.write_bytes(old)
        with patch.object(overlay.os, "replace", side_effect=OSError("fixture refusal")):
            try:
                overlay.migrate_heading_file(target, old.decode(), new.decode())
            except OSError:
                pass
            else:
                raise AssertionError("atomic replacement failure accepted")
        record("atomic-failure-keeps-original-and-cleans-temp",
               target.read_bytes() == old and not list(root.glob(f".{target.name}.flow-*")))
    return "\n".join([*passed, f"[overlay-noop] {len(passed)}/{len(passed)} PASS"]), ""
