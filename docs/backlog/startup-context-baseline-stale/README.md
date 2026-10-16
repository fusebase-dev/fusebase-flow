# startup-context-baseline-stale

**Status:** open — paid by `eight-rule-kernel-and-cards` (6.0.0 WP 5, wave 3), which re-bases the inventory; close it with that commit. **Filed:** 2026-10-15 (v5.11 program, `docs/changes/2026-10-15-v511-consumer-review.md`). **Severity:** low (opt-in diagnostic, not a release gate). **Surface:** `hooks/tests/test-startup-context.sh` (`EXPECTED_SHA`, `EXPECTED_ROWS`).

## Observed

`semantic-inventory-preserved` has been red since T126 (2026-10-08): `EXPECTED_SHA` was last set at `7ab052a` (2026-09-05) while the rule-inventory output changed with WT.FR-27 (T123) and again in v5.11 (T146 WT.FR-27 tail, T156 PO.3, T149 shared-protocols). The other 10 rows pass (Python emulation). `startup-context` is a Diagnostic exclusion (`docs/maintainer-testing.md`), so no release run selects it.

## Ask

Run `rule-inventory.sh` on a quiet host, diff its rows against the 2026-09-05 baseline, confirm every changed row is an intended rule edit (list them by commit), then re-baseline `EXPECTED_SHA`/`EXPECTED_ROWS` in one commit naming those rows. Never re-baseline without the row-by-row diff.
