#!/usr/bin/env bash
# WP6-a: the 6.0.0 skill drafts carry the named 5.11 text (hooks/tests/fixtures/skill_carry_anchors.py).
# Opt-in (docs/maintainer-testing.md, Diagnostic exclusions): FF_ONLY=skill-carry. Needs the v5.11 tag.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
exec "${PYTHON:-python3}" -B "$HERE/fixtures/skill_carry_anchors.py" \
  --root "$ROOT/docs/changes/2026-10-16-v600-wp6-skills" --repo "$ROOT"
