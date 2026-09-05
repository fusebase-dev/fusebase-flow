#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
from typing import Callable


BEGIN = b"<!-- CUSTOM:SKILL:BEGIN -->"
END = b"<!-- CUSTOM:SKILL:END -->"
PRESERVE_BEGIN = b"<!-- FLOW:PRESERVE:BEGIN"
PRESERVE_END = b"<!-- FLOW:PRESERVE:END -->"


class OverlayError(ValueError):
    pass


def _line_matches(data: bytes, values: tuple[bytes, ...]) -> list[tuple[int, int]]:
    matches: list[tuple[int, int]] = []
    offset = 0
    for line in data.splitlines(keepends=True):
        body = line.rstrip(b"\r\n")
        if body in values:
            matches.append((offset, offset + len(body)))
        offset += len(line)
    return matches


def _marker_pairs(data: bytes) -> list[tuple[int, int]]:
    events = sorted(
        [(match.start(), True) for match in re.finditer(re.escape(BEGIN), data)]
        + [(match.start(), False) for match in re.finditer(re.escape(END), data)]
    )
    pairs: list[tuple[int, int]] = []
    opened: int | None = None
    for position, is_begin in events:
        if is_begin:
            if opened is not None:
                raise OverlayError("nested CUSTOM:SKILL marker")
            opened = position
        else:
            if opened is None:
                raise OverlayError("CUSTOM:SKILL END without BEGIN")
            pairs.append((opened, position + len(END)))
            opened = None
    if opened is not None:
        raise OverlayError("CUSTOM:SKILL BEGIN without END")
    return pairs


def _legacy_start(data: bytes, heading_start: int) -> int:
    lines: list[tuple[int, bytes]] = []
    offset = 0
    for line in data.splitlines(keepends=True):
        lines.append((offset, line.rstrip(b"\r\n")))
        offset += len(line)
    heading_index = next(index for index, row in enumerate(lines) if row[0] == heading_start)
    index = heading_index - 1
    while index >= 0 and not lines[index][1].strip():
        index -= 1
    if index >= 0 and lines[index][1].strip() == b"---":
        return lines[index][0]
    return heading_start


def _owned_span(
    data: bytes,
    headings: tuple[bytes, ...],
    *,
    allow_legacy: bool,
) -> tuple[int, int, bool]:
    heading_matches = _line_matches(data, headings)
    if len(heading_matches) != 1:
        raise OverlayError(f"expected one Flow heading, found {len(heading_matches)}")
    heading_start, _ = heading_matches[0]
    pairs = _marker_pairs(data)
    owners = [(start, end) for start, end in pairs if start < heading_start < end]
    if len(owners) == 1:
        return owners[0][0], owners[0][1], False
    if owners or not allow_legacy:
        raise OverlayError("Flow heading is outside one owned marker span")
    return _legacy_start(data, heading_start), len(data), True


def _newline_style(data: bytes) -> bytes:
    crlf = data.count(b"\r\n")
    lf = data.count(b"\n") - crlf
    return b"\r\n" if crlf > lf else b"\n"


def _convert_newlines(data: bytes, newline: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n").replace(b"\n", newline)


def _preserve_span(block: bytes) -> tuple[int, int] | None:
    starts = [match.start() for match in re.finditer(re.escape(PRESERVE_BEGIN), block)]
    ends = [match.start() for match in re.finditer(re.escape(PRESERVE_END), block)]
    if not starts and not ends:
        return None
    if len(starts) != 1 or len(ends) != 1:
        raise OverlayError("ambiguous FLOW:PRESERVE markers")
    begin_close = block.find(b"-->", starts[0])
    if begin_close < 0 or ends[0] <= begin_close:
        raise OverlayError("unbalanced FLOW:PRESERVE markers")
    return starts[0], ends[0] + len(PRESERVE_END)


def _legacy_preserve(block: bytes, template_preserve: bytes, newline: bytes) -> bytes | None:
    headings = _line_matches(block, (b"### Project-specific values",))
    if len(headings) != 1:
        return None
    start = headings[0][0]
    footer = block.find(b"project-specific rules win.", start)
    if footer < 0:
        raise OverlayError("legacy project values have no recognized footer")
    end = block.find(b"\n", footer)
    end = len(block) if end < 0 else end
    begin_close = template_preserve.find(b"-->")
    if begin_close < 0:
        raise OverlayError("template FLOW:PRESERVE BEGIN is malformed")
    begin_marker = template_preserve[: begin_close + 3]
    return begin_marker + newline + block[start:end] + newline + PRESERVE_END


def _effective_template(live: bytes, template: bytes, newline: bytes) -> bytes:
    converted = _convert_newlines(template, newline)
    template_span = _preserve_span(converted)
    live_span = _preserve_span(live)
    if template_span is None:
        return converted
    replacement = live[slice(*live_span)] if live_span else _legacy_preserve(
        live, converted[slice(*template_span)], newline
    )
    if replacement is None:
        return converted
    return converted[: template_span[0]] + replacement + converted[template_span[1] :]


def replace_overlay(
    target: Path,
    template: Path,
    heading: str,
    legacy_headings: tuple[str, ...],
    backup: Path,
    *,
    replace_fn: Callable[[str, str], None] = os.replace,
    validate_only: bool = False,
) -> str:
    original = target.read_bytes()
    template_bytes = template.read_bytes()
    canonical = heading.encode("utf-8")
    aliases = tuple(value.encode("utf-8") for value in legacy_headings)
    start, end, legacy = _owned_span(
        original, (canonical, *aliases), allow_legacy=True
    )
    template_start, template_end, template_legacy = _owned_span(
        template_bytes, (canonical,), allow_legacy=False
    )
    if template_legacy:
        raise OverlayError("template cannot use a marker-less span")
    live = original[start:end]
    effective = _effective_template(
        live,
        template_bytes[template_start:template_end],
        _newline_style(original),
    )
    updated = original[:start] + effective + original[end:]
    if not legacy and updated == original:
        return "current"
    if validate_only:
        return "refresh-needed"

    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(target, backup)
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{target.name}.flow-", dir=target.parent
    )
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(updated)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_name, stat.S_IMODE(target.stat().st_mode))
        replace_fn(temp_name, str(target))
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise
    return "refreshed"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path)
    parser.add_argument("template", type=Path)
    parser.add_argument("heading")
    parser.add_argument("backup", type=Path)
    parser.add_argument("--legacy-heading", action="append", default=[])
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    try:
        result = replace_overlay(
            args.target,
            args.template,
            args.heading,
            tuple(args.legacy_heading),
            args.backup,
            validate_only=args.validate_only,
        )
    except (OSError, OverlayError) as exc:
        print(f"overlay replacement refused: {exc}", file=os.sys.stderr)
        return 2
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
