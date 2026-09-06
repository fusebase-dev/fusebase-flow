# Flow performance and recovery hardening — roadmap

**Status:** CORRECTIVE EXECUTION PLANNED; Astra review verdict CHANGES REQUIRED
**Documentation tier:** 4
**Execution owner:** `tasks.md` owns order, dependencies, files, SHAs and status; `verification-gate.md` owns proof.
**Starting source:** `2217a9c631300e510b18437548ed4bccb5f31036`
**Sequence:** validator trust -> recovery ownership/preflight/verification -> exact hook/overlay ownership -> real workflow evidence -> temporal/write-mode measurement -> gate -> Astra re-review -> closeout.

## Evidence inputs

- `state/audit/adversarial-review-2026-09-05.md`
- `state/audit/adversarial-review-2026-09-05-probes.json`
- `state/audit/find-wasted-effort-2026-09-05.md`
- `docs/specs/flow-performance-and-recovery-hardening/adversarial-review.md`

## Baseline and measurement targets

| Measure | Baseline | Target / owner |
|---|---|---|
| Unchanged skill mirror writes | 98/98 targets rewritten | three independent write-mode no-op recoveries; AC5 / T20 |
| Read-only mirror integrity | prior `--check` run | label read-only only; never infer write count; N2 / T20 |
| Native Stop reads | 2 full reads | one; AC6 / T5 |
| Mandatory startup estimate | 61,509 chars, common AI Developer inputs | paired actual delivered-context decrease; estimate-only hosts UNVERIFIED; AC7 / T7 |
| Ordinary decisions | multiple possible gates/relays | one product decision; release go-ahead only when releasing; AC8 / T6 |
| Repeated Flow validation | pre-commit always runs configured validators | complete trusted identity or reuse unavailable; AC9 / T11-T12 |
| CLI mutations | demonstrated recovery defects | zero unowned mutation and authoritative per-surface verification; AC1-AC5, AC11 / T13-T17 |

## Constraints

Serialize shared validator and recovery files. T11-T20 each produce one commit; T21 is report-only, T22 is the repeated Astra review, and T23 is docs-only closeout. No production deployment/publication. Actual CLI install/update/recover comparison, five-provider host telemetry, Windows authority ACL proof, and three real-symlink controls remain UNVERIFIED until directly exercised. UI/client applicability: N/A.
