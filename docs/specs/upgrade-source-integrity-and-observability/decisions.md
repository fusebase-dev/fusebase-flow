# Decisions — upgrade-source-integrity-and-observability

**Letter prefix:** M
**Approval status:** LOCKED 2026-07-30 under the operator's standing end-to-end autonomous-run authorization. Each lock is a PO recommendation the operator did not individually confirm; flagged **ASSUMPTION** where a different call changes the work.
**Linked spec:** `docs/specs/upgrade-source-integrity-and-observability/spec.md`

## Decision matrix

| ID | Title | Recommendation | Lock status |
|---|---|---|---|
| M1 | Fix the source, not the symptom | Materialize managed content from git objects; reject attribute/fixture/hasher fixes | LOCKED |
| M2 | The hasher stays byte-exact | No line-ending normalization in integrity hashing | LOCKED |
| M3 | Keep tempfile capture; add a parent heartbeat | Never switch to `tee`/pipe streaming | LOCKED |
| M4 | Backup exclusion is exact-shape only | Prune `<name>.pre-upgrade-<UTC>` families; no `.pre-*` wildcard; no secret-scan bypass | LOCKED |
| M5 | Cleanup gets a validated tool, not looser guidance | New script; FR-06 deny stays intact | LOCKED |
| M6 | Re-point `v4.7.0`; do not invent `v4.7.1` | No Release was published; fold and re-tag | LOCKED |
| M7 | Close F1/F3/F4 as no-code | Already-fixed / refuted; strengthen bootstrap docs only | LOCKED |
| M8 | F7 is a parser project, not a patch | Own ticket, own review cycle; naive narrowing forbidden | LOCKED |

## M1. Fix the source, not the symptom

**Recommendation:** `upgrade.sh` materializes managed content from the **selected git commit's object database** (`git archive` / a detached worktree), not from the persistent source clone's working tree. For a plain non-git `--source`, verify its bytes against its shipped manifest before copying and abort explicitly if non-canonical.

**Reasoning:** The reporter proposed three fixes and all three are wrong, which matters because each would have looked like it worked. `.gitattributes` already pins `*.json`/`*.jsonl` (`:19-20`, since `601574d`), the fixture blobs **are** LF (raw-object hashes match `audit/hook-layer-manifest.json:300-325` exactly), and `git ls-files --eol` reports `i/lf w/lf attr/text eol=lf`. The CRLF exists only in a **stale worktree**: a clone checked out under `core.autocrlf=true` before the pin landed, then advanced by `git pull`, which does not rewrite unchanged files. `upgrade.sh:496` then `cp`s those bytes into the consumer.

So the defect is that the upgrade trusts a mutable working tree as its definition of canonical content. `git add --renormalize` is a no-op here (blobs are already clean) and would not rewrite the stale worktree anyway. Fixing the transport is the only fix that holds for every future file type, rather than for `.jsonl` until the next unpinned extension appears.

**Alternatives considered:**

- **Option A: add more `.gitattributes` pins** — rejected: the pins already exist; this fixes nothing and would be recorded as a fix.
- **Option B: normalize in the hasher** — rejected, see M2.
- **Option C: force a fresh clone every upgrade** — rejected: discards the deliberate persistent-clone design and its offline/bandwidth properties. Materializing from objects gets canonical bytes *and* keeps the cached clone.

**Lock status:** LOCKED

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

**Recommendation:** Add `hooks/local/cleanup-flow-backups.sh`, validating repo root, approved prefixes and exact timestamp shape. `upgrade.sh` guidance points at it. The FR-06 `rm -rf` deny in `policies/command-policy.yml:47-50` is **not** touched.

**Reasoning:** `upgrade.sh:743-749,776-781` advises `rm -rf .fusebase-flow-source` and the command policy denies it. Both are individually right; the framework is contradicting itself. The wrong fix is to carve an exception into FR-06 — that weakens a hard deny to make a convenience path work, and FR-06's deny is doing exactly its job. The right fix is a purpose-built tool that deletes only what Flow created, with the destructive surface narrowed by validation rather than by trust. It never accepts a caller-supplied glob.

**Alternatives considered:**

- **Option A: allowlist `rm -rf .fusebase-flow-source` in command-policy** — rejected: a string-matched exception to a destructive-command deny is trivially over-broad and sets a precedent.
- **Option B: have `upgrade.sh` auto-delete backups at the end** — rejected: they exist so a consumer can recover from a bad upgrade; deleting them automatically defeats their purpose.

**Lock status:** LOCKED

---

## M6. Re-point `v4.7.0`; do not invent `v4.7.1` — ASSUMPTION

**Recommendation:** Fold T1..T5 in, get the full gate green, then recreate `v4.7.0` at that commit and push it. Do not cut `v4.7.1`.

**Reasoning:** No GitHub Release for `v4.7.0` was ever created — the release workflow's `publish` job is `needs: verify` and verify was red, so the API returns 404. Nothing consumer-facing resolves to that tag. `VERSION`, both plugin manifests and `marketplace.json` all already read `4.7.0`, and every doc, CHANGELOG entry, release-note file and the closed `approval-binding-and-upgrade-classification` spec reference 4.7.0. Cutting `v4.7.1` would mean a version bump whose changelog says "fixes to the unreleased 4.7.0" — confusing, and it leaves a permanent tag pointing at a commit that fails its own CI.

**ASSUMPTION:** the operator does not treat any pushed tag as immutable regardless of release status. The reporter did fetch the tag pre-release, so the release notes must state that `v4.7.0` moved and pre-release testers should delete and re-fetch. If tags are considered immutable, this flips to `v4.7.1` and all four version carriers change together.

**Alternatives considered:**

- **Option A: `v4.7.1`** — the safe-by-convention choice; rejected on the grounds above, but it is a one-line reversal if the operator prefers it.
- **Option B: publish `v4.7.0` as-is and hot-fix in `v4.7.1`** — rejected: ships F2 to every Windows consumer when nothing forces us to.

**Lock status:** LOCKED

---

## M7. Close F1/F3/F4 as no-code

**Recommendation:** No implementation slice for F1, F3 or F4. Record the correction and move on.

**Reasoning:** F1 and F3 were the last run of the **4.5** engine, not 4.7.0 behaviour. At `664503b`, `upgrade.sh:237-249` already drives the managed set through `managed_content_manifest.py list-managed`, whose canonical list at `:34-49` includes `FLOW_RULES_HISTORY.md` — the exact "drive it from a manifest" fix the reporter asked for, already shipped as K14. The 4.7 classifier at `managed_content_manifest.py:220-294` already preserves-and-reports consumer-modified policy files, which is F3's fix. F4 is refuted outright: `merge-module-size-baseline.sh:95-103` deduplicates by path and the reported mechanism cannot produce a duplicate.

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
- **Option B: ship the parser in this release** — rejected on sequencing, not merit: it would hold F2 (which breaks every Windows consumer) behind a security-sensitive component that needs its own review cycle.

**Lock status:** LOCKED

---

## Lock confirmation

| ID | Final option | Locked by | Date |
|---|---|---|---|
| M1..M8 | as recommended above | PO under the operator's standing autonomous-run authorization | 2026-07-30 |

Implementation may start. M4, M6, M8 carry **ASSUMPTION** flags — an operator reversal re-opens that decision only.
