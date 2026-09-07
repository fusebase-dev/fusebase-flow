# Tasks - v4.15.0 completion

**Status:** implementation complete through T59 `e99d61b`; T60 documentation reconciliation recorded by this commit; publication evidence pending.
**Source:** final implementation `e99d61b`. **Prior review:** adversarial-review.md final T22 at `559ca5a`. **Evidence/history owner:** gate-report.md.

## Complete slice mapping and order

| Slices | Final disposition |
|---|---|
| T1-T9 |initial implementation; corrections below supersede unsafe/provisional aspects |
| T10 |historical gate superseded by independent review; never current proof |
| T11-T20 |corrective implementation; exact commits below |
| T24-T34 |fixture/liveness/ownership/scoped-validation corrections; exact commits below |
| T35 |absorbed into T36 39fbeaf |
| T36 |39fbeaf |
| T37/T38 |d0270f0; T38 selected-Bash correction absorbed |
| T39/T40/T41 |harness/runtime reductions absorbed into T46 008ade7 |
| T42/T43/T44/T45 |experimental tracer/helper loop retired; no shipped test file; disposition in008ade7 |
| T46 |008ade7 |
| T47 |identity-scoped orphan cleanup and one environment-corrected T20 run; no source commit |
| T48 -> T49 -> T51 -> T50 -> T52 |8e54a74 ->90288ae ->078f0b2 ->8a8d450 ->6fa185e |
| T53 -> T54 |c3c2580 ->559ca5a; final focused corrections accepted |
| T56 |`f4c577b`; exact overlay structure replaces prose/substring detection; T54/T56 focused selectors PASS |
| T57 |`96de58e`; health stages emit observable progress; no speedup claim |
| T58 |`e432480`; v4.15.0 release preparation only; no publication/tag |
| T59 |`e99d61b`; canonical Claude adapter heading matches an exact logical line with optional terminal CR |
| T60 |this commit; reconcile final release evidence and remaining deferrals; docs only |
| T21 |81bb130 report plus affected evidence reconciliations |
| T22 |final targeted APPROVED/ZERO BLOCKERS; prior findings/corrections retained in review |
| T23 |`079e84d`; scoped docs closeout |

## Exact commit chronology (includes planning commits)

| SHA | Recorded subject |
|---|---|
| `c158b45` | T1: replace only the owned Flow overlay span |
| `5bf89f8` | T2: make settings recovery ownership-safe and unique |
| `0829d16` | T3: restore valid prior hook intent safely |
| `1b44a95` | T4: make recovery targets zero-write on no-op |
| `598c667` | T5: reuse one Stop transcript read |
| `0db37fc` | feat(flow): T6 make ordinary work diagnosis-first |
| `7ab052a` | refactor(flow): T7 compact startup carriers |
| `b581d71` | feat(flow): T8 reuse exact-state validator evidence |
| `ff941ea` | feat(flow): T9 separate historical window evidence |
| `b42a203` | fix(flow): T7 restore compacted carrier invariants |
| `e300953` | fix(flow): T7 restore preflight carrier contracts |
| `2217a9c` | fix(flow): T10 restamp hook integrity manifests |
| `31a98fa` | docs(flow): plan T11-T23 Astra corrections |
| `86b98db` | fix(flow): T11 complete validator identity |
| `6af5291` | fix(flow): T12 trust validator signing boundary |
| `2db3f5b` | fix(flow): T13 preserve recovery target ownership |
| `d126865` | fix(flow): T14 prevalidate recovery plans |
| `41c1fd2` | fix(flow): verify recovery final state (T15) |
| `deb21b1` | fix(flow): isolate exact lifecycle hooks (T16) |
| `82db5f0` | fix(flow): bound markerless overlay migration (T17) |
| `44cc556` | test(flow): execute lane workflow evidence (T18) |
| `bd3bc76` | fix(flow): scope conclusions to task commits (T19) |
| `adc1a3d` | test(flow): prove repeated recovery no-ops (T20) |
| `d8d5b59` | docs(flow): insert T24 recovery fixture correction |
| `4504cf0` | docs(T25): separate recovery liveness blocker from T24 fixture proof |
| `fe1629c` | test(flow): initialize recovery fixture git repo (T24) |
| `72cf2d1` | docs(T26): separate stale Stop fixture from liveness proof |
| `ef320de` | fix(flow): bound MSYS recovery engine waits (T25) |
| `0231fb9` | docs(T26): include proven Stop status encoding regression |
| `4d4711e` | docs(T27-T28): bound fixture corrections and deduplicate final verification |
| `335ed08` | fix(flow): preserve exact Stop hook identity (T26) |
| `597b02d` | test(flow): harden legacy recovery fixtures (T27) |
| `e657392` | test(flow): add bounded recovery selectors (T28) |
| `24ba9c6` | docs(T29-T30): batch mutation manifests and verify probe budget semantics |
| `17749db` | test(flow): batch mutation artifact manifests (T29) |
| `314ead3` | fix(flow): verify bounded probe deadlines and reap (T30) |
| `ffc2dba` | docs(T31): synchronize heartbeat proof and isolate focused diagnostics |
| `1cad34d` | test(flow): synchronize heartbeat evidence (T31) |
| `98bda61` | docs(T32): deduplicate composed liveness regression coverage |
| `d3d0d0e` | docs(T33): scope local acceptance and preserve full release verification |
| `a9d7272` | test(flow): deduplicate composed liveness coverage (T32) |
| `fb156aa` | T33: add risk-scoped validation reporting |
| `7c9be06` | fix(T34): bootstrap proven mirror ownership |
| `39fbeaf` | fix(T36): unify recovery ownership preparation |
| `d0270f0` | test(T37): bound recovery verification evidence |
| `008ade7` | perf(T46): accelerate no-op recovery |
| `81bb130` | docs(T21): reconcile scoped acceptance evidence |
| `8e54a74` | fix(T48): fail closed incomplete validator reuse |
| `90288ae` | fix(T49): persist canonical hook repair |
| `078f0b2` | fix(T51): reject stale recovery ownership |
| `8a8d450` | fix(T50): preserve recovery authorization evidence |
| `6fa185e` | fix(T52): require explicit temporal evidence links |
| `c3c2580` | fix(T53): disable unproved validator reuse |
| `559ca5a` | fix(T54): reject malformed overlay append inputs |
| `079e84d` | docs(T23): close performance hardening roadmap |
| `f4c577b` | fix(T56): parse overlay markers structurally |
| `96de58e` | fix(T57): expose health stage progress |
| `e432480` | chore(T58): prepare Fusebase Flow v4.15.0 |
| `e99d61b` | fix(T59): accept canonical Claude adapter heading |
| `this commit` | docs(T60): reconcile v4.15.0 release evidence |

## Delivery/rollback boundaries

Actual CLI `2026.090414.3609` compatibility is observed in the recorded Windows/Git Bash consumer scenario; gate-report.md owns exact attribution. Tagged Linux and Windows/MSYS release CI, unexecuted real-symlink cases, five-provider delivered-context telemetry, and Windows authority isolation/successful signing remain DEFERRED/UNVERIFIED. Validator reuse is globally unavailable: validators execute normally on every platform.

No deploy/migration/UI scope. Preserve CLI/user bytes, retained originals and repair backups. Recovery/restore instructions remain in docs/install-fusebase-cli-project.md and docs/fusebase-cli-edition.md; do not replace them with an improvised procedure. Roll back exact owning commits in reverse dependency order; preserve unrelated dirty/untracked smoke/archive/wasted-code paths.

No full-prefix replay, observer/helper test recreation or new evidence collection is pending. Future source changes invalidate only affected dependency rows; first red stops. A documented environment precondition correction may justify one bounded rerun, never an unchanged retry loop. Failed history remains in gate-report.md and original evidence.
