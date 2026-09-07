# Adversarial review - flow-performance-and-recovery-hardening

**Reviewer:** independent Architect, GPT-6 Astra Medium; final targeted T22, 2026-09-07.
**Range:** retained whole-implementation review ef6cac3..81bb130; correction diffs 81bb130..559ca5a and reconciled docs; final focus c3c2580 (T53) and 559ca5a (T54).
**Verdict:** APPROVED for the reviewed source through `559ca5a`; **ZERO BLOCKERS**. R1-R5 closed for that contract. T56-T60 post-review evidence is owned by `gate-report.md`; this file does not claim a repeated independent review or publication acceptance.
**Method:** targeted source/diff/manifests/focused-evidence review plus targeted in-memory negative/positive controls and read-only manifest hashes. No suites, recovery writes, external actions or source edits. UI/client N/A.

## Blockers

**None. Zero-blocker approval is explicit.** No new correctness/security or evidence-only blocker found in final changed seams.

## Final R1/R3 closure

| Finding / correction | Evidence and scope |
|---|---|
| R1 / T53 c3c2580 | CLOSED: hooks/local/lib/validator-evidence.py:244 unconditionally rejects caller-asserted completeness after schema parsing. In-memory complete=true with nonempty inputs/dependencies/environment/toolchains refuses both before and after undeclared VALIDATOR_STRICT mutation; omitted files cannot restore eligibility. Runner :393-407 executes validators on unavailable identity and returns before signing; verifier :434 and main :459 fail closed for old receipts too. Focused executor evidence3/3,31.620s; fixture checks actual rerun counts and lint failure propagation. Reusable receipts are now unavailable on every platform, not only Windows. |
| R3 / T54 559ca5a | CLOSED: hooks/local/lib/recovery-preflight.py:202-216 validates canonical template, existing CUSTOM markers and preserve span before append selection. In-memory unmatched/nested no-heading inputs now refuse; marker-free provider bytes yield exactly original+template. Existing focused fixture validates unchanged target inventory on refusal and exact planned append hash. Executor evidence2/2, command0.122s/stage0.031s. Preflight remains before recovery writes. |
| R2/R4/R5 regression lens | Final diff changes only validator evidence, overlay preflight, their focused fixtures, validator guidance/mirrors and manifests. Settings canonicalization, owned-writer classification/lock/revalidation, temporal linkage and their dependencies are unchanged; prior closure retained without reruns. |

## Closed corrections and retained evidence

| Scope | Disposition |
|---|---|
| R2 / T49 / B5 | CLOSED: settings-json-merge.py:297,338 detects real semantic mutation; :245 validates exact dedicated canonical handler/block/matcher. Restricted matcher repairs persist; custom scope/order preserved. Focused4/4 retained. |
| R4 / T51 / B3 | CLOSED for reviewed model: recovery-owned-write.py:413,427,438 revalidate source/target ancestry/type/bytes and serialize writers; :496-517 applies checks before receipt authority. Four race/control cases retained. No hostile same-user race guarantee. |
| R5 / T52 / B8 | CLOSED: hooks/local/find_wasted_effort/conclusion_link.py requires explicit valid unique SHA/task and action-linked approval; windowing removes cosmetic-current fallback. Focused16/16 retained. |
| R1 / T48 / B1-B2 | Missing/incomplete context now reruns; direct minting remains removed; command/config binding and live identity checks retained. Windows authority refuses safely. T53 closes completeness by disabling reuse; no validator-skipping performance benefit remains. |
| R3 / T50 / B4 | Prior two-hook receipt gates auto Git restoration; external-settings uncertainty persists; exact planned overlay digest and surface partition strengthen final proof. Focused4/4 retained; T54 closes the no-heading append gap. |
| T1-T10 and other fix-forwards / B6-B7 / N1-N2 | Prior whole-implementation review retained: exact spans, CLI/user ownership, one-read transcript, diagnosis-first lanes, compact core/role bootstrap, no-op mirrors, rollback and manifests. No additional blocker in changed seams. |

## Evidence and claim limits

- Correction commits: T48 8e54a74; T49 90288ae; T51 078f0b2; T50 8a8d450; T52 6fa185e; T53 c3c2580; T54 559ca5a. gate-report.md owns focused commands/results/timing. T48 timeout/partial evidence remains historical non-success.
- Read-only normalized-byte hashing matched all209 hook and372 managed manifest entries at559ca5a. Those counts are historical review evidence. Final `e99d61b` execution matched212/212 hook and375/375 managed entries; `gate-report.md` owns the post-review run attribution. Recorded normal precommit remains executor evidence, not a full/platform run.
- T20 three independent no-ops and T32 composed9/9 remain historical at008ade7; changed recovery semantics rely on focused corrections, not a claimed integrated run at the final559ca5a. T47 cleanup remains limited to recorded owned identities.
- Performance: static carrier reduction, one transcript read and observed zero writes only. Validator reuse is disabled globally; do not claim duplicate lint/typecheck elimination or successful HMAC reuse as delivered performance. No consumer/model token or end-to-end speedup proved; cleanup-versus-runtime timing contribution UNKNOWN.
- Rollback: exact task commits in reverse dependency order; retained consumer originals. No deploy/migration/UI scope.

## Non-blockers and residual UNVERIFIED

| Item | Disposition |
|---|---|
| Actual current CLI install/update/recover | OBSERVED on CLI `2026.090414.3609` Windows/Git Bash consumer scenario; update/recovery/no-op evidence predates final `e99d61b` sync/health. |
| Five-provider delivered-context telemetry | DEFERRED AC7; static reduction is not host measurement. |
| Tagged Linux + Windows/MSYS release CI, unexecuted real symlinks, Windows authority isolation/successful signing | DEFERRED/UNVERIFIED; observed consumer compatibility is not tagged publication or signing proof. |
| Hostile same-user execution | Outside HMAC trust model; no stronger protection claimed. |
| T23 | COMPLETE at `079e84d`; later actual-CLI evidence is owned by `gate-report.md`. AC7 delivered-context telemetry and remaining release/platform cases stay deferred. |

**Post-review reconciliation:** T56 `f4c577b`, T57 `96de58e`, T58 `e432480`, and T59 `e99d61b` followed this review. T60 updates status only; `gate-report.md` owns current evidence. T58 prepared the release and did not publish it. T57 adds observability only. Validator reuse remains disabled. No broad/default suite, benchmark repeat, successful-prefix replay or observer harness.
**T23 documentation check:** APPROVE after correcting historical-source labels, separating in-memory proof from old-receipt source inspection, and restoring the T10 roadmap disposition. Exact commit chronology matches Git history. No source/tests/external actions or commit; doc diff-check passed.

**Workspace:** documentation only; pre-existing repair backups, smoke/archive/wasted-code preserved.

---
Phase: Verify | Ticket: flow-performance-and-recovery-hardening/T60 | Next: tagged release verification under `PUBLISHING.md`.
