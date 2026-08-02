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
| M13 | The repair-verification contract | Bind the required layer set at authorization; `rc == 0` AND exact `MATCH` per bound layer; empty set refused before any write | LOCKED |
| M14 | Bound-set membership: either consumer artifact | — | **SUPERSEDED BY M16** |
| M15 | `cli-flow-recovery` bound 480s → 900s | Deliberate headroom, not a re-set edge | LOCKED |
| M16 | Bound-set membership is declared by the verified upstream tree | Membership reads `$SOURCE_TREE` only; the consumer tree cannot influence it | LOCKED |

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

---

## M11. `--unsafe-legacy-copy` does not bypass the integrity boundary

**Recommendation:** RATIFIED as implemented in R1 (`470f7d2`). The K20a `--unsafe-legacy-copy` escape is reachable only for a **pre-manifest** source. A manifest-bearing source whose bytes cannot be proven — missing verifier, no verdict, unexpected exit, DRIFT or BROKEN — **aborts**, and the flag does not override that.

**Reasoning:** K20a exists so a genuinely pre-classifier source can still upgrade; it was never meant to be a way to install unverifiable bytes when a manifest *is* present. Letting the flag bypass a failed verification would recreate F2 behind an opt-in — and an opt-in that a diagnostic could eventually suggest is exactly how the `preflight` self-restamp hole (K20b) happened. If the source has a manifest, we can prove the bytes or we stop.

The `ac23` fixtures that previously modelled a manifest-with-no-verifier tree were impossible states; corrected to genuinely pre-manifest so they assert the classifier gate rather than the boundary abort.

**Lock status:** LOCKED

---

## M12. Allowlist-discovery basename matching is out of scope, and stays that way

**Recommendation:** `hooks/tests/test-sync-allowlist.sh`'s discovery prune matches by path-segment basename. Leave it. Do **not** extend M5's exact-stem rule to it in this ticket.

**Reasoning:** M5 governs **destructive authority** — what `cleanup-flow-backups.sh` may delete — where over-broad matching means deleting a file nobody authorized. Allowlist discovery decides only which files a *documentation sweep* considers reachable; an over-broad prune there hides a file from a sweep, it does not destroy anything. Different blast radius, different bar.

Widening the fix mid-round would also have meant changing a test's semantics under a finding that did not name it, which is how scope creep enters a corrections round. Filed as an observation for a future ticket rather than actioned here.

**Lock status:** LOCKED

---

## Lock confirmation (updated)

| ID | Final option | Locked by | Date |
|---|---|---|---|
| M1..M10 | as recorded above | PO under the operator's standing autonomous-run authorization | 2026-07-30 |
| M11, M12 | ratifications from the review-findings fix round | PO, same authorization | 2026-07-30 |

---

## M13. The repair-verification contract — bind the layer set at authorization

**Recommendation:** Option (b). `--repair-managed` binds the **required manifest set at authorization time**, before any write, and that set cannot shrink mid-run. Every layer in the bound set must return **`rc == 0` AND a parsed verdict of exactly `MATCH`**. A layer that is in the bound set but whose manifest or wrapper is absent at verification time is a **failure**, not a skip.

**Reasoning:** The round-4 defects were both instances of one ambiguity — nobody had decided what "repair confirmed" *means* when a consumer may not carry every layer, so the implementation invented an answer twice and got it wrong twice:

- `ff_boot_repair_verify` captured the verifier's stdout but never `rc`, returning success on a parsed `MATCH` regardless of exit code — while `ff_boot_verify` and `_ff_mms_verify` both require rc 0 *and* exact MATCH. Three verifiers, two contracts.
- The layer-skip was keyed on the **manifest** where the prior loop keyed on the **wrapper**. Deleting `audit/managed-content-manifest.json` therefore silently skipped that layer and exited 0, where the old loop returned rc 4. The asymmetry is real and one-directional: the hook manifest is anchored by being managed content; the managed-content manifest has no reciprocal anchor, so its absence cannot be self-certifying.

Binding at authorization removes the ambiguity structurally rather than by another predicate: the set is fixed when the operator authorizes the repair, so a mid-run absence is a detectable contradiction instead of an input to the decision. Options (a) and (c) were both coherent — (a) is stricter but breaks installs that legitimately lack a layer, and (c) is honest but reduces repair to a claim too weak to act on ("these paths were replaced" without "and the tree is now clean" gives the operator nothing to verify against).

**Also required, independent of the above:** disclose plain-source trust. `docs/release-notes/v4.7.0.md:127` claims a re-stamped manifest aborts for any manifest-bearing source. That holds for **git** transport, where the canonical tree comes from committed objects. It is **false for a plain `--source` directory**, where snapshot, payload, verifier and manifest share one authority and can be made self-consistent. Say so plainly rather than leaving the stronger claim standing.

**Alternatives considered:**

- **(a) require both layers unconditionally** — rejected: fails installs that legitimately carry only one layer, converting a coverage question into an outage.
- **(c) narrow the claim** — rejected as the primary answer: it is the most honest framing but leaves the operator without a whole-tree assertion after a repair, which is the thing a repair exists to restore. Its honesty is preserved by the disclosure requirement above.

**Process note:** this decision exists because the previous three rounds tried to *patch* the ambiguity. One implementation pass against a decided contract, then one review — not another iterate-until-green loop.

**Lock status:** LOCKED 2026-07-31, PO, on the operator's "proceed with your recommendations".

---

## M14. Bound-set membership: either consumer artifact present at authorization

**SUPERSEDED BY M16 (2026-08-02). Refuted, never shipped.** M14 derived membership from the consumer tree, so "this install never carried the layer" and "both of its artifacts were deleted a second before authorization" were the same observation — a pre-authorization downgrade needing no race. The refutation and the replacement rule are in M16; the rejected text is in git history (`0f50c05`, `257439a`).

---

## M15. `cli-flow-recovery` bound raised 480s → 900s

**Recommendation:** RATIFIED. Out of M13's contract, kept anyway.

**Reasoning:** Not a flake — reproduced, and standalone on a quiet host the phase runs **542s to completion, 31/31, exit 0**. It copies an entire skill tree; its own tripwire records that 240s and then 480s were each set at the measured edge and each crossed by ordinary growth one ticket later. 900s restores headroom instead of re-setting the edge a third time.

It weakens nothing: an assertion failure still FAILs, and a genuine hang is still bounded and still surfaces as INCONCLUSIVE. The alternative — leaving a bound that the phase legitimately exceeds — makes the gate unrunnable and trains the reader to ignore INCONCLUSIVE, which is worse than a longer timeout.

**Pattern worth naming:** this is the third time this bound has been set at the measured edge and then crossed. A timeout chosen from one clean-host measurement is a latent failure with a delay fuse. Future bounds on growing phases should carry deliberate headroom, not a rounded-up observation.

**Lock status:** LOCKED 2026-07-31

---

## M16. Bound-set membership is declared by the verified upstream tree

**Recommendation:** A manifest layer is in the repair's bound set **iff the VERIFIED source tree declares it** — `$SOURCE_TREE/<manifest-rel>` exists at the version being repaired from. The consumer's tree contributes **nothing** to membership. For every declared layer the consumer must carry that manifest, and must carry the layer's verify wrapper whenever the verified source ships one; either absence is a **FAILURE**, not a skip. A layer the source does not declare is not bound. Everything else in M13 is unchanged: bound before any repository write, no mid-run shrink, `rc == 0` **and** parsed exact `MATCH` for every bound layer, empty bound set refused before any write.

**Why M14 failed:** it read membership out of the tree under repair. "Neither artifact present ⇒ not carried" is the same observation as "both artifacts were deleted before authorization", so the exploit needs no race: delete `audit/managed-content-manifest.json` **and** `hooks/local/verify-managed-content-manifest.sh`, leave managed-only drift in the tree, authorize a repair through the still-intact hook layer — the managed layer is never bound, the hook layer returns MATCH, and the hop exits 0 over a dirty tree. No consumer-side predicate can close this: whatever artifacts the rule reads, the party who can delete two files can delete N.

**Why the upstream tree is a valid anchor:**

| Property | Basis |
|---|---|
| Outside the **repaired tree's** control | `$SOURCE_TREE` is materialized from committed git objects (`git archive <oid>`) or an immutable snapshot; the consumer root is never read for membership. **Not** "outside the consumer's control" — M17 locks the same-principal threat model, so the party who owns the repaired tree can also author the staging tree. What M16 buys is cost: a downgrade goes from *delete two files* to *author a self-consistent source tree that lies about its own layer set* |
| Already proven, not merely present | repair refuses unless `FF_SOURCE_STATE = VERIFIED`, i.e. the source's own `audit/managed-content-manifest.json` returned rc 0 **and** a parsed exact `MATCH` through `python3 -I -S` with a trusted verifier (B4/B5) |
| Version-matched | the coverage statement comes from the version being repaired **from**, so skew is resolved by the anchor rather than by inspecting the consumer |
| Non-shrinkable | the set is bound before the first repository write and re-read from nothing afterwards |

**Threat model (M17, locked):** same-principal workspace. This anchor defends against accidental and mid-run corruption, not against a hostile co-tenant who can author the staging tree. Closing that case needs a trust root outside the workspace — `docs/backlog/repair-trust-root-outside-workspace/`.

**Consequences, stated so none is discovered later:**

- A consumer genuinely missing a declared layer now **fails** the repair instead of silently narrowing it. This is intended, and recoverable in one command: both artifacts are themselves managed content, so the other layer's verifier reports them as `missing` and they can be named in `--repair-managed`. The diagnostic says so.
- The managed layer is declared **by construction** for any repair-eligible source (`VERIFIED` ⇒ the source manifest exists **at verification time**). That does not make M13's empty-bound-set refusal unreachable: `$SOURCE_TREE` stays mutable until the bind, so the branch is **fail-closed**, not unreachable. It stays as the floor; "every bound layer must MATCH" is vacuously true over an empty set.
- The AC3 fixture stays green **by design, not by retuning**: its source declares only the managed layer and ships no verify wrapper, so the bound set is that one layer with no wrapper requirement, and the consumer carries its manifest. A partial *consumer* is refused; a source that legitimately does not ship a layer at that version is not invented into one.
- Plain `--source` transport is unchanged and still disclosed: snapshot, payload, verifier and manifest share one authority there, so a plain source can declare a self-consistent coverage list. Git transport is the case the anchor is strong for.

**Alternatives considered:**

- **An install/upgrade record of which layers were written** — rejected: a new durable state file *in the consumer tree* is the same class of anchor that just failed (deletable by the same party), plus a migration for every existing install that has no such record.
- **Keep M14 and disclose the downgrade** — rejected: the disclosure would read "the whole-tree claim is void whenever the consumer can delete two files", which is precisely the claim `--repair-managed` exists to make.
- **Require both artifacts unconditionally, source-independent (M13 option (a))** — rejected again: it answers "which layers exist" with a constant instead of a version-matched fact, and turns a source that ships no wrapper at that version into a permanent failure.

**Process note:** this is the fourth answer to one question, and the last. The three before it were invented inside an implementation pass; this one was decided first, then implemented once, then reviewed once.

**Lock status:** LOCKED 2026-08-02 by the operator, on the explicit instruction to implement the upstream-declared anchor and not re-open it.

---

## M17. Threat model: same-principal workspace

**Recommendation:** Option (a). `--repair-managed` defends against **accidental and mid-run corruption within a workspace owned by one principal** — not against a hostile co-tenant who can author the staging tree.

**Reasoning:** This is not a new position; it is the position the whole system already holds. K3 locked that the agent and the operator write as the same OS principal, that `$USER` and self-attested roles are forgeable by the process being gated, and that Flow therefore enforces schema/expiry/binding but **not** identity. FR-07 approvals, `approve-local.sh` and `write-bootstrap-approval.sh` all rest on that same assumption. Choosing (b) here would make one command in the upgrade path stricter than the approval system that authorizes it — a guarantee that cannot be honoured end to end is worse than an accurate weaker one.

Closing the co-tenant case genuinely requires truth from outside the workspace: fetching the release from the remote at repair time, or verifying a signature. K3 already recorded that Flow has no signing seam. That is a feature with its own ticket, not a patch on this one.

**What M16's wording must become:** "outside the **repaired tree's** control", never "outside the consumer's control". M16 raises the cost of a downgrade from *delete two files* to *author a self-consistent source tree that lies about its own layer set*. That is a real improvement and it is all M16 may claim. Delete "unreachable by construction" — the property is **fail-closed**, not unreachable.

**Alternatives considered:**

- **(b) hostile co-tenant** — rejected for this ticket. Correct to want, unbuildable without a trust root Flow does not have, and it would leave `--repair-managed` claiming more than the gate that authorizes it.

**Backlog:** file `docs/backlog/repair-trust-root-outside-workspace/` for the (b) case — remote fetch or signature verification at repair time — cross-linked to K3 and `provenance-and-single-seam-guarantees`.

**Lock status:** LOCKED 2026-08-02
