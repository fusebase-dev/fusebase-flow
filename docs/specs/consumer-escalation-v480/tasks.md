# Consumer escalation v4.8.0 - tasks

**Status:** DRAFT | **commit rule:** one task = one commit (FR-03) | **scope:** AC1-AC28
**Landed:** T1 `9fdba11`, T3 `ac0879d` | **SHIP-BLOCKER:** T4-T8

## Task chain

| Order | Task | Slice | State | Blocked by | Commit scope |
|---:|---|---|---|---|---|
| 1 | T1 | S1 / R3-attribution | LANDED `9fdba11` | - | Typed provenance + public contract + regression |
| 2 | T3 | S4a / R1-message | LANDED `ac0879d` | - | Denial rendering + regression only |
| 3 | T4 | S1 / M1 | IMPLEMENTABLE / SHIP-BLOCKER | - | Tree/commit binding + adopted-bootstrap receipt |
| 4 | T5 | S1 / M2+M4 | IMPLEMENTABLE / SHIP-BLOCKER | T4; serialize shared files | Failure-safe marker lifecycle + helper isolation |
| 5 | T6 | S4a / m1 | IMPLEMENTABLE / SHIP-BLOCKER | - | Exact denial tests + signature guard |
| 6 | T7 | S1+S4a / m2 | IMPLEMENTABLE / SHIP-BLOCKER | T4, T5; serialize test registry | Independent oracles + live health + mutation harness |
| 7 | T8 | S1 / M3 | IMPLEMENTABLE / SHIP-BLOCKER | - | Canonical doc correction + discovery pointer |
| 8 | T2 | S2 / R2 | DESIGN-BLOCKED | Explicit operator lock of C3 receipt schema | Receipt + census + regression only |

## T1 - Implement typed installed-source provenance

**ACs:** AC1-AC9
**Landed:** `9fdba11`; T4, T5, and T7 own adversarial fix-forward gaps.

**Target files:**

- `hooks/local/lib/materialize-managed-source.sh`
- `hooks/local/lib/installed-provenance.sh` (new; marker schema/read/write responsibility seam)
- `hooks/local/upgrade.sh`
- `hooks/local/bootstrap-upgrade.sh`
- `hooks/local/fusebase-flow-health-check.sh`
- `hooks/local/lib/managed_content_manifest.py`
- `hooks/tests/test-installed-from-provenance.sh` (new)
- `hooks/tests/run-tests.sh`
- Existing public install/upgrade documentation surface; do not create a second contract owner
- `INSTALLED_FROM` as generated runtime output only; do not commit a development-tree marker

**Work:** propagate `source_kind` with `FF_SOURCE_COMMIT` for Git and a consumed-snapshot SHA-256 for plain sources; validate/write the v1 JSON through the new helper; atomically replace only after success; preserve on early no-op/failure; exclude marker state from source manifests; document generated-unmanaged ownership.

**Verify:** run the targeted AC9 matrix and full hook tests. Capture observed marker/health output for Git direct, Git bootstrap, plain, no-op absent/present, post-materialization failure, atomic replacement, prior preservation, manifest exclusion, missing, and malformed cases.

**Module-size:** keep provenance parsing/writing in `installed-provenance.sh`; run the FR-25 ratchet before edits and do not grow an over-ceiling caller with helper-owned logic.

**Commit:** one T1 commit; exclude S2, retag policy/detection, R1 text, generated marker content, and unrelated cleanup.

## T2 - Implement clone-durable approval receipt

**ACs:** AC10-AC13 | **Start condition:** operator locks closure C3 and the exact v1 schema.

**Target files:**

- `hooks/local/approve-local.sh`
- `hooks/local/lib/approval-receipt.sh` (new if extraction is required by FR-25)
- `templates/deploy-report.md`
- `templates/gate-report.md` (census input; edit only if it emits/cites approval evidence)
- `docs/backlog/provenance-and-single-seam-guarantees/README.md`
- `hooks/tests/test-approval-receipt-durability.sh` (new)
- `hooks/tests/run-tests.sh`

**Work after lock:** emit/capture the C3 receipt from the exact validated artifact; separate copied fields from computed verdict/TTL; bind the receipt to deploy hash; remove committed-output citations to local approval paths; retain live validation and gitignore behavior; record all reader/writer dispositions.

**Verify:** targeted tests prove exact artifact digest, all binding fields, computed labels, deploy binding, rejection of `approved_at`/stored `ttl`/stored `verdict`, zero dangling local-path output, and unchanged validation; then run full hook tests.

**Commit:** one T2 commit; exclude live approval JSON, `.gitignore` changes, S1, R1, and retag work.

## T3 - Add conservative denial explanation

**ACs:** AC14-AC17
**Landed:** `ac0879d`; T6 and T7 own adversarial test-hardening gaps.

**Target files:**

- `hooks/shared/command_policy.py`
- `hooks/tests/test-command-policy-denial-message.sh` (new, or the existing command-policy test owner if one exists)
- `hooks/tests/run-tests.sh`

**Work:** render the exact AC14 text from existing `rule_id` and `matched_pattern`. Do not add parser/token/span logic, re-match text, change policy patterns, or alter an allow/deny result.

**Verify:** exact-message tests for executable text and quoted prose; invariant tests for decision/rule/pattern/exit behavior; full hook tests.

**Protected path:** `hooks/shared/**` is protected by `policies/protected-paths.yml`; obtain the normal scoped FR-07 authorization for the exact protected edit before commit. No authorization applies to unrelated paths.

**Commit:** one T3 commit; exclude parser/matching/policy changes and unrelated denial copy.

## T4 - Bind recorded Git identity to the consumed canonical tree

**ACs:** AC18-AC19 | **Targets:** `hooks/local/upgrade.sh`, `hooks/local/bootstrap-upgrade.sh`, `hooks/local/lib/installed-provenance.sh`, `hooks/tests/test-installed-from-provenance.sh`, `hooks/tests/run-tests.sh`

**Work/verify:** remove caller precedence over `FF_SOURCE_COMMIT`; add and validate the adopted-bootstrap commit+tree-digest receipt before target writes. Prove tree A/commit B and digest mismatch reject with zero target change; retain direct Git, normal bootstrap, plain, `VERSION`, tag, and manifest behavior.

**Module-size/commit:** keep receipt validation in the provenance helper seam; run the FR-25 ratchet. One T4 commit; exclude marker-failure, denial, documentation, S2, S3, and S5 work.

## T5 - Make marker failures truthful, atomic, and non-fatal

**ACs:** AC20-AC22 | **Blocked by:** T4
**Targets:** `hooks/local/lib/installed-provenance.sh`, `hooks/local/upgrade.sh`, `hooks/tests/test-installed-from-provenance.sh`, `hooks/tests/run-tests.sh`

**Work/verify:** verify deletion absence; preflight/reject an undeletable stale valid marker before target writes; never print `removed` without proof. Inject write/move/delete failures and assert prior preservation, zero residue, zero false-current attribution, and zero target change where rejection is required. Load+record in one isolated subshell; malformed/`exit`/record failure is warning-only and does not abort the core upgrade.

**Module-size/commit:** helper owns marker lifecycle; caller owns orchestration only. One T5 commit; exclude digest-oracle, mutation-harness, denial, docs, and S2 work.

## T6 - Make denial regression tests exact

**ACs:** AC25-AC26 | **Targets:** `hooks/tests/test-command-policy-denial-message.sh`

**Work/verify:** assert the complete expected reason for every deny sample; include an appended-location-prose adversary that must fail; assert the renderer exposes exactly two required parameters. Run the targeted test and full hook suite.

**Commit:** one T6 test-only commit; no `hooks/shared/**`, policy, parser, matcher, or denial-copy edits.

## T7 - Commit independent provenance and mutation proof

**ACs:** AC23-AC24, AC27 | **Blocked by:** T4, T5
**Targets:** `hooks/tests/test-installed-from-provenance.sh`, `hooks/tests/test-installed-from-provenance-mutations.sh` (new committed harness), `hooks/tests/run-tests.sh`

**Work/verify:** replace self-referential digest expectations with a fixed independent oracle and byte-sensitivity/exclusion cases; encode a malformed marker through the live health engine. Reproduce all seven reported mutants from the committed harness, require each targeted test to fail, restore the tree with zero residue, then run the full suite.

**Commit:** one T7 test-evidence commit; no durable production mutation or report-only RED assertion.

## T8 - Correct and cross-link the public provenance contract

**ACs:** AC28 | **Targets:** `docs/install-existing-project.md`, `docs/install-fusebase-cli-project.md`

**Work/verify:** replace the unconditional historical-byte claim with current-tag-target limits pending S3/S5. Add only a pointer from the CLI-project workflow to the canonical `INSTALLED_FROM` owner; check that `byte-identical` is absent from the claim and the pointer resolves.

**Commit:** one T8 docs-only commit; do not duplicate the canonical contract or implement S3/S5.

## Serialization and deferred work

- Serialize edits to `hooks/local/upgrade.sh`, `hooks/tests/test-installed-from-provenance.sh`, and `hooks/tests/run-tests.sh`; T4 precedes T5, and T7 follows both.
- T1/T2 paths under `hooks/local/**`, `hooks/tests/**`, `templates/**`, `docs/**`, and generated root state are not protected by `policies/protected-paths.yml`; do not mint FR-07 authorization for them.
- T4-T8 are required to clear the adversarial SHIP-BLOCKER; the 1024/1024 pre-fix suite is not sufficient evidence.
- No task exists for S3, S4b, or S5. Their roadmap blockers must clear before planning implementation.
