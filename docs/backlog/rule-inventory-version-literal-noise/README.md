# Backlog — rule-inventory-version-literal-noise

**Status:** parked
**Filed:** 2026-07-26 (v4.6.0 deploy prep)
**Owner:** unassigned
**Lane guess:** Lightweight (one normalization rule + one test arm)

## Problem

`hooks/local/rule-inventory.sh` captures the self-attestation string verbatim in its `BOOT.attestation` row. That string embeds the framework version (`"Operating as {role} under Fusebase Flow v4.6.0…"`), so **every release version bump makes the committed baseline stale by exactly one row** — a `c` (change), never a `d`.

Observed live during the v4.6.0 release: `43c052d` re-baselined the inventory, then `ef7793e`'s `sync-version-strings.sh` sweep rewrote the attestation `v4.5.0` → `v4.6.0`, requiring a second re-baseline inside `4323b23`.

## Why it matters

The inventory is a **rule-loss tripwire** (AC2 of `token-floor-remediation`). A tripwire that is expected to show a benign diff after every release trains its reader to skim past the diff — which is precisely the failure mode decision D5 of that ticket exists to prevent, and precisely how the T5 phantom-principle row nearly masked real losses. Recurring known noise on a safety instrument degrades the instrument.

## Proposed fix

Normalize version literals inside `rule-inventory.sh`'s `norm()` — replace `v\d+\.\d+\.\d+` with a stable token (e.g. `vX.Y.Z`) before emitting a row. The rule's *semantics* do not change across a version bump, so the row should not either.

## Acceptance criteria

- AC1 — A version-only bump (`sync-version-strings.sh` after a `VERSION` change) produces an **empty** inventory diff.
- AC2 — A genuine reword of the attestation sentence still produces a non-empty diff (the normalization must not blind the row entirely). Prove both arms in `hooks/tests/test-rule-inventory.sh`.
- AC3 — No other row's normalization behavior changes; row count stays 170.

## Notes

Found by the Deploy-phase session during v4.6.0 release prep and filed rather than fixed — it is an instrument change, out of scope for a deploy. Related: `docs/specs/token-floor-remediation/` (A2, D5, AC2).
