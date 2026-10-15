# rule-inventory-two-part-version

**Status:** open — not scheduled. **Filed:** 2026-10-15 (v5.11 program, `docs/changes/2026-10-15-v511-consumer-review.md`). **Severity:** low (opt-in diagnostic, not a release gate). **Surface:** `hooks/local/rule-inventory.sh` (`norm()`, ~:69), `hooks/tests/test-rule-inventory.sh`.

## Observed

`norm()` normalizes only three-part versions (`vX.Y.Z`) out of the attestation line. Since the two-part `v5.10` attestation (`FLOW_RULES.md` self-attestation), the version leaks into the inventory, so `attestation-version-normalized` and `version-bump-green` are inferred red (not run on the v5.11 host; bash-only). `rule-inventory` is a Diagnostic exclusion, so no release run selects it.

## Ask

Normalize `v<major>.<minor>(.<patch>)?` in `norm()`; add a two-part row to the test; confirm `startup-context-baseline-stale` is re-baselined after, not before, this fix.
