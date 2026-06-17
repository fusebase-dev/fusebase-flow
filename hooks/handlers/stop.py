#!/usr/bin/env python3
"""Fusebase Flow — stop handler.

Prevents premature "done" / "ready" / "deploy complete" claims when required
artifacts are missing. Reads required-artifacts.yml.

The handler heuristically inspects the agent's final message (event["agent_message"])
for claim phrases and the recent transcript (event["transcript_path"]) for the
signals defined in policies/required-artifacts.yml.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from shared.audit_logger import emit  # noqa: E402
from shared.policy_loader import find_git_root, get_policy  # noqa: E402


CLAIM_PATTERNS = {
    "before_done_claim": [
        r"\bimplementation\s+(complete|done|finished)\b",
        r"\bready\s+(to\s+)?(deploy|merge|ship)\b",
        r"\ball\s+tasks?\s+(complete|done)\b",
        r"\btests?\s+pass(ed)?\b",
    ],
    "before_deploy_complete_claim": [
        r"\bdeploy(ed)?\s+(complete|successful|done)\b",
        r"\bspec\s+is\s+done\b",
        r"\bDRAFT\s*[-—→>]+\s*DONE\b",
        r"\bship(ped)?\b",
    ],
}


# PO activation marker (ASCII, grep-stable). Match the stable prefix, not a
# version number — the PO substitutes the live VERSION at runtime (spec D3).
_PO_MARKER_RE = re.compile(r"\[\[ PO-ACTIVATED \| FuseBase Flow", re.IGNORECASE)
# A PO session is present when the transcript shows the explicit /product-owner
# invocation OR the marker itself (spec D1 — literal scan only; no audit-log
# session correlation, no rule-content inspection).
_PO_INVOCATION_RE = re.compile(r"(?:^|\s)/product-owner\b", re.IGNORECASE)


def _po_activation_warn(transcript_text: str) -> str | None:
    """Dedicated PO-activation check, INDEPENDENT of the done/deploy CLAIM_PATTERNS
    gate (a normal PO first reply carries no claim phrase, so that gate never fires
    for it). Returns a warn reason when a PO session is detected but the activation
    marker is absent; otherwise None. Never denies, never touches the done/deploy
    decision (spec D1/D2)."""
    is_po_session = bool(_PO_INVOCATION_RE.search(transcript_text)) or bool(
        _PO_MARKER_RE.search(transcript_text)
    )
    if is_po_session and not _PO_MARKER_RE.search(transcript_text):
        return (
            "PO session detected but the activation marker is absent. Emit the "
            "activation boot checklist ending with "
            "'[[ PO-ACTIVATED | FuseBase Flow <VERSION> | ... ]]' as the first reply "
            "(warn-only, never blocks)."
        )
    return None


def _signals_from_transcript(transcript_text: str, signal_defs: dict) -> dict[str, bool]:
    """Heuristic signal detection. v0.1 uses pattern definitions from
    required-artifacts.yml signal_definitions; we approximate with regex/keyword
    match. v0.2 will use a more structured transcript."""
    detected: dict[str, bool] = {}
    text = transcript_text.lower()
    detected["diff_summary_present"] = bool(re.search(r"git diff\b|--stat", text))
    detected["lint_clean_marker"] = bool(re.search(r"lint\s+clean|0\s+errors,?\s+0\s+warnings", text))
    detected["typecheck_clean_marker"] = bool(re.search(r"typecheck\s+clean|tsc\s+clean", text))
    detected["gate_report_present"] = bool(re.search(r"gate\s+report|verification\s+gate", text))
    detected["worker_undisturbed_recheck"] = bool(re.search(r"worker[-\s]?undisturbed", text))
    detected["deploy_hash_captured"] = bool(re.search(r"deploy\s+hash|deployed\s+via\s+[a-f0-9]{7,}", text))
    detected["probes_passed"] = bool(re.search(r"\bg-?[mnopq]\b.*pass", text))
    detected["smoke_results_present"] = bool(re.search(r"docs/tmp/handoff/.*-smoke/|smoke\s+results", text))
    detected["rollback_note_present"] = bool(re.search(r"\brollback\b", text))
    detected["docs_commit_present"] = bool(re.search(r"docs\(post-deploy\)|single docs commit", text))
    # Live-user verification cleanup signal (per workflows/live-user-verification.md Step 8).
    # Two indicators: (a) a session_key_or_cookie_use approval artifact was authored
    # for this ticket (raw transcript reference), and (b) the literal cleanup phrase.
    detected["live_user_verification_used"] = bool(
        re.search(r"session_key_or_cookie_use|live-user verification", text)
    )
    detected["cleanup_marker_present"] = bool(
        re.search(r"cleanup:\s*operator can sign out or cookie expires per ttl", text)
    )
    # FR-21 Lightweight-lane marker. When present, the deploy-complete gate drops
    # the Full-lane-only signals (probes table, post-deploy docs commit, smoke
    # artifacts) but KEEPS the safety floor (deploy hash + rollback note).
    detected["lightweight_lane_marker"] = bool(
        re.search(r"change_tier:\s*lightweight|lightweight lane|phase:\s*lightweight", text)
    )
    # FR-22 review-ran marker (artifact-level; never inspects comment content).
    # Either phrase satisfies it; absence is warn-only (decision D1), never a block.
    detected["comment_policy_review_applied"] = bool(
        re.search(
            r"comment-policy review:\s*applied \(fr-22\)"
            r"|comment-policy review:\s*n/a \(fr-22; no code diff\)",
            text,
        )
    )
    return detected


def main() -> int:
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        event = {}

    try:
        root = find_git_root(Path(event.get("cwd") or "."))
    except FileNotFoundError:
        root = None

    agent_message = (event.get("agent_message") or "").lower()
    transcript_text = ""
    tp = event.get("transcript_path")
    if tp:
        try:
            transcript_text = Path(tp).read_text(encoding="utf-8", errors="ignore")
        except OSError:
            transcript_text = ""
    transcript_text = transcript_text + "\n" + (event.get("agent_message") or "")

    # Dedicated PO-activation path (spec D1/D2): runs OUTSIDE the CLAIM_PATTERNS
    # gate so it fires on a PO first reply (which carries no claim phrase). Emits
    # a warn when a PO session lacks the marker; never denies, never changes the
    # done/deploy decision below.
    po_warn = _po_activation_warn(transcript_text)
    if po_warn:
        emit("stop", decision="warn", reason=po_warn, rule_id="po_activation_attested", root=root)
        print(f"[fusebase-flow] WARN: {po_warn}", file=sys.stderr)

    # Decide which gate applies
    triggered_gate: str | None = None
    for gate, patterns in CLAIM_PATTERNS.items():
        if any(re.search(p, agent_message) for p in patterns):
            triggered_gate = gate
            break

    if not triggered_gate:
        emit("stop", decision="allow", reason="no claim phrase detected", root=root)
        sys.stdout.write(json.dumps({"decision": "allow"}))
        return 0

    policy = get_policy("required-artifacts")
    gate_cfg = policy.get(triggered_gate) or {}
    signal_defs = policy.get("signal_definitions") or {}
    detected = _signals_from_transcript(transcript_text, signal_defs)

    lightweight = detected.get("lightweight_lane_marker", False)

    missing: list[str] = []
    for req in gate_cfg.get("required", []) or []:
        sig = req.get("signal")
        if sig:
            optional_smoke = (
                req.get("optional_unless_smoke_specified")
                and not detected.get("smoke_results_present", False)
            )
            optional_live_user = (
                req.get("optional_unless_live_user_verification_used")
                and not detected.get("live_user_verification_used", False)
            )
            # FR-21: a signal flagged optional_when_lightweight is waived on a
            # Lightweight-lane ticket (the marker is in the transcript). The
            # safety-floor signals (deploy hash, rollback) are NOT flagged, so
            # they stay required in both lanes.
            optional_lightweight = bool(req.get("optional_when_lightweight")) and lightweight
            if not detected.get(sig, False) and not (
                optional_smoke or optional_live_user or optional_lightweight
            ):
                missing.append(sig)

    # Recommended (non-blocking) signals (D1): a missing one emits a warn note but
    # is NEVER added to `missing` — it cannot flip the decision to deny.
    missing_recommended: list[str] = []
    for rec in gate_cfg.get("recommended", []) or []:
        sig = rec.get("signal")
        if sig and not detected.get(sig, False):
            missing_recommended.append(sig)
    if missing_recommended:
        warn_reason = (
            f"FR-22 (recommended, non-blocking): claim '{triggered_gate}' missing "
            + ", ".join(missing_recommended)
            + ". Emit 'comment-policy review: applied (FR-22)' (or '… N/A (FR-22; no code diff)')."
        )
        emit(
            "stop",
            decision="warn",
            reason=warn_reason,
            rule_id="FR-22",
            extra={"gate": triggered_gate, "missing_recommended": missing_recommended},
            root=root,
        )

    if missing:
        on_missing = gate_cfg.get("on_missing", "deny")
        decision = on_missing if on_missing in ("deny", "warn") else "deny"
        reason = (
            f"FR-04/05/14: claim '{triggered_gate}' detected but missing required signals: "
            + ", ".join(missing)
            + ". See policies/required-artifacts.yml for the full list."
        )
        emit(
            "stop",
            decision=decision,
            reason=reason,
            rule_id="FR-05",
            extra={"gate": triggered_gate, "missing_signals": missing},
            root=root,
        )
        out = {
            "decision": decision,
            "reason": reason,
            "rule_id": "FR-05",
            "missing_signals": missing,
            "hookSpecificOutput": {
                "hookEventName": "Stop",
                "decision": "block" if decision == "deny" else "warn",
                "reason": reason,
            },
        }
        sys.stdout.write(json.dumps(out))
        return 2 if decision == "deny" else 0

    emit("stop", decision="allow", reason=f"all signals present for {triggered_gate}", root=root)
    sys.stdout.write(json.dumps({"decision": "allow"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
