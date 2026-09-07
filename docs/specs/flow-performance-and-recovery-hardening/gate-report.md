# T21 scoped acceptance reconciliation

**Verdict:** OPEN for final independent T22 review; spec DRAFT, T23 OPEN. Current 16-row ledger: 12 scoped PASS / 3 OPEN / 1 DEFERRED (`verification-gate.md`). Previous 9/6/1 is historical. No full-suite, real-CLI or release attestation.
**Final source:** `008ade7553009f38ebf0d9ee29c83df8be64d50b` — `perf(T46): accelerate no-op recovery`. Commit includes T39/T40 harness, T41 runtime reductions, T46 ownership/mirror optimization and final manifests. T47 corrected environment only.
**Report date/owner:** 2026-09-07, Architect; report-only. The reconciliation itself changed no source/tests and launched no tests.

## Current evidence

| Evidence | Exact result | Attribution/limit |
|---|---|---|
| Hook manifest | 209/209 MATCH | final-source executor report and manifest-bearing commit |
| Managed manifest | 372/372 MATCH | final-source executor report and manifest-bearing commit |
| Normal precommit | PASS, 18.3s | executor report for `008ade7`; not a new standalone full preflight |
| T47 T20 | rc0, 109.53s overall | `T47-t20.log`; actual Windows Git Bash execution |
| Fixture | 0.167s | `%TEMP%/fusebase-flow-t20-evidence-896279/stages.jsonl` |
| Convergence | 20.516s, complete/8 verified | same directory convergence result |
| Attempt1 | 23.687s, rc0; changed 0, copied 0 | independent process; target bytes/mtimes including ownership receipt |
| Attempt2 | 23.312s, rc0; changed 0, copied 0 | independent process; same assertions |
| Attempt3 | 31.015s, rc0; changed 0, copied 0 | independent process; same assertions |
| Mutation | changed 1; copy-parser refusals 2 | existing T20 red control; not bootstrap/race mutation coverage |
| T20 survivors | 0 | executor scoped post-run inventory |
| T32 final composition | 9/9, rc0, 85.777s; survivors 0 | `T32-final-composition.log`, executor survivor report |
| Environment cleanup | 11 validated September 5 orphan loop roots removed; no unrelated processes | `T47-loop-process-cleanup.json`; exact identity/owner/parent/command criteria |

Named logs above are under `docs/tmp/handoff/2026-09-05-flow-performance-and-recovery-hardening-smoke/`. Temporary T20 result files remain at the explicit directory above; do not claim tracked portability. Counts/manifest/precommit/survivor assertions supplied by the owning executor are labeled as such; this Architect read the commit, logs, stage evidence and cleanup record and did not rerun them. Executions preceded the final commit; use the executor's final source/dependency mapping, not a claim they ran after the SHA existed. Final-manifest changes are separate from the tested fixture behavior.

## Acceptance boundaries

| Scope | Verdict | Reason |
|---|---|---|
| AC1/AC2/AC4 | PASS, reused | retained overlay/settings exact ownership proofs; unchanged source dependencies listed in ledger |
| AC3 | OPEN; current positive PASS | composed recovery/final verification proven; T46 bootstrap orchestration requires final review of negative-path dependency reuse |
| AC5/S2 | PASS, scoped | all 3 independent write-mode attempts; receipt/manifest no-op and injected change detection; broader ownership negatives under AC3/AC12 |
| AC6 | PASS, reused | unchanged one-read Stop implementation and retained fixture evidence |
| AC7 | DEFERRED | actual paired host-delivered telemetry absent; character estimates insufficient |
| AC8/S3 | PASS, reused | post-T18 lane 12/12 executed actions/mutations; no new rerun needed |
| AC9 | PASS, scoped fail-closed reuse | retained validator matrix; unavailable Windows authority means reuse unavailable, not verified signer isolation |
| AC10 | PASS, scoped | retained window/benchmark proofs plus honest T20 write-mode metrics |
| AC11 |OPEN | fixture CLI/user preservation PASS; actual full CLI install/update/recover UNVERIFIED/DEFERRED |
| AC12 | OPEN; normal convergence PASS | canonical/fallback prior evidence plus current no-op; lazy bootstrap dependency review pending |
| T32/current manifests/precommit | PASS, scoped | evidence table; neither release nor whole-platform attestation |

## Material failures retained

| Stage | Failure and eventual disposition |
|---|---|
| Initial T10 | 1,274/1,274 reported; superseded by independent CHANGES REQUIRED, never final acceptance |
| Corrective broad prefix | 414 PASS/0 FAIL over 108 minutes, no complete terminal result; never rerun to inflate counts |
| T24-T30 | real-Git, Stop fixture, encoding, portability and timeout defects corrected; focused evidence in tasks/history |
| T33/T34 | stale manifests and receiptless first-edit bootstrap gap; current manifests fixed, bootstrap implementation retained for T22 review |
| T35/T36 | dataclass dynamic import and classify API mismatch; shared preparation plus conservative legacy API |
| T37/T38 | T15 timeout then bare Bash selected WSL; composed restore/provider negatives retained and explicit-shell final-status correction |
| T39/T40 | convergence 55/80s timeouts; no attempts accepted |
| T41-T44 | PATH observer missed calls; calibration12s timeouts; replacement status shell12s timeout; experimental tests retired, no false semantic PASS |
| T45 | convergence 72.813s; attempt1 timeout45s/49.203s; receipt sole changed target |
| T46 | `child_copy` and selector124; no convergence END; infrastructure-inconclusive |
| T47 | identity-scoped orphan cleanup; one corrected-environment T20 passed unchanged bounds |

No failed record is erased or relabeled PASS. The improved current timing is measured; separation of runtime optimization versus environment cleanup contributions is UNKNOWN. No causal percentage speedup or total token-saving claim.

## Gate remainder and next action

T22 independently reviews `2217a9c..008ade7`, current source/dependency evidence and original B1-B8/N1-N2 findings in unchanged `adversarial-review.md`. Review decides remaining AC3/AC12 negative-path evidence sufficiency; no automatic test prefix or new helper suite. Concrete blockers require narrowly scoped correction and affected-evidence invalidation only.

Actual CLI full chain, cross-provider context telemetry, real symlink/MSYS controls, Windows authority isolation and full platform/release CI remain UNVERIFIED/DEFERRED. T23 cannot mark DONE until zero-blocker review and explicit disposition of acceptance residuals. No deploy/publication claim. Preserve all existing untracked smoke/archive/wasted-code paths. Rollback uses exact owning commits in reverse dependency order; do not discard shared dirty documentation.
