#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path


def load_evidence(path: Path):
    spec = importlib.util.spec_from_file_location("fusebase_flow_validator_evidence", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("validator evidence module cannot be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--lint", default="")
    parser.add_argument("--typecheck", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    runner = Path(__file__).resolve()
    evidence_path = runner.with_name("validator-evidence.py")
    try:
        evidence = load_evidence(evidence_path)
        root = evidence.canonical_root(args.root)
        receipt = evidence.run_validators(root, args.lint, args.typecheck, runner)
        if receipt is not None:
            print(f"[run-validators] authentic exact-state receipt: {receipt}")
        return 0
    except Exception as exc:
        print(f"[run-validators] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
