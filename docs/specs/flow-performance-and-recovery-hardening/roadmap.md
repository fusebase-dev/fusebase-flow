# Flow performance and recovery hardening — roadmap

**Status:** implementation through T47 complete/absorbed; source `008ade7`; T21 report reconciled, T22/T23 OPEN; spec DRAFT. Tier 4 existing pack. `tasks.md` owns detailed slices; `gate-report.md` owns evidence and residuals.

| Recommendation order | Slices | Disposition |
|---|---|---|
| Recovery and ownership first | T1-T4, T11-T17 | implemented; final negative-path acceptance under T22 |
| Ordinary-work efficiency and honest measurement | T5-T9, T18-T20 | implemented; measured-host/real-CLI residuals explicit |
| Initial gate | T10 | historical, superseded by independent CHANGES REQUIRED |
| Real-Git/timeout/fixture/portability corrections | T24-T31 | completed with scoped evidence |
| Remove repeated execution and adopt scoped gates | T32-T33 | completed; current T32 composition 9/9 |
| Bootstrap/shared classify/import compatibility | T34-T36; T35 absorbed into T36 | completed; final dependency review pending |
| Observable provider/status recovery | T37-T38; T38 absorbed into T37 | completed; preserve partial-run evidence honestly |
| Minimal no-op harness and product process reduction | T39-T41 | absorbed into `008ade7` |
| Retire observer and mirrored helper tests | T42-T45 | superseded experiments removed; material failures retained |
| Lazy baseline/stable receipt/batched mirror work | T46 | committed at `008ade7` |
| Scoped orphan cleanup and one environment-corrected run | T47 | complete; T20 all 3 no-ops PASS |
| Reconcile technical acceptance | T21 | report complete; scoped gate OPEN |
| Independent whole-diff/evidence review | T22 | NEXT; review original findings and current closure limits |
| Honest docs closeout | T23 | only after zero-blocker T22 and residual disposition |

No more implementation or test execution is implied by this roadmap. T22 identifies any concrete remaining defect; only its affected evidence is revisited. Preserve existing bounds and anti-overtesting disposition. Actual CLI install/update/recover, host telemetry, real symlink/Windows authority and full platform/release coverage remain UNVERIFIED/DEFERRED. No app UI/deploy/migration scope.
