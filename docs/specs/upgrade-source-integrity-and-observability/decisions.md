# Decisions — upgrade-source-integrity-and-observability

**Letter prefix:** M
**Approval status:** LOCKED 2026-07-30 under the operator's standing end-to-end autonomous-run authorization. M1/M6 are revised; M9/M10 are added and locked. Each lock is a PO recommendation the operator did not individually confirm; flagged **ASSUMPTION** where a different call changes the work.
**Linked spec:** `docs/specs/upgrade-source-integrity-and-observability/spec.md`

## Decision matrix

| ID | Title | Recommendation | Lock status |
|---|---|---|---|
| M1 | Fix the source, not the symptom | Force-LF verified incoming `U`; as-found local `L`; consumer-EOL K13 base `B` | LOCKED — REVISED 2026-07-30 |
| M2 | The hasher stays byte-exact | No line-ending normalization in integrity hashing | LOCKED |
| M3 | Keep tempfile capture; add a parent heartbeat | Never switch to `tee`/pipe streaming | LOCKED |
| M4 | Backup exclusion is exact-shape only | Prune `<name>.pre-upgrade-<UTC>` families; no `.pre-*` wildcard; no secret-scan bypass | LOCKED |
| M5 | Cleanup gets a validated tool, not looser guidance | New script; FR-06 deny stays intact | LOCKED |
| M6 | Re-point `v4.7.0`; do not invent `v4.7.1` | Remote tag was visible; re-point only with notice + explicit authorization | LOCKED — REVISED 2026-07-30 |
| M7 | Close F1/F3/F4 as no-code | Already-fixed / refuted; strengthen bootstrap docs only | LOCKED |
| M8 | F7 is a parser project, not a patch | Own ticket, own review cycle; naive narrowing forbidden | LOCKED |
| M9 | Approval staleness is visibility-only | Additive `created_at`; separate warnings; authorization/verdict unchanged | LOCKED |
| M10 | Non-git source compatibility is explicit | Verify manifest-bearing sources; named unverified fallback only for pre-manifest sources | LOCKED |

## M1. Fix the source, not the symptom

**Recommendation:** Enforce three distinct byte models; never collapse them.

| Model | Required bytes | Source |
|---|---|---|
| Incoming `U` | Forced LF on every OS; verify before use | `git -c core.autocrlf=false archive <resolved-commit>` |
| Existing local `L` | Consumer bytes exactly as found | Consumer working tree |
| Historical base `B` | Consumer EOL convention | K13 synthesis only: `git -c core.autocrlf=<consumer-setting> archive <prior-tag>` (`bootstrap-upgrade.sh:198-209`) |

For a git source, `bootstrap-upgrade.sh` resolves `<ref>^{commit}`, materializes absolute `SOURCE_TREE`, verifies it, then invokes the engine from that tree with internal absolute `--source-tree`, absolute `--source-repo`, and full-OID `--source-commit`. A plain source omits `--source-commit` and follows M10. `SOURCE_REPO` is used only for git/plain-directory detection, ref resolution, and metadata. Every incoming content read uses `SOURCE_TREE`. Materialization and an early cleanup trap precede every read or source operation on source-derived content.

**Reasoning:** `.gitattributes:19-20` already pins `*.json`/`*.jsonl`; the blobs are LF. The CRLF exists only in a persistent worktree populated under `core.autocrlf=true` before `601574d`, then advanced without rewriting unchanged files. `upgrade.sh:496` copies those worktree bytes. Incoming `U` must therefore ignore consumer/global EOL and match the shipped byte manifest. K13 `B` has the opposite purpose: it models what the consumer previously received, so it alone must retain consumer EOL. Forced LF for `B` makes untouched CRLF local files appear modified; consumer EOL for `U` makes the incoming tree fail its own manifest.

**Alternatives considered:**

- **Option A: add more `.gitattributes` pins** — rejected: the pins already exist; this fixes nothing and would be recorded as a fix.
- **Option B: normalize in the hasher** — rejected, see M2.
- **Option C: use consumer `core.autocrlf` for incoming `U`** — rejected: recreates F2 and disagrees with the shipped manifest.
- **Option D: force LF for historical `B`** — rejected: misclassifies untouched CRLF consumer files as local edits.
- **Option E: force a fresh clone every upgrade** — rejected: discards the persistent-clone design and its offline/bandwidth properties. Materializing from objects gets canonical bytes and keeps the cached clone.

**Lock status:** LOCKED — REVISED 2026-07-30

---

## M2. The hasher stays byte-exact

**Recommendation:** Do **not** normalize line endings before hashing in `hook_manifest.py` or `managed_content_manifest.py`.

**Reasoning:** A byte-exact manifest exists to detect exactly one thing: content that is not what upstream shipped. Normalizing before hashing makes the manifest blind to the corruption class it was built to catch, and would have hidden this very bug — the consumer's tree genuinely did contain wrong bytes. The drift report was **correct**; the upgrade that produced those bytes was wrong. Weakening the detector to silence a true positive is the wrong direction, and it would make future transport bugs undiagnosable rather than merely annoying.

**Alternatives considered:**

- **Option A: normalize for `*.jsonl`/`*.json` only** — rejected: same blindness, narrower. Also leaves the real transport bug live.
- **Option B: store both raw and normalized hashes, warn on normalized-only match** — genuinely tempting and would have diagnosed this faster. Rejected for this ticket as scope creep once M1 removes the cause; noted as a possible future diagnostic.

**Lock status:** LOCKED

---

## M3. Keep tempfile capture; add a parent-owned heartbeat

**Recommendation:** `run-with-timeout.sh` keeps redirecting the child's streams to a tempfile. Add an **optional parent-owned heartbeat** that prints progress to stderr on a bounded interval while the child runs. `run-tests.sh` and `hook-integrity-check.sh`'s deep run opt in.

**Reasoning:** The reporter diagnosed libc/Python buffering and proposed `stdbuf` / `PYTHONUNBUFFERED` / explicit flushes. None of those can work: the parent redirects the **entire** child stream into a tempfile (`run-with-timeout.sh:462-493`) and only reads it at `:534-539`. No amount of child-side flushing escapes a parent redirect. `run-tests.sh` already emits immediate stderr markers (`:112-129`) — they are being swallowed, not withheld.

Switching to `tee` or a pipe would fix visibility and reintroduce a worse bug: the tempfile strategy is deliberate, documented protection against MSYS native grandchildren holding an inherited pipe open past the deadline and freezing the harness — a hang already in this repo's problem catalog. A parent-side heartbeat gives observability without touching the capture path, and `bounded-run.sh:26-97` already proves the pattern in this codebase.

**Alternatives considered:**

- **Option A: `stdbuf` / `PYTHONUNBUFFERED`** — rejected: cannot bypass a parent redirect. Would ship as a fix and change nothing.
- **Option B: pipe through `tee`** — rejected: reintroduces the inherited-pipe hang the tempfile design prevents.
- **Option C: shorten the suite** — rejected: not the problem. A 25-minute run is fine if it says so.

**Lock status:** LOCKED

---

## M4. Backup exclusion is exact-shape only — ASSUMPTION

**Recommendation:** `test-sync-allowlist.sh` prunes only exact Flow-owned families matching `<known-name>.pre-upgrade-<UTC-timestamp>`. **No** `.pre-*` or `.pre-upgrade-*` wildcard. **No** secret-scan exclusion of any kind.

**Reasoning:** The allowlist failure is real (`test-sync-allowlist.sh:100-109` discovers with a repo-wide `find` that does not prune these). But the reporter's secret-scan half rests on a false premise twice over: `test-secret-scan-staged.sh:158-177` enumerates via `git ls-files`, so untracked backups never enter it, and the exclusion they cite lives in `.git/info/exclude` (written by `upgrade.sh:430-456`), not upstream `.gitignore`. Adding a secret-scan bypass for a `.pre-*` pattern would create a genuine hole — anything an attacker or a mistake names `foo.pre-upgrade-x` becomes unscannable.

Exact-shape matching keeps a lookalike visible, which is what the negative test in AC6 asserts.

**ASSUMPTION:** the operator accepts that a *malformed* backup name still fails the allowlist phase. That is deliberate — a backup Flow did not create should not be silently trusted.

**Alternatives considered:**

- **Option A: broad `.pre-*` prune in both sweeps** — rejected: creates a secret-scan hole for a symptom that does not exist in that sweep.
- **Option B: leave it; tell consumers to delete backups first** — rejected: the suite failing on the framework's own artifacts is the framework's bug, and M5 shows deletion was itself blocked.

**Lock status:** LOCKED

---

## M5. Cleanup gets a validated tool, not looser guidance

**Recommendation:** Add `hooks/local/cleanup-flow-backups.sh` with exactly two CLI forms: `cleanup-flow-backups.sh --all`, or `cleanup-flow-backups.sh <exact-repo-relative-target>...`. Build an exact authorized stem set from `managed_content_manifest.py list-managed`, then add `VERSION`, legacy `skills`, `policies/module-size-baseline.txt`, and exact installed `docs/_fusebase-flow/<source-top-level-doc-basename>.md` stems. Exact `.fusebase-flow-source/` is a separate target. A backup target is eligible only when its exact stem is in that set and its suffix is `.pre-upgrade-<YYYYMMDDTHHMMSSZ>`. Reject absolute paths, `..`, glob metacharacters, symlinks, non-members, and resolved paths outside the root. String-prefix authorization is forbidden. The FR-06 `rm -rf` deny at `policies/command-policy.yml:47-50` remains unchanged.

**Reasoning:** `upgrade.sh:743-749` gives generic “remove once validated” guidance; the raw recursive delete is at `upgrade.sh:776-781`, and command policy denies it. Both are individually right; the framework is contradicting itself. The wrong fix is an FR-06 exception. The right fix is a purpose-built tool whose destructive authority is exact membership plus resolved-path validation. `--all` enumerates only that same authorized set; explicit targets never widen it.

**Alternatives considered:**

- **Option A: allowlist `rm -rf .fusebase-flow-source` in command-policy** — rejected: a string-matched exception to a destructive-command deny is trivially over-broad and sets a precedent.
- **Option B: have `upgrade.sh` auto-delete backups at the end** — rejected: they exist so a consumer can recover from a bad upgrade; deleting them automatically defeats their purpose.

**Lock status:** LOCKED

---

## M6. Re-point `v4.7.0`; do not invent `v4.7.1` — ASSUMPTION

**Recommendation:** Fold T1..T6 in, get T7 green and both T8 reviews green, then recreate `v4.7.0` at that commit only after explicit operator authorization. Publish a moved-tag notice before/with the release. Do not cut `v4.7.1` under the current authorization.

**Reasoning:** No GitHub Release exists, but the remote tag was consumer-visible and a prerelease tester fetched it (`docs/tmp/handoff/2026-07-30-workhub-upstream-report.md:18`). Re-pointing is therefore a published-ref mutation. Existing version carriers already read `4.7.0`; keeping that version avoids a misleading bump, but requires the moved-tag notice and explicit authorization.

**ASSUMPTION:** the operator authorizes moving a prerelease tag when no GitHub Release exists, after reviewing the exact old/new commits and notice. Without that authorization, this decision flips to `v4.7.1` and all version carriers change together.

**Alternatives considered:**

- **Option A: `v4.7.1`** — the safe-by-convention choice; rejected on the grounds above, but it is a one-line reversal if the operator prefers it.
- **Option B: publish `v4.7.0` as-is and hot-fix in `v4.7.1`** — rejected: ships F2 to consumers upgrading through an affected pre-`601574d`, `core.autocrlf=true` persistent source worktree when nothing forces us to.

**Lock status:** LOCKED — REVISED 2026-07-30

---

## M7. Close F1/F3/F4 as no-code

**Recommendation:** No implementation slice for F1, F3 or F4. Record the correction and move on.

**Reasoning:** F1 and F3 were the last run of the **4.5** engine, not 4.7.0 behaviour. At `664503b`, `upgrade.sh:237-249` already drives the managed set through `managed_content_manifest.py list-managed`, whose canonical list at `:34-49` includes `FLOW_RULES_HISTORY.md` — the exact "drive it from a manifest" fix the reporter asked for, already shipped as K14. The 4.7 classifier at `managed_content_manifest.py:220-294` already preserves-and-reports consumer-modified policy files, which is F3's fix. F4 is refuted outright: `merge-module-size-baseline.sh:85-103` deduplicates by path and the reported mechanism cannot produce a duplicate.

Writing a slice for any of them would mean authoring a test that passes at HEAD — the tautology the previous ticket's anti-tautology contract exists to forbid. The honest deliverable is telling the consumer their upgrade route was unsupported, which the v4.7.0 release notes already do (M7 adds prominence, not new behaviour).

**Alternatives considered:**

- **Option A: implement defensively anyway ("cheap insurance")** — rejected: it would add untestable code and misreport three findings as fixed defects, corrupting the record for the next reader.

**Lock status:** LOCKED

---

## M8. F7 is a parser project, not a patch — ASSUMPTION

**Recommendation:** Do **not** fix F7 in this ticket. Promote `docs/backlog/command-gate-shell-evasion/` to a full ticket with a semantic corpus, and forbid the narrowing patch explicitly in that ticket and in `policies/command-policy.yml`'s header.

**Reasoning:** F7 is confirmed and genuinely bad UX — the reporter could not write an honest commit message about the guard and had to route around it with `git commit -F`, which is precisely what a safety rail must not teach. But every narrowing the report proposes is unsafe:

| Proposed | Fails because |
|---|---|
| Ignore text after `git commit -m` | `git commit -m "$(rm -rf …)"` runs the substitution before git |
| Ignore heredoc bodies | `bash <<EOF … EOF` executes the body |
| Match only command position | Misses `safe && rm -rf …` |
| Split argv and inspect | **Worsens** K21 quote-fragmentation evasion |

The correct fix is parsing execution structure — distinguishing executed command nodes, compound lists and substitutions from single-quoted literals and data-only heredocs. That is a real component with its own adversarial corpus, and it interacts directly with the K21 evasion gap this release documented. Shipping half of it under release pressure would produce a gate that is both evadable *and* obstructive.

**ASSUMPTION:** the operator accepts F7 friction for one more release. Mitigation available today and worth stating in the release notes: `git commit -F <file>` works, and is no longer "routing around the guard" once it is the documented path for prose that quotes a destructive pattern.

**Alternatives considered:**

- **Option A: narrow now, harden later** — rejected: creates a false-negative security hole to fix a false-positive annoyance.
- **Option B: ship the parser in this release** — rejected on sequencing, not merit: it would hold F2 (which breaks consumers upgrading through an affected pre-`601574d`, `core.autocrlf=true` persistent source worktree) behind a security-sensitive component that needs its own review cycle.

**Lock status:** LOCKED

---

## M9. Approval staleness is visibility-only

**Recommendation:** Writers add `created_at` to every newly minted artifact; the field remains additive/schema-optional for legacy artifacts. Only active `protected_path_edit` artifacts produce age warnings. Missing `created_at` means unknown age and warns. Populate a separate `APPROVAL_WARNINGS[]`; print it outside verdict counts; never add its entries to `LOCAL_DRIFT`, `LOCAL_BROKEN`, or `LOCAL_UNVERIFIED`. Approval validity, authorization, verdict precedence, and exit status remain unchanged.

`stale_approval_warn_after_days` is a positive integer with shipped default `7`. Lower days are tighter. With `local_override_may_relax: false`, a local override may lower or equal the shipped value; higher, non-integer, boolean, zero, or negative values are rejected with an explicit policy error, never silently accepted or treated as the base value.

**Reasoning:** `active-approvals.sh:11-16` documents the arrays that drive authorization-related reporting, and `fusebase-flow-health-check.sh:560-590` derives verdict counts from separate health arrays. Reusing `ARTIFACT_NOTES[]` would mix status notes with age warnings and leave the public array contract false. A dedicated warning channel makes visibility-only mechanically testable. Restricting reports to still-active `protected_path_edit` artifacts avoids warning on expired/non-authorizing files or `health_check_deferral` artifacts.

**Alternatives considered:**

- **Option A: expire approvals based on age** — rejected: changes authorization semantics and the auth model; single-use consumption remains a separate ticket.
- **Option B: put warnings in `ARTIFACT_NOTES[]`** — rejected: overloads the documented array contract and risks changing `EXCEPTION_IN_EFFECT` classification.
- **Option C: allow local threshold increases** — rejected: silently suppresses shipped warnings and violates tighten-only policy layering.

**Lock status:** LOCKED

---

## M10. Non-git source compatibility is explicit

**Recommendation:** Snapshot every non-git source into temporary absolute `SOURCE_TREE` before any source-derived read. Run `managed_content_manifest.py verify --root <SOURCE_TREE>`. If a manifest is present, `MATCH` proceeds; `BROKEN` or `DRIFT` aborts before writes and reports paths/reason. `ABSENT` is supported only as the named, logged `UNVERIFIED_LEGACY_SOURCE` compatibility fallback for pre-manifest sources; preserve `test-upgrade-conflict-classification.sh:310-319`.

**Reasoning:** Manifest-bearing plain directories can and must prove byte integrity. Pre-4.7 sources cannot: rejecting `ABSENT` would silently revoke the existing pre-classifier upgrade contract. A named fallback preserves compatibility without falsely labeling legacy bytes verified. The immutable snapshot also prevents the caller from changing source bytes between validation and copy.

**Alternatives considered:**

- **Option A: reject every `ABSENT` source** — rejected: breaks the existing pre-classifier compatibility contract.
- **Option B: accept every plain directory without a named state** — rejected: erases the security distinction between verified and legacy-unverified content.

**Lock status:** LOCKED

---

## Lock confirmation

| ID | Final option | Locked by | Date |
|---|---|---|---|
| M1..M10 | as recommended above | PO under the operator's standing autonomous-run authorization | 2026-07-30 |

Implementation may start. M4, M6, M8 carry **ASSUMPTION** flags — an operator reversal re-opens that decision only. M6 still requires action-specific tag-move authorization at release time.
