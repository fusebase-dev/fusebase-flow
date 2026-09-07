# Problem: CLI overlay marker prose was misclassified as structure

**Slug:** `cli-overlay-marker-prose-misclassified`
**Filed:** 2026-09-07
**Severity:** high
**Status:** resolved by T56 `f4c577b` + T59 `e99d61b`; actual CLI consumer scenario observed

## Symptom

An actual FuseBase CLI project with the canonical `## FuseBase Flow — Claude Code adapter` overlay reported `SHARED_MERGE_DRIFT` because the conflict reporter searched for the old-cased product name. Removing the overlay exposed a second failure: the CLI's inline documentation of `` `<!-- CUSTOM:SKILL:BEGIN --> ... <!-- CUSTOM:SKILL:END -->` `` was parsed as a real block, so recovery refused a safe append. The embedded preflight also rejected the canonical adapter heading unless publisher-only title prose was present.

## Root cause

Overlay ownership tokens were treated as substrings in prose. Case-sensitive product text substituted for an exact heading-and-owned-span check, while CUSTOM and FLOW:PRESERVE scans ignored Markdown line structure.

## Permanent fix

| Surface | Rule |
|---|---|
| Conflict report | Accept one documented canonical/legacy heading only when the recovery parser proves its owned span. |
| CUSTOM markers | Delimit only exact standalone marker lines; inline backticked examples are prose. |
| FLOW:PRESERVE markers | Accept the allowed standalone BEGIN line and exact standalone END line only; malformed standalone opening candidates refuse before backup/write. |
| Recovery preflight | Reuse the same parser for append/refusal decisions and expected-byte pinning. |
| Embedded preflight | Accept only exact canonical, legacy, or source-template heading lines; product-name prose does not qualify. |

T59 matches headings by exact logical line and accepts an optional terminal CR; inline or surrounding prose cannot qualify. Focused proof: T56 uses `hooks/tests/test-recovery-final-verification.py --only t54` and `--only t56`; T59 uses `hooks/tests/test-cli-flow-recovery.sh --only t14`. The recorded CLI `2026.090414.3609` Windows/Git Bash scenario completed update and recovery rc0, reported conflict HEALTHY, and converged to a second no-op. `docs/specs/flow-performance-and-recovery-hardening/gate-report.md` owns exact evidence attribution.

## Guardrail

Marker syntax is a line grammar, not a substring convention. Every ownership consumer must distinguish literal documentation from standalone delimiters and must preserve provider bytes around the proven span.
