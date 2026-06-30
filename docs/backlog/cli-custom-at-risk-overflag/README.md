# Backlog ticket — cli-custom-at-risk-overflag

**Status:** parked (filed 2026-06-29 as the LOW follow-up from the FuseBase adversarial impl review of `cli-0.25.9-vendor-refresh`, shipped v3.30.0). Severity: LOW, advisory-only, cosmetic.
**Predecessor:** `docs/specs/cli-0.25.9-vendor-refresh/spec.md` (v3.30.0).

## Pain

The `CLI_CUSTOM_AT_RISK` advisory in `check-cli-flow-conflicts.sh` over-flags **CLI-shipped CUSTOM blocks** as at-risk. Concretely, a CLI-owned skill that legitimately carries a CUSTOM marker block (e.g. `app-dev-practices`) is reported as a CUSTOM block that could be lost on re-vendor, even though it's CLI-owned content that the re-vendor intentionally overwrites with the fresh CLI copy.

The effect is **cosmetic**: the advisory is informational (it does not change the verdict, does not gate, does not block deploy). It just produces noise that a reader has to mentally discount.

## Why it was deferred (not folded into v3.30.0)

It's advisory-only and changes no verdict or exit contract. The fix needs a small classification refinement — distinguish a **Flow-owned/operator-owned** CUSTOM block (genuinely at risk from a CLI regen) from a **CLI-shipped** CUSTOM block (expected to be overwritten by re-vendor) — without weakening the genuine at-risk signal. Low value relative to the v3.30.0 scope; parked rather than rushed.

## Acceptance (when picked up)

- `CLI_CUSTOM_AT_RISK` no longer flags CLI-shipped CUSTOM blocks (e.g. `app-dev-practices`).
- A genuinely at-risk operator/Flow CUSTOM block is still surfaced.
- Advisory-only contract unchanged (no verdict/exit-code change).
