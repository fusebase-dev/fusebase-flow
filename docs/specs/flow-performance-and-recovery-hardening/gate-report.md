# T56 actual CLI overlay coexistence correction

**Verdict:** PASS - T56 focused local gate; no release/platform attestation.
**Current source:** T56 commit (this commit); prior accepted source `559ca5a` remains historical dependency evidence.
**Report date/owner:** 2026-09-07, AI Developer. **Started at:** 2026-09-07T13:07:08Z. **Committed at:** 2026-09-07T13:34:23Z.

## T56 affected evidence

| Risk | Command/probe | Result | Scope |
|---|---|---|---|
| Standalone malformed markers | `test-recovery-final-verification.py --only t54` | PASS, 2 assertions, 0.031s | unmatched/nested refusal; marker-free append control |
| Structural overlay grammar | `test-recovery-final-verification.py --only t56` | PASS, 3 assertion groups, 4.781s | canonical compact, prose negative, legacy forms, inline CUSTOM/PRESERVE prose, append hash, provider bytes, stable current overlay, malformed standalone preserve refusal before backup/write |
| Actual R55 fixture | new conflict reporter against `flow-cli-coexistence-v4150-r55` | HEALTHY, rc0; AGENTS/CLAUDE both OK | read-only Windows/Git Bash fixture probe; not a CLI update/recover attestation |

No full/default suite ran. T56 changes invalidate AC1/shared-overlay parsing only; T54 and T56 are the selected local rows under B6. Release evidence remains exact-tag CI.


## Prior final affected evidence - accepted by final T22

| Correction | Commit | Focused evidence | Packaging (executor-reported) |
|---|---|---|---|
| T53 / R1 / AC9 |c3c2580 |3/3 in31.620s; uncertain completeness stays non-reusable |mirror98/98, hook209/209, managed372/372; normal precommit PASS |
| T54 / R3 / AC1 |559ca5a |2/2; command0.122s, stage0.031s; no-heading marker preflight |hook209/209, managed372/372; normal precommit PASS |

No precommit duration supplied for these commits. Implementation and focused proof accepted by final targeted T22 ZERO BLOCKERS. T49/T51/T52 findings remain closed; unchanged T50 seams and dependency-limited T20/T32 evidence retained. No broad rerun. Final review assessed6fa185e..559ca5a and R1/R3 counterexamples; adversarial-review.md owns APPROVED/ZERO BLOCKERS and read-only209/372 manifest hash verification.

## R1-R5 correction evidence - closed

| Finding/task | Commit | Focused evidence | Packaging evidence (executor-reported) |
|---|---|---|---|
| R1 / T48 |8e54a74 |four earlier named PASS retained; remaining4/4 in30.168s; real runner/fallback and failure propagation; Windows authority unavailable |hook209/209, managed372/372; normal precommit PASS, duration unreported |
| R2 / T49 |90288ae |4/4 in0.235s; canonical matcher persistence and final predicate |hook209/209, managed372/372; precommit PASS23.4s |
| R4 / T51 |078f0b2 |4 named cases in4.487s; apply-time target races and unchanged control |hook209/209, managed372/372; precommit PASS29.84s |
| R3 / T50 |8a8d450 |4/4 in49.266s; prior authorization, uncertainty, preflight/pinned post-state seams |hook209/209, managed372/372; normal precommit PASS, duration unreported |
| R5 / T52 |6fa185e |16/16 in1.535s; explicit temporal linkage and counterexamples |managed372/372; hook manifest unaffected; normal precommit PASS, duration unreported |

This earlier correction group ended at `6fa185e`; final source is `559ca5a`. Results/timings are owning-executor evidence; manifest asset inventories were also read from each commit (209 hook/372 managed entries). Inventory counts alone are not verification execution. Named logs remain under the existing smoke directory; original T48 timeout120s/155.9s and4/6 partial result are retained historical evidence, not retrospectively6/6. The remaining run reports4/4, not the earlier planned3/3.

T20/T32 evidence below is reused only by dependency: T32 composition implementation is unchanged; T20's measured three independent processes/zero-change observations remain valid at008ade7. T49/T51/T50 change recovery semantics, so their focused seam proofs supplement that history; no claim T20 ran on6fa185e or proves all changed paths. No broad reruns occurred or are requested. Final T22 accepted R1-R5 closure and this scoped dependency mapping.

## Prior integrated evidence (dependency-scoped reuse)

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

## Acceptance ownership

verification-gate.md owns final scoped acceptance and explicit deferred coverage. Earlier12/3/1 observations were superseded by focused corrections and final zero-blocker review; they are not current unresolved blockers.

## Material failures retained

| Stage | Failure and eventual disposition |
|---|---|
| Initial T10 | 1,274/1,274 reported; superseded by independent CHANGES REQUIRED, never final acceptance |
| Corrective broad prefix | 414 PASS/0 FAIL over 108 minutes, no complete terminal result; never rerun to inflate counts |
| T24-T30 | real-Git, Stop fixture, encoding, portability and timeout defects corrected; focused evidence in tasks/history |
| T33/T34 | stale manifests and receiptless first-edit bootstrap gap; current manifests fixed, bootstrap implementation accepted by final T22 within the reviewed model |
| T35/T36 | dataclass dynamic import and classify API mismatch; shared preparation plus conservative legacy API |
| T37/T38 | T15 timeout then bare Bash selected WSL; composed restore/provider negatives retained and explicit-shell final-status correction |
| T39/T40 | convergence 55/80s timeouts; no attempts accepted |
| T41-T44 | PATH observer missed calls; calibration12s timeouts; replacement status shell12s timeout; experimental tests retired, no false semantic PASS |
| T45 | convergence 72.813s; attempt1 timeout45s/49.203s; receipt sole changed target |
| T46 | `child_copy` and selector124; no convergence END; infrastructure-inconclusive |
| T47 | identity-scoped orphan cleanup; one corrected-environment T20 passed unchanged bounds |

No failed record is erased or relabeled PASS. The historical T20 timing at `008ade7` is measured; separation of runtime optimization versus environment cleanup contributions is UNKNOWN. No causal percentage speedup or total token-saving claim.

## Final local acceptance and explicit residual disposition

Final T22 APPROVED/ZERO BLOCKERS at559ca5a closes R1-R5 for the reviewed contract. T53 c3c2580 and T54 559ca5a evidence above accepted; T49/T51/T52 closure retained. Reviewer checked complete=true refusal and malformed no-heading refusal/marker-free append in memory, inspected old-receipt fail-closed control flow, and checked normalized209 hook/372 managed manifest hashes. No suites were repeated by that review.

Scoped local implementation and T23 docs are DONE. Actual current CLI install/update/recover, five-provider delivered-context telemetry, real-symlink/MSYS/Linux coverage and Windows authority isolation remain DEFERRED/UNVERIFIED. They are explicitly outside the approved local completion boundary and are not blockers for this scoped closeout; they still prohibit claims of verified release/platform coverage. Validator reuse is globally unavailable: validators execute normally on every platform.

Main outcomes within reviewed source/fixture coverage: CLI/user ownership preservation and restore safety; fewer redundant mirror/recovery processes; byte/mtime-stable mirrors and ownership receipt; one native Stop transcript read; composed heavy health/liveness execution once; compact static context and honest outcome linkage. Three historical T20 no-op calls remained under45s with zero target changes/copies after T47 cleanup; T32 9/9. No measured consumer-token saving or causal end-to-end speedup claim. No duplicate lint/typecheck elimination: validators always run.

Anti-overtesting outcome: dynamic tracer and implementation-mirroring helper-test loop retired; one existing composed product oracle, dependency-aware focused corrections, stop-first-red. T47 was a documented environment-precondition correction with identity-scoped cleanup, not an unchanged retry. No active implementation/test collection remains.

Restore paths remain docs/install-fusebase-cli-project.md and docs/fusebase-cli-edition.md; preserve retained consumer originals and ownership boundaries. No deploy, migration or app UI scope. Exact task rollback in reverse dependency order; preserve all unrelated dirty/untracked smoke/archive/wasted-code. This closeout edits docs only and makes no commit.
