#!/usr/bin/env python3

import json
import sys


TRIGGER_IDS = {
    "auth",
    "permissions",
    "secrets",
    "data-schema",
    "public-contract",
    "production-release",
    "protected-path",
    "cross-cutting-architecture",
    "unresolved-product-decision",
}


def fail(reason: str) -> int:
    print(json.dumps({"schema_version": 1, "status": "error", "reason": reason}))
    return 2


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return fail(f"invalid JSON: {exc}")

    if not isinstance(payload, dict):
        return fail("input must be an object")
    router = payload.get("router")
    assessment = payload.get("assessment")
    if not isinstance(router, dict) or not isinstance(assessment, dict):
        return fail("router and assessment objects are required")

    mechanical = router.get("mechanical_result")
    if router.get("status") != "ok" or mechanical not in {
        "FULL_REQUIRED",
        "NO_MECHANICAL_MATCH",
    }:
        return fail("router result is invalid")
    matches = router.get("matches")
    if not isinstance(matches, list):
        return fail("router matches must be a list")
    for index, match in enumerate(matches):
        if not isinstance(match, dict) or not all(
            isinstance(match.get(key), str) and match[key].strip()
            for key in ("path", "trigger_id", "reason")
        ):
            return fail(f"router match {index} is invalid")
    if (mechanical == "FULL_REQUIRED") != bool(matches):
        return fail("router mechanical_result and matches disagree")
    triggers = assessment.get("triggers")
    if not isinstance(assessment.get("complete"), bool) or not isinstance(triggers, list):
        return fail("assessment.complete and assessment.triggers are required")

    normalized = []
    for index, trigger in enumerate(triggers):
        if not isinstance(trigger, dict):
            return fail(f"assessment trigger {index} must be an object")
        trigger_id = trigger.get("trigger_id")
        evidence_path = trigger.get("evidence_path")
        reason = trigger.get("reason")
        if trigger_id not in TRIGGER_IDS:
            return fail(f"assessment trigger {index} has an unknown trigger_id")
        if not isinstance(evidence_path, str) or not evidence_path.strip():
            return fail(f"assessment trigger {index} needs evidence_path")
        if not isinstance(reason, str) or not reason.strip():
            return fail(f"assessment trigger {index} needs reason")
        normalized.append(
            {
                "trigger_id": trigger_id,
                "evidence_path": evidence_path,
                "reason": reason,
            }
        )

    if not assessment["complete"]:
        result = {
            "schema_version": 1,
            "status": "blocked",
            "mechanical_result": mechanical,
            "semantic_triggers": normalized,
            "final_lane": None,
            "blocked_at": "BLOCKED-AT-lane-assessment",
        }
        print(json.dumps(result, separators=(",", ":")))
        return 20

    final_lane = "full" if mechanical == "FULL_REQUIRED" or normalized else "lightweight"
    result = {
        "schema_version": 1,
        "status": "ok",
        "mechanical_result": mechanical,
        "semantic_triggers": normalized,
        "final_lane": final_lane,
    }
    print(json.dumps(result, separators=(",", ":")))
    return 10 if final_lane == "full" else 0


if __name__ == "__main__":
    raise SystemExit(main())
