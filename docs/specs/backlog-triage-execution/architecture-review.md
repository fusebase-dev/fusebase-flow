# Architecture review — 2026-08-07 (Codex gpt-5.6-sol, xhigh)

**Verdict: `DELETE-AND-MOVE`.** Asked cold, with no plan to react to, and with
"the current direction is wrong" as an available answer. It took it.

**The finding that reframes the week:** the local full gate is NOT mechanically required for
publication — CI is. `.github/workflows/fusebase-flow-release.yml` publishes only after its
reusable `verify` job passes on the tagged SHA. Optimizing the local gate was never on the
critical path. The prose disagrees with the machinery: `PUBLISHING.md` demands a local full run,
`docs/maintainer-execution.md` demands two platforms, and the enforced CI job is Ubuntu-only.

VERDICT: DELETE-AND-MOVE

## Q1 should the local full gate exist in this form

No. Delete the full local gate as a release oracle.

`run-tests.sh` should become a fast, non-attesting local check. Release-depth verification belongs in exact-SHA CI, split into Linux and Windows/MSYS jobs. Platform stress and profiling belong in maintainer opt-in jobs.

Symptom:    The required local gate takes 2–4.5 hours and cannot pass its committed recovery timeout.  
Root cause: One runner conflates fast feedback, release verification, platform stress, compatibility soak, and diagnostics.  
Layer:      config/test architecture — fixing there? yes; change test ownership and release authority, not timeouts.  
Drift risk: Moving everything to the current Ubuntu-only CI would silently lose MSYS coverage.  
Decision:   root-cause fix — delete the local full-release oracle and move/shrink its heavy phases.

North-star: Drift  
Dimension: constraint — low friction, opt-in governance, and cost as a defect are contradicted by the mandatory full local gate.  
Recommendation: fast local feedback; exact-SHA CI owns release evidence.

## Q2 is cli-flow-recovery proportionate

No. The failure class is valuable; the 26-minute monolith is not.

It protects real recovery and upgrade behavior:

- preserving CLI-owned files while restoring Flow;
- opt-in hook wiring without duplication;
- overlay refresh, idempotence, and operator-value preservation;
- correct health/conflict classification;
- invalid-settings rollback;
- legacy `skills/` migration;
- provider ownership and provenance.

Those classes have occurred. Git history records live data loss (`83e9ea9`, `4c1c522`), downstream false drift (`250e068`, `ea38342`, `b42a3d2`, `24dd371`), silent Stop-hook miswiring (`d227837`), and a live deploy-lint blocker (`905037f`).

But the phase implements 31 assertion groups using ten complete `$PROJECT` clones and approximately 27 recursive copy operations. The latest retained trace had already spent 1,428 seconds reaching assertion 19 of 31. That is not proportionate isolation.

Replace it with:

- table-driven minimal fixtures for U10/U11/U12/U13/U17/U18/U19/F4 and provenance classifications;
- tiny direct tests for U15 and agent ownership;
- four end-to-end cases: default/`--wire-hooks` recovery, preserve-aware overlay refresh, invalid-JSON rollback, and real legacy migration;
- one complete-tree recovery smoke in CI.

What is genuinely lost: every classification mutation would no longer be exercised against a complete publisher-shaped tree. The one full-tree smoke retains emergent integration coverage; the repeated whole-tree copies add little beyond that.

Delete the old monolithic phase after a 31-to-new-test coverage map proves every predicate has an owner.

## Q3 was today's machinery justified

The sentinel fixed a real defect: an externally killed MSYS gate left descendants alive for 38 minutes. Some child-lifecycle mechanism remains necessary wherever long MSYS process trees run; a ten-minute gate can still be cancelled.

But the out-of-band sentinel is symptom-support for the current default architecture. It should not run or be tested on every fast local check. Keep it only around the Windows/MSYS deep runner until a simpler Job Object or supervisor owns those children. Move `signal-reap` to Windows CI and maintainer fault-injection; collapse its repeated scenarios around the field discriminator and essential collateral controls.

The recovery instrumentation seam was justified as a temporary diagnostic, not as permanent release coverage. It proves trace schema, containment, redaction, and failure inertness—not recovery correctness—and its own review produced truncation, secret-leak, and symlink findings. Remove `cli-flow-profile` from every required gate immediately. After recovery is decomposed, delete the helper and its synthetic test; ordinary per-test timing is sufficient.

Today’s net change is roughly 1,786 added lines across runner, sentinel, fixtures, and profiling files, while the required gate gained about 22 minutes. That direction should not continue.

## Q4 the smallest correct architecture

| Tier | Required contents | Authority |
|---|---|---|
| Local default | `preflight`; `fixtures`, `module-size`, `git-smoke`, `hook-manifest`, `lane-router`, `secret-scan-staged`, `approval-binding`, `approval-writer`, `command-policy`; manifest/mirror checks | Fast feedback only; never release proof |
| Linux CI | All deterministic cross-platform phases; decomposed recovery tests; runner parity; both manifest checks; mirror, module-size, public-surface, clean-tree checks | Required release evidence |
| Windows/MSYS CI | `health-check-timeout`, `liveness`, `secret-scan-staged`, `hook-install-rc`, `msys-tree-cleanup`, `signal-reap`, CLI/upgrade/recovery integration phases after decomposition | Required platform evidence |
| Maintainer opt-in | repeated kill/load stress, profiling, compatibility soak, CI-job reproduction | Diagnostic only; never substitutes for required CI |

Delete or move:

- Delete `cli-flow-profile` from the required phase list; delete its helper/test after recovery decomposition.
- Remove `signal-reap` from the default local list; shrink and move it to Windows CI.
- Delete the single-row `run_exitcode_phase` treatment of `cli-flow-recovery`; expose individual scenario results.
- Delete the old monolithic recovery script after its assertions migrate.
- Delete the rule that only a full unscoped local run may support a release claim.
- Stop treating `state/audit/hook-test-results.md` as release evidence.
- Remove the 900-second recovery default and every release-time timeout override with it.

Release-evidence contract:

- Required checks are `verify-linux` and `verify-windows-msys` on the exact tag SHA.
- Both upload phase results, logs, SHA, platform, committed bounds, and durations even on failure.
- GitHub Release publication and the tag ruleset require both checks.
- Required-job timeout or `INCONCLUSIVE` is red. Platform N/A is explicit and never counted as PASS.
- A local fast result has a visibly non-release summary shape.

Bound policy:

- Local product budget: ≤10 minutes under loaded MSYS; committed 15-minute outer wall. A phase that breaks the budget leaves the local tier—the wall is not raised.
- CI shards: ≤30-minute design target, 60-minute absolute wall, and five-minute no-progress deadline for milestone-producing phases.
- No release-time environment override.
- Maintainer stress jobs may have larger committed ceilings but carry no release authority.

## Q5 traps for this step

- Do not raise 900 to 2,700 or 5,400 seconds. That repeats the symptom patch already reviewed down.
- Do not weaken `ac5` from two heartbeats to one and call the architecture fixed. Replace wall-clock counting with a deterministic “heartbeat observed before child completion” discriminator.
- Do not move the suite into the existing Ubuntu-only workflow and claim two-platform coverage.
- Do not delete assertions directly from the monolith. Map each predicate to its new unit, integration, or full-tree owner first.
- Do not preserve ten full clones under a new fixture-builder abstraction. The discriminator is clone count and elapsed cost, not prettier plumbing.
- Do not use shared mutable fixtures. Generate small isolated fixtures per scenario.
- Do not treat synthetic profile tests as evidence about recovery runtime or correctness.
- Do not count controls, skips, or inconclusives as discriminators or passes.
- Do not run parallel deep gates against one workspace or fixed `hook-test-results.md`; CI jobs and artifacts require unique run identities.
- Do not add another sentinel, watchdog, trace format, or evidence file before subtracting the phases that created the need.
- Do not run another multi-hour full gate before the authority split and phase ownership are settled.

## Q6 critical path to publishing

The local full gate is not mechanically required for GitHub Release publication; CI is. `.github/workflows/fusebase-flow-release.yml` publishes only after its reusable `verify` job passes on the tagged SHA.

The repository’s prose currently says otherwise: `PUBLISHING.md` requires a local full run, while `docs/maintainer-execution.md` also requires two platforms. Meanwhile, the enforced CI job is Ubuntu-only. That is an inconsistent contract, not a reason to keep spending hours locally.

The genuine release path is:

1. exact-SHA adversarial review;
2. required Linux and Windows/MSYS CI checks;
3. committed-default bounds with no skips or overrides;
4. fresh manifests, mirrors, module ratchet, public-surface and clean-tree checks;
5. tag protection and publish job dependent on both required checks.

Optimizing the old local full gate is not on the critical path. Moving release authority to the two-platform CI contract is. Recovery decomposition is required only far enough for the Windows job to complete within its committed budget. Further sentinel hardening and profiling are maintainer comfort unless a real required check exposes a product defect.

## Findings

1. BLOCKER | `hooks/tests/run-tests.sh:430-471`; `docs/backlog/gate-bounds-lack-headroom/README.md:44-55` | The committed 900-second recovery bound is below the documented 1,568–1,813-second healthy path | The shipped release gate cannot pass on the measured host without an uncommitted override | Verified from the bound implementation, committed 2h02m result, and backlog measurements.

2. BLOCKER | `hooks/tests/run-tests.sh:473-502`; `state/audit/hook-test-results.md:1-5` | The claimed release artifact records neither SHA nor platform and is written only after every phase finishes | A killed run produces no authoritative artifact, and an existing artifact cannot prove the published tree | Verified by tracing report generation and reading the current result header.

3. BLOCKER | `.github/workflows/fusebase-flow-verify.yml:18-20`; `docs/maintainer-execution.md:42-44` | Release CI is Ubuntu-only while repository policy says two-platform evidence is mandatory and known defects are MSYS-specific | Deleting local MSYS evidence without adding Windows CI would weaken release safety | Verified from the workflow runner and maintainer contract.

4. HIGH | `hooks/local/lib/hook-integrity-check.sh:99-108,156-162`; `PUBLISHING.md:50-95` | The health engine already declares the MSYS full suite infeasible and defaults to three fast phases, while publishing still requires that infeasible suite locally | Two product surfaces encode opposite gate architectures | Verified by comparing the adaptive health path with publication prerequisites.

5. HIGH | `hooks/tests/test-cli-flow-recovery.sh:247-953`; `state/audit/cli-flow-recovery-profiles/49f94fb5373ae771805ce83ffdc358992b3a81d2/run-20260807T212855Z-1185675.tsv:18-36` | Thirty-one assertions are coupled to ten full project clones and repeated recovery/health invocations | One integration corpus dominates the gate and scales with filesystem/process overhead rather than assertion complexity | Verified by static counts and the retained trace reaching only scenario 19 after 1,428 seconds.

6. HIGH | artifact `git diff 0550d37..49f94fb -- hooks/tests hooks/local/lib/run-with-timeout.sh` | This week added approximately 1,786 lines of sentinel, fixture, and profile machinery to support the gate | The support system now materially increases the cost and review surface of the thing it protects | Verified from the exact diff’s nine-file numstat.

7. HIGH | `hooks/tests/run-tests.sh:421-426`; `docs/specs/backlog-triage-execution/implementation-review.md:39-45` | Diagnostic instrumentation became a required release phase and itself introduced file-truncation, verdict-changing, and secret-recording defects | Observability added correctness and security surface without product coverage | Verified by phase registration and adversarial findings.

8. HIGH | `docs/specs/backlog-triage-execution/re-review-c97f8d2.md:48-60`; `hooks/tests/test-run-tests-signal-reap.sh:178-518` | The 19-row signal suite had only four correction discriminators; the remainder were controls or pre-existing behavior | Its reported breadth overstates what the expensive phase proves | Verified by the re-review’s row-by-row comparison against the pre-fix implementation.

9. HIGH | `hooks/tests/run-tests.sh:355-376`; `docs/specs/backlog-triage-execution/re-review-c97f8d2.md:42-46,79-83` | Shell-phase `INCONCLUSIVE` rows do not enter the parent total | A locked red acceptance condition can disappear inside a green full-gate count | Verified by comparing parser patterns with the signal test’s INT row.

10. MAJOR | `hooks/tests/test-health-check-timeout.sh:611-648` | `ac5` infers correctness from at least two heartbeats during a four-second sleep | Host scheduling can fail the gate while the heartbeat mechanism still works | Verified from the real-time sleep, one-second polling, and count assertion.

11. MAJOR | `hooks/tests/run-tests.sh:104-111,475-502` | Concurrent full runs share one canonical result path and replace it only at completion | Two sessions can overwrite or misattribute evidence even if process cleanup is correct | Verified from the fixed result filename and non-atomic whole-report write.

## Recommended sequence

1. Lock CI as the sole release-evidence authority. Discriminator: local output cannot match the release-pass contract; `PUBLISHING`, runner headers, health-check text, and workflows agree.
2. Remove `cli-flow-profile` from required execution. Discriminator: required coverage totals remain semantically unchanged; only diagnostic-schema assertions leave the release gate.
3. Make the fast phase set the local default. Discriminator: three loaded-host MSYS runs complete within ten minutes without overrides.
4. Decompose `cli-flow-recovery`. Discriminator: all 31 predicates map to new tests, full `$PROJECT` clones fall from ten to one, and both CI jobs remain green.
5. Move and shrink `signal-reap` plus deterministic heartbeat testing into Windows CI. Discriminator: the pre-fix orphan field case is red, current code is green, essential collateral controls remain, and the job fits its shard budget.
6. Add required Linux and Windows/MSYS exact-SHA jobs. Discriminator: either red/timeout job makes `publish` unreachable.
7. Delete the old monolith, profile helper/test, fixed local release artifact, and timeout-override guidance. Discriminator: no required path invokes them and no release documentation cites them.

## What I could NOT verify

- The exact 4h30m, 805 PASS / 1 FAIL raw log was not retained in the repository. The incomplete current recovery trace corroborates noncompletion but not the complete total.
- The raw 1,568s and 1,813s historical recovery logs were also not retained; the repository explicitly records that limitation.
- I did not rerun the multi-hour gate; doing so would add no architectural information.
- I could not inspect current GitHub check status or repository tag-ruleset configuration from local files.
- No ordinary consumer timing exists; `docs/north-star.md` explicitly says that population remains unmeasured.

---
🔎 Phase: Verify
🎫 Ticket: gate-architecture-zoom-out
➡️ Next: operator/PO locks the CI-authoritative split before any harness implementation.
