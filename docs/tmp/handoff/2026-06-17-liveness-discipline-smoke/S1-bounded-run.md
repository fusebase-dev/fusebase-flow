# Smoke S1 — bounded-run structural anti-hang (FR-27, AC3) — PASS

**Deploy:** v3.28.0 · hash 8cacb80 · 2026-06-17
**Command:** `source hooks/local/lib/bounded-run.sh; BOUNDED_RUN_HEARTBEAT_SECS=1 bounded_run 2 "smoke-sleep30" -- sleep 30`

**Outcome (operator-visible):**
```
bounded-run: still running (1s/2s) — smoke-sleep30
bounded-run: still running (2s/2s) — smoke-sleep30
bounded-run: TIMEOUT after 2s — smoke-sleep30 (rc 124)
SMOKE_RC=124
```

**Ground-truth diagnostics:**
- rc = 124 (timeout-induced; classified by ffhc_timed_out) ✓
- terminal `bounded-run: TIMEOUT` line emitted on EVERY path ✓
- incremental heartbeat emitted (live-but-slow ≠ hang) ✓
- a `sleep 30` terminated at ~2s — the silent unbounded wait is structurally bounded ✓

**No-regression:** test-health-check-timeout.sh 26/26 PASS (ffhc_* API intact); test-liveness-bounded-run.sh 14/14 PASS.

**Verdict:** PASS — the load-bearing structural fix works as specified.
