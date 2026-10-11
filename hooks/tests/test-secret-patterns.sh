#!/usr/bin/env bash
# T133: hooks/tests/fixtures/secret_patterns_matrix.py
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${PYTHON:-python3}" -B "$ROOT/hooks/tests/fixtures/secret_patterns_matrix.py"
