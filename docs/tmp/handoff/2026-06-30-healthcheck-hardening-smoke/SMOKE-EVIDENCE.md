# Ticket smoke evidence — healthcheck-baseline-and-custom-flag-hardening (v3.30.1)

Advisory-only invariant. Real merge writer (settings-json-merge.py --baseline-out)
+ real reporter (check-cli-flow-conflicts.sh) exercised on complete fixtures.

## Operator-visible outcome — receipt written by the REAL merge
receipt-after-wire.json: 3 CLI Stop hooks, stop.py EXCLUDED:
  run-lint-on-stop.sh, run-typecheck-on-stop.sh, quality-check-apps.js

## Ground-truth diagnostics (real reporter verdict + exit), from ticket-smoke-0259-full.log
- acm1-receipt-written-on-real-merge          PASS  (AC-M1 receipt write)
- acm1-receipt-lists-cli-hooks-only           PASS  (excludes stop.py)
- acm1-receipt-durable-across-noop            PASS  (survives 2nd no-op)
- acm2-receipt-dropped-hook-is-baseline-drift PASS  (-> CLI_STOP_BASELINE_DRIFT, NOT SHARED_MERGE_DRIFT)
- acm2-verdict-healthy                        PASS  (verdict HEALTHY)
- acm2-exit-0                                 PASS  (exit 0, not exit-1)
- acm2-unwired-typecheck-apps-stays-benign    PASS  (0.25.9 run-typecheck-apps.js benign)
- acm2-rebaseline-clears-advisory             PASS  (re-run updater clears it)
- acm3-no-receipt-is-unverified               PASS  (-> CLI_STOP_UNVERIFIED)
- acm3-verdict-healthy / acm3-exit-0          PASS  (exit 0)
- acm3-no-stop-py-no-nag                      PASS  (no nag on never-wired project)
- acl1-pristine-sha-eq-provenance-not-flagged PASS  (sha-gate: pristine NOT flagged)
- acl1-drifted-sha-ne-provenance-flagged      PASS  (drifted IS flagged)
- acl1-provenance-absent-conservative-flag    PASS  (conservative flag preserved)
- acl1-advisory-only-stays-healthy            PASS  (verdict unchanged)
- ac1-m4-no-exit1-from-missing-cli-hook       PASS  (NO input forces exit-1)

Tally: 30 PASS / 0 FAIL (test-cli-0259-compat.sh exit 0).

Note: a separate hand-built minimal fixture produced exit-1 driven solely by 4
unrelated MISSING surfaces (AGENTS.md, flow-skills/**, agents/**, FLOW_RULES.md)
the minimal fixture never created, plus a Git-Bash /tmp path-translation that
blocked the native-Python receipt read — NOT the receipt logic. The receipt
finding itself resolved correctly to CLI_STOP_BASELINE_DRIFT (advisory) with
SHARED_MERGE_DRIFT absent from findings. The authoritative complete-fixture test
(above) is environment-correct and green.
