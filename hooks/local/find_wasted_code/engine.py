"""Orchestrator: run every rule over the scan set, collect findings + coverage.

Deterministic: iterates inv.scan_files (already sorted), rules append in a fixed
order, the report sorts again. No clock, no randomness.
"""
from __future__ import annotations

import hashlib

from .model import Coverage
from .rules_refs import scan_w1, scan_w3
from .rules_links import scan_w2, _HeadingCache
from .rules_config import scan_w4
from .rules_swallow import baseline_py, baseline_sh


def index_identity(inv) -> str:
    blob = "\n".join(sorted(inv.files)).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()[:12]


def _is_settings_example(rel_low) -> bool:
    base = rel_low.rsplit("/", 1)[-1]
    return base.endswith(".json.example") and "settings" in base


def run(inv):
    cov = Coverage()
    findings = []
    hcache = _HeadingCache(inv)
    for rel in inv.scan_files:
        text, note = inv.read_text(rel)
        if text is None:
            cov.skip(rel, note)
            continue
        if note:
            cov.skip(rel, note)   # e.g. invalid-utf8-replaced — still scanned
        cov.scanned += 1
        low = rel.lower()
        if low.endswith((".md", ".markdown")):
            findings += list(scan_w1(inv, cov, rel, text))
            findings += list(scan_w2(inv, cov, rel, text, hcache))
            findings += list(scan_w3(inv, cov, rel, text))
        if low.endswith((".sh", ".bash")):
            findings += list(scan_w3(inv, cov, rel, text))
            baseline_sh(cov, rel, text)
        if low.endswith(".py"):
            baseline_py(cov, rel, text)
        if _is_settings_example(low):
            findings += list(scan_w4(inv, cov, rel, text))
    return findings, cov
