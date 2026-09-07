# Flow performance and recovery hardening — decisions

**Letter prefix:** A
**Approval status:** LOCKED by operator instruction on 2026-09-05
**Scope:** `spec.md` AC1..AC12

## A1 — Recovery owns exact regions and named Flow commands

**Lock status:** LOCKED

**Decision:** Replace only one validated Flow marker span and add/remove only recognized Flow hook commands. Preserve all bytes and hook blocks outside those owned spans.

**Alternatives considered:**

| Alternative | Rejected because |
|---|---|
| Continue BEGIN→EOF replacement | demonstrably deletes trailing external instructions |
| Rewrite entire provider files from snapshots | violates CLI/operator ownership and loses custom state |

## A2 — Restore prior integration intent; keep first-time activation opt-in

**Lock status:** LOCKED

**Decision:** Valid enabled nonempty same-project intent authorizes only its recorded surfaces. Schema-1 hook intent authorizes Claude settings restoration only; it never implies prior Git-hook installation. Missing/revoked/malformed/foreign/unverifiable intent does not authorize new integrations.

| Surface | Restoration evidence / missing-state rule |
|---|---|
| Claude settings | Valid settings intent: repair exact Flow commands/matchers; absent file: create minimal Flow-only settings, never infer lost CLI/user settings; report lost external-state uncertainty as partial |
| AGENTS/CLAUDE overlay | Existing unambiguous owned block or recorded surface inventory authorizes repair; absent provider file: restore only backed-up original bytes plus validated overlay; without recoverable external bytes report partial, never synthesize a CLI base |
| Skills, agents, commands | Installed canonical inventory plus verified ownership authorizes missing/drift repair; collisions with unowned content remain untouched and report partial |
| Git hooks | Prior per-surface intent plus recognized installed Flow hook/receipt authorizes repair; schema-1 settings intent alone cannot install Git hooks; absent/custom hooks without prior proof remain untouched |
| Opt-out / unsupported evidence | Preserve bytes; report per-surface skipped/unverified reason; never silently treat unsupported prior intent as complete |

**Failure contract:** Before any target mutation, compute the complete applicable repair plan and validate source ownership, required sources, marker spans, settings JSON and configuration. Invalid/unavailable inputs yield failed/exit 2 with zero target writes. Stage replacements beside destinations, retain original recovery material, atomically replace each file; no claim of multi-file transaction atomicity. Mid-apply error/interruption yields partial/exit 1 with applied/pending surface inventory and backup paths; a durable in-progress record prevents the next run from claiming complete without re-verification. Retry revalidates and converges without duplicating hooks or overwriting external bytes. Complete/exit 0 requires all authorized expected surfaces verified; diagnostic output is separate from repair targets.

**Alternatives considered:**

| Alternative | Rejected because |
|---|---|
| Require `--wire-hooks` after every update | recovery can report success while a previously enabled safety layer remains absent |
| Always wire hooks during recovery | converts repair into a new integration/permission choice |

## A3 — Recovery configuration is installed and complete

**Lock status:** LOCKED

**Decision:** Recovery uses configuration shipped with the installed recovery engine. Incidental local/parent staging trees are ignored. An alternate source requires explicit verified input and a complete expected Flow handler/matcher set; no non-Flow command can stand in for a missing Flow handler.

**Alternatives considered:**

| Alternative | Rejected because |
|---|---|
| Auto-discover any nearby staging checkout | stale/partial sources can silently disable enforcement |
| Accept the first command in an event | can misclassify a CLI hook as Flow recovery configuration |

## A4 — Lightweight is the consumer default with objective escalation

**Lock status:** LOCKED

**Decision:** Allow bounded read-only diagnosis before lane classification. Ordinary low-risk changes use one-pass lightweight execution. Full activates on observable auth, permissions, secrets, data/schema, public-contract, production/release, protected-path, cross-cutting architecture, or unresolved product-decision triggers.

| Owner | Contract |
|---|---|
| Path router | Changed paths in; structured matched paths/trigger IDs out; input error is nonzero and never Lightweight; no-match means only no mechanical match |
| AI semantic assessor | Inspect diagnosed behavior/diff and declare each risk trigger with evidence path/reason in the existing change-note or Full spec; sensitive logic in ordinary filenames still escalates |
| Lane decision | Mechanical match OR semantic trigger → Full; incomplete assessment → bounded diagnosis, then BLOCKED-AT-lane-assessment if unresolved, never an inferred safe result |
| Workflow fixture runner | Persist router result, assessor declarations, final lane, decisions/relays and created artifact inventory; assert ordinary one-pass vs sensitive Full behavior separately from router unit tests |

T6 aligns role references and all behavioral carriers before T7 compaction; file count or unknown cause alone is not a sensitive trigger.

**Alternatives considered:**

| Alternative | Rejected because |
|---|---|
| “In doubt → Full” | contradicts the locked North Star and converts uncertainty into ceremony |
| Remove Full lane | discards useful controls for sensitive and cross-cutting work |

## A5 — Compact instructions around one authoritative core

**Lock status:** LOCKED

**Decision:** Keep one always-on safety/ownership core, short role deltas, and on-demand procedure references. Provider adapters point to canonical owners and remain self-bootstrapping without reprinting full protocol bodies.

**Alternatives considered:**

| Alternative | Rejected because |
|---|---|
| Keep duplicated bodies for every surface | charges every session and drifts across mirrors |
| Rely only on provider auto-loading | unsupported across the declared mixed fleet |

## A6 — Remove proven duplicate work; do not invent unsafe validation caching

**Lock status:** LOCKED

**Decision:** Skip identical skill/agent copies and manifests, reuse one transcript read, and execute composed heavy health/liveness coverage once. Validator reuse remains disabled globally by T53; normal validators still run. CLI-owned validators and live secret/protected-path/release checks remain unchanged.

**Current delivered boundary (T53):** caller-declared completeness cannot establish exhaustive validator inputs. Reuse is unavailable globally, including old receipts; the real runner executes validators and propagates failure without signing. Future reuse requires a separately proven completeness/authority contract, not another declaration.

**Authority:** no current host is accepted for reuse. No successful HMAC reuse or duplicate lint/typecheck elimination is claimed. Live secret/protected/release checks remain enabled.

**No-op scope:** all recovery target files, manifests, settings backup/receipt/intent, and Git hooks retain bytes/mtimes. New run diagnostics are separately named evidence, excluded from target write counts, never used as a pretext to refresh intent or ownership.

**Alternatives considered:**

| Alternative | Rejected because |
|---|---|
| Disable CLI Stop validators | harms CLI behavior and removes a real safeguard |
| Add a broad “tests already ran” cache | stale success can bless different source or dependencies |

## A7 — Measurements distinguish history from the selected window

**Lock status:** LOCKED

**Decision:** Historical artifact evidence remains useful but is labeled separately. Window-specific conclusions require task/commit linkage. Performance claims use actual consumer measurements where available and declare missing metrics.

**Alternatives considered:**

| Alternative | Rejected because |
|---|---|
| Treat all artifacts as part of `--window N` | current behavior cites evidence outside the requested window |
| Remove historical evidence | loses useful low-frequency safety counterexamples |

## B1 — Validator reuse fails closed on identity or authority incompleteness

**Lock status:** LOCKED by corrective instruction, 2026-09-06

**Future eligibility requirement, not currently enabled:** Reuse would require that the trusted runner owns validator child execution and receipt signing and can prove the complete validator-visible state: declared ignored inputs/dependencies, followed symlink targets, every validator-affecting environment value, commands, wrappers, interpreters, package runners, and toolchain binaries. Remove public success minting. A direct mint, substituted runner, failed/skipped validator, incomplete identity, concurrent mutation, or unproved external authority disables reuse and runs validators normally.

| Alternative | Rejected because |
|---|---|
| Add the four missing hashes to the current begin/finish API | public finish still signs success without proving validator execution |
| Treat same-user key storage as independent authority | the invoking user can call the signer directly; Windows ACL authority is unproven |
| Keep reuse on partial identity with a warning | stale validation can bless a different dependency/input/toolchain state |

## B2 — Recovery is ownership-classified, planned before writes, and verified after apply

**Lock status:** LOCKED by corrective instruction, 2026-09-06

**Decision:** Build the complete recovery plan before target writes. Each destination is classified `current`, `missing-and-authorized`, `owned-repair`, `unowned-collision`, or `unsafe` (including symlinks). Preserve collisions as partial, retain originals for owned repairs, and use atomic per-file replacement. Persist plan/applied/verified/pending state without resetting an interrupted run. Exit 2 means invalid plan and zero target writes; exit 1 means partial/uncertain end state; exit 0 requires a fresh parsed/hash verification of every authorized surface.

Provider restoration requires verified original bytes or an explicit partial uncertainty. Git-hook restoration requires per-surface intent plus exact installed Flow ownership; command output text is not proof.

| Alternative | Rejected because |
|---|---|
| Continue best-effort sequential writes and summarize warnings | later invalid input can leave earlier mutations and status can outrun reality |
| Overwrite any path whose name matches a Flow asset | path name does not prove ownership and loses user/CLI content |
| Claim transaction-wide atomicity | the implementation can guarantee atomic replacement per file, not one atomic multi-file commit |

## B3 — Hook ownership is exact and Flow scope is isolated

**Lock status:** LOCKED by corrective instruction, 2026-09-06

**Decision:** Recognize only exact canonical/current legacy Flow commands for the expected event. Move an exact Flow command out of a mixed custom block into a dedicated Flow block before applying Flow matcher changes. Preserve custom command order, matcher, timeout, and scope byte/semantically; substring lookalikes are unowned. Deduplication produces one dedicated exact Flow block with the full Flow matcher even when the first duplicate was restrictive.

| Alternative | Rejected because |
|---|---|
| Treat any `hooks/handlers/` path as Flow-owned | custom paths and arguments can match the substring |
| Widen the first block containing a Flow command | a mixed block silently widens every custom command in that block |

## B4 — Markerless overlays require a proven end boundary

**Lock status:** LOCKED by corrective instruction, 2026-09-06

**Decision:** Marker-wrapped overlays remain the normal owned span. Ownership markers and recognized adapter headings are exact logical lines; an optional terminal CR is accepted, while inline/backticked prose is ignored. Markerless migration is allowed only for a fully recognized legacy layout with a proven terminal boundary. A suffix, custom heading, unrecognized section, duplicate boundary, or any ambiguity returns exit 2 with zero target/backup writes.

| Alternative | Rejected because |
|---|---|
| Keep heading-to-EOF ownership | unrelated instructions after the legacy overlay are deleted |
| Guess the boundary from Markdown heading level alone | consumer headings are not ownership markers |

## B5 — Evidence linkage and performance claims derive from executed outcomes

**Lock status:** LOCKED by corrective instruction, 2026-09-06

**Decision:** A window conclusion needs structured outcome/task/commit linkage; file recency or an arbitrary SHA mention cannot promote the whole artifact. Mixed reports partition conclusions individually. Workflow evidence counts actual actions and created artifacts, with mutation controls for extra relay/artifact and skipped diagnosis. No-op write claims require three independent write-mode recoveries with byte/mtime/write evidence; `--check` is read-only integrity evidence only.

| Alternative | Rejected because |
|---|---|
| Link the whole file by its latest commit or any SHA in its body | a cosmetic footer or unrelated reference promotes historical outcomes |
| Count fixture constants as workflow outcomes | the test verifies its own assignments rather than the workflow |
| Infer zero writes from `--check` | the command performs no writes by design |

## B6 — Risk-scoped local acceptance; complete release evidence remains distinct

**Lock status:** LOCKED by operator acceptance of the testing-strategy adversarial review, 2026-09-07.
**Decision:** Local acceptance uses an explicit changed-risk/AC-to-test ledger, never a mandatory monolithic local rerun. Record source/input dependencies, command, platform, result and durable evidence; changed or unknown dependencies invalidate only affected rows. Prior results are not reusable solely because HEAD or filenames match. Missing evidence stays open. Scoped/fast summaries remain visibly partial and cannot satisfy full-suite classifiers. Normal secret/protected/precommit gates remain live.
**Coverage tiers:** per-change positive/negative contract and affected callers; pre-merge local AC acceptance; broad mutation/compatibility/platform suites in existing maintainer/release CI. `.github/workflows/fusebase-flow-verify.yml` actually invokes the unscoped suite on Linux/Windows; runner selects full under GITHUB_ACTIONS; release workflow structurally requires verify. No push/PR/nightly trigger exists: do not claim those jobs ran or are scheduled. No workflow correction is required. Future nightly scheduling is optional backlog, not T33.
**Economy:** no equivalent-state nested full suite; one execution owns output/status. Each selected phase exposes start/end/elapsed/rc and its configured timeout budget. A timeout is failure, not permission to raise bounds. Local launch declares expected budget and reevaluates unexplained overruns. Full summary stays reserved for actual full runs; exact tagged-SHA CI remains release authority.
**Closeout:** final T22 ZERO BLOCKERS at559ca5a; final implementation T59 `e99d61b`; T60 release-evidence reconciliation is documentation-only. tasks.md owns completed slice order; gate-report.md owns proof.
**Residual disposition:** actual CLI `2026.090414.3609` compatibility is observed in the recorded Windows/Git Bash consumer scenario. Tagged Linux and Windows/MSYS release CI, unexecuted real-symlink cases, five-provider delivered-context telemetry, and Windows authority isolation/successful signing remain DEFERRED/UNVERIFIED. Validator reuse is globally unavailable: validators execute normally on every platform. T57 adds observability only and establishes no runtime speedup.

**T48 validation economy:** completed via shared real fixture/boundary; four prior results retained, remaining4/4. No repeated full-precommit matrix. Exact evidence and original timeout retained in gate-report.md.
