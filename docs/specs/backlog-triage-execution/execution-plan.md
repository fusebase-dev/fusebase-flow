# Execution plan — backlog triage correction

**Status:** DRAFT — reissued after `STOP-AND-RESCOPE` · **Lane:** Full · **Execution rule:** no implementation before the task's dependency and decision gates pass
**Canonical plan:** `docs/specs/backlog-triage-execution/execution-plan.md`
**Evidence labels:** `VERIFIED` = directly established against shipped files/behavior · `HYPOTHESIS` = observation requiring repeated in-harness profiling · `UNVERIFIED` = must not drive a fix

North-star: On-vision
Dimension: constraint — mechanism over prose; retain the safety kernel and move maintainer-only work out of the consumer default
Recommendation: proceed with evidence-gated observability, lifecycle repair, and semantic-corpus work

## 1. Authoritative triage

**Population:** one static inventory of the tickets carried by the superseded plan; sample size `n=15`. T1 revalidates every row against `docs/backlog/index.md` and the matching ticket README before editing.

| Ticket | Authoritative status | Basis / next owner |
|---|---|---|
| `gate-bounds-lack-headroom` | active — S3A/S3B | Instrument first; choose gate-bound semantics only from repeated clean profiles |
| `harness-kill-leaves-orphan-children` | active — S2 | Begin with a retained failing reproduction against the shipped helper; root cause is not settled |
| `codex-plugin-packaging` | **shipped — v4.4.0** | `.codex-plugin/plugin.json` shipped; remove “pending release” |
| `local-gate-misses-manifest-freshness` | **re-scoped to maintainer lane** | Discrepancy is real; default consumer-gate placement was wrong |
| `self-granting-health-deferral` | **reopened** | `docs/health-check-deferrals.md:58,73` contradict `hooks/local/lib/active-approvals.sh`: object keys are accepted, so shipped prose does not describe the mechanism |
| `adapter-overlay-refresh-parity` | **reopened** | `GEMINI.md`, `.github/copilot-instructions.md`, and `.cursor/rules/fusebase-flow-always.mdc` carry duplicated material; the prior canonical-pointer rationale was false |
| `architect-sub-agent` | not planned — no measured PO context-cost defect | Closure remains; reopen only on observed consumer evidence |
| `role-path-hook-enforcement` | not planned — claimed structural guarantee remains fail-open | Closure remains; prompt-role extraction cannot support the proposed guarantee |
| `fr22-predelegation-hook` | not planned — no observed escape and shipped matchers omit delegation launch | Closure remains |
| `fr27-prelaunch-nudge` | not planned — warning prose adds no liveness mechanism | Closure remains |
| `repair-trust-root-outside-workspace` | **not-planned under locked threat model** | Hostile co-tenant/signing trust root remains outside K3 |
| `command-gate-shell-evasion` | active — semantic corpus and decision only | FR-06 safety-kernel gap; T5 is before any optional performance optimization; no parser patch authorized |
| `approval-single-use-consumption` | parked — stable cross-hook call identity and atomic reservation absent | No execution task in this round |
| `compat-approval-surfacing` | parked — carrier table absent | No execution task in this round |
| `install-into-existing-fusebase-cli-project` | automation parked; S1 documentation-ownership audit active | Fix the shipped install contract without starting installer automation |

**Closure set:** six rows, derived from this full inventory: one `shipped` row plus five `not planned` rows. `DONE` and `DROP` are prohibited status shortcuts for this triage.

## 2. Evidence register — cost and lifecycle

| ID | Status | Evidence, acquisition, sample size | Permitted conclusion |
|---|---|---|---|
| E1 | VERIFIED | `grep -c 'bash hooks/local/post-fusebase-update.sh' hooks/tests/test-cli-flow-recovery.sh` returned `9`; one static scan of one shipped test file (`n=1` file) | Nine literal call sites exist; no runtime share follows |
| E2 | VERIFIED | Search for `mirror-skills.sh --check` in the same file returned `0`; one static scan of one shipped test file (`n=1` file) | The superseded mirror-check count was false |
| E3 | HYPOTHESIS | `post-fusebase-update.sh` took `78s` in one direct invocation outside the harness (`n=1` invocation) | Candidate investigation signal only; not a harness attribution |
| E4 | HYPOTHESIS | A reduced-skill direct invocation took `31s` outside the harness (`n=1` invocation) | Candidate investigation signal only; does not select a fixture or support projected savings |
| E5 | HYPOTHESIS | Ten outer `cp -R $PROJECT` sites were found by one static scan (`n=1` file), interpreted with one timing sample (`n=1` run) | **The ten outer project-fixture clones did not dominate this one sample.** No percentage, cost share, shared-fixture design, or projected saving follows |
| E6 | VERIFIED | `hooks/tests/test-cli-flow-recovery.sh` has `954` lines by one static line count (`n=1` file); `policies/module-size-baseline.txt` contains the same `954` baseline in one row (`n=1` row) | Instrumentation must extract a responsibility seam; the baselined file may not grow |
| E7 | VERIFIED | One static inspection of `hooks/tests/run-tests.sh` shows `trap _ff_exit_reap EXIT`; one static inspection of `hooks/local/lib/run-with-timeout.sh` shows `FFHC_USE_JOB_OBJECT` defaults to `0` (`n=1` code path each) | The harness has an EXIT-only reaper; the Job Object fence does not run in this gate by default |
| E8 | VERIFIED | `hooks/local/lib/run-with-timeout.sh` defines `FFHC_TIMEOUT_KILL_GRACE` default `5s`; one static configuration read (`n=1` code path) | S2 reuses this exact cleanup deadline; no second grace constant is introduced |
| E9 | UNVERIFIED | Review reports the bounded phase is backgrounded and polled in `hooks/tests/run-tests.sh` around `:521-564`; not reproduced in this planning pass | If confirmed on the implementation-base SHA, it weakens the foreground-command trap-deferral theory; T3 must establish topology and timing before a cause is chosen |

**Deleted as unsupported:** runtime-share decomposition, health-drive count, clone percentage, dominant-cost selection, and projected savings. E3–E5 remain hypotheses until T6 publishes repeated clean in-harness profiles from one SHA.

## 3. Locked planning constraints

| ID | Constraint | Consequence |
|---|---|---|
| P1 | S3A is instrumentation-only | No fixture reduction, invocation consolidation, timeout change, shared state, or optimization selection in T2 |
| P2 | S3B requires repeated clean profiles from one exact SHA | Sample count is `UNKNOWN`; T6 pre-registers it before the first retained run, then publishes median, range, exclusions, and raw traces |
| P3 | No shared mutable fixture | No cross-scenario state reuse, order dependence, mutate/restore protocol, or contamination risk is accepted |
| P4 | Reduced skill fixtures are conditional, synthetic, and representative | If T7 selects this direction, fixtures cover a `SKILL.md`-only layout and a nested references/assets layout; every synthetic member is asserted in both provider mirrors; a separate `bash hooks/local/mirror-skills.sh --check` against the full production tree is mandatory |
| P5 | Fixture membership cannot be derived from current assertion mentions | That selection method is circular and prohibited |
| P6 | S2 cause is open | No causal theory is settled; T3 evidence precedes T4 design |
| P7 | S1 is expanded, not narrowed | The defect sits inside one install-ownership contract; a one-line edit would leave adjacent canonical/derived/plugin/hook claims unverified and could bless another unsafe path |
| P8 | Command-gate work precedes optional optimization | T5 may create a semantic corpus and decision record only; no parser/policy patch is authorized |
| P9 | UX is an operator-facing CLI contract | stdout/stderr, exit codes, timeout behavior, stall diagnostics, and provenance are acceptance surfaces |
| P10 | Every change task has one commit and one rollback | No task commit contains work from another T-number |

## 4. Slice contracts

### S0 — governance truth reset · Full lane

**Scope:** archive the legacy restart handoff before replacement; synchronize the triage statuses in `docs/backlog/index.md` and affected ticket READMEs; replace `docs/tmp/handoff.md` with one restart record pointing here.

**Why Full:** the exact changed-file count is `UNKNOWN`; T1 produces it before editing. The scope spans the active handoff, its archive, the backlog index, and multiple governance owners, so it fails Lightweight's single-concern/minimal-artifact gate.

**Required operation order:**

1. Inventory intended files and record pre-edit `git status`, branch, exact HEAD, active-handoff hash, and archive target.
2. Copy the untouched legacy handoff to `docs/tmp/handoff/archive/handoff-superseded-<YYYYMMDD>.md`; verify archive hash equals the recorded pre-edit hash.
3. Only after step 2 passes, replace `docs/tmp/handoff.md`.
4. Synchronize ticket status text; retain ticket evidence.

**Replacement handoff fields:**

| Field | Required value |
|---|---|
| `Mode` | `restart` |
| `Updated` | parseable timestamp with timezone captured at replacement |
| `Branch` | branch captured immediately before replacement |
| `HEAD` | exact full HEAD captured immediately before replacement |
| `Plan` | `docs/specs/backlog-triage-execution/execution-plan.md` |
| `Next` | one authoritative action: T2 instrumentation-only |

**Discriminator:** a validator must prove archive/pre-edit hash equality; metadata presence and parseability; branch/HEAD agreement with the captured pre-edit record; plan-path existence plus this plan's corrected status marker; and exactly one `Next` value naming T2. Grepping stale phrases is supplemental and cannot pass S0 by itself.

### S1 — install-document ownership audit · Full lane

**Chosen scope:** expand to a bounded audit; do not narrow to `skills` → `flow-skills` alone.

| Surface | Audit question |
|---|---|
| `.codex-plugin/` | Is it canonical install content, collision-sensitive content, or derived content; what copy/merge rule is truthful? |
| `.claude-plugin/` | Same ownership and collision analysis as `.codex-plugin/` |
| `flow-skills/` | Canonical source path is used consistently in Bash and PowerShell |
| `.claude/skills/`, `.agents/skills/` | Document as derived mirrors; do not blind-copy them as canonical source |
| Bash / PowerShell blocks | Source set, destination set, collision stops, and post-copy recovery are semantically symmetric |
| `--wire-hooks` | Claim is checked against `hooks/local/post-fusebase-update.sh:319-330`: default does not merge; opt-in merges only when prerequisites are present |

**Acceptance:** every documented source exists; canonical and derived ownership is explicit; both shell paths implement the same ownership contract; plugin collisions are review-gated; the `--wire-hooks` wording matches the shipped branch behavior. A scratch-install discriminator exercises both command blocks without modifying the repository.

### S2 — signal-safe gate teardown · Full lane

**Entry gate:** T3 runs first and retains a failing reproduction against the shipped helper. The reproduction captures the implementation-base SHA, shell/platform, signal, timestamps, POSIX identity, Windows identity, and process topology before signal, during cleanup, and after cleanup.

**Cause status before T3:**

| Claim | Status |
|---|---|
| EXIT-only trap exists | VERIFIED — E7 |
| Job Object path is disabled by default in this gate | VERIFIED — E7 |
| Foreground-command trap deferral causes the leak | UNVERIFIED |
| Reviewed bounded phase is backgrounded and polled around `run-tests.sh:521-564` | UNVERIFIED — E9; if confirmed, weakens the trap-deferral theory |

**TERM/INT semantics:**

| Concern | Contract |
|---|---|
| Cleanup deadline | Reuse `FFHC_TIMEOUT_KILL_GRACE`; default `5s` per E8 |
| Identity capture | At child launch capture POSIX PID/start token/PPID/PGID/SID and Windows PID/creation token/parent PID/executable identity |
| Before any kill | Re-resolve and compare the captured identity tuple; mismatch or missing identity means no kill |
| Scope | Target child and descendants only; never ancestor, caller shell, name-wide process set, or unrelated same-executable process |
| TERM exit | Cleanup, tear down helper/heartbeat, then exit `143` |
| INT exit | Cleanup, tear down helper/heartbeat, then exit `130` |
| Normal exit | Preserve existing exit status and success-path stdout; perform no kill |
| Auxiliary processes | Heartbeat and Job Object/helper processes, when present, are stopped and reaped on every signal path and normal completion |
| Failure diagnostic | stderr names signal, scoped target identity, cleanup result, and next action without dumping command line or environment |

**Control set:** target child and target grandchild are gone before the E8 cleanup deadline; caller shell survives; an independently launched same-executable sibling survives; PID-reuse/identity mismatch causes no kill; normal exit performs no kill; behavior is stable across repeated runs. Repeat count is `UNKNOWN`; T3 pre-registers it before repetition and retains every run result.

**Platform knowledge:** T3/T4 update or cross-link both `docs/problem-catalog/bounded-run-msys-collateral-kill/problem.md` and `docs/problem-catalog/run-tests-never-completes-msys/problem.md`, distinguishing external TERM/INT teardown from deadline reap and preserving the strict identity guardrail.

### S3A — recovery observability only · Full lane

**Module-size strategy:** extract profiling/timing/trace formatting into `hooks/tests/lib/cli-flow-recovery-profile.sh`, a named observability seam. `hooks/tests/test-cli-flow-recovery.sh` remains at or below its verified `954`-line baseline; it may source the helper and add labels only by moving at least the added line count out. Mechanical `utils` extraction and baseline growth are prohibited.

**Output contract:**

- Named scenario/substep start and completion events go to the retained raw trace and stderr.
- Existing `PASS:`, `FAIL:`, `INCONCLUSIVE:`, total, and final summary stdout shapes remain parser-compatible.
- Success-path stdout line count does not increase.
- stderr is limited to start, configured-cadence heartbeat, completion, and failure-only diagnostic events; no per-poll output, duplicate unchanged status, or success-path process dump.
- Instrumentation inventories the shipped assertion groups without changing their names, predicates, fixtures, or count. The baseline count is `UNKNOWN`; T2 records it from the implementation-base SHA.
- T2 selects no optimization and changes no timeout or fixture topology.

### S4 — command-gate semantic corpus and decision · Full lane

**Scope authorized:** corpus and decision work only.

**Corpus contract:** record shell-semantic equivalence, current gate result, desired gate result, false-positive class, and handler parity for literal commands, quote fragmentation, escapes, separators, variables, substitutions, and dynamically constructed gated commands. Cases must distinguish “shell executes the gated action” from lexical lookalikes that do not.

**Decision output:** choose a parser/conservative-deny direction or record `NO IMPLEMENTABLE DECISION`; enumerate accepted false positives/negatives and platform assumptions. The operator/PO locks any implementation direction later. T5 must not edit `hooks/shared/command_policy.py`, `policies/command-policy.yml`, or any parser implementation.

### S3B — repeated profiles, bound contract, and optimization gate · Full lane

**Profile preconditions:** S3A merged; S2 control set green; no target/sibling orphan detected; clean worktree except designated trace outputs; one exact SHA; no skip or timeout override.

**Profile protocol:** T6 pre-registers the repeat count (`UNKNOWN` until then) before the first retained run. Every included run records raw scenario/substep traces; excluded runs remain retained with exclusion reason. Publish per-event median and range, exact SHA, platform/shell, effective defaults, and orphan check. The outside-harness E3/E4 samples are not members of this profile set.

**Optimization decision:** T7 returns exactly one status:

- `SELECT <mechanism>` — only when repeated profiles identify a reproducible cost and an isolated experiment preserves assertion strength; exact target files and rollback are added before T8 starts.
- `CANCEL optimization` — when evidence does not justify a mechanism; T8 does not run and no performance code is committed.

No shared mutable fixture may be selected. A reduced skill fixture may be selected only under P4/P5 and only with a separate full-production mirror check. No projected savings are accepted; only observed profile distributions are reported.

**Gate-bound decision:** T7 also records the default absolute bound and, if used, stall deadline from T6 data; both values are `UNKNOWN` until T7. A scalar increase without a progress model is prohibited.

**Stall-progress semantics:**

- Progress is a unique, monotonic named milestone: scenario/substep start, assertion-result advance, or scenario/substep completion emitted by the instrumentation helper.
- The stall timer starts at phase launch and resets only when the milestone sequence advances.
- Heartbeats, polls, repeated text, process existence, timestamp-only/mtime changes, and duplicate milestones do not reset it.
- A stall emits an actionable stderr diagnostic naming the last completed and current milestone, elapsed stall state, absolute-bound state, trace pointer, and rerun action; it exits with the existing timeout classification.
- Absolute deadline remains a liveness backstop even when milestones advance.

### S5 — assertion-strength and two-platform gate

**Final SHA:** one exact post-T8-or-cancellation and post-S1 SHA. Windows/MSYS and Linux `ubuntu:24.04` run that same SHA with committed defaults, unscoped, without skip/timeout overrides.

**Pass contract:** all baseline assertion names and predicates remain present; synthetic reduced-fixture members, if selected, pass in both provider mirrors; the separate full-production mirror check passes; signal controls pass on Windows/MSYS; stdout parsers remain stable; provenance allowlist is complete; both platform gates pass. No release claim follows automatically.

## 5. Provenance, redaction, and CLI UX acceptance

### Provenance allowlists

| Artifact | Allowed fields | Forbidden / redacted |
|---|---|---|
| S2 topology trace | timestamp, role, signal, POSIX PID/PPID/PGID/SID/start token, Windows PID/parent PID/creation token, executable basename/path hash, parent-child edge, identity-match result, liveness result | raw command line, full executable path, username/home path, environment, file contents; repository/temp roots normalized to `$REPO`/`$TMP` |
| Recovery profile trace | exact HEAD, platform, shell, scope, scenario/substep ID, monotonic milestone sequence, start/end timestamps, duration, result, exclusion reason | arbitrary environment, raw subprocess argv, file contents, user-specific absolute paths |
| `state/audit/hook-test-results.md` | exact HEAD, platform, shell, scope, start timestamp, duration, result, effective timeout/stall values, raw-trace pointer, non-default allowlisted `FF_*` values | all other environment variables; any value whose name matches `TOKEN`, `SECRET`, `KEY`, `PASSWORD`, `AUTH`, or `COOKIE` is `[REDACTED]` |

**Allowlisted `FF_*` names:** `FF_ONLY`, `FF_SKIP_CLI_RECOVERY`, `FF_CLI_RECOVERY_TIMEOUT`, `FF_PHASE_TIMEOUT`, `FFHC_TIMEOUT_KILL_GRACE`, `FFHC_USE_JOB_OBJECT`, `FFHC_HEARTBEAT_SECS`. The artifact records absence/default explicitly; it never dumps the environment.

### Output and parser compatibility

| Surface | Acceptance |
|---|---|
| stdout | Existing summary and `PASS:`/`FAIL:`/`INCONCLUSIVE:` shapes remain byte-compatible for parsers; instrumentation adds no success-path stdout |
| stderr | Progress/timing/stall/cleanup diagnostics are actionable; no unchanged poll spam, raw process dump on success, or repeated advice |
| exit codes | Normal child status preserved; timeout classification preserved; external TERM=`143`; external INT=`130` |
| timeout UX | Diagnostic distinguishes absolute timeout, stall timeout, external signal, identity mismatch, and assertion failure |
| artifact UX | Every diagnostic cites the raw-trace pointer and exact HEAD; scoped output cannot be mistaken for full-gate evidence |

## 6. T-numbered execution tasks

| Task | Slice / owner | Exact targets or target rule | Depends on | Commit boundary | Verification owner | Rollback |
|---|---|---|---|---|---|---|
| T1 | S0 · Product Owner/Architect | `docs/tmp/handoff.md`; collision-free archive under `docs/tmp/handoff/archive/`; `docs/backlog/index.md`; only ticket READMEs whose §1 status differs after pre-edit inventory | — | Governance truth only; exact file count recorded in commit body | Architect cross-owner consistency check | Revert T1; restore archived handoff as active only if rollback requires the legacy direction |
| T2 | S3A · AI Developer | `hooks/tests/test-cli-flow-recovery.sh`; new `hooks/tests/lib/cli-flow-recovery-profile.sh`; new `hooks/tests/test-cli-flow-recovery-profile.sh`; trace schema | T1 | Instrumentation/extraction only; no optimization/fixture/timeout change | Independent parser + module-ratchet review | Revert T2; removes helper and restores pre-instrumentation harness |
| T3 | S2 red arm · AI Developer | new `hooks/tests/test-run-tests-signal-reap.sh`; `state/audit/run-tests-signal-reap/<full-head>/`; `docs/backlog/harness-kill-leaves-orphan-children/README.md`; both platform problem-catalog entries | T2 | Reproduction/evidence only; manual red arm fails against shipped helper but is not wired as a required green gate yet | Windows/MSYS verifier | Revert T3; no production behavior changed |
| T4 | S2 fix · AI Developer | `hooks/tests/run-tests.sh`; existing scoped identity/timeout helper only where T3 proves needed; T3 regression test; both platform problem-catalog entries | T3 | Signal lifecycle fix and gate wiring only | Independent Windows/MSYS control-set verifier | Revert T4; T3 retained red arm remains available and unwired |
| T5 | S4 · Architect + test author | `docs/backlog/command-gate-shell-evasion/README.md`; new `hooks/tests/fixtures/command-gate-semantic-corpus.json`; `hooks/tests/test-command-policy.sh` | T1; complete before T7 | Corpus + decision record; no parser/policy implementation | Independent FR-06 semantic review; operator/PO locks any later implementation | Revert T5; shipped gate behavior unchanged |
| T6 | S3B profile · Verification owner | raw traces plus `summary.md` under `state/audit/cli-flow-recovery-profiles/<full-head>/` | T2, T4 | Evidence only; one SHA, pre-registered sample count, median/range/raw traces | Independent trace/provenance audit | Revert T6 evidence commit; rerun protocol on one new exact SHA |
| T7 | S3B decision · Architect | `docs/backlog/gate-bounds-lack-headroom/README.md`; this plan's decision-status fields; exact T8 targets if selected | T5, T6 | `SELECT <mechanism>` or `CANCEL optimization`; gate-bound/stall contract only | Operator/PO decision lock + independent assertion-strength review | Revert T7; no optimization may remain authorized |
| T8 | S3B conditional implementation · AI Developer | `UNKNOWN` until T7 names exact files; no task starts with an unresolved target | T7=`SELECT` only | Selected optimization only; absent when T7=`CANCEL optimization` | Independent profile comparison + assertion-strength verifier | Revert T8; retain T2 observability and T4 lifecycle fix |
| T9 | S1 · AI Developer | `docs/install-fusebase-cli-project.md`; new `hooks/tests/test-install-fusebase-cli-project-doc.sh`; no installer automation | T1 | Bounded ownership-audit correction only | Bash + PowerShell verifier on scratch destinations | Revert T9; automation ticket remains parked |
| T10 | S5 · Verification owner | `state/audit/hook-test-results.md`; final profile/gate evidence; affected ticket status evidence only | T4, T7, T8 when selected, T9 | Verification evidence only; no source fix folded into gate commit | Independent Windows/MSYS + Linux gate owner; PO consumes report | Revert T10 evidence commit; source commits remain independently revertible |

## 7. Dependency and stop gates

| Gate | Must be true before proceeding | Stop result |
|---|---|---|
| G0 | T1 archive hash + structured handoff discriminator pass | Stop before any code task |
| G1 | T2 emits parser-compatible raw events and module ratchet passes without growth | Stop before S2 reproduction |
| G2 | T3 reproduces and retains target/grandchild leak with complete identity/topology evidence | If not reproducible, mark S2 `BLOCKED-AT-reproduction`; do not patch |
| G3 | T4 passes the full signal control set across the pre-registered repeated runs | Stop before performance profiles |
| G4 | T5 corpus and decision record complete; no parser patch present | Stop before optional optimization decision |
| G5 | T6 clean profiles share one SHA and publish median/range with raw traces | T7 must `CANCEL optimization` if the evidence cannot select safely |
| G6 | T7 names exact targets and assertion controls, or records cancellation | T8 forbidden without `SELECT` |
| G7 | T10 assertion-strength, production-mirror, provenance, parser, and two-platform gates pass on one final SHA | No release claim; return gate report for review |

**Execution kernel:** T1 governance reset → T2 instrumentation → T3 failing reproduction → T4 S2 fix → T5 command-gate corpus/decision → T6 repeated profiles → T7 select or CANCEL optimization → T8 conditional implementation → T9 install audit → T10 assertion-strength and two-platform validation. T9 is technically independent after T1 but must land before T10.

## 8. Acceptance criteria

| AC | Requirement | Owner task |
|---|---|---|
| AC1 | All triage statuses match §1; only the six defensible closures remain; reopened and maintainer-lane tickets are not labeled DONE/DROP | T1 |
| AC2 | Legacy restart handoff is archived before replacement; replacement metadata and corrected-plan pointer pass the structured discriminator | T1 |
| AC3 | S3A selects no optimization, preserves parser stdout, emits bounded-noise traces, and keeps the baselined test file at or below `954` lines | T2 |
| AC4 | S2 starts with a retained red reproduction against the shipped helper and captures POSIX/Windows identity plus full target topology | T3 |
| AC5 | TERM/INT cleanup uses the existing `5s` default grace, revalidates identity before kill, returns `143`/`130`, reaps helper/heartbeat, and passes every collateral/reuse/repetition control | T4 |
| AC6 | Both named MSYS problem-catalog entries are updated or cross-linked with the external-signal defect and guardrails | T3, T4 |
| AC7 | Command-gate semantic corpus and decision precede optional optimization; no parser/policy patch lands | T5 |
| AC8 | Repeated clean profiles use one exact SHA; sample count is pre-registered; median/range are published; raw and excluded traces are retained | T6 |
| AC9 | Optimization is explicitly selected from clean evidence or cancelled; shared mutable fixtures and projected savings are absent | T7 |
| AC10 | Any reduced skill fixture is synthetic and multi-layout, asserts every member in both mirrors, and passes a separate full-production mirror check | T8, T10 |
| AC11 | Stall progress/reset semantics match S3B; heartbeat/poll/mtime noise cannot postpone a stall | T7, T8, T10 |
| AC12 | Provenance fields obey the allowlist/redaction contract; scoped/overridden evidence is self-identifying | T2, T3, T6, T10 |
| AC13 | stdout/stderr, exit-code, timeout, failure-message, parser-stability, and noise-limit contracts pass | T4, T10 |
| AC14 | S1 audit covers both plugin directories, canonical `flow-skills`, derived mirrors, Bash/PowerShell parity, and the shipped `--wire-hooks` behavior | T9 |
| AC15 | Final Windows/MSYS and Linux `ubuntu:24.04` unscoped gates pass on the same exact SHA with committed defaults and no skip/timeout override | T10 |

## 9. Explicitly out of scope

- C0, M1A, the classifier work, and roadmap S5–S9; their parked artifacts remain non-authoritative for this execution.
- Any new FR, rule, or skill.
- Any claim that artifacts are signed, operator-authenticated, or identity-bound; the repository has no signing seam.
- Parser or policy implementation for `command-gate-shell-evasion`; T5 authorizes corpus and decision work only.
- Shared mutable recovery fixtures; order-dependent mutate/restore protocols.
- Database/data/schema migrations and production service deploy: N/A — this repository has no database or production runtime service in this scope.
- Page/component UI, routes, visual theming, and client/internal page design: N/A. Operator-facing CLI UX is in scope under §5.
- Release publication: out of scope. T10 produces review evidence only.
- Auth/sign-in/session/role product problem-catalog work: N/A. Platform problem-catalog work is in scope for S2, specifically `bounded-run-msys-collateral-kill` and `run-tests-never-completes-msys`.

## 10. Verification ownership summary

| Evidence | Producer | Independent checker | Consumer |
|---|---|---|---|
| S0 structured truth reset | Product Owner/Architect | cross-owner metadata/status checker | next AI Developer session |
| S2 red/green topology traces | AI Developer on Windows/MSYS | separate Windows/MSYS verifier | T6 profiler + reviewer |
| S3A parser/module proof | AI Developer | parser/module-ratchet reviewer | T6 profiler |
| S4 corpus/decision | Architect + test author | FR-06 semantic reviewer | operator/PO lock |
| S3B profiles/decision | Verification owner + Architect | raw-trace/assertion-strength reviewer | operator/PO lock |
| S1 scratch install parity | AI Developer | Bash and PowerShell verifier | T10 gate owner |
| Final same-SHA gates | Windows/MSYS and Linux gate owners | independent cross-artifact reviewer | Product Owner; no automatic deploy/release |
