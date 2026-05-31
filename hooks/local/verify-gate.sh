#!/usr/bin/env bash
# Fusebase Flow — verify-gate
# Verifies a pasted gate-report or deploy-report file against gate-contracts.yml.
# Useful when reviewing handoff outputs offline.
#
# Usage:
#   bash hooks/local/verify-gate.sh <report-file> <contract-name>
# Example:
#   bash hooks/local/verify-gate.sh /tmp/gate.txt gate_report

set -euo pipefail

REPORT_FILE="${1:-}"
CONTRACT="${2:-gate_report}"

if [ -z "$REPORT_FILE" ] || [ ! -f "$REPORT_FILE" ]; then
    echo "Usage: $0 <report-file> [contract-name]" >&2
    echo "Contract names: gate_report, deploy_report, smoke_report, code_review_report, security_review_report" >&2
    exit 2
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
POLICY="$ROOT/policies/gate-contracts.yml"

if [ ! -f "$POLICY" ]; then
    echo "Policy not found: $POLICY" >&2
    exit 1
fi

python3 - "$REPORT_FILE" "$CONTRACT" <<'PY'
import sys, yaml, re
from pathlib import Path

report_file, contract_name = Path(sys.argv[1]), sys.argv[2]
policy = yaml.safe_load(Path("policies/gate-contracts.yml").read_text())
contract = policy.get(contract_name)
if not contract:
    print(f"[verify-gate] unknown contract: {contract_name}", file=sys.stderr)
    sys.exit(2)

text = report_file.read_text(encoding="utf-8")
required = contract.get("required_fields") or {}
missing = []

for field, spec in required.items():
    field_label = field.replace("_", " ")
    pattern = field.replace("_", "[ _]?")
    found = bool(re.search(pattern, text, flags=re.IGNORECASE))
    if not found:
        # try alt: contains_phrase clue
        cp = (spec or {}).get("contains_phrase") if isinstance(spec, dict) else None
        if cp and cp in text:
            found = True
    if not found:
        missing.append(field_label)

if missing:
    print(f"[verify-gate] {contract_name} INCOMPLETE — missing: {', '.join(missing)}")
    sys.exit(1)
print(f"[verify-gate] {contract_name} all required fields present (lightweight check; full validation in code-review skill)")
PY
