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

**Decision:** Skip identical skill/agent copies and manifests, reuse one transcript read, and remove redundant validation at the actual Flow pre-commit boundary. CLI-owned validators and live secret/protected-path/release checks remain unchanged.

**Evidence identity:** exact command/arguments, working directory, relevant environment, full validator-visible source state (including unstaged/untracked inputs), staged tree identity, config, dependency contents/lock state, and toolchain identity. Compare before and after validation and immediately before reuse; concurrent change, missing identity, unsuccessful result, or mismatch reruns. No mtime-only or HEAD-only identity.

**Authenticity:** reuse only evidence created by the trusted validator runner with an authenticated receipt whose authority is outside repository-writable content; never trust an unsigned/self-asserted tracked or gitignored JSON file. The implementation must state its trust boundary and exclude arbitrary hostile same-user execution claims. If independent receipt authentication cannot be established on a host, rerun validators there and report reuse unavailable. Never add a secret/key to the repository. Replay on changed state, edited receipts and caller-asserted success must fail closed.

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
