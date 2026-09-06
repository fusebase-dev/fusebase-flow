# Flow performance and recovery hardening — roadmap

**Status:** T24 complete; T25 focused/engine proof passed; T26 U14 fixture correction precedes T21
**Documentation tier:** 4
**Execution owner:** `tasks.md` owns order, dependencies, files, SHAs and status; `verification-gate.md` owns proof.
**Starting source:** `2217a9c631300e510b18437548ed4bccb5f31036`
**Sequence:** T11-T20 complete -> T24 real-Git fixture -> T25 Windows/MSYS liveness -> T26 Stop fixture -> T21 gate -> T22 Astra re-review -> T23 closeout.

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

T24 is committed at `fe1629c`. T25 timeout 23/23 and bounded engine rc0 permit its separate commit; the wrapper advanced to 33 PASS and exposed U14's stale first-Stop-block assumption. T26 owns that fixture correction, the proven Stop-status encoding regression, and terminal full-wrapper PASS (`tasks.md` T26), preserving T16's correct CLI/Flow block isolation. Production change is restricted to the intended status literal; no weakened verdicts. T21 remains report-only, T22 GPT-6 Astra review-only, T23 docs-only. No production deployment/publication. Actual CLI install/update/recover comparison, five-provider host telemetry, Windows authority ACL proof, and three real-symlink controls remain UNVERIFIED until directly exercised. UI/client applicability: N/A.
