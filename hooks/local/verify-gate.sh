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

PYTHONIOENCODING=utf-8 python3 "$ROOT/hooks/local/lib/gate_contract_check.py" "$REPORT_FILE" "$CONTRACT" "$POLICY"
