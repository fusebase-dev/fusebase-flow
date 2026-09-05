# Flow performance and recovery hardening — roadmap

**Status:** LOCKED for execution
**Documentation tier:** 4
**Execution owner:** `tasks.md` owns order, dependencies, files, SHAs and status; `verification-gate.md` owns proof.
**Sequence:** recovery correctness → hot paths → consumer workflow → validation/measurement → gate.

## Evidence inputs

- `state/audit/adversarial-review-2026-09-05.md`
- `state/audit/adversarial-review-2026-09-05-probes.json`
- `state/audit/find-wasted-effort-2026-09-05.md`

## Baseline and measurement targets

| Measure | Baseline | Target / owner |
|---|---|---|
| Unchanged skill mirror writes | 98/98 targets rewritten | zero whole-recovery writes; AC5 / T4 |
| Unchanged mirror duration | 15.683s, one Windows/Git Bash run | report distribution, no hard timing gate |
| Native Stop reads | 2 full reads | one; AC6 / T5 |
| Mandatory startup estimate | 61,509 chars, common AI Developer inputs | paired actual delivered-context decrease; estimate-only hosts UNVERIFIED; AC7 / T7 |
| Ordinary decisions | multiple possible gates/relays | one product decision; release go-ahead only when releasing; AC8 / T6 |
| Repeated Flow validation | pre-commit always runs configured validators | authenticated exact-state reuse at invocation boundary; AC9 / T8 |
| CLI mutations | demonstrated recovery defects | zero unowned mutation; AC1–AC4, AC11 |

## Constraints

Serialize shared recovery files and test registry. Complete T6 behavioral carrier alignment before T7 compaction. No production deployment/publication; T10 verifies the local package and bounded disposable CLI refresh. UI/client applicability: N/A, internal developer tooling.
