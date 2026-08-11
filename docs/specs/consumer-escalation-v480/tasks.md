# Consumer escalation v4.8.0 - tasks

**Status:** DRAFT | **commit rule:** one task = one commit (FR-03) | **scope:** AC1-AC17

## Task chain

| Order | Task | Slice | State | Blocked by | Commit scope |
|---:|---|---|---|---|---|
| 1 | T1 | S1 / R3-attribution | IMPLEMENTABLE | Plan approval | Typed provenance + public contract + regression |
| 2 | T3 | S4a / R1-message | IMPLEMENTABLE | Plan approval; FR-07 authorization before protected-path commit | Denial rendering + regression only |
| 3 | T2 | S2 / R2 | DESIGN-BLOCKED | Explicit operator lock of C3 receipt schema | Receipt + census + regression only |

## T1 - Implement typed installed-source provenance

**ACs:** AC1-AC9

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

**Target files:**

- `hooks/shared/command_policy.py`
- `hooks/tests/test-command-policy-denial-message.sh` (new, or the existing command-policy test owner if one exists)
- `hooks/tests/run-tests.sh`

**Work:** render the exact AC14 text from existing `rule_id` and `matched_pattern`. Do not add parser/token/span logic, re-match text, change policy patterns, or alter an allow/deny result.

**Verify:** exact-message tests for executable text and quoted prose; invariant tests for decision/rule/pattern/exit behavior; full hook tests.

**Protected path:** `hooks/shared/**` is protected by `policies/protected-paths.yml`; obtain the normal scoped FR-07 authorization for the exact protected edit before commit. No authorization applies to unrelated paths.

**Commit:** one T3 commit; exclude parser/matching/policy changes and unrelated denial copy.

## Serialization and deferred work

- Serialize edits to `hooks/tests/run-tests.sh`; this is not a semantic prerequisite between T1, T2, or T3.
- T1/T2 paths under `hooks/local/**`, `hooks/tests/**`, `templates/**`, `docs/**`, and generated root state are not protected by `policies/protected-paths.yml`; do not mint FR-07 authorization for them.
- No task exists for S3, S4b, or S5. Their roadmap blockers must clear before planning implementation.
