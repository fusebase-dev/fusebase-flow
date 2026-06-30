# Backlog ticket — cli-custom-at-risk-overflag

**Status:** DONE — resolved in **v3.30.1** (deploy hash `70b32e2`, tag `v3.30.1`, 2026-06-30). Severity: LOW, advisory-only, cosmetic. **Resolution = sha-gate:** `scan_custom_skill_block` now gates `CLI_CUSTOM_AT_RISK` on provenance drift — it fires only when the CLI-owned skill file's sha256 ≠ the bundled provenance (operator content a CLI refresh would clobber). sha == provenance → CLI-shipped block → skip (the pristine `app-dev-practices` over-flag is gone); provenance unavailable for that file → conservative flag (genuine at-risk signal preserved). Advisory-only contract unchanged (no verdict/exit-code change). Spec: `docs/specs/healthcheck-baseline-and-custom-flag-hardening/spec.md`.
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
