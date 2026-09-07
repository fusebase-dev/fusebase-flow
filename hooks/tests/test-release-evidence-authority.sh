#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# Parsed workflow assertions own publication safety; editorial wording is reviewed separately.
python_bin="${PYTHON:-python3}"
command -v "$python_bin" >/dev/null 2>&1 || python_bin=python
exec "$python_bin" "$ROOT/hooks/tests/lib/workflow_graph_check.py" --root "$ROOT"
